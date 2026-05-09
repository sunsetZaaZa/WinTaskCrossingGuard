function Get-WtcgResultMailSettings {
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

    $resultMail = Get-WtcgObjectPropertyValue -InputObject $selectionMail -Name 'Result'
    if ($null -ne $resultMail) {
        return $resultMail
    }

    return $selectionMail
}
