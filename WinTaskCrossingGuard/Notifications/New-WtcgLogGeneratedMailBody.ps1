function New-WtcgLogGeneratedMailBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $XmlLogPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $IdentityOutputPath,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard log generated',

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

    @"
WinTaskCrossingGuard generated an XML log.

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

XML log path:
  $XmlLogPath

Identity output path:
  $IdentityOutputPath
"@
}
