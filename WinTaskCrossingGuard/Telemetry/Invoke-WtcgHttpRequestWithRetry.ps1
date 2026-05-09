function Invoke-WtcgHttpRequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter()]
        [ValidateSet('Post', 'Put', 'Patch')]
        [string] $Method = 'Post',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Body,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ContentType = 'application/json; charset=utf-8',

        [Parameter()]
        [AllowNull()]
        [hashtable] $Headers,

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

    $attempt = 0
    $maxAttempts = $RetryCount + 1
    $lastErrorMessage = $null
    $lastStatusCode = $null

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $response = Invoke-WtcgTelemetryRestMethod `
                -Uri $Uri `
                -Method $Method `
                -Body $Body `
                -ContentType $ContentType `
                -Headers $Headers `
                -TimeoutSeconds $TimeoutSeconds `
                -AllowInsecureTls:$AllowInsecureTls

            return [pscustomobject]@{
                Sent             = $true
                Uri              = $Uri
                Method           = $Method
                ContentType      = $ContentType
                AttemptCount     = $attempt
                TimeoutSeconds   = $TimeoutSeconds
                RetryCount       = $RetryCount
                RetryDelaySeconds = $RetryDelaySeconds
                AllowInsecureTls = [bool]$AllowInsecureTls
                HeaderNames      = if ($null -ne $Headers) { @($Headers.Keys) } else { @() }
                Response         = $response
                Error            = $null
                StatusCode       = $null
            }
        }
        catch {
            $lastErrorMessage = $_.Exception.Message
            $lastStatusCode = Get-WtcgHttpErrorStatusCode -ErrorRecord $_
            $shouldRetry = ($attempt -lt $maxAttempts -and (Test-WtcgTransientHttpStatusCode -StatusCode $lastStatusCode))

            if ($shouldRetry) {
                if ($RetryDelaySeconds -gt 0) {
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
                continue
            }

            if ($FailOnError) {
                throw
            }

            return [pscustomobject]@{
                Sent             = $false
                Uri              = $Uri
                Method           = $Method
                ContentType      = $ContentType
                AttemptCount     = $attempt
                TimeoutSeconds   = $TimeoutSeconds
                RetryCount       = $RetryCount
                RetryDelaySeconds = $RetryDelaySeconds
                AllowInsecureTls = [bool]$AllowInsecureTls
                HeaderNames      = if ($null -ne $Headers) { @($Headers.Keys) } else { @() }
                Response         = $null
                Error            = $lastErrorMessage
                StatusCode       = $lastStatusCode
            }
        }
    }
}
