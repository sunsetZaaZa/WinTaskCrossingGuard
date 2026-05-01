#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Emergency restore latest artifact discovery' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds the newest restorable identity or manifest JSON file under the run root' {
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
        } {
            param($TempDir)

            $olderContext = New-WtcgRunContext -RunId 'wtcg-older' -RunRootPath $TempDir
            $newerContext = New-WtcgRunContext -RunId 'wtcg-newer' -RunRootPath $TempDir

            $olderTask = [pscustomobject]@{
                TaskPath = '\Root\'
                TaskName = 'Older'
                State = 'Ready'
                OriginalState = 'Ready'
                WasOriginallyEnabled = $true
                DisabledBySuite = $true
            }
            $newerTask = [pscustomobject]@{
                TaskPath = '\Root\'
                TaskName = 'Newer'
                State = 'Ready'
                OriginalState = 'Ready'
                WasOriginallyEnabled = $true
                DisabledBySuite = $true
            }

            $olderPath = Resolve-WtcgRunArtifactPath -RunContext $olderContext -Kind 'Manifests' -FileName 'rollback-manifest.json'
            $newerPath = Resolve-WtcgRunArtifactPath -RunContext $newerContext -Kind 'Manifests' -FileName 'rollback-manifest.json'

            $olderTask | Save-WtcgManifest `
                -Path $olderPath `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -RunId $olderContext.RunId `
                -RunFolderPath $olderContext.RunFolderPath |
                Out-Null

            $newerTask | Save-WtcgManifest `
                -Path $newerPath `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -RunId $newerContext.RunId `
                -RunFolderPath $newerContext.RunFolderPath |
                Out-Null

            (Get-Item -LiteralPath $olderPath).LastWriteTimeUtc = [datetime]'2030-01-02T10:00:00Z'
            (Get-Item -LiteralPath $newerPath).LastWriteTimeUtc = [datetime]'2030-01-02T11:00:00Z'

            $latest = Find-WtcgLatestRestoreArtifact -SearchPath $TempDir

            $latest.Path | Should -Be $newerPath
            $latest.RunId | Should -Be 'wtcg-newer'
            $latest.TaskCount | Should -Be 1
            $latest.RestorableTaskCount | Should -Be 1
        }
    }

    It 'imports only tasks that were originally enabled and disabled by this suite run' {
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
        } {
            param($TempDir)

            $context = New-WtcgRunContext -RunId 'wtcg-filter' -RunRootPath $TempDir
            $manifestPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Manifests' -FileName 'rollback-manifest.json'

            [pscustomobject]@{
                Kind = 'WinTaskCrossingGuard.RollbackManifest'
                RunId = $context.RunId
                RunFolderPath = $context.RunFolderPath
                Tasks = @(
                    @{
                        TaskPath = '\Root\'
                        TaskName = 'RestoreMe'
                        OriginalState = 'Ready'
                        WasOriginallyEnabled = $true
                        DisabledBySuite = $true
                    }
                    @{
                        TaskPath = '\Root\'
                        TaskName = 'LeaveDisabled'
                        OriginalState = 'Disabled'
                        WasOriginallyEnabled = $false
                        DisabledBySuite = $false
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding utf8

            $identities = @(Import-WtcgRestoreArtifactTaskIdentity -Path $manifestPath)

            $identities.Count | Should -Be 1
            $identities[0].TaskName | Should -Be 'RestoreMe'
            $identities[0].DisabledBySuite | Should -BeTrue
        }
    }

    It 'ships a root wrapper for the emergency restore script' {
        Test-Path (Join-Path $script:ProjectRoot 'Emergency-RestoreLatestDisabledTasks.ps1') | Should -BeTrue
    }
}
