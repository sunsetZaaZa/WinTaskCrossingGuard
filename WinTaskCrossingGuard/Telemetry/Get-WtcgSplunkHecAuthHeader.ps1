function Get-WtcgSplunkHecAuthHeader {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) { return @{} }
    @{ Authorization = "Splunk $Token" }
}
