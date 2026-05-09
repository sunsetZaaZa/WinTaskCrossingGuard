function ConvertTo-WtcgElasticBulkPayload {
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
        [ValidateNotNullOrEmpty()]
        [string] $Index = 'wintaskcrossingguard-events',

        [Parameter()]
        [switch] $DataStream,

        [Parameter()]
        [ValidateSet('index', 'create')]
        [string] $Action = 'index'
    )

    begin {
        $events = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in @($Event)) {
            if ($null -ne $entry) {
                $events.Add($entry)
            }
        }
    }

    end {
        if (-not [string]::IsNullOrWhiteSpace($JsonlPath)) {
            foreach ($entry in Import-WtcgJsonlEvent -Path $JsonlPath) {
                if ($null -ne $entry) {
                    $events.Add($entry)
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($Index)) {
            throw 'Elasticsearch index or data stream name cannot be empty.'
        }

        if ($events.Count -eq 0) {
            return ''
        }

        $bulkActionName = if ($DataStream) { 'create' } else { $Action.ToLowerInvariant() }
        $lines = [System.Collections.Generic.List[string]]::new()

        foreach ($entry in $events) {
            $document = $entry
            if ($entry -is [string]) {
                $document = $entry | ConvertFrom-Json -ErrorAction Stop
            }

            $metadataBody = [ordered]@{ _index = $Index }
            $metadata = [ordered]@{}
            $metadata[$bulkActionName] = $metadataBody

            $lines.Add((ConvertTo-WtcgCompactJson -InputObject $metadata -Depth 20))
            $lines.Add((ConvertTo-WtcgCompactJson -InputObject $document -Depth 20))
        }

        return (($lines -join "`n") + "`n")
    }
}
