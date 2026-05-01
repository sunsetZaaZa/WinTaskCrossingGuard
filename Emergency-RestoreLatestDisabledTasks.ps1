#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Emergency-RestoreLatestDisabledTasks.ps1') @args
exit $LASTEXITCODE
