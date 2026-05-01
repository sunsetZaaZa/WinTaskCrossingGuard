#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'

    Import-Module $script:ModulePath -Force
}

Describe 'Disable-WtcgTasksInWindowAndScheduleReenable orchestration' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null

        $script:IdentityPath = Join-Path $script:TempDir 'identities.json'
        $script:SelectionPath = Join-Path $script:TempDir 'selection.json'
        $script:EnableScriptPath = Join-Path $script:ProjectRoot 'scripts\Restore-TasksFromManifest.ps1'

        @{
            includeTasks = @(
                @{
                    taskPath = '\Root\'
                    taskName = 'InWindow'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:SelectionPath -Encoding utf8

        # WTCG module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            IdentityPath = $script:IdentityPath
            SelectionPath = $script:SelectionPath
            EnableScriptPath = $script:EnableScriptPath
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $IdentityPath, $SelectionPath, $EnableScriptPath, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:IdentityPath = $IdentityPath
            $script:SelectionPath = $SelectionPath
            $script:EnableScriptPath = $EnableScriptPath
            $script:ProjectRoot = $ProjectRoot
        }
        InModuleScope WinTaskCrossingGuard {
            function Import-Module { }
            function Get-ScheduledTask {
                param(
                    [string] $TaskPath,
                    [string] $TaskName,
                    [string] $ErrorAction
                )
            }

            function Get-ScheduledTaskInfo {
                param(
                    [string] $TaskPath,
                    [string] $TaskName
                )
            }

            function Disable-ScheduledTask {
                param(
                    [string] $TaskPath,
                    [string] $TaskName
                )
            }
            function New-ScheduledTaskAction { }
            function New-ScheduledTaskTrigger { }
            function New-ScheduledTaskSettingsSet { }
            function New-ScheduledTaskPrincipal { }
            function Register-ScheduledTask { }
            function Set-ScheduledTask { }

            function Invoke-WtcgRegisterScheduledTask {
                param(
                    [string] $TaskPath,
                    [string] $TaskName,
                    $Action,
                    $Trigger,
                    $Settings,
                    $Principal,
                    [string] $Description,
                    [switch] $Force
                )
            }

            function Invoke-WtcgSetScheduledTask {
                param(
                    [string] $TaskPath,
                    [string] $TaskName,
                    $Action,
                    $Trigger,
                    $Settings,
                    $Principal
                )
            }
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds tasks, disables them, writes identities, and creates a re-enable scheduled task when one does not exist' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                return $null
            }

            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'InWindow'
            } {
                [pscustomobject]@{
                    TaskPath = '\Root\'
                    TaskName = 'InWindow'
                    State = 'Ready'
                    Author = 'Pester'
                    Description = 'In window task'
                }
            }

            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'InWindow'
                        State = 'Ready'
                        Author = 'Pester'
                        Description = 'In window task'
                    }
                )
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }
            Mock Disable-ScheduledTask {}
            Mock New-ScheduledTaskAction {
                [pscustomobject]@{
                    Execute = $Execute
                    Argument = $Argument
                }
            }
            Mock New-ScheduledTaskTrigger {
                [pscustomobject]@{
                    Once = $Once
                    At = $At
                }
            }
            Mock New-ScheduledTaskSettingsSet {
                [pscustomobject]@{
                    StartWhenAvailable = $StartWhenAvailable
                }
            }
            Mock New-ScheduledTaskPrincipal {
                [pscustomobject]@{
                    UserId = $UserId
                    LogonType = $LogonType
                    RunLevel = $RunLevel
                }
            }
            Mock Invoke-WtcgRegisterScheduledTask { [pscustomobject]@{ Registered = $true } }
            Mock Invoke-WtcgSetScheduledTask {}

            $result = Disable-WtcgTasksInWindowAndScheduleReenable `
                -Start '2030-01-02T08:00:00' `
                -End '2030-01-02T17:00:00' `
                -ReenableAt ([datetime]'2030-01-02T18:00:00') `
                -SelectionPath $script:SelectionPath `
                -IdentityOutputPath $script:IdentityPath `
                -ReenableTaskPath '\WinTaskCrossingGuard\' `
                -ReenableTaskName 'ReenableDisabledTasks' `
                -PowerShellExePath 'pwsh.exe' `
                -EnableScriptPath $script:EnableScriptPath `
                -PassThru

            $result.DisabledTaskCount | Should -Be 1
            $result.IdentityOutputPath | Should -Be $script:IdentityPath
            $result.ReenableAt | Should -Be ([datetime]'2030-01-02T18:00:00')
            $result.ReenableTaskPath | Should -Be '\WinTaskCrossingGuard\'
            $result.ReenableTaskName | Should -Be 'ReenableDisabledTasks'
            $result.ReenableTaskFullName | Should -Be '\WinTaskCrossingGuard\ReenableDisabledTasks'
            @($result.Tasks).Count | Should -Be 1
            $result.Tasks[0].TaskPath | Should -Be '\Root\'
            $result.Tasks[0].TaskName | Should -Be 'InWindow'

            Test-Path -LiteralPath $script:IdentityPath | Should -BeTrue

            Should -Invoke Disable-ScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\Root\' -and $TaskName -eq 'InWindow'
            }

            Should -Invoke New-ScheduledTaskAction -Times 1 -ParameterFilter {
                $Execute -eq 'pwsh.exe' -and
                $Argument -like '*Restore-TasksFromManifest.ps1*' -and
                $Argument -like '*-ManifestPath*' -and
                $Argument -like '*identities.json*' -and
                $Argument -like '*-JsonlLogPath*' -and
                $Argument -like '*-EventLogSource*' -and
                $Argument -like '*WinTaskCrossingGuard*' -and
                $Argument -like '*-EventLogName*'
            }

            Should -Invoke New-ScheduledTaskTrigger -Times 1 -ParameterFilter {
                $Once -eq $true -and $At -eq ([datetime]'2030-01-02T18:00:00')
            }

            Should -Invoke Invoke-WtcgRegisterScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\WinTaskCrossingGuard\' -and
                $TaskName -eq 'ReenableDisabledTasks' -and
                $Force -eq $true
            }

            Should -Invoke Invoke-WtcgSetScheduledTask -Times 0
        }
    }

    It 'blocks a new run when the configured re-enable task is still active' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                [pscustomobject]@{
                    TaskPath = '\WinTaskCrossingGuard\'
                    TaskName = 'ReenableDisabledTasks'
                    State = 'Ready'
                    Description = 'Re-enables tasks disabled by WinTaskCrossingGuard.'
                }
            }
            Mock Get-ScheduledTaskInfo -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T18:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }
            Mock Disable-ScheduledTask {}
            Mock Invoke-WtcgRegisterScheduledTask {}
            Mock Invoke-WtcgSetScheduledTask {}

            {
                Disable-WtcgTasksInWindowAndScheduleReenable `
                    -Start '2030-01-02T08:00:00' `
                    -End '2030-01-02T17:00:00' `
                    -ReenableAt ([datetime]'2030-01-02T19:00:00') `
                    -IdentityOutputPath $script:IdentityPath `
                    -XmlLogPath (Join-Path $script:TempDir 'overlap-error.xml') `
                    -JsonlLogPath (Join-Path $script:TempDir 'overlap-error.jsonl') `
                    -ReenableTaskPath '\WinTaskCrossingGuard\' `
                    -ReenableTaskName 'ReenableDisabledTasks' `
                    -EnableScriptPath $script:EnableScriptPath `
                    -PassThru
            } | Should -Throw '*Active prior WinTaskCrossingGuard re-enable run detected*'

            Test-Path -LiteralPath $script:IdentityPath | Should -BeFalse

            Should -Invoke Disable-ScheduledTask -Times 0
            Should -Invoke Invoke-WtcgRegisterScheduledTask -Times 0
            Should -Invoke Invoke-WtcgSetScheduledTask -Times 0
        }
    }

    It 'detects an overlapping manifest-backed active prior run in the re-enable folder' {
        InModuleScope WinTaskCrossingGuard {
            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                return $null
            }

            $priorManifestPath = Join-Path $script:TempDir 'prior-manifest.json'
            @{
                Kind = 'WinTaskCrossingGuard.RollbackManifest'
                ManifestVersion = 1
                CreatedAt = [datetime]'2030-01-02T08:00:00'
                WindowStart = [datetime]'2030-01-02T08:00:00'
                WindowEnd = [datetime]'2030-01-02T17:00:00'
                Tasks = @(
                    @{
                        TaskPath = '\Root\'
                        TaskName = 'InWindow'
                        FullName = '\Root\InWindow'
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $priorManifestPath -Encoding utf8

            Mock Get-ScheduledTask -ParameterFilter {
                $TaskPath -eq '\WinTaskCrossingGuard\' -and -not $PSBoundParameters.ContainsKey('TaskName')
            } {
                [pscustomobject]@{
                    TaskPath = '\WinTaskCrossingGuard\'
                    TaskName = 'PriorRunRestore'
                    State = 'Ready'
                    Description = 'WinTaskCrossingGuard restore task'
                    Actions = @(
                        [pscustomobject]@{
                            Arguments = ('-NoProfile -File restore.ps1 -ManifestPath "{0}"' -f $priorManifestPath)
                        }
                    )
                }
            }
            Mock Get-ScheduledTaskInfo -ParameterFilter {
                $TaskName -eq 'PriorRunRestore'
            } {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T18:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }

            $run = Get-WtcgActivePriorReenableRun `
                -WindowStart ([datetime]'2030-01-02T17:30:00') `
                -WindowEnd ([datetime]'2030-01-02T19:00:00') `
                -ReenableAt ([datetime]'2030-01-02T20:00:00') `
                -ReenableTaskPath '\WinTaskCrossingGuard\' `
                -ReenableTaskName 'ReenableDisabledTasks' `
                -Now ([datetime]'2030-01-02T12:00:00')

            $run | Should -Not -BeNullOrEmpty
            $run.TaskName | Should -Be 'PriorRunRestore'
            $run.ManifestPath | Should -Be $priorManifestPath
            $run.OverlapReason | Should -Be 'active re-enable window overlaps requested disable-to-reenable interval'
        }
    }

    It 'updates the existing re-enable scheduled task trigger when the existing task is stale' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                [pscustomobject]@{
                    TaskPath = '\WinTaskCrossingGuard\'
                    TaskName = 'ReenableDisabledTasks'
                    State = 'Ready'
                }
            }

            Mock Get-ScheduledTask -ParameterFilter {
                $TaskName -eq 'InWindow'
            } {
                [pscustomobject]@{
                    TaskPath = '\Root\'
                    TaskName = 'InWindow'
                    State = 'Ready'
                    Author = 'Pester'
                    Description = 'In window task'
                }
            }

            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'InWindow'
                        State = 'Ready'
                        Author = 'Pester'
                        Description = 'In window task'
                    }
                )
            }
            Mock Get-ScheduledTaskInfo -ParameterFilter {
                $TaskName -eq 'ReenableDisabledTasks'
            } {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2029-12-31T23:59:00'
                    LastRunTime = [datetime]'2029-12-31T23:59:00'
                    LastTaskResult = 0
                }
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }
            Mock Disable-ScheduledTask {}
            Mock New-ScheduledTaskAction { [pscustomobject]@{ Execute = $Execute; Argument = $Argument } }
            Mock New-ScheduledTaskTrigger { [pscustomobject]@{ Once = $Once; At = $At } }
            Mock New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
            Mock New-ScheduledTaskPrincipal { [pscustomobject]@{} }
            Mock Invoke-WtcgRegisterScheduledTask {}
            Mock Invoke-WtcgSetScheduledTask { [pscustomobject]@{ Updated = $true } }

            $result = Disable-WtcgTasksInWindowAndScheduleReenable `
                -Start '2030-01-02T08:00:00' `
                -End '2030-01-02T17:00:00' `
                -ReenableAt ([datetime]'2030-01-03T06:30:00') `
                -IdentityOutputPath $script:IdentityPath `
                -ReenableTaskPath '\WinTaskCrossingGuard\' `
                -ReenableTaskName 'ReenableDisabledTasks' `
                -EnableScriptPath $script:EnableScriptPath `
                -PassThru

            $result.DisabledTaskCount | Should -Be 1
            $result.ReenableAt | Should -Be ([datetime]'2030-01-03T06:30:00')

            Should -Invoke Invoke-WtcgRegisterScheduledTask -Times 0
            Should -Invoke Invoke-WtcgSetScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\WinTaskCrossingGuard\' -and
                $TaskName -eq 'ReenableDisabledTasks'
            }
        }
    }

    It 'returns without disabling or scheduling when no tasks are inside the window' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'OutWindow'
                        State = 'Ready'
                        Author = 'Pester'
                        Description = 'Out window task'
                    }
                )
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T20:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }
            Mock Disable-ScheduledTask {}
            Mock Invoke-WtcgRegisterScheduledTask {}
            Mock Invoke-WtcgSetScheduledTask {}

            $result = Disable-WtcgTasksInWindowAndScheduleReenable `
                -Start '2030-01-02T08:00:00' `
                -End '2030-01-02T17:00:00' `
                -ReenableAt ([datetime]'2030-01-03T06:30:00') `
                -IdentityOutputPath $script:IdentityPath `
                -PassThru

            $result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $script:IdentityPath | Should -BeFalse

            Should -Invoke Disable-ScheduledTask -Times 0
            Should -Invoke Invoke-WtcgRegisterScheduledTask -Times 0
            Should -Invoke Invoke-WtcgSetScheduledTask -Times 0
        }
    }

    It 'supports WhatIf so tasks are found and identities are exported without disabling or scheduling' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                if ($PSBoundParameters.ContainsKey('TaskName') -and $TaskName -eq 'ReenableDisabledTasks') {
                    return $null
                }

                @(
                    [pscustomobject]@{
                        TaskPath = '\Root\'
                        TaskName = 'InWindow'
                        State = 'Ready'
                        Author = 'Pester'
                        Description = 'In window task'
                    }
                )
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                }
            }
            Mock Disable-ScheduledTask {}
            Mock New-ScheduledTaskAction { [pscustomobject]@{} }
            Mock New-ScheduledTaskTrigger { [pscustomobject]@{} }
            Mock New-ScheduledTaskSettingsSet { [pscustomobject]@{} }
            Mock New-ScheduledTaskPrincipal { [pscustomobject]@{} }
            Mock Invoke-WtcgRegisterScheduledTask {}
            Mock Invoke-WtcgSetScheduledTask {}

            $result = Disable-WtcgTasksInWindowAndScheduleReenable `
                -Start '2030-01-02T08:00:00' `
                -End '2030-01-02T17:00:00' `
                -ReenableAt ([datetime]'2030-01-03T06:30:00') `
                -IdentityOutputPath $script:IdentityPath `
                -PassThru `
                -WhatIf

            $result.DisabledTaskCount | Should -Be 0
            Test-Path -LiteralPath $script:IdentityPath | Should -BeTrue

            Should -Invoke Disable-ScheduledTask -Times 0
            Should -Invoke Invoke-WtcgRegisterScheduledTask -Times 0
            Should -Invoke Invoke-WtcgSetScheduledTask -Times 0
        }
    }
}
