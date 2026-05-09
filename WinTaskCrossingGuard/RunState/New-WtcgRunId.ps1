function New-WtcgRunId {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Prefix = 'wtcg'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return "$Prefix-$timestamp-$suffix"
}
