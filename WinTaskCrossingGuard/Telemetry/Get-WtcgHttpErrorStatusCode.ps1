function Get-WtcgHttpErrorStatusCode {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $ErrorRecord
    )

    $response = Get-WtcgObjectPropertyValue -InputObject (Get-WtcgObjectPropertyValue -InputObject $ErrorRecord -Name 'Exception') -Name 'Response'
    if ($null -eq $response) {
        return $null
    }

    $statusCode = Get-WtcgObjectPropertyValue -InputObject $response -Name 'StatusCode'
    if ($null -eq $statusCode) {
        return $null
    }

    try { return [int]$statusCode }
    catch { return $null }
}
