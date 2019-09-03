. "$PSScriptRoot\core.ps1"

Function Update-PersonalToken
{
    [CmdletBinding()]
    Param()

    $Token = Read-PersonalToken
    Save-PersonalToken $Token
}

Function Remove-PersonalToken
{
    [CmdletBinding()]
    Param()

    $TokenFilePath = Get-PersonalTokenPath
    If (Test-Path -PathType Leaf -LiteralPath $TokenFilePath)
    {
        Remove-Item -LiteralPath $TokenFilePath
        Write-Verbose "PAT token file [$TokenFilePath] has been deleted"
    }
}