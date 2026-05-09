function Send-WtcgWebhookNotificationsFromEnv {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('result', 'error', 'notification')]
        [string] $NotificationEvent = 'notification',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Subject = 'WinTaskCrossingGuard notification',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $JsonlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorMessage
    )

    $settings = Get-WtcgWebhookSettings -EnvPath $EnvPath
    $results = [System.Collections.Generic.List[object]]::new()
    $targets = @($settings.Targets | Where-Object { Test-WtcgWebhookTargetReady -Target $_ -NotificationEvent $NotificationEvent })

    if ($targets.Count -eq 0) { return @() }

    $text = New-WtcgWebhookNotificationText -Subject $Subject -Operation $Operation -Status $Status -RunId $RunId -RunFolderPath $RunFolderPath -XmlLogPath $XmlLogPath -JsonlLogPath $JsonlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $ErrorMessage

    foreach ($target in $targets) {
        $provider = [string]$target.Provider
        try {
            $sendResult = Send-WtcgWebhookNotification -Target $target -Text $text
            $results.Add($sendResult)

            try {
                Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'sent' -Channel "webhook:$provider" -Subject $Subject -To @($provider) -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null
            }
            catch { Write-Verbose "Failed to write WinTaskCrossingGuard webhook notification JSONL event: $($_.Exception.Message)" }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $failure = [pscustomobject]@{ Sent = $false; Provider = $provider; Url = $target.Url; Error = $errorMessage }
            $results.Add($failure)

            try {
                Write-WtcgNotificationJsonlLog -Path $JsonlLogPath -Operation $Operation -Status 'failed' -Channel "webhook:$provider" -Subject $Subject -To @($provider) -XmlLogPath $XmlLogPath -IdentityOutputPath $IdentityOutputPath -ErrorMessage $errorMessage -RunId $RunId -RunFolderPath $RunFolderPath | Out-Null
            }
            catch { Write-Verbose "Failed to write WinTaskCrossingGuard webhook notification JSONL event: $($_.Exception.Message)" }

            Write-Warning "Failed to send WinTaskCrossingGuard $provider webhook notification: $errorMessage"
            if ([bool]$target.FailOnError -or [bool]$settings.FailOnError) { throw }
        }
    }

    @($results)
}
