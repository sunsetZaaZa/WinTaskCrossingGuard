function Assert-WtcgMailEventSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    $entries = @($Mail)

    if ($null -eq $Mail -or $entries.Count -le 1) {
        return
    }

    if ($entries.Count -gt 2) {
        throw "Invalid mail configuration: the 'mail' array supports either one shared entry or two entries: one with event='result' and one with event='error'."
    }

    $events = foreach ($entry in $entries) {
        $entryEvent = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'event'
        if ($null -eq $entryEvent -or [string]::IsNullOrWhiteSpace([string]$entryEvent)) {
            throw "Invalid mail configuration: when two mail entries are provided, each entry must include an event attribute. Required values are 'result' and 'error'."
        }

        ([string]$entryEvent).Trim().ToLowerInvariant()
    }

    foreach ($event in $events) {
        if ($event -notin @('result', 'error')) {
            throw "Invalid mail configuration: unsupported mail event '$event'. Required values are 'result' and 'error'."
        }
    }

    if (@($events | Where-Object { $_ -eq 'result' }).Count -ne 1 -or
        @($events | Where-Object { $_ -eq 'error' }).Count -ne 1) {
        throw "Invalid mail configuration: when two mail entries are provided, exactly one must use event='result' and exactly one must use event='error'."
    }
}
