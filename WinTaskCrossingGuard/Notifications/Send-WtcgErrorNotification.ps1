function Send-WtcgErrorNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter(Mandatory)]
        [string] $SmtpServer,

        [Parameter()]
        [int] $Port = 25,

        [Parameter(Mandatory)]
        [string] $From,

        [Parameter(Mandatory)]
        [string[]] $To,

        [Parameter()]
        [string[]] $Cc,

        [Parameter()]
        [string] $Subject = 'WinTaskCrossingGuard error',

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
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential,

        [Parameter()]
        [switch] $AttachXmlLog = $true,

        [Parameter()]
        [switch] $FailOnEmailError
    )

    $webhookErrorMessage = if ($null -ne $ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    Send-WtcgWebhookNotificationsFromEnv -NotificationEvent 'error' -Subject $Subject -Operation $Operation -Status 'failed' -RunId $RunId -RunFolderPath $RunFolderPath -XmlLogPath $XmlLogPath -JsonlLogPath $JsonlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $webhookErrorMessage | Out-Null

    try {
        $attachments = @()
        if ($AttachXmlLog -and -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and (Test-Path -LiteralPath $XmlLogPath)) { $attachments += $XmlLogPath }

        $body = New-WtcgErrorMailBody -ErrorRecord $ErrorRecord -Operation $Operation -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath
        $sendResult = Send-WtcgMailNotification -SmtpServer $SmtpServer -Port $Port -From $From -To $To -Cc $Cc -Subject $Subject -Body $body -AttachmentPath $attachments -UseSsl:$UseSsl -Credential $Credential

        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'sent' -Subject $Subject -To $To -Cc $Cc -SmtpServer $SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        $sendResult
    }
    catch {
        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'failed' -Subject $Subject -To $To -Cc $Cc -SmtpServer $SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $_.Exception.Message -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        Write-Warning "Failed to send WinTaskCrossingGuard error email: $($_.Exception.Message)"
        if ($FailOnEmailError) { throw }
    }
}
