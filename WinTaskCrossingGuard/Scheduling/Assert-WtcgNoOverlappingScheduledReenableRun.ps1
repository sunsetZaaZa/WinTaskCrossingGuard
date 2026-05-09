function Assert-WtcgNoOverlappingScheduledReenableRun {
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
        [string] $ReenableTaskName
    )

    $activePriorRun = Get-WtcgActivePriorReenableRun `
        -WindowStart $WindowStart `
        -WindowEnd $WindowEnd `
        -ReenableAt $ReenableAt `
        -ReenableTaskPath $ReenableTaskPath `
        -ReenableTaskName $ReenableTaskName

    if ($null -eq $activePriorRun) {
        return
    }

    $details = [System.Collections.Generic.List[string]]::new()
    $details.Add("task '$($activePriorRun.TaskFullName)'")
    if ($null -ne $activePriorRun.NextRunTime) {
        $details.Add("next re-enable '$($activePriorRun.NextRunTime.ToString('o'))'")
    }
    if ($null -ne $activePriorRun.WindowStart) {
        $details.Add("prior window start '$($activePriorRun.WindowStart.ToString('o'))'")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$activePriorRun.ManifestPath)) {
        $details.Add("manifest '$($activePriorRun.ManifestPath)'")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$activePriorRun.OverlapReason)) {
        $details.Add("reason '$($activePriorRun.OverlapReason)'")
    }

    throw "Active prior WinTaskCrossingGuard re-enable run detected: $($details -join '; '). Refusing to schedule a new re-enable task because it could overwrite or prematurely re-enable another run."
}
