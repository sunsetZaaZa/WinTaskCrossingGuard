function New-WtcgWebhookPayload {
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
