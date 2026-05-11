function New-WtcgTaskIdentity {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TaskPath,

        [Parameter(Mandatory)]
        [string] $TaskName,

        [Parameter()]
        [AllowNull()]
        [object] $NextRunTime,

        [Parameter()]
        [AllowNull()]
        [string] $State,

        [Parameter()]
        [AllowNull()]
        [string] $OriginalState,

        [Parameter()]
        [AllowNull()]
        [bool] $WasOriginallyEnabled = $true,

        [Parameter()]
        [AllowNull()]
        [bool] $DisabledBySuite = $false,

        [Parameter()]
        [AllowNull()]
        [object] $DisabledAt,

        [Parameter()]
        [AllowNull()]
        [object] $LastRunTime,

        [Parameter()]
        [AllowNull()]
        [object] $LastTaskResult,

        [Parameter()]
        [AllowNull()]
        [string] $Author,

        [Parameter()]
        [AllowNull()]
        [string] $Description
    )

    $normalizedPath = Normalize-WtcgTaskPath -TaskPath $TaskPath
    $effectiveOriginalState = if ([string]::IsNullOrWhiteSpace($OriginalState)) { $State } else { $OriginalState }
    $effectiveWasOriginallyEnabled = if ([string]::IsNullOrWhiteSpace($effectiveOriginalState)) { $WasOriginallyEnabled } else { $effectiveOriginalState -ne 'Disabled' }

    [pscustomObject]@{
        PSTypeName              = 'WinTaskCrossingGuard.TaskIdentity'
        TaskPath                = $normalizedPath
        TaskName                = $TaskName
        FullName                = "$normalizedPath$TaskName"
        NextRunTime             = $NextRunTime
        State                   = $State
        OriginalState           = $effectiveOriginalState
        WasOriginallyEnabled    = [bool]$effectiveWasOriginallyEnabled
        DisabledBySuite         = [bool]$DisabledBySuite
        DisabledAt              = $DisabledAt
        LastRunTime             = $LastRunTime
        LastTaskResult          = $LastTaskResult
        Author                  = $Author
        Description             = $Description

    }
}
