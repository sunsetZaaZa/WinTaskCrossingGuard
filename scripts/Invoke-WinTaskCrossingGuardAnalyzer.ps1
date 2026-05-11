#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [switch] $InstallAnalyzer,

    [Parameter()]
    [version] $RequiredAnalyzerVersion = '1.21.0',

    [Parameter()]
    [string] $SettingsPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\PSScriptAnalyzerSettings.psd1'),

    [Parameter()]
    [string] $OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..\TestResults'),

    [Parameter()]
    [string[]] $Path,

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]] $Severity = @('Error', 'Warning'),

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Information')]
    [string[]] $FailOnSeverity = @('Error'),

    [Parameter()]
    [ValidateRange(0, 100)]
    [int] $LogFindingLimit = 25,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WtcgAnalyzerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CandidatePath
    )

    $resolvedPath = Resolve-Path -LiteralPath $CandidatePath -ErrorAction Stop
    return $resolvedPath.ProviderPath
}

if ($InstallAnalyzer) {
    Install-Module PSScriptAnalyzer `
        -MinimumVersion $RequiredAnalyzerVersion `
        -Scope CurrentUser `
        -Force `
        -SkipPublisherCheck
}

Import-Module PSScriptAnalyzer -MinimumVersion $RequiredAnalyzerVersion -ErrorAction Stop

$repoRoot = Resolve-WtcgAnalyzerPath -CandidatePath (Join-Path -Path $PSScriptRoot -ChildPath '..')
$settingsFile = Resolve-WtcgAnalyzerPath -CandidatePath $SettingsPath
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if (-not $Path -or $Path.Count -eq 0) {
    $rootScripts = Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -File |
        Sort-Object -Property FullName |
        Select-Object -ExpandProperty FullName

    $defaultAnalyzerPaths = @(
        (Join-Path -Path $repoRoot -ChildPath 'WinTaskCrossingGuard')
        (Join-Path -Path $repoRoot -ChildPath 'scripts')
        (Join-Path -Path $repoRoot -ChildPath 'tests')
    )

    $Path = [string[]] @($defaultAnalyzerPaths + $rootScripts)
}

$analyzerPaths = [string[]] @(
    foreach ($candidatePath in $Path) {
        [string] (Resolve-WtcgAnalyzerPath -CandidatePath $candidatePath)
    }
)

$requestedRules = @(
    # Style and maintainability
    'PSAvoidUsingCmdletAliases'
    'PSAvoidTrailingWhitespace'
    'PSPlaceOpenBrace'
    'PSPlaceCloseBrace'
    'PSUseApprovedVerbs'
    'PSUseConsistentIndentation'
    'PSUseConsistentWhitespace'
    'PSUseCompatibleSyntax'
    'PSUseDeclaredVarsMoreThanAssignments'

    # Pipeline and command correctness
    'PSUseCmdletCorrectly'
    'PSUseOutputTypeCorrectly'
    'PSUseProcessBlockForPipelineCommand'

    # Security and risky constructs
    'PSAvoidAssignmentToAutomaticVariable'
    'PSAvoidGlobalVars'
    'PSAvoidUsingConvertToSecureStringWithPlainText'
    'PSAvoidUsingEmptyCatchBlock'
    'PSAvoidUsingInvokeExpression'
    'PSAvoidUsingPlainTextForPassword'
    'PSAvoidUsingUsernameAndPasswordParams'
    'PSAvoidUsingWMICmdlet'
    'PSUsePSCredentialType'

    # ShouldProcess and destructive-action guardrails
    'PSAvoidShouldContinueWithoutForce'
    'PSUseShouldProcessForStateChangingFunctions'
    'PSUseSupportsShouldProcess'
)

$availableRules = Get-ScriptAnalyzerRule | Select-Object -ExpandProperty RuleName
$activeRules = @($requestedRules | Where-Object { $_ -in $availableRules })
$missingRules = @($requestedRules | Where-Object { $_ -notin $availableRules })

if ($missingRules.Count -gt 0) {
    Write-Warning "The installed PSScriptAnalyzer version does not expose these requested rules: $($missingRules -join ', ')"
}

if ($activeRules.Count -eq 0) {
    throw 'No requested PSScriptAnalyzer rules are available. Check the installed PSScriptAnalyzer version.'
}

Write-Host "Running PSScriptAnalyzer against $($analyzerPaths.Count) path(s)."
Write-Host "Settings: $settingsFile"
Write-Host "Rules: $($activeRules -join ', ')"
Write-Host "Severity: $($Severity -join ', ')"
Write-Host "Fail on severity: $($FailOnSeverity -join ', ')"

$diagnostics = @(
    foreach ($analyzerPath in $analyzerPaths) {
        Invoke-ScriptAnalyzer `
            -Path $analyzerPath `
            -Settings $settingsFile `
            -IncludeRule $activeRules `
            -Severity $Severity `
            -Recurse
    }
)

$resultObjects = @(
    foreach ($diagnostic in $diagnostics) {
        [pscustomobject]@{
            Severity = [string] $diagnostic.Severity
            RuleName = [string] $diagnostic.RuleName
            ScriptName = [string] $diagnostic.ScriptName
            Line = [int] $diagnostic.Line
            Column = [int] $diagnostic.Column
            Message = [string] $diagnostic.Message
        }
    }
) | Sort-Object -Property Severity, ScriptName, Line, Column, RuleName

$jsonPath = Join-Path -Path $OutputDirectory -ChildPath 'scriptanalyzer-results.json'
$csvPath = Join-Path -Path $OutputDirectory -ChildPath 'scriptanalyzer-results.csv'

if ($resultObjects.Count -gt 0) {
    $resultObjects | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $resultObjects | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
} else {
    '[]' | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    '' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

Write-Host "PSScriptAnalyzer findings: $($resultObjects.Count)"
Write-Host "JSON report: $jsonPath"
Write-Host "CSV report: $csvPath"

if ($resultObjects.Count -gt 0) {
    $severitySummary = $resultObjects |
        Group-Object -Property Severity |
        Sort-Object -Property Name |
        ForEach-Object { "$($_.Name): $($_.Count)" }

    $ruleSummary = $resultObjects |
        Group-Object -Property RuleName |
        Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true } |
        Select-Object -First 15 |
        ForEach-Object { "$($_.Name): $($_.Count)" }

    Write-Host "PSScriptAnalyzer severity summary: $($severitySummary -join '; ')"
    Write-Host "PSScriptAnalyzer top rules: $($ruleSummary -join '; ')"

    if ($LogFindingLimit -gt 0) {
        Write-Host "Showing first $LogFindingLimit PSScriptAnalyzer finding(s):"
        $resultObjects |
            Select-Object -First $LogFindingLimit |
            ForEach-Object {
                Write-Host ("[{0}] {1} {2}:{3}:{4} - {5}" -f $_.Severity, $_.RuleName, $_.ScriptName, $_.Line, $_.Column, $_.Message)
            }
    }
}

if ($PassThru) {
    $resultObjects
}

$blockingResults = @(
    $resultObjects | Where-Object { $_.Severity -in $FailOnSeverity }
)

if ($blockingResults.Count -gt 0) {
    $blockingSummary = $blockingResults |
        Group-Object -Property Severity |
        Sort-Object -Property Name |
        ForEach-Object { "$($_.Name): $($_.Count)" }

    throw "PSScriptAnalyzer failed with $($blockingResults.Count) blocking finding(s). $($blockingSummary -join '; ')"
}

if ($resultObjects.Count -gt 0) {
    Write-Warning "PSScriptAnalyzer completed with non-blocking finding(s). Review $jsonPath or $csvPath for cleanup work."
}
