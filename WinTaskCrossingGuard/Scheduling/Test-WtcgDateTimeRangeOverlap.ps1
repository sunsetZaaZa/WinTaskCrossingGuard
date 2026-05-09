function Test-WtcgDateTimeRangeOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $FirstStart,

        [Parameter(Mandatory)]
        [datetime] $FirstEnd,

        [Parameter(Mandatory)]
        [datetime] $SecondStart,

        [Parameter(Mandatory)]
        [datetime] $SecondEnd
    )

    if ($FirstEnd -lt $FirstStart) {
        throw 'FirstEnd cannot be earlier than FirstStart.'
    }

    if ($SecondEnd -lt $SecondStart) {
        throw 'SecondEnd cannot be earlier than SecondStart.'
    }

    return ($FirstStart -lt $SecondEnd -and $SecondStart -lt $FirstEnd)
}
