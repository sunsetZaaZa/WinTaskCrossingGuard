function Write-WtcgReenableJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Task,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ManifestPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'ReenableTaskIdentities'
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Task) {
            if ($null -ne $entry) {
                $items.Add($entry)
            }
        }
    }

    end {
        $events = foreach ($entry in $items) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskPath'))
            $taskName = [string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskName')

            $details = [ordered]@{
                taskPath     = $taskPath
                taskName     = $taskName
                fullName     = "$taskPath$taskName"
                identityPath  = $IdentityPath
                manifestPath  = $ManifestPath
            }

            New-WtcgJsonlEvent `
                -Action 're-enable' `
                -Operation $Operation `
                -Status 'succeeded' `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -Details $details
        }

        $events | Write-WtcgJsonlEvent -Path $Path
    }
}
