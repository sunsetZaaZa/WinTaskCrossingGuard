function Invoke-WtcgSetScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter()]
        [object] $Action,

        [Parameter()]
        [object] $Trigger,

        [Parameter()]
        [object] $Settings,

        [Parameter()]
        [object] $Principal
    )

    Set-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal
}
