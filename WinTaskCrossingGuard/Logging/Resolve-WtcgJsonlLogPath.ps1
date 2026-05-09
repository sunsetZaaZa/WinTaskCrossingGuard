function Resolve-WtcgJsonlLogPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot),

        [Parameter()]
        [string] $Prefix = 'wintaskcrossingguard-events'
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $BaseDirectory (Join-Path 'streamablelogs' "$Prefix-$timestamp.jsonl")
}
