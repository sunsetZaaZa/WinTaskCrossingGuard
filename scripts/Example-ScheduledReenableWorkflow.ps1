#requires -Version 7.0

<#
Example-ScheduledReenableWorkflow.ps1

This is a plain example script.

It shows how to:

1. Import the WinTaskCrossingGuard module
2. Find tasks whose NextRunTime falls inside a time window
3. Disable those tasks
4. Save a rollback manifest with original state and discovery metadata
5. Create or update a separate Windows Scheduled Task that restores only tasks disabled by this suite run

Place this file next to WinTaskCrossingGuard.psm1.
Run with:

pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-ScheduledReenableWorkflow.ps1

Safer first run:

pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-ScheduledReenableWorkflow.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 1. Import the suite module
# ---------------------------------------------------------------------

$modulePath = Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
Import-Module $modulePath -Force

# ---------------------------------------------------------------------
# 2. Configure the disable window and re-enable time
# ---------------------------------------------------------------------

$windowStart = '22:00'
$windowEnd = '06:00'

# Example: re-enable at 6:30 AM tomorrow.
$reenableAt = (Get-Date).Date.AddDays(1).AddHours(6).AddMinutes(30)

$selectionPath = Join-Path $PSScriptRoot 'task-selection.example.json'
$identityOutputPath = Join-Path $PSScriptRoot 'rollback-manifest.json'
$xmlLogPath = Join-Path $PSScriptRoot 'logs\scheduled-reenable-disable-log.xml'

# ---------------------------------------------------------------------
# 3. Find, disable, save identities, and schedule re-enable
# ---------------------------------------------------------------------

$result = Disable-WtcgTasksInWindowAndScheduleReenable `
    -Start $windowStart `
    -End $windowEnd `
    -ReenableAt $reenableAt `
    -SelectionPath $selectionPath `
    -IdentityOutputPath $identityOutputPath `
    -XmlLogPath $xmlLogPath `
    -ReenableTaskPath '\WinTaskCrossingGuard\' `
    -ReenableTaskName 'ReenableDisabledTasks' `
    -WhatIf:$WhatIfPreference `
    -PassThru

if ($null -eq $result) {
    Write-Host "No tasks were disabled and no re-enable task was scheduled."
    return
}

Write-Host ''
Write-Host "Scheduled re-enable workflow:"
Write-Host "  Window start:          $($result.WindowStart)"
Write-Host "  Window end:            $($result.WindowEnd)"
Write-Host "  Disabled task count:   $($result.DisabledTaskCount)"
Write-Host "  Rollback manifest:     $($result.IdentityOutputPath)"
Write-Host "  XML log path:          $($result.XmlLogPath)"
Write-Host "  Re-enable at:          $($result.ReenableAt)"
Write-Host "  Re-enable task:        $($result.ReenableTaskFullName)"
Write-Host ''

Write-Host "Tasks:"
$result.Tasks | Format-Table TaskPath, TaskName, NextRunTime, State -AutoSize
