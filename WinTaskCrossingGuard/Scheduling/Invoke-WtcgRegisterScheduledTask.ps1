function Invoke-WtcgRegisterScheduledTask {
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
        [object] $Principal,

        [Parameter()]
        [string] $Description,

        [Parameter()]
        [switch] $Force
    )

    Register-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal `
        -Description $Description `
        -Force:$Force
}
