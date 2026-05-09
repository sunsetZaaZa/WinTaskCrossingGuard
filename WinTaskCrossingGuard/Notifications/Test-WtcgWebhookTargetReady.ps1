function Test-WtcgWebhookTargetReady {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Target,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $NotificationEvent
    )

    if ($null -eq $Target) { return $false }
    if (-not [bool](Get-WtcgObjectPropertyValue -InputObject $Target -Name 'Enabled' -DefaultValue $false)) { return $false }

    $url = [string](Get-WtcgObjectPropertyValue -InputObject $Target -Name 'Url')
    if ([string]::IsNullOrWhiteSpace($url)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($NotificationEvent)) {
        $events = @(Get-WtcgObjectPropertyValue -InputObject $Target -Name 'Events' -DefaultValue @('result', 'error'))
        $eventNames = @($events | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ($events.Count -gt 0 -and $eventNames -notcontains $NotificationEvent.ToLowerInvariant()) {
            return $false
        }
    }

    return $true
}
