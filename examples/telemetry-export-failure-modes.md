# WinTaskCrossingGuard telemetry export failure modes

Telemetry export is intentionally best-effort by default.

## Default mode

```dotenv
WTCG_TELEMETRY_FAIL_ON_ERROR=false
```

When export fails, WinTaskCrossingGuard continues the local workflow and writes the failure into the central run folder:

```text
runs/<runId>/reports/telemetry-export-report.json
runs/<runId>/errors/telemetry-export-error.json
```

Use this for normal maintenance windows so Elasticsearch, OpenSearch, or a collector outage does not block task restoration.

## Strict mode

```dotenv
WTCG_TELEMETRY_FAIL_ON_ERROR=true
```

In strict mode, telemetry export failures can fail the operation. Use this only when policy requires proof that events reached an external telemetry system before the operation is considered successful.

## Retry behavior

```dotenv
WTCG_TELEMETRY_RETRY_COUNT=2
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=2
```

Transient HTTP failures are retried by the generic sender. Final reports include status, attempt counts, sink names, and sanitized destination information. Header values and authentication secrets are not written to reports.

## Security checklist

- Do not put credentials in URLs.
- Do not commit `.env` with live secrets.
- Use a least-privilege API key/token.
- Rotate secrets if they appear in console logs, PR output, reports, commits, screenshots, or issue trackers.
- Keep `ALLOW_INSECURE_TLS=false` outside local labs.
