#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:InternalLoaderPath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\Load-WinTaskCrossingGuardInternal.ps1'
}

Describe 'WinTaskCrossingGuard internal loader' {
    It 'ships an internal loader for repository scripts' {
        Test-Path -LiteralPath $script:InternalLoaderPath -PathType Leaf | Should -BeTrue
    }

    It 'is used by repository scripts that call private helpers' {
        @(
            'scripts\Find-TasksInWindow.ps1'
            'scripts\Disable-TasksInWindow.ps1'
            'scripts\Enable-TaskIdentities.ps1'
            'scripts\Start-TaskIdentities.ps1'
            'scripts\Restore-TasksFromManifest.ps1'
            'scripts\Emergency-RestoreLatestDisabledTasks.ps1'
            'scripts\Example-WinTaskCrossingGuardWorkflow.ps1'
        ) | ForEach-Object {
            $scriptPath = Join-Path $script:ProjectRoot $_
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Match 'Load-WinTaskCrossingGuardInternal\.ps1'
        }
    }
}
