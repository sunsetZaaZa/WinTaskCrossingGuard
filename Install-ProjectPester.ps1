#requires -Version 7.0

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'scripts\Install-ProjectPester.ps1'
& $scriptPath @args
exit $LASTEXITCODE
