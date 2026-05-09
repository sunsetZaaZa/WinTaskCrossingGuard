function Normalize-WtcgTaskPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $TaskPath
    )

    if ([string]::IsNullOrWhiteSpace($TaskPath)) {
        return '\'
    }

    $normalized = $TaskPath.Trim()

    if (-not $normalized.StartsWith('\')) {
        $normalized = "\$normalized"
    }

    if (-not $normalized.EndsWith('\')) {
        $normalized = "$normalized\"
    }

    return $normalized
}
