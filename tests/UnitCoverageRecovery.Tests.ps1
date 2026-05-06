#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'WinTaskCrossingGuard coverage recovery tests' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns null for unreadable restore artifact JSON candidates' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'rollback-manifest.json'
            '{this is not json' | Set-Content -Path $path -Encoding utf8

            Get-WtcgRestoreArtifactSummary -Path $path | Should -BeNullOrEmpty
        }
    }

    It 'infers restore run metadata from the manifests folder when payload fields are absent' {
        InModuleScope WinTaskCrossingGuard {
            $runFolder = Join-Path $script:TempDir 'wtcg-inferred-run'
            $manifestFolder = Join-Path $runFolder 'manifests'
            New-Item -ItemType Directory -Path $manifestFolder -Force | Out-Null
            $path = Join-Path $manifestFolder 'rollback-manifest.json'

            [pscustomobject]@{
                Kind = 'WinTaskCrossingGuard.RollbackManifest'
                CreatedAt = '2030-01-02T03:04:05Z'
                Tasks = @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'RestoreMe'
                        OriginalState = 'Ready'
                        WasOriginallyEnabled = $true
                        DisabledBySuite = $true
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $summary = Get-WtcgRestoreArtifactSummary -Path $path

            $summary.RunFolderPath | Should -Be $runFolder
            $summary.RunId | Should -Be 'wtcg-inferred-run'
            $summary.TaskCount | Should -Be 1
            $summary.RestorableTaskCount | Should -Be 1
        }
    }

    It 'uses RunRootPath when finding the latest restore artifact without SearchPath' {
        InModuleScope WinTaskCrossingGuard {
            $runFolder = Join-Path $script:TempDir 'wtcg-runroot-only'
            $manifestFolder = Join-Path $runFolder 'manifests'
            New-Item -ItemType Directory -Path $manifestFolder -Force | Out-Null
            $path = Join-Path $manifestFolder 'rollback-manifest.json'

            [pscustomobject]@{
                Kind = 'WinTaskCrossingGuard.RollbackManifest'
                RunId = 'wtcg-runroot-only'
                RunFolderPath = $runFolder
                Tasks = @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'RestoreMe'
                        OriginalState = 'Ready'
                        WasOriginallyEnabled = $true
                        DisabledBySuite = $true
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $latest = Find-WtcgLatestRestoreArtifact -RunRootPath $script:TempDir

            $latest.Path | Should -Be $path
            $latest.RunId | Should -Be 'wtcg-runroot-only'
        }
    }

    It 'throws for invalid boolean text' {
        InModuleScope WinTaskCrossingGuard {
            { ConvertTo-WtcgBoolean -Value 'maybe' } |
                Should -Throw -ExpectedMessage '*Invalid boolean value*'
        }
    }

    It 'converts array values to a trimmed string list while removing blanks' {
        InModuleScope WinTaskCrossingGuard {
            $values = @(ConvertTo-WtcgStringList -Value @('alpha', '', '  ', 'beta', 42))

            $values.Count | Should -Be 3
            $values | Should -Contain 'alpha'
            $values | Should -Contain 'beta'
            $values | Should -Contain '42'
        }
    }

    It 'throws for invalid telemetry numeric settings' {
        InModuleScope WinTaskCrossingGuard {
            $cases = @(
                @{ Name = 'WTCG_TELEMETRY_TIMEOUT_SECONDS'; Value = '0'; Expected = '*WTCG_TELEMETRY_TIMEOUT_SECONDS*' }
                @{ Name = 'WTCG_TELEMETRY_BATCH_SIZE'; Value = '-1'; Expected = '*WTCG_TELEMETRY_BATCH_SIZE*' }
                @{ Name = 'WTCG_TELEMETRY_RETRY_COUNT'; Value = '-1'; Expected = '*WTCG_TELEMETRY_RETRY_COUNT*' }
                @{ Name = 'WTCG_TELEMETRY_RETRY_DELAY_SECONDS'; Value = '-1'; Expected = '*WTCG_TELEMETRY_RETRY_DELAY_SECONDS*' }
            )

            foreach ($case in $cases) {
                $envPath = Join-Path $script:TempDir "$($case.Name).env"
                "$($case.Name)=$($case.Value)" | Set-Content -Path $envPath -Encoding utf8

                { Get-WtcgTelemetrySettings -EnvPath $envPath } |
                    Should -Throw -ExpectedMessage $case.Expected
            }
        }
    }

    It 'uses defaults when optional telemetry names are blank' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_ELASTICSEARCH_INDEX=
WTCG_GENERIC_HTTP_METHOD=
WTCG_GENERIC_HTTP_FORMAT=
WTCG_GENERIC_HTTP_CONTENT_TYPE=
'@ | Set-Content -Path $envPath -Encoding utf8

            $settings = Get-WtcgTelemetrySettings -EnvPath $envPath

            $settings.Elasticsearch.Index | Should -Be 'wintaskcrossingguard-events'
            $settings.GenericHttp.Method | Should -Be 'Post'
            $settings.GenericHttp.Format | Should -Be 'ndjson'
            $settings.GenericHttp.ContentType | Should -Be 'application/x-ndjson'
        }
    }

    It 'throws for unsupported generic HTTP telemetry method and format' {
        InModuleScope WinTaskCrossingGuard {
            $cases = @(
                @{ Line = 'WTCG_GENERIC_HTTP_METHOD=Delete'; Expected = '*WTCG_GENERIC_HTTP_METHOD*' }
                @{ Line = 'WTCG_GENERIC_HTTP_FORMAT=xml'; Expected = '*WTCG_GENERIC_HTTP_FORMAT*' }
            )

            foreach ($case in $cases) {
                $envPath = Join-Path $script:TempDir ([System.Guid]::NewGuid().ToString() + '.env')
                $case.Line | Set-Content -Path $envPath -Encoding utf8

                { Get-WtcgTelemetrySettings -EnvPath $envPath } |
                    Should -Throw -ExpectedMessage $case.Expected
            }
        }
    }

    It 'throws when importing a missing JSONL event file' {
        InModuleScope WinTaskCrossingGuard {
            { Import-WtcgJsonlEvent -Path (Join-Path $script:TempDir 'missing.jsonl') } |
                Should -Throw -ExpectedMessage '*JSONL event file not found*'
        }
    }

    It 'throws with the line number when importing invalid JSONL content' {
        InModuleScope WinTaskCrossingGuard {
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            @(
                '{"action":"disable"}'
                '{invalid json}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            { Import-WtcgJsonlEvent -Path $jsonlPath } |
                Should -Throw -ExpectedMessage '*line 2*'
        }
    }

    It 'returns an empty bulk payload when no telemetry events are supplied' {
        InModuleScope WinTaskCrossingGuard {
            $payload = ConvertTo-WtcgElasticBulkPayload -Index 'wtcg-events'

            $payload | Should -Be ''
        }
    }

    It 'accepts string telemetry events when building Elasticsearch bulk payloads' {
        InModuleScope WinTaskCrossingGuard {
            $payload = '{"action":"disable","runId":"wtcg-string"}' |
                ConvertTo-WtcgElasticBulkPayload -Index 'wtcg-events'

            $lines = @($payload -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $lines.Count | Should -Be 2
            ($lines[1] | ConvertFrom-Json).runId | Should -Be 'wtcg-string'
        }
    }

    It 'builds HTTP headers from hashtable entries' {
        InModuleScope WinTaskCrossingGuard {
            $headers = ConvertTo-WtcgHttpHeaderDictionary -Headers @{ 'X-One' = '1'; 'X-Two' = '2' }

            $headers['X-One'] | Should -Be '1'
            $headers['X-Two'] | Should -Be '2'
        }
    }

    It 'throws when an HTTP header entry is malformed' {
        InModuleScope WinTaskCrossingGuard {
            { ConvertTo-WtcgHttpHeaderDictionary -Headers @('X-Good=1', 'BrokenHeader') } |
                Should -Throw -ExpectedMessage '*Invalid HTTP header entry*'
        }
    }

    It 'builds Elasticsearch authorization headers without leaking blanks' {
        InModuleScope WinTaskCrossingGuard {
            (Get-WtcgElasticAuthHeader -AuthType ApiKey -ApiKey '').Count | Should -Be 0
            (Get-WtcgElasticAuthHeader -AuthType Bearer -ApiKey 'token')['Authorization'] | Should -Be 'Bearer token'
            (Get-WtcgElasticAuthHeader -AuthType Basic -Username 'user' -Password 'pass')['Authorization'] | Should -Be 'Basic dXNlcjpwYXNz'
            (Get-WtcgElasticAuthHeader -AuthType None).Count | Should -Be 0
        }
    }

    It 'falls back cleanly when sanitizing an invalid telemetry result URI' {
        InModuleScope WinTaskCrossingGuard {
            $summary = ConvertTo-WtcgTelemetryExportResultSummary `
                -SinkName 'genericHttp' `
                -Uri 'http://[bad' `
                -EventCount 1

            $summary.Uri | Should -Be '[invalid-uri]'
            $summary.Sent | Should -BeFalse
        }
    }

    It 'reports configured telemetry sinks that are enabled without required URIs' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=genericHttp,elasticsearch
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_ELASTICSEARCH_ENABLED=true
'@ | Set-Content -Path $envPath -Encoding utf8
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            '{"action":"disable","runId":"wtcg-missing-uri"}' | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {}

            $result = Invoke-WtcgTelemetryExportForJsonl `
                -JsonlPath $jsonlPath `
                -EnvPath $envPath `
                -ReportPath (Join-Path $script:TempDir 'report.json')

            $result.Status | Should -Be 'completed-with-errors'
            @($result.Results).Count | Should -Be 2
            @($result.Results).Sent | Should -Not -Contain $true
            @($result.Results).Error | Should -Contain 'WTCG_GENERIC_HTTP_URI is not configured.'
            @($result.Results).Error | Should -Contain 'WTCG_ELASTICSEARCH_URI is not configured.'
            Should -Invoke Send-WtcgGenericHttpPayload -Times 0
        }
    }

    It 'skips telemetry export when no configured sinks are enabled' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=genericHttp
WTCG_GENERIC_HTTP_ENABLED=false
'@ | Set-Content -Path $envPath -Encoding utf8
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            '{"action":"disable","runId":"wtcg-no-sinks"}' | Set-Content -Path $jsonlPath -Encoding utf8

            $result = Invoke-WtcgTelemetryExportForJsonl `
                -JsonlPath $jsonlPath `
                -EnvPath $envPath `
                -ReportPath (Join-Path $script:TempDir 'report.json')

            $result.Status | Should -Be 'skipped-no-enabled-sinks'
            @($result.Results).Count | Should -Be 0
        }
    }

    It 'writes a telemetry error report when export throws and fail-on-error is disabled' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=genericHttp
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_GENERIC_HTTP_URI=https://collector.example.com/events
'@ | Set-Content -Path $envPath -Encoding utf8
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            $errorReportPath = Join-Path $script:TempDir 'telemetry-error.json'
            '{"action":"disable","runId":"wtcg-throwing-sink"}' | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload { throw 'collector exploded' }

            $result = Invoke-WtcgTelemetryExportForJsonl `
                -JsonlPath $jsonlPath `
                -EnvPath $envPath `
                -ErrorReportPath $errorReportPath

            $result.Status | Should -Be 'failed'
            $result.ReportPath | Should -Be $errorReportPath
            Test-Path -LiteralPath $errorReportPath | Should -BeTrue
            @($result.Results)[0].Error | Should -Match 'collector exploded'
        }
    }

    It 'skips direct Windows event log writes on non-Windows platforms' {
        InModuleScope WinTaskCrossingGuard {
            Mock Test-WtcgWindowsPlatform { $false }

            $result = Write-WtcgWindowsEventLog -EventId 4100 -Message 'not on this platform'

            $result.Written | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Error | Should -Match 'only available on Windows'
        }
    }

    It 'skips direct Windows event log writes when the source cannot be ensured' {
        InModuleScope WinTaskCrossingGuard {
            Mock Test-WtcgWindowsPlatform { $true }
            Mock Initialize-WtcgWindowsEventLogSource {
                [pscustomobject]@{
                    SourceExists = $false
                    Error = $null
                }
            }

            $result = Write-WtcgWindowsEventLog -EventId 4100 -Message 'source missing'

            $result.Written | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Error | Should -Match 'could not be created'
        }
    }
}
