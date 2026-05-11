function Write-WtcgErrorXmlLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

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
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    $resolvedPath = Resolve-WtcgXmlLogPath -Path $Path -Prefix 'wintaskcrossingguard-error'
    $directory = Split-Path -Parent $resolvedPath
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    $createdAt = Get-Date
    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

    $writer = [System.Xml.XmlWriter]::Create($resolvedPath, $settings)

    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('WinTaskCrossingGuardErrorLog')
        $writer.WriteAttributeString('createdAt', $createdAt.ToString('o'))
        $writer.WriteAttributeString('createdLocal', $createdAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))
        $writer.WriteAttributeString('operation', $Operation)
        if (-not [string]::IsNullOrWhiteSpace($RunId)) {
            $writer.WriteAttributeString('runId', $RunId)
        }
        if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
            $writer.WriteElementString('RunFolderPath', $RunFolderPath)
        }

        if (-not [string]::IsNullOrWhiteSpace($SelectionSource)) {
            $writer.WriteElementString('SelectionSource', $SelectionSource)
        }

        if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
            $writer.WriteElementString('IdentityOutputPath', $IdentityOutputPath)
        }

        $writer.WriteStartElement('Error')
        $writer.WriteElementString('Message', $message)

        if (-not [string]::IsNullOrWhiteSpace($errorType)) {
            $writer.WriteElementString('Type', $errorType)
        }

        if ($null -ne $ErrorRecord.FullyQualifiedErrorId) {
            $writer.WriteElementString('FullyQualifiedErrorId', ([string]$ErrorRecord.FullyQualifiedErrorId))
        }

        if ($null -ne $ErrorRecord.InvocationInfo -and
            -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage)) {
            $writer.WriteElementString('PositionMessage', $ErrorRecord.InvocationInfo.PositionMessage)
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

    Get-Item -Path $resolvedPath
}
