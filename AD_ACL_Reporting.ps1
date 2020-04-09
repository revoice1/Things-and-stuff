$TargetPrincipals = "Group or username"

foreach ($TargetPrincipal in $TargetPrincipals) {
    $Reportpath = "C:\temp\$($TargetPrincipal)-permission-report.csv"

    $TargetPrincipal = "$env:USERDOMAIN\$TargetPrincipal"

    $ADOUs = Get-ADOrganizationalUnit -Filter * -Properties nTSecurityDescriptor, CanonicalName

    $PermReport = @()

    $SchemaNamingContext = Get-ADObject -Filter { objectclass -eq "classschema" } -SearchBase (Get-ADRootDSE).schemanamingcontext -Properties schemaidguid
    $SchemaNamingContextHT = @{ }
    foreach ($SchemaNamingContextItem in $SchemaNamingContext) {
        $SchemaNamingContextHT += @{([System.GUID]$SchemaNamingContextItem.schemaidguid).ToString() = $SchemaNamingContextItem.name }
    }

    $RightsNamingContext = Get-ADObject -Filter { objectclass -eq "controlAccessRight" } -SearchBase (Get-ADRootDSE).ConfigurationNamingContext  -Properties RightsGuid
    foreach ($RightsNamingContextItem in $RightsNamingContext) {
        if ($SchemaNamingContextHT[([System.GUID]$RightsNamingContextItem.RightsGuid).ToString()]) {
            continue
        }
        $SchemaNamingContextHT += @{([System.GUID]$RightsNamingContextItem.RightsGuid).ToString() = $RightsNamingContextItem.name }
    }

    foreach ($OU in $ADOUs) {
        $OU.Distinguishedname

        $PermReportProperties = @{
            Property = @(
                #@{Name = "OU_DN"; Expression = { $OU.Distinguishedname } }
                @{Name = "OU_CN"; Expression = { $OU.CanonicalName } }
                "IdentityReference"
                "ActiveDirectoryRights"
                @{
                    Name       = "ObjectTypeRes"
                    Expression = { 
                        if ($SchemaNamingContextHT[$_.ObjectType.Guid]) {
                            $SchemaNamingContextHT[$_.ObjectType.Guid]
                        }
                        elseif ($_.ObjectType -match "^(?>0+-?){5}$") {
                            ""
                        }
                        else {
                            $_.ObjectType 
                        }
                        
                    } 
                }
            
                @{Name         = "InheritedObjectTypeRes"
                    Expression = { 
                        if ($SchemaNamingContextHT[$_.InheritedObjectType.Guid]) {
                            $SchemaNamingContextHT[$_.InheritedObjectType.Guid]
                    
                        }
                        elseif ($_.InheritedObjectType -match "^(?>0+-?){5}$") {
                            ""
                        }
                        else {
                            $_.InheritedObjectType 
                        }
                    
                    } 
                }
                "AccessControlType"
                "IsInherited"
                "InheritanceType"
                "PropagationFlags"
            )
        }


        $ACLs = $OU.nTSecurityDescriptor.access | Where-Object { $_.IdentityReference -eq $TargetPrincipal } 
        $PermReport += $ACLs | Select-Object @PermReportProperties
    }
    $PermReport = $PermReport | Sort-Object OU_CN
    $PermReport | Export-Csv $Reportpath -NoTypeInformation -Delimiter ";"
    $PermReport | Format-Table
}
