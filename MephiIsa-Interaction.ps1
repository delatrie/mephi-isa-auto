. "$PSScriptRoot\core.ps1"

Function Select-Item
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            ValueFromPipeline = $True
        )]
        [System.Object[]] $InputObject,

        [Parameter(
            Position = 0
        )]
        [System.Object[]] $Property
    )

    Begin
    {
        $Collection = [System.Collections.ArrayList]::new()
        $TableArguments = @{}
        If ($PSBoundParameters.ContainsKey('Property'))
        {
            $TableArguments['Property'] = @('_Index') + @($Property)
        }
    }

    Process
    {
        ForEach ($Item in $InputObject)
        {
            $Collection.Add($Item) | Out-Null
        }
    }

    End
    {
        If ($Collection.Count -gt 0)
        {
            $TableFile = [System.IO.Path]::GetTempFileName()
            Try
            {
                0..($Collection.Count - 1) | ForEach-Object {
                    $Index = $_
                    $Item = $Collection[$_]
                    $Output = [PSCustomObject] @{
                        _Index = $Index
                    }

                    $Item.PSObject.Properties | ForEach-Object {
                        Add-Member -InputObject $Output -MemberType NoteProperty -Name $_.Name -Value $_.Value
                    }

                    Write-Output $Output
                } | Format-Table @TableArguments | Out-File -Encoding UTF8 $TableFile

                Get-Content -LiteralPath $TableFile -Encoding UTF8 | Write-Host

                [int] $SelectedIndex = If ($Collection.Count -gt 1) {
                    Read-Host -Prompt 'Please, select an index of the item'
                } Else {
                    0
                }

                Write-Output $Collection[$SelectedIndex]
            }
            Finally
            {
                If (Test-Path -PathType Leaf $TableFile)
                {
                    $TableFile | Remove-Item
                }
            }
        }
    }
}