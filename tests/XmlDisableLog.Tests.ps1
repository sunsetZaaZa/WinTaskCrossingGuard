#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Write-WtcgDisableXmlLog' {
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

    It 'writes an XML log with timestamp, window, metadata, and disabled task entries' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'disabled-tasks.xml'

            $tasks = @(
                [pscustomobject]@{
                    TaskPath = 'Root'
                    TaskName = 'TaskA'
                    State = 'Ready'
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                },
                [pscustomobject]@{
                    TaskPath = '\Root\Nested\'
                    TaskName = 'TaskB'
                    State = 'Queued'
                    NextRunTime = [datetime]'2030-01-02T13:00:00'
                }
            )

            $file = $tasks | Write-WtcgDisableXmlLog `
                -Path $path `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -ReenableAt ([datetime]'2030-01-02T18:00:00') `
                -SelectionSource 'C:\selection.json' `
                -IdentityOutputPath 'C:\identities.json' `
                -ReenableTaskFullName '\WinTaskCrossingGuard\ReenableDisabledTasks' `
                -Operation 'PesterOperation'

            $file.Exists | Should -BeTrue

            [xml]$xml = Get-Content -Path $path -Raw

            $xml.WinTaskCrossingGuardDisableLog.operation | Should -Be 'PesterOperation'
            $xml.WinTaskCrossingGuardDisableLog.createdAt | Should -Not -BeNullOrEmpty
            $xml.WinTaskCrossingGuardDisableLog.createdLocal | Should -Not -BeNullOrEmpty

            $xml.WinTaskCrossingGuardDisableLog.Window.Start | Should -Be ([datetime]'2030-01-02T08:00:00').ToString('o')
            $xml.WinTaskCrossingGuardDisableLog.Window.End | Should -Be ([datetime]'2030-01-02T17:00:00').ToString('o')
            $xml.WinTaskCrossingGuardDisableLog.ReenableAt | Should -Be ([datetime]'2030-01-02T18:00:00').ToString('o')
            $xml.WinTaskCrossingGuardDisableLog.SelectionSource | Should -Be 'C:\selection.json'
            $xml.WinTaskCrossingGuardDisableLog.IdentityOutputPath | Should -Be 'C:\identities.json'
            $xml.WinTaskCrossingGuardDisableLog.ReenableTaskFullName | Should -Be '\WinTaskCrossingGuard\ReenableDisabledTasks'

            $xml.WinTaskCrossingGuardDisableLog.Tasks.count | Should -Be '2'
            @($xml.WinTaskCrossingGuardDisableLog.Tasks.Task).Count | Should -Be 2

            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].TaskPath | Should -Be '\Root\'
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].TaskName | Should -Be 'TaskA'
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].FullName | Should -Be '\Root\TaskA'
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].StateAtDiscovery | Should -Be 'Ready'
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].NextRunTime | Should -Be ([datetime]'2030-01-02T12:00:00').ToString('o')
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].Action | Should -Be 'Disabled'
            $xml.WinTaskCrossingGuardDisableLog.Tasks.Task[0].LoggedAt | Should -Not -BeNullOrEmpty
        }
    }

    It 'omits optional metadata when optional values are absent' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'minimal.xml'

            $tasks = @(
                [pscustomobject]@{
                    TaskPath = '\Root\'
                    TaskName = 'TaskA'
                }
            )

            $tasks | Write-WtcgDisableXmlLog `
                -Path $path `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') |
                Out-Null

            [xml]$xml = Get-Content -Path $path -Raw

            $xml.SelectSingleNode('/WinTaskCrossingGuardDisableLog/SelectionSource') | Should -BeNullOrEmpty
            $xml.SelectSingleNode('/WinTaskCrossingGuardDisableLog/IdentityOutputPath') | Should -BeNullOrEmpty
            $xml.SelectSingleNode('/WinTaskCrossingGuardDisableLog/ReenableTaskFullName') | Should -BeNullOrEmpty
            $xml.SelectSingleNode('/WinTaskCrossingGuardDisableLog/Tasks').count | Should -Be '1'
        }
    }
}
