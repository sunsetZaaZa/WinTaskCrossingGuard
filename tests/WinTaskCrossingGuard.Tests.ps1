#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'

    Import-Module $script:ModulePath -Force

    function New-FakeScheduledTask {
        param(
            [string] $TaskPath = '\',
            [string] $TaskName = 'FakeTask',
            [string] $State = 'Ready',
            [string] $Author = 'Pester',
            [string] $Description = 'Test task'
        )

        [pscustomobject]@{
            TaskPath    = $TaskPath
            TaskName    = $TaskName
            State       = $State
            Author      = $Author
            Description = $Description
        }
    }

    function New-FakeScheduledTaskInfo {
        param(
            [datetime] $NextRunTime = (Get-Date),
            [datetime] $LastRunTime = [datetime]::MinValue,
            [int] $LastTaskResult = 0
        )

        [pscustomobject]@{
            NextRunTime    = $NextRunTime
            LastRunTime    = $LastRunTime
            LastTaskResult = $LastTaskResult
        }
    }
}

Describe 'WinTaskCrossingGuard pure date/time helpers' {
    It 'parses an ISO date/time string as an exact DateTime' {
        InModuleScope WinTaskCrossingGuard {
            $result = Resolve-WtcgDateTime -Value '2026-04-26T22:30:45'
            $result.Year | Should -Be 2026
            $result.Month | Should -Be 4
            $result.Day | Should -Be 26
            $result.Hour | Should -Be 22
            $result.Minute | Should -Be 30
            $result.Second | Should -Be 45
        }
    }

    It 'anchors a time-only string to the provided anchor date' {
        InModuleScope WinTaskCrossingGuard {
            $anchor = [datetime]'2030-12-25T03:04:05'
            $result = Resolve-WtcgDateTime -Value '22:15' -AnchorDate $anchor

            $result.Year | Should -Be 2030
            $result.Month | Should -Be 12
            $result.Day | Should -Be 25
            $result.Hour | Should -Be 22
            $result.Minute | Should -Be 15
        }
    }

    It 'anchors a time-only string with AM/PM to the provided anchor date' {
        InModuleScope WinTaskCrossingGuard {
            $anchor = [datetime]'2030-12-25T03:04:05'
            $result = Resolve-WtcgDateTime -Value '9:05 PM' -AnchorDate $anchor

            $result.Year | Should -Be 2030
            $result.Month | Should -Be 12
            $result.Day | Should -Be 25
            $result.Hour | Should -Be 21
            $result.Minute | Should -Be 5
        }
    }

    It 'throws for unparseable date/time input' {
        InModuleScope WinTaskCrossingGuard {
            { Resolve-WtcgDateTime -Value 'not-a-clock' } | Should -Throw
        }
    }

    It 'resolves a same-day window' {
        InModuleScope WinTaskCrossingGuard {
            $anchor = [datetime]'2030-01-02T00:00:00'
            $window = Resolve-WtcgWindow -Start '08:00' -End '17:00' -AnchorDate $anchor

            $window.Start | Should -Be ([datetime]'2030-01-02T08:00:00')
            $window.End   | Should -Be ([datetime]'2030-01-02T17:00:00')
        }
    }

    It 'resolves an overnight window by adding a day to End' {
        InModuleScope WinTaskCrossingGuard {
            $anchor = [datetime]'2030-01-02T00:00:00'
            $window = Resolve-WtcgWindow -Start '22:00' -End '06:00' -AnchorDate $anchor

            $window.Start | Should -Be ([datetime]'2030-01-02T22:00:00')
            $window.End   | Should -Be ([datetime]'2030-01-03T06:00:00')
        }
    }

    It 'treats date/times inside the window as in-window inclusively' {
        InModuleScope WinTaskCrossingGuard {
            Test-WtcgDateTimeInWindow `
                -DateTime ([datetime]'2030-01-02T08:00:00') `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') |
                Should -BeTrue

            Test-WtcgDateTimeInWindow `
                -DateTime ([datetime]'2030-01-02T17:00:00') `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') |
                Should -BeTrue
        }
    }

    It 'treats date/times outside the window as outside' {
        InModuleScope WinTaskCrossingGuard {
            Test-WtcgDateTimeInWindow `
                -DateTime ([datetime]'2030-01-02T07:59:59') `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') |
                Should -BeFalse
        }
    }
}

Describe 'WinTaskCrossingGuard task path and folder selection helpers' {
    It 'normalizes null, empty, relative, and slashless task paths' {
        InModuleScope WinTaskCrossingGuard {
            Normalize-WtcgTaskPath -TaskPath $null | Should -Be '\'
            Normalize-WtcgTaskPath -TaskPath '' | Should -Be '\'
            Normalize-WtcgTaskPath -TaskPath 'MyCompany' | Should -Be '\MyCompany\'
            Normalize-WtcgTaskPath -TaskPath '\MyCompany' | Should -Be '\MyCompany\'
            Normalize-WtcgTaskPath -TaskPath '\MyCompany\' | Should -Be '\MyCompany\'
        }
    }

    It 'creates a folder selection with normalized task path and recurse flag' {
        InModuleScope WinTaskCrossingGuard {
            $folder = New-WtcgFolderSelection -TaskPath 'MyCompany' -Recurse $true

            $folder.TaskPath | Should -Be '\MyCompany\'
            $folder.Recurse | Should -BeTrue
        }
    }

    It 'converts a legacy string folder entry using the provided default recurse value' {
        InModuleScope WinTaskCrossingGuard {
            $folder = 'MyCompany' | ConvertTo-WtcgFolderSelection -DefaultRecurse $true

            $folder.TaskPath | Should -Be '\MyCompany\'
            $folder.Recurse | Should -BeTrue
        }
    }

    It 'converts an object folder entry that uses taskPath and recurse' {
        InModuleScope WinTaskCrossingGuard {
            $folder = [pscustomobject]@{
                taskPath = 'MyCompany'
                recurse = $false
            } | ConvertTo-WtcgFolderSelection -DefaultRecurse $true

            $folder.TaskPath | Should -Be '\MyCompany\'
            $folder.Recurse | Should -BeFalse
        }
    }

    It 'converts an object folder entry that uses path alias' {
        InModuleScope WinTaskCrossingGuard {
            $folder = [pscustomobject]@{
                path = 'AliasFolder'
            } | ConvertTo-WtcgFolderSelection -DefaultRecurse $true

            $folder.TaskPath | Should -Be '\AliasFolder\'
            $folder.Recurse | Should -BeTrue
        }
    }

    It 'throws when folder selection object has no path' {
        InModuleScope WinTaskCrossingGuard {
            { [pscustomobject]@{ recurse = $true } | ConvertTo-WtcgFolderSelection } | Should -Throw
        }
    }
}

Describe 'WinTaskCrossingGuard task identity import/export helpers' {
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
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates a task identity with normalized path and full name' {
        InModuleScope WinTaskCrossingGuard {
            $identity = New-WtcgTaskIdentity -TaskPath 'MyCompany' -TaskName 'NightlyBackup' -NextRunTime ([datetime]'2030-01-02T03:00:00') -State Ready

            $identity.PSTypeNames[0] | Should -Be 'WinTaskCrossingGuard.TaskIdentity'
            $identity.TaskPath | Should -Be '\MyCompany\'
            $identity.TaskName | Should -Be 'NightlyBackup'
            $identity.FullName | Should -Be '\MyCompany\NightlyBackup'
            $identity.NextRunTime | Should -Be ([datetime]'2030-01-02T03:00:00')
            $identity.State | Should -Be 'Ready'
        }
    }

    It 'exports task identities to JSON and imports them back from the Tasks payload shape' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'identities.json'

            $original = @(
                New-WtcgTaskIdentity -TaskPath 'MyCompany' -TaskName 'A'
                New-WtcgTaskIdentity -TaskPath 'Other' -TaskName 'B'
            )

            $file = $original | Export-WtcgTaskIdentity -Path $path -Kind 'TestKind'
            $file.Exists | Should -BeTrue

            $payload = Get-Content -Path $path -Raw | ConvertFrom-Json
            $payload.Kind | Should -Be 'TestKind'
            @($payload.Tasks).Count | Should -Be 2

            $roundTrip = @(Import-WtcgTaskIdentity -Path $path)
            $roundTrip.Count | Should -Be 2
            $roundTrip[0].TaskPath | Should -Be '\MyCompany\'
            $roundTrip[0].TaskName | Should -Be 'A'
            $roundTrip[1].TaskPath | Should -Be '\Other\'
            $roundTrip[1].TaskName | Should -Be 'B'
        }
    }

    It 'imports a bare array of task identities' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'bare-identities.json'

            @(
                [pscustomobject]@{ TaskPath = '\A\'; TaskName = 'One' }
                [pscustomobject]@{ TaskPath = '\B\'; TaskName = 'Two' }
            ) | ConvertTo-Json | Set-Content -Path $path -Encoding utf8

            $result = @(Import-WtcgTaskIdentity -Path $path)

            $result.Count | Should -Be 2
            $result[0].FullName | Should -Be '\A\One'
            $result[1].FullName | Should -Be '\B\Two'
        }
    }

    It 'throws when importing a missing identity file' {
        InModuleScope WinTaskCrossingGuard {
            { Import-WtcgTaskIdentity -Path (Join-Path $script:TempDir 'missing.json') } | Should -Throw
        }
    }
}

Describe 'WinTaskCrossingGuard selection JSON import and matching' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

        # WTCG selection module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:ProjectRoot = $ProjectRoot
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports selection JSON with per-folder recurse and default recurse values' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'
            New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

            @{
                defaultIncludeFolderRecurse = $true
                defaultExcludeFolderRecurse = $false
                includeFolders = @(
                    '\LegacyString\'
                    @{
                        taskPath = '\ExactOnly\'
                        recurse = $false
                    }
                    @{
                        path = '\Alias\'
                        recurse = $true
                    }
                )
                excludeFolders = @(
                    '\Never\'
                    @{
                        taskPath = '\Nope\'
                        recurse = $true
                    }
                )
                includeTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = 'Include-*'
                    }
                )
                excludeTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = 'ExcludeMe'
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $selection = Import-WtcgTaskSelection -Path $path

            $selection.IncludeFolders.Count | Should -Be 3
            $selection.IncludeFolders[0].TaskPath | Should -Be '\LegacyString\'
            $selection.IncludeFolders[0].Recurse | Should -BeTrue
            $selection.IncludeFolders[1].TaskPath | Should -Be '\ExactOnly\'
            $selection.IncludeFolders[1].Recurse | Should -BeFalse
            $selection.IncludeFolders[2].TaskPath | Should -Be '\Alias\'
            $selection.IncludeFolders[2].Recurse | Should -BeTrue

            $selection.ExcludeFolders.Count | Should -Be 2
            $selection.ExcludeFolders[0].TaskPath | Should -Be '\Never\'
            $selection.ExcludeFolders[0].Recurse | Should -BeFalse
            $selection.ExcludeFolders[1].TaskPath | Should -Be '\Nope\'
            $selection.ExcludeFolders[1].Recurse | Should -BeTrue

            $selection.IncludeTasks[0].TaskPath | Should -Be '\Root\'
            $selection.IncludeTasks[0].TaskName | Should -Be 'Include-*'
            $selection.ExcludeTasks[0].TaskPath | Should -Be '\Root\'
            $selection.ExcludeTasks[0].TaskName | Should -Be 'ExcludeMe'
            $selection.SourcePath | Should -Be (Resolve-Path -LiteralPath $path).Path
        }
    }

    It 'throws when selection file is missing' {
        InModuleScope WinTaskCrossingGuard {
            { Import-WtcgTaskSelection -Path (Join-Path $script:TempDir 'missing.json') } | Should -Throw
        }
    }

    It 'throws when selection JSON is invalid' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'bad.json'
            '{ this is not valid json' | Set-Content -Path $path -Encoding utf8

            { Import-WtcgTaskSelection -Path $path } | Should -Throw
        }
    }

    It 'throws when a task include has an empty taskName' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'bad-task.json'
            @{
                includeTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = ''
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            { Import-WtcgTaskSelection -Path $path } | Should -Throw
        }
    }

    It 'matches task specs by exact folder and wildcard task name' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Backup-01' }
            $spec = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Backup-*' })

            Test-WtcgTaskSpecMatch -Task $task -TaskSpec $spec | Should -BeTrue
        }
    }

    It 'does not match task specs when folder differs' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Other\'; TaskName = 'Backup-01' }
            $spec = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Backup-*' })

            Test-WtcgTaskSpecMatch -Task $task -TaskSpec $spec | Should -BeFalse
        }
    }

    It 'matches recursive folder selections against descendants' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\Nested\'; TaskName = 'T' }
            $folders = @([pscustomobject]@{ TaskPath = '\Root\'; Recurse = $true })

            Test-WtcgTaskFolderSelectionMatch -Task $task -FolderSelection $folders | Should -BeTrue
        }
    }

    It 'matches non-recursive folder selections only against exact folders' {
        InModuleScope WinTaskCrossingGuard {
            $exact = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'T' }
            $nested = [pscustomobject]@{ TaskPath = '\Root\Nested\'; TaskName = 'T' }
            $folders = @([pscustomobject]@{ TaskPath = '\Root\'; Recurse = $false })

            Test-WtcgTaskFolderSelectionMatch -Task $exact -FolderSelection $folders | Should -BeTrue
            Test-WtcgTaskFolderSelectionMatch -Task $nested -FolderSelection $folders | Should -BeFalse
        }
    }

    It 'allows all tasks when selection is null' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Anywhere\'; TaskName = 'T' }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $null | Should -BeTrue
        }
    }

    It 'excludes task when an exclude folder matches' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\Nested\'; TaskName = 'T' }
            $selection = [pscustomobject]@{
                IncludeFolders = @()
                IncludeTasks = @()
                ExcludeFolders = @([pscustomobject]@{ TaskPath = '\Root\'; Recurse = $true })
                ExcludeTasks = @()
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeFalse
        }
    }

    It 'excludes task when an exclude task spec matches' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Critical' }
            $selection = [pscustomobject]@{
                IncludeFolders = @()
                IncludeTasks = @()
                ExcludeFolders = @()
                ExcludeTasks = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Critical' })
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeFalse
        }
    }

    It 'allows task when include folder matches and no exclusion matches' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\Nested\'; TaskName = 'Included' }
            $selection = [pscustomobject]@{
                IncludeFolders = @([pscustomobject]@{ TaskPath = '\Root\'; Recurse = $true })
                IncludeTasks = @()
                ExcludeFolders = @()
                ExcludeTasks = @()
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeTrue
        }
    }

    It 'allows task when include task spec matches and no exclusion matches' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'DataExport-1' }
            $selection = [pscustomobject]@{
                IncludeFolders = @()
                IncludeTasks = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'DataExport-*' })
                ExcludeFolders = @()
                ExcludeTasks = @()
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeTrue
        }
    }

    It 'blocks task when includes exist but none match' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Nope' }
            $selection = [pscustomobject]@{
                IncludeFolders = @([pscustomobject]@{ TaskPath = '\Other\'; Recurse = $false })
                IncludeTasks = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Yes' })
                ExcludeFolders = @()
                ExcludeTasks = @()
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeFalse
        }
    }

    It 'allows task when only exclusions exist and none match' {
        InModuleScope WinTaskCrossingGuard {
            $task = [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Safe' }
            $selection = [pscustomobject]@{
                IncludeFolders = @()
                IncludeTasks = @()
                ExcludeFolders = @([pscustomobject]@{ TaskPath = '\Other\'; Recurse = $true })
                ExcludeTasks = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Danger' })
            }

            Test-WtcgTaskAllowedBySelection -Task $task -Selection $selection | Should -BeTrue
        }
    }
}

Describe 'WinTaskCrossingGuard scheduled task discovery with mocked ScheduledTasks module' {
    BeforeEach {
        InModuleScope WinTaskCrossingGuard {
            function Import-Module { }
            function Get-ScheduledTask { }
            function Get-ScheduledTaskInfo { }
            function Disable-ScheduledTask { }
            function Enable-ScheduledTask { }
            function Start-ScheduledTask { }
        }
    }

    It 'gets only exact-folder command-line candidates when Recurse is not used' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'One'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Two'; State = 'Disabled' }
                )
            } -ParameterFilter { $TaskPath -eq '\Root\' }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Root\' -TaskName '*')

            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'One'
            Should -Invoke Get-ScheduledTask -Times 1 -Exactly
        }
    }

    It 'includes disabled candidates when IncludeDisabled is used' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'One'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Two'; State = 'Disabled' }
                )
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Root\' -IncludeDisabled)

            $result.Count | Should -Be 2
        }
    }

    It 'uses command-line recurse by scanning all tasks and filtering paths' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'RootTask'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Root\Child\'; TaskName = 'ChildTask'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Other\'; TaskName = 'OtherTask'; State = 'Ready' }
                )
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Root\' -Recurse)

            $result.TaskName | Should -Contain 'RootTask'
            $result.TaskName | Should -Contain 'ChildTask'
            $result.TaskName | Should -Not -Contain 'OtherTask'
        }
    }

    It 'adds selection include folders with their own recurse settings' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                if ($PSBoundParameters.ContainsKey('TaskPath')) {
                    @(
                        [pscustomobject]@{ TaskPath = $TaskPath; TaskName = 'ExactTask'; State = 'Ready' }
                    )
                }
                else {
                    @(
                        [pscustomobject]@{ TaskPath = '\JsonRoot\'; TaskName = 'JsonRootTask'; State = 'Ready' }
                        [pscustomobject]@{ TaskPath = '\JsonRoot\Child\'; TaskName = 'JsonChildTask'; State = 'Ready' }
                        [pscustomobject]@{ TaskPath = '\Other\'; TaskName = 'OtherTask'; State = 'Ready' }
                    )
                }
            }

            $selection = [pscustomobject]@{
                IncludeFolders = @([pscustomobject]@{ TaskPath = '\JsonRoot\'; Recurse = $true })
                IncludeTasks = @()
                ExcludeFolders = @()
                ExcludeTasks = @()
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Nothing\' -Selection $selection)

            $result.TaskName | Should -Contain 'JsonRootTask'
            $result.TaskName | Should -Contain 'JsonChildTask'
            $result.TaskName | Should -Not -Contain 'OtherTask'
        }
    }

    It 'adds explicitly included tasks from selection and de-duplicates results' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                if ($PSBoundParameters.ContainsKey('TaskName')) {
                    @(
                        [pscustomobject]@{ TaskPath = $TaskPath; TaskName = 'Special'; State = 'Ready' }
                    )
                }
                else {
                    @(
                        [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Special'; State = 'Ready' }
                    )
                }
            }

            $selection = [pscustomobject]@{
                IncludeFolders = @()
                IncludeTasks = @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Special' })
                ExcludeFolders = @()
                ExcludeTasks = @()
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Root\' -Selection $selection)

            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'Special'
        }
    }

    It 'filters candidate names using TaskName wildcards' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Backup-1'; State = 'Ready' }
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Other-1'; State = 'Ready' }
                )
            }

            $result = @(Get-WtcgScheduledTaskCandidate -TaskPath '\Root\' -TaskName 'Backup-*')

            $result.Count | Should -Be 1
            $result[0].TaskName | Should -Be 'Backup-1'
        }
    }

    It 'finds in-window tasks and returns rich records by default' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @(
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'InWindow'; State = 'Ready'; Author = 'A'; Description = 'D' }
                    [pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'OutWindow'; State = 'Ready'; Author = 'A'; Description = 'D' }
                )
            }
            Mock Get-ScheduledTaskInfo {
                if ($TaskName -eq 'InWindow') {
                    [pscustomobject]@{
                        NextRunTime = [datetime]'2030-01-02T12:00:00'
                        LastRunTime = [datetime]'2030-01-01T01:00:00'
                        LastTaskResult = 0
                    }
                }
                else {
                    [pscustomobject]@{
                        NextRunTime = [datetime]'2030-01-02T20:00:00'
                        LastRunTime = [datetime]'2030-01-01T01:00:00'
                        LastTaskResult = 1
                    }
                }
            }

            $result = @(Find-WtcgTaskInWindow `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') `
                -TaskPath '\Root\')

            $result.Count | Should -Be 1
            $result[0].TaskPath | Should -Be '\Root\'
            $result[0].TaskName | Should -Be 'InWindow'
            $result[0].FullName | Should -Be '\Root\InWindow'
            $result[0].LastTaskResult | Should -Be 0
        }
    }

    It 'finds in-window tasks and returns identity-only records' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'InWindow'; State = 'Ready' })
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]::MinValue
                    LastTaskResult = 0
                }
            }

            $result = @(Find-WtcgTaskInWindow `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') `
                -TaskPath '\Root\' `
                -IdentityOnly)

            $result.Count | Should -Be 1
            $result[0].PSTypeNames[0] | Should -Be 'WinTaskCrossingGuard.TaskIdentity'
            $result[0].TaskName | Should -Be 'InWindow'
        }
    }

    It 'skips tasks with no upcoming run' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'NoRun'; State = 'Ready' })
            }
            Mock Get-ScheduledTaskInfo {
                [pscustomobject]@{
                    NextRunTime = [datetime]::MinValue
                    LastRunTime = [datetime]::MinValue
                    LastTaskResult = 0
                }
            }

            $result = @(Find-WtcgTaskInWindow `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') `
                -TaskPath '\Root\')

            $result.Count | Should -Be 0
        }
    }

    It 'warns and skips tasks whose info cannot be read' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Get-ScheduledTask {
                @([pscustomobject]@{ TaskPath = '\Root\'; TaskName = 'Broken'; State = 'Ready' })
            }
            Mock Get-ScheduledTaskInfo { throw 'boom' }
            Mock Write-Warning {}

            $result = @(Find-WtcgTaskInWindow `
                -Start ([datetime]'2030-01-02T08:00:00') `
                -End ([datetime]'2030-01-02T17:00:00') `
                -TaskPath '\Root\')

            $result.Count | Should -Be 0
            Should -Invoke Write-Warning -Times 1
        }
    }
}

Describe 'WinTaskCrossingGuard identity actions with mocked ScheduledTasks module' {
    BeforeEach {
        InModuleScope WinTaskCrossingGuard {
            function Import-Module { }
            function Disable-ScheduledTask { }
            function Enable-ScheduledTask { }
            function Start-ScheduledTask { }
        }
    }

    It 'disables task identities from the pipeline and returns identities' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Disable-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $result = @($identity | Disable-WtcgTaskIdentity)

            Should -Invoke Disable-ScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\Root\' -and $TaskName -eq 'T'
            }
            $result[0].FullName | Should -Be '\Root\T'
        }
    }

    It 'enables task identities from the pipeline and returns identities' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Enable-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $result = @($identity | Enable-WtcgTaskIdentity)

            Should -Invoke Enable-ScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\Root\' -and $TaskName -eq 'T'
            }
            $result[0].FullName | Should -Be '\Root\T'
        }
    }

    It 'starts task identities from the pipeline and returns identities' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Start-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $result = @($identity | Start-WtcgTaskIdentity)

            Should -Invoke Start-ScheduledTask -Times 1 -ParameterFilter {
                $TaskPath -eq '\Root\' -and $TaskName -eq 'T'
            }
            $result[0].FullName | Should -Be '\Root\T'
        }
    }

    It 'respects WhatIf for disable operations' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Disable-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $identity | Disable-WtcgTaskIdentity -WhatIf

            Should -Invoke Disable-ScheduledTask -Times 0
        }
    }

    It 'respects WhatIf for enable operations' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Enable-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $identity | Enable-WtcgTaskIdentity -WhatIf

            Should -Invoke Enable-ScheduledTask -Times 0
        }
    }

    It 'respects WhatIf for start operations' {
        InModuleScope WinTaskCrossingGuard {
            Mock Import-Module {}
            Mock Start-ScheduledTask {}

            $identity = New-WtcgTaskIdentity -TaskPath 'Root' -TaskName 'T'
            $identity | Start-WtcgTaskIdentity -WhatIf

            Should -Invoke Start-ScheduledTask -Times 0
        }
    }
}

Describe 'WinTaskCrossingGuard manifest output' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes a manifest with window and selection source information' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'manifest.json'
            $tasks = @(
                [pscustomobject]@{
                    TaskPath = 'Root'
                    TaskName = 'T'
                    State = 'Ready'
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                    Author = 'A'
                    Description = 'D'
                }
            )
            $selection = [pscustomobject]@{ SourcePath = 'C:\selection.json' }

            $file = $tasks | Save-WtcgManifest `
                -Path $path `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -Selection $selection

            $file.Exists | Should -BeTrue

            $payload = Get-Content -Path $path -Raw | ConvertFrom-Json
            $payload.SelectionSource | Should -Be 'C:\selection.json'
            @($payload.Tasks).Count | Should -Be 1
            $payload.Tasks[0].TaskPath | Should -Be '\Root\'
            $payload.Tasks[0].TaskName | Should -Be 'T'
            $payload.Tasks[0].FullName | Should -Be '\Root\T'
        }
    }

    It 'writes null selection source when no selection is provided' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'manifest.json'
            $tasks = @(
                [pscustomobject]@{
                    TaskPath = 'Root'
                    TaskName = 'T'
                    State = 'Ready'
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                    LastRunTime = [datetime]'2030-01-01T01:00:00'
                    LastTaskResult = 0
                    Author = 'A'
                    Description = 'D'
                }
            )

            $tasks | Save-WtcgManifest `
                -Path $path `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') |
                Out-Null

            $payload = Get-Content -Path $path -Raw | ConvertFrom-Json
            $payload.SelectionSource | Should -BeNullOrEmpty
        }
    }
}
