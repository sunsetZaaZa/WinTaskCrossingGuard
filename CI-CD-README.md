# CI/CD pipeline files

This suite includes pipeline definitions for:

- GitHub Actions: `.github/workflows/pester.yml`
- GitLab CI/CD: `.gitlab-ci.yml`
- Azure DevOps Pipelines: `azure-pipelines.yml`

All three use PowerShell 7 on Windows, run PSScriptAnalyzer, install/update the project-required Pester version, then run:

```powershell
./Invoke-WinTaskCrossingGuardAnalyzer.ps1 -InstallAnalyzer
./Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
```


## Static analysis gate

`Invoke-WinTaskCrossingGuardAnalyzer.ps1` installs PSScriptAnalyzer when `-InstallAnalyzer` is supplied, loads `PSScriptAnalyzerSettings.psd1`, and scans the module, repository scripts, and tests. The analyzer writes JSON and CSV reports for both `Error` and `Warning` findings, prints severity/rule summaries to the CI log, and fails the gate only for severities listed in `-FailOnSeverity` (default: `Error`). Warnings are kept visible as cleanup debt without blocking Pester coverage while the project carries an analyzer baseline.

Analyzer artifacts are published with the test artifacts:

```text
TestResults/scriptanalyzer-results.json
TestResults/scriptanalyzer-results.csv
```

## GitLab runner note

The GitLab file expects a Windows runner tagged:

```yaml
tags:
  - windows
```

Change the tag if your runner uses a different label.

## Coverage gate note

`Invoke-WinTaskCrossingGuardTests.ps1` currently warns when coverage is below 100%.

To make the pipeline fail below 100%, change this block in the runner:

```powershell
if ($coverage -lt 100) {
    Write-Warning "Coverage is below 100%. Open '$($config.CodeCoverage.OutputPath)' or inspect missed commands with Pester output."
}
```

to:

```powershell
if ($coverage -lt 100) {
    throw "Coverage is below 100%. Actual coverage: $coverage%"
}
```


The pipelines enforce a 90% code coverage gate using `-MinimumCoveragePercent 90`.
