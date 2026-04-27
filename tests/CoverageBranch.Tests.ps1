#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'WinTaskCrossingGuard coverage branch tests' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

        InModuleScope WinTaskCrossingGuard -Parameters @{
            TempDir = $script:TempDir
        } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns the default object property value when the input object is null' {
        InModuleScope WinTaskCrossingGuard {
            Get-WtcgObjectPropertyValue -InputObject $null -Name 'Anything' -DefaultValue 'fallback' |
                Should -Be 'fallback'
        }
    }

    It 'returns false when checking explicit includes against null selection' {
        InModuleScope WinTaskCrossingGuard {
            Test-WtcgSelectionHasExplicitIncludes -Selection $null | Should -BeFalse
        }
    }

    It 'throws when protectedTasks has an empty taskName' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'protected-empty-name.json'

            @{
                protectedTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = ''
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            { Import-WtcgTaskSelection -Path $path } |
                Should -Throw -ExpectedMessage '*Every protectedTasks entry must have a non-empty taskName*'
        }
    }

    It 'throws when .env contains a malformed line without equals' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir '.env'
            'LOG_RETENTION' | Set-Content -Path $path -Encoding utf8

            { Import-WtcgDotEnv -Path $path } |
                Should -Throw -ExpectedMessage '*Expected KEY=VALUE*'
        }
    }

    It 'throws when .env contains an empty key' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir '.env'
            '=30' | Set-Content -Path $path -Encoding utf8

            { Import-WtcgDotEnv -Path $path } |
                Should -Throw -ExpectedMessage '*Key cannot be empty*'
        }
    }

    It 'skips log cleanup when logs folder is missing' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            $missingLogs = Join-Path $script:TempDir 'missing-logs'
            'LOG_RETENTION=1' | Set-Content -Path $envPath -Encoding utf8

            { Clear-WtcgOldLogs -EnvPath $envPath -LogsPath $missingLogs -Verbose } |
                Should -Not -Throw
        }
    }

    It 'returns disabled mail settings for missing configuration-error selection path' {
        InModuleScope WinTaskCrossingGuard {
            $settings = Get-WtcgMailSettingsForConfigurationError -SelectionPath (Join-Path $script:TempDir 'missing.json')

            $settings.Enabled | Should -BeFalse
        }
    }

    It 'returns disabled mail settings when configuration-error JSON has no mail block' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'
            @{ includeTasks = @() } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $settings = Get-WtcgMailSettingsForConfigurationError -SelectionPath $path

            $settings.Enabled | Should -BeFalse
        }
    }

    It 'uses a single mail entry for configuration-error fallback' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'

            @{
                mail = @{
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops@example.com')
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $settings = Get-WtcgMailSettingsForConfigurationError -SelectionPath $path

            $settings.Enabled | Should -BeTrue
            $settings.To | Should -Contain 'ops@example.com'
        }
    }

    It 'throws when more than two mail event entries are supplied' {
        InModuleScope WinTaskCrossingGuard {
            {
                Assert-WtcgMailEventSettings -Mail @(
                    [pscustomobject]@{ event = 'result' },
                    [pscustomobject]@{ event = 'error' },
                    [pscustomobject]@{ event = 'error' }
                )
            } | Should -Throw -ExpectedMessage '*supports either one shared entry or two entries*'
        }
    }

    It 'throws when an unsupported mail event value is supplied' {
        InModuleScope WinTaskCrossingGuard {
            {
                Assert-WtcgMailEventSettings -Mail @(
                    [pscustomobject]@{ event = 'result' },
                    [pscustomobject]@{ event = 'banana' }
                )
            } | Should -Throw -ExpectedMessage '*unsupported mail event*'
        }
    }

    It 'returns the plain Mail object when result and error wrappers are absent' {
        InModuleScope WinTaskCrossingGuard {
            $mail = [pscustomobject]@{
                Enabled = $true
                SmtpServer = 'mail.internal.example.com'
                From = 'wintaskcrossingguard@example.com'
                To = @('ops@example.com')
            }

            $selection = [pscustomobject]@{
                Mail = $mail
            }

            Get-WtcgResultMailSettings -Selection $selection | Should -Be $mail
            Get-WtcgErrorMailSettings -Selection $selection | Should -Be $mail
        }
    }

    It 'returns false for null mail settings readiness' {
        InModuleScope WinTaskCrossingGuard {
            Test-WtcgMailSettingsReady -MailSettings $null | Should -BeFalse
        }
    }

    It 'returns an empty attachment list when no attachments are enabled' {
        InModuleScope WinTaskCrossingGuard {
            $settings = [pscustomobject]@{
                AttachXmlLog = $false
                AttachIdentityFile = $false
            }

            @(Get-WtcgMailAttachments -MailSettings $settings -XmlLogPath $null -IdentityOutputPath $null).Count |
                Should -Be 0
        }
    }

    It 'throws from direct mail sender when there are no recipients' {
        InModuleScope WinTaskCrossingGuard {
            {
                Send-WtcgMailNotification `
                    -SmtpServer 'mail.internal.example.com' `
                    -From 'wintaskcrossingguard@example.com' `
                    -To @() `
                    -Subject 'Pester' `
                    -Body 'Body'
            } | Should -Throw -ExpectedMessage '*At least one email recipient*'
        }
    }

    It 'throws from direct mail sender when an attachment is missing' {
        InModuleScope WinTaskCrossingGuard {
            {
                Send-WtcgMailNotification `
                    -SmtpServer 'mail.internal.example.com' `
                    -From 'wintaskcrossingguard@example.com' `
                    -To @('ops@example.com') `
                    -Cc @('audit@example.com') `
                    -Subject 'Pester' `
                    -Body 'Body' `
                    -AttachmentPath (Join-Path $script:TempDir 'missing.xml')
            } | Should -Throw -ExpectedMessage '*Attachment not found*'
        }
    }

    It 'builds an error XML log when the error record is plain text-like' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'plain-error.xml'

            $file = Write-WtcgErrorXmlLog `
                -ErrorRecord ([pscustomobject]@{
                    Exception = $null
                    FullyQualifiedErrorId = 'PlainText'
                    InvocationInfo = $null
                }) `
                -Path $path `
                -Operation 'PlainTextError'

            $file.Exists | Should -BeTrue
        }
    }
}
