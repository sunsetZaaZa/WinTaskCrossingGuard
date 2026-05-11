function New-WtcgWebhookNotificationText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Subject = 'WinTaskCrossingGuard notification',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorMessage
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("**$Subject**")
    if (-not [string]::IsNullOrWhiteSpace($Status)) { $lines.Add("Status: $Status") }
    if (-not [string]::IsNullOrWhiteSpace($Operation)) { $lines.Add("Operation: $Operation") }
    if (-not [string]::IsNullOrWhiteSpace($RunId)) { $lines.Add("Run ID: $RunId") }
    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) { $lines.Add("Run folder: $RunFolderPath") }
    if (-not [string]::IsNullOrWhiteSpace($XmlLogPath)) { $lines.Add("XML log: $XmlLogPath") }
    if (-not [string]::IsNullOrWhiteSpace($JsonlLogPath)) { $lines.Add("JSONL log: $JsonlLogPath") }
    if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) { $lines.Add("Identity/manifest: $IdentityOutputPath") }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) { $lines.Add("Error: $ErrorMessage") }

    $lines -join "`n"
}
