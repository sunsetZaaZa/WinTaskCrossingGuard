[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

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

trap {
    Write-WtcgErrorJsonlLog `
        -ErrorRecord $_ `
        -Path $JsonlLogPath `
        -Operation 'RestoreTasksFromManifest' `
        -IdentityOutputPath $ManifestPath `
        -RunId $RunId |
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
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null


    throw
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
    }) `
    -RunId $RunId `
    -EventLogSource $EventLogSource `
    -EventLogName $EventLogName `
    -DisableEventLog:$DisableEventLog `
    -FailOnEventLogError:$FailOnEventLogError |
    Out-Null


if ($PassThru) {
    $restored
}
