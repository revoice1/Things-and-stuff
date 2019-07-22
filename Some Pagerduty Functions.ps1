Function Find-PagerDutyUser {
    <#
    .SYNOPSIS
    Find a pagerduty user and return data based on email or PD ID

    .PARAMETER APIToken
    API Token with at least user read access

    .PARAMETER UsertoFind
    The e-mail address, partial email address or PD ID of the user

    .PARAMETER DoNotBackpJson
    Switch to supress json user data backp creation

    .PARAMETER JsonBackupPath
    Optional parameter to specify the location of the json user data file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$APIToken,
        [Parameter(Mandatory = $true)]
        [string]$UsertoFind,
        [Switch]$DoNotBackpJson,
        [string]$JsonBackupPath = ".\temp\PDUserBackup.json"
    )

    $BaseEndpoint = "https://api.pagerduty.com/"
    $AuthHeader = @{ Authorization = "Token token=$($APIToken)" }

    $FindUserSplat = @{
        Headers = $AuthHeader
        Method  = "Get"
        URI     = "$BaseEndpoint/users?query=$([System.Web.HttpUtility]::UrlEncode($UsertoFind))"
    }

    $FindUserResult = (Invoke-RestMethod @FindUserSplat).users
    $ResultUserCount = $FindUserResult.Count

    # If we found users
    if ($ResultUserCount) {
        # PD query is always a wildcard query, if we return more than one result
        if ($ResultUserCount -gt 1) {
            # Check for exact match
            $Exactmatch = $FindUserResult | Where-Object { $_.email -eq $UsertoFind }
            # If no exact match, throw a warning
            if ($Exactmatch.count -ne 1) {
                Write-Warning "More than one user returned, are you sure your input is correct?"
                $FindUserResult | Select-Object name, email, id | Format-Table
            }
            else {
                $FindUserResult = $Exactmatch
            }
        }
        else {
            # If one match
            if (!$DoNotBackpJson) {
                # Export the User Json in case it's deleted on accident
                $FindUserResult | ConvertTo-Json | Out-File $JsonBackupPath -Append
            }
            # Return the found user data
            return $FindUserResult
        }
    }
    else {
        # Throw an error if no users found
        throw "No User Found"
    }
}

Function Remove-PagerDutyUser {
    <#
    .SYNOPSIS
    Remove a user from Pagerduty

    .PARAMETER APIToken
    API Token with at least user read/delete/disable access

    .PARAMETER PDUserEmail
    The e-mail address of the user

    .PARAMETER PDUserID
    The PD User ID of the user

    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$APIToken,
        [Parameter(Mandatory = $true, ParameterSetName = "UserID")]
        [string]$PDUserID,
        [Parameter(Mandatory = $true, ParameterSetName = "Email")]
        [string]$PDUserEmail
    )

    # If an e-mail was specified instead of a PD User ID, find the ID
    if ($PDUserEmail) {
        $PDUserID = (Find-PagerDutyUser -APIToken $APIToken -UsertoFind $PDUserEmail).ID
    }

    $BaseEndpoint = "https://api.pagerduty.com/"
    $AuthHeader = @{ Authorization = "Token token=$($APIToken)" }

    $PDUserToDelete | Select-Object name, email, id | Format-List
    "Removing user with PagerDuty ID: $PDUserID"

    $DeleteUserSplat = @{
        Headers = $AuthHeader
        Method  = "Delete"
        URI     = "$BaseEndpoint/users/$($PDUserID)"
    }

    try {
        Invoke-RestMethod @DeleteUserSplat
    }
    catch {
        $_.Exception
        ($_.ErrorDetails.Message | ConvertFrom-Json).error | Format-List
    }
    
}

# Remove-PagerdutyUser -PDUserEmail "adalberto.ryan@example.com" -APIToken "y_NbAkKc66ryYTWUXYEu"
