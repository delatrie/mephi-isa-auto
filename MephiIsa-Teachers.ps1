. "$PSScriptRoot\core.ps1"

Function Get-Teacher
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $CourseRun,

        [Parameter(
            HelpMessage = 'Get only a record corresponding to yourself'
        )]
        [Switch] $Me
    )

    Begin
    {
        If ($Me)
        {
            $MyId = (Invoke-RemoteApi -Resource $Constants.Resources.Me).id
        }
    }

    Process
    {
        ForEach ($CurrentCourseRun in $CourseRun)
        {
            $CurrentCourseRunId = $CurrentCourseRun.Id
            $Url = "/$CurrentCourseRunId/members/"
            $Url += If ($Me) { $MyId } Else { 'all' }
            Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath $Url |
                Where-Object {
                    $_.access_level -eq $Constants.AccessLevels.Owner
                } | ForEach-Object {
                    [PSCustomObject]@{
                        Id       = $_.id
                        Name     = $_.Name
                        UserName = $_.username
                    }
                }
        }
    }
}