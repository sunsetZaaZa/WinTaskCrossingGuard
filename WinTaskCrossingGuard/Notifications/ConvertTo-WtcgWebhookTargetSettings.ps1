function ConvertTo-WtcgWebhookTargetSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('teams', 'slack', 'discord')]
        [string] $Provider,

        [Parameter(Mandatory)]
        [hashtable] $EnvValues,

        [Parameter()]
        [bool] $GlobalEnabled = $true,

        [Parameter()]
        [int] $DefaultTimeoutSeconds = 15,

        [Parameter()]
        [bool] $DefaultFailOnError = $false
    )

    $providerToken = $Provider.ToUpperInvariant()
    $url = [string](Get-WtcgEnvValue -Values $EnvValues -Name "WTCG_WEBHOOK_${providerToken}_URL" -Default '')
    $enabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $EnvValues -Name "WTCG_WEBHOOK_${providerToken}_ENABLED" -Default $false) -Default $false
    $events = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $EnvValues -Name "WTCG_WEBHOOK_${providerToken}_EVENTS" -Default 'result,error') -Default @('result', 'error')
    $failOnError = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $EnvValues -Name "WTCG_WEBHOOK_${providerToken}_FAIL_ON_ERROR" -Default $DefaultFailOnError) -Default $DefaultFailOnError

    $timeoutSeconds = $DefaultTimeoutSeconds
    $rawTimeout = Get-WtcgEnvValue -Values $EnvValues -Name "WTCG_WEBHOOK_${providerToken}_TIMEOUT_SECONDS" -Default $DefaultTimeoutSeconds
    if (-not [int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -or $timeoutSeconds -le 0) {
        throw "Invalid WTCG_WEBHOOK_${providerToken}_TIMEOUT_SECONDS value '$rawTimeout'. Expected a positive whole number."
    }

    [pscustomobject]@{
        Provider       = $Provider
        Enabled        = ($GlobalEnabled -and $enabled)
        Url            = $url
        Events         = @($events | ForEach-Object { $_.ToLowerInvariant() })
        TimeoutSeconds = $timeoutSeconds
        FailOnError    = $failOnError
    }
}
