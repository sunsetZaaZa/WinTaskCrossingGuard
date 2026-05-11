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
    $urlName = 'WTCG_WEBHOOK_{0}_URL' -f $providerToken
    $enabledName = 'WTCG_WEBHOOK_{0}_ENABLED' -f $providerToken
    $eventsName = 'WTCG_WEBHOOK_{0}_EVENTS' -f $providerToken
    $failOnErrorName = 'WTCG_WEBHOOK_{0}_FAIL_ON_ERROR' -f $providerToken
    $timeoutName = 'WTCG_WEBHOOK_{0}_TIMEOUT_SECONDS' -f $providerToken

    $url = [string](Get-WtcgEnvValue -Values $EnvValues -Name $urlName -Default '')
    $enabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $EnvValues -Name $enabledName -Default $false) -Default $false
    $events = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $EnvValues -Name $eventsName -Default 'result,error') -Default @('result', 'error')
    $failOnError = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $EnvValues -Name $failOnErrorName -Default $DefaultFailOnError) -Default $DefaultFailOnError

    $timeoutSeconds = $DefaultTimeoutSeconds
    $rawTimeout = Get-WtcgEnvValue -Values $EnvValues -Name $timeoutName -Default $DefaultTimeoutSeconds
    if (-not [int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -or $timeoutSeconds -le 0) {
        throw "Invalid $timeoutName value '$rawTimeout'. Expected a positive whole number."
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
