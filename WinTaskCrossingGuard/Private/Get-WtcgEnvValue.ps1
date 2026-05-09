function Get-WtcgEnvValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Values,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $Default = $null
    )

    if ($Values.ContainsKey($Name)) { return $Values[$Name] }
    return $Default
}
