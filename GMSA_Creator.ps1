$GMSAName = "GMSAToDoThings" # Name of GMSA Object
$GMSADescription = "A GMSA account to do things" # Description for GMSA Object

$PrincipalsGroup = "GMSA_Allowed_$($GMSAName)" # Group name for Allowed Principals Group (The group that is allowed to use the account password)
$Principals = "$($ENV:COMPUTERNAME)$" # List of machines to add to the allowed principals group

$ADLocation = "CN=Managed Service Accounts,DC=YOUR,DC=DOMAIN,DC=com" # Directory location for GMSA and Principals Group

$PermissionGroups = "permission_group" # Additional groups to add the GMSA account to (for job permissions)

# Task VARs
$TaskName = "GMSA_Scheduled_Task_Name $($GMSAName)" # Name of the scheduled task
$TaskAction = New-ScheduledTaskAction -Execute PowerShell.exe -Argument "-Command `"& { .\Script`` Name_With_Escaped_Space.ps1 -ScriptParamater -AnotherOne }`"" -WorkingDirectory "D:\scripts\"
$TaskTrigger = New-ScheduledTaskTrigger -Daily -At "8/14/2020 4:00 PM"
$TaskPrincipal = New-ScheduledTaskPrincipal -UserId "$GMSAName$" -LogonType Password
$TaskSettings = New-ScheduledTaskSettingsSet

# If the principals group doesn't already exist, create it
Try {
    Get-ADGroup $PrincipalsGroup
}
catch {
    Write-Output "Creating Group: $($PrincipalsGroup) in $($ADLocation)"
    New-ADGroup -Name $PrincipalsGroup -DisplayName $PrincipalsGroup -GroupScope Global -GroupCategory Security -Description "Allowed principals for AD GMSA $GMSAName" -Path $ADLocation
}

# Add listed principals to principals group
Write-Output "Adding Group Member: $($Principals) to $($PrincipalsGroup)"
Add-ADGroupMember -Identity $PrincipalsGroup -Members $Principals

# Create GMSA
Write-Output "Creating GMSA: $($GMSAName) in $($ADLocation)"
New-ADServiceAccount -Name $GMSAName `
    -DNSHostName "$GMSAName.$($env:USERDNSDOMAIN)" `
    -AccountNotDelegated $true `
    -Description $GMSADescription `
    -ManagedPasswordIntervalInDays 15 `
    -PrincipalsAllowedToRetrieveManagedPassword $PrincipalsGroup `
    -TrustedForDelegation $false `
    -KerberosEncryptionType AES128, AES256 `
    -Path $ADLocation

# Add GMSA to perm groups
foreach ($PermissionsGroup in $PermissionGroups) {
    Write-Output "Adding Group Member: $($GMSAName) to $($PermissionsGroup)"
    Add-ADGroupMember -Identity $PermissionsGroup -Members "$($GMSAName)$"
}

Write-Output "Clearing system kerberos tokens and waiting for GMSA permission"
$Loop = 0
do {
    klist purge -li 0x3e7 | Out-Null
    Try {
        $Test = Test-ADServiceAccount -Identity $GMSAName
    }
    catch {
        $Test = $false
        Start-Sleep 5
    }
    $Loop++
}
until(($Test) -OR ($Loop -ge 10))

if ($Test) {
    Write-Output "Registering Scheduled Task"
    $Try = 0
    do {
        $Try++
        Try {
            Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings 
            $TaskSuccess = $True
        }
        catch {
            $TaskSuccess = $False
            Write-Output "Error creating task, waiting 5 seconds. This can happen when the job is created too quickly"
            Write-Output "Try $($Try) of 10"
            Start-Sleep 5
        }
    }
    until(($TaskSuccess) -or ($Try -ge 10))
    if (-Not($TaskSuccess)) {
        Write-Error "Error creating scheduled task"
    }
}
else {
    Write-Error "Something Went Wrong, could not verify GMSA permission on local machine. Verify this machine has been added to principals group"
}
