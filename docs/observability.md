# WinTaskCrossingGuard observability contract

WinTaskCrossingGuard treats observability as three separate concerns:

1. **Events and logs** answer "what happened?"
2. **Metrics** answer "how often, how many, and is the system healthy?"
3. **Dashboards** answer "what should an operator see first?"

This document defines the contract for adding Loki, VictoriaMetrics, Thanos, and Grafana support without changing the runtime behavior of the current project. The existing JSONL event stream remains the source of truth for workflow telemetry. Future adapters should transform that stream into log or metric payloads rather than duplicating task-discovery or task-restore logic.

## End-state architecture

```text
WinTaskCrossingGuard workflow
  |
  |-- Central run folder
  |     |
  |     |-- run-info.json
  |     |-- reports/*.json
  |     |-- errors/*.json
  |     |-- streamablelogs/wintaskcrossingguard-events.jsonl
  |
  |-- Log adapters
  |     |
  |     |-- Existing Elastic/OpenSearch bulk export
  |     |-- Existing Datadog Logs export
  |     |-- Existing Splunk HEC export
  |     |-- Existing Azure Monitor export
  |     |-- Existing Logstash/generic HTTP export
  |     |-- Planned Grafana Loki push export
  |
  |-- Metric adapters
  |     |
  |     |-- Planned Prometheus textfile output
  |     |-- Planned VictoriaMetrics direct Prometheus import
  |     |-- Planned Prometheus/vmagent remote_write path for Thanos Receive
  |
  |-- Visualization artifacts
        |
        |-- Planned Grafana datasource provisioning
        |-- Planned Grafana dashboard provisioning
```

The important rule is that WinTaskCrossingGuard writes local evidence first. External observability systems are downstream consumers. A broken collector should not erase the local run folder or prevent emergency recovery unless strict telemetry failure behavior is explicitly enabled.

## Logs versus metrics versus dashboards

### Logs and events

Logs are for detailed, searchable facts about individual workflow actions.

Use logs for:

- Run correlation such as `runId` and `runFolderPath`.
- Task identity fields such as `TaskPath`, `TaskName`, and task state.
- Error objects, exception messages, and remediation hints.
- Notification delivery details.
- Audit trails for disable, restore, scheduled re-enable, and emergency restore workflows.

The project already emits newline-delimited JSON from workflow operations. Each JSONL line should remain a compact event with the existing top-level fields:

```text
schemaVersion
source
timestampUtc
timestampLocal
action
operation
status
hostName
userName
processId
runId
runFolderPath
details
```

Loki support should ingest these events as log lines. The full JSON object should stay in the log body so operators can search and inspect high-detail fields without turning them into labels.

### Metrics

Metrics are for low-cardinality, aggregated signals that power alerting and trend dashboards.

Use metrics for:

- Counts of events by action and status.
- Counts of disabled, restored, skipped, failed, and notification events.
- Last-seen timestamps.
- Telemetry export success and failure counts.
- Duration or latency gauges and histograms when the workflow records reliable timings.

Do not create a new time series for every task, run, user, process, or output path. Metrics should be boring, small, and dependable. The metric layer is the little brass bell on the counter, not the entire filing cabinet.

### Dashboards

Dashboards are presentation artifacts, not telemetry sinks.

Grafana support should provide:

- Datasource provisioning for Loki and Prometheus-compatible metrics backends.
- Dashboard provisioning for operator views.
- Example panels and queries for local labs and production-like deployments.

Grafana should read from Loki, VictoriaMetrics, or Thanos Query. WinTaskCrossingGuard should not post workflow telemetry directly to Grafana dashboards.

## Recommended sink selection

| Need | Recommended target | Why |
| --- | --- | --- |
| Search individual disable, restore, notification, and error events | Loki, Elastic/OpenSearch, Splunk HEC, Datadog Logs, Azure Monitor, or generic HTTP collector | Event logs preserve high-detail JSON without forcing fields into metric labels. |
| Query task names, run IDs, task paths, and error text | Loki or another log/search backend | These fields are high-cardinality and belong in logs. |
| Build counts, rates, last-seen panels, and alert rules | VictoriaMetrics or another Prometheus-compatible metrics backend | Metrics backends are optimized for aggregated time series. |
| Store long-term metrics across many hosts or sites | Thanos through Prometheus or vmagent remote_write | Thanos Receive is a remote-write receiver, while Thanos Query is the Grafana-facing read endpoint. |
| Provide operator dashboards | Grafana | Grafana should visualize logs and metrics through datasources. |
| Local development or a small lab | Loki plus single-node VictoriaMetrics plus Grafana | This gives searchable logs, basic metrics, and dashboards with a small footprint. |
| Enterprise deployment | Existing SIEM/log sink plus VictoriaMetrics or Thanos plus Grafana | Keeps audit logs and metric alerting separate while preserving local run evidence. |

## Tool responsibilities

### Grafana

Grafana is the visualization layer. Add support through files under `examples/grafana/` in a future PR:

```text
examples/grafana/provisioning/datasources/*.yaml
examples/grafana/provisioning/dashboards/*.yaml
examples/grafana/dashboards/*.json
```

Grafana provisioning should include at least these datasource options:

- Loki for event logs.
- VictoriaMetrics as a Prometheus-compatible datasource.
- Thanos Query as a Prometheus-compatible datasource.

Grafana dashboards should assume that detailed task facts live in logs and summary counts live in metrics.

### Grafana Loki

Loki is a log backend. Future Loki support should transform JSONL events into Loki push payloads and send them to `/loki/api/v1/push`.

The log line should be the compact JSON event. Labels should be intentionally small and stable, for example:

```text
source="WinTaskCrossingGuard"
application="wintaskcrossingguard"
environment="prod"
host="SERVER01"
action="disable"
status="succeeded"
```

The following fields should stay in the JSON log body by default:

```text
runId
runFolderPath
taskName
taskPath
userName
processId
timestampUtc
timestampLocal
```

### VictoriaMetrics

VictoriaMetrics is a metrics backend. Future VictoriaMetrics support should aggregate JSONL events into Prometheus-style samples and send them through either:

- Direct import to `/api/v1/import/prometheus` for simple push-style workflows.
- Prometheus or vmagent scraping/remote_write for pull or agent-based deployments.

Recommended first metrics:

```text
wtcg_events_total{source,environment,host,action,status}
wtcg_tasks_disabled_total{source,environment,host,operation}
wtcg_tasks_reenabled_total{source,environment,host,operation}
wtcg_errors_total{source,environment,host,operation}
wtcg_notifications_total{source,environment,host,status}
wtcg_telemetry_exports_total{source,environment,sink,status}
wtcg_last_event_timestamp_seconds{source,environment,host,action}
```

### Thanos

Thanos is for durable, horizontally scalable Prometheus-style metrics. It should be supported through documented integration examples first:

```text
WinTaskCrossingGuard
  -> Prometheus textfile output or local metrics endpoint
  -> Prometheus or vmagent
  -> remote_write
  -> Thanos Receive
  -> Thanos Query
  -> Grafana Prometheus datasource
```

Avoid direct remote_write from PowerShell in the first implementation. Remote write is a wire protocol for Prometheus-compatible senders. Prometheus, vmagent, or the OpenTelemetry Collector should own that protocol boundary.

## Cardinality rules

Cardinality is the number of unique label combinations a backend must index. High-cardinality labels create too many Loki streams and too many metric time series. That makes storage noisy, dashboards slower, and alerts harder to reason about.

### Good Loki labels

Use labels that are stable and have a small set of values:

```text
source
application
environment
host
action
operation
status
```

Use `host` carefully. It is usually acceptable for a fleet-level tool, but it can still multiply streams in large environments. It should be configurable.

### Bad Loki labels by default

Do not use these as Loki labels unless an operator deliberately opts in for a narrow lab scenario:

```text
runId
runFolderPath
taskName
taskPath
userName
processId
errorMessage
manifestPath
identityPath
notificationRecipient
```

Keep these in the JSON log body.

### Good metric labels

Use labels that make aggregate charts useful:

```text
source
environment
host
action
operation
status
sink
```

### Bad metric labels by default

Do not use these as metric labels:

```text
runId
taskName
taskPath
runFolderPath
manifestPath
identityPath
userName
processId
exceptionMessage
```

If an operator needs a per-run or per-task investigation, they should pivot from a metric panel into logs.

## Naming conventions

Use a short, consistent metric prefix:

```text
wtcg_
```

Use stable action and status names that match the JSONL event contract where possible:

```text
disable
re-enable
scheduled-reenable
notification
error
succeeded
failed
skipped
```

Use one canonical source name:

```text
WinTaskCrossingGuard
```

Use one canonical app/service label:

```text
wintaskcrossingguard
```

## Security and privacy rules

- Never write telemetry secrets to JSONL, reports, dashboards, or example files.
- Keep bearer tokens, API keys, and basic-auth passwords in `.env` or a secret manager.
- Do not put credentials in collector URLs.
- Avoid logging notification recipients unless the deployment explicitly requires it.
- Prefer TLS for every remote sink outside local labs.
- Keep local run folders as the durable audit record even when external export succeeds.

## Planned PR sequence

This contract sets up the following implementation order:

1. Loki telemetry adapter.
2. Prometheus metrics text output.
3. VictoriaMetrics direct import sink.
4. Thanos integration examples through Prometheus or vmagent.
5. Grafana provisioning and dashboards.
6. Local observability lab.
7. CI and regression hardening for payloads, docs, and examples.

Each implementation PR should keep this split intact: logs carry detail, metrics carry aggregates, Grafana reads from datasources, and the local run folder remains the source of truth.

## References

- Grafana provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- Loki HTTP API: https://grafana.com/docs/loki/latest/reference/loki-http-api/
- Loki label best practices: https://grafana.com/docs/loki/latest/get-started/labels/bp-labels/
- VictoriaMetrics Prometheus import: https://docs.victoriametrics.com/victoriametrics/url-examples/#apiv1importprometheus
- VictoriaMetrics Prometheus integration: https://docs.victoriametrics.com/victoriametrics/integrations/prometheus/
- Thanos Receive: https://thanos.io/tip/components/receive.md/
- Prometheus remote write specification: https://prometheus.io/docs/specs/prw/remote_write_spec/
