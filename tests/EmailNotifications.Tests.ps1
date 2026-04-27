#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'WinTaskCrossingGuard email body helpers' {
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

    It 'builds a log-generated email body that references the XML log' {
        InModuleScope WinTaskCrossingGuard {
            $body = New-WtcgLogGeneratedMailBody `
                -XmlLogPath 'C:\logs\disabled.xml' `
                -IdentityOutputPath 'C:\ids.json' `
                -Operation 'PesterLog'

            $body | Should -Match 'WinTaskCrossingGuard generated an XML log'
            $body | Should -Match 'PesterLog'
            $body | Should -Match 'C:\\logs\\disabled.xml'
            $body | Should -Match 'C:\\ids.json'
        }
    }

    It 'builds an error email body that references the XML log and error message' {
        InModuleScope WinTaskCrossingGuard {
            try {
                throw 'pester boom'
            }
            catch {
                $body = New-WtcgErrorMailBody `
                    -ErrorRecord $_ `
                    -Operation 'PesterError' `
                    -XmlLogPath 'C:\logs\disabled.xml' `
                    -IdentityOutputPath 'C:\ids.json'
            }

            $body | Should -Match 'WinTaskCrossingGuard encountered an error'
            $body | Should -Match 'PesterError'
            $body | Should -Match 'pester boom'
            $body | Should -Match 'C:\\logs\\disabled.xml'
        }
    }

    It 'log-generated notification attempts to attach the XML log when requested' {
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

            $log = Join-Path $script:TempDir 'log.xml'
            '<root />' | Set-Content -Path $log -Encoding utf8

            Mock Send-WtcgMailNotification { [pscustomobject]@{ Sent = $true } }

            Send-WtcgLogGeneratedNotification `
                -SmtpServer 'mail.intranet.local' `
                -From 'wtcg@example.com' `
                -To 'ops@example.com' `
                -XmlLogPath $log `
                -IdentityOutputPath 'C:\ids.json' `
                -AttachXmlLog |
                Out-Null

            Should -Invoke Send-WtcgMailNotification -Times 1 -ParameterFilter {
                $SmtpServer -eq 'mail.intranet.local' -and
                $From -eq 'wtcg@example.com' -and
                $To -contains 'ops@example.com' -and
                $AttachmentPath -contains $log
            }
        }
    }

    It 'error notification attempts to attach the XML log when requested' {
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

            $log = Join-Path $script:TempDir 'log.xml'
            '<root />' | Set-Content -Path $log -Encoding utf8

            Mock Send-WtcgMailNotification { [pscustomobject]@{ Sent = $true } }

            try {
                throw 'pester boom'
            }
            catch {
                Send-WtcgErrorNotification `
                    -ErrorRecord $_ `
                    -SmtpServer 'mail.intranet.local' `
                    -From 'wtcg@example.com' `
                    -To 'ops@example.com' `
                    -XmlLogPath $log `
                    -AttachXmlLog |
                    Out-Null
            }

            Should -Invoke Send-WtcgMailNotification -Times 1 -ParameterFilter {
                $SmtpServer -eq 'mail.intranet.local' -and
                $From -eq 'wtcg@example.com' -and
                $To -contains 'ops@example.com' -and
                $AttachmentPath -contains $log
            }
        }
    }

    It 'notification helpers warn instead of throwing when email send fails by default' {
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
            Mock Send-WtcgMailNotification { throw 'smtp down' }
            Mock Write-Warning {}

            Send-WtcgLogGeneratedNotification `
                -SmtpServer 'mail.intranet.local' `
                -From 'wtcg@example.com' `
                -To 'ops@example.com' `
                -XmlLogPath 'missing.xml'

            Should -Invoke Write-Warning -Times 1
        }
    }

    It 'notification helpers can fail the operation when FailOnEmailError is set' {
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
            Mock Send-WtcgMailNotification { throw 'smtp down' }

            {
                Send-WtcgLogGeneratedNotification `
                    -SmtpServer 'mail.intranet.local' `
                    -From 'wtcg@example.com' `
                    -To 'ops@example.com' `
                    -XmlLogPath 'missing.xml' `
                    -FailOnEmailError
            } | Should -Throw
        }
    }
}
