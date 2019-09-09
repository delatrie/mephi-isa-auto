Set-Variable -Scope 'Script' -Name 'Constants' -Value ([PSCustomObject]@{
    BaseUrl           = 'https://gitlab.com'
    ApiPath           = '/api'
    ApiVersion        = 'v4'
    AppName           = 'MephiIsaAutomation'
    PatFileName       = '.pat'
    CourseGroupPrefix = 'mephi.'
    Resources         = [PSCustomObject]@{
        Group = 'groups'
        Me    = 'user'
        User  = 'users'
    }
    AccessLevels      = [PSCustomObject]@{
        Guest      = 10
        Reported   = 20
        Developer  = 30
        Maintainer = 40
        Owner      = 50
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
    [CmdletBinding(DefaultParameterSetName = 'Get')]
    Param
    (
        [Parameter(ParameterSetName = 'Get')]
        [Switch] $Get,
        [Parameter(ParameterSetName = 'Post')]
        [Switch] $Post,
        [Parameter(ParameterSetName = 'Put')]
        [Switch] $Put,
        [Parameter(ParameterSetName = 'Delete')]
        [Switch] $Delete,

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
            HelpMessage = 'An attributes of the query'
        )]
        [ValidateNotNull()]
        [System.Collections.Hashtable] $Attributes = @{},

        [Parameter(
            HelpMessage = 'A body of the request'
        )]
        [ValidateNotNull()]
        [System.Collections.Hashtable] $Body = @{}
    )

    $OriginalSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
    [System.Net.ServicePointManager]::SecurityProtocol = 'Tls12'

    Try
    {
        $ContentFile = [System.IO.Path]::GetTempFileName()
        $Query = ($Attributes.Keys | ForEach-Object {
            "$([System.Net.WebUtility]::UrlEncode($_))=$([System.Net.WebUtility]::UrlEncode($Attributes[$_]))"
        }) -join '&'
        $QueryString = If ($Query) { "?$Query" } Else { '' }
        $Url = "$($Constants.BaseUrl)$($Constants.ApiPath)/$($Constants.ApiVersion)/${Resource}${SubPath}$QueryString"
        $Token = Resolve-PersonalToken

        $PlainToken = [System.Management.Automation.PSCredential]::new('unused', $Token).GetNetworkCredential().Password

        $InvokeWebRequestParams = @{
            Method  = $PSCmdlet.ParameterSetName
            Headers = @{
                'Accept'         = 'application/json'
                'Accept-Charset' = 'utf-8'
                'Authorization'  = "Bearer $PlainToken"
            }
            Uri     = $Url
            ContentType = 'application/json; charset=UTF-8'
            OutFile = $ContentFile
        }

        If ($Post -or $Put)
        {
            $InvokeWebRequestParams['Body'] = $Body | ConvertTo-Json -Depth 20 -Compress
        }

        Invoke-WebRequest @InvokeWebRequestParams

        $Result = Get-Content -LiteralPath $ContentFile -Encoding UTF8 -Raw | ConvertFrom-Json
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
        If (Test-Path -PathType Leaf $ContentFile)
        {
            Remove-Item $ContentFile
        }
        [System.Net.ServicePointManager]::SecurityProtocol = $OriginalSecurityProtocol
    }
}

Function Get-Schema
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A name of the course',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object] $CourseRun
    )

    $Course = $CourseRun.Course
    $Year = $CourseRun.Year
    $Semester = $CourseRun.Semester
    $FileName = "$Course-$Year-$Semester.json"
    $SchemaPath = Join-Path $PSScriptRoot $FileName
    If (-not (Test-Path -PathType Leaf $SchemaPath))
    {
        Throw "Cannot find a schema of the $Yeas-$Semester run of the ${Course}: [$SchemaPath] does not exist"
    }

    Get-Content $SchemaPath -Encoding UTF8 | ConvertFrom-Json
}

Function Get-MilestoneDefinition
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory = $True
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A name of the milestone requested',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.String] $Name
    )

    $Result = $Schema.milestones | Where-Object 'name' -eq $Name
    If (-not $Result)
    {
        Write-Error "Milestone '$Name' not found in the schema of the course '$($Schema.id)'"
    }
    ElseIf ($Result.Count -gt 1)
    {
        Write-Error "Multiple milestones '$Name' exist in the schema of the course '$($Schema.id)'"
    }
    Else
    {
        Return $Result
    }
}

Function Get-MilestoneStart
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory = $True
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A name of the milestone',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object] $Milestone
    )

    $Start = Get-Date $Schema.start
    $PrevMilestones = $Schema.milestones | Where-Object {
        $_.week -lt $Milestone.Week
    } | Sort-Object 'Week' -Descending
    $PrevMilestone = If ($Null -ne $PrevMilestones) {
        $PrevMilestones[0]
    } Else {
        0
    }
    $Start.AddDays(7 * $PrevMilestone.week)
}

Function Get-MilestoneFinish
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory = $True
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A name of the milestone',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object] $Milestone
    )

    If ($Milestone.week -lt 1)
    {
        Throw "A milestone's week must be greater then zero"
    }

    $Start = Get-Date $Schema.start
    $Start.AddDays(7 * $Milestone.week - 1)
}

Function Get-DomainDefinition
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory = $True
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A domain requested',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.String] $Name
    )

    $Result = $Schema.domains | Where-Object 'id' -eq $Name
    If (-not $Result)
    {
        Write-Error "Domain $Name not found in the schema of the course '$($Schema.id)'"
    }
    ElseIf ($Result.Count -gt 1)
    {
        Write-Error "Multiple domains $Name exist in the schema of the course '$($Schema.id)'"
    }
    Else
    {
        Return $Result
    }
}

Function Get-AreaDefinition
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A domain of the area requested',
            Mandatory = $True
        )]
        [System.Object] $Domain,

        [Parameter(
            HelpMessage = 'A name of the requested area',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.String] $Name
    )

    $Result = $Domain.areas | Where-Object 'id' -eq $Name
    If (-not $Result)
    {
        Write-Error "Area $Name not found in the domain '$($Domain.id)'"
    }
    ElseIf ($Result.Count -gt 1)
    {
        Write-Error "Multiple areas $Name exist in the domain '$($Domain.id)'"
    }
    Else
    {
        Return $Result
    }
}