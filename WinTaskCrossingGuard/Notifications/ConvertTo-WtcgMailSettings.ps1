function ConvertTo-WtcgMailSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    if ($null -eq $Mail) {
        return [pscustomobject]@{
            Enabled            = $false
            SmtpServer         = $null
            Port               = 25
            From               = $null
            To                 = @()
            Cc                 = @()
            UseSsl             = $false
            AttachXmlLog       = $true
            AttachIdentityFile = $false
            FailOnEmailError   = $false
        }
    }

    $enabled = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'enabled' -DefaultValue $false)
    $port = [int](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'port' -DefaultValue 25)
    $useSsl = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'useSsl' -DefaultValue $false)
    $attachXmlLog = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'attachXmlLog' -DefaultValue $true)
    $attachIdentityFile = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'attachIdentityFile' -DefaultValue $false)
    $failOnEmailError = [bool](Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'failOnEmailError' -DefaultValue $false)

    $smtpServer = Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'smtpServer'
    $from = Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'from'
    $to = @(Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'to' -DefaultValue @())
    $cc = @(Get-WtcgObjectPropertyValue -InputObject $Mail -Name 'cc' -DefaultValue @())

    [pscustomobject]@{
        Enabled            = $enabled
        SmtpServer         = if ($null -ne $smtpServer) { [string]$smtpServer } else { $null }
        Port               = $port
        From               = if ($null -ne $from) { [string]$from } else { $null }
        To                 = @($to | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        Cc                 = @($cc | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        UseSsl             = $useSsl
        AttachXmlLog       = $attachXmlLog
        AttachIdentityFile = $attachIdentityFile
        FailOnEmailError   = $failOnEmailError
    }
}
