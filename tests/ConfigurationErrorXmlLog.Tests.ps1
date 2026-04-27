#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Configuration error XML logging' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        # WTCG module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:ProjectRoot = $ProjectRoot
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes an XML error log that records the configuration error' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'error.xml'

            try {
                throw 'Invalid mail configuration test'
            }
            catch {
                $file = Write-WtcgErrorXmlLog `
                    -ErrorRecord $_ `
                    -Path $path `
                    -Operation 'PesterConfig' `
                    -SelectionSource 'C:\selection.json' `
                    -IdentityOutputPath 'C:\ids.json'
            }

            $file.Exists | Should -BeTrue

            [xml]$xml = Get-Content -Path $path -Raw

            $xml.WinTaskCrossingGuardErrorLog.operation | Should -Be 'PesterConfig'
            $xml.WinTaskCrossingGuardErrorLog.SelectionSource | Should -Be 'C:\selection.json'
            $xml.WinTaskCrossingGuardErrorLog.IdentityOutputPath | Should -Be 'C:\ids.json'
            $xml.WinTaskCrossingGuardErrorLog.Error.Message | Should -Match 'Invalid mail configuration test'
        }
    }
}
