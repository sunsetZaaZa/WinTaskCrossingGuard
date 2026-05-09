#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
}

Describe 'Root script wrappers' {
    It 'keeps Disable-TasksInWindow.ps1 as a thin wrapper around scripts/Disable-TasksInWindow.ps1' {
        $rootScript = Join-Path $script:ProjectRoot 'Disable-TasksInWindow.ps1'
        $content = Get-Content -LiteralPath $rootScript -Raw

        $content | Should -Match '#requires -Version 7\.0'
        $content | Should -Match "scripts\\Disable-TasksInWindow\.ps1"
        $content | Should -Match '@args'
        $content | Should -Match 'exit \$LASTEXITCODE'
        $content | Should -Not -Match 'Import-Module'
        $content | Should -Not -Match '\[CmdletBinding\('
    }

    It 'keeps Restore-TasksFromManifest.ps1 as a thin wrapper around scripts/Restore-TasksFromManifest.ps1' {
        $rootScript = Join-Path $script:ProjectRoot 'Restore-TasksFromManifest.ps1'
        $content = Get-Content -LiteralPath $rootScript -Raw

        $content | Should -Match '#requires -Version 7\.0'
        $content | Should -Match "scripts\\Restore-TasksFromManifest\.ps1"
        $content | Should -Match '@args'
        $content | Should -Match 'exit \$LASTEXITCODE'
        $content | Should -Not -Match 'Import-Module'
        $content | Should -Not -Match '\[CmdletBinding\('
    }

    It 'keeps root wrappers small enough to prevent implementation drift' {
        @(
            Join-Path $script:ProjectRoot 'Disable-TasksInWindow.ps1'
            Join-Path $script:ProjectRoot 'Restore-TasksFromManifest.ps1'
        ) | ForEach-Object {
            $lineCount = (Get-Content -LiteralPath $_).Count
            $lineCount | Should -BeLessThan 10
        }
    }
}
