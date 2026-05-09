function Get-WtcgTelemetrySettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
    )

    $envValues = Import-WtcgDotEnv -Path $EnvPath

    $enabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_ENABLED' -Default $false) -Default $false
    $events = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_EVENTS' -Default 'result,error,notification,disable,re-enable,scheduled-reenable') -Default @('result', 'error', 'notification', 'disable', 're-enable', 'scheduled-reenable')
    $sinks = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_SINKS' -Default 'elasticsearch') -Default @('elasticsearch')
    $failOnError = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_FAIL_ON_ERROR' -Default $false) -Default $false

    $timeoutSeconds = 15
    $rawTimeout = Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_TIMEOUT_SECONDS' -Default 15
    if (-not [int]::TryParse([string]$rawTimeout, [ref]$timeoutSeconds) -or $timeoutSeconds -le 0) {
        throw "Invalid WTCG_TELEMETRY_TIMEOUT_SECONDS value '$rawTimeout'. Expected a positive whole number."
    }

    $batchSize = 100
    $rawBatchSize = Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_BATCH_SIZE' -Default 100
    if (-not [int]::TryParse([string]$rawBatchSize, [ref]$batchSize) -or $batchSize -le 0) {
        throw "Invalid WTCG_TELEMETRY_BATCH_SIZE value '$rawBatchSize'. Expected a positive whole number."
    }

    $retryCount = 2
    $rawRetryCount = Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_RETRY_COUNT' -Default 2
    if (-not [int]::TryParse([string]$rawRetryCount, [ref]$retryCount) -or $retryCount -lt 0) {
        throw "Invalid WTCG_TELEMETRY_RETRY_COUNT value '$rawRetryCount'. Expected zero or a positive whole number."
    }

    $retryDelaySeconds = 2
    $rawRetryDelaySeconds = Get-WtcgEnvValue -Values $envValues -Name 'WTCG_TELEMETRY_RETRY_DELAY_SECONDS' -Default 2
    if (-not [int]::TryParse([string]$rawRetryDelaySeconds, [ref]$retryDelaySeconds) -or $retryDelaySeconds -lt 0) {
        throw "Invalid WTCG_TELEMETRY_RETRY_DELAY_SECONDS value '$rawRetryDelaySeconds'. Expected zero or a positive whole number."
    }

    $elasticAuthType = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_AUTH_TYPE' -Default 'None')
    if ([string]::IsNullOrWhiteSpace($elasticAuthType)) { $elasticAuthType = 'None' }
    $elasticAuthType = $elasticAuthType.Trim()
    $allowedAuthTypes = @('None', 'ApiKey', 'Bearer', 'Basic')
    $matchedAuthType = @($allowedAuthTypes | Where-Object { $_ -ieq $elasticAuthType } | Select-Object -First 1)
    if ($matchedAuthType.Count -eq 0) {
        throw "Invalid WTCG_ELASTICSEARCH_AUTH_TYPE value '$elasticAuthType'. Expected one of: $($allowedAuthTypes -join ', ')."
    }
    $elasticAuthType = [string]$matchedAuthType[0]

    $elasticDataStream = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_DATA_STREAM' -Default $false) -Default $false
    $elasticEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_ENABLED' -Default $false) -Default $false
    $elasticAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $elasticIndex = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_INDEX' -Default 'wintaskcrossingguard-events')
    if ([string]::IsNullOrWhiteSpace($elasticIndex)) {
        $elasticIndex = 'wintaskcrossingguard-events'
    }

    $genericHttpEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_ENABLED' -Default $false) -Default $false
    $genericHttpAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $genericHttpMethod = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_METHOD' -Default 'Post')
    if ([string]::IsNullOrWhiteSpace($genericHttpMethod)) { $genericHttpMethod = 'Post' }
    $allowedGenericHttpMethods = @('Post', 'Put', 'Patch')
    $matchedGenericHttpMethod = @($allowedGenericHttpMethods | Where-Object { $_ -ieq $genericHttpMethod.Trim() } | Select-Object -First 1)
    if ($matchedGenericHttpMethod.Count -eq 0) {
        throw "Invalid WTCG_GENERIC_HTTP_METHOD value '$genericHttpMethod'. Expected one of: $($allowedGenericHttpMethods -join ', ')."
    }
    $genericHttpMethod = [string]$matchedGenericHttpMethod[0]

    $genericHttpFormat = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_FORMAT' -Default 'ndjson')
    if ([string]::IsNullOrWhiteSpace($genericHttpFormat)) { $genericHttpFormat = 'ndjson' }
    $allowedGenericHttpFormats = @('ndjson', 'jsonArray', 'raw')
    $matchedGenericHttpFormat = @($allowedGenericHttpFormats | Where-Object { $_ -ieq $genericHttpFormat.Trim() } | Select-Object -First 1)
    if ($matchedGenericHttpFormat.Count -eq 0) {
        throw "Invalid WTCG_GENERIC_HTTP_FORMAT value '$genericHttpFormat'. Expected one of: $($allowedGenericHttpFormats -join ', ')."
    }
    $genericHttpFormat = [string]$matchedGenericHttpFormat[0]

    $genericHttpDefaultContentType = if ($genericHttpFormat -ieq 'ndjson') { 'application/x-ndjson' } else { 'application/json; charset=utf-8' }
    $genericHttpContentType = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_CONTENT_TYPE' -Default $genericHttpDefaultContentType)
    if ([string]::IsNullOrWhiteSpace($genericHttpContentType)) { $genericHttpContentType = $genericHttpDefaultContentType }

    $genericHttpHeaders = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_HEADERS' -Default '') -Default @()

    $datadogEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_ENABLED' -Default $false) -Default $false
    $datadogAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $datadogUri = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_URI' -Default 'https://http-intake.logs.datadoghq.com/api/v2/logs')
    if ([string]::IsNullOrWhiteSpace($datadogUri)) { $datadogUri = 'https://http-intake.logs.datadoghq.com/api/v2/logs' }

    $splunkEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_ENABLED' -Default $false) -Default $false
    $splunkAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $splunkSourcetype = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_SOURCETYPE' -Default '_json')
    if ([string]::IsNullOrWhiteSpace($splunkSourcetype)) { $splunkSourcetype = '_json' }

    $azureMonitorEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_ENABLED' -Default $false) -Default $false
    $azureMonitorAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $azureMonitorApiVersion = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_API_VERSION' -Default '2023-01-01')
    if ([string]::IsNullOrWhiteSpace($azureMonitorApiVersion)) { $azureMonitorApiVersion = '2023-01-01' }

    $logstashEnabled = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_ENABLED' -Default $false) -Default $false
    $logstashAllowInsecureTls = ConvertTo-WtcgBoolean -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_ALLOW_INSECURE_TLS' -Default $false) -Default $false
    $logstashFormat = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_FORMAT' -Default 'ndjson')
    if ([string]::IsNullOrWhiteSpace($logstashFormat)) { $logstashFormat = 'ndjson' }
    $allowedLogstashFormats = @('ndjson', 'jsonArray', 'raw')
    $matchedLogstashFormat = @($allowedLogstashFormats | Where-Object { $_ -ieq $logstashFormat.Trim() } | Select-Object -First 1)
    if ($matchedLogstashFormat.Count -eq 0) {
        throw "Invalid WTCG_LOGSTASH_FORMAT value '$logstashFormat'. Expected one of: $($allowedLogstashFormats -join ', ')."
    }
    $logstashFormat = [string]$matchedLogstashFormat[0]
    $logstashDefaultContentType = if ($logstashFormat -ieq 'ndjson') { 'application/x-ndjson' } else { 'application/json; charset=utf-8' }
    $logstashContentType = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_CONTENT_TYPE' -Default $logstashDefaultContentType)
    if ([string]::IsNullOrWhiteSpace($logstashContentType)) { $logstashContentType = $logstashDefaultContentType }
    $logstashHeaders = ConvertTo-WtcgStringList -Value (Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_HEADERS' -Default '') -Default @()

    [pscustomobject]@{
        Enabled           = $enabled
        EnvPath           = $EnvPath
        Events            = @($events | ForEach-Object { ([string]$_).ToLowerInvariant() })
        Sinks             = @($sinks | ForEach-Object { ([string]$_).ToLowerInvariant() })
        FailOnError       = $failOnError
        TimeoutSeconds    = $timeoutSeconds
        BatchSize         = $batchSize
        RetryCount        = $retryCount
        RetryDelaySeconds = $retryDelaySeconds
        Elasticsearch     = [pscustomobject]@{
            Enabled          = $elasticEnabled
            Uri              = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_URI' -Default '')
            Index            = $elasticIndex
            DataStream       = $elasticDataStream
            AuthType         = $elasticAuthType
            ApiKey           = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_API_KEY' -Default '')
            Username         = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_USERNAME' -Default '')
            Password         = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_ELASTICSEARCH_PASSWORD' -Default '')
            AllowInsecureTls = $elasticAllowInsecureTls
        }
        GenericHttp       = [pscustomobject]@{
            Enabled          = $genericHttpEnabled
            Uri              = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_URI' -Default '')
            Method           = $genericHttpMethod
            Format           = $genericHttpFormat
            ContentType      = $genericHttpContentType
            Headers          = @($genericHttpHeaders)
            AuthHeaderName   = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_AUTH_HEADER_NAME' -Default '')
            AuthHeaderValue  = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_GENERIC_HTTP_AUTH_HEADER_VALUE' -Default '')
            AllowInsecureTls = $genericHttpAllowInsecureTls
        }
        Datadog           = [pscustomobject]@{
            Enabled          = $datadogEnabled
            Uri              = $datadogUri
            ApiKey           = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_API_KEY' -Default '')
            Service          = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_SERVICE' -Default 'wintaskcrossingguard')
            Source           = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_SOURCE' -Default 'powershell')
            Tags             = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_DATADOG_TAGS' -Default 'tool:wintaskcrossingguard')
            AllowInsecureTls = $datadogAllowInsecureTls
        }
        SplunkHec         = [pscustomobject]@{
            Enabled          = $splunkEnabled
            Uri              = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_URI' -Default '')
            Token            = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_TOKEN' -Default '')
            Index            = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_INDEX' -Default '')
            Source           = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_SPLUNK_HEC_SOURCE' -Default 'WinTaskCrossingGuard')
            Sourcetype       = $splunkSourcetype
            AllowInsecureTls = $splunkAllowInsecureTls
        }
        AzureMonitor     = [pscustomobject]@{
            Enabled                  = $azureMonitorEnabled
            Uri                      = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_URI' -Default '')
            Endpoint                 = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_ENDPOINT' -Default '')
            DataCollectionRuleId     = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_DCR_IMMUTABLE_ID' -Default '')
            StreamName               = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_STREAM_NAME' -Default '')
            ApiVersion               = $azureMonitorApiVersion
            BearerToken              = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_AZURE_MONITOR_BEARER_TOKEN' -Default '')
            AllowInsecureTls         = $azureMonitorAllowInsecureTls
        }
        Logstash         = [pscustomobject]@{
            Enabled          = $logstashEnabled
            Uri              = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_URI' -Default '')
            Format           = $logstashFormat
            ContentType      = $logstashContentType
            Headers          = @($logstashHeaders)
            AuthHeaderName   = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_AUTH_HEADER_NAME' -Default '')
            AuthHeaderValue  = [string](Get-WtcgEnvValue -Values $envValues -Name 'WTCG_LOGSTASH_AUTH_HEADER_VALUE' -Default '')
            AllowInsecureTls = $logstashAllowInsecureTls
        }
    }
}
