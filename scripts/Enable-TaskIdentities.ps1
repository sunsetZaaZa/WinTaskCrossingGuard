[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string] $IdentityPath,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $JsonlLogPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $EventLogSource = 'WinTaskCrossingGuard',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $EventLogName = 'Application',

    [Parameter()]
    [switch] $DisableEventLog,

    [Parameter()]
    [switch] $FailOnEventLogError,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string] $RunId,

    [Parameter()]
    [string] $Operation = 'EnableTaskIdentities',

    [Parameter(ValueFromPipeline)]
    [object[]] $TaskIdentity
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot '..\WinTaskCrossingGuard\WinTaskCrossingGuard.psd1') -Force

    $buffer = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($IdentityPath)) {
        foreach ($identity in @(Import-WtcgTaskIdentity -Path $IdentityPath)) {
            $buffer.Add($identity)
        }
    }
}

process {
    foreach ($identity in $TaskIdentity) {
        $buffer.Add($identity)
    }
}

end {
    if ($buffer.Count -eq 0) {
        throw "No task identities were provided. Use -IdentityPath or pipe objects with TaskPath and TaskName."
    }

    $enabled = @($buffer | Enable-WtcgTaskIdentity -WhatIf:$WhatIfPreference -Confirm:$false)

    if ($enabled.Count -gt 0) {
        $enabled |
            Write-WtcgReenableJsonlLog `
                -Path $JsonlLogPath `
                -IdentityPath $IdentityPath `
                -RunId $RunId `
                -Operation $Operation |
            Out-Null
    }
    Write-WtcgAuditEvent `
        -Action 're-enable' `
        -Operation $Operation `
        -Status 'succeeded' `
        -EventId 4200 `
        -EntryType 'Information' `
        -Details ([ordered]@{
            identityPath = $IdentityPath
            candidateTaskCount = $buffer.Count
            enabledTaskCount = $enabled.Count
            jsonlLogPath = $JsonlLogPath
        }) `
        -RunId $RunId `
        -EventLogSource $EventLogSource `
        -EventLogName $EventLogName `
        -DisableEventLog:$DisableEventLog `
        -FailOnEventLogError:$FailOnEventLogError |
        Out-Null


    $enabled
}
