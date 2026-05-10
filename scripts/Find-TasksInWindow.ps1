[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Start,

    [Parameter(Mandatory)]
    [string] $End,

    [Parameter()]
    [string[]] $TaskPath = '\',

    [Parameter()]
    [string[]] $TaskName = '*',

    [Parameter()]
    [string] $SelectionPath,

    [Parameter()]
    [switch] $Recurse,

    [Parameter()]
    [switch] $IncludeDisabled,

    [Parameter()]
    [string] $IdentityOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\Load-WinTaskCrossingGuardInternal.ps1')

$window = Resolve-WtcgWindow -Start $Start -End $End

$selection = $null
if (-not [string]::IsNullOrWhiteSpace($SelectionPath)) {
    $selection = Import-WtcgTaskSelection -Path $SelectionPath
}

$taskIdentities = @(
    Find-WtcgTaskInWindow `
        -Start $window.Start `
        -End $window.End `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Recurse:$Recurse `
        -IncludeDisabled:$IncludeDisabled `
        -Selection $selection `
        -IdentityOnly
)

if (-not [string]::IsNullOrWhiteSpace($IdentityOutputPath)) {
    $taskIdentities |
        Export-WtcgTaskIdentity -Path $IdentityOutputPath -Kind 'WinTaskCrossingGuard.MatchedWindowTasks' |
        Out-Null
}

$taskIdentities
