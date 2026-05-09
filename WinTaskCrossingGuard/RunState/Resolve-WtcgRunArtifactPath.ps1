function Resolve-WtcgRunArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $RunContext,

        [Parameter(Mandatory)]
        [ValidateSet('Logs', 'JsonlLogs', 'Manifests', 'Identities', 'Reports', 'Errors')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FileName
    )

    $folder = switch ($Kind) {
        'Logs'       { $RunContext.LogsPath }
        'JsonlLogs'  { $RunContext.JsonlLogsPath }
        'Manifests'  { $RunContext.ManifestsPath }
        'Identities' { $RunContext.IdentitiesPath }
        'Reports'    { $RunContext.ReportsPath }
        'Errors'     { $RunContext.ErrorsPath }
    }

    if ([string]::IsNullOrWhiteSpace([string]$folder)) {
        throw "Run context does not contain a folder for artifact kind '$Kind'."
    }

    New-Item -ItemType Directory -Path $folder -Force -WhatIf:$false | Out-Null
    return (Join-Path $folder $FileName)
}
