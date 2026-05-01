#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Central run folder and run ID' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
        } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates a unique run folder with the expected artifact subfolders and run-info file' {
        InModuleScope WinTaskCrossingGuard {
            $context = New-WtcgRunContext `
                -RunId 'wtcg-pester-run' `
                -RunRootPath $script:TempDir `
                -Operation 'PesterOperation'

            $context.RunId | Should -Be 'wtcg-pester-run'
            $context.RunFolderPath | Should -Be (Join-Path $script:TempDir 'wtcg-pester-run')

            @(
                $context.RunFolderPath
                $context.LogsPath
                $context.JsonlLogsPath
                $context.ManifestsPath
                $context.IdentitiesPath
                $context.ReportsPath
                $context.ErrorsPath
            ) | ForEach-Object {
                Test-Path -LiteralPath $_ | Should -BeTrue
            }

            Test-Path -LiteralPath $context.RunInfoPath | Should -BeTrue
            $runInfo = Get-Content -LiteralPath $context.RunInfoPath -Raw | ConvertFrom-Json
            $runInfo.Kind | Should -Be 'WinTaskCrossingGuard.RunInfo'
            $runInfo.RunId | Should -Be 'wtcg-pester-run'
            $runInfo.Operation | Should -Be 'PesterOperation'
            $runInfo.Folders.steamablelogs | Should -Be $context.JsonlLogsPath
        }
    }

    It 'resolves artifacts into the central run folder layout' {
        InModuleScope WinTaskCrossingGuard {
            $context = New-WtcgRunContext -RunId 'wtcg-layout' -RunRootPath $script:TempDir

            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Logs' -FileName 'disabled.xml' |
                Should -Be (Join-Path $context.LogsPath 'disabled.xml')
            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'events.jsonl' |
                Should -Be (Join-Path $context.JsonlLogsPath 'events.jsonl')
            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Manifests' -FileName 'rollback.json' |
                Should -Be (Join-Path $context.ManifestsPath 'rollback.json')
            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Identities' -FileName 'identities.json' |
                Should -Be (Join-Path $context.IdentitiesPath 'identities.json')
            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Reports' -FileName 'report.json' |
                Should -Be (Join-Path $context.ReportsPath 'report.json')
            Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Errors' -FileName 'error.json' |
                Should -Be (Join-Path $context.ErrorsPath 'error.json')
        }
    }

    It 'adds run correlation fields to manifests, reports, XML logs, and JSONL events' {
        InModuleScope WinTaskCrossingGuard {
            $context = New-WtcgRunContext -RunId 'wtcg-correlation' -RunRootPath $script:TempDir
            $task = [pscustomobject]@{
                TaskPath = '\Root\'
                TaskName = 'TaskA'
                State = 'Ready'
                OriginalState = 'Ready'
                WasOriginallyEnabled = $true
                DisabledBySuite = $true
                DisabledAt = [datetime]'2030-01-02T08:30:00'
                NextRunTime = [datetime]'2030-01-02T12:00:00'
            }

            $manifestPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Manifests' -FileName 'rollback-manifest.json'
            $manifestFile = $task | Save-WtcgManifest `
                -Path $manifestPath `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -RunId $context.RunId `
                -RunFolderPath $context.RunFolderPath

            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
            $manifest.RunId | Should -Be $context.RunId
            $manifest.RunFolderPath | Should -Be $context.RunFolderPath

            $reportFile = Save-WtcgRunReport `
                -RunContext $context `
                -Operation 'PesterOperation' `
                -Status 'succeeded' `
                -Details ([ordered]@{ manifestPath = $manifestFile.FullName })
            $report = Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json
            $report.RunId | Should -Be $context.RunId
            $report.RunFolderPath | Should -Be $context.RunFolderPath

            $xmlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'Logs' -FileName 'disabled-tasks.xml'
            $task | Write-WtcgDisableXmlLog `
                -Path $xmlPath `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -IdentityOutputPath $manifestFile.FullName `
                -RunId $context.RunId `
                -RunFolderPath $context.RunFolderPath |
                Out-Null
            [xml]$xml = Get-Content -LiteralPath $xmlPath -Raw
            $xml.WinTaskCrossingGuardDisableLog.runId | Should -Be $context.RunId
            $xml.WinTaskCrossingGuardDisableLog.RunId | Should -Be $context.RunId
            $xml.WinTaskCrossingGuardDisableLog.RunFolderPath | Should -Be $context.RunFolderPath

            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
            $task | Write-WtcgDisableJsonlLog `
                -Path $jsonlPath `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -IdentityOutputPath $manifestFile.FullName `
                -RunId $context.RunId `
                -RunFolderPath $context.RunFolderPath |
                Out-Null
            $event = Get-Content -LiteralPath $jsonlPath -Raw | ConvertFrom-Json
            $event.runId | Should -Be $context.RunId
            $event.runFolderPath | Should -Be $context.RunFolderPath
        }
    }
}
