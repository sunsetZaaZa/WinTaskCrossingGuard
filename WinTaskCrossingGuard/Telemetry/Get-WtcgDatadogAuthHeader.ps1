function Get-WtcgDatadogAuthHeader {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ApiKey
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return @{} }
    @{ 'DD-API-KEY' = $ApiKey }
}
