function ConvertTo-WtcgTelemetryExportResultSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SinkName,

        [Parameter()]
        [AllowNull()]
        [object] $Result,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Uri,

        [Parameter()]
        [int] $EventCount = 0,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorMessage
    )

    $safeUri = $null
    if (-not [string]::IsNullOrWhiteSpace($Uri)) {
        try {
            $builder = [System.UriBuilder]::new($Uri)
            $builder.Query = $null
            $safeUri = $builder.Uri.AbsoluteUri
        }
        catch {
            $safeUri = '[invalid-uri]'
        }
    }

    $sent = if ($null -ne $Result) { [bool](Get-WtcgObjectPropertyValue -InputObject $Result -Name 'Sent' -DefaultValue $false) } else { $false }
    $attemptCount = if ($null -ne $Result) { Get-WtcgObjectPropertyValue -InputObject $Result -Name 'AttemptCount' } else { $null }
    $statusCode = if ($null -ne $Result) { Get-WtcgObjectPropertyValue -InputObject $Result -Name 'StatusCode' } else { $null }
    $resultError = if ($null -ne $Result) { Get-WtcgObjectPropertyValue -InputObject $Result -Name 'Error' } else { $null }

    [pscustomobject]@{
        SinkName     = $SinkName
        Sent         = $sent
        EventCount   = $EventCount
        Uri          = $safeUri
        AttemptCount = $attemptCount
        StatusCode   = $statusCode
        Error        = if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) { $ErrorMessage } else { $resultError }
        HeaderNames  = if ($null -ne $Result) { @(Get-WtcgObjectPropertyValue -InputObject $Result -Name 'HeaderNames' -DefaultValue @()) } else { @() }
    }
}
