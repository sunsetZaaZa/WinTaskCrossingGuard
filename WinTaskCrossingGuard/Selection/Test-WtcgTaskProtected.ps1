function Test-WtcgTaskProtected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    $protectedFolders = @(Get-WtcgDefaultProtectedFolderSelection)
    $protectedTasks = @()

    if ($null -ne $Selection) {
        $useDefaultProtectedTaskList = [bool](Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'UseDefaultProtectedTaskList' -DefaultValue $true)

        if (-not $useDefaultProtectedTaskList) {
            $protectedFolders = @()
        }

        $selectionProtectedFolders = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ProtectedFolders'
        if ($null -ne $selectionProtectedFolders) {
            $protectedFolders += @($selectionProtectedFolders)
        }

        $selectionProtectedTasks = Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ProtectedTasks'
        if ($null -ne $selectionProtectedTasks) {
            $protectedTasks += @($selectionProtectedTasks)
        }
    }

    if ($protectedFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $protectedFolders)) {
        return $true
    }

    if ($protectedTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $protectedTasks)) {
        return $true
    }

    return $false
}
