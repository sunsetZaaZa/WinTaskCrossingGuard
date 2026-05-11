function ConvertTo-WtcgSplunkHecPayload {
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
        [string] $Index,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Source = 'WinTaskCrossingGuard',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Sourcetype = '_json'
    )

    begin { $events = [System.Collections.Generic.List[object]]::new() }
    process {
        foreach ($entry in @($InputEvent)) {
            if ($null -ne $entry -and (Test-WtcgTelemetryEventAllowed -InputEvent $entry -AllowedEvents $AllowedEvents)) { $events.Add($entry) }
        }
    }
    end {
        if (-not [string]::IsNullOrWhiteSpace($JsonlPath)) {
            foreach ($entry in Import-WtcgJsonlEvent -Path $JsonlPath | Select-WtcgTelemetryEvent -AllowedEvents $AllowedEvents) {
                if ($null -ne $entry) { $events.Add($entry) }
            }
        }

        if ($events.Count -eq 0) { return '' }

        # Build the full HEC body with a StringBuilder and write it as one
        # scalar string. This avoids two PowerShell gotchas that break NDJSON/HEC
        # tests on some hosts: foreach output collection and accidental pipeline
        # enumeration of strings/objects returned from nested helpers.
        $body = [System.Text.StringBuilder]::new()
        foreach ($entry in $events) {
            $timestamp = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'timestampUtc'
            $hostName = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'hostName'
            $epoch = ConvertTo-WtcgUnixEpochSeconds -Value $timestamp

            # Splunk HEC accepts newline-delimited event envelopes. Build the
            # envelope explicitly so the top-level JSON object is guaranteed to
            # remain a single physical line even when PowerShell serializes
            # ordered dictionaries differently across versions/platforms.
            $sourceJson = [string]::Concat(@(ConvertTo-WtcgCompactJson -InputObject $Source -Depth 5))
            $sourcetypeJson = [string]::Concat(@(ConvertTo-WtcgCompactJson -InputObject $Sourcetype -Depth 5))
            $eventJson = [string]::Concat(@(ConvertTo-WtcgCompactJson -InputObject $entry -Depth 30))

            $parts = [System.Collections.Generic.List[string]]::new()
            [void]$parts.Add('"source":' + $sourceJson)
            [void]$parts.Add('"sourcetype":' + $sourcetypeJson)
            [void]$parts.Add('"event":' + $eventJson)

            if (-not [string]::IsNullOrWhiteSpace($Index)) {
                $indexJson = [string]::Concat(@(ConvertTo-WtcgCompactJson -InputObject $Index -Depth 5))
                [void]$parts.Add('"index":' + $indexJson)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$hostName)) {
                $hostJson = [string]::Concat(@(ConvertTo-WtcgCompactJson -InputObject ([string]$hostName) -Depth 5))
                [void]$parts.Add('"host":' + $hostJson)
            }
            if ($null -ne $epoch) {
                [void]$parts.Add('"time":' + ([string]$epoch))
            }

            $line = '{' + ($parts -join ',') + '}'
            $line = [System.Text.RegularExpressions.Regex]::Replace([string]$line, "(`r`n|`n|`r)\s*", '')
            [void]$body.Append($line)
            [void]$body.Append("`n")
        }

        Write-Output -NoEnumerate $body.ToString()
    }
}
