# Requirements for the script, PS 3 might actually work, but it's untested.
#Requires -Version 5.0
#Requires -Modules @{ ModuleName="ActiveDirectory"; ModuleVersion="1.0.0.0" }

$ReportPath = $(Split-Path $MyInvocation.MyCommand.path -Parent) # Path to where the report should be output
$ReportOutputPath = "$ReportPath\$($Env:USERDOMAIN)_AD_Report.html" # Path to where the report file will output

[float]$MinimumSupportedWindowsVersion = 6.2 # Minimum version of windows supported by Microsoft, 6.2 = 2012/8
[int]$LastLogonCutoff = 120 # The number of days we want to check last logon for to consider an object valid

# Array of groups to report on membership of
[array]$AdminGroups = "Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators", "Group Policy Creator Owners", "DNSAdmins", "Cert Publishers", "Account Operators", "Server Operators", "Backup Operators", "Print Operators"
[int]$ReplicationThreshold = 60 # AD DC healthy replication threshold, in minutes

# Check the AD module to make sure it has the required cmdlets
# We have to do this because 2008 and 2012 AD modules have the same version number 1.0.0.0
# ...but have different cmdlets :Shrug:
$ADModule = Get-Module -Name ActiveDirectory -ListAvailable
$CMDLetCheck = $ADModule.ExportedCmdlets["Get-ADReplicationSite"]
if (!$CMDLetCheck) {
    throw "Module ActiveDirectory does not have the required commands, please use a Windows 2012 or newer system."
}

# Check for the Functions script
# If it doesn't exist, error out
try {
    $WorkingDIr = Split-Path $MyInvocation.MyCommand.path -Parent
    $FunctionFilePath = "$($WorkingDIr)\AD_State_Functions.ps1"
    Import-Module $FunctionFilePath -Force
}
catch {
    Throw "Function module not found"
}

# CSS Data for the HTML Report
$ReportCSS = @"
<style>
BODY{background-color:white;font-family:consolas;font-size:9pt;color:black;}
TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH{border-width: 1px;padding: 3px;padding-right: 5px;padding-left: 5px;border-style: solid;border-color: white;background-color:black;color:white;}
TD{border-width: 1px;padding-right: 5px;padding-left: 5px;padding-top: 2px;padding-bottom: 2px;border-style: solid;border-color: black;background-color: white;}
</style>
"@

# Report runtime data
$ReportHeader = [PSCustomObject]@{
    "Report Generated Date" = "$(Get-Date)"
    "Report Generated On"   = $env:COMPUTERNAME
    "Report User"           = "$($Env:USERDOMAIN)\$($Env:USERNAME)"
}

# Gather all report data
$BaseADReport = Get-BaseADReport -Verbose -LastLogonCutoff $LastLogonCutoff
$ReplicationIssueReport = Get-ADReplicationIssueReport -Verbose -ReplicationThreshold $ReplicationThreshold
$ADSiteReport = Get-ADSiteReport -Verbose
$ADBackupReport = Get-ADBackupReport -Verbose
$UnsupportedComputerReport = Get-UnSupportedComputerReport -Verbose -MinimumSupportedWindowsVersion $MinimumSupportedWindowsVersion -LastLogonCutoff $LastLogonCutoff
$AdminGroupReport = Get-AdminGroupReport -Verbose -AdminGroups $AdminGroups
$PKIObjectReport = Get-PKiTemplateReport
$GPOReport = Get-TopLevelGPOReport -Verbose

# Construct the Report
$ReportData = @()
$ReportData += $ReportCSS
$ReportData += "Domain State Report: $Env:USERDOMAIN" | Get-HTMLCode -Header -Level 1
$ReportData += $ReportHeader | Get-HTMLCode -HTList
$ReportData += $BaseADReport
$ReportData += "Unsupported OS Report" | Get-HTMLCode -Header -Level 2
$ReportData += $UnsupportedComputerReport | ConvertTo-Html -Fragment
$ReportData += "Domain Backup Report" | Get-HTMLCode -Header -Level 2
$ReportData += $ADBackupReport | ConvertTo-Html -Fragment
$ReportData += "AD Site Report" | Get-HTMLCode -Header -Level 2
$ReportData += $ADSiteReport | ConvertTo-Html -Fragment
$ReportData += "Domain Replication Report" | Get-HTMLCode -Header -Level 2
$ReportData += $ReplicationIssueReport | ConvertTo-Html -Fragment
$ReportData += "Admin Group Report" | Get-HTMLCode -Header -Level 2
$ReportData += $AdminGroupReport | ConvertTo-Html -Fragment
$ReportData += $PKIObjectReport
$ReportData += $GPOReport

# Output the report
$ReportData | Out-File -FilePath $ReportOutputPath -Verbose
