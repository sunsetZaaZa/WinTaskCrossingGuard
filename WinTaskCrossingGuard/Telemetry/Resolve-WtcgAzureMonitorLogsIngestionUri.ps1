function Resolve-WtcgAzureMonitorLogsIngestionUri {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Uri,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Endpoint,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $DataCollectionRuleId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $StreamName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ApiVersion = '2023-01-01'
    )

    if (-not [string]::IsNullOrWhiteSpace($Uri)) {
        try {
            $builder = [System.UriBuilder]::new($Uri.Trim())
            if ([string]::IsNullOrWhiteSpace($builder.Query)) { $builder.Query = "api-version=$ApiVersion" }
            return $builder.Uri.AbsoluteUri
        }
        catch { return $Uri }
    }

    if ([string]::IsNullOrWhiteSpace($Endpoint) -or [string]::IsNullOrWhiteSpace($DataCollectionRuleId) -or [string]::IsNullOrWhiteSpace($StreamName)) {
        return $null
    }

    $base = $Endpoint.Trim().TrimEnd('/')
    '{0}/dataCollectionRules/{1}/streams/{2}?api-version={3}' -f $base, $DataCollectionRuleId, $StreamName, $ApiVersion
}
