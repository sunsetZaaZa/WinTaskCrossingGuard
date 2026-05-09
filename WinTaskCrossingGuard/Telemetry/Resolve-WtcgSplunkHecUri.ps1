function Resolve-WtcgSplunkHecUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri
    )

    try {
        $builder = [System.UriBuilder]::new($Uri.Trim())
        $builder.Query = $null
        $path = $builder.Path.TrimEnd('/')
        if ($path -notmatch '/services/collector(?:/event)?$') {
            $path = "$path/services/collector"
        }
        $builder.Path = $path
        $builder.Uri.AbsoluteUri
    }
    catch {
        $trimmed = $Uri.Trim().TrimEnd('/')
        if ($trimmed -match '/services/collector(?:/event)?$') { return $trimmed }
        "$trimmed/services/collector"
    }
}
