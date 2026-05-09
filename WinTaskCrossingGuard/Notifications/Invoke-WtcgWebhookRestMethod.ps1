function Invoke-WtcgWebhookRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $Body,

        [Parameter()]
        [int] $TimeoutSeconds = 15
    )

    Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json; charset=utf-8' -Body $Body -TimeoutSec $TimeoutSeconds
}
