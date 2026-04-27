#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Disable-TasksInWindow.ps1') @args
exit $LASTEXITCODE
