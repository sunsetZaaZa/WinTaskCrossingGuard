#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe '.env log retention cleanup' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $script:LogsDir = Join-Path $script:TempDir 'logs'
        New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
        # WTCG module-scope test variable bridge
        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
            LogsDir = $script:LogsDir
            ProjectRoot = $script:ProjectRoot
        } {
            param($TempDir, $LogsDir, $ProjectRoot)
            $script:TempDir = $TempDir
            $script:LogsDir = $LogsDir
            $script:ProjectRoot = $ProjectRoot
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports KEY=VALUE pairs from a .env file and ignores comments/blanks' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'

            @'
# comment
LOG_RETENTION=14

OTHER_VALUE="hello world"
'@ | Set-Content -Path $envPath -Encoding utf8

            $values = Import-WtcgDotEnv -Path $envPath

            $values['LOG_RETENTION'] | Should -Be '14'
            $values['OTHER_VALUE'] | Should -Be 'hello world'
        }
    }

    It 'returns null when LOG_RETENTION is not configured' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'OTHER_VALUE=abc' | Set-Content -Path $envPath -Encoding utf8

            Get-WtcgLogRetentionDays -EnvPath $envPath | Should -BeNullOrEmpty
        }
    }

    It 'throws when LOG_RETENTION is not a whole number' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'LOG_RETENTION=abc' | Set-Content -Path $envPath -Encoding utf8

            { Get-WtcgLogRetentionDays -EnvPath $envPath } | Should -Throw -ExpectedMessage '*Invalid LOG_RETENTION value*'
        }
    }

    It 'throws when LOG_RETENTION is negative' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'LOG_RETENTION=-1' | Set-Content -Path $envPath -Encoding utf8

            { Get-WtcgLogRetentionDays -EnvPath $envPath } | Should -Throw -ExpectedMessage '*Value must be zero or greater*'
        }
    }

    It 'deletes XML logs older than LOG_RETENTION days and keeps newer XML logs' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            'LOG_RETENTION=7' | Set-Content -Path $envPath -Encoding utf8

            $now = [datetime]'2030-01-10T12:00:00'

            $oldLog = Join-Path $script:LogsDir 'old.xml'
            $newLog = Join-Path $script:LogsDir 'new.xml'
            $nonXml = Join-Path $script:LogsDir 'old.txt'

            '<old />' | Set-Content -Path $oldLog -Encoding utf8
            '<new />' | Set-Content -Path $newLog -Encoding utf8
            'old text' | Set-Content -Path $nonXml -Encoding utf8

            (Get-Item $oldLog).LastWriteTime = $now.AddDays(-8)
            (Get-Item $newLog).LastWriteTime = $now.AddDays(-6)
            (Get-Item $nonXml).LastWriteTime = $now.AddDays(-30)

            $deleted = @(Clear-WtcgOldLogs `
                -EnvPath $envPath `
                -LogsPath $script:LogsDir `
                -Now $now `
                -PassThru)

            Test-Path -LiteralPath $oldLog | Should -BeFalse
            Test-Path -LiteralPath $newLog | Should -BeTrue
            Test-Path -LiteralPath $nonXml | Should -BeTrue

            $deleted.Count | Should -Be 1
            $deleted[0].RetentionDays | Should -Be 7
        }
    }

    It 'skips cleanup when .env file is missing' {
        InModuleScope WinTaskCrossingGuard {
            $oldLog = Join-Path $script:LogsDir 'old.xml'
            '<old />' | Set-Content -Path $oldLog -Encoding utf8
            (Get-Item $oldLog).LastWriteTime = ([datetime]'2030-01-01T00:00:00')

            Clear-WtcgOldLogs `
                -EnvPath (Join-Path $script:TempDir 'missing.env') `
                -LogsPath $script:LogsDir `
                -Now ([datetime]'2030-01-10T12:00:00')

            Test-Path -LiteralPath $oldLog | Should -BeTrue
        }
    }
}
