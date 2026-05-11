function Write-WtcgDisableXmlLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
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
        [string] $SelectionSource,

        [Parameter()]
        [AllowNull()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
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
        $createdAt = Get-Date
    }

    process {
        foreach ($entry in $Task) {
            $items.Add($entry)
        }
    }

    end {
        $resolvedPath = if ([string]::IsNullOrWhiteSpace($Path)) {
            Resolve-WtcgXmlLogPath -Path $null
        }
        else {
            Resolve-WtcgXmlLogPath -Path $Path
        }

        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            throw "Could not resolve XML log path."
        }

        $directory = Split-Path -Parent $resolvedPath
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }

        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

        $writer = [System.Xml.XmlWriter]::Create($resolvedPath, $settings)

        try {
            $writer.WriteStartDocument()

            $writer.WriteStartElement('WinTaskCrossingGuardDisableLog')
            $writer.WriteAttributeString('createdAt', $createdAt.ToString('o'))
            $writer.WriteAttributeString('createdLocal', $createdAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))
            $writer.WriteAttributeString('operation', $Operation)
            if (-not [string]::IsNullOrWhiteSpace($RunId)) {
                $writer.WriteAttributeString('runId', $RunId)
            }
            if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
                $writer.WriteElementString('RunFolderPath', $RunFolderPath)
            }

            $writer.WriteStartElement('Window')
            $writer.WriteElementString('Start', $WindowStart.ToString('o'))
            $writer.WriteElementString('End', $WindowEnd.ToString('o'))
            $writer.WriteEndElement()

            if ($null -ne $ReenableAt) {
                $writer.WriteElementString('ReenableAt', $ReenableAt.ToString('o'))
            }

            if (-not [string]::IsNullOrWhiteSpace($SelectionSource)) {
                $writer.WriteElementString('SelectionSource', $SelectionSource)
            }

            if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
                $writer.WriteElementString('IdentityOutputPath', $IdentityOutputPath)
            }

            if (-not [string]::IsNullOrWhiteSpace($ReenableTaskFullName)) {
                $writer.WriteElementString('ReenableTaskFullName', $ReenableTaskFullName)
            }

            $writer.WriteStartElement('Tasks')
            $writer.WriteAttributeString('count', ([string]$items.Count))

            foreach ($entry in $items) {
                $normalizedPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskPath'))
                $taskName = [string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'TaskName')

                $writer.WriteStartElement('Task')
                $writer.WriteElementString('TaskPath', $normalizedPath)
                $writer.WriteElementString('TaskName', $taskName)
                $writer.WriteElementString('FullName', "$normalizedPath$taskName")

                $entryState = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'State'
                if ($null -ne $entryState) {
                    $writer.WriteElementString('StateAtDiscovery', ([string]$entryState))
                }

                $entryNextRunTime = Get-WtcgObjectPropertyValue -InputObject $entry -Name 'NextRunTime'
                if ($null -ne $entryNextRunTime) {
                    $nextRunTime = [datetime]$entryNextRunTime
                    if ($nextRunTime -ne [datetime]::MinValue) {
                        $writer.WriteElementString('NextRunTime', $nextRunTime.ToString('o'))
                    }
                }

                $writer.WriteElementString('Action', 'Disabled')
                $writer.WriteElementString('LoggedAt', (Get-Date).ToString('o'))
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
            $writer.WriteEndElement()
            $writer.WriteEndDocument()
        }
        finally {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
        }

        Get-Item -LiteralPath $resolvedPath
    }
}
