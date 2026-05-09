function Exit-WtcgRuntimeLock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Lock
    )

    if ($null -eq $Lock) {
        return
    }

    try {
        if ((Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Acquired' -DefaultValue $false) -and
            $null -ne (Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Mutex')) {
            $Lock.Mutex.ReleaseMutex()
        }
    }
    finally {
        if ($null -ne (Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'Mutex')) {
            $Lock.Mutex.Dispose()
        }

        $lockPath = Get-WtcgObjectPropertyValue -InputObject $Lock -Name 'LockPath'
        if (-not [string]::IsNullOrWhiteSpace([string]$lockPath) -and (Test-Path -LiteralPath $lockPath)) {
            if ($PSCmdlet.ShouldProcess($lockPath, 'Remove WinTaskCrossingGuard runtime lock file')) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
        }
    }
}
