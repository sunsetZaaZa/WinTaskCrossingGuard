function Get-WtcgRestoreArtifactSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $nameLooksRestorable = $file.Name -match '(?i)(manifest|identit)'

    try {
        $payload = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "Skipping non-JSON or unreadable restore artifact candidate '$($file.FullName)': $($_.Exception.Message)"
        return $null
    }

    $kind = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Kind')
    $kindLooksRestorable = $kind -match '(?i)(manifest|identity)'

    if (-not ($nameLooksRestorable -or $kindLooksRestorable)) {
        return $null
    }

    $tasks = Get-WtcgObjectPropertyValue -InputObject $payload -Name 'Tasks'
    if ($null -eq $tasks) {
        return $null
    }

    $taskArray = @($tasks)
    if ($taskArray.Count -eq 0) {
        return $null
    }

    $restorableTaskCount = 0
    foreach ($task in $taskArray) {
        if ($null -ne $task -and (Test-WtcgRestoreArtifactTaskRestorable -Task $task)) {
            $restorableTaskCount++
        }
    }

    $createdAt = ConvertTo-WtcgNullableDateTime -Value (Get-WtcgObjectPropertyValue -InputObject $payload -Name 'CreatedAt')
    $runFolderPath = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'RunFolderPath')
    if ([string]::IsNullOrWhiteSpace($runFolderPath)) {
        $parent = Split-Path -Parent $file.FullName
        if (-not [string]::IsNullOrWhiteSpace($parent) -and @('manifests', 'identities') -contains (Split-Path -Leaf $parent)) {
            $runFolderPath = Split-Path -Parent $parent
        }
    }

    $runId = [string](Get-WtcgObjectPropertyValue -InputObject $payload -Name 'RunId')
    if ([string]::IsNullOrWhiteSpace($runId) -and -not [string]::IsNullOrWhiteSpace($runFolderPath)) {
        $runId = Split-Path -Leaf $runFolderPath
    }

    [pscustomobject]@{
        PSTypeName          = 'WinTaskCrossingGuard.RestoreArtifactSummary'
        Path                = $file.FullName
        Name                = $file.Name
        Kind                = $kind
        CreatedAt           = $createdAt
        LastWriteTime       = $file.LastWriteTime
        LastWriteTimeUtc    = $file.LastWriteTimeUtc
        RunId               = $runId
        RunFolderPath       = $runFolderPath
        TaskCount           = $taskArray.Count
        RestorableTaskCount = $restorableTaskCount
    }
}
