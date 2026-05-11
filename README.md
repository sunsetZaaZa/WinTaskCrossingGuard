# WinTaskCrossingGuard

PowerShell 7 script suite for finding, disabling, enabling, and immediately starting Windows Scheduled Tasks whose `NextRunTime` falls inside a command-line time window.

## Files

- `WinTaskCrossingGuard/WinTaskCrossingGuard.psd1` - PowerShell module manifest.
- `WinTaskCrossingGuard/WinTaskCrossingGuard.psm1` - thin module loader that dot-sources categorized function files under `Public/`, `Private/`, `Logging/`, `Telemetry/`, `Notifications/`, `Scheduling/`, `Selection/`, and `RunState/`.
- `Find-TasksInWindow.ps1` - returns task identities for tasks inside a time window.
- `Disable-TasksInWindow.ps1` - finds matching tasks, returns identities when requested, writes a manifest, and disables them.
- `Enable-TaskIdentities.ps1` - enables tasks from piped identities or an identity JSON file.
- `Start-TaskIdentities.ps1` - starts tasks immediately from piped identities or an identity JSON file.
- `Restore-TasksFromManifest.ps1` - restores only tasks marked as disabled by this suite run in a rollback manifest.
- `Emergency-RestoreLatestDisabledTasks.ps1` - finds the newest restorable identity or manifest JSON file and immediately re-enables those tasks.
- `task-selection.example.json` - example selection policy.
- `task-selection.schema.json` - JSON schema for editor validation.

## Folder recurse in selection JSON

`includeFolders` and `excludeFolders` now support per-folder recursion.

Preferred format:

```json
{
  "includeFolders": [
    {
      "taskPath": "\\MyCompany\\",
      "recurse": true
    },
    {
      "taskPath": "\\Microsoft\\Windows\\Defrag\\",
      "recurse": false
    }
  ],
  "excludeFolders": [
    {
      "taskPath": "\\MyCompany\\NeverDisable\\",
      "recurse": true
    }
  ]
}
```

Meaning:

- `"recurse": true` matches the folder and all subfolders.
- `"recurse": false` matches only that exact folder.
- If `recurse` is omitted, it defaults to `false`.

Legacy string format still works:

```json
{
  "includeFolders": [
    "\\MyCompany\\"
  ]
}
```

Legacy string folders use the default recurse value. By default that is `false`.

You can change the default for string entries or object entries that omit `recurse`:

```json
{
  "defaultIncludeFolderRecurse": true,
  "defaultExcludeFolderRecurse": true,

  "includeFolders": [
    "\\MyCompany\\"
  ],

  "excludeFolders": [
    "\\MyCompany\\NeverDisable\\"
  ]
}
```

## Core identity object

The suite uses a lightweight identity object. Rollback manifests extend it with the original state and suite-disable marker so tasks that were already disabled stay disabled:

```powershell
[pscustomobject]@{
  TaskPath = "\MyCompany\"
  TaskName = "NightlyBackup"
  OriginalState = "Ready"
  WasOriginallyEnabled = $true
  DisabledBySuite = $true
}
```

That object can be piped into:

- `Disable-WtcgTaskIdentity`
- `Enable-WtcgTaskIdentity`
- `Start-WtcgTaskIdentity`

or passed through the wrapper scripts.

## Find tasks and return their names/folders

```powershell
$tasks = .\Find-TasksInWindow.ps1 `
  -Start "22:00" `
  -End "06:00" `
  -SelectionPath .\task-selection.example.json

$tasks | Format-Table TaskPath, TaskName, NextRunTime
```

## Find, write rollback manifest, and disable

```powershell
.\Disable-TasksInWindow.ps1 `
  -Start "22:00" `
  -End "06:00" `
  -SelectionPath .\task-selection.example.json `
  -ManifestPath .\rollback-manifest.json
```


## Emergency restore latest

Use the emergency restore script when a scheduled re-enable task did not fire, was deleted, or needs to be bypassed.

```powershell
.\Emergency-RestoreLatestDisabledTasks.ps1
```

By default it searches the central run root:

```text
.\runs
```

It scans for identity or manifest JSON files such as:

```text
.\runs\<runId>\manifests\rollback-manifest.json
.\runs\<runId>\identities\*.json
```

The newest supported artifact is selected by file write time, then only tasks marked as originally enabled and disabled by WinTaskCrossingGuard are re-enabled immediately. Legacy identity files that do not contain `DisabledBySuite` are treated as restorable so older exports still work.

Useful options:

```powershell
.\Emergency-RestoreLatestDisabledTasks.ps1 `
  -RunRootPath .\runs `
  -PassThru
```

```powershell
.\Emergency-RestoreLatestDisabledTasks.ps1 `
  -ArtifactPath .\runs\wtcg-20260429-120000-a1b2c3d4e5f6\manifests\rollback-manifest.json `
  -PassThru
```

Emergency restore writes back into the same run folder when the artifact contains run correlation metadata. It emits JSONL re-enable/error events, a run report, and Windows Event Log audit events using the `WinTaskCrossingGuard` source unless Event Log writing is disabled.

## Return identities while disabling

```powershell
$disabledTasks = .\Disable-TasksInWindow.ps1 `
  -Start "22:00" `
  -End "06:00" `
  -SelectionPath .\task-selection.example.json `
  -ReturnTaskIdentity
```

## Re-enable using returned identities

```powershell
$disabledTasks | .\Enable-TaskIdentities.ps1
```

## Restore using rollback manifest

```powershell
.\Restore-TasksFromManifest.ps1 -ManifestPath .\rollback-manifest.json
```

## Start immediately using returned identities

```powershell
$disabledTasks | .\Start-TaskIdentities.ps1
```

## Start immediately using identity JSON

```powershell
.\Start-TaskIdentities.ps1 -IdentityPath .\matched-task-identities.json
```

## Direct module usage

The module manifest exports only the supported public commands from `WinTaskCrossingGuard/Public`. Wrapper scripts continue to use private helpers internally, but those helpers are no longer part of the public API.

```powershell
Import-Module .\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1 -Force

$tasks = Find-WtcgTaskInWindow `
  -Start ([datetime]'2026-04-26T22:00:00') `
  -End ([datetime]'2026-04-27T06:00:00') `
  -TaskPath '\MyCompany\' `
  -IdentityOnly

$tasks | Disable-WtcgTaskIdentity
$tasks | Enable-WtcgTaskIdentity
$tasks | Start-WtcgTaskIdentity
```

Supported public commands:

```text
Disable-WtcgTaskIdentity
Disable-WtcgTasksInWindowAndScheduleReenable
Enable-WtcgTaskIdentity
Find-WtcgTaskInWindow
Save-WtcgManifest
Start-WtcgTaskIdentity
```

## Selection JSON behavior

The find/disable scripts accept `-SelectionPath`.

The JSON can define:

- `includeFolders`: task folders to search.
- `includeTasks`: individual tasks to include by `taskPath` and `taskName`.
- `excludeFolders`: task folders that must not be disabled.
- `excludeTasks`: individual tasks that must not be disabled.

Exclusions win over inclusions.

If any include list is present, only included folders/tasks are eligible. If no include list is present, command-line filters decide the scan set and the JSON only excludes.

`taskName` supports PowerShell wildcard patterns such as `Backup-*`.

## Behavior notes

- A task is considered in-window when `Get-ScheduledTaskInfo` reports a `NextRunTime` between `Start` and `End`, inclusive.
- Time-only values such as `22:00` are anchored to the current date.
- If `End` is earlier than `Start`, the window is treated as crossing midnight.
- Disabled tasks are ignored by default. Use `-IncludeDisabled` only when you want them listed too.
- Folder paths are normalized to leading and trailing slashes, for example `MyCompany` becomes `\MyCompany\`.
- Exclusions always win.
- Command-line `-Recurse` still controls command-line `-TaskPath` scanning. JSON folder recursion is controlled per folder with `"recurse": true` or `"recurse": false`.


## Test and static analysis bootstrap

Install or update the project-required Pester version:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-ProjectPester.ps1
```

Run tests and install/update Pester first if needed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -InstallPester
```

Run the same PSScriptAnalyzer gate used by CI:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardAnalyzer.ps1 -InstallAnalyzer
```

The analyzer uses `PSScriptAnalyzerSettings.psd1` and fails on `Error` or `Warning` findings from the selected style, unused-variable, command-correctness, security, and `ShouldProcess` rules. Reports are written to `TestResults\scriptanalyzer-results.json` and `TestResults\scriptanalyzer-results.csv`.


## Plain workflow example

A plain top-to-bottom example script is included:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-WinTaskCrossingGuardWorkflow.ps1
```

The example demonstrates finding tasks inside a time window, exporting task identities, disabling them, re-enabling them, and starting them immediately.


## CI/CD pipeline files

Included pipeline definitions:

```text
.github/workflows/pester.yml
.gitlab-ci.yml
azure-pipelines.yml
CI-CD-README.md
```

Each pipeline runs PSScriptAnalyzer first, then the Pester test suite on Windows with PowerShell 7.


## Scheduled re-enable orchestration

The module includes a one-call orchestration function:

```powershell
Disable-WtcgTasksInWindowAndScheduleReenable
```

It does all of this in one flow:

```text
Find tasks inside a time window
Detect active prior re-enable runs before making changes
Capture original task state and discovery metadata in a rollback manifest
Disable only tasks that were originally enabled
Create or update a separate Windows Scheduled Task that restores only tasks disabled by this suite run
```

Example:

```powershell
Import-Module .\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1 -Force

Disable-WtcgTasksInWindowAndScheduleReenable `
  -Start '22:00' `
  -End '06:00' `
  -ReenableAt ([datetime]'2026-04-27T06:30:00') `
  -SelectionPath .\task-selection.example.json `
  -IdentityOutputPath .\rollback-manifest.json `
  -ReenableTaskPath '\WinTaskCrossingGuard\' `
  -ReenableTaskName 'ReenableDisabledTasks'
```

A plain example script is included:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-ScheduledReenableWorkflow.ps1
```

Use `-WhatIf` for a dry run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Example-ScheduledReenableWorkflow.ps1 -WhatIf
```

If the re-enable scheduled task already exists but is stale, the function updates its one-time trigger to the new `-ReenableAt` value.

If the configured re-enable task is still active, or another active WinTaskCrossingGuard re-enable task in the same folder overlaps the requested disable-to-reenable interval, orchestration stops before disabling any tasks. This protects a prior run's manifest and prevents an earlier scheduled restore from re-enabling tasks during a later maintenance window.


## Central run folder and run ID

Every disable or scheduled disable operation now gets a run/correlation ID and a central operation folder. By default, the folder is created under `./runs/<runId>/`. Pass `-RunId` when an external change ticket, maintenance ID, or SIEM correlation ID already exists. Pass `-RunRootPath` to move all generated run folders, or `-RunFolderPath` to force one exact operation folder.

Default run layout:

```text
./runs/<runId>/
  run-info.json
  logs/
    disabled-tasks.xml
  streamablelogs/
    wintaskcrossingguard-events.jsonl
  manifests/
    rollback-manifest.json
  identities/
    matched-window-tasks.json
  reports/
    disable-report.json
    disable-schedule-report.json
    restore-report.json
  errors/
    wintaskcrossingguard-error.xml
    disable-error-report.json
    disable-schedule-error-report.json
    restore-error-report.json
```

The run ID is propagated into `run-info.json`, XML logs, JSONL events, rollback manifests, task identity files, run reports, Windows Event Log JSON payloads, notification bodies/events, runtime lock metadata, and the scheduled restore task arguments. Scheduled restore scripts infer the run folder from a manifest stored in `manifests/`, so restore events and reports stay in the same operation folder when possible.

Explicit artifact paths still work. For example, `-XmlLogPath`, `-JsonlLogPath`, `-ManifestPath`, `-IdentityOutputPath`, and `-ReportPath` override the default path for that specific artifact while preserving run correlation metadata inside the artifact.

Example with an external change ID:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -RunId 'CHG0123456' `
  -RunRootPath .\runs
```


## Pester unit tests with 90% coverage gate

The suite includes Pester tests under:

```text
tests/
```

Run them locally with the same coverage gate used by CI:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
```

The test runner measures coverage for the module loader plus the split function files under `WinTaskCrossingGuard\`. It fails when coverage is below 90%.


## XML disable log

The regular disable script writes an XML log detailing tasks found and disabled. The XML writer is now an internal helper, not an exported module command.

The regular disable script writes an XML log by default. When `-XmlLogPath` is not provided, the log is written inside the central run folder under `logs\disabled-tasks.xml`:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -SelectionPath .\task-selection.example.json `
  -XmlLogPath .\logs\disabled-tasks.xml
```

The scheduled re-enable orchestration also writes an XML log:

```powershell
Disable-WtcgTasksInWindowAndScheduleReenable `
  -Start '22:00' `
  -End '06:00' `
  -ReenableAt ([datetime]'2026-04-27T06:30:00') `
  -SelectionPath .\task-selection.example.json `
  -XmlLogPath .\logs\scheduled-reenable-disable-log.xml
```

The XML log includes:

```text
createdAt timestamp
createdLocal timestamp
operation name
run/correlation ID
run folder path
window start/end
optional re-enable time
optional selection source
optional identity output path
optional re-enable task name
task count
task path
task name
full task name
state at discovery
next run time
disabled action marker
per-task logged timestamp
```


Default XML log path format inside a run:

```text
.\runs\<runId>\logs\disabled-tasks.xml
```


## SIEM-friendly JSONL event log

The module also writes newline-delimited JSON events for SIEM and observability tools such as Splunk, Sentinel, Elastic, and Datadog. JSONL output complements the XML log instead of replacing it.

JSONL events are written to the central run folder's `streamablelogs/` directory by default, not the root `./logs/` folder:

```text
.\runs\<runId>\streamablelogs\wintaskcrossingguard-events.jsonl
```

JSONL path resolution and event writers are internal helpers used by the wrapper scripts and orchestration command; they are not exported as public module commands.

Each line is one compact JSON object with these top-level fields:

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

Supported action values:

```text
disable
re-enable
error
notification
```

Example disable run with an explicit JSONL path:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -SelectionPath .\task-selection.example.json `
  -XmlLogPath .\logs\disabled-tasks.xml `
  -JsonlLogPath .\streamablelogs\disabled-tasks.jsonl
```

Scheduled re-enable workflows pass the generated JSONL path, `-RunId`, and `-RunFolderPath` into `Restore-TasksFromManifest.ps1` so disable, notification, and re-enable events can land in the same streamable event file and share the same correlation ID.




## Telemetry export: secure Elastic/OpenSearch and generic HTTP examples

Telemetry export uses the local JSONL stream as the source of truth. Workflow operations write JSONL first, then export matching events to configured telemetry sinks. Export results are written back into the central run folder:

```text
./runs/<runId>/reports/telemetry-export-report.json
./runs/<runId>/errors/telemetry-export-error.json
```

The implementation currently includes configuration parsing, Elastic/OpenSearch bulk payload building, generic HTTP sending with retry/timeout/header/TLS options, and workflow-level export after JSONL writes.

The telemetry parsers, payload builders, retry helpers, and sink senders are internal implementation helpers. Operational workflows call them after JSONL writes, but the module manifest does not export them as public commands.

### Secure `.env` examples

Keep telemetry secrets in `.env` or your deployment secret store. Do not commit live API keys, bearer tokens, basic-auth passwords, collector tokens, or webhook URLs. Export reports deliberately record header names, sink names, status, and counts, but not secret header values.

Elastic/OpenSearch bulk sink with API key authentication:

```dotenv
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_EVENTS=disable,re-enable,scheduled-reenable,error,notification
WTCG_TELEMETRY_FAIL_ON_ERROR=false
WTCG_TELEMETRY_TIMEOUT_SECONDS=15
WTCG_TELEMETRY_BATCH_SIZE=100
WTCG_TELEMETRY_RETRY_COUNT=2
WTCG_TELEMETRY_RETRY_DELAY_SECONDS=2
WTCG_TELEMETRY_SINKS=elasticsearch

WTCG_ELASTICSEARCH_ENABLED=true
WTCG_ELASTICSEARCH_URI=https://elastic.example.com:9200
WTCG_ELASTICSEARCH_INDEX=wintaskcrossingguard-events
WTCG_ELASTICSEARCH_DATA_STREAM=false
WTCG_ELASTICSEARCH_AUTH_TYPE=ApiKey
WTCG_ELASTICSEARCH_API_KEY=<store in secret manager or local .env only>
WTCG_ELASTICSEARCH_ALLOW_INSECURE_TLS=false
```

Elastic data-stream style sink. Data streams should use `create` bulk actions; the internal export layer handles that automatically when data-stream mode is enabled:

```dotenv
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=elasticsearch
WTCG_ELASTICSEARCH_ENABLED=true
WTCG_ELASTICSEARCH_URI=https://elastic.example.com:9200
WTCG_ELASTICSEARCH_INDEX=logs-wintaskcrossingguard-default
WTCG_ELASTICSEARCH_DATA_STREAM=true
WTCG_ELASTICSEARCH_AUTH_TYPE=ApiKey
WTCG_ELASTICSEARCH_API_KEY=<secret>
```

Generic NDJSON collector endpoint:

```dotenv
WTCG_TELEMETRY_ENABLED=true
WTCG_TELEMETRY_SINKS=genericHttp
WTCG_GENERIC_HTTP_ENABLED=true
WTCG_GENERIC_HTTP_URI=https://collector.example.com/events
WTCG_GENERIC_HTTP_METHOD=Post
WTCG_GENERIC_HTTP_FORMAT=ndjson
WTCG_GENERIC_HTTP_CONTENT_TYPE=application/x-ndjson
WTCG_GENERIC_HTTP_HEADERS=X-WTCG-Source=WinTaskCrossingGuard;X-Environment=prod
WTCG_GENERIC_HTTP_AUTH_HEADER_NAME=Authorization
WTCG_GENERIC_HTTP_AUTH_HEADER_VALUE=Bearer <secret>
WTCG_GENERIC_HTTP_ALLOW_INSECURE_TLS=false
```

Local lab-only TLS bypass:

```dotenv
WTCG_ELASTICSEARCH_ALLOW_INSECURE_TLS=true
WTCG_GENERIC_HTTP_ALLOW_INSECURE_TLS=true
```

Use those only for local labs with self-signed certificates. Production collectors should use valid TLS and leave both options set to `false`.

### Inspect generated telemetry input

The public workflow writes its SIEM source stream to JSONL first. To inspect events without relying on private helpers, read the generated stream directly:

```powershell
Get-Content .\runs\<runId>\streamablelogs\wintaskcrossingguard-events.jsonl | Select-Object -First 6
```

Generated Elastic/OpenSearch bulk payloads:

```text
{"index":{"_index":"wintaskcrossingguard-events"}}
{"schemaVersion":"1.0","source":"WinTaskCrossingGuard",...}
```

When `-DataStream` is used, the action metadata switches to `create`:

```text
{"create":{"_index":"logs-wintaskcrossingguard-default"}}
{"schemaVersion":"1.0","source":"WinTaskCrossingGuard",...}
```

Bulk payloads always end with a final newline, which Elastic/OpenSearch bulk endpoints expect for NDJSON bodies.

### Generic HTTP telemetry export

Configure the generic HTTP sink through `.env` and run one of the public workflows. The workflow writes JSONL locally, exports matching events, then records the export result under the run folder reports directory.

```text
LOG_RETENTION=30
```

Meaning:

```text
Keep legacy XML log files in .\logs and legacy JSONL files in .\streamablelogs for 30 days. Central run folders under .\runs are not pruned by this legacy log-retention helper yet.
Delete matching files older than 30 days at the end of execution.
```

Example file included:

```text
.env.example
```

Cleanup applies to XML files in the suite `logs` folder and JSONL files in the suite `streamablelogs` folder when called with `-Filter '*.jsonl'`. Central run folders are intentionally left intact for audit review unless an operator removes them. Other file types are ignored.

Legacy cleanup and `.env` parsing are handled by internal helpers that are called by the repository scripts. They are intentionally not exported from the module manifest.


## Project name

This project is named **WinTaskCrossingGuard**.

The suite uses the `Wtcg` prefix for PowerShell functions. Only files under `WinTaskCrossingGuard/Public` are exported as supported module commands; categorized helper folders remain private implementation details.

## License

WinTaskCrossingGuard is licensed under the BSD Zero Clause License, also known as 0BSD.

See the `LICENSE` file for the full license text.



## PowerShell module package layout

WinTaskCrossingGuard is packaged as a PowerShell module.

```text
WinTaskCrossingGuard/
  WinTaskCrossingGuard.psd1
  WinTaskCrossingGuard.psm1        # thin loader
  Private/                         # shared internal helpers
  Public/                          # high-level module commands
  Logging/                         # XML, JSONL, event log, retention
  Telemetry/                       # SIEM/export adapters and retry helpers
  Notifications/                   # email and webhook notifications
  Scheduling/                      # scheduled re-enable orchestration helpers
  Selection/                       # task identity and selection policy logic
  RunState/                        # run IDs, locks, reports, restore artifacts
scripts/
  Disable-TasksInWindow.ps1
  Find-TasksInWindow.ps1
  Enable-TaskIdentities.ps1
  Start-TaskIdentities.ps1
  Restore-TasksFromManifest.ps1
tests/
examples/
config/
```

Import the module with:

```powershell
Import-Module .\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1 -Force
```

Run tests from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
```

The root scripts are convenience wrappers that call the matching scripts under `scripts\`. The repository scripts dot-source `WinTaskCrossingGuard\Load-WinTaskCrossingGuardInternal.ps1` so they can use private helpers without exporting them from the module manifest.

## Runtime lock / mutex

WinTaskCrossingGuard now uses a named Windows mutex to prevent two executions from mutating scheduled tasks on the same host at the same time. The default lock is:

```powershell
Global\WinTaskCrossingGuard
```

The disable and restore workflows also write a diagnostic lock file by default:

```powershell
$env:ProgramData\WinTaskCrossingGuard\runtime.lock.json
```

The mutex is the source of truth and is released automatically by Windows if the PowerShell process exits. The lock file is only a breadcrumb showing the owning process, host, operation, and related paths.

The mutex prevents simultaneous mutations. Scheduled re-enable overlap detection covers the longer-lived hazard: a previous run can still be waiting for its one-time restore task after the process has exited. In that case, a later run is refused rather than replacing the prior restore trigger or manifest.

Useful parameters:

```powershell
-LockName 'Global\WinTaskCrossingGuard'
-LockPath 'C:\ProgramData\WinTaskCrossingGuard\runtime.lock.json'
-LockTimeoutSeconds 0
-DisableLock
```

`-LockTimeoutSeconds 0` fails immediately if another run is active. Use a positive value to wait, or `-1` to wait indefinitely. `-DisableLock` is available for tests and advanced manual recovery only.

