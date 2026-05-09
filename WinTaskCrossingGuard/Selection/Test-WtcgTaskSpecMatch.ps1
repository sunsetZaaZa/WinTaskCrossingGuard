function Test-WtcgTaskSpecMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [object[]] $TaskSpec
    )

    foreach ($spec in $TaskSpec) {
        if ($Task.TaskPath -eq $spec.TaskPath -and $Task.TaskName -like $spec.TaskName) {
            return $true
        }
    }

    return $false
}
