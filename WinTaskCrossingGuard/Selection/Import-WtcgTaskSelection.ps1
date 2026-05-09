function Import-WtcgTaskSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Task selection JSON not found: $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read task selection JSON '$Path': $($_.Exception.Message)"
    }

    $defaultIncludeFolderRecurse = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'defaultIncludeFolderRecurse' -DefaultValue $false)
    $defaultExcludeFolderRecurse = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'defaultExcludeFolderRecurse' -DefaultValue $false)

    $includeFolders = @()
    $excludeFolders = @()
    $includeTasks = @()
    $excludeTasks = @()
    $protectedFolders = @()
    $protectedTasks = @()
    $safetyAllowListMode = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'safetyAllowListMode' -DefaultValue $false)
    $useDefaultProtectedTaskList = [bool](Get-WtcgObjectPropertyValue -InputObject $json -Name 'useDefaultProtectedTaskList' -DefaultValue $true)

    $jsonIncludeFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'includeFolders'
    if ($null -ne $jsonIncludeFolders) {
        $includeFolders = @(
            $jsonIncludeFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $defaultIncludeFolderRecurse
        )
    }

    $jsonExcludeFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'excludeFolders'
    if ($null -ne $jsonExcludeFolders) {
        $excludeFolders = @(
            $jsonExcludeFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $defaultExcludeFolderRecurse
        )
    }

    $jsonProtectedFolders = Get-WtcgObjectPropertyValue -InputObject $json -Name 'protectedFolders'
    if ($null -ne $jsonProtectedFolders) {
        $protectedFolders = @(
            $jsonProtectedFolders |
                ConvertTo-WtcgFolderSelection -DefaultRecurse $true
        )
    }

    $jsonProtectedTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'protectedTasks'
    if ($null -ne $jsonProtectedTasks) {
        $protectedTasks = @($jsonProtectedTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    $jsonIncludeTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'includeTasks'
    if ($null -ne $jsonIncludeTasks) {
        $includeTasks = @($jsonIncludeTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    $jsonExcludeTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'excludeTasks'
    if ($null -ne $jsonExcludeTasks) {
        $excludeTasks = @($jsonExcludeTasks | ForEach-Object {
            [pscustomobject]@{
                TaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskPath'))
                TaskName = [string](Get-WtcgObjectPropertyValue -InputObject $_ -Name 'taskName')
            }
        })
    }

    foreach ($entry in $includeTasks + $excludeTasks) {
        if ([string]::IsNullOrWhiteSpace($entry.TaskName)) {
            throw "Every includeTasks/excludeTasks entry must have a non-empty taskName."
        }
    }

    foreach ($entry in $protectedTasks) {
        if ([string]::IsNullOrWhiteSpace($entry.TaskName)) {
            throw "Every protectedTasks entry must have a non-empty taskName."
        }
    }

    [pscustomobject]@{
        IncludeFolders              = $includeFolders
        ExcludeFolders              = $excludeFolders
        IncludeTasks                = $includeTasks
        ExcludeTasks                = $excludeTasks
        ProtectedFolders            = $protectedFolders
        ProtectedTasks              = $protectedTasks
        SafetyAllowListMode         = $safetyAllowListMode
        UseDefaultProtectedTaskList = $useDefaultProtectedTaskList
        SourcePath                  = (Resolve-Path -LiteralPath $Path).Path
        Mail                        = ConvertTo-WtcgMailEventSettings -Mail (Get-WtcgObjectPropertyValue -InputObject $json -Name 'mail')
    }
}
