function Find-WtcgTaskInWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [Parameter()]
        [string[]] $TaskPath = '\',

        [Parameter()]
        [string[]] $TaskName = '*',

        [Parameter()]
        [switch] $Recurse,

        [Parameter()]
        [switch] $IncludeDisabled,

        [Parameter()]
        [AllowNull()]
        [object] $Selection,

        [Parameter()]
        [switch] $IdentityOnly
    )

    $tasks = Get-WtcgScheduledTaskCandidate `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Recurse:$Recurse `
        -IncludeDisabled:$IncludeDisabled `
        -Selection $Selection

    foreach ($task in $tasks) {
        $info = $null
        try {
            $info = Get-ScheduledTaskInfo -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not read task info for '$($task.TaskPath)$($task.TaskName)': $($_.Exception.Message)"
            continue
        }

        if ($null -eq $info.NextRunTime -or $info.NextRunTime -eq [datetime]::MinValue) {
            continue
        }

        if (Test-WtcgDateTimeInWindow -DateTime $info.NextRunTime -Start $Start -End $End) {
            if ($IdentityOnly) {
                New-WtcgTaskIdentity `
                    -TaskPath $task.TaskPath `
                    -TaskName $task.TaskName `
                    -NextRunTime $info.NextRunTime `
                    -State ([string]$task.State) `
                    -OriginalState ([string]$task.State) `
                    -WasOriginallyEnabled ([string]$task.State -ne 'Disabled') `
                    -LastRunTime $info.LastRunTime `
                    -LastTaskResult $info.LastTaskResult `
                    -Author (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Author') `
                    -Description (Get-WtcgObjectPropertyValue -InputObject $task -Name 'Description')
            }
            else {
                [pscustomobject]@{
                    TaskPath             = $task.TaskPath
                    TaskName             = $task.TaskName
                    FullName             = "$($task.TaskPath)$($task.TaskName)"
                    State                = $task.State
                    OriginalState        = [string]$task.State
                    WasOriginallyEnabled = ([string]$task.State -ne 'Disabled')
                    DisabledBySuite      = $false
                    DisabledAt           = $null
                    NextRunTime          = $info.NextRunTime
                    LastRunTime          = $info.LastRunTime
                    LastTaskResult       = $info.LastTaskResult
                    Author               = $task.Author
                    Description          = $task.Description
                }
            }
        }
    }
}
