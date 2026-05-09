function ConvertTo-WtcgUnixEpochSeconds {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    $dateTime = ConvertTo-WtcgNullableDateTime -Value $Value
    if ($null -eq $dateTime) { return $null }
    $dateTimeOffset = [datetimeoffset]($dateTime.ToUniversalTime())
    $dateTimeOffset.ToUnixTimeSeconds()
}
