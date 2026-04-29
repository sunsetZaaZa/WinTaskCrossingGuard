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
    [string] $RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

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
            -Operation 'RestoreTasksFromManifest' |
        Out-Null
}

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
        -RunId $RunId |
        Out-Null

    throw
}
finally {
    Exit-WtcgRuntimeLock -Lock $runtimeLock -ErrorAction SilentlyContinue
}
