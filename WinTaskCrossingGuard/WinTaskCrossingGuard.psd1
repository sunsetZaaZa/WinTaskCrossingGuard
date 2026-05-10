@{
    RootModule = 'WinTaskCrossingGuard.psm1'
    ModuleVersion = '1.0.0'
    GUID = '0d666ab2-3479-49b8-b6a7-4784a3ba2615'
    Author = 'WinTaskCrossingGuard contributors'
    CompanyName = 'WinTaskCrossingGuard contributors'
    Copyright = '(c) 2026 WinTaskCrossingGuard contributors. Licensed under 0BSD.'
    Description = 'PowerShell module for safely finding, disabling, logging, re-enabling, and auditing Windows Scheduled Tasks inside configured maintenance windows.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Disable-WtcgTaskIdentity',
        'Disable-WtcgTasksInWindowAndScheduleReenable',
        'Enable-WtcgTaskIdentity',
        'Find-WtcgTaskInWindow',
        'Save-WtcgManifest',
        'Start-WtcgTaskIdentity'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'ScheduledTasks', 'Maintenance', 'Automation', 'Pester')
            LicenseUri = 'https://spdx.org/licenses/0BSD.html'
            ProjectUri = 'https://example.invalid/WinTaskCrossingGuard'
            ReleaseNotes = 'Packaged as a PowerShell module with manifest.'
        }
    }
}
