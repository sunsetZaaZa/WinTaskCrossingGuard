#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Windows Event Log audit integration' {
    It 'formats audit events for the WinTaskCrossingGuard source' {
        InModuleScope WinTaskCrossingGuard {
            Mock Write-WtcgWindowsEventLog {
                [pscustomobject]@{
                    Source = $Source
                    LogName = $LogName
                    EventId = $EventId
                    EntryType = $EntryType
                    Message = $Message
                    Written = $true
                    Skipped = $false
                    Error = $null
                }
            }

            $result = Write-WtcgAuditEvent `
                -Action 'disable' `
                -Operation 'PesterDisable' `
                -Status 'succeeded' `
                -EventId 4100 `
                -EntryType 'Information' `
                -Details ([ordered]@{ disabledTaskCount = 2 })

            $result.Source | Should -Be 'WinTaskCrossingGuard'
            $result.LogName | Should -Be 'Application'
            $result.EventId | Should -Be 4100
            $result.EntryType | Should -Be 'Information'

            $payload = $result.Message | ConvertFrom-Json
            $payload.product | Should -Be 'WinTaskCrossingGuard'
            $payload.eventSource | Should -Be 'WinTaskCrossingGuard'
            $payload.action | Should -Be 'disable'
            $payload.operation | Should -Be 'PesterDisable'
            $payload.status | Should -Be 'succeeded'
            $payload.details.disabledTaskCount | Should -Be 2

            Should -Invoke Write-WtcgWindowsEventLog -Times 1 -ParameterFilter {
                $Source -eq 'WinTaskCrossingGuard' -and
                $LogName -eq 'Application' -and
                $EventId -eq 4100 -and
                $EntryType -eq 'Information'
            }
        }
    }

    It 'can be disabled without calling the native event writer' {
        InModuleScope WinTaskCrossingGuard {
            Mock Write-WtcgWindowsEventLog {}

            $result = Write-WtcgAuditEvent `
                -Action 'error' `
                -Operation 'PesterError' `
                -Status 'failed' `
                -EventId 5100 `
                -EntryType 'Error' `
                -DisableEventLog

            $result.Source | Should -Be 'WinTaskCrossingGuard'
            $result.Written | Should -BeFalse
            $result.Skipped | Should -BeTrue
            $result.Error | Should -Match 'disabled'

            Should -Invoke Write-WtcgWindowsEventLog -Times 0
        }
    }

    It 'skips source creation on non-Windows platforms' {
        InModuleScope WinTaskCrossingGuard {
            Mock Test-WtcgWindowsPlatform { $false }

            $result = Initialize-WtcgWindowsEventLogSource `
                -Source 'WinTaskCrossingGuard' `
                -LogName 'Application'

            $result.Source | Should -Be 'WinTaskCrossingGuard'
            $result.LogName | Should -Be 'Application'
            $result.IsWindows | Should -BeFalse
            $result.SourceExists | Should -BeFalse
            $result.Created | Should -BeFalse
            $result.Skipped | Should -BeTrue
        }
    }
}
