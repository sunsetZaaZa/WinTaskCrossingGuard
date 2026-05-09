function Write-WtcgNotificationJsonlLog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard notification',

        [Parameter()]
        [ValidateSet('attempted', 'sent', 'failed', 'skipped')]
        [string] $Status = 'sent',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Channel = 'email',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Subject,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $To,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Cc,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SmtpServer,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ErrorMessage,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $RunFolderPath
    )

    $details = [ordered]@{
        channel            = $Channel
        subject            = $Subject
        to                 = @($To | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        cc                 = @($Cc | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        smtpServer         = $SmtpServer
        xmlLogPath         = $XmlLogPath
        identityOutputPath = $IdentityOutputPath
        errorMessage       = $ErrorMessage
    }

    New-WtcgJsonlEvent `
        -Action 'notification' `
        -Operation $Operation `
        -Status $Status `
        -RunId $RunId `
        -RunFolderPath $RunFolderPath `
        -Details $details |
        Write-WtcgJsonlEvent -Path $Path
}
