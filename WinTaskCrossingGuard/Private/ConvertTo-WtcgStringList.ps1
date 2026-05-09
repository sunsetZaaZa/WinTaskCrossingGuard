function ConvertTo-WtcgStringList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [string[]] $Default = @()
    )

    if ($null -eq $Value) { return @($Default) }

    if ($Value -is [array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return @($Default) }

    @($text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
