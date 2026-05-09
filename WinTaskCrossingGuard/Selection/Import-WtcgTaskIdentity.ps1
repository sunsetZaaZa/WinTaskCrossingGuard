function Import-WtcgTaskIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Task identity JSON not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    $jsonTasks = Get-WtcgObjectPropertyValue -InputObject $json -Name 'Tasks'
    $items = if ($null -ne $jsonTasks) { @($jsonTasks) } else { @($json) }

    foreach ($item in $items) {
        New-WtcgTaskIdentity `
            -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskPath')) `
            -TaskName ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskName')) `
            -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $item -Name 'NextRunTime') `
            -State (Get-WtcgObjectPropertyValue -InputObject $item -Name 'State') `
            -OriginalState (Get-WtcgObjectPropertyValue -InputObject $item -Name 'OriginalState') `
            -WasOriginallyEnabled ([bool](Get-WtcgObjectPropertyValue -InputObject $item -Name 'WasOriginallyEnabled' -DefaultValue $true)) `
            -DisabledBySuite ([bool](Get-WtcgObjectPropertyValue -InputObject $item -Name 'DisabledBySuite' -DefaultValue $false)) `
            -DisabledAt (Get-WtcgObjectPropertyValue -InputObject $item -Name 'DisabledAt') `
            -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $item -Name 'LastRunTime') `
            -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $item -Name 'LastTaskResult') `
            -Author (Get-WtcgObjectPropertyValue -InputObject $item -Name 'Author') `
            -Description (Get-WtcgObjectPropertyValue -InputObject $item -Name 'Description')
    }
}
