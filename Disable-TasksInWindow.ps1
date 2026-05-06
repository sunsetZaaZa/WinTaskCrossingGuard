[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $Start,

    [Parameter(Mandatory)]
    [string] $End,

    [Parameter()]
    [string[]] $TaskPath = '\',

    [Parameter()]
    [string[]] $TaskName = '*',

    [Parameter()]
    [string] $SelectionPath,

    [Parameter()]
    [switch] $Recurse,

    [Parameter()]
    [switch] $IncludeDisabled,

    [Parameter()]
    [string] $ManifestPath = (Join-Path $PSScriptRoot ("manifests\disabled-tasks-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))),

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
    [string] $IdentityOutputPath,

    [Parameter()]
    [switch] $ReturnTaskIdentity,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

$runContext = New-WtcgRunContext `
    -RunId $RunId `
    -RunRootPath $RunRootPath `
    -RunFolderPath $RunFolderPath `
    -Operation 'DisableTasksInWindow'

$RunId = $runContext.RunId
$RunFolderPath = $runContext.RunFolderPath

if (-not $PSBoundParameters.ContainsKey('ManifestPath') -or [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Manifests' -FileName 'rollback-manifest.json'
}

if (-not $PSBoundParameters.ContainsKey('IdentityOutputPath') -or [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
    $IdentityOutputPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Identities' -FileName 'matched-window-tasks.json'
}

if (-not $PSBoundParameters.ContainsKey('XmlLogPath') -or [string]::IsNullOrWhiteSpace($XmlLogPath)) {
    $XmlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Logs' -FileName 'disabled-tasks.xml'
}

if (-not $PSBoundParameters.ContainsKey('JsonlLogPath') -or [string]::IsNullOrWhiteSpace($JsonlLogPath)) {
    $JsonlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
}

if (-not $PSBoundParameters.ContainsKey('ReportPath') -or [string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Reports' -FileName 'disable-report.json'
}

$effectiveErrorXmlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'wintaskcrossingguard-error.xml'
$effectiveErrorReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'disable-error-report.json'

# WinTaskCrossingGuard notification try/catch wrapper
try {
$resultMailSettings = ConvertTo-WtcgMailSettings -Mail $null
$errorMailSettings = Get-WtcgMailSettingsForConfigurationError -SelectionPath $SelectionPath
$xmlLogFile = $null
$jsonlLogFile = $null


$window = Resolve-WtcgWindow -Start $Start -End $End

$selection = $null
if (-not [string]::IsNullOrWhiteSpace($SelectionPath)) {
    $selection = Import-WtcgTaskSelection -Path $SelectionPath
    Write-Verbose "Loaded task selection JSON: $($selection.SourcePath)"
}

$resultMailSettings = Get-WtcgResultMailSettings -Selection $selection
$errorMailSettings = Get-WtcgErrorMailSettings -Selection $selection

$matches = @(
    Find-WtcgTaskInWindow `
        -Start $window.Start `
        -End $window.End `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Recurse:$Recurse `
        -IncludeDisabled:$IncludeDisabled `
        -Selection $selection
)

if ($matches.Count -eq 0) {
    Write-Host "No enabled scheduled tasks have NextRunTime inside $($window.Start) -> $($window.End) after selection filtering."
    $reportFile = Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $ReportPath `
        -Operation 'DisableTasksInWindow' `
        -Status 'no-matching-tasks' `
        -Details ([ordered]@{
            windowStart = $window.Start.ToString('o')
            windowEnd = $window.End.ToString('o')
            selectionSource = if ($null -ne $selection) { $selection.SourcePath } else { $null }
        })
    Write-Host "Run report written to: $($reportFile.FullName)"
    return
}

$taskIdentities = @(
    $matches | ForEach-Object {
        New-WtcgTaskIdentity `
            -TaskPath $_.TaskPath `
            -TaskName $_.TaskName `
            -NextRunTime $_.NextRunTime `
            -State ([string]$_.State) `
            -OriginalState ([string]$_.State) `
            -WasOriginallyEnabled ([string]$_.State -ne 'Disabled') `
            -LastRunTime $_.LastRunTime `
            -LastTaskResult $_.LastTaskResult `
            -Author (Get-WtcgObjectPropertyValue -InputObject $_ -Name 'Author') `
            -Description (Get-WtcgObjectPropertyValue -InputObject $_ -Name 'Description')
    }
)

$disabledTaskIdentities = @(
    $taskIdentities | Disable-WtcgTaskIdentity -WhatIf:$WhatIfPreference -Confirm:$false
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

$manifestFile = $rollbackIdentities |
    Save-WtcgManifest -Path $ManifestPath -WindowStart $window.Start -WindowEnd $window.End -Selection $selection -RunId $RunId -RunFolderPath $RunFolderPath

Write-Host "Matched $($matches.Count) task(s). Rollback manifest written to: $($manifestFile.FullName)"

$xmlLogFile = $rollbackIdentities |
    Write-WtcgDisableXmlLog `
        -Path $XmlLogPath `
        -WindowStart $window.Start `
        -WindowEnd $window.End `
        -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
        -IdentityOutputPath $manifestFile.FullName `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Operation 'DisableTasksInWindow'

Write-Host "XML disable log written to: $($xmlLogFile.FullName)"

$effectiveJsonlLogPath = Resolve-WtcgJsonlLogPath -Path $JsonlLogPath
if ($disabledTaskIdentities.Count -gt 0) {
    $jsonlLogFile = $disabledTaskIdentities |
        Write-WtcgDisableJsonlLog `
            -Path $effectiveJsonlLogPath `
            -WindowStart $window.Start `
            -WindowEnd $window.End `
            -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
            -IdentityOutputPath $manifestFile.FullName `
            -RunId $RunId `
            -RunFolderPath $RunFolderPath `
            -Operation 'DisableTasksInWindow'

    Write-Host "JSONL disable log written to: $($jsonlLogFile.FullName)"
}
Write-WtcgAuditEvent `
    -Action 'disable' `
    -Operation 'DisableTasksInWindow' `
    -Status 'succeeded' `
    -EventId 4100 `
    -EntryType 'Information' `
    -Details ([ordered]@{
        matchedTaskCount = $matches.Count
        disabledTaskCount = $disabledTaskIdentities.Count
        windowStart = $window.Start.ToString('o')
        windowEnd = $window.End.ToString('o')
        selectionSource = if ($null -ne $selection) { $selection.SourcePath } else { $null }
        manifestPath = $manifestFile.FullName
        identityOutputPath = $IdentityOutputPath
        xmlLogPath = $xmlLogFile.FullName
        jsonlLogPath = $effectiveJsonlLogPath
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


Send-WtcgLogGeneratedNotificationFromSettings `
    -MailSettings $resultMailSettings `
    -XmlLogPath $xmlLogFile.FullName `
    -JsonlLogPath $effectiveJsonlLogPath `
    -IdentityOutputPath $manifestFile.FullName `
    -RunId $RunId `
    -RunFolderPath $RunFolderPath `
    -Operation 'DisableTasksInWindow'


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
        -IdentityOutputPath $manifestFile.FullName `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Operation 'DisableTasksInWindow' `
        -UseSsl:$LogEmailUseSsl `
        -Credential $LogEmailCredential `
        -AttachXmlLog `
        -FailOnEmailError:$FailOnLogEmailError
}

if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
    $identityFile = $rollbackIdentities |
        Export-WtcgTaskIdentity -Path $IdentityOutputPath -Kind 'WinTaskCrossingGuard.MatchedWindowTasks' -RunId $RunId -RunFolderPath $RunFolderPath

    Write-Host "Task identity list written to: $($identityFile.FullName)"
}

$reportFile = Save-WtcgRunReport `
    -RunContext $runContext `
    -Path $ReportPath `
    -Operation 'DisableTasksInWindow' `
    -Status 'succeeded' `
    -Details ([ordered]@{
        matchedTaskCount = $matches.Count
        disabledTaskCount = $disabledTaskIdentities.Count
        windowStart = $window.Start.ToString('o')
        windowEnd = $window.End.ToString('o')
        manifestPath = $manifestFile.FullName
        identityOutputPath = $IdentityOutputPath
        xmlLogPath = $xmlLogFile.FullName
        jsonlLogPath = $effectiveJsonlLogPath
    })
Write-Host "Run report written to: $($reportFile.FullName)"

$telemetryExportResult = Invoke-WtcgTelemetryExportForJsonl `
    -JsonlPath $effectiveJsonlLogPath `
    -RunContext $runContext `
    -Operation 'DisableTasksInWindow'

Clear-WtcgOldLogs -EnvPath (Join-Path $PSScriptRoot '.env') -LogsPath (Join-Path $PSScriptRoot 'logs') -WhatIf:$WhatIfPreference
Clear-WtcgOldLogs -EnvPath (Join-Path $PSScriptRoot '.env') -LogsPath (Join-Path $PSScriptRoot 'steamablelogs') -Filter '*.jsonl' -WhatIf:$WhatIfPreference

if ($ReturnTaskIdentity -or $PassThru) {
    $rollbackIdentities
}

}
catch {
    Write-Host "WinTaskCrossingGuard error: $($_.Exception.Message)" -ForegroundColor Red

    $errorXmlLogFile = Write-WtcgErrorXmlLog `
        -ErrorRecord $_ `
        -Path $effectiveErrorXmlLogPath `
        -Operation 'DisableTasksInWindow' `
        -SelectionSource $SelectionPath `
        -IdentityOutputPath $ManifestPath `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath

    Write-Host "XML error log written to: $($errorXmlLogFile.FullName)" -ForegroundColor Yellow

    $errorJsonlLogFile = Write-WtcgErrorJsonlLog `
        -ErrorRecord $_ `
        -Path $JsonlLogPath `
        -Operation 'DisableTasksInWindow' `
        -SelectionSource $SelectionPath `
        -IdentityOutputPath $ManifestPath `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath

    Write-Host "JSONL error log written to: $($errorJsonlLogFile.FullName)" -ForegroundColor Yellow

    Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $effectiveErrorReportPath `
        -Operation 'DisableTasksInWindow' `
        -Status 'failed' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            selectionSource = $SelectionPath
            manifestPath = $ManifestPath
            xmlLogPath = if ($null -ne $errorXmlLogFile) { $errorXmlLogFile.FullName } else { $null }
            jsonlLogPath = if ($null -ne $errorJsonlLogFile) { $errorJsonlLogFile.FullName } else { $null }
        }) |
        Out-Null

    Write-WtcgAuditEvent `
        -Action 'error' `
        -Operation 'DisableTasksInWindow' `
        -Status 'failed' `
        -EventId 5100 `
        -EntryType 'Error' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            selectionSource = $SelectionPath
            manifestPath = $ManifestPath
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
            -Operation 'DisableTasksInWindow' `
            -XmlLogPath $errorXmlLogFile.FullName `
            -JsonlLogPath $errorJsonlLogFile.FullName `
            -IdentityOutputPath $ManifestPath `
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
            -Operation 'DisableTasksInWindow' `
            -XmlLogPath $errorXmlLogFile.FullName `
            -JsonlLogPath $errorJsonlLogFile.FullName `
            -IdentityOutputPath $ManifestPath `
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
            -Operation 'DisableTasksInWindow' |
            Out-Null
    }
    catch {
        Write-Verbose "Failed to export WinTaskCrossingGuard telemetry events: $($_.Exception.Message)"
    }

    throw
}

