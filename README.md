# WinTaskCrossingGuard

PowerShell 7 script suite for finding, disabling, enabling, and immediately starting Windows Scheduled Tasks whose `NextRunTime` falls inside a command-line time window.

## Files

- `WinTaskCrossingGuard.psm1` - reusable functions.
- `Find-TasksInWindow.ps1` - returns task identities for tasks inside a time window.
- `Disable-TasksInWindow.ps1` - finds matching tasks, returns identities when requested, writes a manifest, and disables them.
- `Enable-TaskIdentities.ps1` - enables tasks from piped identities or an identity JSON file.
- `Start-TaskIdentities.ps1` - starts tasks immediately from piped identities or an identity JSON file.
- `Restore-TasksFromManifest.ps1` - restores only tasks marked as disabled by this suite run in a rollback manifest.
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

```powershell
Import-Module .\WinTaskCrossingGuard.psm1 -Force

$window = Resolve-WtcgWindow -Start "22:00" -End "06:00"

$selection = Import-WtcgTaskSelection -Path .\task-selection.example.json

$tasks = Find-WtcgTaskInWindow `
  -Start $window.Start `
  -End $window.End `
  -Selection $selection `
  -IdentityOnly

$tasks | Disable-WtcgTaskIdentity
$tasks | Enable-WtcgTaskIdentity
$tasks | Start-WtcgTaskIdentity
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


## Test bootstrap

Install or update the project-required Pester version:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-ProjectPester.ps1
```

Run tests and install/update Pester first if needed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -InstallPester
```


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

Each pipeline runs the Pester test suite on Windows with PowerShell 7.


## Scheduled re-enable orchestration

The module includes a one-call orchestration function:

```powershell
Disable-WtcgTasksInWindowAndScheduleReenable
```

It does all of this in one flow:

```text
Find tasks inside a time window
Capture original task state and discovery metadata in a rollback manifest
Disable only tasks that were originally enabled
Create or update a separate Windows Scheduled Task that restores only tasks disabled by this suite run
```

Example:

```powershell
Import-Module .\WinTaskCrossingGuard.psm1 -Force

Disable-WtcgTasksInWindowAndScheduleReenable `
  -Start '22:00' `
  -End '06:00' `
  -ReenableAt ([datetime]'2026-04-27T06:30:00') `
  -SelectionPath .\task-selection.example.json `
  -ManifestPath .\rollback-manifest.json `
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

If the re-enable scheduled task already exists, the function updates its one-time trigger to the new `-ReenableAt` value.


## Pester unit tests with 90% coverage gate

The suite includes Pester tests under:

```text
tests/
```

Run them locally with the same coverage gate used by CI:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
```

The test runner measures coverage for:

```text
WinTaskCrossingGuard.psm1
```

and fails when coverage is below 90%.


## XML disable log

The core module can now write an XML log detailing tasks found and disabled.

Core function:

```powershell
Write-WtcgDisableXmlLog
```

The regular disable script writes an XML log by default. When `-XmlLogPath` is not provided, the log is written under `.\logs\` with the current date and time in the filename:

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


Default XML log path format:

```text
.\logs\disabled-tasks-yyyyMMdd-HHmmss.xml
```


## Intranet SMTP email notifications

The suite supports two separate email notification events:

```text
1. XML log generated
2. Error encountered
```

The XML-log-generated email can attach the generated XML log file:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -SelectionPath .\task-selection.example.json `
  -LogEmailSmtpServer 'mail.intranet.local' `
  -LogEmailFrom 'wintaskcrossingguard@example.com' `
  -LogEmailTo 'ops@example.com'
```

The error email is independent and is sent only when an error is encountered:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -SelectionPath .\task-selection.example.json `
  -ErrorEmailSmtpServer 'mail.intranet.local' `
  -ErrorEmailFrom 'wintaskcrossingguard@example.com' `
  -ErrorEmailTo 'ops@example.com'
```

Both events can be enabled at the same time:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Disable-TasksInWindow.ps1 `
  -Start '22:00' `
  -End '06:00' `
  -SelectionPath .\task-selection.example.json `
  -LogEmailSmtpServer 'mail.intranet.local' `
  -LogEmailFrom 'wintaskcrossingguard@example.com' `
  -LogEmailTo 'ops@example.com' `
  -ErrorEmailSmtpServer 'mail.intranet.local' `
  -ErrorEmailFrom 'wintaskcrossingguard@example.com' `
  -ErrorEmailTo 'ops@example.com'
```

The same notification parameters are available on:

```powershell
Disable-WtcgTasksInWindowAndScheduleReenable
```

By default, email failures are warnings and do not block the suite. Use these flags to make email failure stop the operation:

```powershell
-FailOnLogEmailError
-FailOnErrorEmail
```


## JSON mail configuration

Email settings can be configured inside the same JSON used by `-SelectionPath`:

```json
{
  "mail": {
    "enabled": true,
    "smtpServer": "mail.internal.example.com",
    "port": 25,
    "from": "wintaskcrossingguard@example.com",
    "to": [
      "ops@example.com"
    ],
    "cc": [
      "audit@example.com"
    ],
    "useSsl": false,
    "attachXmlLog": true,
    "attachIdentityFile": true
  }
}
```

When `mail.enabled` is `true`, the suite uses those settings for two separate notification events:

```text
1. XML log generated
2. Error encountered
```

`attachXmlLog` controls whether the generated XML log is attached.

`attachIdentityFile` controls whether the generated task identity JSON file is attached.

The mail object is optional. If it is missing or disabled, no JSON-configured email is sent.


## Single-entry and split-entry mail JSON

The `mail` setting supports two shapes.

### One mail entry

When one mail entry is included, it is used for both events:

```text
1. XML log/result email
2. Error email
```

Example file:

```text
examples/task-selection.mail-single-entry.example.json
```

### Two mail entries

When two mail entries are included, one entry is used for the suite result/log email and the other is used for error email.

Preferred explicit format:

```json
{
  "mail": [
    {
      "event": "result",
      "enabled": true,
      "smtpServer": "mail.internal.example.com",
      "port": 25,
      "from": "wintaskcrossingguard@example.com",
      "to": ["ops@example.com"],
      "cc": ["audit@example.com"],
      "useSsl": false,
      "attachXmlLog": true,
      "attachIdentityFile": true
    },
    {
      "event": "error",
      "enabled": true,
      "smtpServer": "mail.internal.example.com",
      "port": 25,
      "from": "wintaskcrossingguard@example.com",
      "to": ["ops-alerts@example.com"],
      "cc": ["audit@example.com"],
      "useSsl": false,
      "attachXmlLog": true,
      "attachIdentityFile": true
    }
  ]
}
```

Example file:

```text
examples/task-selection.mail-split-entry.example.json
```

When two mail entries are provided, both entries must include an explicit `event` field.

Required values:

```text
event = result
event = error
```

If either entry is missing `event`, or if the pair does not contain exactly one `result` and one `error`, the suite prints a console error, writes an XML error log, sends the error email when possible, and stops before disabling tasks.

Invalid example file:

```text
examples/task-selection.mail-invalid-missing-event.example.json
```


## Safety allow-list mode

Enable explicit-only task disabling with:

```json
{
  "safetyAllowListMode": true
}
```

When enabled, the suite refuses to scan or disable unless at least one `includeFolders` or `includeTasks` entry is present. This prevents accidental broad scans such as root folder plus recursive scanning.

## Protected never-disable task policy

The suite includes a built-in protected list for risky Windows/Microsoft/system task folders. Protected entries are filtered out before disable operations and win over explicit includes.

You can extend the protected list in JSON:

```json
{
  "protectedFolders": [
    {
      "taskPath": "\\MyCompany\\Critical\\",
      "recurse": true
    }
  ],
  "protectedTasks": [
    {
      "taskPath": "\\MyCompany\\",
      "taskName": "DoNotDisable-*"
    }
  ]
}
```

Example:

```text
examples/task-selection.safety-allow-list.example.json
```


## Strict two-entry mail validation

When two mail entries are provided, both entries must include an explicit `event` field. One must be `result` and one must be `error`.

If either entry is missing `event`, or if the pair does not contain exactly one `result` and one `error`, the suite prints a console error, writes an XML error log, sends the error email when possible, and stops before disabling tasks.

Invalid example:

```text
examples/task-selection.mail-invalid-missing-event.example.json
```


## Verification note for this package

This package was statically verified for:

```text
Required file inventory
JSON example/schema parsing
CI YAML parsing
Safety allow-list mode function wiring
Protected never-disable task function wiring
Strict two-entry mail validation
XML disable/error log functions
Error email fallback settings
90% coverage gate command wiring
```

Pester and real Windows Task Scheduler execution must be run on a Windows machine with PowerShell 7 because this environment does not provide `pwsh` or the Windows `ScheduledTasks` module.


## .env log retention

The suite can clean up old XML logs at the end of successful execution.

Create a `.env` file next to `WinTaskCrossingGuard.psm1`:

```text
LOG_RETENTION=30
```

Meaning:

```text
Keep XML log files in .\logs for 30 days.
Delete .xml files older than 30 days at the end of execution.
```

Example file included:

```text
.env.example
```

Cleanup applies to XML files in the suite `logs` folder. Non-XML files are ignored.

The cleanup function is:

```powershell
Clear-WtcgOldLogs
```

The `.env` parser function is:

```powershell
Import-WtcgDotEnv
```


## Project name

This project is named **WinTaskCrossingGuard**.

The suite uses the `Wtcg` prefix for internal PowerShell functions.

## License

WinTaskCrossingGuard is licensed under the BSD Zero Clause License, also known as 0BSD.

See the `LICENSE` file for the full license text.



## PowerShell module package layout

WinTaskCrossingGuard is packaged as a PowerShell module.

```text
WinTaskCrossingGuard/
  WinTaskCrossingGuard.psd1
  WinTaskCrossingGuard.psm1
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

The root scripts are convenience wrappers that call the matching scripts under `scripts\`.

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

Useful parameters:

```powershell
-LockName 'Global\WinTaskCrossingGuard'
-LockPath 'C:\ProgramData\WinTaskCrossingGuard\runtime.lock.json'
-LockTimeoutSeconds 0
-DisableLock
```

`-LockTimeoutSeconds 0` fails immediately if another run is active. Use a positive value to wait, or `-1` to wait indefinitely. `-DisableLock` is available for tests and advanced manual recovery only.

