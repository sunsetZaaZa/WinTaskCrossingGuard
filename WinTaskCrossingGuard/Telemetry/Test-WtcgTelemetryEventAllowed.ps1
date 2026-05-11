function Test-WtcgTelemetryEventAllowed {
    [CmdletBinding()]
    param(
        [Parameter()]
        [Alias('Event')]
        [AllowNull()]
        [object] $InputEvent,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents
    )

    if ($null -eq $AllowedEvents -or @($AllowedEvents).Count -eq 0) {
        return $true
    }

    $normalizedAllowedEvents = @($AllowedEvents | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($normalizedAllowedEvents -contains '*' -or $normalizedAllowedEvents -contains 'all') {
        return $true
    }

    $action = ([string](Get-WtcgObjectPropertyValue -InputObject $InputEvent -Name 'action' -DefaultValue '')).ToLowerInvariant()
    $status = ([string](Get-WtcgObjectPropertyValue -InputObject $InputEvent -Name 'status' -DefaultValue '')).ToLowerInvariant()
    $operation = ([string](Get-WtcgObjectPropertyValue -InputObject $InputEvent -Name 'operation' -DefaultValue '')).ToLowerInvariant()

    return (
        (-not [string]::IsNullOrWhiteSpace($action) -and $normalizedAllowedEvents -contains $action) -or
        (-not [string]::IsNullOrWhiteSpace($status) -and $normalizedAllowedEvents -contains $status) -or
        (-not [string]::IsNullOrWhiteSpace($operation) -and $normalizedAllowedEvents -contains $operation)
    )
}
