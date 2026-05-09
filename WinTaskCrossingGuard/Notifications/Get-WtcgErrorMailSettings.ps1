function Get-WtcgErrorMailSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $selectionMail = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'Mail'
    if ($null -eq $selectionMail) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    $errorMail = Get-WtcgObjectPropertyValue -InputObject $selectionMail -Name 'Error'
    if ($null -ne $errorMail) {
        return $errorMail
    }

    return $selectionMail
}
