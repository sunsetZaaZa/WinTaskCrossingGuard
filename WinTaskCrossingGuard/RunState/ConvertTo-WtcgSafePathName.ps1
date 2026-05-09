function ConvertTo-WtcgSafePathName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $safe = $Value.Trim()
    foreach ($invalidCharacter in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$invalidCharacter, '-')
    }

    $safe = $safe -replace '\s+', '-'
    $safe = $safe -replace '-{2,}', '-'
    $safe = $safe.Trim('-')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw 'RunId cannot resolve to an empty folder name.'
    }

    return $safe
}
