function Assert-WtcgSafetyAllowListSatisfied {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Selection
    )

    if ($null -eq $Selection) {
        return
    }

    $safetyAllowListMode = [bool](Get-WtcgObjectPropertyValue -InputObject $Selection -Name 'SafetyAllowListMode' -DefaultValue $false)

    if (-not $safetyAllowListMode) {
        return
    }

    if (-not (Test-WtcgSelectionHasExplicitIncludes -Selection $Selection)) {
        throw "Safety allow-list mode is enabled, but no includeFolders or includeTasks entries were provided. Refusing to scan or disable tasks."
    }
}
