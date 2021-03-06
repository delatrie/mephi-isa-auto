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
. "$PSScriptRoot\MephiIsa-Teachers.ps1"
. "$PSScriptRoot\MephiIsa-Projects.ps1"
. "$PSScriptRoot\MephiIsa-Assignments.ps1"
. "$PSScriptRoot\MephiIsa-Interaction.ps1"

Export-ModuleMember -Function @(
    'Select-Item'

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

    'Get-Teacher'

    'Get-Project'
    'Sync-Project'

    'Get-Assignment'
    'New-AssignmentMap'
    'Set-Assignment'
    'Remove-Assignment'
)