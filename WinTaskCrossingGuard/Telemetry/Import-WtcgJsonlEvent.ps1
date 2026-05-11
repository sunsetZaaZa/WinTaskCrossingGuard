function Import-WtcgJsonlEvent {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSONL event file not found: $Path"
    }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Invalid JSONL event at line $lineNumber in '$Path': $($_.Exception.Message)"
        }
    }
}
