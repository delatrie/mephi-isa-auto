. "$PSScriptRoot\core.ps1"

Function Get-Student
{
    [CmdletBinding(DefaultParameterSetName = 'All')]
    Param
    (
        [Parameter(
            HelpMessage       = 'A group',
            Mandatory         = $True,
            ValueFromPipeline = $True
        )]
        [System.Object[]] $Group,

        [Parameter(
            HelpMessage      = 'Include students with pending access request',
            ParameterSetName = 'All'
        )]
        [Switch] $Pending,

        [Parameter(
            HelpMessage      = 'Include students with approved access request',
            ParameterSetName = 'All'
        )]
        [Switch] $Granted,

        [Parameter(
            HelpMessage      = 'An id of the student',
            Mandatory        = $True,
            ParameterSetName = 'Id'
        )]
        [System.Int32] $Id,

        [Parameter(
            HelpMessage      = 'A username of the student',
            Mandatory        = $True,
            ParameterSetName = 'UserName'
        )]
        [ValidateNotNullOrEmpty()]
        [System.String] $UserName,

        [Parameter(
            HelpMessage      = 'A name of the student',
            Mandatory        = $True,
            ParameterSetName = 'NameQuery',
            Position         = 0
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
                        $_.access_level -eq $Constants.AccessLevels.Developer
                    } | ForEach-Object {
                        [PSCustomObject]@{
                            Id       = $_.id
                            UserName = $_.username
                            Name     = $_.Name
                            Access   = 'Granted'
                            Email    = $Null
                        }
                    }
            } Catch {
                If ($_.Exception -isnot [Microsoft.PowerShell.Commands.HttpResponseException] -or $_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound)
                {
                    Throw
                }
            })
            $GroupAccessRequests = @(Invoke-RemoteApi -Resource $Constants.Resources.Group -SubPath "/$CurrentGroupId/access_requests" |
                ForEach-Object {
                    [PSCustomObject]@{
                        Id       = $_.id
                        UserName = $_.username
                        Name     = $_.Name
                        Access   = 'Pending'
                        Email    = $Null
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
                $UserInfo  = Invoke-RemoteApi -Resource $Constants.Resources.User -SubPath "/$StudentId"
                $_.Email   = $UserInfo.public_email
                Write-Output $_
            }
        }
    }
}

Function Grant-StudentAccess
{
    [CmdletBinding(DefaultParameterSetName = 'UserName')]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of a course',
            Mandatory   = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A group, the student reqeust access to',
            Mandatory   = $True
        )]
        [System.Object] $Group,

        [Parameter(
            HelpMessage       = 'A user to grant the access',
            Mandatory         = $True,
            ValueFromPipeline = $True,
            ParameterSetName  = 'Instance'
        )]
        [System.Object[]] $Student,

        [Parameter(
            HelpMessage       = 'An id of the user to grant the access',
            Mandatory         = $True,
            ValueFromPipeline = $True,
            ParameterSetName  = 'Id'
        )]
        [System.Int32[]] $StudentId,

        [Parameter(
            HelpMessage                     = 'A username of the user to grant the access',
            Mandatory                       = $True,
            ValueFromPipeline               = $True,
            ValueFromPipelineByPropertyName = $True,
            ParameterSetName                = 'UserName'
        )]
        [System.String[]] $UserName
    )

    Begin
    {
        $GroupId = $Group.Id
        $ExpirationDate = Get-ExpirationDate -CourseRun $CourseRun
    }

    Process
    {
        $Collection = Switch($PSCmdlet.ParameterSetName)
        {
            'Id'       { $StudentId }
            'Instance' { $Student   }
            'UserName' { $UserName  }
        }

        ForEach ($Item in $Collection)
        {
            $CurrentStudentId = Switch ($PSCmdlet.ParameterSetName)
            {
                'Id'       { $Item }
                'Instance' { $Item.Id }
                'UserName' { Get-StudentId -UserName $Item }
            }
            If ($Null -ne $CurrentStudentId)
            {
                $CurrentStudent = $Group | Get-Student -Id $CurrentStudentId
                If ($Null -eq $CurrentStudent)
                {
                    Write-Verbose "Granting the student with id #$CurrentStudentId the access to the group $($Group.FullName)..."
                    $Result = Invoke-RemoteApi -Post -Resource $Constants.Resources.Group -SubPath "/$GroupId/members" -Body @{
                        'user_id'      = $CurrentStudentId
                        'access_level' = $Constants.AccessLevels.Developer
                        'expires_at'   = $ExpirationDate.ToString('yyyy-MM-dd')
                    }
                    If (-not $Result -or $Result.access_level -ne $Constants.AccessLevels.Developer)
                    {
                        Throw "Cannot grant student #$CurrentStudentId the access to group #$GroupId"
                    }
                    $Group | Get-Student -Id $CurrentStudentId
                }
                ElseIf ($CurrentStudent.Access -eq 'Granted')
                {
                    Write-Verbose "$($CurrentStudent.Name) ($($CurrentStudent.UserName)) already has the access to the group $($Group.FullName)"
                    Write-Output $CurrentStudent
                }
                Else
                {
                    Write-Verbose "Accepting the access request of $($CurrentStudent.Name) ($($CurrentStudent.UserName)) to the group $($Group.FullName)..."
                    $Result = Invoke-RemoteApi -Put -Resource $Constants.Resources.Group -SubPath "/$GroupId/access_requests/$CurrentStudentId/approve"
                    If (-not $Result -or $Result.access_level -ne $Constants.AccessLevels.Developer)
                    {
                        Throw "Cannot approve access request of $CurrentStudentId to $GroupId"
                    }

                    $Result = Invoke-RemoteApi -Put -Resource $Constants.Resources.Group -SubPath "/$GroupId/members/$CurrentStudentId" -Attributes @{
                        'access_level' = $Constants.AccessLevels.Developer
                        'expires_at'   = $ExpirationDate.ToString('yyyy-MM-dd')
                    }
                    If (-not $Result -or (Get-Date -Date $Result.expires_at) -ne $ExpirationDate)
                    {
                        Throw "Cannot set up expiration datetime of member $CurrentStudentId in $GroupId. The student appears to have the access to the group for unlimited amount of time"
                    }
                    $Group | Get-Student -Id $CurrentStudentId
                }
            }
        }
    }
}

Function Deny-StudentAccess
{
    [CmdletBinding(DefaultParameterSetName = 'UserName')]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of the course',
            Mandatory   = $True
        )]
        [System.Object] $CourseRun,

        [Parameter(
            HelpMessage = 'A group, to remove the student from',
            Mandatory   = $True
        )]
        [System.Object] $Group,

        [Parameter(
            HelpMessage       = 'A student to exclude from the group',
            Mandatory         = $True,
            ValueFromPipeline = $True,
            ParameterSetName  = 'Instance'
        )]
        [System.Object[]] $Student,

        [Parameter(
            HelpMessage       = 'An id of the student to exclude from the group',
            Mandatory         = $True,
            ValueFromPipeline = $True,
            ParameterSetName  = 'Id'
        )]
        [System.Int32[]] $StudentId,

        [Parameter(
            HelpMessage                     = 'A username of the student to exclude from the group',
            Mandatory                       = $True,
            ValueFromPipeline               = $True,
            ValueFromPipelineByPropertyName = $True,
            ParameterSetName                = 'UserName'
        )]
        [System.String[]] $UserName
    )

    Begin
    {
        $GroupId = $Group.Id
    }

    Process
    {
        $Collection = Switch($PSCmdlet.ParameterSetName)
        {
            'Id'       { $StudentId }
            'Instance' { $Student   }
            'UserName' { $UserName  }
        }
        ForEach ($Item in $Collection)
        {
            $CurrentStudentId = Switch ($PSCmdlet.ParameterSetName)
            {
                'Id'       { $Item }
                'Instance' { $Item.Id }
                'UserName' { Get-StudentId -UserName $Item }
            }
            If ($Null -ne $CurrentStudentId)
            {
                $CurrentStudent = $Group | Get-Student -Id $CurrentStudentId
                If ($Null -eq $CurrentStudent)
                {
                    Write-Verbose "The student with id #$CurrentStudentId does not have the access to the group $($Group.FullName)"
                }
                ElseIf ($CurrentStudent.Access -eq 'Pending')
                {
                    Write-Verbose "Declining the access request of $($CurrentStudent.Name) ($($CurrentStudent.UserName)) to the group $($Group.FullName)..."
                    Invoke-RemoteApi -Delete -Resource $Constants.Resources.Group -SubPath "/$GroupId/access_requests/$CurrentStudentId"
                }
                Else
                {
                    Write-Verbose "Removing $($CurrentStudent.Name) ($($CurrentStudent.UserName)) from the group $($Group.FullName)..."
                    Invoke-RemoteApi -Delete -Resource $Constants.Resources.Group -SubPath "/$GroupId/members/$CurrentStudentId"
                }
            }
        }
    }
}

Function Get-ExpirationDate
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A run of a course',
            Mandatory = $True
        )]
        [System.Object] $CourseRun
    )

    Get-Date ($CourseRun | Get-Schema).end
}

Function Get-StudentId
{
    [CmdletBinding()]
    Param
    (
        [Parameter(
            HelpMessage = 'A login of the student',
            Mandatory = $True
        )]
        [System.String] $UserName
    )

    $Result = Invoke-RemoteApi -Resource $Constants.Resources.User -Attributes @{
        'username' = $UserName
    } -ErrorVariable 'ApiError'

    If (-not $ApiError)
    {
        If (-not $Result)
        {
            Write-Error "No gitlab account matched the username '$UserName'"
        }
        Else
        {
            $Result.id
        }
    }
}