#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Wrapper script availability' {
    It 'ships all wrapper scripts expected by the suite' {
        @(
            'scripts\Find-TasksInWindow.ps1'
            'scripts\Disable-TasksInWindow.ps1'
            'scripts\Enable-TaskIdentities.ps1'
            'scripts\Start-TaskIdentities.ps1'
            'scripts\Restore-TasksFromManifest.ps1'
            'scripts\Emergency-RestoreLatestDisabledTasks.ps1'
        ) | ForEach-Object {
            Test-Path (Join-Path $script:ProjectRoot $_) | Should -BeTrue
        }
    }

    It 'wrapper scripts parse without syntax errors' {
        @(
            'scripts\Find-TasksInWindow.ps1'
            'scripts\Disable-TasksInWindow.ps1'
            'scripts\Enable-TaskIdentities.ps1'
            'scripts\Start-TaskIdentities.ps1'
            'scripts\Restore-TasksFromManifest.ps1'
            'scripts\Emergency-RestoreLatestDisabledTasks.ps1'
        ) | ForEach-Object {
            $path = Join-Path $script:ProjectRoot $_
            $tokens = $null
            $errors = $null

            [System.Management.Automation.Language.Parser]::ParseFile(
                $path,
                [ref] $tokens,
                [ref] $errors
            ) | Out-Null

            $errors | Should -BeNullOrEmpty
        }
    }
}

Describe 'Wrapper script identity file consumers' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null

        $script:IdentityPath = Join-Path $script:TempDir 'identities.json'
        @{
            Kind = 'Test'
            CreatedAt = Get-Date
            Tasks = @(
                @{
                    TaskPath = '\Root\'
                    TaskName = 'A'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:IdentityPath -Encoding utf8
        # WTCG module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            IdentityPath = $script:IdentityPath
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $IdentityPath, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:IdentityPath = $IdentityPath
            $script:ProjectRoot = $ProjectRoot
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Enable-TaskIdentities.ps1 supports WhatIf with an identity file' {
        $scriptPath = Join-Path $script:ProjectRoot 'scripts\Enable-TaskIdentities.ps1'

        { & $scriptPath -IdentityPath $script:IdentityPath -WhatIf } | Should -Not -Throw
    }

    It 'Start-TaskIdentities.ps1 supports WhatIf with an identity file' {
        $scriptPath = Join-Path $script:ProjectRoot 'scripts\Start-TaskIdentities.ps1'

        { & $scriptPath -IdentityPath $script:IdentityPath -WhatIf } | Should -Not -Throw
    }

    It 'Enable-TaskIdentities.ps1 throws when no identities are supplied' {
        $scriptPath = Join-Path $script:ProjectRoot 'scripts\Enable-TaskIdentities.ps1'

        { & $scriptPath } | Should -Throw
    }

    It 'Start-TaskIdentities.ps1 throws when no identities are supplied' {
        $scriptPath = Join-Path $script:ProjectRoot 'scripts\Start-TaskIdentities.ps1'

        { & $scriptPath } | Should -Throw
    }
}
