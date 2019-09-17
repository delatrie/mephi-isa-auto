. "$PSScriptRoot\core.ps1"

[System.String[]] $Semesters = @('Spring', 'Autumn')
$SemesterMonths = @{
    Spring = 2..8
    Autumn = 9..12 + 1
}

$SemestersSubPattern = ($Semesters | ForEach-Object {
    [System.Text.RegularExpressions.Regex]::Escape($_)
}) -join '|'
[System.Text.RegularExpressions.Regex] $CourseRunNamePattern = "^(?<year>\d{4})-(?<half>$SemestersSubPattern)$"

$Degrees = [ordered] @{
    'M' = 'Master'
}
$DegreePattern = ($Degrees.Keys | ForEach-Object {
    [System.Text.RegularExpressions.Regex]::Escape($_)
}) -join '|'
[System.Text.RegularExpressions.Regex] $GroupNamePattern = "^(?<level>$DegreePattern)(?<year>\d\d)-(?<number>\d+)$"

Function Get-Course
{
    [CmdletBinding(
        DefaultParameterSetName = 'Name',
        SupportsShouldProcess = $True
    )]
    Param
    (
        [Parameter(
            HelpMessage = 'A name of a course',
            ValueFromPipeline = $True,
            ParameterSetName = 'Name',
            Position = 0
        )]
        [ValidateNotNull()]
        [System.String[]] $Name = @(),

        [Parameter(
            Mandatory = $True,
            HelpMessage = 'An id of the course',
            ValueFromPipeline = $True,
            ParameterSetName = 'Id',
            Position = 0
        )]
        [System.Int32[]] $Id,

        [Parameter(
            HelpMessage = 'Automatically create missing course labels'
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

    End
    {
        Switch ($PSCmdlet.ParameterSetName)
        {
            'Name'
            {
                $Groups = Invoke-RemoteApi -Resource $Constants.Resources.Group -Attributes @{
                    owned = 'true'
                }
            }

            'Id'
            {
                $Groups = $Id | ForEach-Object {
                    "/$Id"
                } | ForEach-Object {
                    Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath $_
                }
            }
        }

        $Groups | Where-Object {
            $Null -eq $_.parent_id -and $_.name.StartsWith($Constants.CourseGroupPrefix)
        } | ForEach-Object {
            [PSCustomObject]@{
                Id = $_.id
                Name = $_.name.Substring($Constants.CourseGroupPrefix.Length)
                Url = $_.web_url
                Description = $_.description
            }
        } | Where-Object {
            $PSCmdlet.ParameterSetName -ne 'Name' -or $_.Name -in $Name
        } | ForEach-Object {
            $Label = Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$($_.Id)/labels" |
                Where-Object {
                    $_.name -eq $Constants.CourseLabel.Name
                }
            If ($Null -eq $Label)
            {
                If ($Force -or $PSCmdlet.ShouldContinue("Course '$($_.Name)' misses label '$($Constants.CourseLabel.Name)'. Do you want to create it?", "Missing course label"))
                {
                    $Label = Invoke-RemoteApi -Post -Resource $Constants.Resources.Group -SubPath "/$($_.Id)/labels" -Body @{
                        name        = $Constants.CourseLabel.Name
                        color       = $Constants.CourseLabel.Color
                        description = $Constants.CourseLabel.Description
                    }
                    If (-not $Label -or $Label.name -ne $Constants.CourseLabel.Name)
                    {
                        Write-Error "Cannot create the label '$($Constants.CourseLabel.Name)' for the course '$($_.Name)'. The label is still missing"
                    }
                }
            }
            Write-Output $_
        }
    }
}

Function Get-CourseRun
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    Param
    (
        [Parameter(
            HelpMessage = 'A course',
            ValueFromPipeline = $True
        )]
        [ValidateNotNull()]
        [System.Object[]] $Course,

        [Parameter(
            HelpMessage = 'A year of the semester',
            ParameterSetName = 'Semester'
        )]
        [ValidateRange(2010, 9999)]
        [System.Int32] $Year = $Null,

        [Parameter(
            HelpMessage = 'Return a course run for the current semester',
            ParameterSetName = 'Current'
        )]
        [Switch] $Current
    )

    DynamicParam
    {
        $Name = 'Semester'

        $Attributes = [System.Management.Automation.ParameterAttribute]::new()
        $Attributes.Mandatory = $False
        $Attributes.HelpMessage = 'A half-year of the semester'
        $Attributes.ParameterSetName = 'Semester'

        $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $AttributeCollection.Add($Attributes)

        $ValidateSetAttribute = [System.Management.Automation.ValidateSetAttribute]::new($Semesters)
        $AttributeCollection.Add($ValidateSetAttribute)

        $Parameter = [System.Management.Automation.RuntimeDefinedParameter]::new(
            $Name,
            [System.String],
            $AttributeCollection
        )

        $ParametersDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $ParametersDictionary.Add($Name, $Parameter)

        Return $ParametersDictionary
    }

    Begin
    {
        $HasYear = $PSBoundParameters.ContainsKey('Year')
        $HasSemester = $PSBoundParameters.ContainsKey('Semester')

        If ($HasSemester)
        {
            $Semester = $PSBoundParameters.Semester
        }

        If ($Current)
        {
            $HasYear = $True
            $Year = [System.DateTime]::Now.Year

            $HasSemester = $True
            $CurrentMonth = [System.DateTime]::Now.Month
            $CurrentSemester = $SemesterMonths.Keys | Where-Object {
                $CurrentMonth -in $SemesterMonths[$_]
            }
            $Semester = $CurrentSemester
        }
    }

    Process
    {
        ForEach($CurrentCourse in $Course)
        {
            If ($CurrentCourse -is [System.String])
            {
                $CurrentCourse = $CurrentCourse | Get-Course
            }
            $CurrentCourseId = $CurrentCourse.Id
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseId/subgroups" |
                Where-Object {
                    $_.name -match $CourseRunNamePattern
                } | ForEach-Object {
                    $Match = $CourseRunNamePattern.Match($_.name)

                    [System.Int32] $CurrentRunYear = $Match.Groups['year'].Value
                    $CurrentRunSemester = $Match.Groups['half'].Value

                    $Semester = $Semesters | Where-Object { $_ -eq $CurrentRunSemester }
                    [PSCustomObject]@{
                        Id = $_.id
                        FullName = "$CurrentRunYear-$Semester"
                        Course = $CurrentCourse.Name
                        Year = $CurrentRunYear
                        Semester = $Semester
                        Description = $_.description
                    }
                } | Where-Object {
                    $PSCmdlet.ParameterSetName -eq 'All' -or ((-not $HasYear -or $_.Year -eq $Year) -and (-not $HasSemester -or $_.Semester -eq $Semester))
                } | Sort-Object Year, { $Semesters.IndexOf($_.Semester) }
        }
    }
}

Function Sync-Milestone
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            ValueFromPipeline = $True
        )]
        [ValidateNotNull()]
        [System.Object[]] $CourseRun,

        [Parameter(
            HelpMessage = 'Only check correctness of actual milestones'
        )]
        [Switch] $CheckOnly
    )

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id
            $Schema = $CurrentCourseRun | Get-Schema

            $DefinedMilestones = $Schema.milestones | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    Description = $_.description
                    From = ($_ | Get-MilestoneStart -Schema $Schema)
                    To = ($_ | Get-MilestoneFinish -Schema $Schema)
                }
            }

            $ActualMilestones = @(Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/milestones" |
                ForEach-Object {
                    [PSCustomObject]@{
                        Id = $_.id
                        Name = $_.title
                        Description = $_.description
                        From = (Get-Date $_.start_date)
                        To = (Get-Date $_.due_date)
                    }
                })

            Compare-Object -ReferenceObject $DefinedMilestones -DifferenceObject $ActualMilestones -Property 'Name' -IncludeEqual |
                ForEach-Object {
                    $Name = $_.Name
                    Switch ($_.SideIndicator)
                    {
                        '<='
                        {
                            Write-Warning "Missing milestone '$Name'"
                            If (-not $CheckOnly)
                            {
                                $ReferenceMilestone = $DefinedMilestones | Where-Object Name -eq $Name
                                $CreateParams = @{
                                    'Post' = $True
                                    'Resource' = $Constants.Resources.Group
                                    'SubPath' = "/$CurrentCourseRunId/milestones"
                                    'Body' = @{
                                        'title' = $Name
                                        'description' = $ReferenceMilestone.Description
                                        'start_date' = (Get-Date $ReferenceMilestone.From -Format 'yyyy-MM-dd')
                                        'due_date' = (Get-Date $ReferenceMilestone.To -Format 'yyyy-MM-dd')
                                    }
                                }
                                Invoke-RemoteApi @CreateParams | ForEach-Object {
                                    Write-Verbose "Milestone # $($_.id) '$($_.title)' has been created (dates are $($_.start_date) - $($_.due_date))"
                                }
                            }
                        }

                        '=>'
                        {
                            Write-Warning "Extra milestone '$Name'"
                            If (-not $CheckOnly)
                            {
                                $DifferenceMilestone = $ActualMilestones | Where-Object Name -eq $Name
                                $DeleteParams = @{
                                    'Delete' = $True
                                    'Resource' = $Constants.Resources.Group
                                    'SubPath' = "/$CurrentCourseRunId/milestones/$($DifferenceMilestone.Id)"
                                }
                                Invoke-RemoteApi @DeleteParams
                                Write-Verbose "Milestone $Name has been deleted"
                            }
                        }

                        '=='
                        {
                            $CorrectBody = @{}
                            $ReferenceMilestone = $DefinedMilestones | Where-Object Name -eq $Name
                            $DifferenceMilestone = $ActualMilestones | Where-Object Name -eq $Name
                            If ($ReferenceMilestone.From -ne $DifferenceMilestone.From)
                            {
                                Write-Warning "Mismatch between defined and actual start of the milestone '$Name': $($ReferenceMilestone.From) != $($DifferenceMilestone.From)"
                                $CorrectBody['start_date'] = Get-Date $ReferenceMilestone.From -Format 'yyyy-MM-dd'
                            }
                            If ($ReferenceMilestone.To -ne $DifferenceMilestone.To)
                            {
                                Write-Warning "Mismatch between defined and actual finish of the milestone '$Name': $($ReferenceMilestone.To) != $($DifferenceMilestone.To)"
                                $CorrectBody['due_date'] = Get-Date $ReferenceMilestone.To -Format 'yyyy-MM-dd'
                            }
                            If ($ReferenceMilestone.Description -ne $DifferenceMilestone.Description)
                            {
                                Write-Warning "Mismatch between defined and actual description of the milestone '$Name': '$($ReferenceMilestone.Description)' != '$($DifferenceMilestone.Description)'"
                                $CorrectBody['description'] = $ReferenceMilestone.Description
                            }
                            If (-not $CheckOnly -and $CorrectBody.Count -gt 0)
                            {
                                $CorrectParams = @{
                                    'Put' = $True
                                    'Resource' = $Constants.Resources.Group
                                    'SubPath' = "/$CurrentCourseRunId/milestones/$($DifferenceMilestone.Id)"
                                    'Body' = $CorrectBody
                                }

                                Invoke-RemoteApi @CorrectParams | ForEach-Object {
                                    Write-Verbose "Milestone $Name # $($DifferenceMilestone.Id) has been corrected"
                                }
                            }
                        }
                    }
                }
        }
    }
}

Function Get-Milestone
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            ValueFromPipeline = $True
        )]
        [ValidateNotNull()]
        [System.Object[]] $CourseRun,

        [Parameter(
            HelpMessage = 'Get current milestone only'
        )]
        [Switch] $Current
    )

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id
            $Schema = $CurrentCourseRun | Get-Schema

            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/milestones" |
                ForEach-Object {
                    $Definition = $_.title | Get-MilestoneDefinition -Schema $Schema
                    [PSCustomObject]@{
                        Id = $_.id
                        Definition = $Definition
                        From = (Get-Date $_.start_date)
                        To = (Get-Date $_.due_date)
                    }
                } | Where-Object {
                    $dt = [System.DateTime]::Now.Date
                    -not $Current -or ($_.From -le $dt -and $_.To -ge $dt)
                } | Sort-Object -Property 'From'
        }
    }
}

Function Get-Group
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    Param
    (
        [Parameter(
            HelpMessage = 'A course run',
            ValueFromPipeline = $True
        )]
        [ValidateNotNull()]
        [System.Object[]] $CourseRun,

        [Parameter(
            HelpMessage = 'A name of the group',
            ParameterSetName = 'Single',
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $Name = $Null,

        [Parameter(
            HelpMessage = 'A year of matriculation',
            ParameterSetName = 'Query'
        )]
        [System.Int32] $Year,

        [Parameter(
            HelpMessage = 'A number of the group',
            ParameterSetName = 'Query'
        )]
        [System.Int32] $Number
    )

    DynamicParam
    {
        $DynamicParameterName = 'Degree'

        $Attributes = [System.Management.Automation.ParameterAttribute]::new()
        $Attributes.Mandatory = $False
        $Attributes.HelpMessage = 'A degree'
        $Attributes.ParameterSetName = 'Query'

        $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $AttributeCollection.Add($Attributes)

        $ValidateSetAttribute = [System.Management.Automation.ValidateSetAttribute]::new($Degrees.Values)
        $AttributeCollection.Add($ValidateSetAttribute)

        $Parameter = [System.Management.Automation.RuntimeDefinedParameter]::new(
            $DynamicParameterName,
            [System.String],
            $AttributeCollection
        )

        $ParametersDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $ParametersDictionary.Add($DynamicParameterName, $Parameter)

        Return $ParametersDictionary
    }

    Begin
    {
        $HasDegree = $PSBoundParameters.ContainsKey('Degree')
        $HasYear = $PSBoundParameters.ContainsKey('Year')
        $HasNumber = $PSBoundParameters.ContainsKey('Number')

        If ($HasDegree)
        {
            $Degree = $PSBoundParameters.Degree
        }
    }

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/subgroups" |
                Where-Object {
                    $_.name -match $GroupNamePattern
                } | ForEach-Object {
                    $Match = $GroupNamePattern.Match($_.name)

                    $CurrentGroupDegreeKey = $Match.Groups['level'].Value
                    [System.Int32] $CurrentGroupYearShort = $Match.Groups['year'].Value
                    $CurrentGroupYear = 2000 + $CurrentGroupYearShort
                    [System.Int32] $CurrentGroupNumber = $Match.Groups['number'].Value

                    [PSCustomObject]@{
                        Id = $_.Id
                        FullName = $_.name
                        Degree = $Degrees[$CurrentGroupDegreeKey]
                        Year = $CurrentGroupYear
                        Number = $CurrentGroupNumber
                        Description = $_.description
                    }
                } | Where-Object {
                    $Group = $_
                    Switch($PSCmdlet.ParameterSetName)
                    {
                        'All' { $True }
                        'Single' { $Group.FullName -eq $Name }
                        'Query' { (-not $HasDegree -or $Group.Degree -eq $Degree ) -and (-not $HasYear -or $Group.Year -eq $Year) -and (-not $HasNumber -or $Group.Number -eq $Number) }
                    }
                }
        }
    }
}