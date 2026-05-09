function Write-WtcgDisableJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $Task,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter()]
        [AllowNull()]
        [datetime] $ReenableAt,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ReenableTaskFullName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [string] $Operation = 'DisableTasksInWindow'
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
            $nextRunTime = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
            $disabledAt = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledAt'

            $details = [ordered]@{
                taskPath               = $taskPath
                taskName               = $taskName
                fullName               = "$taskPath$taskName"
                stateAtDiscovery       = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                originalState          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'OriginalState'
                wasOriginallyEnabled   = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'WasOriginallyEnabled' -DefaultValue $true)
                disabledBySuite        = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledBySuite' -DefaultValue $true)
                disabledAt             = if ($null -ne $disabledAt) { ([datetime]$disabledAt).ToString('o') } else { $null }
                nextRunTime            = if ($null -ne $nextRunTime -and ([datetime]$nextRunTime) -ne [datetime]::MinValue) { ([datetime]$nextRunTime).ToString('o') } else { $null }
                windowStart            = $WindowStart.ToString('o')
                windowEnd              = $WindowEnd.ToString('o')
                reenableAt             = if ($null -ne $ReenableAt) { $ReenableAt.ToString('o') } else { $null }
                selectionSource        = $SelectionSource
                identityOutputPath     = $IdentityOutputPath
                reenableTaskFullName   = $ReenableTaskFullName
            }

            New-WtcgJsonlEvent `
                -Action 'disable' `
                -Operation $Operation `
                -Status 'succeeded' `
                -RunId $RunId `
                -RunFolderPath $RunFolderPath `
                -Details $details
        }

        $events | Write-WtcgJsonlEvent -Path $Path
    }
}
