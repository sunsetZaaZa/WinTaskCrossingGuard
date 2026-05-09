function ConvertTo-WtcgBoolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [bool] $Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }

    switch -Regex ($text.ToLowerInvariant()) {
        '^(1|true|yes|y|on|enabled)$' { return $true }
        '^(0|false|no|n|off|disabled)$' { return $false }
        default { throw "Invalid boolean value '$Value'. Expected true/false, yes/no, on/off, or 1/0." }
    }
}
