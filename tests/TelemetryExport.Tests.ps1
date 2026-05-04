#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Telemetry export Stage 1 configuration and payload building' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports telemetry and Elasticsearch settings from .env' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_EVENTS=result,error,disable
WTCG_TELEMETRY_FAIL_ON_ERROR=true
WTCG_TELEMETRY_TIMEOUT_SECONDS=22
WTCG_TELEMETRY_BATCH_SIZE=250
WTCG_TELEMETRY_RETRY_COUNT=3
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=4
WTCG_TELEMETRY_SINKS=elasticsearch,opensearch
WTCG_ELASTICSEARCH_ENABLED=true
WTCG_ELASTICSEARCH_URI=https://elastic.example.com:9200
WTCG_ELASTICSEARCH_INDEX=wtcg-events
WTCG_ELASTICSEARCH_DATA_STREAM=true
WTCG_ELASTICSEARCH_AUTH_TYPE=ApiKey
WTCG_ELASTICSEARCH_API_KEY=secret-api-key
WTCG_ELASTICSEARCH_ALLOW_INSECURE_TLS=true
'@ | Set-Content -Path $envPath -Encoding utf8

            $settings = Get-WtcgTelemetrySettings -EnvPath $envPath

            $settings.Enabled | Should -BeTrue
            $settings.Events | Should -Contain 'result'
            $settings.Events | Should -Contain 'disable'
            $settings.FailOnError | Should -BeTrue
            $settings.TimeoutSeconds | Should -Be 22
            $settings.BatchSize | Should -Be 250
            $settings.RetryCount | Should -Be 3
            $settings.RetryDelaySeconds | Should -Be 4
            $settings.Sinks | Should -Contain 'elasticsearch'
            $settings.Sinks | Should -Contain 'opensearch'

            $settings.Elasticsearch.Enabled | Should -BeTrue
            $settings.Elasticsearch.Uri | Should -Be 'https://elastic.example.com:9200'
            $settings.Elasticsearch.Index | Should -Be 'wtcg-events'
            $settings.Elasticsearch.DataStream | Should -BeTrue
            $settings.Elasticsearch.AuthType | Should -Be 'ApiKey'
            $settings.Elasticsearch.ApiKey | Should -Be 'secret-api-key'
            $settings.Elasticsearch.AllowInsecureTls | Should -BeTrue
        }
    }

    It 'uses safe telemetry defaults when .env is missing' {
        InModuleScope WinTaskCrossingGuard {
            $settings = Get-WtcgTelemetrySettings -EnvPath (Join-Path $script:TempDir 'missing.env')

            $settings.Enabled | Should -BeFalse
            $settings.FailOnError | Should -BeFalse
            $settings.TimeoutSeconds | Should -Be 15
            $settings.BatchSize | Should -Be 100
            $settings.RetryCount | Should -Be 2
            $settings.RetryDelaySeconds | Should -Be 2
            $settings.Sinks | Should -Contain 'elasticsearch'
            $settings.Elasticsearch.Enabled | Should -BeFalse
            $settings.Elasticsearch.Index | Should -Be 'wintaskcrossingguard-events'
            $settings.Elasticsearch.AuthType | Should -Be 'None'
        }
    }

    It 'throws for unsupported Elasticsearch auth type' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'WTCG_ELASTICSEARCH_AUTH_TYPE=TokenGoblin' | Set-Content -Path $envPath -Encoding utf8

            { Get-WtcgTelemetrySettings -EnvPath $envPath } |
                Should -Throw '*WTCG_ELASTICSEARCH_AUTH_TYPE*'
        }
    }

    It 'imports newline-delimited JSON events from a JSONL file' {
        InModuleScope WinTaskCrossingGuard {
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            @(
                '{"action":"disable","runId":"wtcg-1"}'
                ''
                '{"action":"error","runId":"wtcg-1"}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            $events = @(Import-WtcgJsonlEvent -Path $jsonlPath)

            $events.Count | Should -Be 2
            $events[0].action | Should -Be 'disable'
            $events[1].action | Should -Be 'error'
        }
    }

    It 'builds an Elasticsearch bulk NDJSON payload from JSONL events' {
        InModuleScope WinTaskCrossingGuard {
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
            @(
                '{"schemaVersion":"1.0","action":"disable","runId":"wtcg-1"}'
                '{"schemaVersion":"1.0","action":"notification","runId":"wtcg-1"}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            $payload = ConvertTo-WtcgElasticBulkPayload `
                -JsonlPath $jsonlPath `
                -Index 'wtcg-events' `
                -DataStream

            $payload.EndsWith("`n") | Should -BeTrue
            $lines = @($payload -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $lines.Count | Should -Be 4

            $metadata1 = $lines[0] | ConvertFrom-Json
            $document1 = $lines[1] | ConvertFrom-Json
            $metadata2 = $lines[2] | ConvertFrom-Json
            $document2 = $lines[3] | ConvertFrom-Json

            $metadata1.create._index | Should -Be 'wtcg-events'
            $metadata2.create._index | Should -Be 'wtcg-events'
            $document1.action | Should -Be 'disable'
            $document1.runId | Should -Be 'wtcg-1'
            $document2.action | Should -Be 'notification'
        }
    }

    It 'builds an index bulk payload from piped event objects' {
        InModuleScope WinTaskCrossingGuard {
            $events = @(
                [pscustomobject]@{ action = 'disable'; runId = 'wtcg-pipeline' },
                [pscustomobject]@{ action = 're-enable'; runId = 'wtcg-pipeline' }
            )

            $payload = $events | ConvertTo-WtcgElasticBulkPayload -Index 'wtcg-index'
            $lines = @($payload -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            $lines.Count | Should -Be 4
            ($lines[0] | ConvertFrom-Json).index._index | Should -Be 'wtcg-index'
            ($lines[1] | ConvertFrom-Json).runId | Should -Be 'wtcg-pipeline'
            ($lines[2] | ConvertFrom-Json).index._index | Should -Be 'wtcg-index'
            ($lines[3] | ConvertFrom-Json).action | Should -Be 're-enable'
        }
    }

    It 'does not include configured secrets in generated bulk payloads' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_ELASTICSEARCH_AUTH_TYPE=ApiKey
WTCG_ELASTICSEARCH_API_KEY=super-secret-key
'@ | Set-Content -Path $envPath -Encoding utf8
            $settings = Get-WtcgTelemetrySettings -EnvPath $envPath

            $payload = [pscustomobject]@{ action = 'disable'; runId = 'wtcg-safe' } |
                ConvertTo-WtcgElasticBulkPayload -Index $settings.Elasticsearch.Index

            $payload | Should -Not -Match 'super-secret-key'
        }
    }
}

Describe 'Telemetry export Stage 2 generic HTTP sender' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports generic HTTP telemetry settings from .env' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_GENERIC_HTTP_URI=https://collector.example.com/events
WTCG_GENERIC_HTTP_METHOD=Patch
WTCG_GENERIC_HTTP_FORMAT=jsonArray
WTCG_GENERIC_HTTP_CONTENT_TYPE=application/json
WTCG_GENERIC_HTTP_HEADERS=X-WTCG-Source=WinTaskCrossingGuard;X-Env=prod
WTCG_GENERIC_HTTP_AUTH_HEADER_NAME=Authorization
WTCG_GENERIC_HTTP_AUTH_HEADER_VALUE=Bearer secret-token
WTCG_GENERIC_HTTP_ALLOW_INSECURE_TLS=true
'@ | Set-Content -Path $envPath -Encoding utf8

            $settings = Get-WtcgTelemetrySettings -EnvPath $envPath

            $settings.GenericHttp.Enabled | Should -BeTrue
            $settings.GenericHttp.Uri | Should -Be 'https://collector.example.com/events'
            $settings.GenericHttp.Method | Should -Be 'Patch'
            $settings.GenericHttp.Format | Should -Be 'jsonArray'
            $settings.GenericHttp.ContentType | Should -Be 'application/json'
            $settings.GenericHttp.Headers | Should -Contain 'X-WTCG-Source=WinTaskCrossingGuard'
            $settings.GenericHttp.Headers | Should -Contain 'X-Env=prod'
            $settings.GenericHttp.AuthHeaderName | Should -Be 'Authorization'
            $settings.GenericHttp.AuthHeaderValue | Should -Be 'Bearer secret-token'
            $settings.GenericHttp.AllowInsecureTls | Should -BeTrue
        }
    }

    It 'builds HTTP headers from static entries and an auth header' {
        InModuleScope WinTaskCrossingGuard {
            $headers = ConvertTo-WtcgHttpHeaderDictionary `
                -Headers @('X-WTCG-Source=WinTaskCrossingGuard', 'X-Environment=Test') `
                -AuthHeaderName 'Authorization' `
                -AuthHeaderValue 'Bearer secret-token'

            $headers['X-WTCG-Source'] | Should -Be 'WinTaskCrossingGuard'
            $headers['X-Environment'] | Should -Be 'Test'
            $headers['Authorization'] | Should -Be 'Bearer secret-token'
        }
    }

    It 'sends a generic HTTP payload with timeout headers and TLS option without returning header secrets' {
        InModuleScope WinTaskCrossingGuard {
            Mock Invoke-WtcgTelemetryRestMethod {
                [pscustomobject]@{ ok = $true }
            }

            $result = Send-WtcgGenericHttpPayload `
                -Uri 'https://collector.example.com/events' `
                -Method 'Put' `
                -Body '{"ok":true}' `
                -ContentType 'application/json' `
                -Headers @('X-WTCG-Source=WinTaskCrossingGuard') `
                -AuthHeaderName 'Authorization' `
                -AuthHeaderValue 'Bearer secret-token' `
                -TimeoutSeconds 22 `
                -RetryCount 0 `
                -RetryDelaySeconds 0 `
                -AllowInsecureTls

            $result.Sent | Should -BeTrue
            $result.Method | Should -Be 'Put'
            $result.TimeoutSeconds | Should -Be 22
            $result.AllowInsecureTls | Should -BeTrue
            $result.HeaderNames | Should -Contain 'Authorization'
            $result | ConvertTo-Json -Depth 10 | Should -Not -Match 'secret-token'

            Should -Invoke Invoke-WtcgTelemetryRestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://collector.example.com/events' -and
                $Method -eq 'Put' -and
                $ContentType -eq 'application/json' -and
                $TimeoutSeconds -eq 22 -and
                $AllowInsecureTls -and
                $Headers['Authorization'] -eq 'Bearer secret-token' -and
                $Headers['X-WTCG-Source'] -eq 'WinTaskCrossingGuard'
            }
        }
    }

    It 'retries transient HTTP sender failures before succeeding' {
        InModuleScope WinTaskCrossingGuard {
            $script:Attempts = 0
            Mock Start-Sleep {}
            Mock Invoke-WtcgTelemetryRestMethod {
                $script:Attempts++
                if ($script:Attempts -lt 3) {
                    throw 'temporary collector outage'
                }
                [pscustomobject]@{ ok = $true }
            }

            $result = Invoke-WtcgHttpRequestWithRetry `
                -Uri 'https://collector.example.com/events' `
                -Body 'payload' `
                -RetryCount 2 `
                -RetryDelaySeconds 9

            $result.Sent | Should -BeTrue
            $result.AttemptCount | Should -Be 3
            Should -Invoke Invoke-WtcgTelemetryRestMethod -Times 3
            Should -Invoke Start-Sleep -Times 2 -ParameterFilter { $Seconds -eq 9 }
        }
    }

    It 'returns a sanitized failure result when sending fails and fail-on-error is disabled' {
        InModuleScope WinTaskCrossingGuard {
            Mock Start-Sleep {}
            Mock Invoke-WtcgTelemetryRestMethod { throw 'collector down' }

            $result = Send-WtcgGenericHttpPayload `
                -Uri 'https://collector.example.com/events' `
                -Body 'payload' `
                -Headers @('X-Secret=super-secret-header') `
                -RetryCount 1 `
                -RetryDelaySeconds 0

            $result.Sent | Should -BeFalse
            $result.AttemptCount | Should -Be 2
            $result.Error | Should -Match 'collector down'
            $result.HeaderNames | Should -Contain 'X-Secret'
            $result | ConvertTo-Json -Depth 10 | Should -Not -Match 'super-secret-header'
        }
    }

    It 'throws when sending fails and fail-on-error is enabled' {
        InModuleScope WinTaskCrossingGuard {
            Mock Start-Sleep {}
            Mock Invoke-WtcgTelemetryRestMethod { throw 'collector down' }

            {
                Send-WtcgGenericHttpPayload `
                    -Uri 'https://collector.example.com/events' `
                    -Body 'payload' `
                    -RetryCount 0 `
                    -RetryDelaySeconds 0 `
                    -FailOnError
            } | Should -Throw '*collector down*'
        }
    }

    It 'passes SkipCertificateCheck to Invoke-RestMethod when insecure TLS is allowed on PowerShell 7+' {
        InModuleScope WinTaskCrossingGuard {
            Mock Invoke-RestMethod {
                [pscustomobject]@{ ok = $true }
            }

            Invoke-WtcgTelemetryRestMethod `
                -Uri 'https://collector.example.com/events' `
                -Body 'payload' `
                -AllowInsecureTls | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://collector.example.com/events' -and
                $SkipCertificateCheck -eq $true
            }
        }
    }
}

Describe 'Telemetry export Stage 4 workflow integration helpers' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exports JSONL events to the generic HTTP sink and writes a run report without secrets' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_EVENTS=disable
WTCG_TELEMETRY_SINKS=genericHttp
WTCG_TELEMETRY_TIMEOUT_SECONDS=21
WTCG_TELEMETRY_RETRY_COUNT=0
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=0
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_GENERIC_HTTP_URI=https://collector.example.com/events?token=secret-query-token
WTCG_GENERIC_HTTP_METHOD=Post
WTCG_GENERIC_HTTP_FORMAT=jsonArray
WTCG_GENERIC_HTTP_CONTENT_TYPE=application/json
WTCG_GENERIC_HTTP_HEADERS=X-WTCG-Source=WinTaskCrossingGuard
WTCG_GENERIC_HTTP_AUTH_HEADER_NAME=Authorization
WTCG_GENERIC_HTTP_AUTH_HEADER_VALUE=Bearer secret-token
'@ | Set-Content -Path $envPath -Encoding utf8

            $context = New-WtcgRunContext -RunId 'wtcg-telemetry-stage4' -RunRootPath $script:TempDir
            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
            @(
                '{"schemaVersion":"1.0","action":"disable","runId":"wtcg-telemetry-stage4"}'
                '{"schemaVersion":"1.0","action":"notification","runId":"wtcg-telemetry-stage4"}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {
                [pscustomobject]@{
                    Sent = $true
                    Uri = $Uri
                    Method = $Method
                    ContentType = $ContentType
                    AttemptCount = 1
                    StatusCode = $null
                    Error = $null
                    HeaderNames = @('Authorization', 'X-WTCG-Source')
                }
            }

            $result = Invoke-WtcgTelemetryExportForJsonl `
                -JsonlPath $jsonlPath `
                -RunContext $context `
                -EnvPath $envPath `
                -Operation 'PesterTelemetryExport'

            $result.Enabled | Should -BeTrue
            $result.Status | Should -Be 'succeeded'
            Test-Path -LiteralPath $result.ReportPath | Should -BeTrue

            $reportText = Get-Content -LiteralPath $result.ReportPath -Raw
            $reportText | Should -Not -Match 'secret-token'
            $reportText | Should -Not -Match 'secret-query-token'
            $report = $reportText | ConvertFrom-Json
            $report.Kind | Should -Be 'WinTaskCrossingGuard.TelemetryExportReport'
            $report.Operation | Should -Be 'PesterTelemetryExport'
            $report.RunId | Should -Be 'wtcg-telemetry-stage4'
            @($report.Results)[0].SinkName | Should -Be 'genericHttp'
            @($report.Results)[0].Sent | Should -BeTrue
            @($report.Results)[0].Uri | Should -Be 'https://collector.example.com/events'

            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://collector.example.com/events?token=secret-query-token' -and
                $Method -eq 'Post' -and
                $ContentType -eq 'application/json' -and
                $TimeoutSeconds -eq 21 -and
                $RetryCount -eq 0 -and
                $RetryDelaySeconds -eq 0 -and
                $AuthHeaderValue -eq 'Bearer secret-token' -and
                ($Body | ConvertFrom-Json).Count -eq 1 -and
                ($Body | ConvertFrom-Json)[0].action -eq 'disable'
            }
        }
    }

    It 'exports JSONL events to Elasticsearch bulk endpoint using NDJSON and sanitized reports' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_EVENTS=disable,notification
WTCG_TELEMETRY_SINKS=elasticsearch
WTCG_TELEMETRY_RETRY_COUNT=0
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=0
WTCG_ELASTICSEARCH_ENABLED=true
WTCG_ELASTICSEARCH_URI=https://elastic.example.com:9200/base?apikey=secret-query
WTCG_ELASTICSEARCH_INDEX=wtcg-events
WTCG_ELASTICSEARCH_DATA_STREAM=true
WTCG_ELASTICSEARCH_AUTH_TYPE=ApiKey
WTCG_ELASTICSEARCH_API_KEY=super-secret-api-key
WTCG_ELASTICSEARCH_ALLOW_INSECURE_TLS=true
'@ | Set-Content -Path $envPath -Encoding utf8

            $context = New-WtcgRunContext -RunId 'wtcg-elastic-stage4' -RunRootPath $script:TempDir
            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
            @(
                '{"schemaVersion":"1.0","action":"disable","runId":"wtcg-elastic-stage4"}'
                '{"schemaVersion":"1.0","action":"notification","runId":"wtcg-elastic-stage4"}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {
                [pscustomobject]@{
                    Sent = $true
                    Uri = $Uri
                    Method = $Method
                    ContentType = $ContentType
                    AttemptCount = 1
                    StatusCode = $null
                    Error = $null
                    HeaderNames = @('Authorization')
                }
            }

            $result = Invoke-WtcgTelemetryExportForJsonl -JsonlPath $jsonlPath -RunContext $context -EnvPath $envPath

            $result.Status | Should -Be 'succeeded'
            $reportText = Get-Content -LiteralPath $result.ReportPath -Raw
            $reportText | Should -Not -Match 'super-secret-api-key'
            $reportText | Should -Not -Match 'secret-query'
            @(($reportText | ConvertFrom-Json).Results)[0].Uri | Should -Be 'https://elastic.example.com:9200/base/_bulk'

            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://elastic.example.com:9200/base/_bulk' -and
                $Method -eq 'Post' -and
                $ContentType -eq 'application/x-ndjson' -and
                $AllowInsecureTls -and
                $Headers['Authorization'] -eq 'ApiKey super-secret-api-key' -and
                $Body.EndsWith("`n") -and
                (($Body -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 4)
            }
        }
    }

    It 'writes an export error report when a configured sink fails non-fatally' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=genericHttp
WTCG_TELEMETRY_RETRY_COUNT=0
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=0
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_GENERIC_HTTP_URI=https://collector.example.com/events
'@ | Set-Content -Path $envPath -Encoding utf8

            $context = New-WtcgRunContext -RunId 'wtcg-telemetry-failure' -RunRootPath $script:TempDir
            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
            '{"schemaVersion":"1.0","action":"disable","runId":"wtcg-telemetry-failure"}' | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {
                [pscustomobject]@{
                    Sent = $false
                    Uri = $Uri
                    Method = $Method
                    ContentType = $ContentType
                    AttemptCount = 1
                    StatusCode = $null
                    Error = 'collector down'
                    HeaderNames = @()
                }
            }

            $result = Invoke-WtcgTelemetryExportForJsonl -JsonlPath $jsonlPath -RunContext $context -EnvPath $envPath

            $result.Status | Should -Be 'completed-with-errors'
            Test-Path -LiteralPath $result.ReportPath | Should -BeTrue
            $report = Get-Content -LiteralPath $result.ReportPath -Raw | ConvertFrom-Json
            @($report.Results)[0].Sent | Should -BeFalse
            @($report.Results)[0].Error | Should -Be 'collector down'
        }
    }

    It 'does not send or write a report when telemetry is disabled' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'WTCG_TELEMETRY_ENABLED=false' | Set-Content -Path $envPath -Encoding utf8
            $context = New-WtcgRunContext -RunId 'wtcg-disabled-telemetry' -RunRootPath $script:TempDir
            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'wintaskcrossingguard-events.jsonl'
            '{"schemaVersion":"1.0","action":"disable"}' | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {}

            $result = Invoke-WtcgTelemetryExportForJsonl -JsonlPath $jsonlPath -RunContext $context -EnvPath $envPath

            $result.Status | Should -Be 'skipped-disabled'
            $result.ReportPath | Should -BeNullOrEmpty
            Should -Invoke Send-WtcgGenericHttpPayload -Times 0
        }
    }
}

Describe 'Telemetry export Stage 6 future adapters' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports Datadog Splunk Azure Monitor and Logstash settings from .env' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=datadog,splunkHec,azureMonitor,logstash
WTCG_DATADOG_ENABLED=true
WTCG_DATADOG_URI=https://http-intake.logs.datadoghq.com/api/v2/logs
WTCG_DATADOG_API_KEY=dd-secret
WTCG_DATADOG_SERVICE=wtcg
WTCG_DATADOG_SOURCE=powershell
WTCG_DATADOG_TAGS=env:test,tool:wtcg
WTCG_SPLUNK_HEC_ENABLED=true
WTCG_SPLUNK_HEC_URI=https://splunk.example.com:8088
WTCG_SPLUNK_HEC_TOKEN=splunk-secret
WTCG_SPLUNK_HEC_INDEX=main
WTCG_SPLUNK_HEC_SOURCE=WinTaskCrossingGuard
WTCG_SPLUNK_HEC_SOURCETYPE=_json
WTCG_AZURE_MONITOR_ENABLED=true
WTCG_AZURE_MONITOR_ENDPOINT=https://dce.example.ingest.monitor.azure.com
WTCG_AZURE_MONITOR_DCR_IMMUTABLE_ID=dcr-abc
WTCG_AZURE_MONITOR_STREAM_NAME=Custom-WinTaskCrossingGuard_CL
WTCG_AZURE_MONITOR_BEARER_TOKEN=azure-secret
WTCG_LOGSTASH_ENABLED=true
WTCG_LOGSTASH_URI=https://logstash.example.com:8080/wtcg
WTCG_LOGSTASH_FORMAT=ndjson
WTCG_LOGSTASH_HEADERS=X-WTCG-Source=WinTaskCrossingGuard
'@ | Set-Content -Path $envPath -Encoding utf8

            $settings = Get-WtcgTelemetrySettings -EnvPath $envPath

            $settings.Sinks | Should -Contain 'datadog'
            $settings.SplunkHec.Enabled | Should -BeTrue
            $settings.Datadog.ApiKey | Should -Be 'dd-secret'
            $settings.SplunkHec.Token | Should -Be 'splunk-secret'
            $settings.AzureMonitor.BearerToken | Should -Be 'azure-secret'
            $settings.Logstash.Headers | Should -Contain 'X-WTCG-Source=WinTaskCrossingGuard'
        }
    }

    It 'builds Datadog log payloads without exposing the API key' {
        InModuleScope WinTaskCrossingGuard {
            $event = [pscustomobject]@{
                action = 'disable'
                status = 'succeeded'
                operation = 'Pester'
                runId = 'wtcg-dd'
                hostName = 'host01'
            }

            $payload = $event | ConvertTo-WtcgDatadogLogPayload -Service 'wtcg' -Source 'powershell' -Tags 'env:test'
            $logs = @($payload | ConvertFrom-Json)
            $logs.Count | Should -Be 1
            $logs[0].service | Should -Be 'wtcg'
            $logs[0].ddsource | Should -Be 'powershell'
            $logs[0].ddtags | Should -Be 'env:test'
            $logs[0].hostname | Should -Be 'host01'
            $logs[0].message.runId | Should -Be 'wtcg-dd'
            $payload | Should -Not -Match 'dd-secret'
        }
    }

    It 'builds Splunk HEC payloads and auth headers' {
        InModuleScope WinTaskCrossingGuard {
            $event = [pscustomobject]@{
                timestampUtc = '2030-01-02T03:04:05Z'
                action = 'error'
                runId = 'wtcg-splunk'
                hostName = 'host02'
            }

            $payload = $event | ConvertTo-WtcgSplunkHecPayload -Index 'main' -Source 'WinTaskCrossingGuard' -Sourcetype '_json'
            $payload.EndsWith("`n") | Should -BeTrue
            $hec = ($payload -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0] | ConvertFrom-Json
            $hec.index | Should -Be 'main'
            $hec.source | Should -Be 'WinTaskCrossingGuard'
            $hec.sourcetype | Should -Be '_json'
            $hec.host | Should -Be 'host02'
            $hec.event.runId | Should -Be 'wtcg-splunk'

            (Resolve-WtcgSplunkHecUri -Uri 'https://splunk.example.com:8088').EndsWith('/services/collector') | Should -BeTrue
            $headers = Get-WtcgSplunkHecAuthHeader -Token 'splunk-token'
            $headers['Authorization'] | Should -Be 'Splunk splunk-token'
        }
    }

    It 'builds Azure Monitor Logs Ingestion payloads and URI' {
        InModuleScope WinTaskCrossingGuard {
            $event = [pscustomobject]@{
                timestampUtc = '2030-01-02T03:04:05Z'
                action = 'disable'
                operation = 'PesterAzure'
                status = 'succeeded'
                runId = 'wtcg-azure'
                hostName = 'host03'
                details = [pscustomobject]@{ disabledTaskCount = 2 }
            }

            $payload = $event | ConvertTo-WtcgAzureMonitorPayload
            $records = @($payload | ConvertFrom-Json)
            $records.Count | Should -Be 1
            $records[0].TimeGenerated | Should -Be '2030-01-02T03:04:05Z'
            $records[0].Action | Should -Be 'disable'
            $records[0].RunId | Should -Be 'wtcg-azure'
            $records[0].RawEvent.runId | Should -Be 'wtcg-azure'

            $uri = Resolve-WtcgAzureMonitorLogsIngestionUri `
                -Endpoint 'https://dce.example.ingest.monitor.azure.com' `
                -DataCollectionRuleId 'dcr-abc' `
                -StreamName 'Custom-WinTaskCrossingGuard_CL'
            $uri | Should -Be 'https://dce.example.ingest.monitor.azure.com/dataCollectionRules/dcr-abc/streams/Custom-WinTaskCrossingGuard_CL?api-version=2023-01-01'

            $headers = Get-WtcgBearerAuthHeader -Token 'azure-token'
            $headers['Authorization'] | Should -Be 'Bearer azure-token'
        }
    }

    It 'exports to Datadog Splunk Azure Monitor and Logstash using sanitized report results' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=datadog,splunkHec,azureMonitor,logstash
WTCG_TELEMETRY_RETRY_COUNT=0
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=0
WTCG_DATADOG_ENABLED=true
WTCG_DATADOG_URI=https://http-intake.logs.datadoghq.com/api/v2/logs?query-secret=hide-me
WTCG_DATADOG_API_KEY=dd-secret
WTCG_SPLUNK_HEC_ENABLED=true
WTCG_SPLUNK_HEC_URI=https://splunk.example.com:8088
WTCG_SPLUNK_HEC_TOKEN=splunk-secret
WTCG_AZURE_MONITOR_ENABLED=true
WTCG_AZURE_MONITOR_ENDPOINT=https://dce.example.ingest.monitor.azure.com
WTCG_AZURE_MONITOR_DCR_IMMUTABLE_ID=dcr-abc
WTCG_AZURE_MONITOR_STREAM_NAME=Custom-WinTaskCrossingGuard_CL
WTCG_AZURE_MONITOR_BEARER_TOKEN=azure-secret
WTCG_LOGSTASH_ENABLED=true
WTCG_LOGSTASH_URI=https://logstash.example.com:8080/wtcg?secret=hide-me
WTCG_LOGSTASH_FORMAT=ndjson
WTCG_LOGSTASH_AUTH_HEADER_NAME=Authorization
WTCG_LOGSTASH_AUTH_HEADER_VALUE=Bearer logstash-secret
'@ | Set-Content -Path $envPath -Encoding utf8

            $context = New-WtcgRunContext -RunId 'wtcg-stage6' -RunRootPath $script:TempDir
            $jsonlPath = Resolve-WtcgRunArtifactPath -RunContext $context -Kind 'JsonlLogs' -FileName 'events.jsonl'
            @(
                '{"schemaVersion":"1.0","action":"disable","status":"succeeded","runId":"wtcg-stage6","hostName":"host01"}'
                '{"schemaVersion":"1.0","action":"error","status":"failed","runId":"wtcg-stage6","hostName":"host01"}'
            ) | Set-Content -Path $jsonlPath -Encoding utf8

            Mock Send-WtcgGenericHttpPayload {
                [pscustomobject]@{
                    Sent = $true
                    Uri = $Uri
                    Method = $Method
                    ContentType = $ContentType
                    AttemptCount = 1
                    StatusCode = 200
                    Error = $null
                    HeaderNames = if ($Headers -is [hashtable]) { @($Headers.Keys) } else { @($Headers) }
                }
            }

            $result = Invoke-WtcgTelemetryExportForJsonl -JsonlPath $jsonlPath -RunContext $context -EnvPath $envPath

            $result.Status | Should -Be 'succeeded'
            @($result.Results).SinkName | Should -Contain 'datadog'
            @($result.Results).SinkName | Should -Contain 'splunkHec'
            @($result.Results).SinkName | Should -Contain 'azureMonitor'
            @($result.Results).SinkName | Should -Contain 'logstash'

            $reportText = Get-Content -LiteralPath $result.ReportPath -Raw
            $reportText | Should -Not -Match 'dd-secret'
            $reportText | Should -Not -Match 'splunk-secret'
            $reportText | Should -Not -Match 'azure-secret'
            $reportText | Should -Not -Match 'logstash-secret'
            $reportText | Should -Not -Match 'query-secret'
            $reportText | Should -Not -Match 'secret=hide-me'

            Should -Invoke Send-WtcgGenericHttpPayload -Times 4
            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://http-intake.logs.datadoghq.com/api/v2/logs?query-secret=hide-me' -and
                ($Headers -is [hashtable]) -and
                $Headers['DD-API-KEY'] -eq 'dd-secret' -and
                $ContentType -eq 'application/json; charset=utf-8'
            }
            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://splunk.example.com:8088/services/collector' -and
                ($Headers -is [hashtable]) -and
                $Headers['Authorization'] -eq 'Splunk splunk-secret' -and
                $Body.EndsWith("`n")
            }
            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://dce.example.ingest.monitor.azure.com/dataCollectionRules/dcr-abc/streams/Custom-WinTaskCrossingGuard_CL?api-version=2023-01-01' -and
                ($Headers -is [hashtable]) -and
                $Headers['Authorization'] -eq 'Bearer azure-secret'
            }
            Should -Invoke Send-WtcgGenericHttpPayload -Times 1 -ParameterFilter {
                $Uri -eq 'https://logstash.example.com:8080/wtcg?secret=hide-me' -and
                $AuthHeaderName -eq 'Authorization' -and
                $AuthHeaderValue -eq 'Bearer logstash-secret' -and
                $ContentType -eq 'application/x-ndjson'
            }
        }
    }
}
