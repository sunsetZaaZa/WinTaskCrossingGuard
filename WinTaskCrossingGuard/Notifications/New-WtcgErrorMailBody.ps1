function New-WtcgErrorMailBody {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $ErrorRecord,

        [Parameter()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $XmlLogPath,

        [Parameter()]
        [string] $LogEmailSmtpServer,

        [Parameter()]
        [int] $LogEmailSmtpPort = 25,

        [Parameter()]
        [string] $LogEmailFrom,

        [Parameter()]
        [string[]] $LogEmailTo,

        [Parameter()]
        [string[]] $LogEmailCc,

        [Parameter()]
        [string] $LogEmailSubject = 'WinTaskCrossingGuard XML log generated',

        [Parameter()]
        [switch] $LogEmailUseSsl,

        [Parameter()]
        [pscredential] $LogEmailCredential,

        [Parameter()]
        [switch] $FailOnLogEmailError,

        [Parameter()]
        [string] $ErrorEmailSmtpServer,

        [Parameter()]
        [int] $ErrorEmailSmtpPort = 25,

        [Parameter()]
        [string] $ErrorEmailFrom,

        [Parameter()]
        [string[]] $ErrorEmailTo,

        [Parameter()]
        [string[]] $ErrorEmailCc,

        [Parameter()]
        [string] $ErrorEmailSubject = 'WinTaskCrossingGuard error',

        [Parameter()]
        [switch] $ErrorEmailUseSsl,

        [Parameter()]
        [pscredential] $ErrorEmailCredential,

        [Parameter()]
        [switch] $FailOnErrorEmail,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

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
        [string] $HostName = $env:COMPUTERNAME
    )

    $exception = $ErrorRecord.Exception
    $message = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
    $errorType = if ($null -ne $exception) { $exception.GetType().FullName } else { $null }

    @"
WinTaskCrossingGuard encountered an error.

Operation:
  $Operation

Host:
  $HostName

Timestamp:
  $(Get-Date -Format 'o')

Run ID:
  $RunId

Run folder:
  $RunFolderPath

Error:
  $message

Error type:
  $errorType

Script position:
$($ErrorRecord.InvocationInfo.PositionMessage)

XML log path:
  $XmlLogPath

Identity output path:
  $IdentityOutputPath

Fully qualified error id:
  $($ErrorRecord.FullyQualifiedErrorId)
"@
}
