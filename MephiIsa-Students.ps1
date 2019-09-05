. "$PSScriptRoot\core.ps1"

Function Get-Student
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    Param
    (
        [Parameter(
            HelpMessage = 'A group',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Group,

        [Parameter(
            HelpMessage = 'Include students with pending access request',
            ParameterSetName = 'All'
        )]
        [Switch] $Pending,

        [Parameter(
            HelpMessage = 'Include students with approved access request',
            ParameterSetName = 'All'
        )]
        [Switch] $Granted,

        [Parameter(
            HelpMessage = 'An id of the student',
            Mandatory = $True,
            ParameterSetName = 'Id'
        )]
        [System.Int32] $Id,

        [Parameter(
            HelpMessage = 'A username of the student',
            Mandatory = $True,
            ParameterSetName = 'UserName'
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $UserName,

        [Parameter(
            HelpMessage = 'A name of the student',
            Mandatory = $True,
            ParameterSetName = 'NameQuery'
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $Name
    )

    Process
    {
        ForEach ($CurrentGroup in $Group)
        {
            $CurrentGroupId = $CurrentGroup.Id
            $GroupMembersUrl = "/$CurrentGroupId/members"
            If ($PSCmdlet.ParameterSetName -eq 'Id')
            {
                $GroupMembersUrl += "/$Id"
            }
            $GroupUsers = @(Try {
                Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath $GroupMembersUrl |
                    Where-Object {
                        $_.access_level -eq 30
                    } | ForEach-Object {
                        [PSCustomObject]@{
                            Id = $_.id
                            UserName = $_.username
                            Name = $_.Name
                            Access = 'Granted'
                            Email = $Null
                        }
                    }
            } Catch {
                If ($_.Exception -isnot [System.Net.WebException] -or $_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound)
                {
                    Throw
                }
            })
            $GroupAccessRequests = @(Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentGroupId/access_requests" |
                ForEach-Object {
                    [PSCustomObject]@{
                        Id = $_.id
                        UserName = $_.username
                        Name = $_.Name
                        Access = 'Pending'
                        Email = $Null
                    }
                })

            ($GroupUsers + $GroupAccessRequests) | Where-Object {
                $Student = $_
                Switch ($PSCmdlet.ParameterSetName)
                {
                    'All'       { (-not $Pending -or $Student.Access -eq 'Pending') -and (-not $Granted -or $Student.Access -eq 'Granted') }
                    'Id'        { $Student.Id -eq $Id  }
                    'UserName'  { $Student.UserName -eq $UserName }
                    'NameQuery' { $Student.Name -match $Name }
                }
            } | ForEach-Object {
                $StudentId = $_.Id
                $UserInfo = Invoke-RemoteApi -Resource $Constants.Resources.User -SubPath "/$StudentId"
                $_.Email = $UserInfo.public_email
                $_
            }
        }
    }
}

Function Grant-StudentAccess
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of a course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A group, the student reqeust access to',
            Mandatory = $True
        )]
        [System.Object] $Group,

        [Parameter(
            HelpMessage = 'A user to grant the access',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Student
    )

    Begin
    {
        $GroupId = $Group.Id
        $ExpirationDate = Switch ($CourseRun.Semester) {
            'Spring' { "$($CourseRun.Year)-08-31" }
            'Autumn' { "$($CourseRun.Year + 1)-02-10" }
            Default  { Throw "Unknown semester '$_'" }
        }
    }

    Process
    {
        ForEach ($CurrentStudent in $Student)
        {
            $StudentId = $CurrentStudent.Id
            $Result = Invoke-RemoteApi -Method PUT -Resource $Constants.Resources.Group -SubPath "/$GroupId/access_requests/$StudentId/approve"
            If (-not $Result -or $Result.access_level -ne 30)
            {
                Throw "Cannot approve access request of $StudentId to $GroupId"
            }
            $Result = Invoke-RemoteApi -Method PUT -Resource $Constants.Resources.Group -SubPath "/$GroupId/members/$StudentId" -Attributes @{
                'access_level' = 30
                'expires_at'   = $ExpirationDate
            }
            If (-not $Result -or (Get-Date -Date $Result.expires_at).ToString('yyyy-MM-dd') -ne $ExpirationDate)
            {
                Throw "Cannot set up expiration datetime of member $StudentId in $GroupId"
            }
            $Group | Get-Student -Id $StudentId
        }
    }
}

Function Deny-StudentAccess
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of a course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A group, the student reqeust access to',
            Mandatory = $True
        )]
        [System.Object] $Group,

        [Parameter(
            HelpMessage = 'A student to deny the access',
            Mandatory = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Student
    )

    Begin
    {
        $GroupId = $Group.Id
    }

    Process
    {
        ForEach ($CurrentStudent in $Student)
        {
            $StudentId = $CurrentStudent.Id
            Invoke-RemoteApi -Method DELETE -Resource $Constants.Resources.Group -SubPath "/$GroupId/access_requests/$StudentId"
        }
    }
}