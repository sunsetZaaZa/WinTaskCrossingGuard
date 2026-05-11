function New-WtcgRunId {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Prefix = 'wtcg'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return "$Prefix-$timestamp-$suffix"
}
