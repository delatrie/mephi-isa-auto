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

Function Get-Course
{
    [CmdletBinding(DefaultParameterSetName = 'Name')]
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
        [System.Int32[]] $Id
    )

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

    $Groups = $Groups | Where-Object {
        $Null -eq $_.parent_id -and $_.name.StartsWith($Constants.CourseGroupPrefix)
    } | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.id
            Name = $_.name.Substring($Constants.CourseGroupPrefix.Length)
            Url = $_.web_url
            Description = $_.description
        }
    }

    If ($Name)
    {
        $Groups = $Groups | Where-Object {
            $_.Name -in $Name
        }
    }

    Return $Groups
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
            $CurrentCourseId = $CurrentCourse.Id
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseId/subgroups" |
                Where-Object {
                    $_.name -match $CourseRunNamePattern
                } | ForEach-Object {
                    $Match = $CourseRunNamePattern.Match($_.name)

                    [System.Int32] $CurrentRunYear = $Match.Groups['year'].Value
                    $CurrentRunSemester = $Match.Groups['half'].Value

                    [PSCustomObject]@{
                        Id = $_.id
                        Year = $CurrentRunYear
                        Semester = $Semesters | Where-Object { $_ -eq $CurrentRunSemester }
                        Description = $_.description
                    }
                } | Where-Object {
                    $PSCmdlet.ParameterSetName -eq 'All' -or ((-not $HasYear -or $_.Year -eq $Year) -and (-not $HasSemester -or $_.Semester -eq $Semester))
                } | Sort-Object Year, { $Semesters.IndexOf($_.Semester) }
        }
    }

    End
    {

    }
}