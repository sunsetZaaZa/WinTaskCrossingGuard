function Enable-WtcgTaskIdentity {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]] $TaskIdentity
    )

    begin {
        Import-Module ScheduledTasks -ErrorAction Stop
    }

    process {
        foreach ($identity in $TaskIdentity) {
            $taskPath = Normalize-WtcgTaskPath -TaskPath ([string]$identity.TaskPath)
            $taskName = [string]$identity.TaskName
            $fullName = "$taskPath$taskName"

            if ($PSCmdlet.ShouldProcess($fullName, 'Enable scheduled task')) {
                Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                New-WtcgTaskIdentity -TaskPath $taskPath -TaskName $taskName
            }
        }
    }
}
