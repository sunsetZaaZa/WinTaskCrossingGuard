function Invoke-WtcgTelemetryRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter()]
        [ValidateSet('Post', 'Put', 'Patch')]
        [string] $Method = 'Post',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Body,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ContentType = 'application/json; charset=utf-8',

        [Parameter()]
        [AllowNull()]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int] $TimeoutSeconds = 15,

        [Parameter()]
        [switch] $AllowInsecureTls
    )

    $invokeParameters = @{
        Uri        = $Uri
        Method     = $Method
        ContentType = $ContentType
        Body       = $Body
        TimeoutSec = $TimeoutSeconds
    }

    if ($null -ne $Headers -and $Headers.Count -gt 0) {
        $invokeParameters.Headers = $Headers
    }

    if ($AllowInsecureTls -and $PSVersionTable.PSVersion.Major -ge 7) {
        $invokeParameters.SkipCertificateCheck = $true
    }

    Invoke-RestMethod @invokeParameters
}
