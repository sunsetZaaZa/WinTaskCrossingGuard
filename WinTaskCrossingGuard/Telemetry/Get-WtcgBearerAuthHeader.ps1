function Get-WtcgBearerAuthHeader {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) { return @{} }
    @{ Authorization = "Bearer $Token" }
}
