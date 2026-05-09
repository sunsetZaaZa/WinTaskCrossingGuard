function Write-WtcgWindowsEventLog {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $EventId,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $EntryType = 'Information',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Source = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $LogName = 'Application',

        [Parameter()]
        [ValidateRange(0, 32767)]
        [int] $Category = 0,

        [Parameter()]
        [bool] $EnsureSource = $true,

        [Parameter()]
        [switch] $FailOnError
    )

    $result = [ordered]@{
        Source    = $Source
        LogName   = $LogName
        EventId   = $EventId
        EntryType = $EntryType
        Message   = $Message
        Written   = $false
        Skipped   = $false
        Error     = $null
    }

    if (-not (Test-WtcgWindowsPlatform)) {
        $result.Skipped = $true
        $result.Error = 'Windows Event Log is only available on Windows.'
        return [pscustomobject]$result
    }

    if ($EnsureSource) {
        $sourceResult = Initialize-WtcgWindowsEventLogSource `
            -Source $Source `
            -LogName $LogName `
            -FailOnError:$FailOnError

        if (-not ([bool]$sourceResult.SourceExists)) {
            $result.Skipped = $true
            $result.Error = if (-not [string]::IsNullOrWhiteSpace([string]$sourceResult.Error)) {
                [string]$sourceResult.Error
            }
            else {
                "Windows Event Log source '$Source' does not exist and could not be created."
            }
            return [pscustomobject]$result
        }
    }

    try {
        if ($PSCmdlet.ShouldProcess("$LogName/$Source", "Write event $EventId")) {
            $entryTypeValue = [System.Diagnostics.EventLogEntryType]::$EntryType
            [System.Diagnostics.EventLog]::WriteEntry($Source, $Message, $entryTypeValue, $EventId, [int16]$Category)
            $result.Written = $true
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        if ($FailOnError) {
            throw
        }
    }

    [pscustomobject]$result
}
