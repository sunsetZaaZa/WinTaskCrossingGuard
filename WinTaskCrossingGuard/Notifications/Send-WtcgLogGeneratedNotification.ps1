function Send-WtcgLogGeneratedNotification {
    [CmdletBinding()]
    param(
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
        [string] $Subject = 'WinTaskCrossingGuard XML log generated',

        [Parameter(Mandatory)]
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
        [string] $Operation = 'WinTaskCrossingGuard log generated',

        [Parameter()]
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential,

        [Parameter()]
        [switch] $AttachXmlLog = $true,

        [Parameter()]
        [switch] $FailOnEmailError
    )

    Send-WtcgWebhookNotificationsFromEnv -NotificationEvent 'result' -Subject $Subject -Operation $Operation -Status 'sent' -RunId $RunId -RunFolderPath $RunFolderPath -XmlLogPath $XmlLogPath -JsonlLogPath $JsonlLogPath -IdentityOutputPath $IdentityOutputPath | Out-Null

    try {
        $attachments = @()
        if ($AttachXmlLog -and -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and (Test-Path -LiteralPath $XmlLogPath)) { $attachments += $XmlLogPath }

        $body = New-WtcgLogGeneratedMailBody -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -Operation $Operation -RunId $RunId -RunFolderPath $RunFolderPath
        $sendResult = Send-WtcgMailNotification -SmtpServer $SmtpServer -Port $Port -From $From -To $To -Cc $Cc -Subject $Subject -Body $body -AttachmentPath $attachments -UseSsl:$UseSsl -Credential $Credential

        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'sent' -Subject $Subject -To $To -Cc $Cc -SmtpServer $SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        $sendResult
    }
    catch {
        try { Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'failed' -Subject $Subject -To $To -Cc $Cc -SmtpServer $SmtpServer -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $_.Exception.Message -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null }
        catch { Write-Verbose "Failed to write WinTaskCrossingGuard notification JSONL event: $($_.Exception.Message)" }

        Write-Warning "Failed to send WinTaskCrossingGuard log-generated email: $($_.Exception.Message)"
        if ($FailOnEmailError) { throw }
    }
}
