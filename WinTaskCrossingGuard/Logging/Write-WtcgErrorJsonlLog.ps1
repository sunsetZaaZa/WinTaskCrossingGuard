function Write-WtcgErrorJsonlLog {
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

    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    $details = [ordered]@{
        message                 = $message
        type                    = $errorType
        fullyQualifiedErrorId   = if ($null -ne $ErrorRecord.FullyQualifiedErrorId) { [string]$ErrorRecord.FullyQualifiedErrorId } else { $null }
        positionMessage         = if ($null -ne $ErrorRecord.InvocationInfo) { $ErrorRecord.InvocationInfo.PositionMessage } else { $null }
        selectionSource         = $SelectionSource
        identityOutputPath      = $IdentityOutputPath
    }

    New-WtcgJsonlEvent `
        -Action 'error' `
        -Operation $Operation `
        -Status 'failed' `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Details $details |
        Write-WtcgJsonlEvent -Path $Path
}
