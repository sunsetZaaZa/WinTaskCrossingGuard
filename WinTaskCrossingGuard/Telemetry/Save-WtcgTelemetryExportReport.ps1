function Save-WtcgTelemetryExportReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $RunContext,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'TelemetryExport',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlPath,

        [Parameter()]
        [AllowNull()]
        [object[]] $Results
    )

    if ([string]::IsNullOrWhiteSpace($Path) -and $null -ne $RunContext) {
        $Path = Resolve-WtcgRunArtifactPath -RunContext $RunContext -Kind 'Reports' -FileName 'telemetry-export-report.json'
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    [pscustomobject]@{
        Kind          = 'WinTaskCrossingGuard.TelemetryExportReport'
        Version       = 1
        RunId         = if ($null -ne $RunContext) { $RunContext.RunId } else { $null }
        RunFolderPath = if ($null -ne $RunContext) { $RunContext.RunFolderPath } else { $null }
        Operation     = $Operation
        Status        = $Status
        JsonlPath     = $JsonlPath
        CreatedAt     = (Get-Date).ToString('o')
        Results       = @($Results)
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding utf8 -WhatIf:$false

    Get-Item -LiteralPath $Path
}
