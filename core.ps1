Set-Variable -Scope 'Script' -Name 'Constants' -Value ([PSCustomObject]@{
    BaseUrl           = 'https://gitlab.com'
    ApiPath           = '/api'
    ApiVersion        = 'v4'
    AppName           = 'MephiIsaAutomation'
    PatFileName       = '.pat'
    CourseGroupPrefix = 'mephi.'
    Resources         = [PSCustomObject]@{
        Group   = 'groups'
        Me      = 'user'
        User    = 'users'
        Project = 'projects'
    }
    AccessLevels      = [PSCustomObject]@{
        Guest      = 10
        Reported   = 20
        Developer  = 30
        Maintainer = 40
        Owner      = 50
    }
    CourseLabel       = [PSCustomObject]@{
        Name        = 'Course'
        Color       = '#42A5F5'
        Description = 'Этой меткой помечаются элементы, связанные с прогрессом выполнения практикума'
    }
    Project           = [PSCustomObject]@{
        Visibility          = 'public'
        RequestAccess       = $False
        IssuesAccess        = 'enabled'
        RepositoryAccess    = 'enabled'
        MergeRequestsAccess = 'enabled'
        BuildsAccess        = 'enabled'
        WikiAccess          = 'enabled'
        SnippetsAccess      = 'enabled'
    }
})

Function Resolve-PersonalToken
{
    [CmdletBinding(DefaultParameterSetName = 'My')]
    Param
    (
        [Parameter(
            HelpMessage = 'Do not request PAT from the user if it has not been found'
        )]
        [Switch] $NoInput,

        [Parameter(
            HelpMessage = 'A username of the person you wish to impersonate',
            ParameterSetName = 'Impersonation',
            Mandatory = $True
        )]
        [System.String] $OnBehalfOf
    )

    $Arguments = If ($PSCmdlet.ParameterSetName -eq 'Impersonation') {
        @{
            OnBehalfOf = $OnBehalfOf
        }
    } Else { @{} }

    $TokenFilePath = Get-PersonalTokenPath @Arguments

    If (Test-Path -PathType Leaf $TokenFilePath)
    {
        Write-Verbose "PAT has been found in [$TokenFilePath]"
        $Token = Get-PersonalToken $TokenFilePath
    }
    ElseIf (-not $NoInput)
    {
        Write-Verbose "Missing PAT file [$TokenFilePath]. Requesting..."
        $Token = Read-PersonalToken @Arguments
        Save-PersonalToken -Token $Token -Path $TokenFilePath
    }
    Else
    {
        Throw "Missing PAT file [$TokenFilePath]"
    }

    Return $Token
}

Function Read-PersonalToken
{
    [CmdletBinding(DefaultParameterSetName = 'My')]
    Param
    (
        [Parameter(
            HelpMessage = 'A username of the person you wish to impersonate',
            ParameterSetName = 'Impersonation',
            Mandatory = $True
        )]
        [System.String] $OnBehalfOf
    )

    $Prompt = If ($PSCmdlet.ParameterSetName -eq 'My') {
        'Please, create PAT and paste it here'
    } Else {
        'Please, request PAT from $OnBehalfOf and paste it here'
    }

    Read-Host -Prompt $Prompt -AsSecureString
}

Function Save-PersonalToken
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $True,
            HelpMessage = 'Personal access token represented as a System.SecureString instance'
        )]
        [ValidateNotNull()]
        [System.Security.SecureString] $Token,

        [Parameter(
            Mandatory = $True,
            HelpMessage = 'A path to save a token'
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path
    )

    $TokenString = ConvertFrom-SecureString -SecureString $Token

    $TokenFolderPath = [System.IO.Path]::GetDirectoryName($Path)
    If (-not (Test-Path -PathType Container -LiteralPath $TokenFolderPath))
    {
        New-Item -ItemType Directory -Path $TokenFolderPath | Out-Null
    }

    Set-Content -Value $TokenString -LiteralPath $Path -Encoding Ascii
    Write-Verbose "PAT '$TokenString' has been saved in [$Path]"
}

Function Update-PersonalToken
{
    [CmdletBinding(DefaultParameterSetName = 'My')]
    Param
    (
        [Parameter(
            HelpMessage = 'A username of the person you wish to impersonate',
            ParameterSetName = 'Impersonation',
            Mandatory = $True
        )]
        [System.String] $OnBehalfOf
    )

    $Arguments = If ($PSCmdlet.ParameterSetName -eq 'Impersonation') {
        @{
            OnBehalfOf = $OnBehalfOf
        }
    } Else { @{} }

    $TokenFilePath = Get-PersonalTokenPath @Arguments

    $Token = Read-PersonalToken @Arguments
    Save-PersonalToken -Token $Token -Path $TokenFilePath
}

Function Get-PersonalToken
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $True,
            HelpMessage = 'A path to read a token from'
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path
    )

    $TokenString = Get-Content -LiteralPath $Path -Encoding Ascii
    ConvertTo-SecureString -String $TokenString
}

Function Get-PersonalTokenPath
{
    [CmdletBinding(DefaultParameterSetName = 'My')]
    Param
    (
        [Parameter(
            HelpMessage = 'A username of the person you with to impersonate',
            Mandatory = $True,
            ParameterSetName = 'Impersonation'
        )]
        [ValidatePattern('^[\w\d\-]+$')]
        [System.String] $OnBehalfOf
    )

    $FileName = If ($PSCmdlet.ParameterSetName -eq 'My') {
        $Constants.PatFileName
    } Else {
        "$OnBehalfOf.pat"
    }

    Return [System.IO.Path]::Combine(
        [System.Environment]::GetFolderPath('LocalApplicationData'),
        $Constants.AppName,
        $FileName
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

    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

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
            ContentType = 'application/json; charset=UTF-8'
            OutFile     = $ContentFile
            PassThru    = $True
        }

        If ($Post -or $Put)
        {
            $InvokeWebRequestParams['Body'] = $Body | ConvertTo-Json -Depth 20 -Compress
        }

        $ResultList = [System.Collections.ArrayList]::new()

        Do
        {
            $Response = Invoke-WebRequest -Uri $Url @InvokeWebRequestParams
            $Result = Get-Content -LiteralPath $ContentFile -Encoding UTF8 -Raw | ConvertFrom-Json
            $ResultList.Add($Result) | Out-Null
            $Url = If ($Response.RelationLink) {
                $Response.RelationLink['next']
            }
            ElseIf ($Response.Headers['Link']) {
                [System.Text.RegularExpressions.Regex] $NextLinkPattern = '<(?<link>[^>]+)>; rel="next"'
                $NextLinkMatch = $NextLinkPattern.Match($Response.Headers['Link'])
                If ($NextLinkMatch.Success)
                {
                    $NextLinkMatch.Groups['link'].Value
                }
            }
        } While ($Url)

        $ResultList | ForEach-Object {
            $Result = $_
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
    }
    Finally
    {
        If (Test-Path -PathType Leaf $ContentFile)
        {
            Remove-Item $ContentFile
        }
        [System.Net.ServicePointManager]::SecurityProtocol = $OriginalSecurityProtocol
        $ProgressPreference = $OriginalProgressPreference
    }
}

Function New-Issue
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A definition of the course run',
            Mandatory = $True
        )]
        [System.Object] $Course,

        [Parameter(
            HelpMessage = 'A project (See Get-MephiIsaProject)',
            Mandatory = $True
        )]
        [System.Object] $Project,

        [Parameter(
            HelpMessage = 'A milestone (see Get-MephiIsaMilestone)',
            Mandatory = $True
        )]
        [System.Object] $Milestone,

        [Parameter(
            HelpMessage = 'A requirenment definition',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Requirenment
    )

    Process
    {
        ForEach ($CurrentRequirenment in $Requirenment)
        {
            $Finish = Get-RequirenmentFinish -Schema $Course -Milestone $Milestone.Definition -Requirenment $CurrentRequirenment

            Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -SubPath "/$($Project.Id)/issues" -Body @{
                title        = $CurrentRequirenment.name
                description  = $CurrentRequirenment.description
                milestone_id = $Milestone.Id
                labels       = $Constants.CourseLabel.Name
                due_date     = (Get-Date $Finish -Format 'yyyy-MM-dd')
                weight       = $CurrentRequirenment.points
            }
        }
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

Function Get-RequirenmentDefinition
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A definition of the milestone',
            Mandatory = $True
        )]
        [System.Object] $Milestone,

        [Parameter(
            HelpMessage = 'A name of the requirenment requested',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.String] $Name
    )

    $Result = $Milestone.requirenments | Where-Object 'name' -eq $Name
    If (-not $Result)
    {
        Write-Error "Requirenment '$Name' not found in the schema of the milestone '$($Milestone.name)'"
    }
    ElseIf ($Result.Count -gt 1)
    {
        Write-Error "Multiple requirenments '$Name' exist in the schema of the milestone '$($Milestone.name)'"
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

Function Get-RequirenmentFinish
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory   = $True,
            Position = 0
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A milestone definition',
            Mandatory   = $True,
            Position = 1
        )]
        [System.Object] $Milestone,

        [Parameter(
            HelpMessage = 'A requirenment definition',
            Mandatory   = $True,
            Position = 2
        )]
        [System.Object] $Requirenment
    )

    $PrevMilestones = $Schema.milestones.week | Where-Object {
        $_ -lt $Milestone.week
    } | Sort-Object -Descending
    $PrevMilestoneWeek = If ($Null -ne $PrevMilestones) {
        $PrevMilestones[0]
    } Else {
        0
    }

    If ($Requirenment.week -le $PrevMilestoneWeek -or $Requirenment.week -gt $Milestone.week)
    {
        Throw "A week of a requirenment of the milestone '$($Milestone.name)' must be between ($PrevMilestoneWeek, $($Milestone.week)]"
    }

    $Start = Get-Date $Schema.start
    $Start.AddDays(7 * $Requirenment.week - 1)
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

Function Get-ProjectDescription
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A schema of the course',
            Mandatory = $True,
            Position = 0
        )]
        [System.Object] $Schema,

        [Parameter(
            HelpMessage = 'A domain of the project',
            Mandatory = $True,
            Position = 1
        )]
        [System.Object] $Domain,

        [Parameter(
            HelpMessage = 'An area of the project',
            Mandatory = $True,
            Position = 2
        )]
        [System.Object] $Area
    )

    $Start = Get-Date $Schema.start
    $Year = $Start.Year
    $Month = $Start.Month
    $Semester = If ($Month -eq 9) { 'осеннем' } Else { 'весеннем' }

    Return "Проект по автоматизации группы бизнес-процессов '$($Area.name)' " +
        "предметной области '$($Domain.name)'. Выполняется в рамках курса " +
        "'$($Schema.name)' в $Semester семестре $Year года"
}

Function Get-ProjectReadme
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
            HelpMessage = 'A domain of the project',
            Mandatory = $True
        )]
        [System.Object] $Domain,

        [Parameter(
            HelpMessage = 'A teacher',
            Mandatory = $True
        )]
        [System.Object] $Teacher,

        [Parameter(
            HelpMessage = 'An area of the project',
            Mandatory = $True
        )]
        [System.Object] $Area,

        [Parameter(
            HelpMessage = 'A course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A project from gitlab',
            Mandatory = $True
        )]
        [System.Object] $Project
    )

    $Start = Get-Date $Schema.start
    $Year = $Start.Year

    Return @"
Добро пожаловать в репозиторий для варианта '$($Domain.id).$($Area.id)' по лабораторному практикуму "$($Schema.name)" $Year.

# Преподаватель
Каждый вартант закреплен за своим преподавателем.
Преподаватель для этого варианта: $($Teacher.name) (см. контакты ниже).

# Описание задания
Задание по варианту состоит из предметной области и области автоматизации. Для
выполнения практикума необходимо создать информационную систему, позволяющую
автоматизировать указанные процессы предметной области. Описание предметных
областей и автоматизируемых процессов намеренно упрощено (или отсутствует).
Подробную информацию вам предстоит собрать на этапе аналитики.

## Предметная область
Предметная область данного задания - $($Domain.name)
### $($Domain.name)
$($Domain.description)

## Область автоматизации
Информационная система отвечает за следующий участок предметной области: $($Area.name)
### $($Area.name)
$($Area.description)

# Организация репозиториев
Все репозитории являются открытыми. Это означает, что любой может просмотреть
хранящийся в них код или склонировать его.
Студенту, назначенному на вариант, предоставляются права главного разработчика
(maintainer). Он может совершать коммиты в репозиторий, создавать ветви и т.д.

Обратите внимание на страницу 'Issues'. На ней представлены карточки,
соответствующие заданиям по варианту (на всех таких карточках имеется синяя
метка 'course'). Каждая карточка имеет установленную дату выполнения и связана
с одним из разделов практикума. С их помощью вы можете получить информацию о
выполненных и невыполненных заданиях, а также о сроках выполнения заданий и о
сроках контроля разделов.

> **ВНИМАНИЕ**: Карточки, отмеченные синей меткой 'course' предназначены для
обратной связи от преподавателей о прогрессе студента в выполнении задания.
Студенту нельзя вносить в них изменения (однако, можно комментировать и
связывать с коммитами).

При необходимости, студент может создавать собственные карточки для личного
пользования.

Напоминаем, что все результаты этапов практикума (будь то код или прочие
артефакты) должны быть загружены в репозиторий (для артефактов аналитики
рекомендуется создать отдельную директорию). Студентам, не имеющим опыта работы
с Git, рекоментуется для ознакомления книга "Pro Git" за авторством Scott
Chacon и Ben Straub (см. ссылки ниже). Рекомендуется связывать коммиты,
которыми загружаются результаты этапа, с карточкой соответствующего задания.
Подробнее о том как это делать см. [по этой ссылке](https://docs.gitlab.com/ee/user/project/issues/crosslinking_issues.html#from-commit-messages).

# Полезные ссылки
Ниже перечислены некоторые полезные ссылки.

  - [Группа $($CourseRun.Course)-$($CourseRun.FullName)](https://gitlab.com/groups/mephi.$($CourseRun.Course)/$($CourseRun.FullName))
  - [Контрольные вехи](https://gitlab.com/groups/mephi.$($CourseRun.Course)/$($CourseRun.FullName)/-/milestones)
  - [Задачи по этому варианту]($($Project.web_url)/issues)
  - [Pro Git by Scott Chacon and Ben Straub](https://git-scm.com/book/en/v2)

# Контакты
Ниже перечислены контакты преподавателей

"@ + (($Schema.teachers | ForEach-Object {
        $i = 0
    } {
        $i++
        "$i. $($_.name)"
        "   - email: $($_.email)"
        "   - gitlab: @$($_.id)"
        If ($_.telegram)
        {
            "   - telegram: $($_.telegram)"
        }
    }) -join "`n")
}

Function Get-IdMap
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Sequence,

        [Parameter(
            HelpMessage = 'A name of the key property'
        )]
        [System.String] $Property = 'Id'
    )

    Begin
    {
        $Map = @{}
    }

    Process
    {
        ForEach ($Item in $Sequence)
        {
            $Map[$Item.$Property] = $Item
        }
    }

    End
    {
        Return $Map
    }
}