# Pester tests

This test suite targets the logic-heavy module first and smoke-tests wrapper scripts.

## Install or update Pester

Use the project bootstrap script:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-ProjectPester.ps1
```

Install/update with the same path used by the test runner:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-ProjectPester.ps1 `
  -RequiredVersion 5.0.0 `
  -Scope CurrentUser `
  -Force `
  -SkipPublisherCheck
```

Dry run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-ProjectPester.ps1 -WhatIf
```

or let the runner call the bootstrap script:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90 -InstallPester
```

## Run tests and coverage

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
```

Coverage artifacts are written to:

```text
.\TestResults\coverage.xml
.\TestResults\pester-results.xml
```

## Coverage target

The runner measures coverage for:

```text
WinTaskCrossingGuard.psm1
```

That module contains the functional behavior:

- date/time parsing
- overnight window logic
- path normalization
- selection JSON import
- per-folder recurse matching
- include/exclude rules
- task discovery
- identity import/export
- disable/enable/start identity actions
- manifest writing
- central run folder/run ID creation and artifact path routing
- run report writing
- emergency latest restore artifact discovery
- emergency restore wrapper smoke tests
- XML disable log writing with run correlation fields
- SIEM-friendly JSONL event writing under steamablelogs with run correlation fields
- telemetry export settings import, Elastic bulk payload generation, generic HTTP sender behavior, workflow export reports, Datadog/Splunk HEC/Azure Monitor/Logstash adapter payloads, and docs/examples for secure collector configuration
- Windows Event Log audit event formatting for the WinTaskCrossingGuard source
- default XML log path resolution

Wrapper scripts are intentionally smoke-tested for syntax and identity-file behavior, because they mostly forward parameters into the module.

## Running wrapper scripts safely

The wrapper identity consumers support `-WhatIf`, so these tests do not start or enable real tasks.

The module tests mock these ScheduledTasks commands:

- `Get-ScheduledTask`
- `Get-ScheduledTaskInfo`
- `Disable-ScheduledTask`
- `Enable-ScheduledTask`
- `Start-ScheduledTask`

No real scheduled tasks are required for the unit tests.

- email notification body generation
- log-generated notification dispatch path
- error notification dispatch path

- JSON mail configuration import and attachment behavior

- split JSON mail configuration for result and error notifications

- strict split JSON mail event validation
- XML error log writing for configuration failures
- JSONL error, re-enable, and notification event writing
- Telemetry export Stage 1 configuration/payload building, Stage 2 generic HTTP sender behavior, Stage 3 workflow integration, and Stage 4 docs/examples
- Scheduled re-enable overlap detection and stale-task update behavior
- Central run folder and run ID correlation across logs, manifests, and reports
- Windows Event Log audit integration
- Webhook and ChatOps notifications for Teams, Slack, and Discord

- safety allow-list mode behavior
- protected never-disable task policy

- .env log retention cleanup behavior
