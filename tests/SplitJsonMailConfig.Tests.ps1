#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force

}

Describe 'Strict split JSON mail configuration' {
    It 'directly accepts one result and one error event through Assert-WtcgMailEventSettings' {
        InModuleScope WinTaskCrossingGuard {
            $mail = @(
                [pscustomobject]@{
                    event = 'result'
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops@example.com')
                },
                [pscustomobject]@{
                    event = 'error'
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops-alerts@example.com')
                }
            )

            { Assert-WtcgMailEventSettings -Mail $mail } | Should -Not -Throw
        }
    }

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

    It 'uses one mail entry for both result and error notifications' {
        InModuleScope WinTaskCrossingGuard {
            $settings = ConvertTo-WtcgMailEventSettings -Mail ([pscustomobject]@{
                enabled = $true
                smtpServer = 'mail.internal.example.com'
                from = 'wintaskcrossingguard@example.com'
                to = @('ops@example.com')
                attachXmlLog = $true
                attachIdentityFile = $true
            })

            $settings.Result.To | Should -Contain 'ops@example.com'
            $settings.Error.To | Should -Contain 'ops@example.com'
        }
    }

    It 'uses separate result and error entries when event values are provided' {
        InModuleScope WinTaskCrossingGuard {
            $settings = ConvertTo-WtcgMailEventSettings -Mail @(
                [pscustomobject]@{
                    event = 'result'
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops@example.com')
                },
                [pscustomobject]@{
                    event = 'error'
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops-alerts@example.com')
                }
            )

            $settings.Result.To | Should -Contain 'ops@example.com'
            $settings.Error.To | Should -Contain 'ops-alerts@example.com'
        }
    }

    It 'throws when two mail entries are provided and one is missing event' {
        InModuleScope WinTaskCrossingGuard {
            {
                ConvertTo-WtcgMailEventSettings -Mail @(
                    [pscustomobject]@{
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops@example.com')
                    },
                    [pscustomobject]@{
                        event = 'error'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops-alerts@example.com')
                    }
                )
            } | Should -Throw -ExpectedMessage '*each entry must include an event attribute*'
        }
    }

    It 'throws when two mail entries do not contain exactly one result and one error event' {
        InModuleScope WinTaskCrossingGuard {
            {
                ConvertTo-WtcgMailEventSettings -Mail @(
                    [pscustomobject]@{
                        event = 'result'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops@example.com')
                    },
                    [pscustomobject]@{
                        event = 'result'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops2@example.com')
                    }
                )
            } | Should -Throw -ExpectedMessage '*exactly one must use event=''result'' and exactly one must use event=''error''*'
        }
    }

    It 'imports split mail settings from SelectionPath JSON when events are valid' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'

            @{
                mail = @(
                    @{
                        event = 'result'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops@example.com')
                    },
                    @{
                        event = 'error'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops-alerts@example.com')
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $selection = Import-WtcgTaskSelection -Path $path

            (Get-WtcgResultMailSettings -Selection $selection).To | Should -Contain 'ops@example.com'
            (Get-WtcgErrorMailSettings -Selection $selection).To | Should -Contain 'ops-alerts@example.com'
        }
    }

    It 'imports fallback error mail settings for configuration errors' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'

            @{
                mail = @(
                    @{
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops@example.com')
                    },
                    @{
                        event = 'error'
                        enabled = $true
                        smtpServer = 'mail.internal.example.com'
                        from = 'wintaskcrossingguard@example.com'
                        to = @('ops-alerts@example.com')
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $settings = Get-WtcgMailSettingsForConfigurationError -SelectionPath $path

            $settings.To | Should -Contain 'ops-alerts@example.com'
        }
    }
}
