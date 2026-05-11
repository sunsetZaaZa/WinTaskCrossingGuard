#requires -Version 7.0

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts\Emergency-RestoreLatestDisabledTasks.ps1'
& $scriptPath @args
exit $LASTEXITCODE
