function Get-WtcgMailAttachments {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath
    )

    $attachments = @()

    if ($null -eq $MailSettings) {
        return $attachments
    }

    if ([bool]$MailSettings.AttachXmlLog -and
        -not [string]::IsNullOrWhiteSpace($XmlLogPath) -and
        (Test-Path -LiteralPath $XmlLogPath)) {
        $attachments += $XmlLogPath
    }

    if ([bool]$MailSettings.AttachIdentityFile -and
        -not [string]::IsNullOrWhiteSpace($IdentityOutputPath) -and
        (Test-Path -LiteralPath $IdentityOutputPath)) {
        $attachments += $IdentityOutputPath
    }

    return $attachments
}
