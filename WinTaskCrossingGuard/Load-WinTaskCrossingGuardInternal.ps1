#requires -Version 7.0
<#
.SYNOPSIS
Loads every WinTaskCrossingGuard source file into the caller scope.

.DESCRIPTION
This loader is for repository wrapper scripts and tests that need access to the
module's private implementation functions while the published module manifest
exports only the supported public command surface.
#>

Set-StrictMode -Version Latest

$wtcgInternalSourceFolders = @(
    'Private',
    'RunState',
    'Selection',
    'Scheduling',
    'Logging',
    'Telemetry',
    'Notifications',
    'Public'
)

foreach ($sourceFolder in $wtcgInternalSourceFolders) {
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $sourceFolder

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Module source folder '$sourceFolder' was not found at '$sourcePath'."
    }

    Get-ChildItem -LiteralPath $sourcePath -Filter '*.ps1' -File |
        Sort-Object -Property Name |
        ForEach-Object {
            . $_.FullName
        }
}
