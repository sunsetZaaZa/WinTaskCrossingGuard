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
