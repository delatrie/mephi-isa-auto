Set-Variable -Scope 'Script' -Name 'Constants' -Value ([PSCustomObject]@{
    BaseUrl = 'https://gitlab.com'
    ApiPath = '/api'
    ApiVersion = 'v4'
    AppName = 'MephiIsaAutomation'
    PatFileName = '.pat'
    CourseGroupPrefix = 'mephi.'
    Resources = [PSCustomObject]@{
        Group = 'groups'
        Me = 'user'
    }
})

Function Resolve-PersonalToken
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'Do not request PAT from the user if it has not been found'
        )]
        [Switch] $NoInput
    )

    $TokenFilePath = Get-PersonalTokenPath

    If (Test-Path -PathType Leaf $TokenFilePath)
    {
        Write-Verbose "PAT has been found in [$TokenFilePath]"
        $Token = Get-PersonalToken
    }
    ElseIf (-not $NoInput)
    {
        Write-Verbose "Missing PAT file [$TokenFilePath]. Requesting..."
        $Token = Read-PersonalToken
        Save-PersonalToken $Token
    }
    Else
    {
        Throw "Missing PAT file [$TokenFilePath]"
    }

    Return $Token
}

Function Read-PersonalToken
{
    [CmdletBinding()]
    Param()

    Read-Host -Prompt 'Please, create PAT and paste it here' -AsSecureString
}

Function Save-PersonalToken
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $True,
            HelpMessage = 'Personal access token represented as a System.SecureString instance',
            Position = 0
        )]
        [ValidateNotNull()]
        [System.Security.SecureString] $Token
    )

    $TokenString = ConvertFrom-SecureString -SecureString $Token
    $TokenFilePath = Get-PersonalTokenPath

    $TokenFolderPath = [System.IO.Path]::GetDirectoryName($TokenFilePath)
    If (-not (Test-Path -PathType Container -LiteralPath $TokenFolderPath))
    {
        New-Item -ItemType Directory -Path $TokenFolderPath | Out-Null
    }

    Set-Content -Value $TokenString -LiteralPath $TokenFilePath -Encoding Ascii
    Write-Verbose "PAT '$TokenString' has been saved in [$TokenFilePath]"
}

Function Update-PersonalToken
{
    [CmdletBinding()]
    Param()

    $Token = Read-PersonalToken
    Save-PersonalToken $Token
}

Function Get-PersonalToken
{
    [CmdletBinding()]
    Param()

    $TokenFilePath = Get-PersonalTokenPath
    $TokenString = Get-Content -LiteralPath $TokenFilePath -Encoding Ascii
    ConvertTo-SecureString -String $TokenString
}

Function Get-PersonalTokenPath
{
    [CmdletBinding()]
    Param()

    Return [System.IO.Path]::Combine(
        [System.Environment]::GetFolderPath('LocalApplicationData'),
        $Constants.AppName,
        $Constants.PatFileName
    )
}

Function Invoke-RemoteApi
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $True,
            HelpMessage = 'A resource of interest'
        )]
        [ValidateScript({ $_ -in @($Constants.Resources.PSObject.Properties.Value) })]
        [System.String] $Resource,

        [Parameter(
            HelpMessage = 'A path specified additional arguments/subresources'
        )]
        [System.String] $SubPath = '',

        [Parameter(
            HelpMessage = 'A REST method to execute against the resource'
        )]
        [ValidateSet('GET', 'POST')]
        $Method = 'GET',

        [Parameter(
            HelpMessage = 'An attributes of the query'
        )]
        [ValidateNotNull()]
        [System.Collections.Hashtable] $Attributes = @{}
    )

    $OriginalSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    [System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'

    Try
    {
        $Query = ($Attributes.Keys | ForEach-Object {
            "$([System.Net.WebUtility]::UrlEncode($_))=$([System.Net.WebUtility]::UrlEncode($Attributes[$_]))"
        }) -join '&'
        $QueryString = If ($Query) { "?$Query" } Else { '' }
        $Url = "$($Constants.BaseUrl)$($Constants.ApiPath)/$($Constants.ApiVersion)/${Resource}${SubPath}$QueryString"
        $Token = Resolve-PersonalToken

        $PlainToken = [System.Management.Automation.PSCredential]::new('unused', $Token).GetNetworkCredential().Password

        $Headers = @{
            Authorization = "Bearer $PlainToken"
        }

        $Result = Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers
        If ($Result -is [System.Array])
        {
            For ($i = 0; $i -lt $Result.Length; $i++)
            {
                $Result[$i]
            }
        }
        Else
        {
            $Result
        }
    }
    Finally
    {
        [System.Net.ServicePointManager]::SecurityProtocol = $OriginalSecurityProtocol
    }
}