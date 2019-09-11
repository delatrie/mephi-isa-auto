. "$PSScriptRoot\core.ps1"

[System.Text.RegularExpressions.Regex] $ProjectNamePattern = '^(?<domain>[^\.]+)\.(?<area>.+)$'

Function Sync-Project
{
    [CmdletBinding(SupportsShouldProcess = $True)]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $CourseRun,

        [Parameter(
            HelpMessage = "An email address to commit README.md to a new project's repository"
        )]
        [System.String] $CommitEmail,

        [Parameter(
            HelpMessage = "A name to commit README.md to a new project's repository"
        )]
        [System.String] $CommitName,

        [Parameter(
            HelpMessage = 'Only check correctness of actual projects. Equivalent to NoToAll option'
        )]
        [Switch] $CheckOnly,

        [Parameter(
            HelpMessage = 'Do not prompt to make corrections. Equivalent to YesToAll option'
        )]
        [Switch] $Force
    )

    Begin
    {
        If (-not $PSBoundParameters.ContainsKey('Verbose'))
        {
            $VerbosePreference = $PSCmdlet.SessionState.PSVariable.GetValue('VerbosePreference')
        }
        If (-not $PSBoundParameters.ContainsKey('Confirm'))
        {
            $ConfirmPreference = $PSCmdlet.SessionState.PSVariable.GetValue('ConfirmPreference')
        }
        If (-not $PSBoundParameters.ContainsKey('WhatIf'))
        {
            $WhatIfPreference = $PSCmdlet.SessionState.PSVariable.GetValue('WhatIfPreference')
        }
    }

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $Groups = Get-Group -CourseRun $CurrentCourseRun
            $CurrentCourseRunId = $CurrentCourseRun.Id
            $CurrentCourse = $CurrentCourseRun.Course

            $Schema = $CurrentCourseRun | Get-Schema

            $Milestones = $CurrentCourseRun | Get-Milestone

            $DefinedProjects = $Schema.domains | ForEach-Object {
                $Domain = $_
                $_.areas | ForEach-Object {
                    $Area = $_
                    $Tasks = $Schema.milestones | ForEach-Object {
                        $MilestoneDefinition = $_
                        $Milestone = $Milestones | Where-Object {
                            $_.Definition.name -eq $MilestoneDefinition.name
                        }
                        If (-not $Milestone)
                        {
                            Throw "Milestone '$($MilestoneDefinition.name)' does not exist in the group #$CurrentCourseRunId '$($CurrentCourseRun.FullName)'. You may try Sync-MephiIsaMilestone cmdlet to fix that"
                        }
                        $_.requirenments | ForEach-Object {
                            [PSCustomObject]@{
                                Name = $_.name
                                Description = $_.description
                                Finish = (Get-RequirenmentFinish $Schema $MilestoneDefinition $_)
                                Points = $_.points
                                Milestone = $Milestone
                            }
                        }
                    }
                    [PSCustomObject]@{
                        FullName            = "$($Domain.id).$($Area.id)"
                        Domain              = $Domain
                        Area                = $Area
                        Description         = (Get-ProjectDescription $Schema $Domain $Area)
                        Tags                = @($CurrentCourse)
                        Visibility          = $Constants.Project.Visibility
                        RequestAccess       = $Constants.Project.RequestAccess
                        IssuesAccess        = $Constants.Project.IssuesAccess
                        RepositoryAccess    = $Constants.Project.RepositoryAccess
                        MergeRequestsAccess = $Constants.Project.MergeRequestsAccess
                        BuildsAccess        = $Constants.Project.BuildsAccess
                        WikiAccess          = $Constants.Project.WikiAccess
                        SnippetsAccess      = $Constants.Project.SnippetsAccess
                        Tasks               = $Tasks
                    }
                }
            }

            $ActualProjects = @(Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/projects" |
                Where-Object { $_.name -match $ProjectNamePattern } |
                ForEach-Object {
                    $Project = $_
                    $Match = $ProjectNamePattern.Match($_.name)

                    $DomainName = $Match.Groups['domain'].Value
                    $AreaName = $Match.Groups['area'].Value
                    $Domain = $DomainName | Get-DomainDefinition -Schema $Schema -ErrorAction SilentlyContinue
                    If ($Null -ne $Domain)
                    {
                        $Area = $AreaName | Get-AreaDefinition -Domain $Domain -ErrorAction SilentlyContinue
                        $Tasks = Invoke-RemoteApi -Resource $Constants.Resources.Project -SubPath "/$($_.id)/issues" |
                            Where-Object {
                                $Constants.CourseLabel.Name -in $_.labels
                            } |
                            ForEach-Object {
                                If ($Null -ne $_.milestone -and $_.milestone.group_id -eq $CurrentCourseRunId)
                                {
                                    $Issue = $_
                                    $Milestone = $Milestones | Where-Object {
                                        $_.Id -eq $Issue.milestone.id
                                    }
                                    If ($Null -eq $Milestone)
                                    {
                                        Throw "Issue #$($Issue.id) '$($Issue.title)' of the project #$($Project.id) '$($Project.name)' is assigned to the milestone #$($Issue.milestone.id) '$($Issue.milestone.title)' that does not exist in the group #$CurrentCourseRunId '$($CurrentCourseRun.FullName)'"
                                    }
                                }

                                [PSCustomObject]@{
                                    Id = $_.iid
                                    Name = $_.title
                                    Description = $_.description
                                    Finish = (Get-Date $_.due_date)
                                    Points = $_.weight
                                    Milestone = $Milestone
                                }
                            }
                        If ($Null -ne $Area)
                        {
                            [PSCustomObject]@{
                                Id                  = $_.id
                                FullName            = $_.name
                                Domain              = $Domain
                                Area                = $Area
                                Description         = $_.description
                                Tags                = $_.tag_list
                                Visibility          = $_.visibility
                                RequestAccess       = $_.request_access_enabled
                                IssuesAccess        = $_.issues_access_level
                                RepositoryAccess    = $_.repository_access_level
                                MergeRequestsAccess = $_.merge_requests_access_level
                                BuildsAccess        = $_.builds_access_level
                                WikiAccess          = $_.wiki_access_level
                                SnippetsAccess      = $_.snippets_access_level
                                Tasks               = $Tasks
                                SharedWith          = $_.shared_with_groups
                                GitlabProject       = $_
                            }
                        }
                        Else
                        {
                            Write-Warning "The area '$AreaName' (domain '$DomainName') of the project '$($_.name)' #$($_.id) was not found in the definition of the course '$CurrentCourse'"
                        }
                    }
                    Else
                    {
                        Write-Warning "The domain '$DomainName' of the project '$($_.name)' #$($_.id) was not found in the definition of the course '$CurrentCourse'"
                    }
                })

            Compare-Object -ReferenceObject $DefinedProjects -DifferenceObject $ActualProjects -Property 'FullName' -IncludeEqual |
                ForEach-Object {
                    $FullName = $_.FullName
                    Switch ($_.SideIndicator)
                    {
                        '<='
                        {
                            Write-Warning "Project '$FullName' is missing"
                            If (-not $CheckOnly -and ($Force -or $PSCmdlet.ShouldContinue("Do you wish to create the project?", "Project '$FullName' creation", [ref] $Force, [ref] $CheckOnly)))
                            {
                                $ProjectDefinition = $DefinedProjects | Where-Object { $_.FullName -eq $FullName }
                                Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -Body @{
                                    name                        = $ProjectDefinition.FullName
                                    path                        = $ProjectDefinition.FullName.ToLower()
                                    description                 = $ProjectDefinition.Description
                                    namespace_id                = $CurrentCourseRunId
                                    visibility                  = $ProjectDefinition.Visibility
                                    tag_list                    = $ProjectDefinition.Tags
                                    request_access_enabled      = $ProjectDefinition.RequestAccess
                                    issues_access_level         = $ProjectDefinition.IssuesAccess
                                    repository_access_level     = $ProjectDefinition.RepositoryAccess
                                    merge_requests_access_level = $ProjectDefinition.MergeRequestsAccess
                                    builds_access_level         = $ProjectDefinition.BuildsAccess
                                    wiki_access_level           = $ProjectDefinition.WikiAccess
                                    snippets_access_level       = $ProjectDefinition.SnippetsAccess
                                } | ForEach-Object {
                                    $Project = $_
                                    $ProjectId = $_.id
                                    Write-Verbose "Project $FullName has been created"
                                    $Milestones | ForEach-Object {
                                        $Milestone = $_
                                        $Milestone.Definition.requirenments | New-Issue -Course $Schema -Project $Project -Milestone $_ | ForEach-Object {
                                            Write-Verbose "Issue #$($_.id) '$($_.title)' of project #$ProjectId '$($Project.name)' has been created as part of the milestone #$($_.milestone.id) '$($Milestone.Definition.Name)'"
                                        }
                                    }
                                    $Path = [System.Net.WebUtility]::UrlEncode('README.md')
                                    While (-not $CommitEmail)
                                    {
                                        $CommitEmail = Read-Host -Prompt 'A new project is being created and an email is required to commit a README file. Please, enter your commit email here'
                                    }
                                    While (-not $CommitName)
                                    {
                                        $CommitName = Read-Host -Prompt 'Please, enter your commit name here'
                                    }
                                    $Domain = $ActualProject.Domain
                                    $Teacher = $Schema.teachers | Where-Object { $_.id -eq $Domain.teacher }
                                    If (-not $Teacher)
                                    {
                                        Throw "Teacher '$($Domain.teacher)' not exists"
                                    }
                                    $Content = Get-ProjectReadme -Schema $Schema -Domain $ProjectDefinition.Domain -Teacher $Teacher -Area $ProjectDefinition.Area -CourseRun $CurrentCourseRun -Project $Project
                                    Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -SubPath "/$ProjectId/repository/files/$Path" -Body @{
                                        branch = 'master'
                                        author_email = $CommitEmail
                                        author_name = $CommitName
                                        content = $Content
                                        commit_message = 'Initialize repository, create README.md'
                                    } | ForEach-Object {
                                        Write-Verbose "README.md for $($Project.name) created"
                                    }
                                    Start-Sleep -Seconds 5
                                    $Groups | ForEach-Object {
                                        Write-Verbose "$_"
                                        Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/share" -Body @{
                                            group_id = $_.Id
                                            group_access = $Constants.AccessLevels.Guest
                                        } | ForEach-Object {
                                            Write-Verbose "The project '$($ActualProject.FullName)' has been shared with the group $($_.group_name)"
                                        }
                                    }
                                }
                            }
                        }

                        '=>'
                        {
                            Write-Warning "Project '$FullName' does not exist in the definition of the course. Projects are not removed automatically, you need to check it and delete manually"
                        }

                        '=='
                        {
                            $ProjectDefinition = $DefinedProjects | Where-Object { $_.FullName -eq $FullName }
                            $ActualProject = $ActualProjects | Where-Object { $_.FullName -eq $FullName }

                            $CorrectBody = @{}

                            If ($ProjectDefinition.Description -ne $ActualProject.Description)
                            {
                                Write-Warning "The description of the project '$FullName' does not match the reference value: '$($ActualProject.Description)' != '$($ProjectDefinition.Description)'"
                                $CorrectBody['description'] = $ProjectDefinition.Description
                            }

                            $MissingTags = $ProjectDefinition.Tags | Where-Object {
                                $_ -notin $ActualProject.Tags
                            }
                            If ($MissingTags)
                            {
                                Write-Warning "The project '$FullName' is not tagged with $MissingTags"
                                $CorrectBody['tag_list'] = @($MissingTags)
                            }

                            If ($ProjectDefinition.Visibility -ne $ActualProject.Visibility)
                            {
                                Write-Warning "The visibility of the project '$FullName' does not match the reference value: '$($ActualProject.Visibility)' != '$($ProjectDefinition.Visibility)'"
                                $CorrectBody['visibility'] = $ProjectDefinition.Visibility
                            }

                            If ($ProjectDefinition.RequestAccess -ne $ActualProject.RequestAccess)
                            {
                                Write-Warning "The RequestAccess of the project '$FullName' does not match the reference value: '$($ActualProject.RequestAccess)' != '$($ProjectDefinition.RequestAccess)'"
                                $CorrectBody['request_access_enabled'] = $ProjectDefinition.RequestAccess
                            }

                            If ($ProjectDefinition.IssuesAccess -ne $ActualProject.IssuesAccess)
                            {
                                Write-Warning "The IssuesAccess of the project '$FullName' does not match the reference value: '$($ActualProject.IssuesAccess)' != '$($ProjectDefinition.IssuesAccess)'"
                                $CorrectBody['issues_access_level'] = $ProjectDefinition.IssuesAccess
                            }

                            If ($ProjectDefinition.RepositoryAccess -ne $ActualProject.RepositoryAccess)
                            {
                                Write-Warning "The RepositoryAccess of the project '$FullName' does not match the reference value: '$($ActualProject.RepositoryAccess)' != '$($ProjectDefinition.RepositoryAccess)'"
                                $CorrectBody['repository_access_level'] = $ProjectDefinition.RepositoryAccess
                            }

                            If ($ProjectDefinition.MergeRequestsAccess -ne $ActualProject.MergeRequestsAccess)
                            {
                                Write-Warning "The MergeRequestsAccess of the project '$FullName' does not match the reference value: '$($ActualProject.MergeRequestsAccess)' != '$($ProjectDefinition.MergeRequestsAccess)'"
                                $CorrectBody['merge_requests_access_level'] = $ProjectDefinition.MergeRequestsAccess
                            }

                            If ($ProjectDefinition.BuildsAccess -ne $ActualProject.BuildsAccess)
                            {
                                Write-Warning "The BuildsAccess of the project '$FullName' does not match the reference value: '$($ActualProject.BuildsAccess)' != '$($ProjectDefinition.BuildsAccess)'"
                                $CorrectBody['builds_access_level'] = $ProjectDefinition.BuildsAccess
                            }

                            If ($ProjectDefinition.WikiAccess -ne $ActualProject.WikiAccess)
                            {
                                Write-Warning "The WikiAccess of the project '$FullName' does not match the reference value: '$($ActualProject.WikiAccess)' != '$($ProjectDefinition.WikiAccess)'"
                                $CorrectBody['wiki_access_level'] = $ProjectDefinition.WikiAccess
                            }

                            If ($ProjectDefinition.SnippetsAccess -ne $ActualProject.SnippetsAccess)
                            {
                                Write-Warning "The SnippetsAccess of the project '$FullName' does not match the reference value: '$($ActualProject.SnippetsAccess)' != '$($ProjectDefinition.SnippetsAccess)'"
                                $CorrectBody['snippets_access_level'] = $ProjectDefinition.SnippetsAccess
                            }

                            $DefinedTasks = $ProjectDefinition.Tasks
                            $ActualTasks = @($ActualProject.Tasks)

                            $RequirenmentSync = @(Compare-Object -ReferenceObject $DefinedTasks -DifferenceObject $ActualTasks -Property 'Name' -IncludeEqual |
                                ForEach-Object {
                                    $Name = $_.Name
                                    Switch ($_.SideIndicator)
                                    {
                                        '<='
                                        {
                                            Write-Warning "Task '$Name' of the '$($CurrentCourseRun.FullName)' run (#$CurrentCourseRunId) of the '$CurrentCourse' does not exist in the project #$($ActualProject.Id) '$($ActualProject.FullName)'"
                                            $DefinedTask = $DefinedTasks | Where-Object { $_.Name -eq $Name }
                                            [PSCustomObject]@{
                                                Action = 'Create'
                                                Reference = $DefinedTask
                                            }
                                        }

                                        '=>'
                                        {
                                            Write-Warning "Task '$Name' of the project #$($ActualProject.Id) '$($ActualProject.FullName)' is not defined as a part of the '$($CurrentCourseRun.FullName)' run (#$CurrentCourseRunId) of the '$CurrentCourse'"
                                            $ActualTask = $ActualTasks | Where-Object { $_.Name -eq $Name }
                                            [PSCustomObject]@{
                                                Action = 'Delete'
                                                Name = $Name
                                                Id = $ActualTask.Id
                                            }
                                        }

                                        '=='
                                        {
                                            $DefinedTask = $DefinedTasks | Where-Object { $_.Name -eq $Name }
                                            $ActualTask = $ActualTasks | Where-Object { $_.Name -eq $Name }

                                            $TaskCorrectBody = @{}
                                            If ($DefinedTask.Description -ne $ActualTask.Description)
                                            {
                                                Write-Warning "Task #$($ActualTask.Id) '$Name', project #$($ActualProject.Id) '$($ActualProject.FullName)', run #$CurrentCourseRunId '$($CurrentCourseRun.FullName)' of the '$CurrentCourse': Descriptions mismatch - '$($DefinedTask.Description)' != '$($ActualTask.Description)'"
                                                $TaskCorrectBody['description'] = $DefinedTask.Description
                                            }

                                            If (-not $ActualTask.Milestone)
                                            {
                                                Write-Warning "Task #$($ActualTask.Id) '$Name', project #$($ActualProject.Id) '$($ActualProject.FullName)', run #$CurrentCourseRunId '$($CurrentCourseRun.FullName)' of the '$CurrentCourse': Missing or invalid milestone"
                                                $TaskCorrectBody['milestone_id'] = $DefinedTask.Milestone.Id
                                            }
                                            ElseIf ($DefinedTask.Milestone.Id -ne $ActualTask.Milestone.Id)
                                            {
                                                Write-Warning "Task #$($ActualTask.Id) '$Name', project #$($ActualProject.Id) '$($ActualProject.FullName)', run #$CurrentCourseRunId '$($CurrentCourseRun.FullName)' of the '$CurrentCourse': Milestone mismatch - #$($DefinedTask.Milestone.Id) '$($DefinedTask.Milestone.Name)' != #$($ActualTask.Milestone.Id) '$($ActualTask.Milestone.Name)'"
                                                $TaskCorrectBody['milestone_id'] = $DefinedTask.Milestone.Id
                                            }

                                            If ($DefinedTask.Finish -ne $ActualTask.Finish)
                                            {
                                                Write-Warning "Task #$($ActualTask.Id) '$Name', project #$($ActualProject.Id) '$($ActualProject.FullName)', run #$CurrentCourseRunId '$($CurrentCourseRun.FullName)' of the '$CurrentCourse': Finish mismatch - '$($DefinedTask.Finish)' != '$($ActualTask.Finish)'"
                                                $TaskCorrectBody['due_date'] = Get-Date $DefinedTask.Finish -Format 'yyyy-MM-dd'
                                            }

                                            If ($DefinedTask.Points -ne $ActualTask.Points)
                                            {
                                                Write-Warning "Task #$($ActualTask.Id) '$Name', project #$($ActualProject.Id) '$($ActualProject.FullName)', run #$CurrentCourseRunId '$($CurrentCourseRun.FullName)' of the '$CurrentCourse': Points mismatch - '$($DefinedTask.Points)' != '$($ActualTask.Points)'"
                                                $TaskCorrectBody['weight'] = $DefinedTask.Points
                                            }

                                            If ($TaskCorrectBody.Count -gt 0)
                                            {
                                                [PSCustomObject]@{
                                                    Action = 'Update'
                                                    Id     = $ActualTask.Id
                                                    Body   = $TaskCorrectBody
                                                }
                                            }
                                        }
                                    }
                                }
                            )

                            $SharedWith = @($ActualProject.SharedWith | ForEach-Object {
                                $_.group_id
                            })

                            $MissingGroups = $Groups | Where-Object {
                                $_.Id -notin $SharedWith
                            }

                            If ($MissingGroups)
                            {
                                Write-Warning "The project '$FullName' is not shared with the group(s) $($MissingGroups.FullName)"
                            }

                            $Domain = $ActualProject.Domain
                            $Teacher = $Schema.teachers | Where-Object { $_.id -eq $Domain.teacher }
                            $Readme = Get-ProjectReadme -Schema $Schema -Domain $Domain -Teacher $Teacher -Area $ActualProject.Area -CourseRun $CurrentCourseRun -Project $ActualProject.GitlabProject
                            $Path = [System.Net.WebUtility]::UrlEncode('README.md')
                            $ActualReadme = Invoke-RemoteApi -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/repository/files/$Path" -Attributes @{
                                ref = 'master'
                            } | ForEach-Object {
                                $bytes = [System.Convert]::FromBase64String($_.content)
                                [System.Text.Encoding]::UTF8.GetString($bytes)
                            }

                            If ($Readme -ne $ActualReadme)
                            {
                                Write-Warning "The project's '$FullName' README.md does not match reference value: '$Readme' != '$ActualReadme'"
                            }

                            If (-not $CheckOnly -and $CorrectBody.Count -gt 0 -and ($Force -or $PSCmdlet.ShouldContinue("Do you wish to make $($CorrectBody.Count) correction(s) to the project?", "Project '$FullName' correction", [ref] $Force, [ref] $CheckOnly)))
                            {
                                $ProjectId = $ActualProject.Id
                                Invoke-RemoteApi -Put -Resource $Constants.Resources.Project -SubPath "/$ProjectId" -Body $CorrectBody | ForEach-Object {
                                    Write-Verbose "Project $FullName has been corrected"
                                }
                            }
                            If (-not $CheckOnly -and $MissingGroups -and ($Force -or $PSCmdlet.ShouldContinue("Do you wish to share the project with the groups?", "The project '$FullName' sharing with '$($MissingGroups.FullName)'", [ref] $Force, [ref] $CheckOnly)))
                            {
                                $MissingGroups | ForEach-Object {
                                    Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/share" -Body @{
                                        group_id = $_.Id
                                        group_access = $Constants.AccessLevels.Guest
                                    } | ForEach-Object {
                                        Write-Verbose "The project '$($ActualProject.FullName)' has been shared with the group $($_.group_name)"
                                    }
                                }
                            }
                            If (-not $CheckOnly -and $RequirenmentSync.Count -gt 0 -and ($Force -or $PSCmdlet.ShouldContinue("Do you wish to correct $($RequirenmentSync.Count) issues?", "The project '$FullName' issues correction", [ref] $Force, [ref] $CheckOnly)))
                            {
                                $RequirenmentSync | ForEach-Object {
                                    $Sync = $_
                                    Switch ($_.Action)
                                    {
                                        'Create'
                                        {
                                            $DefinedTask = $Sync.Reference
                                            $Milestone = $DefinedTask.Milestone
                                            $RequirenmentDefinition = $DefinedTask.Name | Get-RequirenmentDefinition -Milestone $Milestone.Definition
                                            New-Issue -Course $Schema -Project $ActualProject -Milestone $Milestone -Requirenment $RequirenmentDefinition |
                                                ForEach-Object {
                                                    Write-Verbose "Issue $($_.iid) ($($DefinedTask.Name)) has been created in the project #$($ActualProject.Id)"
                                                }
                                        }

                                        'Delete'
                                        {
                                            $Id = $Sync.Id
                                            Invoke-RemoteApi -Delete -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/issues/$Id"
                                            Write-Verbose "Issue $Id deleted from the project #$($ActualProject.Id)"
                                        }

                                        'Update'
                                        {
                                            $Id = $Sync.Id
                                            $Body = $Sync.Body
                                            Invoke-RemoteApi -Put -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/issues/$Id" -Body $Body |
                                                ForEach-Object {
                                                    Write-Verbose "Issue $Id of the project #$($ActualProject.Id) has been corrected"
                                                }
                                        }
                                    }
                                }
                            }

                            If (-not $CheckOnly -and $Readme -ne $ActualReadme -and ($Force -or $PSCmdlet.ShouldContinue("Do you wish to correct README.md?", "The project '$FullName' README.md correction", [ref] $Force, [ref] $CheckOnly)))
                            {
                                $Path = [System.Net.WebUtility]::UrlEncode('README.md')
                                While (-not $CommitEmail)
                                {
                                    $CommitEmail = Read-Host -Prompt 'A README.md of the existing project is being updated and an email is required to commit the file. Please, enter your commit email here'
                                }
                                While (-not $CommitName)
                                {
                                    $CommitName = Read-Host -Prompt 'Please, enter your commit name here'
                                }
                                Invoke-RemoteApi -Put -Resource $Constants.Resources.Project -SubPath "/$($ActualProject.Id)/repository/files/$Path" -Body @{
                                    branch = 'master'
                                    author_email = $CommitEmail
                                    author_name = $CommitName
                                    content = $Readme
                                    commit_message = 'Update README.md'
                                } | ForEach-Object {
                                    Write-Verbose "README.md of $($ActualProject.FullName) has been updated"
                                }
                            }
                        }
                    }
                }
        }
    }
}

Function Get-Project
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $CourseRun
    )

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id
            $Schema = $CurrentCourseRun | Get-Schema
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/projects" -Attributes @{
                owned = 'true'
            } | Where-Object {
                $_.name -match $ProjectNamePattern
            } | ForEach-Object {
                $Match = $ProjectNamePattern.Match($_.name)
                $Domain = $Match.Groups['domain'].Value | Get-DomainDefinition -Schema $Schema
                $Area = $Match.Groups['area'].Value | Get-AreaDefinition -Domain $Domain
                [PSCustomObject]@{
                    Id = $_.id
                    FullName = $_.name
                    Description = $_.description
                    Domain = $Domain
                    Area = $Area
                }
            }
        }
    }
}