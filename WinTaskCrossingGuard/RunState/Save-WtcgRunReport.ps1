function Save-WtcgRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $RunContext,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Operation = 'WinTaskCrossingGuard operation',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Status,

        [Parameter()]
        [AllowNull()]
        [object] $Details
    )

    $resolvedPath = if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $Path
    }
    else {
        $safeOperationName = ConvertTo-WtcgSafePathName -Value $Operation.ToLowerInvariant()
        Resolve-WtcgRunArtifactPath -RunContext $RunContext -Kind 'Reports' -FileName "$safeOperationName-report.json"
    }

    $directory = Split-Path -Parent $resolvedPath
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    }

    [pscustomobject]@{
        Kind          = 'WinTaskCrossingGuard.RunReport'
        Version       = 1
        RunId         = $RunContext.RunId
        RunFolderPath = $RunContext.RunFolderPath
        Operation     = $Operation
        Status        = $Status
        CreatedAt     = (Get-Date).ToString('o')
        Details       = if ($null -ne $Details) { $Details } else { [ordered]@{} }
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedPath -Encoding utf8 -WhatIf:$false

    Get-Item -LiteralPath $resolvedPath
}
