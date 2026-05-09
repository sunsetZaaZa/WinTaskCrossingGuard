function Save-WtcgRuntimeLockFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $LockName,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Metadata
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    $payload = [pscustomobject]@{
        Kind         = 'WinTaskCrossingGuard.RuntimeLock'
        Version      = 1
        LockName     = $LockName
        HostName     = $env:COMPUTERNAME
        ProcessId    = $PID
        StartedAtUtc = [datetime]::UtcNow.ToString('o')
        UserName     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Metadata     = $Metadata
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Write WinTaskCrossingGuard runtime lock file')) {
        $payload |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $Path -Encoding utf8 -WhatIf:$false
    }

    if (Test-Path -LiteralPath $Path) {
        Get-Item -LiteralPath $Path
    }
}
