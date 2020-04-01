<#
    .SYNOPSIS
    Relatively simple script to terminate a user in AD
    .DESCRIPTION
    The script attempts to:
        Find the user in AD
        Disable the user
        Randomize the password
        Log and remove the users group memberships
        Log and remove the users manager
        Move the user into the DisableUserOU
        Disable the user in google via GAM
    .PARAMETER GamEXE
    Windows path to the GAM Executable, this needs to be set up for your google environment beforehand
    .PARAMETER DisabledUserOU
    DN of the OU where you would like to move your terminated users
    .PARAMETER WorkingDir
    Working dir for the script, to output the logfile etc..
    Defaults to the current path the script is running from
    .PARAMETER TargetUsername
    Define a username to term in single-user mode
    .PARAMETER TermReportPath
    Define a windows filepath to a report that contains users to term in multi-user mode
    .PARAMETER UsernameAttribute
    The CSV header of the column that holds usernames/samaccountnames in the Term Report in multi-user mode
    .EXAMPLE
    # Run single-user and prompt for username
    &".\simple term.ps1" 
    .EXAMPLE
    #  Run single-user without username prompt
    &".\simple term.ps1" -TargetUsername rvoice
    .EXAMPLE
    # Run multi-user
    &".\simple term.ps1" -TermReportPath C:\Temp\Terms.csv -UsernameAttribute Username -Confirm:$False
#>
#Requires -version 3
#Requires -Modules ActiveDirectory

[CmdletBinding(DefaultParameterSetName = "SingleUser", SupportsShouldProcess)] 
param (
    $GamEXE = "C:\GAM64\gam.exe", # Path to GAM exe
    $DisabledUserOU = "OU=Disabled Users,DN=internal,DN=domain,dc=com", # DN of the DisabledUsers OU
    $WorkingDir = $(Split-Path $MyInvocation.MyCommand.path -Parent), # where the script is running from by default
    [Parameter(ParameterSetName = "SingleUser")]
    $TargetUsername = "",
    [Parameter(ParameterSetName = "MultiUser")]
    $TermReportPath = $null, # Path to Term Report CSV
    [Parameter(ParameterSetName = "MultiUser")]
    $UsernameAttribute = "Username"
)

$ReportOutputPath = "$WorkingDir\TermLog_$(Get-Date -format yyyy-MM-dd_hh.mm.ss).log" # Log Path

if ($TermReportPath) {
    # User Report CSV
    $UsersToTerm = $(Import-Csv $TermReportPath).$UsernameAttribute
}
elseif ($TargetUsername) {
    $UsersToTerm = $TargetUsername
}
else {
    $UsersToTerm = $(Read-Host "Enter SamAccountName of user to Term")
}

$LogData = @()

$ProcessGoogle = Test-Path $GamEXE
if (!$ProcessGoogle) {
    $NewLogData = "Warning: GamEXE not found, google terms will not be processed"
    Write-Output $NewLogData
    $LogData += $NewLogData
}

foreach ($UserToTerm in $UsersToTerm) {
    $NewLogData = "Info: Evaluating $($UserToTerm)"
    Write-Output $NewLogData
    $LogData += $NewLogData

    # Find the user in AD
    try {
        $ADUserObj = Get-ADUser $($UserToTerm) -Properties memberof, mail, manager -ErrorAction Stop
    }
    catch {
        $NewLogData = "Error: $($UserToTerm) was not found in AD"
        Write-Output $NewLogData
        $LogData += $NewLogData

        continue
    }
    if ($ConfirmPreference) { 
        do { 
            Write-Output "Is $($ADUserObj.Name) the correct user?"
            $Answer = Read-Host "yes or no" 
            if (($Answer -notlike "yes") -and ($answer -notlike "no")) {
                Write-Warning "please only input yes or no"
            }
        } 
        until ("yes", "no" -contains $answer)
        
        if ($Answer.ToLower() -eq "no") {
            $NewLogData = "Warning: Wrong user $UsersToTerm, skipping"
            Write-Output $NewLogData
            $LogData += $NewLogData
            continue
        }
    }

    # Disable the user
    if ($PSCmdlet.ShouldProcess("Disable AD Account: $UsersToTerm")) {
        $ADUserObj | Disable-ADAccount -Verbose
    }
    
    $NewLogData = "Info: $($UserToTerm) Pre-Termination Group Membership"
    Write-Output $NewLogData
    $LogData += $NewLogData

    $NewLogData = "`t$($ADUserObj.memberof -join "`n`t")"
    Write-Output $NewLogData
    $LogData += $NewLogData

    if ($PSCmdlet.ShouldProcess("Remove Group Membership: $UsersToTerm")) {
        $ADUserObj.memberof | Remove-ADGroupMember -Members $ADUserObj.DistinguishedName -Confirm:$false    
    }

    # Generate a random password
    $RandomPassword = ([char[]](Get-Random -Input $(48..57) -Count 5)) # Numbers
    $RandomPassword += ([char[]](Get-Random -Input $(65..90) -Count 5)) # UPPERCASE
    $RandomPassword += ([char[]](Get-Random -Input $(97..122) -Count 5)) # lowercase
    $RandomPassword = $RandomPassword -join ""
    $RandomPasswordSS = $RandomPassword | ConvertTo-SecureString -AsPlainText -Force

    # Set the password
    if ($PSCmdlet.ShouldProcess("Randomize Password: $UsersToTerm")) {
        $ADUserObj | Set-ADAccountPassword -NewPassword $RandomPasswordSS -Verbose
    }
    
    $NewLogData = "Info: $($UserToTerm) Pre-Termination Manager: $($ADUserObj.manager)"
    Write-Output $NewLogData
    $LogData += $NewLogData

    # Clear Manager
    if ($PSCmdlet.ShouldProcess("Move AD user: $UsersToTerm")) {
        $ADUserObj | Set-ADUser -Manager $null -Verbose
    }

    # Move the User
    if ($PSCmdlet.ShouldProcess("Move AD user: $UsersToTerm")) {
        Move-ADObject -Identity $ADUserObj.DistinguishedName -TargetPath $DisabledUserOU  -Verbose
    }

    $NewLogData = "Info: Attempting to gam suspend"
    Write-Output $NewLogData
    $LogData += $NewLogData

    if ($ProcessGoogle) {
        try {
            $ErrorActionPreference = "Stop"
            if ($PSCmdlet.ShouldProcess("Disable Google Account: $($ADUserObj.mail)")) {
                $command = &$GamEXE update user $($ADUserObj.mail) suspended on
            }
            $ErrorActionPreference = "Continue"
        }
        catch {
            $NewLogData = "Error: gam suspend failed - $_.message"
            Write-Output $NewLogData
            $LogData += $NewLogData
            $ErrorActionPreference = "Continue"
        }
    }

    $NewLogData = "Info: $($UserToTerm) Term Complete`n"
    Write-Output $NewLogData
    $LogData += $NewLogData
}

# Output the log file
$LogData | Out-File $ReportOutputPath -Verbose -WhatIf:$false

if ($host.name -eq "ConsoleHost") {
    Read-Host "Press enter to exit"
}
