function Send-WtcgErrorNotificationFromSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings,

        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

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
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard error'
    )

    $webhookErrorMessage = if ($null -ne $ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    Send-WtcgWebhookNotificationsFromEnv -NotificationEvent 'error' -Subject $Subject -Operation $Operation -Status 'failed' -RunId $RunId -RunFolderPath $RunFolderPath -XmlLogPath $XmlLogPath -JsonlLogPath $JsonlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $webhookErrorMessage | Out-Null

    if (-not (Test-WtcgMailSettingsReady -MailSettings $MailSettings)) { return }

    try {
        $attachments = Get-WtcgMailAttachments -MailSettings $MailSettings -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath
        $body = New-WtcgErrorMailBody -ErrorRecord $ErrorRecord -Operation $Operation -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath

        $sendResult = Send-WtcgMailNotification -SmtpServer $MailSettings.SmtpServer -Port $MailSettings.Port -From $MailSettings.From -To $MailSettings.To -Cc $MailSettings.Cc -Subject $Subject -Body $body -AttachmentPath $attachments -UseSsl:$MailSettings.UseSsl

        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'sent' -Subject $Subject -To $MailSettings.To -Cc $MailSettings.Cc -SmtpServer $MailSettings.SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        $sendResult
    }
    catch {
        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'failed' -Subject $Subject -To $MailSettings.To -Cc $MailSettings.Cc -SmtpServer $MailSettings.SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $_.Exception.Message -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        Write-Warning "Failed to send WinTaskCrossingGuard error email: $($_.Exception.Message)"
        if ($MailSettings.FailOnEmailError) { throw }
    }
}
