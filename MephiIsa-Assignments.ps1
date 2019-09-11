. "$PSScriptRoot\core.ps1"

Function Set-Assignment
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
            HelpMessage = 'A student',
            Mandatory = $True
        )]
        [System.Object] $Student,

        [Parameter(
            HelpMessage = 'A project',
            Mandatory = $True
        )]
        [System.Object] $Project
    )

    $ProjectId = $Project.Id
    $StudentId = $Student.Id

    $Schema = Get-Schema -CourseRun $CourseRun
    $Start = Get-Date $Schema.start
    $Finish = $Start.AddDays(17 * 7)

    $Member = Invoke-RemoteApi -Resource $Constants.Resources.Project -SubPath "/$ProjectId/members" |
        Where-Object {
            $_.id -eq $StudentId
        }
    If ($Member)
    {
        Throw "$($Member.Name) already has access to the project $($Project.FullName)"
    }

    $Milestone = Get-Milestone -CourseRun $CourseRun -Current

    Invoke-RemoteApi -Post -Resource $Constants.Resources.Project -SubPath "/$ProjectId/members" -Body @{
        user_id = $StudentId
        access_level = $Constants.AccessLevels.Maintainer
        expires_at = Get-Date $Finish -Format 'yyyy-MM-dd'
    } | ForEach-Object {
        Write-Verbose "Student '$($Student.Name)' assigned to the project '$($Project.FullName)'"
        Invoke-RemoteApi -Resource $Constants.Resources.Project -SubPath "/$ProjectId/issues" -Attributes @{
            labels = $Constants.CourseLabel.Name
        } | Where-Object {
            $_.milestone.id -eq $Milestone.Id
        } | ForEach-Object {
            $ExistingAssignee = $_.assignees | Where-Object {
                $_.id -eq $StudentId
            }
            If ($ExistingAssignee)
            {
                Throw "Student '$($Student.Name)' already assigned to requirenment '$($_.title)'"
            }
            Invoke-RemoteApi -Put -Resource $Constants.Resources.Project -SubPath "/$ProjectId/issues/$($_.iid)" -Body @{
                assignee_ids = @($StudentId)
            } | ForEach-Object {
                Write-Verbose "Student '$($Student.Name)' assigned to the issue '$($_.title)' of the project '$($Project.FullName)'"
            }
        }

        [PSCustomObject]@{
            Project = $Project
            Student = $Student
            Level = $Constants.AccessLevels.Maintainer
            Finish = $Finish
        }
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
        $s = $_
        $i = $Random.Next(0, $Projects.Count)
        $p = $Projects[$i]
        Write-Verbose "Assigned '$($s.Name)' to '$($p.FullName)'"
        [PSCustomObject]@{
            Student = $s
            Project = $p
        }
        $Projects = $Projects | Where-Object {
            $_.Id -ne $p.Id
        }
    }
}