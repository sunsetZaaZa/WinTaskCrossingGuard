function Resolve-WtcgXmlLogPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot),

        [Parameter()]
        [string] $Prefix = 'disabled-tasks'
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $BaseDirectory (Join-Path 'logs' "$Prefix-$timestamp.xml")
}
