#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Find-TasksInWindow.ps1') @args
exit $LASTEXITCODE
