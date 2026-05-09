function ConvertTo-WtcgMailEventSettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Mail
    )

    $disabled = ConvertTo-WtcgMailSettings -Mail $null

    if ($null -eq $Mail) {
        return [pscustomobject]@{
            Result = $disabled
            Error  = $disabled
        }
    }

    $entries = @($Mail)

    # A single entry is shared by both events.
    if ($entries.Count -eq 1) {
        $shared = ConvertTo-WtcgMailSettings -Mail $entries[0]

        return [pscustomobject]@{
            Result = $shared
            Error  = $shared
        }
    }

    Assert-WtcgMailEventSettings -Mail $entries

    $result = $disabled
    $errorReport = $disabled

    foreach ($entry in $entries) {
        $event = ([string](Get-WtcgObjectPropertyValue -InputObject $entry -Name 'event')).Trim().ToLowerInvariant()
        $settings = ConvertTo-WtcgMailSettings -Mail $entry

        switch ($event) {
            'result' {
                $result = $settings
                break
            }

            'error' {
                $errorReport = $settings
                break
            }
        }
    }

    [pscustomobject]@{
        Result = $result
        Error  = $errorReport
    }
}
