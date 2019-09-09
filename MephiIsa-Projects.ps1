. "$PSScriptRoot\core.ps1"

[System.Text.RegularExpressions.Regex] $ProjectNamePattern = '^(?<domain>[^\.]+)\.(?<area>.+)$'

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
                $Domain = $Match.Groups['domain'].Value | Get-Domain -Schema $Schema
                $Area = $Match.Groups['area'].Value | Get-Area -Domain $Domain
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