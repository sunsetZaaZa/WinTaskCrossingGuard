#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Enable-TaskIdentities.ps1') @args
exit $LASTEXITCODE
