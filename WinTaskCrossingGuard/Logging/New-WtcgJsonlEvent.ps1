function New-WtcgJsonlEvent {
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
    $event = [ordered]@{
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
        $event.status = $Status
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $event.runId = $RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $event.runFolderPath = $RunFolderPath
    }

    $event.details = if ($null -ne $Details) { $Details } else { [ordered]@{} }

    [pscustomobject]$event
}
