function Get-WtcgScheduledTaskCandidate {
    [CmdletBinding()]
    param(
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
        [object] $Selection
    )

    Assert-WtcgSafetyAllowListSatisfied -Selection $Selection

    Import-Module ScheduledTasks -ErrorAction Stop

    $allTasks = [System.Collections.Generic.List[object]]::new()

    foreach ($path in @($TaskPath | ForEach-Object { Normalize-WtcgTaskPath -TaskPath $_ })) {
        if ($Recurse) {
            Get-ScheduledTask -ErrorAction Stop |
                Where-Object { $_.TaskPath -like "$path*" } |
                ForEach-Object { $allTasks.Add($_) }
        }
        else {
            Get-ScheduledTask -TaskPath $path -ErrorAction Stop |
                ForEach-Object { $allTasks.Add($_) }
        }
    }

    if ($null -ne $Selection -and $Selection.IncludeFolders.Count -gt 0) {
        foreach ($folder in $Selection.IncludeFolders) {
            $folderPath = Normalize-WtcgTaskPath -TaskPath ([string]$folder.TaskPath)

            if ([bool]$folder.Recurse) {
                Get-ScheduledTask -ErrorAction Stop |
                    Where-Object { $_.TaskPath -like "$folderPath*" } |
                    ForEach-Object { $allTasks.Add($_) }
            }
            else {
                Get-ScheduledTask -TaskPath $folderPath -ErrorAction SilentlyContinue |
                    ForEach-Object { $allTasks.Add($_) }
            }
        }
    }

    if ($null -ne $Selection -and $Selection.IncludeTasks.Count -gt 0) {
        foreach ($spec in $Selection.IncludeTasks) {
            Get-ScheduledTask -TaskPath $spec.TaskPath -TaskName $spec.TaskName -ErrorAction SilentlyContinue |
                ForEach-Object { $allTasks.Add($_) }
        }
    }

    $allTasks |
        Where-Object {
            $task = $_

            $nameMatches = foreach ($pattern in $TaskName) {
                if ($task.TaskName -like $pattern) { $true; break }
            }

            $nameMatches -and
            ($IncludeDisabled -or $task.State -ne 'Disabled') -and
            (Test-WtcgTaskAllowedBySelection -Task $task -Selection $Selection)
        } |
        Sort-Object TaskPath, TaskName -Unique
}
