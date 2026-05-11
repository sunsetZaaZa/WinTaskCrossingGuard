function Import-WtcgReenableManifestSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper is called by orchestration commands that own WhatIf/Confirm behavior or builds non-destructive in-memory output.')]
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $summary = [ordered]@{
        ManifestPath    = $Path
        ManifestExists  = $false
        ManifestKind    = $null
        RunId           = $null
        RunFolderPath   = $null
        CreatedAt       = $null
        WindowStart     = $null
        WindowEnd       = $null
        TaskFullNames   = @()
        ReadError       = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$summary
    }

    $summary.ManifestExists = $true

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $summary.ManifestKind = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'Kind'
        $summary.RunId = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'RunId'
        $summary.RunFolderPath = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'RunFolderPath'
        $summary.CreatedAt = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'CreatedAt')
        $summary.WindowStart = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'WindowStart')
        $summary.WindowEnd = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'WindowEnd')

        $tasks = Get-WtcgObjectPropertyValue -InputObject $manifest -Name 'Tasks'
        $taskFullNames = [System.Collections.Generic.List[string]]::new()
        foreach ($task in @($tasks)) {
            $taskFullName = Get-WtcgObjectPropertyValue -InputObject $task -Name 'FullName'
            if (-not [string]::IsNullOrWhiteSpace([string]$taskFullName)) {
                $taskFullNames.Add([string]$taskFullName)
            }
        }
        $summary.TaskFullNames = @($taskFullNames)
    }
    catch {
        $summary.ReadError = $_.Exception.Message
    }

    [pscustomobject]$summary
}
