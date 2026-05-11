function New-WtcgWebhookPayload {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('teams', 'slack', 'discord')]
        [string] $Provider,

        [Parameter(Mandatory)]
        [string] $Text
    )

    switch ($Provider) {
        'teams' {
            [ordered]@{
                '@type'    = 'MessageCard'
                '@context' = 'https://schema.org/extensions'
                summary    = 'WinTaskCrossingGuard notification'
                text       = $Text
            }
        }
        'slack' { [ordered]@{ text = $Text } }
        'discord' { [ordered]@{ content = $Text } }
    }
}
