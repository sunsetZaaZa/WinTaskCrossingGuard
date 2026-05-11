function New-WtcgJsonlEvent {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('disable', 're-enable', 'error', 'notification')]
        [string] $Action,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [object] $Details,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $HostName = $env:COMPUTERNAME,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $UserName = $env:USERNAME
    )

    $now = Get-Date
    $jsonlEvent = [ordered]@{
        schemaVersion  = '1.0'
        source         = 'WinTaskCrossingGuard'
        timestampUtc   = $now.ToUniversalTime().ToString('o')
        timestampLocal = $now.ToString('o')
        action         = $Action
        operation      = $Operation
        hostName       = $HostName
        userName       = $UserName
        processId      = $PID
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $jsonlEvent.status = $Status
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $jsonlEvent.runId = $RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $jsonlEvent.runFolderPath = $RunFolderPath
    }

    $jsonlEvent.details = if ($null -ne $Details) { $Details } else { [ordered]@{} }

    [pscustomobject]$jsonlEvent
}
