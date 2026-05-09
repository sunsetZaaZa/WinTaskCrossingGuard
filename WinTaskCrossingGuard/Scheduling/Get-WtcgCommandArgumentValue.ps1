function Get-WtcgCommandArgumentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Arguments,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Argument name cannot be empty.'
    }

    $escapedName = [regex]::Escape($Name.TrimStart('-'))
    $pattern = "(?i)(?:^|\s)-$escapedName(?:\s+|:)(?:`"(?<dq>[^`"]*)`"|'(?<sq>[^']*)'|(?<bare>\S+))"
    $match = [regex]::Match($Arguments, $pattern)

    if (-not $match.Success) {
        return $null
    }

    foreach ($groupName in @('dq', 'sq', 'bare')) {
        $group = $match.Groups[$groupName]
        if ($null -ne $group -and $group.Success) {
            return $group.Value
        }
    }

    return $null
}
