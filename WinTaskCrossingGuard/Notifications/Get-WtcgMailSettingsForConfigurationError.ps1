function Get-WtcgMailSettingsForConfigurationError {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SelectionPath
    )

    if ([string]::IsNullOrWhiteSpace($SelectionPath) -or -not (Test-Path -LiteralPath $SelectionPath)) {
        return ConvertTo-WtcgMailSettings -Mail $null
    }

    try {
        $json = Get-Content -LiteralPath $SelectionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        $jsonMail = Get-WtcgObjectPropertyValue -InputObject $json -Name 'mail'

        if ($null -eq $jsonMail) {
            return ConvertTo-WtcgMailSettings -Mail $null
        }

        $entries = @($jsonMail)

        if ($entries.Count -eq 1) {
            return ConvertTo-WtcgMailSettings -Mail $entries[0]
        }

        $errorEntry = $entries | Where-Object {
            $entryEvent = Get-WtcgObjectPropertyValue -InputObject $_ -Name 'event'
            $null -ne $entryEvent -and ([string]$entryEvent).Trim().ToLowerInvariant() -eq 'error'
        } | Select-Object -First 1

        if ($null -ne $errorEntry) {
            return ConvertTo-WtcgMailSettings -Mail $errorEntry
        }

        return ConvertTo-WtcgMailSettings -Mail $entries[0]
    }
    catch {
        return ConvertTo-WtcgMailSettings -Mail $null
    }
}
