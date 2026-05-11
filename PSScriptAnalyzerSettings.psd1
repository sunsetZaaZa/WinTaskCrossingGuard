@{
    Severity = @(
        'Error'
        'Warning'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @(
                '7.0'
            )
        }

        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
        }
    }
}
