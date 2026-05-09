function ConvertTo-WtcgAzureMonitorPayload {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object[]] $Event,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlPath,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents
    )

    begin { $events = [System.Collections.Generic.List[object]]::new() }
    process {
        foreach ($entry in @($Event)) {
            if ($null -ne $entry -and (Test-WtcgTelemetryEventAllowed -Event $entry -AllowedEvents $AllowedEvents)) { $events.Add($entry) }
        }
    }
    end {
        if (-not [string]::IsNullOrWhiteSpace($JsonlPath)) {
            foreach ($entry in Import-WtcgJsonlEvent -Path $JsonlPath | Select-WtcgTelemetryEvent -AllowedEvents $AllowedEvents) {
                if ($null -ne $entry) { $events.Add($entry) }
            }
        }

        $records = foreach ($entry in $events) {
            $timestamp = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'timestampUtc'
            [pscustomobject][ordered]@{
                TimeGenerated = ConvertTo-WtcgTelemetryTimestampUtcString -Value $timestamp
                Source        = 'WinTaskCrossingGuard'
                Action        = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'action'
                Operation     = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'operation'
                Status        = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'status'
                RunId         = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'runId'
                RunFolderPath = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'runFolderPath'
                HostName      = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'hostName'
                UserName      = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'userName'
                ProcessId     = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'processId'
                Details       = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'details'
                RawEvent      = $entry
            }
        }

        return (ConvertTo-WtcgCompactJson -InputObject $records -Depth 30 -AsArray)
    }
}
