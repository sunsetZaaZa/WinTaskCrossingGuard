function Write-WtcgJsonlEvent {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('Event')]
        [object[]] $JsonlEvent,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $JsonlEvent) {
            if ($null -ne $entry) {
                $items.Add($entry)
            }
        }
    }

    end {
        $resolvedPath = Resolve-WtcgJsonlLogPath -Path $Path

        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            throw "Could not resolve JSONL log path."
        }

        $directory = Split-Path -Parent $resolvedPath
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        foreach ($entry in $items) {
            $json = $entry | ConvertTo-Json -Depth 20 -Compress
            Add-Content -LiteralPath $resolvedPath -Value $json -Encoding utf8
        }

        Get-Item -LiteralPath $resolvedPath
    }
}
