. "$PSScriptRoot\core.ps1"

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
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentCourseRunId/projects"
        }
    }
}