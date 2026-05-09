function ConvertTo-WtcgTelemetryTimestampUtcString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $format = 'yyyy-MM-ddTHH:mm:ssZ'

    if ($null -eq $Value) {
        return (Get-Date).ToUniversalTime().ToString($format, $culture)
    }

    if ($Value -is [datetimeoffset]) {
        return $Value.UtcDateTime.ToString($format, $culture)
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString($format, $culture)
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return (Get-Date).ToUniversalTime().ToString($format, $culture)
    }

    $dateTimeOffset = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse($text, $culture, $styles, [ref]$dateTimeOffset)) {
        return $dateTimeOffset.UtcDateTime.ToString($format, $culture)
    }

    return $text
}
