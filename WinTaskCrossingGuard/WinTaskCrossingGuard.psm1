Set-StrictMode -Version Latest


function Get-WtcgObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $DefaultValue
    }

    if ($null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value
}

function Resolve-WtcgDateTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter()]
        [datetime] $AnchorDate = (Get-Date)
    )

    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $culture = [System.Globalization.CultureInfo]::CurrentCulture

    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Value, $culture, $styles, [ref] $parsed)) {
        throw "Could not parse date/time value '$Value'. Try an ISO value like '2026-04-26T22:00:00' or a time like '22:00'."
    }

    if ($Value -match '^\s*\d{1,2}(:\d{2}){0,2}\s*([aApP][mM])?\s*$') {
        return [datetime]::new(
            $AnchorDate.Year,
            $AnchorDate.Month,
            $AnchorDate.Day,
            $parsed.Hour,
            $parsed.Minute,
            $parsed.Second,
            $parsed.Kind
        )
    }

    return $parsed
}

function Resolve-WtcgWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Start,

        [Parameter(Mandatory)]
        [string] $End,

        [Parameter()]
        [datetime] $AnchorDate = (Get-Date)
    )

    $startTime = Resolve-WtcgDateTime -Value $Start -AnchorDate $AnchorDate
    $endTime = Resolve-WtcgDateTime -Value $End -AnchorDate $AnchorDate

    if ($endTime -lt $startTime) {
        $endTime = $endTime.AddDays(1)
    }

    [pscustomobject]@{
        Start = $startTime
        End   = $endTime
    }
}

function Test-WtcgDateTimeInWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $DateTime,

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End
    )

    return ($DateTime -ge $Start -and $DateTime -le $End)
}

function Normalize-WtcgTaskPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $TaskPath
    )

    if ([string]::IsNullOrWhiteSpace($TaskPath)) {
        return '\'
    }

    $normalized = $TaskPath.Trim()

    if (-not $normalized.StartsWith('\')) {
        $normalized = "\$normalized"
    }

    if (-not $normalized.EndsWith('\')) {
        $normalized = "$normalized\"
    }

    return $normalized
}

function New-WtcgFolderSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter()]
        [bool] $Recurse = $false
    )

    [pscustomobject]@{
        TaskPath = Normalize-WtcgTaskPath -TaskPath $TaskPath
        Recurse  = $Recurse
    }
}

function ConvertTo-WtcgFolderSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $InputObject,

        [Parameter()]
        [bool] $DefaultRecurse = $false
    )

    process {
        foreach ($entry in $InputObject) {
            if ($entry -is [string]) {
                New-WtcgFolderSelection -TaskPath $entry -Recurse $DefaultRecurse
                continue
            }

            $path = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'taskPath'
            if ([string]::IsNullOrWhiteSpace([string]$path)) {
                $path = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'path'
            }

            if ([string]::IsNullOrWhiteSpace([string]$path)) {
                throw "Folder selection entries must be strings or objects with taskPath/path."
            }

            $recurseValue = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'recurse' -DefaultValue $DefaultRecurse
            New-WtcgFolderSelection -TaskPath ([string]$path) -Recurse ([bool]$recurseValue)
        }
    }
}

function New-WtcgTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter()]
        [AllowNull()]
        [object] $NextRunTime,

        [Parameter()]
        [AllowNull()]
        [string] $State,

        [Parameter()]
        [AllowNull()]
        [string] $OriginalState,

        [Parameter()]
        [AllowNull()]
        [bool] $WasOriginallyEnabled = $true,

        [Parameter()]
        [AllowNull()]
        [bool] $DisabledBySuite = $false,

        [Parameter()]
        [AllowNull()]
        [object] $DisabledAt,

        [Parameter()]
        [AllowNull()]
        [object] $LastRunTime,

        [Parameter()]
        [AllowNull()]
        [object] $LastTaskResult,

        [Parameter()]
        [AllowNull()]
        [string] $Author,

        [Parameter()]
        [AllowNull()]
        [string] $Description
    )

    $normalizedPath = Normalize-WtcgTaskPath -TaskPath $TaskPath
    $effectiveOriginalState = if ([string]::IsNullOrWhiteSpace($OriginalState)) { $State } else { $OriginalState }
    $effectiveWasOriginallyEnabled = if ([string]::IsNullOrWhiteSpace($effectiveOriginalState)) { $WasOriginallyEnabled } else { $effectiveOriginalState -ne 'Disabled' }

    [pscustomObject]@{
        PSTypeName              = 'WinTaskCrossingGuard.TaskIdentity'
        TaskPath                = $normalizedPath
        TaskName                = $TaskName
        FullName                = "$normalizedPath$TaskName"
        NextRunTime             = $NextRunTime
        State                   = $State
        OriginalState           = $effectiveOriginalState
        WasOriginallyEnabled    = [bool]$effectiveWasOriginallyEnabled
        DisabledBySuite         = [bool]$DisabledBySuite
        DisabledAt              = $DisabledAt
        LastRunTime             = $LastRunTime
        LastTaskResult          = $LastTaskResult
        Author                  = $Author
        Description             = $Description

    }
}

function Import-WtcgTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Task identity JSON not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    $jsonTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'Tasks'
    $items = if ($null -ne $jsonTasks) { @($jsonTasks) } else { @($json) }

    foreach ($item in $items) {
        New-WtcgTaskIdentity `
            -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskPath')) `
            -TaskName ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskName')) `
            -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $item -Name 'NextRunTime') `
            -State (Get-WtcgObjectPropertyValue -InputObject $item -Name 'State') `
            -OriginalState (Get-WtcgObjectPropertyValue -InputObject $item -Name 'OriginalState') `
            -WasOriginallyEnabled ([bool](Get-WtcgObjectPropertyValue -InputObject $item -Name 'WasOriginallyEnabled' -DefaultValue $true)) `
            -DisabledBySuite ([bool](Get-WtcgObjectPropertyValue -InputObject $item -Name 'DisabledBySuite' -DefaultValue $false)) `
            -DisabledAt (Get-WtcgObjectPropertyValue -InputObject $item -Name 'DisabledAt') `
            -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $item -Name 'LastRunTime') `
            -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $item -Name 'LastTaskResult') `
            -Author (Get-WtcgObjectPropertyValue -InputObject $item -Name 'Author') `
            -Description (Get-WtcgObjectPropertyValue -InputObject $item -Name 'Description')
    }
}

function Export-WtcgTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [string] $Kind = 'TaskIdentityList',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($identity in $TaskIdentity) {
            $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $items.Add([pscustomobject]@{
                TaskPath             = $normalizedPath
                TaskName             = [string]$identity.TaskName
                FullName             = "$normalizedPath$($identity.TaskName)"
                NextRunTime          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'NextRunTime'
                State                = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'State'
                OriginalState        = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'OriginalState'
                WasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'WasOriginallyEnabled' -DefaultValue $true)
                DisabledBySuite      = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'DisabledBySuite' -DefaultValue $false)
                DisabledAt           = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'DisabledAt'
                LastRunTime          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastRunTime'
                LastTaskResult       = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastTaskResult'
                Author               = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Author'
                Description          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Description'
            })
        }
    }

    end {
        $payload = [pscustomobject]@{
            Kind          = $Kind
            CreatedAt     = (Get-Date)
            RunId         = $RunId
            RunFolderPath = $RunFolderPath
            Tasks         = $items
        }

        $directory = Split-Path -Parent $Path
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $payload |
            ConvertTo-Json -Depth 8 |
            Set-Content -Path $Path -Encoding utf8 -WhatIf:$false

        Get-Item -Path $Path
    }
}

function Resolve-WtcgRuntimeLockPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $basePath = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = $env:TEMP
    }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = [System.IO.Path]::GetTempPath()
    }

    return (Join-Path $basePath 'WinTaskCrossingGuard\runtime.lock.json')
}

function New-WtcgRuntimeLockName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Name = 'Global\WinTaskCrossingGuard'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'LockName cannot be empty.'
    }

    $trimmed = $Name.Trim()
    if ($trimmed -notmatch '^(Global|Local)\\') {
        return "Global\$trimmed"
    }

    return $trimmed
}

function Save-WtcgRuntimeLockFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $LockName,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Metadata
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    $payload = [pscustomobject]@{
        Kind         = 'WinTaskCrossingGuard.RuntimeLock'
        Version      = 1
        LockName     = $LockName
        HostName     = $env:COMPUTERNAME
        ProcessId    = $PID
        StartedAtUtc = [datetime]::UtcNow.ToString('o')
        UserName     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Metadata     = $Metadata
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Write WinTaskCrossingGuard runtime lock file')) {
        $payload |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $Path -Encoding utf8 -WhatIf:$false
    }

    if (Test-Path -LiteralPath $Path) {
        Get-Item -LiteralPath $Path
    }
}

function Enter-WtcgRuntimeLock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string] $LockName = 'Global\WinTaskCrossingGuard',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $LockPath,

        [Parameter()]
        [int] $TimeoutSeconds = 0,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Metadata,

        [Parameter()]
        [switch] $SkipLockFile
    )

    $normalizedName = New-WtcgRuntimeLockName -Name $LockName
    $mutex = [System.Threading.Mutex]::new($false, $normalizedName)

    try {
        $timeout = if ($TimeoutSeconds -lt 0) {
            [System.Threading.Timeout]::InfiniteTimeSpan
        }
        else {
            [TimeSpan]::FromSeconds($TimeoutSeconds)
        }

        $acquired = $mutex.WaitOne($timeout)
        if (-not $acquired) {
            $message = "Another WinTaskCrossingGuard run is already active on this host using lock '$normalizedName'."
            $resolvedPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
            if ($resolvedPath -and (Test-Path -LiteralPath $resolvedPath)) {
                $message += " Lock file: $resolvedPath"
            }
            throw $message
        }

        $resolvedLockPath = $null
        if (-not $SkipLockFile) {
            $resolvedLockPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
            if (-not [string]::IsNullOrWhiteSpace($resolvedLockPath)) {
                Save-WtcgRuntimeLockFile -Path $resolvedLockPath -LockName $normalizedName -Metadata $Metadata -WhatIf:$WhatIfPreference | Out-Null
            }
        }

        [pscustomobject]@{
            PSTypeName = 'WinTaskCrossingGuard.RuntimeLock'
            LockName   = $normalizedName
            Mutex      = $mutex
            LockPath   = $resolvedLockPath
            Acquired   = $true
        }
    }
    catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-WtcgRuntimeLock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Lock
    )

    if ($null -eq $Lock) {
        return
    }

    try {
        if ((Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Acquired' -DefaultValue $false) -and
            $null -ne (Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Mutex')) {
            $Lock.Mutex.ReleaseMutex()
        }
    }
    finally {
        if ($null -ne (Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Mutex')) {
            $Lock.Mutex.Dispose()
        }

        $lockPath = Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'LockPath'
        if (-not [string]::IsNullOrWhiteSpace([string]$lockPath) -and (Test-Path -LiteralPath $lockPath)) {
            if ($PSCmdlet.ShouldProcess($lockPath, 'Remove WinTaskCrossingGuard runtime lock file')) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }
    }
}



function New-WtcgRunId {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Prefix = 'wtcg'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return "$Prefix-$timestamp-$suffix"
}

function ConvertTo-WtcgSafePathName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $safe = $Value.Trim()
    foreach ($invalidCharacter in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$invalidCharacter, '-')
    }

    $safe = $safe -replace '\s+', '-'
    $safe = $safe -replace '-{2,}', '-'
    $safe = $safe.Trim('-')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw 'RunId cannot resolve to an empty folder name.'
    }

    return $safe
}

function Resolve-WtcgRunRootPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    return (Join-Path $BaseDirectory 'runs')
}

function New-WtcgRunContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunRootPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [datetime] $CreatedAt = (Get-Date)
    )

    $effectiveRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { New-WtcgRunId } else { $RunId.Trim() }
    $safeRunFolderName = ConvertTo-WtcgSafePathName -Value $effectiveRunId

    $effectiveRunFolderPath = if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $RunFolderPath
    }
    else {
        Join-Path (Resolve-WtcgRunRootPath -Path $RunRootPath) $safeRunFolderName
    }

    $logsPath = Join-Path $effectiveRunFolderPath 'logs'
    $jsonlLogsPath = Join-Path $effectiveRunFolderPath 'steamablelogs'
    $manifestsPath = Join-Path $effectiveRunFolderPath 'manifests'
    $identitiesPath = Join-Path $effectiveRunFolderPath 'identities'
    $reportsPath = Join-Path $effectiveRunFolderPath 'reports'
    $errorsPath = Join-Path $effectiveRunFolderPath 'errors'

    foreach ($directory in @($effectiveRunFolderPath, $logsPath, $jsonlLogsPath, $manifestsPath, $identitiesPath, $reportsPath, $errorsPath)) {
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }
    }

    $context = [pscustomobject]@{
        PSTypeName        = 'WinTaskCrossingGuard.RunContext'
        RunId             = $effectiveRunId
        RunFolderPath     = $effectiveRunFolderPath
        LogsPath          = $logsPath
        JsonlLogsPath     = $jsonlLogsPath
        ManifestsPath     = $manifestsPath
        IdentitiesPath    = $identitiesPath
        ReportsPath       = $reportsPath
        ErrorsPath        = $errorsPath
        Operation         = $Operation
        CreatedAt         = $CreatedAt
        CreatedAtUtc      = $CreatedAt.ToUniversalTime().ToString('o')
    }

    $runInfoPath = Join-Path $effectiveRunFolderPath 'run-info.json'
    [pscustomobject]@{
        Kind          = 'WinTaskCrossingGuard.RunInfo'
        Version       = 1
        RunId         = $context.RunId
        RunFolderPath = $context.RunFolderPath
        Operation     = $Operation
        CreatedAt     = $CreatedAt.ToString('o')
        CreatedAtUtc  = $CreatedAt.ToUniversalTime().ToString('o')
        HostName      = $env:COMPUTERNAME
        UserName      = $env:USERNAME
        ProcessId     = $PID
        Folders       = [ordered]@{
            logs           = $context.LogsPath
            steamablelogs  = $context.JsonlLogsPath
            manifests      = $context.ManifestsPath
            identities     = $context.IdentitiesPath
            reports        = $context.ReportsPath
            errors         = $context.ErrorsPath
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $runInfoPath -Encoding utf8 -WhatIf:$false

    $context | Add-Member -NotePropertyName RunInfoPath -NotePropertyValue $runInfoPath -Force
    return $context
}

function Resolve-WtcgRunArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $RunContext,

        [Parameter(Mandatory)]
        [ValidateSet('Logs', 'JsonlLogs', 'Manifests', 'Identities', 'Reports', 'Errors')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FileName
    )

    $folder = switch ($Kind) {
        'Logs'       { $RunContext.LogsPath }
        'JsonlLogs'  { $RunContext.JsonlLogsPath }
        'Manifests'  { $RunContext.ManifestsPath }
        'Identities' { $RunContext.IdentitiesPath }
        'Reports'    { $RunContext.ReportsPath }
        'Errors'     { $RunContext.ErrorsPath }
    }

    if ([string]::IsNullOrWhiteSpace([string]$folder)) {
        throw "Run context does not contain a folder for artifact kind '$Kind'."
    }

    New-Item -ItemType Directory -Path $folder -Force -WhatIf:$false | Out-Null
    return (Join-Path $folder $FileName)
}

function Test-WtcgRestoreArtifactTaskRestorable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task
    )

    $propertyNames = @($Task.PSObject.Properties.Name)
    $wasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $Task -Name 'WasOriginallyEnabled' -DefaultValue $true)
    $disabledBySuite = if ($propertyNames -contains 'DisabledBySuite') {
        [bool](Get-WtcgObjectPropertyValue -InputObject $Task -Name 'DisabledBySuite' -DefaultValue $true)
    }
    else {
        $true
    }

    return ($wasOriginallyEnabled -and $disabledBySuite)
}

function Get-WtcgRestoreArtifactSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $nameLooksRestorable = $file.Name -match '(?i)(manifest|identit)'

    try {
        $payload = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "Skipping non-JSON or unreadable restore artifact candidate '$($file.FullName)': $($_.Exception.Message)"
        return $null
    }

    $kind = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Kind')
    $kindLooksRestorable = $kind -match '(?i)(manifest|identity)'

    if (-not ($nameLooksRestorable -or $kindLooksRestorable)) {
        return $null
    }

    $tasks = Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Tasks'
    if ($null -eq $tasks) {
        return $null
    }

    $taskArray = @($tasks)
    if ($taskArray.Count -eq 0) {
        return $null
    }

    $restorableTaskCount = 0
    foreach ($task in $taskArray) {
        if ($null -ne $task -and (Test-WtcgRestoreArtifactTaskRestorable -Task $task)) {
            $restorableTaskCount++
        }
    }

    $createdAt = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $payload -Name 'CreatedAt')
    $runFolderPath = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'RunFolderPath')
    if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
        $parent = Split-Path -Parent $file.FullName
        if (-not [string]::IsNullOrWhiteSpace($parent) -and @('manifests', 'identities') -contains (Split-Path -Leaf $parent)) {
            $runFolderPath = Split-Path -Parent $parent
        }
    }

    $runId = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'RunId')
    if ([string]::IsNullOrWhiteSpace($runId) -and -not [string]::IsNullOrWhiteSpace($runFolderPath)) {
        $runId = Split-Path -Leaf $runFolderPath
    }

    [pscustomobject]@{
        PSTypeName          = 'WinTaskCrossingGuard.RestoreArtifactSummary'
        Path                = $file.FullName
        Name                = $file.Name
        Kind                = $kind
        CreatedAt           = $createdAt
        LastWriteTime       = $file.LastWriteTime
        LastWriteTimeUtc    = $file.LastWriteTimeUtc
        RunId               = $runId
        RunFolderPath       = $runFolderPath
        TaskCount           = $taskArray.Count
        RestorableTaskCount = $restorableTaskCount
    }
}

function Find-WtcgLatestRestoreArtifact {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SearchPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunRootPath,

        [Parameter()]
        [switch] $IncludeEmptyRestoreSets
    )

    $effectiveSearchPath = if (-not [string]::IsNullOrWhiteSpace($SearchPath)) {
        $SearchPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($RunRootPath)) {
        $RunRootPath
    }
    else {
        Resolve-WtcgRunRootPath
    }

    if ([string]::IsNullOrWhiteSpace($effectiveSearchPath) -or -not (Test-Path -LiteralPath $effectiveSearchPath -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $effectiveSearchPath -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)(manifest|identit)' } |
        ForEach-Object { Get-WtcgRestoreArtifactSummary -Path $_.FullName } |
        Where-Object { $null -ne $_ } |
        Sort-Object -Property LastWriteTimeUtc, CreatedAt, Path -Descending |
        Select-Object -First 1
}

function Import-WtcgRestoreArtifactTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Restore artifact not found: $Path"
    }

    $payload = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $tasks = Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Tasks'
    if ($null -eq $tasks) {
        throw "Restore artifact has no Tasks array: $Path"
    }

    foreach ($task in @($tasks)) {
        if ($null -eq $task) {
            continue
        }

        if (-not (Test-WtcgRestoreArtifactTaskRestorable -Task $task)) {
            Write-Verbose "Skipping '$([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskPath'))$([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskName'))' because it was not marked as disabled by this suite run."
            continue
        }

        New-WtcgTaskIdentity `
            -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskPath')) `
            -TaskName ([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskName')) `
            -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $task -Name 'NextRunTime') `
            -State (Get-WtcgObjectPropertyValue -InputObject $task -Name 'State') `
            -OriginalState (Get-WtcgObjectPropertyValue -InputObject $task -Name 'OriginalState') `
            -WasOriginallyEnabled $true `
            -DisabledBySuite $true `
            -DisabledAt (Get-WtcgObjectPropertyValue -InputObject $task -Name 'DisabledAt') `
            -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $task -Name 'LastRunTime') `
            -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $task -Name 'LastTaskResult') `
            -Author (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Author') `
            -Description (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Description')
    }
}

function Save-WtcgRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $RunContext,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [object] $Details
    )

    $resolvedPath = if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $Path
    }
    else {
        $safeOperationName = ConvertTo-WtcgSafePathName -Value $Operation.ToLowerInvariant()
        Resolve-WtcgRunArtifactPath -RunContext $RunContext -Kind 'Reports' -FileName "$safeOperationName-report.json"
    }

    $directory = Split-Path -Parent $resolvedPath
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    [pscustomobject]@{
        Kind          = 'WinTaskCrossingGuard.RunReport'
        Version       = 1
        RunId         = $RunContext.RunId
        RunFolderPath = $RunContext.RunFolderPath
        Operation     = $Operation
        Status        = $Status
        CreatedAt     = (Get-Date).ToString('o')
        Details       = if ($null -ne $Details) { $Details } else { [ordered]@{} }
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedPath -Encoding utf8 -WhatIf:$false

    Get-Item -LiteralPath $resolvedPath
}

function ConvertTo-WtcgNullableDateTime {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $dateTime = [datetime]$Value
        if ($dateTime -eq [datetime]::MinValue) {
            return $null
        }

        return $dateTime
    }
    catch {
        return $null
    }
}

function Test-WtcgDateTimeRangeOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $FirstStart,

        [Parameter(Mandatory)]
        [datetime] $FirstEnd,

        [Parameter(Mandatory)]
        [datetime] $SecondStart,

        [Parameter(Mandatory)]
        [datetime] $SecondEnd
    )

    if ($FirstEnd -lt $FirstStart) {
        throw 'FirstEnd cannot be earlier than FirstStart.'
    }

    if ($SecondEnd -lt $SecondStart) {
        throw 'SecondEnd cannot be earlier than SecondStart.'
    }

    return ($FirstStart -lt $SecondEnd -and $SecondStart -lt $FirstEnd)
}

function Get-WtcgScheduledTaskActionArgumentText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object] $Task
    )

    process {
        if ($null -eq $Task) {
            return
        }

        $actions = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'Actions'
        if ($null -eq $actions) {
            return
        }

        foreach ($action in @($actions)) {
            if ($null -eq $action) {
                continue
            }

            $argumentText = Get-WtcgObjectPropertyValue -InputObject $action -Name 'Arguments'
            if ([string]::IsNullOrWhiteSpace([string]$argumentText)) {
                $argumentText = Get-WtcgObjectPropertyValue -InputObject $action -Name 'Argument'
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$argumentText)) {
                [string]$argumentText
            }
        }
    }
}

function Get-WtcgCommandArgumentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Arguments,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Argument name cannot be empty.'
    }

    $escapedName = [regex]::Escape($Name.TrimStart('-'))
    $pattern = "(?i)(?:^|\s)-$escapedName(?:\s+|:)(?:`"(?<dq>[^`"]*)`"|'(?<sq>[^']*)'|(?<bare>\S+))"
    $match = [regex]::Match($Arguments, $pattern)

    if (-not $match.Success) {
        return $null
    }

    foreach ($groupName in @('dq', 'sq', 'bare')) {
        $group = $match.Groups[$groupName]
        if ($null -ne $group -and $group.Success) {
            return $group.Value
        }
    }

    return $null
}

function Import-WtcgReenableManifestSummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $summary = [ordered]@{
        ManifestPath    = $Path
        ManifestExists  = $false
        ManifestKind    = $null
        RunId           = $null
        RunFolderPath   = $null
        CreatedAt       = $null
        WindowStart     = $null
        WindowEnd       = $null
        TaskFullNames   = @()
        ReadError       = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$summary
    }

    $summary.ManifestExists = $true

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $summary.ManifestKind = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'Kind'
        $summary.RunId = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'RunId'
        $summary.RunFolderPath = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'RunFolderPath'
        $summary.CreatedAt = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'CreatedAt')
        $summary.WindowStart = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'WindowStart')
        $summary.WindowEnd = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'WindowEnd')

        $tasks = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'Tasks'
        $taskFullNames = [System.Collections.Generic.List[string]]::new()
        foreach ($task in @($tasks)) {
            $taskFullName = Get-WtcgObjectPropertyValue -InputObject $task -Name 'FullName'
            if (-not [string]::IsNullOrWhiteSpace([string]$taskFullName)) {
                $taskFullNames.Add([string]$taskFullName)
            }
        }
        $summary.TaskFullNames = @($taskFullNames)
    }
    catch {
        $summary.ReadError = $_.Exception.Message
    }

    [pscustomobject]$summary
}

function Get-WtcgScheduledReenableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [string] $ExpectedTaskPath,

        [Parameter(Mandatory)]
        [string] $ExpectedTaskName,

        [Parameter()]
        [datetime] $Now = (Get-Date)
    )

    $normalizedExpectedTaskPath = Normalize-WtcgTaskPath -TaskPath $ExpectedTaskPath
    $taskPath = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'TaskPath' -DefaultValue $normalizedExpectedTaskPath
    $taskName = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'TaskName' -DefaultValue $ExpectedTaskName

    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        return $null
    }

    $normalizedTaskPath = Normalize-WtcgTaskPath -TaskPath ([string]$taskPath)
    $taskFullName = "$normalizedTaskPath$taskName"
    $expectedTaskFullName = "$normalizedExpectedTaskPath$ExpectedTaskName"
    $isExactConfiguredTask = ($normalizedTaskPath -ieq $normalizedExpectedTaskPath -and [string]$taskName -ieq $ExpectedTaskName)

    $argumentText = @(Get-WtcgScheduledTaskActionArgumentText -Task $Task)
    $manifestPath = $null
    $jsonlLogPath = $null
    $runId = $null
    $runFolderPath = $null
    foreach ($arguments in $argumentText) {
        if ([string]::IsNullOrWhiteSpace($manifestPath)) {
            $manifestPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'ManifestPath'
        }
        if ([string]::IsNullOrWhiteSpace($jsonlLogPath)) {
            $jsonlLogPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'JsonlLogPath'
        }
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'RunId'
        }
        if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
            $runFolderPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'RunFolderPath'
        }
    }

    $description = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'Description'
    $isWinTaskCrossingGuardTask = (
        $isExactConfiguredTask -or
        -not [string]::IsNullOrWhiteSpace([string]$manifestPath) -or
        ([string]$description -match 'WinTaskCrossingGuard')
    )

    if (-not $isWinTaskCrossingGuardTask) {
        return $null
    }

    $taskInfo = $null
    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskPath $normalizedTaskPath -TaskName ([string]$taskName) -ErrorAction Stop
    }
    catch {
        $taskInfo = $null
    }

    $nextRunTime = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $taskInfo -Name 'NextRunTime')
    $manifestSummary = Import-WtcgReenableManifestSummary -Path $manifestPath
    $manifestWindowStart = $null
    $manifestWindowEnd = $null
    $manifestTaskFullNames = @()
    if ($null -ne $manifestSummary) {
        $manifestWindowStart = $manifestSummary.WindowStart
        $manifestWindowEnd = $manifestSummary.WindowEnd
        $manifestTaskFullNames = @($manifestSummary.TaskFullNames)
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = $manifestSummary.RunId
        }
        if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
            $runFolderPath = $manifestSummary.RunFolderPath
        }
    }

    [pscustomobject]@{
        PSTypeName              = 'WinTaskCrossingGuard.ScheduledReenableRun'
        TaskPath                = $normalizedTaskPath
        TaskName                = [string]$taskName
        TaskFullName            = $taskFullName
        ExpectedTaskFullName    = $expectedTaskFullName
        IsExactConfiguredTask   = $isExactConfiguredTask
        NextRunTime             = $nextRunTime
        IsActive                = ($null -ne $nextRunTime -and $nextRunTime -gt $Now)
        ManifestPath            = $manifestPath
        JsonlLogPath            = $jsonlLogPath
        RunId                   = $runId
        RunFolderPath           = $runFolderPath
        WindowStart             = $manifestWindowStart
        WindowEnd               = $manifestWindowEnd
        TaskFullNames           = $manifestTaskFullNames
        ManifestSummary         = $manifestSummary
    }
}

function Get-WtcgActivePriorReenableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter(Mandatory)]
        [datetime] $ReenableAt,

        [Parameter(Mandatory)]
        [string] $ReenableTaskPath,

        [Parameter(Mandatory)]
        [string] $ReenableTaskName,

        [Parameter()]
        [datetime] $Now = (Get-Date)
    )

    $normalizedReenableTaskPath = Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath
    $candidateTasks = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    $addCandidate = {
        param([object] $Candidate)

        foreach ($item in @($Candidate)) {
            if ($null -eq $item) {
                continue
            }

            $candidateTaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskPath' -DefaultValue $normalizedReenableTaskPath))
            $candidateTaskName = [string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskName' -DefaultValue '')
            if ([string]::IsNullOrWhiteSpace($candidateTaskName)) {
                continue
            }

            $key = "$candidateTaskPath|$candidateTaskName".ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $candidateTasks.Add($item)
            }
        }
    }

    try {
        & $addCandidate (Get-ScheduledTask -TaskPath $normalizedReenableTaskPath -TaskName $ReenableTaskName -ErrorAction SilentlyContinue)
    }
    catch { }

    try {
        & $addCandidate (Get-ScheduledTask -TaskPath $normalizedReenableTaskPath -ErrorAction SilentlyContinue)
    }
    catch { }

    $newActiveStart = $WindowStart
    $newActiveEnd = $ReenableAt
    if ($newActiveEnd -lt $newActiveStart) {
        $newActiveEnd = $WindowEnd
    }
    if ($newActiveEnd -lt $newActiveStart) {
        $newActiveEnd = $newActiveStart
    }

    foreach ($candidateTask in @($candidateTasks)) {
        $run = Get-WtcgScheduledReenableRun `
            -Task $candidateTask `
            -ExpectedTaskPath $normalizedReenableTaskPath `
            -ExpectedTaskName $ReenableTaskName `
            -Now $Now

        if ($null -eq $run -or -not $run.IsActive) {
            continue
        }

        if ($null -ne $run.NextRunTime -and $run.NextRunTime -le $WindowStart) {
            continue
        }

        $blocksRequestedRun = $false
        $reason = $null

        if ($run.IsExactConfiguredTask) {
            $blocksRequestedRun = $true
            $reason = 'configured re-enable task is already scheduled'
        }
        elseif ($null -eq $run.WindowStart -or $null -eq $run.NextRunTime) {
            $blocksRequestedRun = $true
            $reason = 'active WinTaskCrossingGuard re-enable task has insufficient manifest timing metadata'
        }
        else {
            $priorActiveStart = $run.WindowStart
            $priorActiveEnd = $run.NextRunTime
            if ($priorActiveEnd -lt $priorActiveStart) {
                $priorActiveEnd = $run.WindowEnd
            }
            if ($priorActiveEnd -lt $priorActiveStart) {
                $priorActiveEnd = $priorActiveStart
            }

            if (Test-WtcgDateTimeRangeOverlap `
                    -FirstStart $priorActiveStart `
                    -FirstEnd $priorActiveEnd `
                    -SecondStart $newActiveStart `
                    -SecondEnd $newActiveEnd) {
                $blocksRequestedRun = $true
                $reason = 'active re-enable window overlaps requested disable-to-reenable interval'
            }
        }

        if ($blocksRequestedRun) {
            $run | Add-Member -NotePropertyName OverlapReason -NotePropertyValue $reason -Force
            return $run
        }
    }

    return $null
}

function Assert-WtcgNoOverlappingScheduledReenableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter(Mandatory)]
        [datetime] $ReenableAt,

        [Parameter(Mandatory)]
        [string] $ReenableTaskPath,

        [Parameter(Mandatory)]
        [string] $ReenableTaskName
    )

    $activePriorRun = Get-WtcgActivePriorReenableRun `
        -WindowStart $WindowStart `
        -WindowEnd $WindowEnd `
        -ReenableAt $ReenableAt `
        -ReenableTaskPath $ReenableTaskPath `
        -ReenableTaskName $ReenableTaskName

    if ($null -eq $activePriorRun) {
        return
    }

    $details = [System.Collections.Generic.List[string]]::new()
    $details.Add("task '$($activePriorRun.TaskFullName)'")
    if ($null -ne $activePriorRun.NextRunTime) {
        $details.Add("next re-enable '$($activePriorRun.NextRunTime.ToString('o'))'")
    }
    if ($null -ne $activePriorRun.WindowStart) {
        $details.Add("prior window start '$($activePriorRun.WindowStart.ToString('o'))'")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$activePriorRun.ManifestPath)) {
        $details.Add("manifest '$($activePriorRun.ManifestPath)'")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$activePriorRun.OverlapReason)) {
        $details.Add("reason '$($activePriorRun.OverlapReason)'")
    }

    throw "Active prior WinTaskCrossingGuard re-enable run detected: $($details -join '; '). Refusing to schedule a new re-enable task because it could overwrite or prematurely re-enable another run."
}

function Import-WtcgTaskSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Task selection JSON not found: $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read task selection JSON '$Path': $($_.Exception.Message)"
    }

    $defaultIncludeFolderRecurse = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'defaultIncludeFolderRecurse' -DefaultValue $false)
    $defaultExcludeFolderRecurse = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'defaultExcludeFolderRecurse' -DefaultValue $false)

    $includeFolders = @()
    $excludeFolders = @()
    $includeTasks = @()
    $excludeTasks = @()
    $protectedFolders = @()
    $protectedTasks = @()
    $safetyAllowListMode = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'safetyAllowListMode' -DefaultValue $false)
    $useDefaultProtectedTaskList = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'useDefaultProtectedTaskList' -DefaultValue $true)

    $jsonIncludeFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'includeFolders'
    if ($null -ne $jsonIncludeFolders) {
        $includeFolders = @(
            $jsonIncludeFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $defaultIncludeFolderRecurse
        )
    }

    $jsonExcludeFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'excludeFolders'
    if ($null -ne $jsonExcludeFolders) {
        $excludeFolders = @(
            $jsonExcludeFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $defaultExcludeFolderRecurse
        )
    }

    $jsonProtectedFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'protectedFolders'
    if ($null -ne $jsonProtectedFolders) {
        $protectedFolders = @(
            $jsonProtectedFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $true
        )
    }

    $jsonProtectedTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'protectedTasks'
    if ($null -ne $jsonProtectedTasks) {
        $protectedTasks = @($jsonProtectedTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    $jsonIncludeTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'includeTasks'
    if ($null -ne $jsonIncludeTasks) {
        $includeTasks = @($jsonIncludeTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    $jsonExcludeTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'excludeTasks'
    if ($null -ne $jsonExcludeTasks) {
        $excludeTasks = @($jsonExcludeTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    foreach ($entry in $includeTasks + $excludeTasks) {
        if ([string]::IsNullOrWhiteSpace($entry.TaskName)) {
            throw "Every includeTasks/excludeTasks entry must have a non-empty taskName."
        }
    }

    foreach ($entry in $protectedTasks) {
        if ([string]::IsNullOrWhiteSpace($entry.TaskName)) {
            throw "Every protectedTasks entry must have a non-empty taskName."
        }
    }

    [pscustomobject]@{
        IncludeFolders              = $includeFolders
        ExcludeFolders              = $excludeFolders
        IncludeTasks                = $includeTasks
        ExcludeTasks                = $excludeTasks
        ProtectedFolders            = $protectedFolders
        ProtectedTasks              = $protectedTasks
        SafetyAllowListMode         = $safetyAllowListMode
        UseDefaultProtectedTaskList = $useDefaultProtectedTaskList
        SourcePath                  = (Resolve-Path -LiteralPath $Path).Path
        Mail                        = ConvertTo-WtcgMailEventSettings -Mail (Get-WtcgObjectPropertyValue -InputObject $json -Name 'mail')
    }
}


function Test-WtcgTaskSpecMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [object[]] $TaskSpec
    )

    foreach ($spec in $TaskSpec) {
        if ($Task.TaskPath -eq $spec.TaskPath -and $Task.TaskName -like $spec.TaskName) {
            return $true
        }
    }

    return $false
}

function Test-WtcgTaskFolderSelectionMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [object[]] $FolderSelection
    )

    foreach ($folder in $FolderSelection) {
        $folderPath = Normalize-WtcgTaskPath -TaskPath ([string]$folder.TaskPath)

        if ([bool]$folder.Recurse) {
            if ($Task.TaskPath -like "$folderPath*") {
                return $true
            }
        }
        else {
            if ($Task.TaskPath -eq $folderPath) {
                return $true
            }
        }
    }

    return $false
}


function Get-WtcgDefaultProtectedFolderSelection {
    [CmdletBinding()]
    param()

    @(
        '\WinTaskCrossingGuard\'
        '\Microsoft\Windows\TaskScheduler\'
        '\Microsoft\Windows\UpdateOrchestrator\'
        '\Microsoft\Windows\WindowsUpdate\'
        '\Microsoft\Windows\WaaSMedic\'
        '\Microsoft\Windows\Servicing\'
        '\Microsoft\Windows\Windows Defender\'
        '\Microsoft\Windows\BitLocker\'
        '\Microsoft\Windows\CertificateServicesClient\'
        '\Microsoft\Windows\RecoveryEnvironment\'
        '\Microsoft\Windows\Registry\'
        '\Microsoft\Windows\Time Synchronization\'
    ) | ForEach-Object {
        New-WtcgFolderSelection -TaskPath $_ -Recurse $true
    }
}

function Test-WtcgSelectionHasExplicitIncludes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return $false
    }

    $includeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeFolders' -DefaultValue @())
    $includeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeTasks' -DefaultValue @())

    return ($includeFolders.Count -gt 0 -or $includeTasks.Count -gt 0)
}

function Assert-WtcgSafetyAllowListSatisfied {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return
    }

    $safetyAllowListMode = [bool](Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'SafetyAllowListMode' -DefaultValue $false)

    if (-not $safetyAllowListMode) {
        return
    }

    if (-not (Test-WtcgSelectionHasExplicitIncludes -Selection $Selection)) {
        throw "Safety allow-list mode is enabled, but no includeFolders or includeTasks entries were provided. Refusing to scan or disable tasks."
    }
}

function Test-WtcgTaskProtected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    $protectedFolders = @(Get-WtcgDefaultProtectedFolderSelection)
    $protectedTasks = @()

    if ($null -ne $Selection) {
        $useDefaultProtectedTaskList = [bool](Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'UseDefaultProtectedTaskList' -DefaultValue $true)

        if (-not $useDefaultProtectedTaskList) {
            $protectedFolders = @()
        }

        $selectionProtectedFolders = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ProtectedFolders'
        if ($null -ne $selectionProtectedFolders) {
            $protectedFolders += @($selectionProtectedFolders)
        }

        $selectionProtectedTasks = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ProtectedTasks'
        if ($null -ne $selectionProtectedTasks) {
            $protectedTasks += @($selectionProtectedTasks)
        }
    }

    if ($protectedFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $protectedFolders)) {
        return $true
    }

    if ($protectedTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $protectedTasks)) {
        return $true
    }

    return $false
}

function Test-WtcgTaskAllowedBySelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if (Test-WtcgTaskProtected -Task $Task -Selection $Selection) {
        return $false
    }

    if ($null -eq $Selection) {
        return $true
    }

    $excludeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ExcludeFolders' -DefaultValue @())
    $excludeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ExcludeTasks' -DefaultValue @())
    $includeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeFolders' -DefaultValue @())
    $includeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeTasks' -DefaultValue @())

    if ($excludeFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $excludeFolders)) {
        return $false
    }

    if ($excludeTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $excludeTasks)) {
        return $false
    }

    $hasIncludes = ($includeFolders.Count -gt 0 -or $includeTasks.Count -gt 0)

    if (-not $hasIncludes) {
        return $true
    }

    if ($includeFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $includeFolders)) {
        return $true
    }

    if ($includeTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $includeTasks)) {
        return $true
    }

    return $false
}

function Get-WtcgScheduledTaskCandidate {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]] $TaskPath = '\',

        [Parameter()]
        [string[]] $TaskName = '*',

        [Parameter()]
        [switch] $Recurse,

        [Parameter()]
        [switch] $IncludeDisabled,

        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    Assert-WtcgSafetyAllowListSatisfied -Selection $Selection

    Import-Module ScheduledTasks -ErrorAction Stop

    $allTasks = [System.Collections.Generic.List[object]]::new()

    foreach ($path in @($TaskPath | ForEach-Object { Normalize-WtcgTaskPath -TaskPath $_ })) {
        if ($Recurse) {
            Get-ScheduledTask -ErrorAction Stop |
                Where-Object { $_.TaskPath -like "$path*" } |
                ForEach-Object { $allTasks.Add($_) }
        }
        else {
            Get-ScheduledTask -TaskPath $path -ErrorAction Stop |
                ForEach-Object { $allTasks.Add($_) }
        }
    }

    if ($null -ne $Selection -and $Selection.IncludeFolders.Count -gt 0) {
        foreach ($folder in $Selection.IncludeFolders) {
            $folderPath = Normalize-WtcgTaskPath -TaskPath ([string]$folder.TaskPath)

            if ([bool]$folder.Recurse) {
                Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { $_.TaskPath -like "$folderPath*" } |
                    ForEach-Object { $allTasks.Add($_) }
            }
            else {
                Get-ScheduledTask -TaskPath $folderPath -ErrorAction SilentlyContinue |
                    ForEach-Object { $allTasks.Add($_) }
            }
        }
    }

    if ($null -ne $Selection -and $Selection.IncludeTasks.Count -gt 0) {
        foreach ($spec in $Selection.IncludeTasks) {
            Get-ScheduledTask -TaskPath $spec.TaskPath -TaskName $spec.TaskName -ErrorAction SilentlyContinue |
                ForEach-Object { $allTasks.Add($_) }
        }
    }

    $allTasks |
        Where-Object {
            $task = $_

            $nameMatches = foreach ($pattern in $TaskName) {
                if ($task.TaskName -like $pattern) { $true; break }
            }

            $nameMatches -and
            ($IncludeDisabled -or $task.State -ne 'Disabled') -and
            (Test-WtcgTaskAllowedBySelection -Task $task -Selection $Selection)
        } |
        Sort-Object TaskPath, TaskName -Unique
}

function Find-WtcgTaskInWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [Parameter()]
        [string[]] $TaskPath = '\',

        [Parameter()]
        [string[]] $TaskName = '*',

        [Parameter()]
        [switch] $Recurse,

        [Parameter()]
        [switch] $IncludeDisabled,

        [Parameter()]
        [AllowNull()]
        [object] $Selection,

        [Parameter()]
        [switch] $IdentityOnly
    )

    $tasks = Get-WtcgScheduledTaskCandidate `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Recurse:$Recurse `
        -IncludeDisabled:$IncludeDisabled `
        -Selection $Selection

    foreach ($task in $tasks) {
        $info = $null
        try {
            $info = Get-ScheduledTaskInfo -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not read task info for '$($task.TaskPath)$($task.TaskName)': $($_.Exception.Message)"
            continue
        }

        if ($null -eq $info.NextRunTime -or $info.NextRunTime -eq [datetime]::MinValue) {
            continue
        }

        if (Test-WtcgDateTimeInWindow -DateTime $info.NextRunTime -Start $Start -End $End) {
            if ($IdentityOnly) {
                New-WtcgTaskIdentity `
                    -TaskPath $task.TaskPath `
                    -TaskName $task.TaskName `
                    -NextRunTime $info.NextRunTime `
                    -State ([string]$task.State) `
                    -OriginalState ([string]$task.State) `
                    -WasOriginallyEnabled ([string]$task.State -ne 'Disabled') `
                    -LastRunTime $info.LastRunTime `
                    -LastTaskResult $info.LastTaskResult `
                    -Author (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Author') `
                    -Description (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Description')
            }
            else {
                [pscustomobject]@{
                    TaskPath             = $task.TaskPath
                    TaskName             = $task.TaskName
                    FullName             = "$($task.TaskPath)$($task.TaskName)"
                    State                = $task.State
                    OriginalState        = [string]$task.State
                    WasOriginallyEnabled = ([string]$task.State -ne 'Disabled')
                    DisabledBySuite      = $false
                    DisabledAt           = $null
                    NextRunTime          = $info.NextRunTime
                    LastRunTime          = $info.LastRunTime
                    LastTaskResult       = $info.LastTaskResult
                    Author               = $task.Author
                    Description          = $task.Description
                }
            }
        }
    }
}

function Disable-WtcgTaskIdentity {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity
    )

    begin {
        Import-Module ScheduledTasks -ErrorAction Stop
    }

    process {
        foreach ($identity in $TaskIdentity) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $taskName = [string]$identity.TaskName
            $fullName = "$taskPath$taskName"

            $wasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'WasOriginallyEnabled' -DefaultValue $true)
            if (-not $wasOriginallyEnabled) {
                Write-Verbose "Skipping originally disabled task: $fullName"
                continue
            }

            if ($PSCmdlet.ShouldProcess($fullName, 'Disable scheduled task')) {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                New-WtcgTaskIdentity `
                    -TaskPath $taskPath `
                    -TaskName $taskName `
                    -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'NextRunTime') `
                    -State (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'State') `
                    -OriginalState (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'OriginalState') `
                    -WasOriginallyEnabled $true `
                    -DisabledBySuite $true `
                    -DisabledAt (Get-Date) `
                    -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastRunTime') `
                    -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastTaskResult' -DefaultValue 0) `
                    -Author (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Author') `
                    -Description (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Description')
            }
        }
    }
}

function Enable-WtcgTaskIdentity {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity
    )

    begin {
        Import-Module ScheduledTasks -ErrorAction Stop
    }

    process {
        foreach ($identity in $TaskIdentity) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $taskName = [string]$identity.TaskName
            $fullName = "$taskPath$taskName"

            if ($PSCmdlet.ShouldProcess($fullName, 'Enable scheduled task')) {
                Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                New-WtcgTaskIdentity -TaskPath $taskPath -TaskName $taskName
            }
        }
    }
}

function Start-WtcgTaskIdentity {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity
    )

    begin {
        Import-Module ScheduledTasks -ErrorAction Stop
    }

    process {
        foreach ($identity in $TaskIdentity) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $taskName = [string]$identity.TaskName
            $fullName = "$taskPath$taskName"

            if ($PSCmdlet.ShouldProcess($fullName, 'Start scheduled task immediately')) {
                Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                New-WtcgTaskIdentity -TaskPath $taskPath -TaskName $taskName
            }
        }
    }
}

function Save-WtcgManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject[]] $Task,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter()]
        [AllowNull()]
        [object] $Selection,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Task) {
            $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string]$entry.TaskPath)
            $items.Add([pscustomobject]@{
                TaskPath             = $normalizedPath
                TaskName             = [string]$entry.TaskName
                FullName             = "$normalizedPath$($entry.TaskName)"
                State                = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                OriginalState        = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'OriginalState' -DefaultValue (Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State')
                WasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'WasOriginallyEnabled' -DefaultValue $true)
                DisabledBySuite      = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledBySuite' -DefaultValue $false)
                DisabledAt           = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledAt'
                NextRunTime          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
                LastRunTime          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'LastRunTime'
                LastTaskResult       = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'LastTaskResult'
                Author               = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'Author'
                Description          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'Description'
            })
        }
    }

    end {
        $manifest = [pscustomobject]@{
            Kind             = 'WinTaskCrossingGuard.RollbackManifest'
            ManifestVersion  = 1
            CreatedAt        = (Get-Date)
            RunId            = $RunId
            RunFolderPath    = $RunFolderPath
            WindowStart      = $WindowStart
            WindowEnd        = $WindowEnd
            SelectionSource  = if ($null -ne $Selection) { $Selection.SourcePath } else { $null }
            Tasks            = $items
        }

        $directory = Split-Path -Parent $Path
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $manifest |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $Path -Encoding utf8 -WhatIf:$false

        Get-Item -Path $Path
    }
}





function Import-WtcgDotEnv {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
    )

    $values = @{}

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $lineNumber++
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed.StartsWith('#')) {
            continue
        }

        $separatorIndex = $trimmed.IndexOf('=')
        if ($separatorIndex -lt 0) {
            throw "Invalid .env line $lineNumber in '$Path'. Expected KEY=VALUE."
        }

        $key = $trimmed.Substring(0, $separatorIndex).Trim()
        $value = $trimmed.Substring($separatorIndex + 1).Trim()

        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "Invalid .env line $lineNumber in '$Path'. Key cannot be empty."
        }

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$key] = $value
    }

    return $values
}

function Get-WtcgLogRetentionDays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
    )

    $envValues = Import-WtcgDotEnv -Path $EnvPath

    if (-not $envValues.ContainsKey('LOG_RETENTION')) {
        return $null
    }

    $rawValue = [string]$envValues['LOG_RETENTION']
    $days = 0

    if (-not [int]::TryParse($rawValue, [ref]$days)) {
        throw "Invalid LOG_RETENTION value '$rawValue' in '$EnvPath'. Expected a whole number of days."
    }

    if ($days -lt 0) {
        throw "Invalid LOG_RETENTION value '$rawValue' in '$EnvPath'. Value must be zero or greater."
    }

    return $days
}

function Clear-WtcgOldLogs {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),

        [Parameter()]
        [string] $LogsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'logs'),

        [Parameter()]
        [datetime] $Now = (Get-Date),

        [Parameter()]
        [string[]] $Filter = @('*.xml'),

        [Parameter()]
        [switch] $PassThru
    )

    $retentionDays = Get-WtcgLogRetentionDays -EnvPath $EnvPath

    if ($null -eq $retentionDays) {
        Write-Verbose "LOG_RETENTION is not configured. Skipping log cleanup."
        return
    }

    if (-not (Test-Path -LiteralPath $LogsPath)) {
        Write-Verbose "Logs folder does not exist. Skipping log cleanup: $LogsPath"
        return
    }

    $cutoff = $Now.AddDays(-1 * $retentionDays)

    $oldLogs = @(
        foreach ($filterItem in @($Filter)) {
            if ([string]::IsNullOrWhiteSpace($filterItem)) {
                continue
            }

            Get-ChildItem -LiteralPath $LogsPath -File -Filter $filterItem -ErrorAction Stop |
                Where-Object { $_.LastWriteTime -lt $cutoff }
        }
    ) | Sort-Object -Property FullName -Unique

    foreach ($logFile in $oldLogs) {
        if ($PSCmdlet.ShouldProcess($logFile.FullName, "Delete log file older than LOG_RETENTION=$retentionDays day(s)")) {
            Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop

            if ($PassThru) {
                [pscustomobject]@{
                    DeletedLogPath = $logFile.FullName
                    LastWriteTime  = $logFile.LastWriteTime
                    Cutoff         = $cutoff
                    RetentionDays  = $retentionDays
                }
            }
        }
    }
}

function Resolve-WtcgXmlLogPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot),

        [Parameter()]
        [string] $Prefix = 'disabled-tasks'
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $BaseDirectory (Join-Path 'logs' "$Prefix-$timestamp.xml")
}


function Test-WtcgWindowsPlatform {
    [CmdletBinding()]
    param()

    if ($null -ne $PSVersionTable -and $PSVersionTable.ContainsKey('Platform')) {
        return ([string]$PSVersionTable.Platform -eq 'Win32NT')
    }

    return ([string]$env:OS -eq 'Windows_NT')
}

function Initialize-WtcgWindowsEventLogSource {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Source = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $LogName = 'Application',

        [Parameter()]
        [switch] $FailOnError
    )

    $result = [ordered]@{
        Source       = $Source
        LogName      = $LogName
        IsWindows    = $false
        SourceExists = $false
        Created      = $false
        Skipped      = $false
        Error        = $null
    }

    if (-not (Test-WtcgWindowsPlatform)) {
        $result.Skipped = $true
        $result.Error = 'Windows Event Log is only available on Windows.'
        return [pscustomobject]$result
    }

    $result.IsWindows = $true

    try {
        $result.SourceExists = [System.Diagnostics.EventLog]::SourceExists($Source)
    }
    catch {
        $result.Error = $_.Exception.Message
        if ($FailOnError) {
            throw
        }
        return [pscustomobject]$result
    }

    if ($result.SourceExists) {
        return [pscustomobject]$result
    }

    try {
        if ($PSCmdlet.ShouldProcess("$LogName/$Source", 'Create Windows Event Log source')) {
            $creationData = [System.Diagnostics.EventSourceCreationData]::new($Source, $LogName)
            [System.Diagnostics.EventLog]::CreateEventSource($creationData)
            $result.Created = $true
            $result.SourceExists = $true
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        if ($FailOnError) {
            throw
        }
    }

    [pscustomobject]$result
}

function Write-WtcgWindowsEventLog {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $EventId,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $EntryType = 'Information',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Source = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $LogName = 'Application',

        [Parameter()]
        [ValidateRange(0, 32767)]
        [int] $Category = 0,

        [Parameter()]
        [bool] $EnsureSource = $true,

        [Parameter()]
        [switch] $FailOnError
    )

    $result = [ordered]@{
        Source    = $Source
        LogName   = $LogName
        EventId   = $EventId
        EntryType = $EntryType
        Message   = $Message
        Written   = $false
        Skipped   = $false
        Error     = $null
    }

    if (-not (Test-WtcgWindowsPlatform)) {
        $result.Skipped = $true
        $result.Error = 'Windows Event Log is only available on Windows.'
        return [pscustomobject]$result
    }

    if ($EnsureSource) {
        $sourceResult = Initialize-WtcgWindowsEventLogSource `
            -Source $Source `
            -LogName $LogName `
            -FailOnError:$FailOnError

        if (-not ([bool]$sourceResult.SourceExists)) {
            $result.Skipped = $true
            $result.Error = if (-not [string]::IsNullOrWhiteSpace([string]$sourceResult.Error)) {
                [string]$sourceResult.Error
            }
            else {
                "Windows Event Log source '$Source' does not exist and could not be created."
            }
            return [pscustomobject]$result
        }
    }

    try {
        if ($PSCmdlet.ShouldProcess("$LogName/$Source", "Write event $EventId")) {
            $entryTypeValue = [System.Diagnostics.EventLogEntryType]::$EntryType
            [System.Diagnostics.EventLog]::WriteEntry($Source, $Message, $entryTypeValue, $EventId, [int16]$Category)
            $result.Written = $true
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        if ($FailOnError) {
            throw
        }
    }

    [pscustomobject]$result
}

function Write-WtcgAuditEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('disable', 'scheduled-reenable', 're-enable', 'error', 'notification')]
        [string] $Action,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $EventId,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $EntryType = 'Information',

        [Parameter()]
        [AllowNull()]
        [object] $Details,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogSource = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogName = 'Application',

        [Parameter()]
        [switch] $DisableEventLog,

        [Parameter()]
        [switch] $FailOnEventLogError
    )

    $now = Get-Date
    $eventDetails = if ($null -ne $Details) { $Details } else { [ordered]@{} }
    $payload = [ordered]@{
        schemaVersion  = '1.0'
        product        = 'WinTaskCrossingGuard'
        eventSource    = $EventLogSource
        timestampUtc   = $now.ToUniversalTime().ToString('o')
        timestampLocal = $now.ToString('o')
        action         = $Action
        operation      = $Operation
        status         = $Status
        hostName       = $env:COMPUTERNAME
        userName       = $env:USERNAME
        processId      = $PID
        details        = $eventDetails
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $payload.runId = $RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $payload.runFolderPath = $RunFolderPath
    }

    $message = $payload | ConvertTo-Json -Depth 20 -Compress

    if ($DisableEventLog) {
        return [pscustomobject]@{
            Source    = $EventLogSource
            LogName   = $EventLogName
            EventId   = $EventId
            EntryType = $EntryType
            Message   = $message
            Written   = $false
            Skipped   = $true
            Error     = 'Windows Event Log auditing disabled by caller.'
        }
    }

    Write-WtcgWindowsEventLog `
        -Source $EventLogSource `
        -LogName $EventLogName `
        -EventId $EventId `
        -EntryType $EntryType `
        -Message $message `
        -EnsureSource $true `
        -FailOnError:$FailOnEventLogError
}

function Resolve-WtcgJsonlLogPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot),

        [Parameter()]
        [string] $Prefix = 'wintaskcrossingguard-events'
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $BaseDirectory (Join-Path 'steamablelogs' "$Prefix-$timestamp.jsonl")
}

function New-WtcgJsonlEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('disable', 're-enable', 'error', 'notification')]
        [string] $Action,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [object] $Details,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $HostName = $env:COMPUTERNAME,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $UserName = $env:USERNAME
    )

    $now = Get-Date
    $event = [ordered]@{
        schemaVersion  = '1.0'
        source         = 'WinTaskCrossingGuard'
        timestampUtc   = $now.ToUniversalTime().ToString('o')
        timestampLocal = $now.ToString('o')
        action         = $Action
        operation      = $Operation
        hostName       = $HostName
        userName       = $UserName
        processId      = $PID
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $event.status = $Status
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $event.runId = $RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $event.runFolderPath = $RunFolderPath
    }

    $event.details = if ($null -ne $Details) { $Details } else { [ordered]@{} }

    [pscustomobject]$event
}

function Write-WtcgJsonlEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Event,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Event) {
            if ($null -ne $entry) {
                $items.Add($entry)
            }
        }
    }

    end {
        $resolvedPath = Resolve-WtcgJsonlLogPath -Path $Path

        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            throw "Could not resolve JSONL log path."
        }

        $directory = Split-Path -Parent $resolvedPath
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        foreach ($entry in $items) {
            $json = $entry | ConvertTo-Json -Depth 20 -Compress
            Add-Content -LiteralPath $resolvedPath -Value $json -Encoding utf8
        }

        Get-Item -LiteralPath $resolvedPath
    }
}

function Write-WtcgDisableJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Task,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter()]
        [AllowNull()]
        [datetime] $ReenableAt,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ReenableTaskFullName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'DisableTasksInWindow'
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Task) {
            if ($null -ne $entry) {
                $items.Add($entry)
            }
        }
    }

    end {
        $events = foreach ($entry in $items) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskPath'))
            $taskName = [string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskName')
            $nextRunTime = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
            $disabledAt = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledAt'

            $details = [ordered]@{
                taskPath               = $taskPath
                taskName               = $taskName
                fullName               = "$taskPath$taskName"
                stateAtDiscovery       = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                originalState          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'OriginalState'
                wasOriginallyEnabled   = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'WasOriginallyEnabled' -DefaultValue $true)
                disabledBySuite        = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledBySuite' -DefaultValue $true)
                disabledAt             = if ($null -ne $disabledAt) { ([datetime]$disabledAt).ToString('o') } else { $null }
                nextRunTime            = if ($null -ne $nextRunTime -and ([datetime]$nextRunTime) -ne [datetime]::MinValue) { ([datetime]$nextRunTime).ToString('o') } else { $null }
                windowStart            = $WindowStart.ToString('o')
                windowEnd              = $WindowEnd.ToString('o')
                reenableAt             = if ($null -ne $ReenableAt) { $ReenableAt.ToString('o') } else { $null }
                selectionSource        = $SelectionSource
                identityOutputPath     = $IdentityOutputPath
                reenableTaskFullName   = $ReenableTaskFullName
            }

            New-WtcgJsonlEvent `
                -Action 'disable' `
                -Operation $Operation `
                -Status 'succeeded' `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -Details $details
        }

        $events | Write-WtcgJsonlEvent -Path $Path
    }
}

function Write-WtcgReenableJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Task,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ManifestPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'ReenableTaskIdentities'
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Task) {
            if ($null -ne $entry) {
                $items.Add($entry)
            }
        }
    }

    end {
        $events = foreach ($entry in $items) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskPath'))
            $taskName = [string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskName')

            $details = [ordered]@{
                taskPath     = $taskPath
                taskName     = $taskName
                fullName     = "$taskPath$taskName"
                identityPath  = $IdentityPath
                manifestPath  = $ManifestPath
            }

            New-WtcgJsonlEvent `
                -Action 're-enable' `
                -Operation $Operation `
                -Status 'succeeded' `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -Details $details
        }

        $events | Write-WtcgJsonlEvent -Path $Path
    }
}

function Write-WtcgErrorJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    $details = [ordered]@{
        message                 = $message
        type                    = $errorType
        fullyQualifiedErrorId   = if ($null -ne $ErrorRecord.FullyQualifiedErrorId) { [string]$ErrorRecord.FullyQualifiedErrorId } else { $null }
        positionMessage         = if ($null -ne $ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.PositionMessage } else { $null }
        selectionSource         = $SelectionSource
        identityOutputPath      = $IdentityOutputPath
    }

    New-WtcgJsonlEvent `
        -Action 'error' `
        -Operation $Operation `
        -Status 'failed' `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Details $details |
        Write-WtcgJsonlEvent -Path $Path
}

function Write-WtcgNotificationJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard notification',

        [Parameter()]
        [ValidateSet('attempted', 'sent', 'failed', 'skipped')]
        [string] $Status = 'sent',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Channel = 'email',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Subject,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $To,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Cc,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SmtpServer,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorMessage,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    $details = [ordered]@{
        channel            = $Channel
        subject            = $Subject
        to                 = @($To | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        cc                 = @($Cc | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        smtpServer         = $SmtpServer
        xmlLogPath         = $XmlLogPath
        identityOutputPath = $IdentityOutputPath
        errorMessage       = $ErrorMessage
    }

    New-WtcgJsonlEvent `
        -Action 'notification' `
        -Operation $Operation `
        -Status $Status `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Details $details |
        Write-WtcgJsonlEvent -Path $Path
}

function Write-WtcgDisableXmlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Task,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter()]
        [AllowNull()]
        [datetime] $ReenableAt,

        [Parameter()]
        [AllowNull()]
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [string] $ReenableTaskFullName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'DisableTasksInWindow'
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
        $createdAt = Get-Date
    }

    process {
        foreach ($entry in $Task) {
            $items.Add($entry)
        }
    }

    end {
        $resolvedPath = if ([string]::IsNullOrWhiteSpace($Path)) {
            Resolve-WtcgXmlLogPath -Path $null
        }
        else {
            Resolve-WtcgXmlLogPath -Path $Path
        }

        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            throw "Could not resolve XML log path."
        }

        $directory = Split-Path -Parent $resolvedPath
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

        $writer = [System.Xml.XmlWriter]::Create($resolvedPath, $settings)

        try {
            $writer.WriteStartDocument()

            $writer.WriteStartElement('WinTaskCrossingGuardDisableLog')
            $writer.WriteAttributeString('createdAt', $createdAt.ToString('o'))
            $writer.WriteAttributeString('createdLocal', $createdAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))
            $writer.WriteAttributeString('operation', $Operation)
            if (-not [string]::IsNullOrWhiteSpace($RunId)) {
                $writer.WriteAttributeString('runId', $RunId)
            }
            if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
                $writer.WriteElementString('RunFolderPath', $RunFolderPath)
            }

            $writer.WriteStartElement('Window')
            $writer.WriteElementString('Start', $WindowStart.ToString('o'))
            $writer.WriteElementString('End', $WindowEnd.ToString('o'))
            $writer.WriteEndElement()

            if ($null -ne $ReenableAt) {
                $writer.WriteElementString('ReenableAt', $ReenableAt.ToString('o'))
            }

            if (-not [string]::IsNullOrWhiteSpace($SelectionSource)) {
                $writer.WriteElementString('SelectionSource', $SelectionSource)
            }

            if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
                $writer.WriteElementString('IdentityOutputPath', $IdentityOutputPath)
            }

            if (-not [string]::IsNullOrWhiteSpace($ReenableTaskFullName)) {
                $writer.WriteElementString('ReenableTaskFullName', $ReenableTaskFullName)
            }

            $writer.WriteStartElement('Tasks')
            $writer.WriteAttributeString('count', ([string]$items.Count))

            foreach ($entry in $items) {
                $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskPath'))
                $taskName = [string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskName')

                $writer.WriteStartElement('Task')
                $writer.WriteElementString('TaskPath', $normalizedPath)
                $writer.WriteElementString('TaskName', $taskName)
                $writer.WriteElementString('FullName', "$normalizedPath$taskName")

                $entryState = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                if ($null -ne $entryState) {
                    $writer.WriteElementString('StateAtDiscovery', ([string]$entryState))
                }

                $entryNextRunTime = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
                if ($null -ne $entryNextRunTime) {
                    $nextRunTime = [datetime]$entryNextRunTime
                    if ($nextRunTime -ne [datetime]::MinValue) {
                        $writer.WriteElementString('NextRunTime', $nextRunTime.ToString('o'))
                    }
                }

                $writer.WriteElementString('Action', 'Disabled')
                $writer.WriteElementString('LoggedAt', (Get-Date).ToString('o'))
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
            $writer.WriteEndElement()
            $writer.WriteEndDocument()
        }
        finally {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
        }

        Get-Item -LiteralPath $resolvedPath
    }
}

function Write-WtcgErrorXmlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    $resolvedPath = Resolve-WtcgXmlLogPath -Path $Path -Prefix 'wintaskcrossingguard-error'
    $directory = Split-Path -Parent $resolvedPath
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    $createdAt = Get-Date
    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $writer = [System.Xml.XmlWriter]::Create($resolvedPath, $settings)

    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('WinTaskCrossingGuardErrorLog')
        $writer.WriteAttributeString('createdAt', $createdAt.ToString('o'))
        $writer.WriteAttributeString('createdLocal', $createdAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))
        $writer.WriteAttributeString('operation', $Operation)
        if (-not [string]::IsNullOrWhiteSpace($RunId)) {
            $writer.WriteAttributeString('runId', $RunId)
        }
        if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
            $writer.WriteElementString('RunFolderPath', $RunFolderPath)
        }

        if (-not [string]::IsNullOrWhiteSpace($SelectionSource)) {
            $writer.WriteElementString('SelectionSource', $SelectionSource)
        }

        if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
            $writer.WriteElementString('IdentityOutputPath', $IdentityOutputPath)
        }

        $writer.WriteStartElement('Error')
        $writer.WriteElementString('Message', $message)

        if (-not [string]::IsNullOrWhiteSpace($errorType)) {
            $writer.WriteElementString('Type', $errorType)
        }

        if ($null -ne $ErrorRecord.FullyQualifiedErrorId) {
            $writer.WriteElementString('FullyQualifiedErrorId', ([string]$ErrorRecord.FullyQualifiedErrorId))
        }

        if ($null -ne $ErrorRecord.InvocationInfo -and
            -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage)) {
            $writer.WriteElementString('PositionMessage', $ErrorRecord.InvocationInfo.PositionMessage)
        }

        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }

    Get-Item -Path $resolvedPath
}

function Get-WtcgMailSettingsForConfigurationError {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionPath
    )

    if ([string]::IsNullOrWhiteSpace($SelectionPath) -or -not (Test-Path -LiteralPath $SelectionPath)) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    try {
        $json = Get-Content -LiteralPath $SelectionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        $jsonMail = Get-WtcgObjectPropertyValue -InputObject $json -Name 'mail'

        if ($null -eq $jsonMail) {
            return ConvertTo-WtcgMailSettings -Mail $null
        }

        $entries = @($jsonMail)

        if ($entries.Count -eq 1) {
            return ConvertTo-WtcgMailSettings -Mail $entries[0]
        }

        $errorEntry = $entries | Where-Object {
            $entryEvent = Get-WtcgObjectPropertyValue -InputObject $_ -Name 'event'
            $null -ne $entryEvent -and ([string]$entryEvent).Trim().ToLowerInvariant() -eq 'error'
        } | Select-Object -First 1

        if ($null -ne $errorEntry) {
            return ConvertTo-WtcgMailSettings -Mail $errorEntry
        }

        return ConvertTo-WtcgMailSettings -Mail $entries[0]
    }
    catch {
        return ConvertTo-WtcgMailSettings -Mail $null
    }
}

function ConvertTo-WtcgMailSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    if ($null -eq $Mail) {
        return [pscustomobject]@{
            Enabled            = $false
            SmtpServer         = $null
            Port               = 25
            From               = $null
            To                 = @()
            Cc                 = @()
            UseSsl             = $false
            AttachXmlLog       = $true
            AttachIdentityFile = $false
            FailOnEmailError   = $false
        }
    }

    $enabled = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'enabled' -DefaultValue $false)
    $port = [int](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'port' -DefaultValue 25)
    $useSsl = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'useSsl' -DefaultValue $false)
    $attachXmlLog = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'attachXmlLog' -DefaultValue $true)
    $attachIdentityFile = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'attachIdentityFile' -DefaultValue $false)
    $failOnEmailError = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'failOnEmailError' -DefaultValue $false)

    $smtpServer = Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'smtpServer'
    $from = Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'from'
    $to = @(Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'to' -DefaultValue @())
    $cc = @(Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'cc' -DefaultValue @())

    [pscustomobject]@{
        Enabled            = $enabled
        SmtpServer         = if ($null -ne $smtpServer) { [string]$smtpServer } else { $null }
        Port               = $port
        From               = if ($null -ne $from) { [string]$from } else { $null }
        To                 = @($to | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        Cc                 = @($cc | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        UseSsl             = $useSsl
        AttachXmlLog       = $attachXmlLog
        AttachIdentityFile = $attachIdentityFile
        FailOnEmailError   = $failOnEmailError
    }
}



function Assert-WtcgMailEventSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    $entries = @($Mail)

    if ($null -eq $Mail -or $entries.Count -le 1) {
        return
    }

    if ($entries.Count -gt 2) {
        throw "Invalid mail configuration: the 'mail' array supports either one shared entry or two entries: one with event='result' and one with event='error'."
    }

    $events = foreach ($entry in $entries) {
        $entryEvent = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'event'
        if ($null -eq $entryEvent -or [string]::IsNullOrWhiteSpace([string]$entryEvent)) {
            throw "Invalid mail configuration: when two mail entries are provided, each entry must include an event attribute. Required values are 'result' and 'error'."
        }

        ([string]$entryEvent).Trim().ToLowerInvariant()
    }

    foreach ($event in $events) {
        if ($event -notin @('result', 'error')) {
            throw "Invalid mail configuration: unsupported mail event '$event'. Required values are 'result' and 'error'."
        }
    }

    if (@($events | Where-Object { $_ -eq 'result' }).Count -ne 1 -or
        @($events | Where-Object { $_ -eq 'error' }).Count -ne 1) {
        throw "Invalid mail configuration: when two mail entries are provided, exactly one must use event='result' and exactly one must use event='error'."
    }
}

function ConvertTo-WtcgMailEventSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    $disabled = ConvertTo-WtcgMailSettings -Mail $null

    if ($null -eq $Mail) {
        return [pscustomobject]@{
            Result = $disabled
            Error  = $disabled
        }
    }

    $entries = @($Mail)

    # A single entry is shared by both events.
    if ($entries.Count -eq 1) {
        $shared = ConvertTo-WtcgMailSettings -Mail $entries[0]

        return [pscustomobject]@{
            Result = $shared
            Error  = $shared
        }
    }

    Assert-WtcgMailEventSettings -Mail $entries

    $result = $disabled
    $errorReport = $disabled

    foreach ($entry in $entries) {
        $event = ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'event')).Trim().ToLowerInvariant()
        $settings = ConvertTo-WtcgMailSettings -Mail $entry

        switch ($event) {
            'result' {
                $result = $settings
                break
            }

            'error' {
                $errorReport = $settings
                break
            }
        }
    }

    [pscustomobject]@{
        Result = $result
        Error  = $errorReport
    }
}

function Get-WtcgResultMailSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $selectionMail = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'Mail'
    if ($null -eq $selectionMail) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $resultMail = Get-WtcgObjectPropertyValue -InputObject $selectionMail -Name 'Result'
    if ($null -ne $resultMail) {
        return $resultMail
    }

    return $selectionMail
}

function Get-WtcgErrorMailSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $selectionMail = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'Mail'
    if ($null -eq $selectionMail) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $errorMail = Get-WtcgObjectPropertyValue -InputObject $selectionMail -Name 'Error'
    if ($null -ne $errorMail) {
        return $errorMail
    }

    return $selectionMail
}

function Test-WtcgMailSettingsReady {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings
    )

    if ($null -eq $MailSettings) {
        return $false
    }

    $enabled = [bool](Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'Enabled' -DefaultValue $false)
    $smtpServer = Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'SmtpServer'
    $from = Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'From'
    $to = @(Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'To' -DefaultValue @())

    return (
        $enabled -and
        -not [string]::IsNullOrWhiteSpace([string]$smtpServer) -and
        -not [string]::IsNullOrWhiteSpace([string]$from) -and
        $to.Count -gt 0
    )
}

function Get-WtcgMailAttachments {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath
    )

    $attachments = @()

    if ($null -eq $MailSettings) {
        return $attachments
    }

    if ([bool]$MailSettings.AttachXmlLog -and
        -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and
        (Test-Path -LiteralPath $XmlLogPath)) {
        $attachments += $XmlLogPath
    }

    if ([bool]$MailSettings.AttachIdentityFile -and
        -not [string]::IsNullOrWhiteSpace($IdentityOutputPath) -and
        (Test-Path -LiteralPath $IdentityOutputPath)) {
        $attachments += $IdentityOutputPath
    }

    return $attachments
}

function Send-WtcgLogGeneratedNotificationFromSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings,

        [Parameter(Mandatory)]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard log generated',

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard XML log generated'
    )

    if (-not (Test-WtcgMailSettingsReady -MailSettings $MailSettings)) {
        return
    }

    try {
        $attachments = Get-WtcgMailAttachments `
            -MailSettings $MailSettings `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath

        $body = New-WtcgLogGeneratedMailBody `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath `
            -Operation $Operation `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        $sendResult = Send-WtcgMailNotification `
            -SmtpServer $MailSettings.SmtpServer `
            -Port $MailSettings.Port `
            -From $MailSettings.From `
            -To $MailSettings.To `
            -Cc $MailSettings.Cc `
            -Subject $Subject `
            -Body $body `
            -AttachmentPath $attachments `
            -UseSsl:$MailSettings.UseSsl

        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'sent' `
                -Subject $Subject `
                -To $MailSettings.To `
                -Cc $MailSettings.Cc `
                -SmtpServer $MailSettings.SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        $sendResult
    }
    catch {
        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'failed' `
                -Subject $Subject `
                -To $MailSettings.To `
                -Cc $MailSettings.Cc `
                -SmtpServer $MailSettings.SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -ErrorMessage $_.Exception.Message `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        Write-Warning "Failed to send WinTaskCrossingGuard log-generated email: $($_.Exception.Message)"

        if ($MailSettings.FailOnEmailError) {
            throw
        }
    }
}

function Send-WtcgErrorNotificationFromSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings,

        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard error'
    )

    if (-not (Test-WtcgMailSettingsReady -MailSettings $MailSettings)) {
        return
    }

    try {
        $attachments = Get-WtcgMailAttachments `
            -MailSettings $MailSettings `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath

        $body = New-WtcgErrorMailBody `
            -ErrorRecord $ErrorRecord `
            -Operation $Operation `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        $sendResult = Send-WtcgMailNotification `
            -SmtpServer $MailSettings.SmtpServer `
            -Port $MailSettings.Port `
            -From $MailSettings.From `
            -To $MailSettings.To `
            -Cc $MailSettings.Cc `
            -Subject $Subject `
            -Body $body `
            -AttachmentPath $attachments `
            -UseSsl:$MailSettings.UseSsl

        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'sent' `
                -Subject $Subject `
                -To $MailSettings.To `
                -Cc $MailSettings.Cc `
                -SmtpServer $MailSettings.SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        $sendResult
    }
    catch {
        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'failed' `
                -Subject $Subject `
                -To $MailSettings.To `
                -Cc $MailSettings.Cc `
                -SmtpServer $MailSettings.SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -ErrorMessage $_.Exception.Message `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        Write-Warning "Failed to send WinTaskCrossingGuard error email: $($_.Exception.Message)"

        if ($MailSettings.FailOnEmailError) {
            throw
        }
    }
}

function Send-WtcgMailNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SmtpServer,

        [Parameter()]
        [int] $Port = 25,

        [Parameter(Mandatory)]
        [string] $From,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $To,

        [Parameter()]
        [string[]] $Cc,

        [Parameter(Mandatory)]
        [string] $Subject,

        [Parameter(Mandatory)]
        [string] $Body,

        [Parameter()]
        [string[]] $AttachmentPath,

        [Parameter()]
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential
    )

    $message = [System.Net.Mail.MailMessage]::new()
    $smtp = $null

    try {
        $message.From = $From

        foreach ($recipient in @($To)) {
            if (-not [string]::IsNullOrWhiteSpace($recipient)) {
                [void] $message.To.Add($recipient)
            }
        }

        foreach ($recipient in @($Cc)) {
            if (-not [string]::IsNullOrWhiteSpace($recipient)) {
                [void] $message.CC.Add($recipient)
            }
        }

        if ($message.To.Count -eq 0) {
            throw "At least one email recipient is required."
        }

        $message.Subject = $Subject
        $message.Body = $Body
        $message.IsBodyHtml = $false

        foreach ($path in @($AttachmentPath)) {
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                if (-not (Test-Path -LiteralPath $path)) {
                    throw "Attachment not found: $path"
                }

                $attachment = [System.Net.Mail.Attachment]::new($path)
                [void] $message.Attachments.Add($attachment)
            }
        }

        $smtp = [System.Net.Mail.SmtpClient]::new($SmtpServer, $Port)
        $smtp.EnableSsl = [bool] $UseSsl

        if ($null -ne $Credential) {
            $smtp.Credentials = $Credential.GetNetworkCredential()
        }
        else {
            $smtp.UseDefaultCredentials = $true
        }

        $smtp.Send($message)

        [pscustomobject]@{
            Sent        = $true
            SmtpServer  = $SmtpServer
            Port        = $Port
            From        = $From
            To          = $To
            Cc          = $Cc
            Subject     = $Subject
            Attachments = @($AttachmentPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    finally {
        if ($null -ne $message) {
            $message.Dispose()
        }

        if ($null -ne $smtp) {
            $smtp.Dispose()
        }
    }
}

function New-WtcgLogGeneratedMailBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard log generated',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $HostName = $env:COMPUTERNAME
    )

    @"
WinTaskCrossingGuard generated an XML log.

Operation:
  $Operation

Host:
  $HostName

Timestamp:
  $(Get-Date -Format 'o')

Run ID:
  $RunId

Run folder:
  $RunFolderPath

XML log path:
  $XmlLogPath

Identity output path:
  $IdentityOutputPath
"@
}

function New-WtcgErrorMailBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [string] $LogEmailSmtpServer,

        [Parameter()]
        [int] $LogEmailSmtpPort = 25,

        [Parameter()]
        [string] $LogEmailFrom,

        [Parameter()]
        [string[]] $LogEmailTo,

        [Parameter()]
        [string[]] $LogEmailCc,

        [Parameter()]
        [string] $LogEmailSubject = 'WinTaskCrossingGuard XML log generated',

        [Parameter()]
        [switch] $LogEmailUseSsl,

        [Parameter()]
        [pscredential] $LogEmailCredential,

        [Parameter()]
        [switch] $FailOnLogEmailError,

        [Parameter()]
        [string] $ErrorEmailSmtpServer,

        [Parameter()]
        [int] $ErrorEmailSmtpPort = 25,

        [Parameter()]
        [string] $ErrorEmailFrom,

        [Parameter()]
        [string[]] $ErrorEmailTo,

        [Parameter()]
        [string[]] $ErrorEmailCc,

        [Parameter()]
        [string] $ErrorEmailSubject = 'WinTaskCrossingGuard error',

        [Parameter()]
        [switch] $ErrorEmailUseSsl,

        [Parameter()]
        [pscredential] $ErrorEmailCredential,

        [Parameter()]
        [switch] $FailOnErrorEmail,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $HostName = $env:COMPUTERNAME
    )

    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    @"
WinTaskCrossingGuard encountered an error.

Operation:
  $Operation

Host:
  $HostName

Timestamp:
  $(Get-Date -Format 'o')

Run ID:
  $RunId

Run folder:
  $RunFolderPath

Error:
  $message

Error type:
  $errorType

Script position:
$($ErrorRecord.InvocationInfo.PositionMessage)

XML log path:
  $XmlLogPath

Identity output path:
  $IdentityOutputPath

Fully qualified error id:
  $($ErrorRecord.FullyQualifiedErrorId)
"@
}

function Send-WtcgLogGeneratedNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SmtpServer,

        [Parameter()]
        [int] $Port = 25,

        [Parameter(Mandatory)]
        [string] $From,

        [Parameter(Mandatory)]
        [string[]] $To,

        [Parameter()]
        [string[]] $Cc,

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard XML log generated',

        [Parameter(Mandatory)]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard log generated',

        [Parameter()]
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential,

        [Parameter()]
        [switch] $AttachXmlLog = $true,

        [Parameter()]
        [switch] $FailOnEmailError
    )

    try {
        $attachments = @()

        if ($AttachXmlLog -and -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and (Test-Path -LiteralPath $XmlLogPath)) {
            $attachments += $XmlLogPath
        }

        $body = New-WtcgLogGeneratedMailBody `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath `
            -Operation $Operation `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        $sendResult = Send-WtcgMailNotification `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -From $From `
            -To $To `
            -Cc $Cc `
            -Subject $Subject `
            -Body $body `
            -AttachmentPath $attachments `
            -UseSsl:$UseSsl `
            -Credential $Credential

        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'sent' `
                -Subject $Subject `
                -To $To `
                -Cc $Cc `
                -SmtpServer $SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        $sendResult
    }
    catch {
        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'failed' `
                -Subject $Subject `
                -To $To `
                -Cc $Cc `
                -SmtpServer $SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -ErrorMessage $_.Exception.Message `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        Write-Warning "Failed to send WinTaskCrossingGuard log-generated email: $($_.Exception.Message)"

        if ($FailOnEmailError) {
            throw
        }
    }
}

function Send-WtcgErrorNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter(Mandatory)]
        [string] $SmtpServer,

        [Parameter()]
        [int] $Port = 25,

        [Parameter(Mandatory)]
        [string] $From,

        [Parameter(Mandatory)]
        [string[]] $To,

        [Parameter()]
        [string[]] $Cc,

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard error',

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential,

        [Parameter()]
        [switch] $AttachXmlLog = $true,

        [Parameter()]
        [switch] $FailOnEmailError
    )

    try {
        $attachments = @()

        if ($AttachXmlLog -and -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and (Test-Path -LiteralPath $XmlLogPath)) {
            $attachments += $XmlLogPath
        }

        $body = New-WtcgErrorMailBody `
            -ErrorRecord $ErrorRecord `
            -Operation $Operation `
            -XmlLogPath $XmlLogPath `
            -IdentityOutputPath $IdentityOutputPath `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        $sendResult = Send-WtcgMailNotification `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -From $From `
            -To $To `
            -Cc $Cc `
            -Subject $Subject `
            -Body $body `
            -AttachmentPath $attachments `
            -UseSsl:$UseSsl `
            -Credential $Credential

        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'sent' `
                -Subject $Subject `
                -To $To `
                -Cc $Cc `
                -SmtpServer $SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        $sendResult
    }
    catch {
        try {
            Write-WtcgNotificationJsonlLog `
                -Path $JsonlLogPath `
                -Operation $Operation `
                -Status 'failed' `
                -Subject $Subject `
                -To $To `
                -Cc $Cc `
                -SmtpServer $SmtpServer `
                -XmlLogPath $XmlLogPath `
                -IdentityOutputPath $IdentityOutputPath `
                -ErrorMessage $_.Exception.Message `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)"
        }

        Write-Warning "Failed to send WinTaskCrossingGuard error email: $($_.Exception.Message)"

        if ($FailOnEmailError) {
            throw
        }
    }
}


function Invoke-WtcgRegisterScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter()]
        [object] $Action,

        [Parameter()]
        [object] $Trigger,

        [Parameter()]
        [object] $Settings,

        [Parameter()]
        [object] $Principal,

        [Parameter()]
        [string] $Description,

        [Parameter()]
        [switch] $Force
    )

    Register-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal `
        -Description $Description `
        -Force:$Force
}

function Invoke-WtcgSetScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter()]
        [object] $Action,

        [Parameter()]
        [object] $Trigger,

        [Parameter()]
        [object] $Settings,

        [Parameter()]
        [object] $Principal
    )

    Set-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal
}

function Disable-WtcgTasksInWindowAndScheduleReenable {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string] $Start,

        [Parameter(Mandatory)]
        [string] $End,

        [Parameter(Mandatory)]
        [datetime] $ReenableAt,

        [Parameter()]
        [string] $SelectionPath,

        [Parameter()]
        [string[]] $TaskPath = '\',

        [Parameter()]
        [string[]] $TaskName = '*',

        [Parameter()]
        [switch] $Recurse,

        [Parameter()]
        [switch] $IncludeDisabled,

        [Parameter()]
        [Alias('ManifestPath')]
        [string] $IdentityOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'rollback-manifest.json'),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunRootPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ReportPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogSource = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogName = 'Application',

        [Parameter()]
        [switch] $DisableEventLog,

        [Parameter()]
        [switch] $FailOnEventLogError,

        [Parameter()]
        [string] $ReenableTaskPath = '\WinTaskCrossingGuard\',

        [Parameter()]
        [string] $ReenableTaskName = 'ReenableDisabledTasks',

        [Parameter()]
        [string] $PowerShellExePath = 'pwsh.exe',

        [Parameter()]
        [string] $EnableScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Restore-TasksFromManifest.ps1'),

        [Parameter()]
        [string] $LogEmailSmtpServer,

        [Parameter()]
        [int] $LogEmailSmtpPort = 25,

        [Parameter()]
        [string] $LogEmailFrom,

        [Parameter()]
        [string[]] $LogEmailTo,

        [Parameter()]
        [string[]] $LogEmailCc,

        [Parameter()]
        [string] $LogEmailSubject = 'WinTaskCrossingGuard XML log generated',

        [Parameter()]
        [switch] $LogEmailUseSsl,

        [Parameter()]
        [pscredential] $LogEmailCredential,

        [Parameter()]
        [switch] $FailOnLogEmailError,

        [Parameter()]
        [string] $ErrorEmailSmtpServer,

        [Parameter()]
        [int] $ErrorEmailSmtpPort = 25,

        [Parameter()]
        [string] $ErrorEmailFrom,

        [Parameter()]
        [string[]] $ErrorEmailTo,

        [Parameter()]
        [string[]] $ErrorEmailCc,

        [Parameter()]
        [string] $ErrorEmailSubject = 'WinTaskCrossingGuard error',

        [Parameter()]
        [switch] $ErrorEmailUseSsl,

        [Parameter()]
        [pscredential] $ErrorEmailCredential,

        [Parameter()]
        [switch] $FailOnErrorEmail,

        [Parameter()]
        [string] $LockName = 'Global\WinTaskCrossingGuard',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $LockPath,

        [Parameter()]
        [int] $LockTimeoutSeconds = 0,

        [Parameter()]
        [switch] $DisableLock,

        [Parameter()]
        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $runtimeLock = $null
    $resultMailSettings = ConvertTo-WtcgMailSettings -Mail $null
    $errorMailSettings = $null
    $xmlLogFile = $null
    $jsonlLogFile = $null
    $reportFile = $null

    $runContext = New-WtcgRunContext `
        -RunId $RunId `
        -RunRootPath $RunRootPath `
        -RunFolderPath $RunFolderPath `
        -Operation 'DisableTasksInWindowAndScheduleReenable'

    $RunId = $runContext.RunId
    $RunFolderPath = $runContext.RunFolderPath

    if (-not $PSBoundParameters.ContainsKey('IdentityOutputPath') -or [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
        $IdentityOutputPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Manifests' -FileName 'rollback-manifest.json'
    }

    if (-not $PSBoundParameters.ContainsKey('XmlLogPath') -or [string]::IsNullOrWhiteSpace($XmlLogPath)) {
        $XmlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Logs' -FileName 'disabled-tasks.xml'
    }

    if (-not $PSBoundParameters.ContainsKey('JsonlLogPath') -or [string]::IsNullOrWhiteSpace($JsonlLogPath)) {
        $JsonlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
    }

    if (-not $PSBoundParameters.ContainsKey('ReportPath') -or [string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Reports' -FileName 'disable-schedule-report.json'
    }

    $effectiveErrorXmlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'wintaskcrossingguard-error.xml'
    $effectiveErrorReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'disable-schedule-error-report.json'

    trap {
        $wtcgTrapError = $_
        Exit-WtcgRuntimeLock -Lock $runtimeLock -ErrorAction SilentlyContinue

        Write-Host "WinTaskCrossingGuard error: $($_.Exception.Message)" -ForegroundColor Red

        $errorXmlLogFile = Write-WtcgErrorXmlLog `
            -ErrorRecord $_ `
            -Path $effectiveErrorXmlLogPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -SelectionSource $SelectionPath `
            -IdentityOutputPath $IdentityOutputPath `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        Write-Host "XML error log written to: $($errorXmlLogFile.FullName)" -ForegroundColor Yellow

        $errorJsonlLogFile = Write-WtcgErrorJsonlLog `
            -ErrorRecord $_ `
            -Path $JsonlLogPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -SelectionSource $SelectionPath `
            -IdentityOutputPath $IdentityOutputPath `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

        Write-Host "JSONL error log written to: $($errorJsonlLogFile.FullName)" -ForegroundColor Yellow

        Save-WtcgRunReport `
            -RunContext $runContext `
            -Path $effectiveErrorReportPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -Status 'failed' `
            -Details ([ordered]@{
                message = $_.Exception.Message
                selectionSource = $SelectionPath
                identityOutputPath = $IdentityOutputPath
                xmlLogPath = if ($null -ne $errorXmlLogFile) { $errorXmlLogFile.FullName } else { $null }
                jsonlLogPath = if ($null -ne $errorJsonlLogFile) { $errorJsonlLogFile.FullName } else { $null }
            }) |
            Out-Null

        Write-WtcgAuditEvent `
            -Action 'error' `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -Status 'failed' `
            -EventId 5100 `
            -EntryType 'Error' `
            -Details ([ordered]@{
                message = $_.Exception.Message
                selectionSource = $SelectionPath
                identityOutputPath = $IdentityOutputPath
                xmlLogPath = if ($null -ne $errorXmlLogFile) { $errorXmlLogFile.FullName } else { $null }
                jsonlLogPath = if ($null -ne $errorJsonlLogFile) { $errorJsonlLogFile.FullName } else { $null }
            }) `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath `
            -EventLogSource $EventLogSource `
            -EventLogName $EventLogName `
            -DisableEventLog:$DisableEventLog `
            -FailOnEventLogError:$FailOnEventLogError |
            Out-Null



        if ($null -ne $errorMailSettings -and (Test-WtcgMailSettingsReady -MailSettings $errorMailSettings)) {
            $errorXmlLogPath = Resolve-WtcgXmlLogPath -Path $XmlLogPath

            Send-WtcgErrorNotificationFromSettings `
                -MailSettings $errorMailSettings `
                -ErrorRecord $_ `
                -Operation 'DisableTasksInWindowAndScheduleReenable' `
                -XmlLogPath $errorXmlLogFile.FullName `
                -JsonlLogPath $errorJsonlLogFile.FullName `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath
        }

        if (-not [string]::IsNullOrWhiteSpace($ErrorEmailSmtpServer) -and
            -not [string]::IsNullOrWhiteSpace($ErrorEmailFrom) -and
            $null -ne $ErrorEmailTo -and
            @($ErrorEmailTo).Count -gt 0) {

            $errorXmlLogPath = Resolve-WtcgXmlLogPath -Path $XmlLogPath

            Send-WtcgErrorNotification `
                -ErrorRecord $_ `
                -SmtpServer $ErrorEmailSmtpServer `
                -Port $ErrorEmailSmtpPort `
                -From $ErrorEmailFrom `
                -To $ErrorEmailTo `
                -Cc $ErrorEmailCc `
                -Subject $ErrorEmailSubject `
                -Operation 'DisableTasksInWindowAndScheduleReenable' `
                -XmlLogPath $errorXmlLogFile.FullName `
                -JsonlLogPath $errorJsonlLogFile.FullName `
                -IdentityOutputPath $IdentityOutputPath `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -UseSsl:$ErrorEmailUseSsl `
                -Credential $ErrorEmailCredential `
                -AttachXmlLog `
                -FailOnEmailError:$FailOnErrorEmail
        }
        throw $wtcgTrapError.Exception.Message
    }


    Import-Module ScheduledTasks -ErrorAction Stop

    $errorMailSettings = Get-WtcgMailSettingsForConfigurationError -SelectionPath $SelectionPath

    $window = Resolve-WtcgWindow -Start $Start -End $End
    $normalizedReenableTaskPath = Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath

    if (-not $DisableLock) {
        $effectiveLockPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
        $runtimeLock = Enter-WtcgRuntimeLock `
            -LockName $LockName `
            -LockPath $effectiveLockPath `
            -TimeoutSeconds $LockTimeoutSeconds `
            -SkipLockFile:$WhatIfPreference `
            -Metadata @{
                Operation = 'DisableTasksInWindowAndScheduleReenable'
                RunId = $RunId
                RunFolderPath = $RunFolderPath
                WindowStart = $window.Start
                WindowEnd = $window.End
                IdentityOutputPath = $IdentityOutputPath
                ReenableAt = $ReenableAt
            }
    }

    $selection = $null
    if (-not [string]::IsNullOrWhiteSpace($SelectionPath)) {
        $selection = Import-WtcgTaskSelection -Path $SelectionPath
    }

    $resultMailSettings = Get-WtcgResultMailSettings -Selection $selection
    $errorMailSettings = Get-WtcgErrorMailSettings -Selection $selection

    Assert-WtcgNoOverlappingScheduledReenableRun `
        -WindowStart $window.Start `
        -WindowEnd $window.End `
        -ReenableAt $ReenableAt `
        -ReenableTaskPath $normalizedReenableTaskPath `
        -ReenableTaskName $ReenableTaskName

    $taskIdentities = @(
        Find-WtcgTaskInWindow `
            -Start $window.Start `
            -End $window.End `
            -TaskPath $TaskPath `
            -TaskName $TaskName `
            -Recurse:$Recurse `
            -IncludeDisabled:$IncludeDisabled `
            -Selection $selection `
            -IdentityOnly
    )

    if ($taskIdentities.Count -eq 0) {
        Write-Host "No tasks found inside $($window.Start) -> $($window.End)."
        $reportFile = Save-WtcgRunReport `
            -RunContext $runContext `
            -Path $ReportPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -Status 'no-matching-tasks' `
            -Details ([ordered]@{
                windowStart = $window.Start.ToString('o')
                windowEnd = $window.End.ToString('o')
                reenableAt = $ReenableAt.ToString('o')
                selectionSource = if ($null -ne $selection) { $selection.SourcePath } else { $null }
            })
        Write-Host "Run report written to: $($reportFile.FullName)"
        Exit-WtcgRuntimeLock -Lock $runtimeLock
        $runtimeLock = $null
        return
    }

    $disabledTaskIdentities = @(
        if ($PSCmdlet.ShouldProcess(
                "$($taskIdentities.Count) task(s)",
                "Disable tasks inside $($window.Start) -> $($window.End)"
            )) {
            $taskIdentities | Disable-WtcgTaskIdentity -Confirm:$false
        }
    )

    $disabledFullNames = @{}
    foreach ($disabledIdentity in $disabledTaskIdentities) {
        $disabledFullNames[$disabledIdentity.FullName] = $disabledIdentity
    }

    $rollbackIdentities = @(
        foreach ($identity in $taskIdentities) {
            if ($disabledFullNames.ContainsKey($identity.FullName)) {
                $disabledFullNames[$identity.FullName]
            }
            else {
                $identity
            }
        }
    )

    $identityFile = $rollbackIdentities |
        Save-WtcgManifest `
            -Path $IdentityOutputPath `
            -WindowStart $window.Start `
            -WindowEnd $window.End `
            -Selection $selection `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath

    Write-Host "Saved rollback manifest to:"
    Write-Host "  $($identityFile.FullName)"

    $xmlLogFile = $rollbackIdentities |
        Write-WtcgDisableXmlLog `
            -Path $XmlLogPath `
            -WindowStart $window.Start `
            -WindowEnd $window.End `
            -ReenableAt $ReenableAt `
            -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
            -IdentityOutputPath $identityFile.FullName `
            -ReenableTaskFullName "$(Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath)$ReenableTaskName" `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable'

    Write-Host "XML disable log written to:"
    Write-Host "  $($xmlLogFile.FullName)"

    $effectiveJsonlLogPath = Resolve-WtcgJsonlLogPath -Path $JsonlLogPath
    if ($disabledTaskIdentities.Count -gt 0) {
        $jsonlLogFile = $disabledTaskIdentities |
            Write-WtcgDisableJsonlLog `
                -Path $effectiveJsonlLogPath `
                -WindowStart $window.Start `
                -WindowEnd $window.End `
                -ReenableAt $ReenableAt `
                -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
                -IdentityOutputPath $identityFile.FullName `
                -ReenableTaskFullName "$(Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath)$ReenableTaskName" `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -Operation 'DisableTasksInWindowAndScheduleReenable'

        Write-Host "JSONL disable log written to:"
        Write-Host "  $($jsonlLogFile.FullName)"
    }
    Write-WtcgAuditEvent `
        -Action 'disable' `
        -Operation 'DisableTasksInWindowAndScheduleReenable' `
        -Status 'succeeded' `
        -EventId 4100 `
        -EntryType 'Information' `
        -Details ([ordered]@{
            matchedTaskCount = $taskIdentities.Count
            disabledTaskCount = $disabledTaskIdentities.Count
            windowStart = $window.Start.ToString('o')
            windowEnd = $window.End.ToString('o')
            reenableAt = $ReenableAt.ToString('o')
            selectionSource = if ($null -ne $selection) { $selection.SourcePath } else { $null }
            identityOutputPath = $identityFile.FullName
            xmlLogPath = $xmlLogFile.FullName
            jsonlLogPath = $effectiveJsonlLogPath
            runFolderPath = $RunFolderPath
            runInfoPath = $runContext.RunInfoPath
            reenableTaskFullName = "$(Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath)$ReenableTaskName"
        }) `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null


    Send-WtcgLogGeneratedNotificationFromSettings `
        -MailSettings $resultMailSettings `
        -XmlLogPath $xmlLogFile.FullName `
        -JsonlLogPath $effectiveJsonlLogPath `
        -IdentityOutputPath $identityFile.FullName `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Operation 'DisableTasksInWindowAndScheduleReenable'


    if (-not [string]::IsNullOrWhiteSpace($LogEmailSmtpServer) -and
        -not [string]::IsNullOrWhiteSpace($LogEmailFrom) -and
        $null -ne $LogEmailTo -and
        @($LogEmailTo).Count -gt 0) {

        Send-WtcgLogGeneratedNotification `
            -SmtpServer $LogEmailSmtpServer `
            -Port $LogEmailSmtpPort `
            -From $LogEmailFrom `
            -To $LogEmailTo `
            -Cc $LogEmailCc `
            -Subject $LogEmailSubject `
            -XmlLogPath $xmlLogFile.FullName `
            -JsonlLogPath $effectiveJsonlLogPath `
            -IdentityOutputPath $identityFile.FullName `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath `
            -Operation 'DisableTasksInWindowAndScheduleReenable' `
            -UseSsl:$LogEmailUseSsl `
            -Credential $LogEmailCredential `
            -AttachXmlLog `
            -FailOnEmailError:$FailOnLogEmailError
    }

    $quotedEnableScriptPath = '"' + $EnableScriptPath + '"'
    $quotedIdentityPath = '"' + $identityFile.FullName + '"'

    $reenableArgumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($argumentPart in @(
            '-NoProfile',
            '-ExecutionPolicy Bypass',
            '-File',
            $quotedEnableScriptPath,
            '-ManifestPath',
            $quotedIdentityPath,
            '-JsonlLogPath',
            ('"' + $effectiveJsonlLogPath + '"'),
            '-RunId',
            ('"' + $RunId + '"'),
            '-RunFolderPath',
            ('"' + $RunFolderPath + '"'),
            '-EventLogSource',
            ('"' + $EventLogSource + '"'),
            '-EventLogName',
            ('"' + $EventLogName + '"')
        )) {
        $reenableArgumentList.Add($argumentPart)
    }

    if ($DisableEventLog) {
        $reenableArgumentList.Add('-DisableEventLog')
    }

    if ($FailOnEventLogError) {
        $reenableArgumentList.Add('-FailOnEventLogError')
    }

    $reenableArguments = $reenableArgumentList -join ' '

    $action = New-ScheduledTaskAction `
        -Execute $PowerShellExePath `
        -Argument $reenableArguments

    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At $ReenableAt

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable

    $principal = New-ScheduledTaskPrincipal `
        -UserId $env:USERNAME `
        -LogonType Interactive `
        -RunLevel Highest

    $existingTask = Get-ScheduledTask `
        -TaskPath $normalizedReenableTaskPath `
        -TaskName $ReenableTaskName `
        -ErrorAction SilentlyContinue

    $reenableScheduleAction = if ($null -eq $existingTask) { 'created' } else { 'updated' }

    if ($null -eq $existingTask) {
        if ($PSCmdlet.ShouldProcess(
                "$normalizedReenableTaskPath$ReenableTaskName",
                "Create re-enable scheduled task for $ReenableAt"
            )) {
            Invoke-WtcgRegisterScheduledTask `
                -TaskPath $normalizedReenableTaskPath `
                -TaskName $ReenableTaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Description "Re-enables tasks disabled by WinTaskCrossingGuard." `
                -Force |
                Out-Null

            Write-Host "Created re-enable task:"
            Write-Host "  $normalizedReenableTaskPath$ReenableTaskName"
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess(
                "$normalizedReenableTaskPath$ReenableTaskName",
                "Update re-enable scheduled task to run at $ReenableAt"
            )) {
            Invoke-WtcgSetScheduledTask `
                -TaskPath $normalizedReenableTaskPath `
                -TaskName $ReenableTaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal |
                Out-Null

            Write-Host "Updated re-enable task execution time:"
            Write-Host "  $normalizedReenableTaskPath$ReenableTaskName"
            Write-Host "  Re-enable at: $ReenableAt"
        }
    }

    Write-WtcgAuditEvent `
        -Action 'scheduled-reenable' `
        -Operation 'DisableTasksInWindowAndScheduleReenable' `
        -Status $reenableScheduleAction `
        -EventId 4101 `
        -EntryType 'Information' `
        -Details ([ordered]@{
            reenableAt = $ReenableAt.ToString('o')
            reenableTaskPath = $normalizedReenableTaskPath
            reenableTaskName = $ReenableTaskName
            reenableTaskFullName = "$normalizedReenableTaskPath$ReenableTaskName"
            identityOutputPath = $identityFile.FullName
            jsonlLogPath = $effectiveJsonlLogPath
            runFolderPath = $RunFolderPath
            actionArguments = $reenableArguments
        }) `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null

    $reportFile = Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $ReportPath `
        -Operation 'DisableTasksInWindowAndScheduleReenable' `
        -Status 'succeeded' `
        -Details ([ordered]@{
            matchedTaskCount = $taskIdentities.Count
            disabledTaskCount = $disabledTaskIdentities.Count
            windowStart = $window.Start.ToString('o')
            windowEnd = $window.End.ToString('o')
            reenableAt = $ReenableAt.ToString('o')
            identityOutputPath = $identityFile.FullName
            xmlLogPath = $xmlLogFile.FullName
            jsonlLogPath = $effectiveJsonlLogPath
            reenableTaskFullName = "$normalizedReenableTaskPath$ReenableTaskName"
        })

    Write-Host "Run report written to:"
    Write-Host "  $($reportFile.FullName)"

    $result = [pscustomobject]@{
        RunId                 = $RunId
        RunFolderPath         = $RunFolderPath
        RunInfoPath           = $runContext.RunInfoPath
        ReportPath            = $reportFile.FullName
        WindowStart           = $window.Start
        WindowEnd             = $window.End
        DisabledTaskCount     = $disabledTaskIdentities.Count
        IdentityOutputPath    = $identityFile.FullName
        XmlLogPath            = $xmlLogFile.FullName
        JsonlLogPath          = $effectiveJsonlLogPath
        ReenableAt            = $ReenableAt
        ReenableTaskPath      = $normalizedReenableTaskPath
        ReenableTaskName      = $ReenableTaskName
        ReenableTaskFullName  = "$normalizedReenableTaskPath$ReenableTaskName"
        Tasks                 = $rollbackIdentities
    }


    Clear-WtcgOldLogs -EnvPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -LogsPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'logs') -WhatIf:$WhatIfPreference
    Clear-WtcgOldLogs -EnvPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -LogsPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'steamablelogs') -Filter '*.jsonl' -WhatIf:$WhatIfPreference

    if ($PassThru) {
        $result
    }

    Exit-WtcgRuntimeLock -Lock $runtimeLock
    $runtimeLock = $null
}

