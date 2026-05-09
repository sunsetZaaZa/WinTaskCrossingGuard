function Disable-WtcgTaskIdentity {
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

            $wasOriginallyEnabled = [bool](Get-WtcgObjectPropertyValue -InputObject $identity -Name 'WasOriginallyEnabled' -DefaultValue $true)
            if (-not $wasOriginallyEnabled) {
                Write-Verbose "Skipping originally disabled task: $fullName"
                continue
            }

            if ($PSCmdlet.ShouldProcess($fullName, 'Disable scheduled task')) {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
                New-WtcgTaskIdentity `
                    -TaskPath $taskPath `
                    -TaskName $taskName `
                    -NextRunTime (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'NextRunTime') `
                    -State (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'State') `
                    -OriginalState (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'OriginalState') `
                    -WasOriginallyEnabled $true `
                    -DisabledBySuite $true `
                    -DisabledAt (Get-Date) `
                    -LastRunTime (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastRunTime') `
                    -LastTaskResult (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'LastTaskResult' -DefaultValue 0) `
                    -Author (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Author') `
                    -Description (Get-WtcgObjectPropertyValue -InputObject $identity -Name 'Description')
            }
        }
    }
}
