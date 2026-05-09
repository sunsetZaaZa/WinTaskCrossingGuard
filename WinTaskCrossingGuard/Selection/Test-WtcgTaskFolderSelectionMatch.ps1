function Test-WtcgTaskFolderSelectionMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [object[]] $FolderSelection
    )

    foreach ($folder in $FolderSelection) {
        $folderPath = Normalize-WtcgTaskPath -TaskPath ([string]$folder.TaskPath)

        if ([bool]$folder.Recurse) {
            if ($Task.TaskPath -like "$folderPath*") {
                return $true
            }
        }
        else {
            if ($Task.TaskPath -eq $folderPath) {
                return $true
            }
        }
    }

    return $false
}
