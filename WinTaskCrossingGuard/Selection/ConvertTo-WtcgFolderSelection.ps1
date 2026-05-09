function ConvertTo-WtcgFolderSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $InputObject,

        [Parameter()]
        [bool] $DefaultRecurse = $false
    )

    process {
        foreach ($entry in $InputObject) {
            if ($entry -is [string]) {
                New-WtcgFolderSelection -TaskPath $entry -Recurse $DefaultRecurse
                continue
            }

            $path = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'taskPath'
            if ([string]::IsNullOrWhiteSpace([string]$path)) {
                $path = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'path'
            }

            if ([string]::IsNullOrWhiteSpace([string]$path)) {
                throw "Folder selection entries must be strings or objects with taskPath/path."
            }

            $recurseValue = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'recurse' -DefaultValue $DefaultRecurse
            New-WtcgFolderSelection -TaskPath ([string]$path) -Recurse ([bool]$recurseValue)
        }
    }
}
