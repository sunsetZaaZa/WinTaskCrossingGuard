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
        [string] $Username,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Password
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
            if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) { return @{} }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("${Username}:${Password}")
            return @{ Authorization = ('Basic ' + [Convert]::ToBase64String($bytes)) }
        }
        default { return @{} }
    }
}
