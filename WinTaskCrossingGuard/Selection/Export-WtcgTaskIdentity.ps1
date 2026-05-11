function Export-WtcgTaskIdentity {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [string] $Kind = 'TaskIdentityList',

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
        foreach ($identity in $TaskIdentity) {
            $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $items.Add([pscustomobject]@{
                TaskPath             = $normalizedPath
                TaskName             = [string]$identity.TaskName
                FullName             = "$normalizedPath$($identity.TaskName)"
                NextRunTime          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'NextRunTime'
                State                = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'State'
                OriginalState        = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'OriginalState'
                WasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'WasOriginallyEnabled' -DefaultValue $true)
                DisabledBySuite      = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'DisabledBySuite' -DefaultValue $false)
                DisabledAt           = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'DisabledAt'
                LastRunTime          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastRunTime'
                LastTaskResult       = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastTaskResult'
                Author               = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Author'
                Description          = Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Description'
            })
        }
    }

    end {
        $payload = [pscustomobject]@{
            Kind          = $Kind
            CreatedAt     = (Get-Date)
            RunId         = $RunId
            RunFolderPath = $RunFolderPath
            Tasks         = $items
        }

        $directory = Split-Path -Parent $Path
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $payload |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $Path -Encoding utf8 -WhatIf:$false

        Get-Item -Path $Path
    }
}
