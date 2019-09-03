[CmdletBinding()]
Param
(
    [Parameter()]
    [ValidateNotNull()]
    [Hashtable] $Parameters = @{}
)

. "$PSScriptRoot\MephiIsa-PersonalToken.ps1"
. "$PSScriptRoot\MephiIsa-CourseStructure.ps1"

Export-ModuleMember -Function @(
    'Update-PersonalToken'
    'Remove-PersonalToken'
    'Get-Course'
    'Get-CourseRun'
)