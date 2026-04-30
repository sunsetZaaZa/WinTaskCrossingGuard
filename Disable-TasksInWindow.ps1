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
    [string] $ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) ("manifests\disabled-tasks-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))),

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $XmlLogPath,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $JsonlLogPath,

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

Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

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
    Save-WtcgManifest -Path $ManifestPath -WindowStart $window.Start -WindowEnd $window.End -Selection $selection

Write-Host "Matched $($matches.Count) task(s). Rollback manifest written to: $($manifestFile.FullName)"

$xmlLogFile = $rollbackIdentities |
    Write-WtcgDisableXmlLog `
        -Path $XmlLogPath `
        -WindowStart $window.Start `
        -WindowEnd $window.End `
        -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
        -IdentityOutputPath $manifestFile.FullName `
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
            -Operation 'DisableTasksInWindow'

    Write-Host "JSONL disable log written to: $($jsonlLogFile.FullName)"
}

Send-WtcgLogGeneratedNotificationFromSettings `
    -MailSettings $resultMailSettings `
    -XmlLogPath $xmlLogFile.FullName `
    -JsonlLogPath $effectiveJsonlLogPath `
    -IdentityOutputPath $manifestFile.FullName `
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
        -Operation 'DisableTasksInWindow' `
        -UseSsl:$LogEmailUseSsl `
        -Credential $LogEmailCredential `
        -AttachXmlLog `
        -FailOnEmailError:$FailOnLogEmailError
}

if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
    $identityFile = $rollbackIdentities |
        Export-WtcgTaskIdentity -Path $IdentityOutputPath -Kind 'WinTaskCrossingGuard.MatchedWindowTasks'

    Write-Host "Task identity list written to: $($identityFile.FullName)"
}

Clear-WtcgOldLogs -EnvPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -LogsPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'logs') -WhatIf:$WhatIfPreference
Clear-WtcgOldLogs -EnvPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -LogsPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'steamablelogs') -Filter '*.jsonl' -WhatIf:$WhatIfPreference

if ($ReturnTaskIdentity -or $PassThru) {
    $rollbackIdentities
}

}
catch {
    Write-Host "WinTaskCrossingGuard error: $($_.Exception.Message)" -ForegroundColor Red

    $errorXmlLogFile = Write-WtcgErrorXmlLog `
        -ErrorRecord $_ `
        -Path $XmlLogPath `
        -Operation 'DisableTasksInWindow' `
        -SelectionSource $SelectionPath `
        -IdentityOutputPath $ManifestPath

    Write-Host "XML error log written to: $($errorXmlLogFile.FullName)" -ForegroundColor Yellow

    $errorJsonlLogFile = Write-WtcgErrorJsonlLog `
        -ErrorRecord $_ `
        -Path $JsonlLogPath `
        -Operation 'DisableTasksInWindow' `
        -SelectionSource $SelectionPath `
        -IdentityOutputPath $ManifestPath

    Write-Host "JSONL error log written to: $($errorJsonlLogFile.FullName)" -ForegroundColor Yellow

    if ($null -ne $errorMailSettings -and (Test-WtcgMailSettingsReady -MailSettings $errorMailSettings)) {
        $errorXmlLogPath = Resolve-WtcgXmlLogPath -Path $XmlLogPath

        Send-WtcgErrorNotificationFromSettings `
            -MailSettings $errorMailSettings `
            -ErrorRecord $_ `
            -Operation 'DisableTasksInWindow' `
            -XmlLogPath $errorXmlLogFile.FullName `
            -JsonlLogPath $errorJsonlLogFile.FullName `
            -IdentityOutputPath $ManifestPath
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
            -UseSsl:$ErrorEmailUseSsl `
            -Credential $ErrorEmailCredential `
            -AttachXmlLog `
            -FailOnEmailError:$FailOnErrorEmail
    }

    throw
}

