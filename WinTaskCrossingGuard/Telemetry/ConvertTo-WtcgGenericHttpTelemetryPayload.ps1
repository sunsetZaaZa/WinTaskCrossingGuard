function ConvertTo-WtcgGenericHttpTelemetryPayload {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('ndjson', 'jsonArray', 'raw')]
        [string] $Format = 'ndjson',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlPath,

        [Parameter()]
        [AllowNull()]
        [string[]] $AllowedEvents
    )

    if ([string]::IsNullOrWhiteSpace($JsonlPath)) {
        return ''
    }

    if (-not (Test-Path -LiteralPath $JsonlPath)) {
        throw "JSONL event file not found: $JsonlPath"
    }

    if ($Format -ieq 'raw') {
        return (Get-Content -LiteralPath $JsonlPath -Raw -ErrorAction Stop)
    }

    $events = @(Import-WtcgJsonlEvent -Path $JsonlPath | Select-WtcgTelemetryEvent -AllowedEvents $AllowedEvents)

    if ($Format -ieq 'jsonArray') {
        return (ConvertTo-WtcgCompactJson -InputObject $events -Depth 20 -AsArray)
    }

    if ($events.Count -eq 0) {
        return ''
    }

    $lines = @($events | ForEach-Object { ConvertTo-WtcgCompactJson -InputObject $_ -Depth 20 })
    return (($lines -join "`n") + "`n")
}
