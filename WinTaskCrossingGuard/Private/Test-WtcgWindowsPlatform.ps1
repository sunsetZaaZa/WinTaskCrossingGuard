function Test-WtcgWindowsPlatform {
    [CmdletBinding()]
    param()

    if ($null -ne $PSVersionTable -and $PSVersionTable.ContainsKey('Platform')) {
        return ([string]$PSVersionTable.Platform -eq 'Win32NT')
    }

    return ([string]$env:OS -eq 'Windows_NT')
}
