function Clear-WtcgOldLogs {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),

        [Parameter()]
        [string] $LogsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'logs'),

        [Parameter()]
        [datetime] $Now = (Get-Date),

        [Parameter()]
        [string[]] $Filter = @('*.xml'),

        [Parameter()]
        [switch] $PassThru
    )

    $retentionDays = Get-WtcgLogRetentionDays -EnvPath $EnvPath

    if ($null -eq $retentionDays) {
        Write-Verbose "LOG_RETENTION is not configured. Skipping log cleanup."
        return
    }

    if (-not (Test-Path -LiteralPath $LogsPath)) {
        Write-Verbose "Logs folder does not exist. Skipping log cleanup: $LogsPath"
        return
    }

    $cutoff = $Now.AddDays(-1 * $retentionDays)

    $oldLogs = @(
        foreach ($filterItem in @($Filter)) {
            if ([string]::IsNullOrWhiteSpace($filterItem)) {
                continue
            }

            Get-ChildItem -LiteralPath $LogsPath -File -Filter $filterItem -ErrorAction Stop |
                Where-Object { $_.LastWriteTime -lt $cutoff }
        }
    ) | Sort-Object -Property FullName -Unique

    foreach ($logFile in $oldLogs) {
        if ($PSCmdlet.ShouldProcess($logFile.FullName, "Delete log file older than LOG_RETENTION=$retentionDays day(s)")) {
            Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop

            if ($PassThru) {
                [pscustomobject]@{
                    DeletedLogPath = $logFile.FullName
                    LastWriteTime  = $logFile.LastWriteTime
                    Cutoff         = $cutoff
                    RetentionDays  = $retentionDays
                }
            }
        }
    }
}
