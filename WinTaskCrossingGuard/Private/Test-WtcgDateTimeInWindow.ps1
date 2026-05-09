function Test-WtcgDateTimeInWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $DateTime,

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End
    )

    return ($DateTime -ge $Start -and $DateTime -le $End)
}
