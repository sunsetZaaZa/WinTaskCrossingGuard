#requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [version] $RequiredVersion = '5.0.0',

    [Parameter()]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string] $Scope = 'CurrentUser',

    [Parameter()]
    [switch] $Force,

    [Parameter()]
    [switch] $AllowClobber,

    [Parameter()]
    [switch] $SkipPublisherCheck,

    [Parameter()]
    [string] $Repository = 'PSGallery',

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectPesterInstallation {
    [CmdletBinding()]
    param()

    $available = @(Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending)

    if ($available.Count -eq 0) {
        return $null
    }

    return $available[0]
}

function Install-ProjectPester {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [version] $RequiredVersion,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $AllowClobber,

        [Parameter()]
        [switch] $SkipPublisherCheck
    )

    $installParams = @{
        Name = 'Pester'
        MinimumVersion = $RequiredVersion.ToString()
        Scope = $Scope
        Repository = $Repository
        ErrorAction = 'Stop'
    }

    if ($Force) {
        $installParams.Force = $true
    }

    if ($AllowClobber) {
        $installParams.AllowClobber = $true
    }

    if ($SkipPublisherCheck) {
        $installParams.SkipPublisherCheck = $true
    }

    if ($PSCmdlet.ShouldProcess("Pester >= $RequiredVersion", "Install from $Repository into $Scope scope")) {
        Install-Module @installParams
    }
}

function Update-ProjectPester {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [version] $RequiredVersion,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter()]
        [switch] $Force,

        [Parameter()]
        [switch] $AllowClobber,

        [Parameter()]
        [switch] $SkipPublisherCheck
    )

    # Install-Module with MinimumVersion is more reliable than Update-Module when
    # the existing module came bundled with Windows PowerShell or was installed
    # under a different scope.
    Install-ProjectPester `
        -RequiredVersion $RequiredVersion `
        -Scope $Scope `
        -Repository $Repository `
        -Force:$Force `
        -AllowClobber:$AllowClobber `
        -SkipPublisherCheck:$SkipPublisherCheck `
        -WhatIf:$WhatIfPreference
}

Write-Host "Required Pester version: >= $RequiredVersion"

$current = Get-ProjectPesterInstallation

if ($null -eq $current) {
    Write-Host "Pester is not installed."

    Install-ProjectPester `
        -RequiredVersion $RequiredVersion `
        -Scope $Scope `
        -Repository $Repository `
        -Force:$Force `
        -AllowClobber:$AllowClobber `
        -SkipPublisherCheck:$SkipPublisherCheck `
        -WhatIf:$WhatIfPreference
}
elseif ([version]$current.Version -lt $RequiredVersion) {
    Write-Host "Installed Pester version $($current.Version) is below required version $RequiredVersion."

    Update-ProjectPester `
        -RequiredVersion $RequiredVersion `
        -Scope $Scope `
        -Repository $Repository `
        -Force:$Force `
        -AllowClobber:$AllowClobber `
        -SkipPublisherCheck:$SkipPublisherCheck `
        -WhatIf:$WhatIfPreference
}
else {
    Write-Host "Installed Pester version $($current.Version) satisfies the project requirement."
}

$after = Get-ProjectPesterInstallation

if ($null -eq $after -and -not $WhatIfPreference) {
    throw "Pester was not found after installation attempt."
}

if ($null -ne $after -and [version]$after.Version -lt $RequiredVersion -and -not $WhatIfPreference) {
    throw "Pester version $($after.Version) is still below required version $RequiredVersion after installation/update attempt."
}

if ($null -ne $after) {
    Write-Host "Using Pester $($after.Version) from: $($after.ModuleBase)"
}

if ($PassThru) {
    [pscustomobject]@{
        RequiredVersion = $RequiredVersion
        InstalledVersion = if ($null -ne $after) { [version]$after.Version } else { $null }
        ModuleBase = if ($null -ne $after) { $after.ModuleBase } else { $null }
        Satisfied = ($null -ne $after -and [version]$after.Version -ge $RequiredVersion)
    }
}
