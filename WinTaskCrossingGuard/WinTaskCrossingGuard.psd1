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
        'Get-WtcgObjectPropertyValue',
        'Resolve-WtcgDateTime',
        'Resolve-WtcgWindow',
        'Test-WtcgDateTimeInWindow',
        'New-WtcgFolderSelection',
        'ConvertTo-WtcgFolderSelection',
        'New-WtcgTaskIdentity',
        'Import-WtcgTaskIdentity',
        'Export-WtcgTaskIdentity',
        'Import-WtcgTaskSelection',
        'Test-WtcgTaskSpecMatch',
        'Test-WtcgTaskFolderSelectionMatch',
        'Get-WtcgDefaultProtectedFolderSelection',
        'Test-WtcgSelectionHasExplicitIncludes',
        'Assert-WtcgSafetyAllowListSatisfied',
        'Test-WtcgTaskProtected',
        'Test-WtcgTaskAllowedBySelection',
        'Get-WtcgScheduledTaskCandidate',
        'Find-WtcgTaskInWindow',
        'Disable-WtcgTaskIdentity',
        'Enable-WtcgTaskIdentity',
        'Start-WtcgTaskIdentity',
        'Save-WtcgManifest',
        'Resolve-WtcgRuntimeLockPath',
        'New-WtcgRuntimeLockName',
        'Save-WtcgRuntimeLockFile',
        'Enter-WtcgRuntimeLock',
        'Exit-WtcgRuntimeLock',
        'New-WtcgRunId',
        'ConvertTo-WtcgSafePathName',
        'Resolve-WtcgRunRootPath',
        'New-WtcgRunContext',
        'Resolve-WtcgRunArtifactPath',
        'Save-WtcgRunReport',
        'Get-WtcgRestoreArtifactSummary',
        'Find-WtcgLatestRestoreArtifact',
        'Import-WtcgRestoreArtifactTaskIdentity',
        'ConvertTo-WtcgNullableDateTime',
        'Test-WtcgDateTimeRangeOverlap',
        'Get-WtcgCommandArgumentValue',
        'Get-WtcgActivePriorReenableRun',
        'Assert-WtcgNoOverlappingScheduledReenableRun',
        'Import-WtcgDotEnv',
        'Get-WtcgLogRetentionDays',
        'Clear-WtcgOldLogs',
        'Resolve-WtcgXmlLogPath',
        'Resolve-WtcgJsonlLogPath',
        'Test-WtcgWindowsPlatform',
        'Initialize-WtcgWindowsEventLogSource',
        'Write-WtcgWindowsEventLog',
        'Write-WtcgAuditEvent',
        'New-WtcgJsonlEvent',
        'Write-WtcgJsonlEvent',
        'Write-WtcgDisableJsonlLog',
        'Write-WtcgReenableJsonlLog',
        'Write-WtcgErrorJsonlLog',
        'Write-WtcgNotificationJsonlLog',
        'Write-WtcgDisableXmlLog',
        'Write-WtcgErrorXmlLog',
        'ConvertTo-WtcgMailSettings',
        'Assert-WtcgMailEventSettings',
        'ConvertTo-WtcgMailEventSettings',
        'Get-WtcgResultMailSettings',
        'Get-WtcgErrorMailSettings',
        'Get-WtcgWebhookSettings',
        'Test-WtcgWebhookTargetReady',
        'New-WtcgWebhookPayload',
        'Send-WtcgWebhookNotification',
        'Send-WtcgWebhookNotificationsFromEnv',
        'Get-WtcgMailSettingsForConfigurationError',
        'Test-WtcgMailSettingsReady',
        'Get-WtcgMailAttachments',
        'Send-WtcgLogGeneratedNotificationFromSettings',
        'Send-WtcgErrorNotificationFromSettings',
        'Send-WtcgMailNotification',
        'New-WtcgLogGeneratedMailBody',
        'New-WtcgErrorMailBody',
        'Send-WtcgLogGeneratedNotification',
        'Send-WtcgErrorNotification',
        'Invoke-WtcgRegisterScheduledTask',
        'Invoke-WtcgSetScheduledTask',
        'Disable-WtcgTasksInWindowAndScheduleReenable'
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
