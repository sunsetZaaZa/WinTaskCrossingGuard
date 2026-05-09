function Resolve-WtcgElasticBulkUri {
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
        if ($path -notmatch '/_bulk$') {
            $path = "$path/_bulk"
        }
        $builder.Path = $path
        return $builder.Uri.AbsoluteUri
    }
    catch {
        $trimmed = $Uri.Trim().TrimEnd('/')
        if ($trimmed -match '/_bulk$') {
            return $trimmed
        }
        return "$trimmed/_bulk"
    }
}
