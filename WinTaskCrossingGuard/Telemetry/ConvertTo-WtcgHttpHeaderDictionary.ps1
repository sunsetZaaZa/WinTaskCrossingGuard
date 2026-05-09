function ConvertTo-WtcgHttpHeaderDictionary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Headers,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $AuthHeaderName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $AuthHeaderValue
    )

    $dictionary = @{}

    if ($Headers -is [hashtable]) {
        foreach ($key in $Headers.Keys) {
            if (-not [string]::IsNullOrWhiteSpace([string]$key)) {
                $dictionary[[string]$key] = [string]$Headers[$key]
            }
        }
    }
    elseif ($null -ne $Headers) {
        foreach ($entry in @($Headers)) {
            if ([string]::IsNullOrWhiteSpace([string]$entry)) {
                continue
            }

            $parts = ([string]$entry) -split '=', 2
            if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0])) {
                throw "Invalid HTTP header entry '$entry'. Expected Name=Value."
            }

            $dictionary[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($AuthHeaderName) -and -not [string]::IsNullOrWhiteSpace($AuthHeaderValue)) {
        $dictionary[$AuthHeaderName.Trim()] = $AuthHeaderValue
    }

    $dictionary
}
