. "$PSScriptRoot\core.ps1"

$ProjectResource = $Constants.Resources.Project
$GroupResource = $Constants.Resources.Group

Function Get-Assignment
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
        HelpMessage           = 'A run of the course',
            Mandatory         = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $CourseRun
    )

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id

            $IdToMilestoneMap = $CurrentCourseRun | Get-Milestone | Get-IdMap
            $IdToStudentMap = $CurrentCourseRun | Get-Group | Get-Student -Granted | Get-IdMap
            $IdToProjectMap = $CurrentCourseRun | Get-Project | Get-IdMap

            Invoke-RemoteApi -Resource $GroupResource -SubPath "/$CurrentCourseRunId/issues" -Attributes @{
                labels = $Constants.CourseLabel.Name
            } | ForEach-Object {
                $Project = $IdToProjectMap[$_.project_id]
                $Milestone = $IdToMilestoneMap[$_.milestone.id]
                $Students = $IdToStudentMap[@($_.assignees.Id)]

                $Definition = $_.title | Get-RequirenmentDefinition -Milestone $Milestone.Definition

                [PSCustomObject]@{
                    Id           = $_.iid
                    Name         = $_.title
                    State        = $_.state
                    Deadline     = (Get-Date $_.due_date)
                    Description  = $_.description
                    Url          = $_.web_url
                    Grade        = $_.weight

                    IsInProgress = 'Doing' -in $_.labels
                    IsScheduled  = 'To Do' -in $_.labels
                    IsCompleted  = $_.state -eq 'closed'

                    Definition   = $Definition

                    Project      = $Project
                    Milestone    = $Milestone
                    Student      = $Students
                }
            }
        }
    }
}

Function Test-Assignment
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
        HelpMessage           = 'A run of the course',
            Mandatory         = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Assignment
    )


}

Function Set-Assignment
{
    [CmdletBinding(
        DefaultParameterSetName = 'Explicit'
    )]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A student',
            ParameterSetName = 'Explicit',
            Mandatory = $True
        )]
        [System.Object] $Student,

        [Parameter(
            HelpMessage = 'A project',
            ParameterSetName = 'Explicit',
            Mandatory = $True
        )]
        [System.Object] $Project,

        [Parameter(
            HelpMessage = 'An assignment map created with New-AssignmentMap',
            ParameterSetName = 'Map',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Map,

        [Parameter(
            HelpMessage = 'A milestone to assign the student. Defaults to the current milestone of the run'
        )]
        [System.Object] $Milestone = $Null
    )

    Begin
    {
        If ($PSCmdlet.ParameterSetName -eq 'Explicit')
        {
            $Map = [PSCustomObject]@{
                Student = $Student
                Project = $Project
            }
        }

        $Schema = Get-Schema -CourseRun $CourseRun
        $Finish = Get-Date $Schema.end

        $AccessLevel = $Constants.AccessLevels.Maintainer

        If (-not $Milestone)
        {
            $Milestone = Get-Milestone -CourseRun $CourseRun -Current
            $MilestoneName = $Milestone.Definition.name
            Write-Verbose "Current milestone '$MilestoneName' selected as the default one"
        }
    }

    Process
    {
        ForEach ($Pair in $Map)
        {
            $Student = $Pair.Student
            $Project = $Pair.Project

            $ProjectId = $Project.Id
            $StudentId = $Student.Id
            $StudentName = $Student.Name
            $Status = 'Unaffected'

            $Member = Invoke-RemoteApi -Resource $ProjectResource -SubPath "/$ProjectId/members" |
                Where-Object {
                    $_.id -eq $StudentId
                }
            If (-not $Member)
            {
                Invoke-RemoteApi -Post -Resource $ProjectResource -SubPath "/$ProjectId/members" -Body @{
                    user_id = $StudentId
                    access_level = $AccessLevel
                    expires_at = Get-Date $Finish -Format 'yyyy-MM-dd'
                } | ForEach-Object {
                    Write-Verbose "Student '$StudentName' has been assigned to the project '$($Project.FullName)'"
                }
                $Status = 'Assigned'
            }
            ElseIf ($Member.access_level -ne $AccessLevel)
            {
                Write-Warning "Student '$StudentName' is assigned to the project '$($Project.FullName)' with the access level $($Member.access_level). Access level $AccessLevel was expected"
                Invoke-RemoteApi -Put -Resource $ProjectResource -SubPath "/$ProjectId/members/$($Member.id)" -Body @{
                    access_level = $AccessLevel
                } | ForEach-Object {
                    Write-Verbose "Access level of the student '$StudentName' as a member of '$($Project.FullName)' has been corrected to be $($_.access_level)"
                }
                $Status = 'Corrected'
            }
            Else
            {
                $CorrectBody = @{}
                If ($Member.access_level -ne $AccessLevel)
                {
                    Write-Warning "Student '$StudentName' is assigned to the project '$($Project.FullName)' with the access level $($Member.access_level). Access level $AccessLevel was expected"
                    $CorrectBody['access_level'] = $AccessLevel
                }

                $ActualFinish = Get-Date $Member.expires_at
                If ($ActualFinish -ne $Finish)
                {
                    Write-Warning "Access of the student '$StudentName' to the project '$($Project.FullName)' expires at $ActualFinish. Expiration date of $Finish was expected"
                    $CorrectBody['expires_at'] = $Finish
                }

                If ($CorrectBody.Count -gt 0)
                {
                    Invoke-RemoteApi -Put -Resource $ProjectResource -SubPath "/$ProjectId/members/$($Member.id)" -Body @{
                        access_level = $AccessLevel
                    } | ForEach-Object {
                        Write-Verbose "Access of the student '$StudentName' as a member of '$($Project.FullName)' has been corrected"
                    }
                    $Status = 'Corrected'
                }
                Else
                {
                    Write-Verbose "$($Member.Name) already has correct access to the project $($Project.FullName)"
                }
            }

            Invoke-RemoteApi -Resource $ProjectResource -SubPath "/$ProjectId/issues" -Attributes @{
                labels = $Constants.CourseLabel.Name
            } | Where-Object {
                $_.milestone.id -eq $Milestone.Id
            } | ForEach-Object {
                $ExistingAssignee = $_.assignees | Where-Object {
                    $_.id -eq $StudentId
                }
                If (-not $ExistingAssignee)
                {
                    $AssigneeIds = @($_.assignees | ForEach-Object {} { $_.id } { $StudentId })
                    Invoke-RemoteApi -Put -Resource $ProjectResource -SubPath "/$ProjectId/issues/$($_.iid)" -Body @{
                        assignee_ids = $AssigneeIds
                    } | ForEach-Object {
                        Write-Verbose "Student '$StudentName' has been assigned to the requirenment '$($_.title)' of the project '$($Project.FullName)'"
                    }

                    If ($Status -eq 'Unaffected')
                    {
                        $Status = 'Assigned'
                    }
                }
                Else
                {
                    Write-Verbose "Student '$($Student.Name)' has already been assigned to the requirenment '$($_.title)' of the project '$($Project.FullName)'"
                }
            }

            [PSCustomObject]@{
                Student = $Student.Name
                Project = $Project.FullName
                Status  = $Status
                Level   = $Constants.AccessLevels.Maintainer
                Finish  = $Finish
            }
        }
    }

    End
    {

    }
}

Function New-AssignmentMap
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'Projects',
            Mandatory = $True
        )]
        [System.Object[]] $Projects,

        [Parameter(
            HelpMessage = 'Students',
            Mandatory = $True
        )]
        [System.Object[]] $Students
    )

    $Random = [System.Random]::new()
    $Students | ForEach-Object {
        [PSCustomObject]@{
            Student = $_
            Rank = $Random.Next()
        }
    } | Sort-Object "Rank" | ForEach-Object { $i = 0 } {
        [PSCustomObject]@{
            Student = $_.Student
            Project = $Projects[$i]
        }
        $i++
    }
}

Function Remove-Assignment
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A student to be unassigned from the project',
            Mandatory = $True
        )]
        [System.Object] $Student,

        [Parameter(
            HelpMessage = 'A project to unassign the student from',
            Mandatory = $True
        )]
        [System.Object] $Project,

        [Parameter(
            HelpMessage = 'A milestone to unassign the student from.' +
                ' Defaults to the current milestone. If this is the last' +
                ' milestone the student is assigned within, the access to ' +
                'the project repository is retracted.'
        )]
        [System.Object] $Milestone = $Null
    )

    $StudentId = $Student.Id
    $StudentName = $Student.Name
    $ProjectId = $Project.Id

    If (-not $Milestone)
    {
        $Milestone = Get-Milestone -CourseRun $CourseRun -Current
        $MilestoneName = $Milestone.Definition.name
        Write-Verbose "Current milestone '$MilestoneName' selected as the default one"
    }

    Invoke-RemoteApi -Resource $ProjectResource -SubPath "/$ProjectId/issues" -Attributes @{
        labels = $Constants.CourseLabel.Name
    } | Where-Object {
        $_.milestone.id -eq $Milestone.Id
    } | ForEach-Object {
        If ($_.assignees | Where-Object { $_.id -eq $StudentId })
        {
            $AssigneeIds = @($_.assignees | ForEach-Object { $_.id } | Where-Object { $_ -ne $StudentId })
            Invoke-RemoteApi -Put -Resource $ProjectResource -SubPath "/$ProjectId/issues/$($_.iid)" -Body @{
                assignee_ids = $AssigneeIds
            } | ForEach-Object {
                Write-Verbose "The student '$StudentName' has been unassigned from the requirenment '$($_.title)' of the project '$($Project.FullName)'"
            }
        }
        Else
        {
            Write-Verbose "The student '$StudentName' is not assigned to the requirenment '$($_.title)' of the project '$($Project.FullName)'"
        }
    }

    $AllMilestones = Get-Milestone -CourseRun $CourseRun
    $AllMilestoneIds = @($AllMilestones | ForEach-Object { $_.Id })

    $AssignedMilestones = Invoke-RemoteApi -Resource $ProjectResource -SubPath "/$ProjectId/issues" -Attributes @{
        labels = $Constants.CourseLabel.Name
        state  = 'opened'
    } | Where-Object {
        $_.milestone.id -in $AllMilestoneIds -and ($_.assignees | Where-Object { $_.id -eq $StudentId })
    } | ForEach-Object {
        $Requirenment = $_
        $ReqMilestone = $AllMilestones | Where-Object { $_.Id -eq $Requirenment.milestone.id }
        [PSCustomObject]@{
            Requirenment = $_.title
            Milestone    = $ReqMilestone.Definition.name
        }
    } | Group-Object Milestone

    If ($AssignedMilestones)
    {
        Write-Verbose "The student '$StudentName' is still assigned to the following milestones of the project '$($Project.FullName)':"
        $AssignedMilestones | ForEach-Object {
            $MilestoneName = $_.Name
            $RequirenmentsCount = $_.Count
            Write-Verbose "  - $MilestoneName - $RequirenmentsCount unfinished requirenments:"
            $_.Group | ForEach-Object {
                $RequirenmentName = $_.Requirenment
                Write-Verbose "      - $RequirenmentName"
            }
        }
        Write-Verbose "The assignment to the project itself is not deleted"
    }
    Else
    {
        Write-Verbose "The student '$StudentName' is not currently assigned to any active requirenment in the project '$($Project.FullName)'"
        $Member = Invoke-RemoteApi -Resource $ProjectResource -SubPath "/$ProjectId/members" |
            Where-Object {
                $_.id -eq $StudentId
            }
        If ($Member)
        {
            Invoke-RemoteApi -Delete -Resource $ProjectResource -SubPath "/$ProjectId/members/$StudentId"
            Write-Verbose "The access of the student '$StudentName' to the project '$($Project.FullName)' has been retracted"
        }
        Else
        {
            Write-Verbose "The student '$StudentName' already has no access to the project '$($Project.FullName)'"
        }
    }
}