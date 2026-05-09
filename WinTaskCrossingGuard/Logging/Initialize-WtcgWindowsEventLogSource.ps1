function Initialize-WtcgWindowsEventLogSource {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Source = 'WinTaskCrossingGuard',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $LogName = 'Application',

        [Parameter()]
        [switch] $FailOnError
    )

    $result = [ordered]@{
        Source       = $Source
        LogName      = $LogName
        IsWindows    = $false
        SourceExists = $false
        Created      = $false
        Skipped      = $false
        Error        = $null
    }

    if (-not (Test-WtcgWindowsPlatform)) {
        $result.Skipped = $true
        $result.Error = 'Windows Event Log is only available on Windows.'
        return [pscustomobject]$result
    }

    $result.IsWindows = $true

    try {
        $result.SourceExists = [System.Diagnostics.EventLog]::SourceExists($Source)
    }
    catch {
        $result.Error = $_.Exception.Message
        if ($FailOnError) {
            throw
        }
        return [pscustomobject]$result
    }

    if ($result.SourceExists) {
        return [pscustomobject]$result
    }

    try {
        if ($PSCmdlet.ShouldProcess("$LogName/$Source", 'Create Windows Event Log source')) {
            $creationData = [System.Diagnostics.EventSourceCreationData]::new($Source, $LogName)
            [System.Diagnostics.EventLog]::CreateEventSource($creationData)
            $result.Created = $true
            $result.SourceExists = $true
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
