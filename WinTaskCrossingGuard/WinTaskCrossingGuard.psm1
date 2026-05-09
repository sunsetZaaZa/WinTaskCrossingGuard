Set-StrictMode -Version Latest

$script:WtcgModuleSourceFolders = @(
    'Private',
    'RunState',
    'Selection',
    'Scheduling',
    'Logging',
    'Telemetry',
    'Notifications',
    'Public'
)

foreach ($sourceFolder in $script:WtcgModuleSourceFolders) {
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
