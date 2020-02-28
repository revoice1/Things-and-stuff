Function Get-ADReplicationIssueReport {
    [cmdletbinding()]
    param(
        $ReplicationThreshold = 60
    )

    Write-Verbose "Collecting AD Replication Issues"

    # Gather list of ALL DCs
    $AllDomainControllers = Get-ADDomainController -Filter *

    $AllReplicationData = @()
    foreach ($DomainController in $AllDomainControllers) {
        Write-Verbose "Attempting to collect data from $($DomainController.Name)"
        $ConnectionTest = Test-Connection $DomainController -Quiet -Count 1
        if ($ConnectionTest) {
            $ConnectionTest = Test-NetConnection $DomainController -Port 9389
        }

        if ($ConnectionTest.TcpTestSucceeded) {
            $ADReplicationData = Get-ADReplicationPartnerMetadata -Target $DomainController.name -Partition *
            $AllReplicationData += $ADReplicationData
        }
        else {
            Write-Warning "$($DomainController.name) is not currently connectable"
            $AllReplicationData += [PSCustomObject]@{
                Server    = $DomainController.Name
                IssueType = "!Not Connectable"
            }
        }
    }

    [int]$ReplicationThreshold = 60
    $ADReplicationReport = @()
    foreach ($Result in $AllReplicationData) {
        $ResultIssueType = @()

        if ($Result.IssueType) {
            $ResultIssueType = $Result.IssueType
        }
        else {
            if ($Result.ConsecutiveReplicationFailures -gt 0 ) {
                $ResultIssueType = "Consecutive Failures"
            }
            elseif ( $Result.LastReplicationResult -ne 0 ) {
                $ResultIssueType = "Last Replication Result"
            }
            elseif ($Result.LastReplicationSuccess -lt $((Get-Date).AddMinutes(-$ReplicationThreshold))) {
                $ResultIssueType = "Recent Replication Older than $($ReplicationThreshold) Minutes"
            }
            else {
                $ResultIssueType = "Healthy"
            }
        }


        if ($ResultIssueType) {
            $ADReplicationReport += [pscustomobject]@{
                Server                         = $Result.Server.toupper().split(".")[0]
                Partner                        = $Result.Partner -replace 'CN=NTDS Settings,CN=([a-zA-Z0-9\-]*).*', '$1'
                Partition                      = switch -regex ($Result.Partition) {
                    "^CN=Configuration,.*" { "Configuration" }
                    "^CN=Schema,.*" { "Schema" }
                    "^DC=.*" { "Domain" }
                    default { $Result.Partition }
                }
                ConsecutiveReplicationFailures = $Result.ConsecutiveReplicationFailures
                LastReplicationResult          = $Result.LastReplicationResult
                LastReplicationAttempt         = $Result.LastReplicationAttempt
                LastReplicationSuccess         = $Result.LastReplicationSuccess
                IssueType                      = $ResultIssueType
            }
        }
    }

    RETURN $ADReplicationReport | Sort-Object -Property IssueType, Server, Partner, Partition
}

function Get-ADSiteReport {
    [cmdletbinding()]
    param()
    Write-Verbose "Collecting AD Site information"
    $ADSiteReport = @()

    $AllADSites = Get-ADReplicationSite -Filter *
    $AllADSiteLinks = Get-ADReplicationSiteLink -Filter *
    $AllADSiteSubnets = Get-ADReplicationSubnet -Filter *
    $AllADDomainControllers = Get-ADDomainController -Filter *

    foreach ($ADSite in $AllADSites) {
        $ConnectableDCs = @()
        $NonConnectableDCs = @()
        $SiteName = $ADSite.Name
        $SiteDN = $ADSite.DistinguishedName

        $SiteSubnets = $AllADSiteSubnets | Where-Object { $_.Site -eq $SiteDN }
        $SiteLinks = $AllADSiteLinks | Where-Object { $_.SitesIncluded -contains $SiteDN }

        $SiteDCs = $AllADDomainControllers | Where-Object { $_.Site -eq $SiteName }
        foreach ($DC in $SiteDCs) {
            $DCConnectionTest = Test-Connection $DC -Quiet -Count 1
            if ($DCConnectionTest) {
                $ConnectableDCs += $DC
            }
            else {
                $NonConnectableDCs += $DC
            }
        }
        $ADSiteReport += [psCustomObject]@{
            SiteName                   = $SiteName
            Subnets                    = $($SiteSubnets.name) -join ", "
            SiteLinks                  = $SiteLinks.name -join ", "
            "Number of DCs"            = @($SiteDCs).Count
            "Connectable Site DCs"     = $ConnectableDCs.name -join ", "
            "Non-Connectable Site DCs" = $NonConnectableDCs.name -join ", "
        }
    }
    return $ADSiteReport
}

function Get-ADBackupReport {
    [cmdletbinding()]
    param()

    Write-Verbose "Collecting AD backup information"
    $MyDC = Get-ADDomainController
    $DomainBackupReport = @()
    $RootDSE = Get-ADRootDSE
    foreach ($Partition in $RootDSE.namingContexts) {
        $PartitionDSASignature = Get-ADReplicationAttributeMetadata -Object $Partition -Properties DSASignature -Server $MyDC.Name
        $DomainBackupReport += [PSCustomObject]@{
            Partition  = $Partition
            LastBackup = $PartitionDSASignature.LastOriginatingChangeTime
        }
    }
    return $DomainBackupReport
}

function Get-UnSupportedComputerReport {
    [cmdletbinding()]
    param(
        [float]$MinimumSupportedWindowsVersion = 6.2,
        $LastLogonCutoff = 120
    )

    Write-Verbose "Collecting information on unsupported OS's bound to the domain"
    $UnSupportedOSTable = @()

    $LastLogonCutoffDate = (Get-Date).AddDays(-$LastLogonCutoff)
    $AllComputers = Get-ADComputer -Filter * -properties LastLogonDate, OperatingSystem, OperatingSystemVersion

    $AllUnsupportedComputers = $AllComputers | Where-Object { $null -ne $_.OperatingSystemVersion } | Where-Object {
        if ($_.OperatingSystem -like "*Windows*") {
            $OSVersionNumber = $_.OperatingSystemVersion.split(" ")[0]
            $OSVersionNumberSplit = $OSVersionNumber.split(".")
            [float]$MajorAndMinorVersion = $OSVersionNumberSplit[0], $OSVersionNumberSplit[1] -join "."

            $MajorAndMinorVersion -lt $MinimumSupportedWindowsVersion
        }
        else {
            $false
        }
    }
    if ($AllUnsupportedComputers) {
        $UnSupportedOSNames = $AllUnsupportedComputers.OperatingSystem | Select-Object -Unique
        Foreach ($UnSupportedOSName in $UnSupportedOSNames) {
            $OSType = if ($UnSupportedOSName -like "*Server*") {
                "Server"
            }
            else {
                "Client"
            }
            $UnSupportedOSMachines = $AllUnsupportedComputers | Where-Object { $_.OperatingSystem -eq $UnSupportedOSName }
            $UnSupportedOSTable += [PSCustomObject] @{
                Type                                        = $OSType
                OS                                          = $UnSupportedOSName
                Enabled                                     = [int]@($UnSupportedOSMachines | Where-Object { $_.enabled }).count
                Disabled                                    = [int]@($UnSupportedOSMachines | Where-Object { !$_.enabled }).count
                Total                                       = [int]@($UnSupportedOSMachines).count
                "Logged on Within $($LastLogonCutoff) Days" = [int]@($UnSupportedOSMachines | Where-Object { $_.LastLogonDate -ge $LastLogonCutoffDate }).Count
            }
        }
    }
    return $UnSupportedOSTable | Sort-Object -Property Type, OS
}

function Get-AdminGroupReport {
    [cmdletbinding()]
    param(
        [array]$AdminGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators", "Group Policy Creator Owners", "DNSAdmins", "Cert Publishers", "Account Operators", "Server Operators", "Backup Operators", "Print Operators")
    )

    Write-Verbose "Collecting membership information for admin groups"

    $AdminGroupReport = @()
    foreach ($AdminGroup in $AdminGroups) {
        Write-Verbose "Processing $AdminGroup"
        $MemberDetail = @()
        $ADGroupObj = Get-ADGroup $AdminGroup -Properties members
        $ADObjs = $ADGroupObj.members | Get-ADObject

        foreach ($ADObj in $ADObjs) {
            if ($ADObj.ObjectClass -match "(user|computer)") {
                switch ($ADObj.ObjectClass) {
                    "User" { $AdUser = $ADObj | Get-ADUser }
                    "Computer" { $AdUser = $ADObj | Get-ADComputer }
                }
                $MemberDetail += [pscustomobject]@{
                    MemberType = "Member"
                    Member     = $AdUser.samaccountname
                    Enabled    = $AdUser.Enabled
                }
            }
            else {
                $MemberDetail += [pscustomobject]@{
                    MemberType = "Group"
                    Member     = $ADObj.name
                    Enabled    = "N/A"
                }
            }
        }

        $AdminGroupReport += [PSCustomObject]@{
            Group        = $AdminGroup
            MemberCount  = @($MemberDetail).count
            NestedGroups = ($MemberDetail | Where-Object { $_.MemberType -eq "Group" }).Member -join ", "
            MemberDetail = ($MemberDetail | Where-Object { $_.MemberType -eq "Member" }).Member -join ", "
            #MemberDetailHT = $MemberDetail
        }
    }
    return $AdminGroupReport
}

function Get-BaseADReport {
    [cmdletbinding()]
    param(
        $LastLogonCutoff = 120
    )

    Write-Verbose "Gathering base AD Domain/Forest Info"
    $ADBaseReport = @()

    $DomainInfo = Get-ADDomain
    $ForestInfo = Get-ADForest
    $DomainCreationDate = (Get-ADObject $($DomainInfo.DistinguishedName) -Properties created).created
    $ADRecyclingBinInfo = Get-ADOptionalFeature -Filter { name -eq "Recycle Bin Feature" }
    $ADRecyclingBinScopes = $ADRecyclingBinInfo.EnabledScopes -join ", "

    $AdminUsername = (New-Object System.Security.Principal.SecurityIdentifier ("$($DomainInfo.DomainSID)-500")).Translate([System.Security.Principal.NTAccount]).Value
    $AdminUserEnabled = (Get-ADUser -Identity $($AdminUsername.Split("\")[1])).enabled
    $GuestUsername = (New-Object System.Security.Principal.SecurityIdentifier ("$($DomainInfo.DomainSID)-501")).Translate([System.Security.Principal.NTAccount]).Value
    $GuestUserEnabled = (Get-ADUser -Identity $($GuestUsername.Split("\")[1])).enabled

    $FSMORoles = [PSCustomObject]@{
        DomainNamingMaster   = $ForestInfo.DomainNamingMaster
        SchemaMaster         = $ForestInfo.SchemaMaster
        InfrastructureMaster = $DomainInfo.InfrastructureMaster
        PDCEmulator          = $DomainInfo.PDCEmulator
        RIDMaster            = $DomainInfo.RIDMaster
    }

    Write-Verbose "Gathering AD trust Info"
    $TrustInfo = Get-ADTrust -Filter *
    $TrustCount = @($TrustInfo).count
    $TrustReport = $TrustInfo | Select-Object Name, Direction, DisallowTransivity, ForestTransitive, SelectiveAuthentication, TrustAttributes, TrustType

    $DomainAttrs = @(
        "Name"
        @{
            Name       = "Domain Created"
            Expression = { $DomainCreationDate }
        }
        "DNSRoot"
        "DistinguishedName"
        "NetBiosName"
        "DomainMode"
        "ComputersContainer"
        "DomainControllersContainer"
        "SystemsContainer"
        "UsersContainer"
        "ChildDomainsDomainSID"
        @{
            Name       = "Administrator Name"
            Expression = { $AdminUsername }
        }
        @{
            Name       = "Administrator User Enabled"
            Expression = { $AdminUserEnabled }
        }
        @{
            Name       = "Guest Name"
            Expression = { $GuestUsername }
        }
        @{
            Name       = "Guest User Enabled"
            Expression = { $GuestUserEnabled }
        }
        @{
            Name       = "Last KRBTGT Password Reset"
            Expression = { (Get-ADUser krbtgt -Properties PasswordLastSet).PasswordLastSet }
        }
        @{
            Name       = "AD Recycling Bin Scopes Enabled"
            Expression = { $ADRecyclingBinScopes }
        }
    )

    $ADBaseReport += "Forest Info" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += $ForestInfo | Select-Object Name, ForestMode, RootDomain | Get-HTMLCode -HTList
    $ADBaseReport += "Domain Info" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += $DomainInfo | Select-Object -Property $DomainAttrs | Get-HTMLCode -HTList
    $ADBaseReport += "FSMO Roles" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += $FSMORoles | Get-HTMLCode -HTList
    $ADBaseReport += "Password Policies" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += "Default Domain Password Policy" | Get-HTMLCode -Header -Level 3
    $ADBaseReport += Get-ADDefaultDomainPasswordPolicy | Select-Object ComplexityEnabled, MinPasswordLength, LockoutDuration, LockoutObservationWindow, LockoutThreshold, MinPasswordAge, MaxPasswordAge, PasswordHistoryCount, ReversibleEncryptionEnabled | Get-HTMLCode -HTList

    $ADBaseReport += "Fine Grained Password Policy" | Get-HTMLCode -Header -Level 3
    $FineGrainPasswordPolicies = Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, @{Name = "AppliedTo"; Expression = { ($_.AppliesTo | Get-ADObject).name -join ", " } }, Precedence, ComplexityEnabled, MinPasswordLength, LockoutDuration, LockoutObservationWindow, LockoutThreshold, MinPasswordAge, MaxPasswordAge, PasswordHistoryCount, ReversibleEncryptionEnabled
    if ($FineGrainPasswordPolicies) {
        $ADBaseReport += $FineGrainPasswordPolicies | Sort-Object -Property Precedence | ConvertTo-Html -Fragment
    }
    else {
        $ADBaseReport += "N/A"
    }

    $ADBaseReport += "AD Trusts" | Get-HTMLCode -Header -Level 2
    if ($TrustReport) {
        $ADBaseReport += "Trusts Found: $($TrustCount)"
        $ADBaseReport += $TrustReport | ConvertTo-Html -Fragment
    }
    else {
        $ADBaseReport += "N/A"
    }

    Write-Verbose "Gathering AD user Info"
    $AllADUsers = Get-ADUser -Filter * -Properties SamAccountName, SID, SIDHistory, GivenName, Surname, UserPrincipalName, Description, Enabled, Created, AllowReversiblePasswordEncryption, DoesNotRequirePreAuth, SmartcardLogonRequired, CannotChangePassword, PasswordNeverExpires, PasswordNotRequired, AccountExpirationDate, PasswordLastSet, PasswordExpired, LastLogonDate, BadLogonCount, LastBadPasswordAttempt, LockedOut, AccountLockoutTime, adminCount, TrustedForDelegation, ServicePrincipalName
    $AllADUserCount = @($AllADUsers).count
    $EnabledADUsers = $AllADUsers | Where-Object { $_.enabled }
    $EnabledADUsersCount = @($EnabledADUsers).count
    $DisabledADUsers = $AllADUsers | Where-Object { !$_.enabled }
    $DisabledADUsersCount = @($DisabledADUsers).count

    $UserReport = [PSCustomObject]@{
        "Total AD Users"                               = @($AllADUsers).count
        "- LoggedOn Within Cutoff Period"              = $( $value = @($AllADUsers | Where-Object { $_.LastLogonDate -ge $((Get-Date).AddDays(-$LastLogonCutoff)) }).count; $Percent = [math]::Round($value / $AllADuserCount * 100) ; "$value ($Percent%)" )
        "- Disabled Users"                             = $( $value = $DisabledADUsersCount; $Percent = [math]::Round($value / $AllADuserCount * 100) ; "$value ($Percent%)" )
        "  - Locked Out (Disabled)"                    = $( $value = @($DisabledADUsers | Where-Object { $_.LockedOut }).count; $Percent = [math]::Round($value / $DisabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - LoggedOn Within Cutoff Period (Disabled)" = $( $value = @($DisabledADUsers | Where-Object { $_.LastLogonDate -ge $((Get-Date).AddDays(-$LastLogonCutoff)) }).count; $Percent = [math]::Round($value / $DisabledADUsersCount * 100) ; "$value ($Percent%)" )
        "- Enabled Users"                              = $( $value = $EnabledADUsersCount; $Percent = [math]::Round($value / $AllADuserCount * 100) ; "$value ($Percent%)" )
        "  - No Password Expiration"                   = $( $value = @($EnabledADUsers | Where-Object { $_.PasswordNeverExpires }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Reversible pwd allowed"                   = $( $value = @($EnabledADUsers | Where-Object { $_.AllowReversiblePasswordEncryption }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - No pre-authentication"                    = $( $value = @($EnabledADUsers | Where-Object { $_.DoesNotRequirePreAuth }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - SmartCard not required"                   = $( $value = @($EnabledADUsers | Where-Object { !$_.SmartcardLogonRequired }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - User cannot change pwd"                   = $( $value = @($EnabledADUsers | Where-Object { $_.CannotChangePassword }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Password never expires"                   = $( $value = @($EnabledADUsers | Where-Object { $_.PasswordNeverExpires }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Password not required"                    = $( $value = @($EnabledADUsers | Where-Object { $_.PasswordNotRequired }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - AdminCount bit is set"                    = $( $value = @($EnabledADUsers | Where-Object { $_.adminCount -gt 0 }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Trusted for delegation"                   = $( $value = @($EnabledADUsers | Where-Object { $_.TrustedForDelegation }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - ServicePrincipalName set"                 = $( $value = @($EnabledADUsers | Where-Object { $_.ServicePrincipalName }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - SIDHistory defined"                       = $( $value = @($EnabledADUsers | Where-Object { $_.SIDHistory }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - No LastLogonDate"                         = $( $value = @($EnabledADUsers | Where-Object { !$_.LastLogonDate }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Password Expired"                         = $( $value = @($EnabledADUsers | Where-Object { $_.PasswordExpired }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - Locked Out (Enabled)"                     = $( $value = @($EnabledADUsers | Where-Object { $_.LockedOut }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
        "  - LoggedOn Within Cutoff Period (Enabled)"  = $( $value = @($EnabledADUsers | Where-Object { $_.LastLogonDate -ge $((Get-Date).AddDays(-$LastLogonCutoff)) }).count; $Percent = [math]::Round($value / $EnabledADUsersCount * 100) ; "$value ($Percent%)" )
    }
    $ADBaseReport += "AD User Report" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += $UserReport | Get-HTMLCode -HTList

    Write-Verbose "Gathering AD Computer Info"
    $AllADComputers = Get-ADComputer -Filter * -Properties LastLogonDate, OperatingSystem
    $CutoffADComputers = $AllADComputers | Where-Object { $_.LastLogonDate -ge $((Get-Date).AddDays(-$LastLogonCutoff)) }
    $ComputersReport = [PSCustomObject]@{
        "Total Computer Count"                         = @($AllADComputers).Count
        " - Enabled Computer Count"                    = $( $value = @($AllADComputers | Where-Object { $_.enabled }).Count; $Percent = $Percent = [math]::Round($value / @($AllADComputers).Count * 100); "$value ($Percent%)" )
        " - Disabled Computer Count"                   = $( $value = @($AllADComputers | Where-Object { !$_.enabled }).Count; $Percent = $Percent = [math]::Round($value / @($AllADComputers).Count * 100); "$value ($Percent%)" )
        " - Logged On Within $($LastLogonCutoff) Days" = $( $value = @($CutoffADComputers | Where-Object { $_.LastLogonDate -ge $((Get-Date).AddDays(-$LastLogonCutoff)) }).count; $Percent = $Percent = [math]::Round($value / @($AllADComputers).Count * 100); "$value ($Percent%)" )
    }

    $AllOSReport = $AllADComputers | Group-Object -Property OperatingSystem | Sort-Object -Property Name | Select-Object Name, Count
    $CutoffOSReport = $CutoffADComputers | Group-Object -Property OperatingSystem | Sort-Object -Property Name | Select-Object Name, Count

    $AllOSReport += [PSCustomObject]@{Name = "- Total"; Count = ($AllOSReport | Measure-Object -Sum -Property count).Sum }
    $CutoffOSReport += [PSCustomObject]@{Name = "- Total"; Count = ($CutoffOSReport | Measure-Object -Sum -Property count).Sum }

    $ADBaseReport += "AD Computer Report" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += "Total Computer Report" | Get-HTMLCode -Header -Level 3
    $ADBaseReport += $ComputersReport | Get-HTMLCode -HTList
    $ADBaseReport += "Total Computer OS Report" | Get-HTMLCode -Header -Level 3
    $ADBaseReport += Get-HTMLCode -HTList -ConvertToPSCustomObject -InputObject $AllOSReport
    $ADBaseReport += "OS logged on within last $($LastLogonCutoff) days Report" | Get-HTMLCode -Header -Level 3
    $ADBaseReport += Get-HTMLCode -HTList -ConvertToPSCustomObject -InputObject $CutoffOSReport
    
    Write-Verbose "Gathering AD Domain Controller Info"
    $AllDomainControllers = Get-ADDomainController -Filter *
    $AllDomainControllerReport = $AllDomainControllers | Select-Object  hostname, @{N = "LastLogonDate"; E = { (Get-ADComputer $_.name -Properties LastLogonDate).LastLogonDate } }, site, enabled, ipv4address, isglobalcatalog, isreadonly, operatingsystem | Sort-Object -Property Site, LastLogonDate, hostname
    $AllDomainControllerStats = [PSCustomObject]@{
        "Total Domain Controllers"                      = @($AllDomainControllerReport).count
        "- Logged in within $($LastLogonCutoff) days"     = @($AllDomainControllerReport | Where-Object { $_.LastLogonDate -ge $(Get-Date).adddays(-$LastLogonCutoff) }).count
        "- Not logged in within $($LastLogonCutoff) days" = @($AllDomainControllerReport | Where-Object { $_.LastLogonDate -ge $(Get-Date).adddays(-$LastLogonCutoff) }).count
    }
    $ADBaseReport += "Domain Controller Info" | Get-HTMLCode -Header -Level 2
    $ADBaseReport += Get-HTMLCode -HTList -InputObject $AllDomainControllerStats
    $ADBaseReport += $AllDomainControllerReport | ConvertTo-Html -Fragment

    return $ADBaseReport

}

function Get-TopLevelGPOReport {
    [cmdletbinding()]
    param()

    Write-Verbose "Gathering GPO report for top level linked GPO's, Default Domain Policy and Default Domain Controllers policy"

    $HTMLReportData = @()
    $HTMLReportData += Get-HTMLCode -InputObject "GPO Report" -Header -Level 1

    $DefaultDomainControllersGUID = "{6ac1786c-016f-11d2-945f-00c04fb984f9}"
    $DefaultDomainGUID = "{31B2F340-016D-11D2-945F-00C04FB984F9}"
    $MyDC = Get-ADDomainController

    $AllGPOReport = Get-GPOReport -All -ReportType Xml -Server $MyDC
    $TotalObjects = ([xml]$AllGPOReport).GPOS.GPO.Count
    $LinkedObjects = (([xml]$AllGPOReport).GPOS.GPO | Where-Object { $_.linksto.SOMPath })
    $DisabledLinkedObjects = $LinkedObjects | Where-Object { $_.linksto.enabled -eq "false" }

    $TopLevelLinkedGUIDs = @()
    $TopLevelLinkedGUIDs += $($LinkedObjects | Where-Object { $_.linksto.SOMPath -eq $MyDC.Domain -and $_.linksto.Enabled }).identifier.identifier."#text"
    if ($TopLevelLinkedGUIDs -contains $DefaultDomainGUID) {
        $TopLevelLinkedGUIDs += $DefaultDomainControllersGUID
    }
    else {
        $TopLevelLinkedGUIDs += $DefaultDomainGUID, $DefaultDomainControllersGUID
    }

    $HTMLReportData += Get-HTMLCode -InputObject "GPO numbers" -Header -Level 3
    $HTMLReportData += [PSCustomObject]@{
        "Total Policy Objects"    = $TotalObjects
        "Linked Objects"          = @($LinkedObjects).Count
        "Disabled Linked Objects" = @($DisabledLinkedObjects).Count
    } | Get-HTMLCode -HTList

    $LinkedObjectTable = @()
    foreach ($LinkedObject in $LinkedObjects) {
        $PolicyLinks = $LinkedObject.linksto
        foreach ($PolicyLink in $PolicyLinks) {
            $LinkedObjectTable += [PSCustomObject]@{
                "Policy GUID"   = $LinkedObject.identifier.identifier."#text"
                "Policy Name"   = $LinkedObject.Name
                "Linked"        = $PolicyLink.SOMPath
                "Link Enabled"  = $PolicyLink.enabled
                "Link Enforced" = $PolicyLink.NoOverride
            }
        }
    }

    $HTMLReportData += Get-HTMLCode -InputObject "GPO Link Report" -Header -Level 3
    $HTMLReportData += $LinkedObjectTable | Sort-Object -Property Linked, "Policy Name" | ConvertTo-Html -Fragment

    $HTMLReportData += Get-HTMLCode -InputObject "TOP Level GPO Settings" -Header -Level 3
    foreach ($GUID in $TopLevelLinkedGUIDs) {
        $HTMLReportData += Get-GPOReport -ReportType HTML -Server $MyDC -Guid $GUID
    }

    return $HTMLReportData

}

function Get-HTMLCode {
    [OutputType('System.String')]
    [cmdletbinding()]
    param (
        [Parameter(Position = 0, Mandatory = $True, ValueFromPipeline = $true)]
        $InputObject,
        [Parameter(ParameterSetName = "List")]
        [switch]$HTList,
        [Parameter(ParameterSetName = "List")]
        [switch]$ConvertToPSCustomObject,
        [Parameter(ParameterSetName = "Header")]
        [switch]$Header,
        [Parameter(Mandatory = $true, ParameterSetName = "Header")]
        [int]$Level
    )

    $HTMLOut = "<pre>"

    if (!$InputObject) {
        return
    }
    if ($HTList) {
        if ($ConvertToPSCustomObject) {
            $NewInputObject = @()
            foreach ($Object in $InputObject) {
                $Name = "$(@($Object.psobject.Properties)[0].Value)"
                $Value = "$(@($Object.psobject.Properties)[1].Value)"
                if ($Null -like $Name) {
                    $Name = "`$NULL"
                }
                $NewInputObject += [PSCustomObject]@{
                    $Name = $Value
                }
            }
            $InputObject = $NewInputObject
        }
        $TopType = $InputObject.gettype()
        if ($TopType.BaseType.name -eq "Array") {
            foreach ($Object in $InputObject) {
                $Properties = $Object.psobject.Properties
                foreach ($Property in $Properties) {
                    $PropertyName = $Property.Name
                    $NameLength = $PropertyName.length
                    if ($NameLength -gt $MaxNameLength) {
                        $MaxNameLength = $NameLength
                    }
                }
            }
            $MaxNameLength++
            foreach ($Object in $InputObject) {
                $Properties = $Object.psobject.Properties
                foreach ($Property in $Properties) {
                    $HTMLOut += "<b>$(($Property.Name).padright($MaxNameLength))</b>: $($Property.Value)<br />"
                }
            }
        }
        else {
            $Properties = $InputObject.psobject.Properties
            foreach ($Property in $Properties) {
                $PropertyName = $Property.Name
                $NameLength = $PropertyName.length
                if ($NameLength -gt $MaxNameLength) {
                    $MaxNameLength = $NameLength
                }
            }
            $MaxNameLength++
            foreach ($Property in $Properties) {
                $HTMLOut += "<b>$(($Property.Name).padright($MaxNameLength))</b>: $($Property.Value)<br />"
            }
        }
        $HTMLOut += "</pre>"
    }

    if ($Header) {
        $HeaderTag = "h$($level)"
        $HTMLOut = "<$HeaderTag>$InputObject</$HeaderTag>"
    }
    return $HTMLOut
}

function Get-PKiTemplateReport {
    [cmdletbinding()]
    param ()

    Write-Verbose "Gathering PKI Template Information"

    $ConfigurationDN = (Get-ADRootDSE).configurationNamingContext
    $CertTemplateDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$($ConfigurationDN)"
    $EnrollmentServicesDN = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$($ConfigurationDN)"

    $TemplateData = Get-ADObject -SearchBase $CertTemplateDN -Filter { ObjectClass -eq "pKICertificateTemplate" } -Properties *
    $EnrollmentServiceData = Get-ADObject -SearchBase $EnrollmentServicesDN -Filter { ObjectClass -eq "pKIEnrollmentService" } -Properties *

    $CAProperties = @(
        "DisplayName"
        "dNSHostName"
        @{
            Name       = "Reachable"
            Expression = {
                $CAPingResult = certutil -ping -config $_.dNSHostName
                if ($CAPingResult[1] -match "interface is alive") {
                    $True
                }
                else {
                    $false
                }
            }
        }
        "Created"
        "Modified"
        @{
            Name       = "Cert Issuer"
            Expression = { "$(([System.Security.Cryptography.X509Certificates.X509Certificate2]$_.cACertificate.Value).Issuer)" }
        }
        @{
            Name       = "Cert Expires"
            Expression = { "$(([System.Security.Cryptography.X509Certificates.X509Certificate2]$_.cACertificate.Value).notafter)" }
        }
    )

    $EnrollmentServiceDataReport = $EnrollmentServiceData | Select-Object $CAProperties

    $ActiveTemplateReport = @()
    $InactiveTemplateReport = @()

    foreach ($Template in $TemplateData) {
        $TemplateName = $Template.name

        $InUse = [bool]($EnrollmentServiceData.certificatetemplates -contains $TemplateName)

        $KeyUsageResolved = foreach ($OID in $Template.pKIExtendedKeyUsage) {
            $(New-Object Security.Cryptography.Oid $OID).FriendlyName
        }
        $KeyUsage = $KeyUsageResolved -join ", "

        $StartLifetime = [datetime]::FromFileTime("0")
        $EndLifetime = [datetime]::FromFileTime(
            [System.BitConverter]::ToInt64($Template.pKIExpirationPeriod, 0) * -1
        )
        $MaxLifetimeDays = (New-TimeSpan -Start $StartLifetime -End $EndLifetime).TotalDays

        if ($InUse) {
            $PresentedOn = ($EnrollmentServiceData | Where-Object { $_.certificatetemplates -contains $TemplateName }).dNSHostName.replace(".internal.salesforce.com", "") -join ", "
            $ActiveTemplateReport += [PSCustomObject]@{
                TemplateName    = $TemplateName
                InUse           = $InUse
                PresentedOn     = $PresentedOn
                MaxLifetimeDays = $MaxLifetimeDays
                KeyUsage        = $KeyUsage
                Created         = $Template.Created
                Modified        = $Template.Modified
            }
        }
        else {
            $InactiveTemplateReport += [PSCustomObject]@{
                TemplateName    = $TemplateName
                InUse           = $InUse
                PresentedOn     = "N/A"
                MaxLifetimeDays = $MaxLifetimeDays
                KeyUsage        = $KeyUsage
                Created         = $Template.Created
                Modified        = $Template.Modified
            }
        }

    }

    $PKIReport = @()
    $PKIReport += Get-HTMLCode -Header -InputObject "PKI Object Report" -Level 2
    $PKIReport += Get-HTMLCode -Header -InputObject "CA Report" -Level 3
    $PKIReport += $EnrollmentServiceDataReport | ConvertTo-Html -Fragment
    $PKIReport += Get-HTMLCode -Header -InputObject "Assigned Template Report" -Level 3
    $PKIReport += $ActiveTemplateReport = $ActiveTemplateReport | Sort-Object -Property TemplateName | ConvertTo-Html -Fragment
    $PKIReport += Get-HTMLCode -Header -InputObject "Unassigned Template Report" -Level 3
    $PKIReport += $InactiveTemplateReport = $InactiveTemplateReport | Sort-Object -Property TemplateName | ConvertTo-Html -Fragment
    return $PKIReport

}

function Get-DHCPReport {
    [cmdletbinding()]
    param ()

    $AuthorizedDHCPServers = Get-DhcpServerInDC

    $NotConnectable = @()

    foreach ($AuthorizedDHCPServer in $AuthorizedDHCPServers) {
        $AuthorizedDHCPServer.DnsName
        $ConnectionTest = Test-Connection -ComputerName $AuthorizedDHCPServer.DnsName -Quiet -Count 1
        if ($ConnectionTest) {
            try {
                "$($AuthorizedDHCPServer.DnsName) Collection"
                $v4Scopes = Get-DhcpServerv4Scope -ComputerName $AuthorizedDHCPServer.DnsName
                $v4ScopeStats = Get-DhcpServerv4ScopeStatistics -ComputerName $AuthorizedDHCPServer.DnsName
                $v6Scopes = Get-DhcpServerv6Scope -ComputerName $AuthorizedDHCPServer.DnsName
                $v6ScopeStats = Get-DhcpServerv6ScopeStatistics -ComputerName $AuthorizedDHCPServer.DnsName
            }
            catch {
                "$($AuthorizedDHCPServer.DnsName) Collection Failed"
                $NotConnectable += $AuthorizedDHCPServer
            }
        }
        else {
            "$($AuthorizedDHCPServer.DnsName) Connection Failed"
            $NotConnectable += $AuthorizedDHCPServer
        }

    }

}
