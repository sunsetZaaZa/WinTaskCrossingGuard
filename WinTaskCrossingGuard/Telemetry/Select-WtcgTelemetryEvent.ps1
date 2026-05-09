function Select-WtcgTelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object[]] $Event,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents
    )

    process {
        foreach ($entry in @($Event)) {
            if ($null -ne $entry -and (Test-WtcgTelemetryEventAllowed -Event $entry -AllowedEvents $AllowedEvents)) {
                $entry
            }
        }
    }
}
