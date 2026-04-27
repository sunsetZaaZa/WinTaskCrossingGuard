#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Safety allow-list mode' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null

        # WTCG module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:ProjectRoot = $ProjectRoot
        }
        InModuleScope WinTaskCrossingGuard {
            function Import-Module { }
            function Get-ScheduledTask { }
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports safetyAllowListMode from SelectionPath JSON' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'

            @{
                safetyAllowListMode = $true
                includeTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = 'AllowedTask'
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $selection = Import-WtcgTaskSelection -Path $path

            $selection.SafetyAllowListMode | Should -BeTrue
            Test-WtcgSelectionHasExplicitIncludes -Selection $selection | Should -BeTrue
        }
    }

    It 'throws before scanning when safety allow-list mode is enabled without includes' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                throw 'Get-ScheduledTask should not be called'
            }

            $selection = [pscustomobject]@{
                SafetyAllowListMode = $true
                IncludeFolders = @()
                IncludeTasks = @()
                ExcludeFolders = @()
                ExcludeTasks = @()
                ProtectedFolders = @()
                ProtectedTasks = @()
                UseDefaultProtectedTaskList = $true
            }

            {
                Get-WtcgScheduledTaskCandidate `
                    -TaskPath '\' `
                    -Recurse `
                    -Selection $selection
            } | Should -Throw -ExpectedMessage '*Safety allow-list mode is enabled*'

            Should -Invoke Get-ScheduledTask -Times 0
        }
    }

    It 'allows scanning when safety allow-list mode has includeTasks' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'AllowedTask'
                        State = 'Ready'
                    }
                )
            }

            $selection = [pscustomobject]@{
                SafetyAllowListMode = $true
                IncludeFolders = @()
                IncludeTasks = @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'AllowedTask'
                    }
                )
                ExcludeFolders = @()
                ExcludeTasks = @()
                ProtectedFolders = @()
                ProtectedTasks = @()
                UseDefaultProtectedTaskList = $true
            }

            $result = @(Get-WtcgScheduledTaskCandidate `
                -TaskPath '\Root\' `
                -Selection $selection)

            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'AllowedTask'
        }
    }

    It 'allows scanning when safety allow-list mode has includeFolders' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Allowed\'
                        TaskName = 'FolderTask'
                        State = 'Ready'
                    }
                )
            }

            $selection = [pscustomobject]@{
                SafetyAllowListMode = $true
                IncludeFolders = @(
                    [pscustomobject]@{
                        TaskPath = '\Allowed\'
                        Recurse = $false
                    }
                )
                IncludeTasks = @()
                ExcludeFolders = @()
                ExcludeTasks = @()
                ProtectedFolders = @()
                ProtectedTasks = @()
                UseDefaultProtectedTaskList = $true
            }

            $result = @(Get-WtcgScheduledTaskCandidate `
                -TaskPath '\Allowed\' `
                -Selection $selection)

            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'FolderTask'
        }
    }
    It 'directly allows explicit includes through Assert-WtcgSafetyAllowListSatisfied' {
        InModuleScope WinTaskCrossingGuard {
            $selection = [pscustomobject]@{
                SafetyAllowListMode = $true
                IncludeFolders = @()
                IncludeTasks = @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'AllowedTask'
                    }
                )
            }

            { Assert-WtcgSafetyAllowListSatisfied -Selection $selection } | Should -Not -Throw
        }
    }

}

Describe 'Protected never-disable task policy' {
    BeforeEach {
        InModuleScope WinTaskCrossingGuard {
            function Import-Module { }
            function Get-ScheduledTask { }
        }
    }

    It 'returns built-in protected folder selections' {
        InModuleScope WinTaskCrossingGuard {
            $folders = @(Get-WtcgDefaultProtectedFolderSelection)

            $folders.Count | Should -BeGreaterThan 0
            $folders.TaskPath | Should -Contain '\Microsoft\Windows\UpdateOrchestrator\'
            ($folders | Where-Object TaskPath -eq '\Microsoft\Windows\UpdateOrchestrator\').Recurse | Should -BeTrue
        }
    }

    It 'treats Microsoft UpdateOrchestrator tasks as protected by default' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{
                TaskPath = '\Microsoft\Windows\UpdateOrchestrator\'
                TaskName = 'Schedule Scan'
            }

            Test-WtcgTaskProtected -Task $task -Selection $null | Should -BeTrue
        }
    }

    It 'lets callers disable the built-in protected task list explicitly' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{
                TaskPath = '\Microsoft\Windows\UpdateOrchestrator\'
                TaskName = 'Schedule Scan'
            }

            $selection = [pscustomobject]@{
                UseDefaultProtectedTaskList = $false
                ProtectedFolders = @()
                ProtectedTasks = @()
            }

            Test-WtcgTaskProtected -Task $task -Selection $selection | Should -BeFalse
        }
    }

    It 'treats user-defined protected folders as protected' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{
                TaskPath = '\MyCompany\Critical\Nested\'
                TaskName = 'CriticalTask'
            }

            $selection = [pscustomobject]@{
                UseDefaultProtectedTaskList = $true
                ProtectedFolders = @(
                    [pscustomobject]@{
                        TaskPath = '\MyCompany\Critical\'
                        Recurse = $true
                    }
                )
                ProtectedTasks = @()
            }

            Test-WtcgTaskProtected -Task $task -Selection $selection | Should -BeTrue
        }
    }

    It 'treats user-defined protected tasks as protected by wildcard name' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{
                TaskPath = '\MyCompany\'
                TaskName = 'DoNotDisable-Heartbeat'
            }

            $selection = [pscustomobject]@{
                UseDefaultProtectedTaskList = $false
                ProtectedFolders = @()
                ProtectedTasks = @(
                    [pscustomobject]@{
                        TaskPath = '\MyCompany\'
                        TaskName = 'DoNotDisable-*'
                    }
                )
            }

            Test-WtcgTaskProtected -Task $task -Selection $selection | Should -BeTrue
        }
    }

    It 'protected tasks are blocked even when explicitly included' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{
                TaskPath = '\MyCompany\'
                TaskName = 'DoNotDisable-Heartbeat'
            }

            $selection = [pscustomobject]@{
                SafetyAllowListMode = $true
                IncludeFolders = @()
                IncludeTasks = @(
                    [pscustomobject]@{
                        TaskPath = '\MyCompany\'
                        TaskName = 'DoNotDisable-*'
                    }
                )
                ExcludeFolders = @()
                ExcludeTasks = @()
                UseDefaultProtectedTaskList = $false
                ProtectedFolders = @()
                ProtectedTasks = @(
                    [pscustomobject]@{
                        TaskPath = '\MyCompany\'
                        TaskName = 'DoNotDisable-*'
                    }
                )
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeFalse
        }
    }

    It 'candidate discovery filters out built-in protected tasks' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Microsoft\Windows\UpdateOrchestrator\'
                        TaskName = 'Schedule Scan'
                        State = 'Ready'
                    },
                    [pscustomobject]@{
                        TaskPath = '\MyCompany\'
                        TaskName = 'AllowedTask'
                        State = 'Ready'
                    }
                )
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\' -Recurse)

            $result.TaskName | Should -Contain 'AllowedTask'
            $result.TaskName | Should -Not -Contain 'Schedule Scan'
        }
    }

    It 'imports protectedFolders and protectedTasks from SelectionPath JSON' {
        InModuleScope WinTaskCrossingGuard {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            try {
                $path = Join-Path $tempDir 'selection.json'

                @{
                    protectedFolders = @(
                        @{
                            taskPath = '\MyCompany\Critical\'
                            recurse = $true
                        }
                    )
                    protectedTasks = @(
                        @{
                            taskPath = '\MyCompany\'
                            taskName = 'DoNotDisable-*'
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

                $selection = Import-WtcgTaskSelection -Path $path

                $selection.ProtectedFolders.Count | Should -Be 1
                $selection.ProtectedFolders[0].TaskPath | Should -Be '\MyCompany\Critical\'
                $selection.ProtectedFolders[0].Recurse | Should -BeTrue
                $selection.ProtectedTasks.Count | Should -Be 1
                $selection.ProtectedTasks[0].TaskName | Should -Be 'DoNotDisable-*'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
