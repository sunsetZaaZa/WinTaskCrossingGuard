function Resolve-WtcgRunRootPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $BaseDirectory = (Split-Path -Parent $PSScriptRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    return (Join-Path $BaseDirectory 'runs')
}
