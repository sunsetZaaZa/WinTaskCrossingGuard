function Test-WtcgRestoreArtifactTaskRestorable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task
    )

    $propertyNames = @($Task.PSObject.Properties.Name)
    $wasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $Task -Name 'WasOriginallyEnabled' -DefaultValue $true)
    $disabledBySuite = if ($propertyNames -contains 'DisabledBySuite') {
        [bool](Get-WtcgObjectPropertyValue -InputObject $Task -Name 'DisabledBySuite' -DefaultValue $true)
    }
    else {
        $true
    }

    return ($wasOriginallyEnabled -and $disabledBySuite)
}
