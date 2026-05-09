function Test-WtcgMailSettingsReady {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $MailSettings
    )

    if ($null -eq $MailSettings) {
        return $false
    }

    $enabled = [bool](Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'Enabled' -DefaultValue $false)
    $smtpServer = Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'SmtpServer'
    $from = Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'From'
    $to = @(Get-WtcgObjectPropertyValue -InputObject $MailSettings -Name 'To' -DefaultValue @())

    return (
        $enabled -and
        -not [string]::IsNullOrWhiteSpace([string]$smtpServer) -and
        -not [string]::IsNullOrWhiteSpace([string]$from) -and
        $to.Count -gt 0
    )
}
