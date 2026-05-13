# WinTaskCrossingGuard observability examples

This folder is the landing pad for observability examples that will be added across the Loki, VictoriaMetrics, Thanos, and Grafana implementation PRs.

The current PR is documentation-only. It defines the contract and recommended topology without changing runtime behavior.

## Current source of truth

WinTaskCrossingGuard writes telemetry evidence to the central run folder first:

```text
runs/<runId>/run-info.json
runs/<runId>/reports/*.json
runs/<runId>/errors/*.json
runs/<runId>/streamablelogs/wintaskcrossingguard-events.jsonl
```

External telemetry systems should consume or transform that local evidence. They should not replace it.

## Recommended local lab topology

```text
WinTaskCrossingGuard
  |
  |-- JSONL event stream
  |     |
  |     +-- Loki log sink
  |
  |-- Prometheus-style metrics
  |     |
  |     +-- VictoriaMetrics
  |
  +-- Grafana
        |
        |-- Loki datasource
        +-- Prometheus-compatible datasource
```

This topology gives a compact lab with searchable logs, basic metrics, and dashboards.

## Recommended production topology

```text
WinTaskCrossingGuard hosts
  |
  |-- Local run folders for audit and recovery
  |
  |-- Log export
  |     |
  |     +-- Loki, Elastic/OpenSearch, Splunk HEC, Datadog Logs, Azure Monitor, or Logstash
  |
  |-- Metrics export
  |     |
  |     +-- VictoriaMetrics
  |     +-- Prometheus/vmagent -> remote_write -> Thanos Receive
  |
  +-- Grafana
        |
        |-- Loki or SIEM/log datasource
        +-- VictoriaMetrics or Thanos Query datasource
```

Use logs for detailed investigations. Use metrics for dashboards and alerts. Use Grafana to stitch the two views together.

## Which example should I use?

| Scenario | Use |
| --- | --- |
| I want to search task names, run IDs, and error text. | Loki or an existing log/SIEM sink. |
| I want panels for counts, rates, last-seen times, and telemetry health. | VictoriaMetrics or another Prometheus-compatible backend. |
| I need long-term Prometheus-style metrics across many hosts or clusters. | Prometheus or vmagent remote_write into Thanos Receive, then query through Thanos Query. |
| I want dashboards managed as code. | Grafana provisioning files. |
| I am testing locally. | Loki plus VictoriaMetrics plus Grafana. |
| I already have Splunk, Datadog, Elastic, or Azure Monitor. | Keep using the existing sink for logs and add metrics only if dashboard/alerting needs require it. |

## Cardinality guardrails

Keep labels small and stable.

Good labels:

```text
source
environment
application
host
action
operation
status
sink
```

Do not use these as Loki or metric labels by default:

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
notificationRecipient
```

Those fields should stay in the JSON log body. They are perfect for search and terrible as default labels, a tiny gremlin factory for time-series systems.

## Planned example layout

Future PRs should fill in this structure:

```text
examples/observability/
  README.md
  loki/
    telemetry-loki.env.example
    sample-logql.md
  victoriametrics/
    telemetry-victoriametrics.env.example
    sample-promql.md
  thanos/
    prometheus.remote_write.thanos.example.yaml
    vmagent.remote_write.thanos.example.yaml
  grafana/
    provisioning/
      datasources/
      dashboards/
    dashboards/
  lab/
    docker-compose.yml
    README.md
```

Top-level tool-specific folders can also exist under `examples/` when they are easier for operators to copy directly. This folder should remain the map that explains how the pieces fit together.

## Contract reference

See [`docs/observability.md`](../../docs/observability.md) for the full observability contract, sink responsibilities, cardinality rules, and implementation sequence.
