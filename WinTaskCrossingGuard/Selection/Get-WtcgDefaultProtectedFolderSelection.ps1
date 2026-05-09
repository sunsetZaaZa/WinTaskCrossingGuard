function Get-WtcgDefaultProtectedFolderSelection {
    [CmdletBinding()]
    param()

    @(
        '\WinTaskCrossingGuard\'
        '\Microsoft\Windows\TaskScheduler\'
        '\Microsoft\Windows\UpdateOrchestrator\'
        '\Microsoft\Windows\WindowsUpdate\'
        '\Microsoft\Windows\WaaSMedic\'
        '\Microsoft\Windows\Servicing\'
        '\Microsoft\Windows\Windows Defender\'
        '\Microsoft\Windows\BitLocker\'
        '\Microsoft\Windows\CertificateServicesClient\'
        '\Microsoft\Windows\RecoveryEnvironment\'
        '\Microsoft\Windows\Registry\'
        '\Microsoft\Windows\Time Synchronization\'
    ) | ForEach-Object {
        New-WtcgFolderSelection -TaskPath $_ -Recurse $true
    }
}
