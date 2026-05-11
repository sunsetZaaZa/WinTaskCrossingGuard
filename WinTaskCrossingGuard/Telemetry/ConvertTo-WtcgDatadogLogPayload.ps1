function ConvertTo-WtcgDatadogLogPayload {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('Event')]
        [AllowNull()]
        [object[]] $InputEvent,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlPath,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Service = 'wintaskcrossingguard',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Source = 'powershell',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Tags = 'tool:wintaskcrossingguard'
    )

    begin {
        $events = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in @($InputEvent)) {
            if ($null -ne $entry -and (Test-WtcgTelemetryEventAllowed -InputEvent $entry -AllowedEvents $AllowedEvents)) {
                $events.Add($entry)
            }
        }
    }

    end {
        if (-not [string]::IsNullOrWhiteSpace($JsonlPath)) {
            foreach ($entry in Import-WtcgJsonlEvent -Path $JsonlPath | Select-WtcgTelemetryEvent -AllowedEvents $AllowedEvents) {
                if ($null -ne $entry) { $events.Add($entry) }
            }
        }

        $logs = foreach ($entry in $events) {
            $hostName = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'hostName'
            $runId = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'runId'
            $action = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'action'
            $status = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'status'
            $operation = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'operation'

            $log = [ordered]@{
                ddsource  = $Source
                service   = $Service
                ddtags    = $Tags
                message   = $entry
                source    = 'WinTaskCrossingGuard'
                action    = $action
                status    = $status
                operation = $operation
                runId     = $runId
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$hostName)) { $log.hostname = [string]$hostName }
            [pscustomobject]$log
        }

        return (ConvertTo-WtcgCompactJson -InputObject $logs -Depth 30 -AsArray)
    }
}
