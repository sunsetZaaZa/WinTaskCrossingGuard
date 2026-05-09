function Resolve-WtcgWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Start,

        [Parameter(Mandatory)]
        [string] $End,

        [Parameter()]
        [datetime] $AnchorDate = (Get-Date)
    )

    $startTime = Resolve-WtcgDateTime -Value $Start -AnchorDate $AnchorDate
    $endTime = Resolve-WtcgDateTime -Value $End -AnchorDate $AnchorDate

    if ($endTime -lt $startTime) {
        $endTime = $endTime.AddDays(1)
    }

    [pscustomobject]@{
        Start = $startTime
        End   = $endTime
    }
}
