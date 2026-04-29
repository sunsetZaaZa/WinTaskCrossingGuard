[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [Alias('ManifestPath', 'IdentityPath')]
    [string] $ArtifactPath,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $SearchPath,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $RunRootPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runs'),

    [Parameter()]
    [switch] $IncludeEmptyRestoreSets,

    [Parameter()]
    [string] $LockName = 'Global\WinTaskCrossingGuard',

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $LockPath,

    [Parameter()]
    [int] $LockTimeoutSeconds = 0,

    [Parameter()]
    [switch] $DisableLock,

    [Parameter()]
    [switch] $PassThru,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $JsonlLogPath,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $ReportPath,

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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

$artifactSummary = $null
if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
    $resolvedArtifactPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArtifactPath)
    $artifactSummary = Get-WtcgRestoreArtifactSummary -Path $resolvedArtifactPath
    if ($null -eq $artifactSummary) {
        throw "Restore artifact was not a supported identity or manifest JSON file: $ArtifactPath"
    }
}
else {
    $artifactSummary = Find-WtcgLatestRestoreArtifact `
        -SearchPath $SearchPath `
        -RunRootPath $RunRootPath `
        -IncludeEmptyRestoreSets:$IncludeEmptyRestoreSets

    if ($null -eq $artifactSummary) {
        $searchedPath = if (-not [string]::IsNullOrWhiteSpace($SearchPath)) { $SearchPath } else { $RunRootPath }
        throw "No restorable identity or manifest JSON file was found under: $searchedPath"
    }
}

$ArtifactPath = $artifactSummary.Path

$runContext = New-WtcgRunContext `
    -RunId $artifactSummary.RunId `
    -RunRootPath $RunRootPath `
    -RunFolderPath $artifactSummary.RunFolderPath `
    -Operation 'EmergencyRestoreLatestDisabledTasks'

$RunId = $runContext.RunId
$RunFolderPath = $runContext.RunFolderPath

if (-not $PSBoundParameters.ContainsKey('JsonlLogPath') -or [string]::IsNullOrWhiteSpace($JsonlLogPath)) {
    $JsonlLogPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
}

if (-not $PSBoundParameters.ContainsKey('ReportPath') -or [string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Reports' -FileName 'emergency-restore-latest-report.json'
}

$effectiveErrorReportPath = Resolve-WtcgRunArtifactPath -RunContext $runContext -Kind 'Errors' -FileName 'emergency-restore-latest-error-report.json'
$runtimeLock = $null

try {
    if (-not $DisableLock) {
        $effectiveLockPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
        $runtimeLock = Enter-WtcgRuntimeLock `
            -LockName $LockName `
            -LockPath $effectiveLockPath `
            -TimeoutSeconds $LockTimeoutSeconds `
            -SkipLockFile:$WhatIfPreference `
            -Metadata @{
                Operation = 'EmergencyRestoreLatestDisabledTasks'
                RunId = $RunId
                RunFolderPath = $RunFolderPath
                ArtifactPath = $ArtifactPath
            }
    }

    $identities = @(Import-WtcgRestoreArtifactTaskIdentity -Path $ArtifactPath)
    if ($identities.Count -eq 0 -and -not $IncludeEmptyRestoreSets) {
        throw "Restore artifact contains no tasks that are marked as restorable by WinTaskCrossingGuard: $ArtifactPath"
    }

    Write-Host "Emergency restore artifact selected:"
    Write-Host "  $ArtifactPath"

    $restored = @()
    if ($identities.Count -gt 0) {
        $restored = @($identities | Enable-WtcgTaskIdentity -WhatIf:$WhatIfPreference -Confirm:$false)
    }

    if ($restored.Count -gt 0) {
        $logParams = @{
            Path = $JsonlLogPath
            RunId = $RunId
            RunFolderPath = $RunFolderPath
            Operation = 'EmergencyRestoreLatestDisabledTasks'
        }

        if ($artifactSummary.Kind -match '(?i)identity' -or $artifactSummary.Name -match '(?i)identit') {
            $logParams.IdentityPath = $ArtifactPath
        }
        else {
            $logParams.ManifestPath = $ArtifactPath
        }

        $restored | Write-WtcgReenableJsonlLog @logParams | Out-Null
    }

    Write-WtcgAuditEvent `
        -Action 're-enable' `
        -Operation 'EmergencyRestoreLatestDisabledTasks' `
        -Status 'succeeded' `
        -EventId 4210 `
        -EntryType 'Information' `
        -Details ([ordered]@{
            artifactPath = $ArtifactPath
            artifactKind = $artifactSummary.Kind
            artifactLastWriteTimeUtc = $artifactSummary.LastWriteTimeUtc.ToString('o')
            candidateTaskCount = $identities.Count
            restoredTaskCount = $restored.Count
            jsonlLogPath = $JsonlLogPath
            runFolderPath = $RunFolderPath
            runInfoPath = $runContext.RunInfoPath
        }) `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null

    $reportFile = Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $ReportPath `
        -Operation 'EmergencyRestoreLatestDisabledTasks' `
        -Status 'succeeded' `
        -Details ([ordered]@{
            artifactPath = $ArtifactPath
            artifactKind = $artifactSummary.Kind
            artifactLastWriteTimeUtc = $artifactSummary.LastWriteTimeUtc.ToString('o')
            candidateTaskCount = $identities.Count
            restoredTaskCount = $restored.Count
            jsonlLogPath = $JsonlLogPath
        })

    Write-Host "Emergency restore report written to:"
    Write-Host "  $($reportFile.FullName)"

    $result = [pscustomobject]@{
        RunId                = $RunId
        RunFolderPath        = $RunFolderPath
        RunInfoPath          = $runContext.RunInfoPath
        ArtifactPath         = $ArtifactPath
        ArtifactKind         = $artifactSummary.Kind
        ArtifactLastWriteTimeUtc = $artifactSummary.LastWriteTimeUtc
        ReportPath           = $reportFile.FullName
        JsonlLogPath         = $JsonlLogPath
        CandidateTaskCount   = $identities.Count
        RestoredTaskCount    = $restored.Count
        Tasks                = $restored
    }

    if ($PassThru) {
        $result
    }
}
catch {
    Write-WtcgErrorJsonlLog `
        -ErrorRecord $_ `
        -Path $JsonlLogPath `
        -Operation 'EmergencyRestoreLatestDisabledTasks' `
        -IdentityOutputPath $ArtifactPath `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath |
        Out-Null

    Save-WtcgRunReport `
        -RunContext $runContext `
        -Path $effectiveErrorReportPath `
        -Operation 'EmergencyRestoreLatestDisabledTasks' `
        -Status 'failed' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            artifactPath = $ArtifactPath
            jsonlLogPath = $JsonlLogPath
        }) |
        Out-Null

    Write-WtcgAuditEvent `
        -Action 'error' `
        -Operation 'EmergencyRestoreLatestDisabledTasks' `
        -Status 'failed' `
        -EventId 5210 `
        -EntryType 'Error' `
        -Details ([ordered]@{
            message = $_.Exception.Message
            artifactPath = $ArtifactPath
            jsonlLogPath = $JsonlLogPath
            runFolderPath = $RunFolderPath
        }) `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null

    throw
}
finally {
    if ($null -ne $runtimeLock) {
        Exit-WtcgRuntimeLock -Lock $runtimeLock
    }
}
