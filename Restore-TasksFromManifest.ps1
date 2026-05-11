#requires -Version 7.0

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts\Restore-TasksFromManifest.ps1'
& $scriptPath @args
exit $LASTEXITCODE
