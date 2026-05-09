function ConvertTo-WtcgCompactJson {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int] $Depth = 30,

        [Parameter()]
        [switch] $AsArray
    )

    process {
        $jsonInput = $InputObject
        if ($null -ne $jsonInput -and $jsonInput -is [System.Collections.IDictionary]) {
            # Convert dictionaries to PSCustomObject before JSON serialization so
            # PowerShell never emits one DictionaryEntry per line for telemetry NDJSON/HEC payloads.
            $jsonInput = [pscustomobject]$jsonInput
        }

        if ($AsArray) {
            $json = ConvertTo-Json -InputObject $jsonInput -Depth $Depth -Compress -AsArray
        }
        else {
            $json = ConvertTo-Json -InputObject $jsonInput -Depth $Depth -Compress
        }

        if ($null -eq $json) {
            Write-Output -NoEnumerate ''
            return
        }

        $text = [string]::Join('', @($json | ForEach-Object { [string]$_ }))
        $compact = [System.Text.RegularExpressions.Regex]::Replace($text, "(`r`n|`n|`r)\s*", '')
        Write-Output -NoEnumerate $compact
    }
}
