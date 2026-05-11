function Normalize-WtcgTaskPath {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Private legacy helper name retained because existing internal tests and scripts call it directly.')]
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
