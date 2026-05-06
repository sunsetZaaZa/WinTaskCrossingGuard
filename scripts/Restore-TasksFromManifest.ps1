[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

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
    [switch] $PassThru,

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
    [switch] $FailOnEventLogError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

$inferredRunFolderPath = $RunFolderPath
if ([string]::IsNullOrWhiteSpace($inferredRunFolderPath) -and -not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $manifestDirectory = Split-Path -Parent $ManifestPath
    if (-not [string]::IsNullOrWhiteSpace($manifestDirectory) -and (Split-Path -Leaf $manifestDirectory) -eq 'manifests') {
        $inferredRunFolderPath = Split-Path -Parent $manifestDirectory
    }
}

$inferredRunId = $RunId
if ([string]::IsNullOrWhiteSpace($inferredRunId) -and -not [string]::IsNullOrWhiteSpace($inferredRunFolderPath)) {
    $inferredRunId = Split-Path -Leaf $inferredRunFolderPath
}

$runContext = New-WtcgRunContext `
    -RunId $inferredRunId `
    -RunFolderPath $inferredRunFolderPath `
    -Operation 'RestoreTasksFromManifest'

$RunId = $runContext.RunId
$RunFolderPath = $runContext.RunFolderPath

if (-not $PSBoundParameters.ContainsKey('JsonlLogPath') -or [string]::IsNullOrWhiteSpace($JsonlLogPath)) {
    $JsonlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
}

if (-not $PSBoundParameters.ContainsKey('ReportPath') -or [string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Reports' -FileName 'restore-report.json'
}

$effectiveErrorReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'restore-error-report.json'

$runtimeLock = $null
try {
    if (-not $DisableLock) {
        $effectiveLockPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
        $runtimeLock = Enter-WtcgRuntimeLock `
            -LockName $LockName `
            -LockPath $effectiveLockPath `
            -TimeoutSeconds $LockTimeoutSeconds `
            -SkipLockFile:$WhatIfPreference `
            -Metadata @{
                Operation = 'RestoreTasksFromManifest'
                RunId = $RunId
                RunFolderPath = $RunFolderPath
                ManifestPath = $ManifestPath
            }
    }

if (-not (Test-Path -Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

if ($null -eq $manifest.Tasks) {
    throw "Manifest has no Tasks array: $ManifestPath"
}

$identities = @(
    foreach ($task in @($manifest.Tasks)) {
        $wasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $task -Name 'WasOriginallyEnabled' -DefaultValue $true)
        $disabledBySuite = [bool](Get-WtcgObjectPropertyValue -InputObject $task -Name 'DisabledBySuite' -DefaultValue $false)

        if (-not ($wasOriginallyEnabled -and $disabledBySuite)) {
            Write-Verbose "Skipping '$($task.TaskPath)$($task.TaskName)' because it was not disabled by this suite run."
            continue
        }

        New-WtcgTaskIdentity `
            -TaskPath ([string]$task.TaskPath) `
            -TaskName ([string]$task.TaskName) `
            -OriginalState (Get-WtcgObjectPropertyValue -InputObject $task -Name 'OriginalState') `
            -WasOriginallyEnabled $true `
            -DisabledBySuite $true
    }
)

$restored = @()
if ($identities.Count -gt 0) {
    $restored = $identities | Enable-WtcgTaskIdentity -WhatIf:$WhatIfPreference -Confirm:$false
}

if ($restored.Count -gt 0) {
    $restored |
        Write-WtcgReenableJsonlLog `
            -Path $JsonlLogPath `
            -ManifestPath $ManifestPath `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath `
            -Operation 'RestoreTasksFromManifest' |
        Out-Null
}
Write-WtcgAuditEvent `
    -Action 're-enable' `
    -Operation 'RestoreTasksFromManifest' `
    -Status 'succeeded' `
    -EventId 4200 `
    -EntryType 'Information' `
    -Details ([ordered]@{
        manifestPath = $ManifestPath
        candidateTaskCount = $identities.Count
        restoredTaskCount = $restored.Count
        jsonlLogPath = $JsonlLogPath
        runFolderPath = $RunFolderPath
        runInfoPath = $runContext.RunInfoPath
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
    -Operation 'RestoreTasksFromManifest' `
    -Status 'succeeded' `
    -Details ([ordered]@{
        manifestPath = $ManifestPath
        candidateTaskCount = $identities.Count
        restoredTaskCount = $restored.Count
        jsonlLogPath = $JsonlLogPath
    })
Write-Host "Run report written to: $($reportFile.FullName)"

$telemetryExportResult = Invoke-WtcgTelemetryExportForJsonl `
    -JsonlPath $JsonlLogPath `
    -RunContext $runContext `
    -Operation 'RestoreTasksFromManifest'

if ($PassThru) {
    $restored
}
}
catch {
    Write-WtcgErrorJsonlLog `
        -ErrorRecord $_ `
        -Path $JsonlLogPath `
        -Operation 'RestoreTasksFromManifest' `
        -IdentityOutputPath $ManifestPath `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath |
        Out-Null
    Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $effectiveErrorReportPath `
        -Operation 'RestoreTasksFromManifest' `
        -Status 'failed' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            manifestPath = $ManifestPath
            jsonlLogPath = $JsonlLogPath
        }) |
        Out-Null
    Write-WtcgAuditEvent `
        -Action 'error' `
        -Operation 'RestoreTasksFromManifest' `
        -Status 'failed' `
        -EventId 5200 `
        -EntryType 'Error' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            manifestPath = $ManifestPath
            jsonlLogPath = $JsonlLogPath
        }) `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null


    try {
        Invoke-WtcgTelemetryExportForJsonl `
            -JsonlPath $JsonlLogPath `
            -RunContext $runContext `
            -Operation 'RestoreTasksFromManifest' |
            Out-Null
    }
    catch {
        Write-Verbose "Failed to export WinTaskCrossingGuard telemetry events: $($_.Exception.Message)"
    }

    throw
}
finally {
    Exit-WtcgRuntimeLock -Lock $runtimeLock -ErrorAction SilentlyContinue
}
