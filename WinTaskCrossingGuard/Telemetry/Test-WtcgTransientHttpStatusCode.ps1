function Test-WtcgTransientHttpStatusCode {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $StatusCode
    )

    if ($null -eq $StatusCode) { return $true }
    $numericStatusCode = [int]$StatusCode
    return ($numericStatusCode -eq 408 -or $numericStatusCode -eq 429 -or ($numericStatusCode -ge 500 -and $numericStatusCode -le 599))
}
