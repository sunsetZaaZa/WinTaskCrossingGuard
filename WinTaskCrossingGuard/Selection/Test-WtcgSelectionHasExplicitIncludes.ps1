function Test-WtcgSelectionHasExplicitIncludes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return $false
    }

    $includeFolders = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeFolders' -DefaultValue @())
    $includeTasks = @(Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'IncludeTasks' -DefaultValue @())

    return ($includeFolders.Count -gt 0 -or $includeTasks.Count -gt 0)
}
