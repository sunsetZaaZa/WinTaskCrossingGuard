function Get-WtcgLogRetentionDays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
    )

    $envValues = Import-WtcgDotEnv -Path $EnvPath

    if (-not $envValues.ContainsKey('LOG_RETENTION')) {
        return $null
    }

    $rawValue = [string]$envValues['LOG_RETENTION']
    $days = 0

    if (-not [int]::TryParse($rawValue, [ref]$days)) {
        throw "Invalid LOG_RETENTION value '$rawValue' in '$EnvPath'. Expected a whole number of days."
    }

    if ($days -lt 0) {
        throw "Invalid LOG_RETENTION value '$rawValue' in '$EnvPath'. Value must be zero or greater."
    }

    return $days
}
