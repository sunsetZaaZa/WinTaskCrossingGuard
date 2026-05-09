function Resolve-WtcgRuntimeLockPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $basePath = $env:ProgramData
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = $env:TEMP
    }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = [System.IO.Path]::GetTempPath()
    }

    return (Join-Path $basePath 'WinTaskCrossingGuard\runtime.lock.json')
}
