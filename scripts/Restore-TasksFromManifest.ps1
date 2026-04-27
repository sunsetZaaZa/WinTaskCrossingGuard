[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

if (-not (Test-Path -Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

if ($null -eq $manifest.Tasks) {
    throw "Manifest has no Tasks array: $ManifestPath"
}

$identities = @(
    foreach ($task in @($manifest.Tasks)) {
        New-WtcgTaskIdentity -TaskPath ([string]$task.TaskPath) -TaskName ([string]$task.TaskName)
    }
)

$restored = $identities | Enable-WtcgTaskIdentity -WhatIf:$WhatIfPreference -Confirm:$false

if ($PassThru) {
    $restored
}
