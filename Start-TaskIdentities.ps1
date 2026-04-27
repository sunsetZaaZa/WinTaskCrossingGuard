#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Start-TaskIdentities.ps1') @args
exit $LASTEXITCODE
