function New-WtcgRuntimeLockName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Name = 'Global\WinTaskCrossingGuard'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'LockName cannot be empty.'
    }

    $trimmed = $Name.Trim()
    if ($trimmed -notmatch '^(Global|Local)\\') {
        return "Global\$trimmed"
    }

    return $trimmed
}
