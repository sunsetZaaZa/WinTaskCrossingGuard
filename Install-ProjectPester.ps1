#requires -Version 7.0

& (Join-Path $PSScriptRoot 'scripts\Install-ProjectPester.ps1') @args
exit $LASTEXITCODE
