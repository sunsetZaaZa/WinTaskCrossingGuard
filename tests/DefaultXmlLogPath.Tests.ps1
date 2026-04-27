#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Default XML log path behavior' {
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

    It 'resolves an empty XML log path to logs folder with current date/time filename' {
        InModuleScope WinTaskCrossingGuard {
            $result = Resolve-WtcgXmlLogPath -Path '' -BaseDirectory $script:TempDir

            Split-Path -Parent $result | Should -Be (Join-Path $script:TempDir 'logs')
            Split-Path -Leaf $result | Should -Match '^disabled-tasks-\d{8}-\d{6}\.xml$'
        }
    }

    It 'keeps the provided XML log path unchanged' {
        InModuleScope WinTaskCrossingGuard {
            $provided = Join-Path $script:TempDir 'custom.xml'

            Resolve-WtcgXmlLogPath -Path $provided -BaseDirectory 'C:\Ignored' | Should -Be $provided
        }
    }

    It 'writes to logs folder with timestamp when Write-WtcgDisableXmlLog receives no path' {
        InModuleScope WinTaskCrossingGuard {
            Push-Location $script:TempDir
            try {
                $task = [pscustomobject]@{
                    TaskPath = '\Root\'
                    TaskName = 'TaskA'
                    State = 'Ready'
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                }

                $file = $task | Write-WtcgDisableXmlLog `
                    -WindowStart ([datetime]'2030-01-02T08:00:00') `
                    -WindowEnd ([datetime]'2030-01-02T17:00:00')

                $file.Exists | Should -BeTrue
                $file.Directory.Name | Should -Be 'logs'
                $file.Name | Should -Match '^disabled-tasks-\d{8}-\d{6}\.xml$'

                [xml]$xml = Get-Content -Path $file.FullName -Raw
                $xml.WinTaskCrossingGuardDisableLog.Tasks.count | Should -Be '1'
            }
            finally {
                Pop-Location
            }
        }
    }
}
