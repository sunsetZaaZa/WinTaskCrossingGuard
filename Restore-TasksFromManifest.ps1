#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Restore-TasksFromManifest.ps1') @args
exit $LASTEXITCODE
