function Invoke-WtcgTelemetryExportForJsonl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlPath,

        [Parameter()]
        [AllowNull()]
        [object] $RunContext,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ReportPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorReportPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'TelemetryExport'
    )

    if ([string]::IsNullOrWhiteSpace($JsonlPath) -or -not (Test-Path -LiteralPath $JsonlPath)) {
        return [pscustomobject]@{
            Enabled    = $false
            Status     = 'skipped-missing-jsonl'
            JsonlPath  = $JsonlPath
            ReportPath = $null
            Results    = @()
        }
    }

    $settings = Get-WtcgTelemetrySettings -EnvPath $EnvPath
    if (-not [bool]$settings.Enabled) {
        return [pscustomobject]@{
            Enabled    = $false
            Status     = 'skipped-disabled'
            JsonlPath  = $JsonlPath
            ReportPath = $null
            Results    = @()
        }
    }

    $events = @(Import-WtcgJsonlEvent -Path $JsonlPath | Select-WtcgTelemetryEvent -AllowedEvents $settings.Events)
    $results = [System.Collections.Generic.List[object]]::new()

    try {
        $sinkNames = @($settings.Sinks | ForEach-Object { ([string]$_).ToLowerInvariant() })

        if (($sinkNames -contains 'generic' -or $sinkNames -contains 'generichttp' -or $sinkNames -contains 'http') -and [bool]$settings.GenericHttp.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$settings.GenericHttp.Uri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'genericHttp' -EventCount $events.Count -ErrorMessage 'WTCG_GENERIC_HTTP_URI is not configured.'))
            }
            else {
                $body = ConvertTo-WtcgGenericHttpTelemetryPayload -Format $settings.GenericHttp.Format -JsonlPath $JsonlPath -AllowedEvents $settings.Events
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $settings.GenericHttp.Uri `
                    -Method $settings.GenericHttp.Method `
                    -Body $body `
                    -ContentType $settings.GenericHttp.ContentType `
                    -Headers $settings.GenericHttp.Headers `
                    -AuthHeaderName $settings.GenericHttp.AuthHeaderName `
                    -AuthHeaderValue $settings.GenericHttp.AuthHeaderValue `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.GenericHttp.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'genericHttp' -Result $sendResult -Uri $settings.GenericHttp.Uri -EventCount $events.Count))
            }
        }

        if (($sinkNames -contains 'elasticsearch' -or $sinkNames -contains 'elastic' -or $sinkNames -contains 'opensearch') -and [bool]$settings.Elasticsearch.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$settings.Elasticsearch.Uri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'elasticsearch' -EventCount $events.Count -ErrorMessage 'WTCG_ELASTICSEARCH_URI is not configured.'))
            }
            else {
                $elasticUri = Resolve-WtcgElasticBulkUri -Uri $settings.Elasticsearch.Uri
                $headers = Get-WtcgElasticAuthHeader -AuthType $settings.Elasticsearch.AuthType -ApiKey $settings.Elasticsearch.ApiKey -Username $settings.Elasticsearch.Username -Password $settings.Elasticsearch.Password
                $body = $events | ConvertTo-WtcgElasticBulkPayload -Index $settings.Elasticsearch.Index -DataStream:$settings.Elasticsearch.DataStream
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $elasticUri `
                    -Method 'Post' `
                    -Body $body `
                    -ContentType 'application/x-ndjson' `
                    -Headers $headers `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.Elasticsearch.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'elasticsearch' -Result $sendResult -Uri $elasticUri -EventCount $events.Count))
            }
        }

        if (($sinkNames -contains 'datadog' -or $sinkNames -contains 'datadoglogs') -and [bool]$settings.Datadog.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$settings.Datadog.Uri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'datadog' -EventCount $events.Count -ErrorMessage 'WTCG_DATADOG_URI is not configured.'))
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$settings.Datadog.ApiKey)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'datadog' -EventCount $events.Count -ErrorMessage 'WTCG_DATADOG_API_KEY is not configured.'))
            }
            else {
                $headers = Get-WtcgDatadogAuthHeader -ApiKey $settings.Datadog.ApiKey
                $body = $events | ConvertTo-WtcgDatadogLogPayload -Service $settings.Datadog.Service -Source $settings.Datadog.Source -Tags $settings.Datadog.Tags -AllowedEvents $settings.Events
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $settings.Datadog.Uri `
                    -Method 'Post' `
                    -Body $body `
                    -ContentType 'application/json; charset=utf-8' `
                    -Headers $headers `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.Datadog.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'datadog' -Result $sendResult -Uri $settings.Datadog.Uri -EventCount $events.Count))
            }
        }

        if (($sinkNames -contains 'splunk' -or $sinkNames -contains 'splunkhec' -or $sinkNames -contains 'hec') -and [bool]$settings.SplunkHec.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$settings.SplunkHec.Uri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'splunkHec' -EventCount $events.Count -ErrorMessage 'WTCG_SPLUNK_HEC_URI is not configured.'))
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$settings.SplunkHec.Token)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'splunkHec' -EventCount $events.Count -ErrorMessage 'WTCG_SPLUNK_HEC_TOKEN is not configured.'))
            }
            else {
                $splunkUri = Resolve-WtcgSplunkHecUri -Uri $settings.SplunkHec.Uri
                $headers = Get-WtcgSplunkHecAuthHeader -Token $settings.SplunkHec.Token
                $body = $events | ConvertTo-WtcgSplunkHecPayload -Index $settings.SplunkHec.Index -Source $settings.SplunkHec.Source -Sourcetype $settings.SplunkHec.Sourcetype -AllowedEvents $settings.Events
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $splunkUri `
                    -Method 'Post' `
                    -Body $body `
                    -ContentType 'application/json; charset=utf-8' `
                    -Headers $headers `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.SplunkHec.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'splunkHec' -Result $sendResult -Uri $splunkUri -EventCount $events.Count))
            }
        }

        if (($sinkNames -contains 'azuremonitor' -or $sinkNames -contains 'azure' -or $sinkNames -contains 'sentinel') -and [bool]$settings.AzureMonitor.Enabled) {
            $azureUri = Resolve-WtcgAzureMonitorLogsIngestionUri `
                -Uri $settings.AzureMonitor.Uri `
                -Endpoint $settings.AzureMonitor.Endpoint `
                -DataCollectionRuleId $settings.AzureMonitor.DataCollectionRuleId `
                -StreamName $settings.AzureMonitor.StreamName `
                -ApiVersion $settings.AzureMonitor.ApiVersion

            if ([string]::IsNullOrWhiteSpace([string]$azureUri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'azureMonitor' -EventCount $events.Count -ErrorMessage 'Azure Monitor URI is not configured. Set WTCG_AZURE_MONITOR_URI or endpoint/DCR/stream settings.'))
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$settings.AzureMonitor.BearerToken)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'azureMonitor' -EventCount $events.Count -ErrorMessage 'WTCG_AZURE_MONITOR_BEARER_TOKEN is not configured.'))
            }
            else {
                $headers = Get-WtcgBearerAuthHeader -Token $settings.AzureMonitor.BearerToken
                $body = $events | ConvertTo-WtcgAzureMonitorPayload -AllowedEvents $settings.Events
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $azureUri `
                    -Method 'Post' `
                    -Body $body `
                    -ContentType 'application/json; charset=utf-8' `
                    -Headers $headers `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.AzureMonitor.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'azureMonitor' -Result $sendResult -Uri $azureUri -EventCount $events.Count))
            }
        }

        if (($sinkNames -contains 'logstash') -and [bool]$settings.Logstash.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$settings.Logstash.Uri)) {
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'logstash' -EventCount $events.Count -ErrorMessage 'WTCG_LOGSTASH_URI is not configured.'))
            }
            else {
                $body = ConvertTo-WtcgGenericHttpTelemetryPayload -Format $settings.Logstash.Format -JsonlPath $JsonlPath -AllowedEvents $settings.Events
                $sendResult = Send-WtcgGenericHttpPayload `
                    -Uri $settings.Logstash.Uri `
                    -Method 'Post' `
                    -Body $body `
                    -ContentType $settings.Logstash.ContentType `
                    -Headers $settings.Logstash.Headers `
                    -AuthHeaderName $settings.Logstash.AuthHeaderName `
                    -AuthHeaderValue $settings.Logstash.AuthHeaderValue `
                    -TimeoutSeconds $settings.TimeoutSeconds `
                    -RetryCount $settings.RetryCount `
                    -RetryDelaySeconds $settings.RetryDelaySeconds `
                    -AllowInsecureTls:$settings.Logstash.AllowInsecureTls `
                    -FailOnError:$settings.FailOnError
                $results.Add((ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'logstash' -Result $sendResult -Uri $settings.Logstash.Uri -EventCount $events.Count))
            }
        }


        $status = if ($results.Count -eq 0) {
            'skipped-no-enabled-sinks'
        }
        elseif (@($results | Where-Object { -not $_.Sent }).Count -gt 0) {
            'completed-with-errors'
        }
        else {
            'succeeded'
        }

        $reportFile = Save-WtcgTelemetryExportReport -RunContext $RunContext -Path $ReportPath -Operation $Operation -Status $status -JsonlPath $JsonlPath -Results @($results)

        if ($settings.FailOnError -and $status -eq 'completed-with-errors') {
            throw "Telemetry export failed for one or more sinks. Report: $($reportFile.FullName)"
        }

        return [pscustomobject]@{
            Enabled    = $true
            Status     = $status
            JsonlPath  = $JsonlPath
            ReportPath = if ($null -ne $reportFile) { $reportFile.FullName } else { $null }
            Results    = @($results)
        }
    }
    catch {
        $errorResult = ConvertTo-WtcgTelemetryExportResultSummary -SinkName 'telemetryExport' -EventCount $events.Count -ErrorMessage $_.Exception.Message
        $errorPath = $ErrorReportPath
        if ([string]::IsNullOrWhiteSpace($errorPath) -and $null -ne $RunContext) {
            $errorPath = Resolve-WtcgRunArtifactPath -RunContext $RunContext -Kind 'Errors' -FileName 'telemetry-export-error.json'
        }

        Save-WtcgTelemetryExportReport -RunContext $RunContext -Path $errorPath -Operation $Operation -Status 'failed' -JsonlPath $JsonlPath -Results @($errorResult) | Out-Null

        if ($settings.FailOnError) {
            throw
        }

        return [pscustomobject]@{
            Enabled    = $true
            Status     = 'failed'
            JsonlPath  = $JsonlPath
            ReportPath = $errorPath
            Results    = @($errorResult)
        }
    }
}
