function Select-WtcgTelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('Event')]
        [AllowNull()]
        [object[]] $InputEvent,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents
    )

    process {
        foreach ($entry in @($InputEvent)) {
            if ($null -ne $entry -and (Test-WtcgTelemetryEventAllowed -InputEvent $entry -AllowedEvents $AllowedEvents)) {
                $entry
            }
        }
    }
}
