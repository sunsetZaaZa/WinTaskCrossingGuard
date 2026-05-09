function Import-WtcgRestoreArtifactTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Restore artifact not found: $Path"
    }

    $payload = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $tasks = Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Tasks'
    if ($null -eq $tasks) {
        throw "Restore artifact has no Tasks array: $Path"
    }

    foreach ($task in @($tasks)) {
        if ($null -eq $task) {
            continue
        }

        if (-not (Test-WtcgRestoreArtifactTaskRestorable -Task $task)) {
            Write-Verbose "Skipping '$([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskPath'))$([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskName'))' because it was not marked as disabled by this suite run."
            continue
        }

        New-WtcgTaskIdentity `
            -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskPath')) `
            -TaskName ([string](Get-WtcgObjectPropertyValue -InputObject $task -Name 'TaskName')) `
            -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $task -Name 'NextRunTime') `
            -State (Get-WtcgObjectPropertyValue -InputObject $task -Name 'State') `
            -OriginalState (Get-WtcgObjectPropertyValue -InputObject $task -Name 'OriginalState') `
            -WasOriginallyEnabled $true `
            -DisabledBySuite $true `
            -DisabledAt (Get-WtcgObjectPropertyValue -InputObject $task -Name 'DisabledAt') `
            -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $task -Name 'LastRunTime') `
            -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $task -Name 'LastTaskResult') `
            -Author (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Author') `
            -Description (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Description')
    }
}
