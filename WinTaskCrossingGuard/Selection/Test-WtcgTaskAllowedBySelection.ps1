function Test-WtcgTaskAllowedBySelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if (Test-WtcgTaskProtected -Task $Task -Selection $Selection) {
        return $false
    }

    if ($null -eq $Selection) {
        return $true
    }

    $excludeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ExcludeFolders' -DefaultValue @())
    $excludeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'ExcludeTasks' -DefaultValue @())
    $includeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeFolders' -DefaultValue @())
    $includeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeTasks' -DefaultValue @())

    if ($excludeFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $excludeFolders)) {
        return $false
    }

    if ($excludeTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $excludeTasks)) {
        return $false
    }

    $hasIncludes = ($includeFolders.Count -gt 0 -or $includeTasks.Count -gt 0)

    if (-not $hasIncludes) {
        return $true
    }

    if ($includeFolders.Count -gt 0 -and
        (Test-WtcgTaskFolderSelectionMatch -Task $Task -FolderSelection $includeFolders)) {
        return $true
    }

    if ($includeTasks.Count -gt 0 -and
        (Test-WtcgTaskSpecMatch -Task $Task -TaskSpec $includeTasks)) {
        return $true
    }

    return $false
}
