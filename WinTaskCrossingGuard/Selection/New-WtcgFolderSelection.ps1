function New-WtcgFolderSelection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
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
