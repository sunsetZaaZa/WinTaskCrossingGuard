function ConvertTo-WtcgNullableDateTime {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    try {
        $dateTime = [datetime]$Value
        if ($dateTime -eq [datetime]::MinValue) {
            return $null
        }

        return $dateTime
    }
    catch {
        return $null
    }
}
