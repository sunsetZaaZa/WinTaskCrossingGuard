function Send-WtcgWebhookNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Target,

        [Parameter(Mandatory)]
        [string] $Text
    )

    $provider = [string](Get-WtcgObjectPropertyValue -InputObject $Target -Name 'Provider')
    $url = [string](Get-WtcgObjectPropertyValue -InputObject $Target -Name 'Url')
    $timeoutSeconds = [int](Get-WtcgObjectPropertyValue -InputObject $Target -Name 'TimeoutSeconds' -DefaultValue 15)

    if ([string]::IsNullOrWhiteSpace($provider)) { throw 'Webhook target provider cannot be empty.' }
    if ([string]::IsNullOrWhiteSpace($url)) { throw "Webhook target '$provider' URL cannot be empty." }

    $payload = New-WtcgWebhookPayload -Provider $provider -Text $Text
    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-WtcgWebhookRestMethod -Uri $url -Body $json -TimeoutSeconds $timeoutSeconds

    [pscustomobject]@{
        Sent           = $true
        Provider       = $provider
        Url            = $url
        TimeoutSeconds = $timeoutSeconds
        Payload        = $payload
        Response       = $response
    }
}
