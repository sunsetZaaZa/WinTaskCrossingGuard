function Send-WtcgMailNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SmtpServer,

        [Parameter()]
        [int] $Port = 25,

        [Parameter(Mandatory)]
        [string] $From,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $To,

        [Parameter()]
        [string[]] $Cc,

        [Parameter(Mandatory)]
        [string] $Subject,

        [Parameter(Mandatory)]
        [string] $Body,

        [Parameter()]
        [string[]] $AttachmentPath,

        [Parameter()]
        [switch] $UseSsl,

        [Parameter()]
        [pscredential] $Credential
    )

    $message = [System.Net.Mail.MailMessage]::new()
    $smtp = $null

    try {
        $message.From = $From

        foreach ($recipient in @($To)) {
            if (-not [string]::IsNullOrWhiteSpace($recipient)) {
                [void] $message.To.Add($recipient)
            }
        }

        foreach ($recipient in @($Cc)) {
            if (-not [string]::IsNullOrWhiteSpace($recipient)) {
                [void] $message.CC.Add($recipient)
            }
        }

        if ($message.To.Count -eq 0) {
            throw "At least one email recipient is required."
        }

        $message.Subject = $Subject
        $message.Body = $Body
        $message.IsBodyHtml = $false

        foreach ($path in @($AttachmentPath)) {
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                if (-not (Test-Path -LiteralPath $path)) {
                    throw "Attachment not found: $path"
                }

                $attachment = [System.Net.Mail.Attachment]::new($path)
                [void] $message.Attachments.Add($attachment)
            }
        }

        $smtp = [System.Net.Mail.SmtpClient]::new($SmtpServer, $Port)
        $smtp.EnableSsl = [bool] $UseSsl

        if ($null -ne $Credential) {
            $smtp.Credentials = $Credential.GetNetworkCredential()
        }
        else {
            $smtp.UseDefaultCredentials = $true
        }

        $smtp.Send($message)

        [pscustomobject]@{
            Sent        = $true
            SmtpServer  = $SmtpServer
            Port        = $Port
            From        = $From
            To          = $To
            Cc          = $Cc
            Subject     = $Subject
            Attachments = @($AttachmentPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    finally {
        if ($null -ne $message) {
            $message.Dispose()
        }

        if ($null -ne $smtp) {
            $smtp.Dispose()
        }
    }
}
