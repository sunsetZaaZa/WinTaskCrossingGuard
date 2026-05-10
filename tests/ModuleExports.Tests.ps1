#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModuleRoot = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'WinTaskCrossingGuard.psd1'
}

Describe 'WinTaskCrossingGuard public exports' {
    It 'exports only functions from the Public source folder' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $publicFunctions = Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1' -File |
            Select-Object -ExpandProperty BaseName |
            Sort-Object

        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($publicFunctions)
    }

    It 'does not export private or categorized helper functions' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $helperFolders = @(
            'Private',
            'RunState',
            'Selection',
            'Scheduling',
            'Logging',
            'Telemetry',
            'Notifications'
        )

        $helperFunctions = foreach ($folder in $helperFolders) {
            Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot $folder) -Filter '*.ps1' -File |
                Select-Object -ExpandProperty BaseName
        }

        foreach ($helperFunction in $helperFunctions) {
            $manifest.FunctionsToExport | Should -Not -Contain $helperFunction
        }
    }

    It 'uses explicit export names rather than wildcard exports' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $manifest.FunctionsToExport | Should -Not -Contain '*'
    }
}
