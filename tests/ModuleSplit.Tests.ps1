#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModuleRoot = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard'
    $script:ModuleManifestPath = Join-Path $script:ModuleRoot 'WinTaskCrossingGuard.psd1'
    $script:ModuleLoaderPath = Join-Path $script:ModuleRoot 'WinTaskCrossingGuard.psm1'
    $script:SourceFolders = @(
        'Private'
        'RunState'
        'Selection'
        'Scheduling'
        'Logging'
        'Telemetry'
        'Notifications'
        'Public'
    )
}

Describe 'Module split layout' {
    It 'keeps the root module file as a dot-source loader instead of a monolith' {
        $content = Get-Content -LiteralPath $script:ModuleLoaderPath -Raw
        $lineCount = (Get-Content -LiteralPath $script:ModuleLoaderPath).Count

        $lineCount | Should -BeLessThan 80
        $content | Should -Match '\$script:WtcgModuleSourceFolders'
        $content | Should -Match 'Get-ChildItem'
        $content | Should -Match '\. \$_.FullName'
        $content | Should -Not -Match '(?m)^function\s+[A-Za-z0-9-]+\s*\{'
    }

    It 'ships each expected module source folder' {
        foreach ($folder in $script:SourceFolders) {
            $path = Join-Path $script:ModuleRoot $folder
            Test-Path -LiteralPath $path -PathType Container | Should -BeTrue
            @(Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File).Count | Should -BeGreaterThan 0
        }
    }

    It 'stores one function per source file and names the file after the function' {
        foreach ($folder in $script:SourceFolders) {
            Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot $folder) -Filter '*.ps1' -File | ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -Raw
                $matches = [regex]::Matches($content, '(?m)^function\s+([A-Za-z0-9-]+)\s*\{')

                $matches.Count | Should -Be 1
                $matches[0].Groups[1].Value | Should -Be $_.BaseName
            }
        }
    }

    It 'has exactly one source file for each manifest-exported function' {
        $manifest = Import-PowerShellDataFile -LiteralPath $script:ModuleManifestPath
        $functionFiles = @{}

        foreach ($folder in $script:SourceFolders) {
            Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot $folder) -Filter '*.ps1' -File | ForEach-Object {
                $functionFiles[$_.BaseName] = $_.FullName
            }
        }

        foreach ($functionName in $manifest.FunctionsToExport) {
            $functionFiles.ContainsKey($functionName) | Should -BeTrue
        }
    }

    It 'does not define duplicate functions across split source files' {
        $seen = @{}

        foreach ($folder in $script:SourceFolders) {
            Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot $folder) -Filter '*.ps1' -File | ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -Raw
                $match = [regex]::Match($content, '(?m)^function\s+([A-Za-z0-9-]+)\s*\{')
                $name = $match.Groups[1].Value

                $seen.ContainsKey($name) | Should -BeFalse
                $seen[$name] = $_.FullName
            }
        }
    }
}
