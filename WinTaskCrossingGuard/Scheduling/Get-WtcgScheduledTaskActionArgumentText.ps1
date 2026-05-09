function Get-WtcgScheduledTaskActionArgumentText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object] $Task
    )

    process {
        if ($null -eq $Task) {
            return
        }

        $actions = Get-WtcgObjectPropertyValue -InputObject $Task -Name 'Actions'
        if ($null -eq $actions) {
            return
        }

        foreach ($action in @($actions)) {
            if ($null -eq $action) {
                continue
            }

            $argumentText = Get-WtcgObjectPropertyValue -InputObject $action -Name 'Arguments'
            if ([string]::IsNullOrWhiteSpace([string]$argumentText)) {
                $argumentText = Get-WtcgObjectPropertyValue -InputObject $action -Name 'Argument'
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$argumentText)) {
                [string]$argumentText
            }
        }
    }
}
