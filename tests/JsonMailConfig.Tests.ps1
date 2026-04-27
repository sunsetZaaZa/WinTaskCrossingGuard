#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'JSON mail configuration' {
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

    It 'imports mail settings from SelectionPath JSON' {
        InModuleScope WinTaskCrossingGuard {
            $path = Join-Path $script:TempDir 'selection.json'

            @{
                includeTasks = @(
                    @{
                        taskPath = '\Root\'
                        taskName = 'TaskA'
                    }
                )
                mail = @{
                    enabled = $true
                    smtpServer = 'mail.internal.example.com'
                    port = 25
                    from = 'wintaskcrossingguard@example.com'
                    to = @('ops@example.com')
                    cc = @('audit@example.com')
                    useSsl = $false
                    attachXmlLog = $true
                    attachIdentityFile = $true
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8

            $selection = Import-WtcgTaskSelection -Path $path

            $mail = Get-WtcgResultMailSettings -Selection $selection

            $mail.Enabled | Should -BeTrue
            $mail.SmtpServer | Should -Be 'mail.internal.example.com'
            $mail.Port | Should -Be 25
            $mail.From | Should -Be 'wintaskcrossingguard@example.com'
            $mail.To | Should -Contain 'ops@example.com'
            $mail.Cc | Should -Contain 'audit@example.com'
            $mail.UseSsl | Should -BeFalse
            $mail.AttachXmlLog | Should -BeTrue
            $mail.AttachIdentityFile | Should -BeTrue
            Test-WtcgMailSettingsReady -MailSettings $mail | Should -BeTrue
        }
    }

    It 'treats missing mail settings as disabled' {
        InModuleScope WinTaskCrossingGuard {
            $settings = ConvertTo-WtcgMailSettings -Mail $null

            $settings.Enabled | Should -BeFalse
            Test-WtcgMailSettingsReady -MailSettings $settings | Should -BeFalse
        }
    }

    It 'builds attachment list from JSON mail settings for XML log and identity file' {
        InModuleScope WinTaskCrossingGuard {
            $xml = Join-Path $script:TempDir 'log.xml'
            $ids = Join-Path $script:TempDir 'ids.json'
            '<root />' | Set-Content -Path $xml -Encoding utf8
            '{}' | Set-Content -Path $ids -Encoding utf8

            $settings = ConvertTo-WtcgMailSettings -Mail ([pscustomobject]@{
                enabled = $true
                smtpServer = 'mail.internal.example.com'
                from = 'wintaskcrossingguard@example.com'
                to = @('ops@example.com')
                attachXmlLog = $true
                attachIdentityFile = $true
            })

            $attachments = @(Get-WtcgMailAttachments `
                -MailSettings $settings `
                -XmlLogPath $xml `
                -IdentityOutputPath $ids)

            $attachments | Should -Contain $xml
            $attachments | Should -Contain $ids
        }
    }

    It 'does not attach identity file when attachIdentityFile is false' {
        InModuleScope WinTaskCrossingGuard {
            $xml = Join-Path $script:TempDir 'log.xml'
            $ids = Join-Path $script:TempDir 'ids.json'
            '<root />' | Set-Content -Path $xml -Encoding utf8
            '{}' | Set-Content -Path $ids -Encoding utf8

            $settings = ConvertTo-WtcgMailSettings -Mail ([pscustomobject]@{
                enabled = $true
                smtpServer = 'mail.internal.example.com'
                from = 'wintaskcrossingguard@example.com'
                to = @('ops@example.com')
                attachXmlLog = $true
                attachIdentityFile = $false
            })

            $attachments = @(Get-WtcgMailAttachments `
                -MailSettings $settings `
                -XmlLogPath $xml `
                -IdentityOutputPath $ids)

            $attachments | Should -Contain $xml
            $attachments | Should -Not -Contain $ids
        }
    }

    It 'dispatches log-generated notification from JSON settings with configured attachments' {
        InModuleScope WinTaskCrossingGuard {
            function Send-WtcgMailNotification {
                param(
                    [string] $SmtpServer,
                    [int] $Port,
                    [string] $From,
                    [string[]] $To,
                    [string[]] $Cc,
                    [string] $Subject,
                    [string] $Body,
                    [string[]] $AttachmentPath,
                    [switch] $UseSsl,
                    [pscredential] $Credential
                )
            }

            $xml = Join-Path $script:TempDir 'log.xml'
            $ids = Join-Path $script:TempDir 'ids.json'
            '<root />' | Set-Content -Path $xml -Encoding utf8
            '{}' | Set-Content -Path $ids -Encoding utf8

            $settings = ConvertTo-WtcgMailSettings -Mail ([pscustomobject]@{
                enabled = $true
                smtpServer = 'mail.internal.example.com'
                port = 25
                from = 'wintaskcrossingguard@example.com'
                to = @('ops@example.com')
                cc = @('audit@example.com')
                attachXmlLog = $true
                attachIdentityFile = $true
            })

            Mock Send-WtcgMailNotification {
                [pscustomobject]@{ Sent = $true }
            }

            Send-WtcgLogGeneratedNotificationFromSettings `
                -MailSettings $settings `
                -XmlLogPath $xml `
                -IdentityOutputPath $ids `
                -Operation 'PesterLog' |
                Out-Null

            Should -Invoke Send-WtcgMailNotification -Times 1 -ParameterFilter {
                $SmtpServer -eq 'mail.internal.example.com' -and
                $From -eq 'wintaskcrossingguard@example.com' -and
                $To -contains 'ops@example.com' -and
                $Cc -contains 'audit@example.com' -and
                $AttachmentPath -contains $xml -and
                $AttachmentPath -contains $ids
            }
        }
    }

    It 'dispatches error notification from JSON settings with configured attachments' {
        InModuleScope WinTaskCrossingGuard {
            function Send-WtcgMailNotification {
                param(
                    [string] $SmtpServer,
                    [int] $Port,
                    [string] $From,
                    [string[]] $To,
                    [string[]] $Cc,
                    [string] $Subject,
                    [string] $Body,
                    [string[]] $AttachmentPath,
                    [switch] $UseSsl,
                    [pscredential] $Credential
                )
            }

            $xml = Join-Path $script:TempDir 'log.xml'
            $ids = Join-Path $script:TempDir 'ids.json'
            '<root />' | Set-Content -Path $xml -Encoding utf8
            '{}' | Set-Content -Path $ids -Encoding utf8

            $settings = ConvertTo-WtcgMailSettings -Mail ([pscustomobject]@{
                enabled = $true
                smtpServer = 'mail.internal.example.com'
                from = 'wintaskcrossingguard@example.com'
                to = @('ops@example.com')
                attachXmlLog = $true
                attachIdentityFile = $true
            })

            Mock Send-WtcgMailNotification {
                [pscustomobject]@{ Sent = $true }
            }

            try {
                throw 'json mail error test'
            }
            catch {
                Send-WtcgErrorNotificationFromSettings `
                    -MailSettings $settings `
                    -ErrorRecord $_ `
                    -XmlLogPath $xml `
                    -IdentityOutputPath $ids |
                    Out-Null
            }

            Should -Invoke Send-WtcgMailNotification -Times 1 -ParameterFilter {
                $AttachmentPath -contains $xml -and
                $AttachmentPath -contains $ids
            }
        }
    }
}
