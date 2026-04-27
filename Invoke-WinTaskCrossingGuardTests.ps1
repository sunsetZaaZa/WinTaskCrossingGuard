#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Invoke-WinTaskCrossingGuardTests.ps1') @args
exit $LASTEXITCODE
