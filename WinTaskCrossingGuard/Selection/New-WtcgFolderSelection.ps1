function New-WtcgFolderSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter()]
        [bool] $Recurse = $false
    )

    [pscustomobject]@{
        TaskPath = Normalize-WtcgTaskPath -TaskPath $TaskPath
        Recurse  = $Recurse
    }
}
