#requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'PSScriptAnalyzer CI gate' {
    BeforeAll {
        $script:RepositoryRoot = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $script:AnalyzerScriptPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'scripts\Invoke-WinTaskCrossingGuardAnalyzer.ps1'
        $script:RootWrapperPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'Invoke-WinTaskCrossingGuardAnalyzer.ps1'
        $script:SettingsPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
    }

    It 'has a repository PSScriptAnalyzer settings file' {
        Test-Path -LiteralPath $script:SettingsPath | Should -BeTrue

        $settings = Get-Content -LiteralPath $script:SettingsPath -Raw
        $settings | Should -Match "Severity\s*=\s*@\("
        $settings | Should -Match "'Error'"
        $settings | Should -Match "'Warning'"
        $settings | Should -Match 'PSUseCompatibleSyntax'
        $settings | Should -Match 'PSUseConsistentIndentation'
        $settings | Should -Match 'PSUseConsistentWhitespace'
    }

    It 'has a root analyzer wrapper that forwards to the script implementation' {
        Test-Path -LiteralPath $script:RootWrapperPath | Should -BeTrue

        $wrapper = Get-Content -LiteralPath $script:RootWrapperPath -Raw
        $wrapper | Should -Match 'scripts\\Invoke-WinTaskCrossingGuardAnalyzer\.ps1'
        $wrapper | Should -Match 'Join-Path -Path \$PSScriptRoot -ChildPath'
        $wrapper | Should -Match '@args'
        $wrapper | Should -Match 'exit \$LASTEXITCODE'
    }

    It 'requests style, unused-variable, command, security, and ShouldProcess rules' {
        Test-Path -LiteralPath $script:AnalyzerScriptPath | Should -BeTrue

        $scriptText = Get-Content -LiteralPath $script:AnalyzerScriptPath -Raw
        @(
            'PSUseApprovedVerbs'
            'PSUseDeclaredVarsMoreThanAssignments'
            'PSUseCmdletCorrectly'
            'PSAvoidUsingInvokeExpression'
            'PSAvoidUsingPlainTextForPassword'
            'PSUseShouldProcessForStateChangingFunctions'
            'PSUseSupportsShouldProcess'
        ) | ForEach-Object {
            $scriptText | Should -Match $_
        }

        $scriptText | Should -Not -Match "'PSAvoidUsingPositionalParameters'"
        $scriptText | Should -Not -Match "'PSUseSingularNouns'"
        $scriptText | Should -Match 'foreach \(\$analyzerPath in \$analyzerPaths\)'
        $scriptText | Should -Match '\[string\[\]\] \$FailOnSeverity = @\(''Error''\)'
        $scriptText | Should -Match '\$blockingResults'
        $scriptText | Should -Match 'PSScriptAnalyzer top rules'
    }

    It 'runs PSScriptAnalyzer before Pester in GitHub Actions' {
        $workflow = Get-Content -LiteralPath (Join-Path -Path $script:RepositoryRoot -ChildPath '.github\workflows\pester.yml') -Raw

        $workflow | Should -Match 'Invoke-WinTaskCrossingGuardAnalyzer\.ps1'
        $workflow | Should -Match 'scriptanalyzer-results\.json'
        $workflow.IndexOf('Invoke-WinTaskCrossingGuardAnalyzer.ps1') | Should -BeLessThan $workflow.IndexOf('Invoke-WinTaskCrossingGuardTests.ps1')
    }

    It 'runs PSScriptAnalyzer before Pester in GitLab CI' {
        $workflow = Get-Content -LiteralPath (Join-Path -Path $script:RepositoryRoot -ChildPath '.gitlab-ci.yml') -Raw

        $workflow | Should -Match 'Invoke-WinTaskCrossingGuardAnalyzer\.ps1'
        $workflow | Should -Match 'scriptanalyzer-results\.json'
        $workflow.IndexOf('Invoke-WinTaskCrossingGuardAnalyzer.ps1') | Should -BeLessThan $workflow.IndexOf('Invoke-WinTaskCrossingGuardTests.ps1')
    }

    It 'runs PSScriptAnalyzer before Pester in Azure Pipelines' {
        $workflow = Get-Content -LiteralPath (Join-Path -Path $script:RepositoryRoot -ChildPath 'azure-pipelines.yml') -Raw

        $workflow | Should -Match 'Invoke-WinTaskCrossingGuardAnalyzer\.ps1'
        $workflow | Should -Match 'scriptanalyzer-results\.json'
        $workflow.IndexOf('Invoke-WinTaskCrossingGuardAnalyzer.ps1') | Should -BeLessThan $workflow.IndexOf('Invoke-WinTaskCrossingGuardTests.ps1')
    }
}
