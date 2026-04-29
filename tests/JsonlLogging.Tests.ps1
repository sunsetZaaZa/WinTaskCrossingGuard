#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'SIEM-friendly JSONL logging' {
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

    It 'resolves an empty JSONL log path to the steamablelogs folder' {
        InModuleScope WinTaskCrossingGuard {
            $result = Resolve-WtcgJsonlLogPath -Path '' -BaseDirectory $script:TempDir

            Split-Path -Parent $result | Should -Be (Join-Path $script:TempDir 'steamablelogs')
            Split-Path -Leaf $result | Should -Match '^wintaskcrossingguard-events-\d{8}-\d{6}\.jsonl$'
            $result | Should -Not -Match '\\logs\\'
        }
    }

    It 'writes disable actions as newline-delimited JSON events' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'disable.jsonl'
            $tasks = @(
                [pscustomobject]@{
                    TaskPath = 'Root'
                    TaskName = 'TaskA'
                    State = 'Ready'
                    OriginalState = 'Ready'
                    WasOriginallyEnabled = $true
                    DisabledBySuite = $true
                    DisabledAt = [datetime]'2030-01-02T08:30:00'
                    NextRunTime = [datetime]'2030-01-02T12:00:00'
                },
                [pscustomobject]@{
                    TaskPath = '\Root\Nested\'
                    TaskName = 'TaskB'
                    State = 'Queued'
                    OriginalState = 'Queued'
                    WasOriginallyEnabled = $true
                    DisabledBySuite = $true
                    DisabledAt = [datetime]'2030-01-02T08:31:00'
                    NextRunTime = [datetime]'2030-01-02T13:00:00'
                }
            )

            $file = $tasks | Write-WtcgDisableJsonlLog `
                -Path $path `
                -WindowStart ([datetime]'2030-01-02T08:00:00') `
                -WindowEnd ([datetime]'2030-01-02T17:00:00') `
                -ReenableAt ([datetime]'2030-01-02T18:00:00') `
                -SelectionSource 'C:\selection.json' `
                -IdentityOutputPath 'C:\manifest.json' `
                -ReenableTaskFullName '\WinTaskCrossingGuard\ReenableDisabledTasks' `
                -Operation 'PesterDisable'

            $file.Exists | Should -BeTrue
            $lines = @(Get-Content -Path $path)
            $lines.Count | Should -Be 2

            $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
            $events[0].schemaVersion | Should -Be '1.0'
            $events[0].source | Should -Be 'WinTaskCrossingGuard'
            $events[0].action | Should -Be 'disable'
            $events[0].status | Should -Be 'succeeded'
            $events[0].operation | Should -Be 'PesterDisable'
            $events[0].details.taskPath | Should -Be '\Root\'
            $events[0].details.taskName | Should -Be 'TaskA'
            $events[0].details.fullName | Should -Be '\Root\TaskA'
            $events[0].details.identityOutputPath | Should -Be 'C:\manifest.json'
            $events[1].details.fullName | Should -Be '\Root\Nested\TaskB'
        }
    }

    It 'writes re-enable actions as JSONL events' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'reenable.jsonl'
            $task = [pscustomobject]@{
                TaskPath = '\Root\'
                TaskName = 'TaskA'
            }

            $file = $task | Write-WtcgReenableJsonlLog `
                -Path $path `
                -ManifestPath 'C:\manifest.json' `
                -Operation 'PesterReenable'

            $file.Exists | Should -BeTrue
            $event = Get-Content -Path $path -Raw | ConvertFrom-Json

            $event.action | Should -Be 're-enable'
            $event.status | Should -Be 'succeeded'
            $event.operation | Should -Be 'PesterReenable'
            $event.details.fullName | Should -Be '\Root\TaskA'
            $event.details.manifestPath | Should -Be 'C:\manifest.json'
        }
    }

    It 'writes error actions as JSONL events' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'error.jsonl'

            try {
                throw 'pester jsonl boom'
            }
            catch {
                $file = Write-WtcgErrorJsonlLog `
                    -ErrorRecord $_ `
                    -Path $path `
                    -Operation 'PesterError' `
                    -SelectionSource 'C:\selection.json' `
                    -IdentityOutputPath 'C:\manifest.json'
            }

            $file.Exists | Should -BeTrue
            $event = Get-Content -Path $path -Raw | ConvertFrom-Json

            $event.action | Should -Be 'error'
            $event.status | Should -Be 'failed'
            $event.operation | Should -Be 'PesterError'
            $event.details.message | Should -Match 'pester jsonl boom'
            $event.details.selectionSource | Should -Be 'C:\selection.json'
        }
    }

    It 'writes notification actions as JSONL events' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'notification.jsonl'

            $file = Write-WtcgNotificationJsonlLog `
                -Path $path `
                -Operation 'PesterNotify' `
                -Status 'sent' `
                -Subject 'Log generated' `
                -To @('ops@example.com') `
                -Cc @('audit@example.com') `
                -SmtpServer 'mail.example.com' `
                -XmlLogPath 'C:\logs\disabled.xml' `
                -IdentityOutputPath 'C:\manifest.json'

            $file.Exists | Should -BeTrue
            $event = Get-Content -Path $path -Raw | ConvertFrom-Json

            $event.action | Should -Be 'notification'
            $event.status | Should -Be 'sent'
            $event.operation | Should -Be 'PesterNotify'
            $event.details.channel | Should -Be 'email'
            $event.details.to | Should -Contain 'ops@example.com'
            $event.details.smtpServer | Should -Be 'mail.example.com'
        }
    }

    It 'cleans up old JSONL files when requested with a JSONL filter' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            $jsonlDir = Join-Path $script:TempDir 'steamablelogs'
            New-Item -ItemType Directory -Path $jsonlDir -Force | Out-Null
            'LOG_RETENTION=7' | Set-Content -Path $envPath -Encoding utf8

            $now = [datetime]'2030-01-10T12:00:00'
            $oldJsonl = Join-Path $jsonlDir 'old.jsonl'
            $newJsonl = Join-Path $jsonlDir 'new.jsonl'
            $oldXml = Join-Path $jsonlDir 'old.xml'

            '{}' | Set-Content -Path $oldJsonl -Encoding utf8
            '{}' | Set-Content -Path $newJsonl -Encoding utf8
            '<old />' | Set-Content -Path $oldXml -Encoding utf8

            (Get-Item $oldJsonl).LastWriteTime = $now.AddDays(-8)
            (Get-Item $newJsonl).LastWriteTime = $now.AddDays(-6)
            (Get-Item $oldXml).LastWriteTime = $now.AddDays(-30)

            $deleted = @(Clear-WtcgOldLogs `
                -EnvPath $envPath `
                -LogsPath $jsonlDir `
                -Filter '*.jsonl' `
                -Now $now `
                -PassThru)

            Test-Path -LiteralPath $oldJsonl | Should -BeFalse
            Test-Path -LiteralPath $newJsonl | Should -BeTrue
            Test-Path -LiteralPath $oldXml | Should -BeTrue
            $deleted.Count | Should -Be 1
        }
    }
}
