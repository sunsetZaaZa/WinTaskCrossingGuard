#requires -Version 7.0

<#
Example-WinTaskCrossingGuardWorkflow.ps1

This is a plain example script.
It shows how to:

1. Import the WinTaskCrossingGuard module
2. Define a time window
3. Load task selection JSON
4. Find tasks inside the time window
5. Disable those tasks
6. Re-enable those tasks
7. Start those tasks immediately

Place this file next to WinTaskCrossingGuard.psm1.
Run with:

pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-WinTaskCrossingGuardWorkflow.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 1. Import the suite module
# ---------------------------------------------------------------------

$modulePath = Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
Import-Module $modulePath -Force

# ---------------------------------------------------------------------
# 2. Define the time window
# ---------------------------------------------------------------------

# Time-only values are anchored to today.
# If End is earlier than Start, the suite treats the window as overnight.
$windowStart = '22:00'
$windowEnd = '06:00'

$window = Resolve-WtcgWindow `
    -Start $windowStart `
    -End $windowEnd

Write-Host "Window:"
Write-Host "  Start: $($window.Start)"
Write-Host "  End:   $($window.End)"
Write-Host ''

# ---------------------------------------------------------------------
# 3. Load optional SelectionPath JSON
# ---------------------------------------------------------------------

$selectionPath = Join-Path $PSScriptRoot 'task-selection.example.json'

$selection = $null

if (Test-Path -LiteralPath $selectionPath) {
    $selection = Import-WtcgTaskSelection -Path $selectionPath
    Write-Host "Loaded selection file:"
    Write-Host "  $($selection.SourcePath)"
}
else {
    Write-Host "Selection file not found. Continuing without selection JSON:"
    Write-Host "  $selectionPath"
}

Write-Host ''

# ---------------------------------------------------------------------
# 4. Find tasks inside the time window
# ---------------------------------------------------------------------

# -IdentityOnly returns lightweight objects containing:
#   TaskPath
#   TaskName
#   FullName
#   NextRunTime
#   State
$tasksInWindow = @(
    Find-WtcgTaskInWindow `
        -Start $window.Start `
        -End $window.End `
        -Selection $selection `
        -IdentityOnly
)

if ($tasksInWindow.Count -eq 0) {
    Write-Host "No matching tasks found inside the window."
    return
}

Write-Host "Tasks found inside the window:"
$tasksInWindow | Format-Table TaskPath, TaskName, NextRunTime, State -AutoSize

# ---------------------------------------------------------------------
# 5. Save the task identities for later use
# ---------------------------------------------------------------------

$identityOutputPath = Join-Path $PSScriptRoot 'matched-task-identities.json'

$tasksInWindow |
    Export-WtcgTaskIdentity `
        -Path $identityOutputPath `
        -Kind 'WinTaskCrossingGuard.ExampleWorkflow' |
    Out-Null

Write-Host ''
Write-Host "Saved task identities to:"
Write-Host "  $identityOutputPath"
Write-Host ''

# ---------------------------------------------------------------------
# 6. Write an XML log for tasks found and about to be disabled
# ---------------------------------------------------------------------

$xmlLogPath = Join-Path $PSScriptRoot 'logs\disabled-tasks-example.xml'

$xmlLogFile = $tasksInWindow |
    Write-WtcgDisableXmlLog `
        -Path $xmlLogPath `
        -WindowStart $window.Start `
        -WindowEnd $window.End `
        -SelectionSource $(if ($null -ne $selection) { $selection.SourcePath } else { $null }) `
        -IdentityOutputPath $identityOutputPath `
        -Operation 'ExampleWorkflowDisable'

Write-Host ''
Write-Host "XML disable log written to:"
Write-Host "  $($xmlLogFile.FullName)"
Write-Host ''

# ---------------------------------------------------------------------
# 7. Disable the tasks
# ---------------------------------------------------------------------

Write-Host "Disabling tasks..."

$disabledTasks = @(
    $tasksInWindow | Disable-WtcgTaskIdentity
)

Write-Host "Disabled tasks:"
$disabledTasks | Format-Table TaskPath, TaskName -AutoSize

Write-Host ''

# ---------------------------------------------------------------------
# 8. Re-enable the same tasks
# ---------------------------------------------------------------------

Write-Host "Re-enabling tasks..."

$enabledTasks = @(
    $tasksInWindow | Enable-WtcgTaskIdentity
)

Write-Host "Re-enabled tasks:"
$enabledTasks | Format-Table TaskPath, TaskName -AutoSize

Write-Host ''

# ---------------------------------------------------------------------
# 9. Start the same tasks immediately
# ---------------------------------------------------------------------

Write-Host "Starting tasks immediately..."

$startedTasks = @(
    $tasksInWindow | Start-WtcgTaskIdentity
)

Write-Host "Started tasks:"
$startedTasks | Format-Table TaskPath, TaskName -AutoSize

Write-Host ''
Write-Host "Example workflow complete."

<#
Safer first-run variant:

Add -WhatIf to the action calls above:

$tasksInWindow | Disable-WtcgTaskIdentity -WhatIf
$tasksInWindow | Enable-WtcgTaskIdentity -WhatIf
$tasksInWindow | Start-WtcgTaskIdentity -WhatIf
#>
