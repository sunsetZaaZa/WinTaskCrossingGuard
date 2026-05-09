function Get-WtcgActivePriorReenableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime] $WindowStart,

        [Parameter(Mandatory)]
        [datetime] $WindowEnd,

        [Parameter(Mandatory)]
        [datetime] $ReenableAt,

        [Parameter(Mandatory)]
        [string] $ReenableTaskPath,

        [Parameter(Mandatory)]
        [string] $ReenableTaskName,

        [Parameter()]
        [datetime] $Now = (Get-Date)
    )

    $normalizedReenableTaskPath = Normalize-WtcgTaskPath -TaskPath $ReenableTaskPath
    $candidateTasks = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    $addCandidate = {
        param([object] $Candidate)

        foreach ($item in @($Candidate)) {
            if ($null -eq $item) {
                continue
            }

            $candidateTaskPath = Normalize-WtcgTaskPath -TaskPath ([string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskPath' -DefaultValue $normalizedReenableTaskPath))
            $candidateTaskName = [string](Get-WtcgObjectPropertyValue -InputObject $item -Name 'TaskName' -DefaultValue '')
            if ([string]::IsNullOrWhiteSpace($candidateTaskName)) {
                continue
            }

            $key = "$candidateTaskPath|$candidateTaskName".ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $candidateTasks.Add($item)
            }
        }
    }

    try {
        & $addCandidate (Get-ScheduledTask -TaskPath $normalizedReenableTaskPath -TaskName $ReenableTaskName -ErrorAction SilentlyContinue)
    }
    catch { }

    try {
        & $addCandidate (Get-ScheduledTask -TaskPath $normalizedReenableTaskPath -ErrorAction SilentlyContinue)
    }
    catch { }

    $newActiveStart = $WindowStart
    $newActiveEnd = $ReenableAt
    if ($newActiveEnd -lt $newActiveStart) {
        $newActiveEnd = $WindowEnd
    }
    if ($newActiveEnd -lt $newActiveStart) {
        $newActiveEnd = $newActiveStart
    }

    foreach ($candidateTask in @($candidateTasks)) {
        $run = Get-WtcgScheduledReenableRun `
            -Task $candidateTask `
            -ExpectedTaskPath $normalizedReenableTaskPath `
            -ExpectedTaskName $ReenableTaskName `
            -Now $Now

        if ($null -eq $run -or -not $run.IsActive) {
            continue
        }

        if ($null -ne $run.NextRunTime -and $run.NextRunTime -le $WindowStart) {
            continue
        }

        $blocksRequestedRun = $false
        $reason = $null

        if ($run.IsExactConfiguredTask) {
            $blocksRequestedRun = $true
            $reason = 'configured re-enable task is already scheduled'
        }
        elseif ($null -eq $run.WindowStart -or $null -eq $run.NextRunTime) {
            $blocksRequestedRun = $true
            $reason = 'active WinTaskCrossingGuard re-enable task has insufficient manifest timing metadata'
        }
        else {
            $priorActiveStart = $run.WindowStart
            $priorActiveEnd = $run.NextRunTime
            if ($priorActiveEnd -lt $priorActiveStart) {
                $priorActiveEnd = $run.WindowEnd
            }
            if ($priorActiveEnd -lt $priorActiveStart) {
                $priorActiveEnd = $priorActiveStart
            }

            if (Test-WtcgDateTimeRangeOverlap `
                    -FirstStart $priorActiveStart `
                    -FirstEnd $priorActiveEnd `
                    -SecondStart $newActiveStart `
                    -SecondEnd $newActiveEnd) {
                $blocksRequestedRun = $true
                $reason = 'active re-enable window overlaps requested disable-to-reenable interval'
            }
        }

        if ($blocksRequestedRun) {
            $run | Add-Member -NotePropertyName OverlapReason -NotePropertyValue $reason -Force
            return $run
        }
    }

    return $null
}
