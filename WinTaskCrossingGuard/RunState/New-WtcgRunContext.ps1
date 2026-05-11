function New-WtcgRunContext {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunRootPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [datetime] $CreatedAt = (Get-Date)
    )

    $effectiveRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { New-WtcgRunId } else { $RunId.Trim() }
    $safeRunFolderName = ConvertTo-WtcgSafePathName -Value $effectiveRunId

    $effectiveRunFolderPath = if (-not [string]::IsNullOrWhiteSpace($RunFolderPath)) {
        $RunFolderPath
    }
    else {
        Join-Path (Resolve-WtcgRunRootPath -Path $RunRootPath) $safeRunFolderName
    }

    $logsPath = Join-Path $effectiveRunFolderPath 'logs'
    $jsonlLogsPath = Join-Path $effectiveRunFolderPath 'streamablelogs'
    $manifestsPath = Join-Path $effectiveRunFolderPath 'manifests'
    $identitiesPath = Join-Path $effectiveRunFolderPath 'identities'
    $reportsPath = Join-Path $effectiveRunFolderPath 'reports'
    $errorsPath = Join-Path $effectiveRunFolderPath 'errors'

    foreach ($directory in @($effectiveRunFolderPath, $logsPath, $jsonlLogsPath, $manifestsPath, $identitiesPath, $reportsPath, $errorsPath)) {
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
        }
    }

    $context = [pscustomobject]@{
        PSTypeName        = 'WinTaskCrossingGuard.RunContext'
        RunId             = $effectiveRunId
        RunFolderPath     = $effectiveRunFolderPath
        LogsPath          = $logsPath
        JsonlLogsPath     = $jsonlLogsPath
        ManifestsPath     = $manifestsPath
        IdentitiesPath    = $identitiesPath
        ReportsPath       = $reportsPath
        ErrorsPath        = $errorsPath
        Operation         = $Operation
        CreatedAt         = $CreatedAt
        CreatedAtUtc      = $CreatedAt.ToUniversalTime().ToString('o')
    }

    $runInfoPath = Join-Path $effectiveRunFolderPath 'run-info.json'
    [pscustomobject]@{
        Kind          = 'WinTaskCrossingGuard.RunInfo'
        Version       = 1
        RunId         = $context.RunId
        RunFolderPath = $context.RunFolderPath
        Operation     = $Operation
        CreatedAt     = $CreatedAt.ToString('o')
        CreatedAtUtc  = $CreatedAt.ToUniversalTime().ToString('o')
        HostName      = $env:COMPUTERNAME
        UserName      = $env:USERNAME
        ProcessId     = $PID
        Folders       = [ordered]@{
            logs           = $context.LogsPath
            streamablelogs  = $context.JsonlLogsPath
            manifests      = $context.ManifestsPath
            identities     = $context.IdentitiesPath
            reports        = $context.ReportsPath
            errors         = $context.ErrorsPath
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $runInfoPath -Encoding utf8 -WhatIf:$false

    $context | Add-Member -NotePropertyName RunInfoPath -NotePropertyValue $runInfoPath -Force
    return $context
}
