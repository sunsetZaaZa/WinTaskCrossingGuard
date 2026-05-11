function Get-WtcgElasticAuthHeader {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('None', 'ApiKey', 'Bearer', 'Basic')]
        [string] $AuthType = 'None',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ApiKey,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $BasicUser,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $BasicSecret
    )

    switch ($AuthType) {
        'ApiKey' {
            if ([string]::IsNullOrWhiteSpace($ApiKey)) { return @{} }
            return @{ Authorization = "ApiKey $ApiKey" }
        }
        'Bearer' {
            if ([string]::IsNullOrWhiteSpace($ApiKey)) { return @{} }
            return @{ Authorization = "Bearer $ApiKey" }
        }
        'Basic' {
            if ([string]::IsNullOrWhiteSpace($BasicUser) -or [string]::IsNullOrWhiteSpace($BasicSecret)) { return @{} }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("${BasicUser}:${BasicSecret}")
            return @{ Authorization = ('Basic ' + [Convert]::ToBase64String($bytes)) }
        }
        default { return @{} }
    }
}
