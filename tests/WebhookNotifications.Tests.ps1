#requires -Version 7.0
#requires -Modules Pester

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'WinTaskCrossingGuard\WinTaskCrossingGuard.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Webhook and ChatOps notifications' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        InModuleScope WinTaskCrossingGuard -Parameters @{ TempDir = $script:TempDir } {
            param($TempDir)
            $script:TempDir = $TempDir
        }
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'imports Teams, Slack, and Discord webhook settings from .env' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_WEBHOOKS_ENABLED=true
WTCG_WEBHOOK_TIMEOUT_SECONDS=21
WTCG_WEBHOOK_TEAMS_ENABLED=true
WTCG_WEBHOOK_TEAMS_URL=https://teams.example/webhook
WTCG_WEBHOOK_TEAMS_EVENTS=result,error
WTCG_WEBHOOK_SLACK_ENABLED=true
WTCG_WEBHOOK_SLACK_URL=https://hooks.slack.example/services/T000/B000/XXX
WTCG_WEBHOOK_SLACK_EVENTS=error
WTCG_WEBHOOK_DISCORD_ENABLED=true
WTCG_WEBHOOK_DISCORD_URL=https://discord.example/api/webhooks/1/token
WTCG_WEBHOOK_DISCORD_EVENTS=result
'@ | Set-Content -Path $envPath -Encoding utf8

            $settings = Get-WtcgWebhookSettings -EnvPath $envPath

            $settings.Enabled | Should -BeTrue
            $settings.TimeoutSeconds | Should -Be 21
            $settings.Targets.Count | Should -Be 3

            $teams = $settings.Targets | Where-Object Provider -eq 'teams'
            $slack = $settings.Targets | Where-Object Provider -eq 'slack'
            $discord = $settings.Targets | Where-Object Provider -eq 'discord'

            $teams.Enabled | Should -BeTrue
            $teams.Url | Should -Be 'https://teams.example/webhook'
            $teams.Events | Should -Contain 'result'
            $teams.Events | Should -Contain 'error'

            $slack.Enabled | Should -BeTrue
            $slack.Events | Should -Contain 'error'
            $slack.Events | Should -Not -Contain 'result'

            $discord.Enabled | Should -BeTrue
            $discord.Events | Should -Contain 'result'
        }
    }

    It 'builds provider-specific payload shapes' {
        InModuleScope WinTaskCrossingGuard {
            $teams = New-WtcgWebhookPayload -Provider teams -Text 'hello teams'
            $slack = New-WtcgWebhookPayload -Provider slack -Text 'hello slack'
            $discord = New-WtcgWebhookPayload -Provider discord -Text 'hello discord'

            $teams.text | Should -Be 'hello teams'
            $teams.summary | Should -Be 'WinTaskCrossingGuard notification'
            $slack.text | Should -Be 'hello slack'
            $discord.content | Should -Be 'hello discord'
        }
    }

    It 'sends enabled result webhooks and writes JSONL notification audit events' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
            $jsonlPath = Join-Path $script:TempDir 'events.jsonl'
@'
WTCG_WEBHOOKS_ENABLED=true
WTCG_WEBHOOK_TEAMS_ENABLED=true
WTCG_WEBHOOK_TEAMS_URL=https://teams.example/webhook
WTCG_WEBHOOK_TEAMS_EVENTS=result
WTCG_WEBHOOK_SLACK_ENABLED=true
WTCG_WEBHOOK_SLACK_URL=https://slack.example/webhook
WTCG_WEBHOOK_SLACK_EVENTS=error
WTCG_WEBHOOK_DISCORD_ENABLED=true
WTCG_WEBHOOK_DISCORD_URL=https://discord.example/webhook
WTCG_WEBHOOK_DISCORD_EVENTS=result
'@ | Set-Content -Path $envPath -Encoding utf8

            Mock Invoke-WtcgWebhookRestMethod {
                [pscustomobject]@{ ok = $true; uri = $Uri; body = $Body }
            }

            $results = @(Send-WtcgWebhookNotificationsFromEnv `
                -EnvPath $envPath `
                -NotificationEvent result `
                -Subject 'Run completed' `
                -Operation 'PesterOperation' `
                -Status 'succeeded' `
                -RunId 'wtcg-pester' `
                -RunFolderPath 'C:\runs\wtcg-pester' `
                -JsonlLogPath $jsonlPath)

            $results.Count | Should -Be 2
            $results.Provider | Should -Contain 'teams'
            $results.Provider | Should -Contain 'discord'
            $results.Provider | Should -Not -Contain 'slack'

            Should -Invoke Invoke-WtcgWebhookRestMethod -Times 2

            $events = @(Get-Content -Path $jsonlPath | ForEach-Object { $_ | ConvertFrom-Json })
            $events.Count | Should -Be 2
            $events.action | Should -Contain 'notification'
            $events.details.channel | Should -Contain 'webhook:teams'
            $events.details.channel | Should -Contain 'webhook:discord'
            $events.runId | Should -Contain 'wtcg-pester'
        }
    }

    It 'does not throw on webhook failure unless fail-on-error is enabled' {
        InModuleScope WinTaskCrossingGuard {
            $envPath = Join-Path $script:TempDir '.env'
@'
WTCG_WEBHOOKS_ENABLED=true
WTCG_WEBHOOK_SLACK_ENABLED=true
WTCG_WEBHOOK_SLACK_URL=https://slack.example/webhook
WTCG_WEBHOOK_SLACK_EVENTS=error
WTCG_WEBHOOK_SLACK_FAIL_ON_ERROR=false
'@ | Set-Content -Path $envPath -Encoding utf8

            Mock Invoke-WtcgWebhookRestMethod { throw 'chatops down' }

            { Send-WtcgWebhookNotificationsFromEnv -EnvPath $envPath -NotificationEvent error -Subject 'Failed' -Operation 'Pester' -Status failed } |
                Should -Not -Throw
        }
    }
}
