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

        try {
            Invoke-WtcgTelemetryExportForJsonl `
                -JsonlPath $errorJsonlLogFile.FullName `
                -RunContext $runContext `
                -Operation 'DisableTasksInWindowAndScheduleReenable' |
                Out-Null
        }
        catch {
            Write-Verbose "Failed to export WinTaskCrossingGuard telemetry events: $($_.Exception.Message)"
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

    $telemetryExportResult = Invoke-WtcgTelemetryExportForJsonl `
        -JsonlPath $effectiveJsonlLogPath `
        -RunContext $runContext `
        -Operation 'DisableTasksInWindowAndScheduleReenable'

    $result = [pscustomobject]@{
        RunId                 = $RunId
        RunFolderPath         = $RunFolderPath
        RunInfoPath           = $runContext.RunInfoPath
        ReportPath            = $reportFile.FullName
        TelemetryExportReportPath = $telemetryExportResult.ReportPath
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
    Clear-WtcgOldLogs -EnvPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -LogsPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'streamablelogs') -Filter '*.jsonl' -WhatIf:$WhatIfPreference

    if ($PassThru) {
        $result
    }

    Exit-WtcgRuntimeLock -Lock $runtimeLock
    $runtimeLock = $null
}
