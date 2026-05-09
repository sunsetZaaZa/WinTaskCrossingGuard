function Get-WtcgWebhookSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
    )

    $envValues = Import-WtcgDotEnv -Path $EnvPath
    $globalEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_WEBHOOKS_ENABLED' -Default $true) -Default $true
    $globalFailOnError = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_WEBHOOK_FAIL_ON_ERROR' -Default $false) -Default $false

    $timeoutSeconds = 15
    $rawTimeout = Get-WtcgEnvValue -Values $envValues -Name 'WTCG_WEBHOOK_TIMEOUT_SECONDS' -Default 15
    if (-not [int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -or $timeoutSeconds -le 0) {
        throw "Invalid WTCG_WEBHOOK_TIMEOUT_SECONDS value '$rawTimeout'. Expected a positive whole number."
    }

    $targets = @(
        ConvertTo-WtcgWebhookTargetSettings -Provider 'teams' -EnvValues $envValues -GlobalEnabled $globalEnabled -DefaultTimeoutSeconds $timeoutSeconds -DefaultFailOnError $globalFailOnError
        ConvertTo-WtcgWebhookTargetSettings -Provider 'slack' -EnvValues $envValues -GlobalEnabled $globalEnabled -DefaultTimeoutSeconds $timeoutSeconds -DefaultFailOnError $globalFailOnError
        ConvertTo-WtcgWebhookTargetSettings -Provider 'discord' -EnvValues $envValues -GlobalEnabled $globalEnabled -DefaultTimeoutSeconds $timeoutSeconds -DefaultFailOnError $globalFailOnError
    )

    [pscustomobject]@{
        Enabled        = $globalEnabled
        EnvPath        = $EnvPath
        TimeoutSeconds = $timeoutSeconds
        FailOnError    = $globalFailOnError
        Targets        = @($targets)
    }
}
