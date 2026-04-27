#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [switch] $InstallPester,

    [Parameter()]
    [version] $RequiredPesterVersion = '5.0.0',

    [Parameter()]
    [switch] $OpenReport,

    [Parameter()]
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\TestResults'),

    [Parameter()]
    [double] $MinimumCoveragePercent = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($InstallPester) {
    & (Join-Path $PSScriptRoot 'Install-ProjectPester.ps1') `
        -RequiredVersion $RequiredPesterVersion `
        -Scope CurrentUser `
        -Force `
        -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion $RequiredPesterVersion -ErrorAction Stop

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$config = New-PesterConfiguration
$config.Run.Path = @((Join-Path $PSScriptRoot '..\tests'))
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psm1')
)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = Join-Path $OutputDirectory 'coverage.xml'

$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $OutputDirectory 'pester-results.xml'

$result = Invoke-Pester -Configuration $config

$coverage = $result.CodeCoverage.CoveragePercent
Write-Host ''
Write-Host "Pester result: $($result.Result)"
Write-Host "Coverage: $coverage%"
Write-Host "Minimum coverage required: $MinimumCoveragePercent%"

if ($coverage -lt $MinimumCoveragePercent) {
    throw "Coverage is below required minimum. Required: $MinimumCoveragePercent%. Actual: $coverage%"
}

if ($OpenReport) {
    Invoke-Item $OutputDirectory
}

exit $result.FailedCount
