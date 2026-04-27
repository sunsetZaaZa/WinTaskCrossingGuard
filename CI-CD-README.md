# CI/CD pipeline files

This suite includes pipeline definitions for:

- GitHub Actions: `.github/workflows/pester.yml`
- GitLab CI/CD: `.gitlab-ci.yml`
- Azure DevOps Pipelines: `azure-pipelines.yml`

All three use PowerShell 7 on Windows, install/update the project-required Pester version, then run:

```powershell
./Invoke-WinTaskCrossingGuardTests.ps1 -MinimumCoveragePercent 90
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
