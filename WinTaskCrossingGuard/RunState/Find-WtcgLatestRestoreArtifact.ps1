function Find-WtcgLatestRestoreArtifact {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SearchPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunRootPath,

        [Parameter()]
        [switch] $IncludeEmptyRestoreSets
    )

    $effectiveSearchPath = if (-not [string]::IsNullOrWhiteSpace($SearchPath)) {
        $SearchPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($RunRootPath)) {
        $RunRootPath
    }
    else {
        Resolve-WtcgRunRootPath
    }

    if ([string]::IsNullOrWhiteSpace($effectiveSearchPath) -or -not (Test-Path -LiteralPath $effectiveSearchPath -PathType Container)) {
        return $null
    }

    Get-ChildItem -LiteralPath $effectiveSearchPath -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)(manifest|identit)' } |
        ForEach-Object { Get-WtcgRestoreArtifactSummary -Path $_.FullName } |
        Where-Object { $null -ne $_ } |
        Sort-Object -Property LastWriteTimeUtc, CreatedAt, Path -Descending |
        Select-Object -First 1
}
