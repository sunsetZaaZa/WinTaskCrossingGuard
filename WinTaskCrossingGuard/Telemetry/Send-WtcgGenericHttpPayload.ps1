function Send-WtcgGenericHttpPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Body,

        [Parameter()]
        [ValidateSet('Post', 'Put', 'Patch')]
        [string] $Method = 'Post',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ContentType = 'application/json; charset=utf-8',

        [Parameter()]
        [AllowNull()]
        [object] $Headers,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $AuthHeaderName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $AuthHeaderValue,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int] $TimeoutSeconds = 15,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int] $RetryCount = 2,

        [Parameter()]
        [ValidateRange(0, 86400)]
        [int] $RetryDelaySeconds = 2,

        [Parameter()]
        [switch] $AllowInsecureTls,

        [Parameter()]
        [switch] $FailOnError
    )

    $resolvedHeaders = ConvertTo-WtcgHttpHeaderDictionary -Headers $Headers -AuthHeaderName $AuthHeaderName -AuthHeaderValue $AuthHeaderValue

    Invoke-WtcgHttpRequestWithRetry `
        -Uri $Uri `
        -Method $Method `
        -Body $Body `
        -ContentType $ContentType `
        -Headers $resolvedHeaders `
        -TimeoutSeconds $TimeoutSeconds `
        -RetryCount $RetryCount `
        -RetryDelaySeconds $RetryDelaySeconds `
        -AllowInsecureTls:$AllowInsecureTls `
        -FailOnError:$FailOnError
}
