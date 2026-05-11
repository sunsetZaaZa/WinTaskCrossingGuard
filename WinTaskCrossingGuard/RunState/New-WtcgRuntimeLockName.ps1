function New-WtcgRuntimeLockName {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
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
