function Enter-WtcgRuntimeLock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string] $LockName = 'Global\WinTaskCrossingGuard',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $LockPath,

        [Parameter()]
        [int] $TimeoutSeconds = 0,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Metadata,

        [Parameter()]
        [switch] $SkipLockFile
    )

    $normalizedName = New-WtcgRuntimeLockName -Name $LockName
    $mutex = [System.Threading.Mutex]::new($false, $normalizedName)

    try {
        $timeout = if ($TimeoutSeconds -lt 0) {
            [System.Threading.Timeout]::InfiniteTimeSpan
        }
        else {
            [TimeSpan]::FromSeconds($TimeoutSeconds)
        }

        $acquired = $mutex.WaitOne($timeout)
        if (-not $acquired) {
            $message = "Another WinTaskCrossingGuard run is already active on this host using lock '$normalizedName'."
            $resolvedPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
            if ($resolvedPath -and (Test-Path -LiteralPath $resolvedPath)) {
                $message += " Lock file: $resolvedPath"
            }
            throw $message
        }

        $resolvedLockPath = $null
        if (-not $SkipLockFile) {
            $resolvedLockPath = Resolve-WtcgRuntimeLockPath -Path $LockPath
            if (-not [string]::IsNullOrWhiteSpace($resolvedLockPath)) {
                Save-WtcgRuntimeLockFile -Path $resolvedLockPath -LockName $normalizedName -Metadata $Metadata -WhatIf:$WhatIfPreference | Out-Null
            }
        }

        [pscustomobject]@{
            PSTypeName = 'WinTaskCrossingGuard.RuntimeLock'
            LockName   = $normalizedName
            Mutex      = $mutex
            LockPath   = $resolvedLockPath
            Acquired   = $true
        }
    }
    catch {
        $mutex.Dispose()
        throw
    }
}
