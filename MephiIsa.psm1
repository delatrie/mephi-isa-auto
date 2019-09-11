[CmdletBinding()]
Param
(
    [Parameter()]
    [ValidateNotNull()]
    [Hashtable] $Parameters = @{}
)

. "$PSScriptRoot\MephiIsa-PersonalToken.ps1"
. "$PSScriptRoot\MephiIsa-CourseStructure.ps1"
. "$PSScriptRoot\MephiIsa-Students.ps1"
. "$PSScriptRoot\MephiIsa-Projects.ps1"
. "$PSScriptRoot\MephiIsa-Assignments.ps1"

Export-ModuleMember -Function @(
    'Update-PersonalToken'
    'Remove-PersonalToken'

    'Get-Course'
    'Get-CourseRun'
    'Get-Group'

    'Get-Milestone'
    'Sync-Milestone'

    'Get-Student'
    'Grant-StudentAccess'
    'Deny-StudentAccess'

    'Get-Project'
    'Sync-Project'

    'New-AssignmentMap'
    'Set-Assignment'
    'Remove-Assignment'
)