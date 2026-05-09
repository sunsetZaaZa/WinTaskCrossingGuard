function Write-WtcgAuditEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('disable', 'scheduled-reenable', 're-enable', 'error', 'notification')]
        [string] $Action,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $EventId,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $EntryType = 'Information',

        [Parameter()]
        [AllowNull()]
        [object] $Details,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogSource = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EventLogName = 'Application',

        [Parameter()]
        [switch] $DisableEventLog,

        [Parameter()]
        [switch] $FailOnEventLogError
    )

    $now = Get-Date
    $eventDetails = if ($null -ne $Details) { $Details } else { [ordered]@{} }
    $payload = [ordered]@{
        schemaVersion  = '1.0'
        product        = 'WinTaskCrossingGuard'
        eventSource    = $EventLogSource
        timestampUtc   = $now.ToUniversalTime().ToString('o')
        timestampLocal = $now.ToString('o')
        action         = $Action
        operation      = $Operation
        status         = $Status
        hostName       = $env:COMPUTERNAME
        userName       = $env:USERNAME
        processId      = $PID
        details        = $eventDetails
    }

    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $payload.runId = $RunId
    }

    if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $payload.runFolderPath = $RunFolderPath
    }

    $message = $payload | ConvertTo-Json -Depth 20 -Compress

    if ($DisableEventLog) {
        return [pscustomobject]@{
            Source    = $EventLogSource
            LogName   = $EventLogName
            EventId   = $EventId
            EntryType = $EntryType
            Message   = $message
            Written   = $false
            Skipped   = $true
            Error     = 'Windows Event Log auditing disabled by caller.'
        }
    }

    Write-WtcgWindowsEventLog `
        -Source $EventLogSource `
        -LogName $EventLogName `
        -EventId $EventId `
        -EntryType $EntryType `
        -Message $message `
        -EnsureSource $true `
        -FailOnError:$FailOnEventLogError
}
