function Resolve-WtcgDateTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter()]
        [datetime] $AnchorDate = (Get-Date)
    )

    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $culture = [System.Globalization.CultureInfo]::CurrentCulture

    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Value, $culture, $styles, [ref] $parsed)) {
        throw "Could not parse date/time value '$Value'. Try an ISO value like '2026-04-26T22:00:00' or a time like '22:00'."
    }

    if ($Value -match '^\s*\d{1,2}(:\d{2}){0,2}\s*([aApP][mM])?\s*$') {
        return [datetime]::new(
            $AnchorDate.Year,
            $AnchorDate.Month,
            $AnchorDate.Day,
            $parsed.Hour,
            $parsed.Minute,
            $parsed.Second,
            $parsed.Kind
        )
    }

    return $parsed
}
