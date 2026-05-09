function Save-WtcgManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject[]] $Task,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter()]
        [AllowNull()]
        [object] $Selection,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in $Task) {
            $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string]$entry.TaskPath)
            $items.Add([pscustomobject]@{
                TaskPath             = $normalizedPath
                TaskName             = [string]$entry.TaskName
                FullName             = "$normalizedPath$($entry.TaskName)"
                State                = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                OriginalState        = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'OriginalState' -DefaultValue (Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State')
                WasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'WasOriginallyEnabled' -DefaultValue $true)
                DisabledBySuite      = [bool](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledBySuite' -DefaultValue $false)
                DisabledAt           = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'DisabledAt'
                NextRunTime          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
                LastRunTime          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'LastRunTime'
                LastTaskResult       = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'LastTaskResult'
                Author               = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'Author'
                Description          = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'Description'
            })
        }
    }

    end {
        $manifest = [pscustomobject]@{
            Kind             = 'WinTaskCrossingGuard.RollbackManifest'
            ManifestVersion  = 1
            CreatedAt        = (Get-Date)
            RunId            = $RunId
            RunFolderPath    = $RunFolderPath
            WindowStart      = $WindowStart
            WindowEnd        = $WindowEnd
            SelectionSource  = if ($null -ne $Selection) { $Selection.SourcePath } else { $null }
            Tasks            = $items
        }

        $directory = Split-Path -Parent $Path
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $manifest |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $Path -Encoding utf8 -WhatIf:$false

        Get-Item -Path $Path
    }
}
