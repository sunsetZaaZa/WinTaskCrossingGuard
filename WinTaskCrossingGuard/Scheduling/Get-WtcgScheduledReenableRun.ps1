function Get-WtcgScheduledReenableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [string] $ExpectedTaskPath,

        [Parameter(Mandatory)]
        [string] $ExpectedTaskName,

        [Parameter()]
        [datetime] $Now = (Get-Date)
    )

    $normalizedExpectedTaskPath = Normalize-WtcgTaskPath -TaskPath $ExpectedTaskPath
    $taskPath = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'TaskPath' -DefaultValue $normalizedExpectedTaskPath
    $taskName = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'TaskName' -DefaultValue $ExpectedTaskName

    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        return $null
    }

    $normalizedTaskPath = Normalize-WtcgTaskPath -TaskPath ([string]$taskPath)
    $taskFullName = "$normalizedTaskPath$taskName"
    $expectedTaskFullName = "$normalizedExpectedTaskPath$ExpectedTaskName"
    $isExactConfiguredTask = ($normalizedTaskPath -ieq $normalizedExpectedTaskPath -and [string]$taskName -ieq $ExpectedTaskName)

    $argumentText = @(Get-WtcgScheduledTaskActionArgumentText -Task $Task)
    $manifestPath = $null
    $jsonlLogPath = $null
    $runId = $null
    $runFolderPath = $null
    foreach ($arguments in $argumentText) {
        if ([string]::IsNullOrWhiteSpace($manifestPath)) {
            $manifestPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'ManifestPath'
        }
        if ([string]::IsNullOrWhiteSpace($jsonlLogPath)) {
            $jsonlLogPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'JsonlLogPath'
        }
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'RunId'
        }
        if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
            $runFolderPath = Get-WtcgCommandArgumentValue -Arguments $arguments -Name 'RunFolderPath'
        }
    }

    $description = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'Description'
    $isWinTaskCrossingGuardTask = (
        $isExactConfiguredTask -or
        -not [string]::IsNullOrWhiteSpace([string]$manifestPath) -or
        ([string]$description -match 'WinTaskCrossingGuard')
    )

    if (-not $isWinTaskCrossingGuardTask) {
        return $null
    }

    $taskInfo = $null
    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskPath $normalizedTaskPath -TaskName ([string]$taskName) -ErrorAction Stop
    }
    catch {
        $taskInfo = $null
    }

    $nextRunTime = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $taskInfo -Name 'NextRunTime')
    $manifestSummary = Import-WtcgReenableManifestSummary -Path $manifestPath
    $manifestWindowStart = $null
    $manifestWindowEnd = $null
    $manifestTaskFullNames = @()
    if ($null -ne $manifestSummary) {
        $manifestWindowStart = $manifestSummary.WindowStart
        $manifestWindowEnd = $manifestSummary.WindowEnd
        $manifestTaskFullNames = @($manifestSummary.TaskFullNames)
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $runId = $manifestSummary.RunId
        }
        if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
            $runFolderPath = $manifestSummary.RunFolderPath
        }
    }

    [pscustomobject]@{
        PSTypeName              = 'WinTaskCrossingGuard.ScheduledReenableRun'
        TaskPath                = $normalizedTaskPath
        TaskName                = [string]$taskName
        TaskFullName            = $taskFullName
        ExpectedTaskFullName    = $expectedTaskFullName
        IsExactConfiguredTask   = $isExactConfiguredTask
        NextRunTime             = $nextRunTime
        IsActive                = ($null -ne $nextRunTime -and $nextRunTime -gt $Now)
        ManifestPath            = $manifestPath
        JsonlLogPath            = $jsonlLogPath
        RunId                   = $runId
        RunFolderPath           = $runFolderPath
        WindowStart             = $manifestWindowStart
        WindowEnd               = $manifestWindowEnd
        TaskFullNames           = $manifestTaskFullNames
        ManifestSummary         = $manifestSummary
    }
}
