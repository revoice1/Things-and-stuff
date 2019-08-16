Function Invoke-GPOSettingCheck {
    [cmdletbinding()]
    param(
        [ValidateSet("Screen", "File")]
        [array]$OutputPreference = "Screen",
        [string]$Filepath = $(Split-Path -parent $PSCommandPath)

    )

    Write-Verbose "Collecting all GPO info"
    $AllGPOs = Get-GPO -All

    $GPONotLinked = @()
    $GPOClean = @()
    $GPOUserSettingsNotDefinedEnabled = @()
    $GPOUserSettingsDefinedNotEnabled = @()
    $GPOComputerSettingsNotDefinedEnabled = @()
    $GPOComputerSettingsDefinedNotEnabled = @()


    foreach ($objGPO in $AllGPOs) {

        if ($VerbosePreference) {
            ""
        }

        Write-Verbose "Evaluating $($objGPO.DisplayName)"
        $Clean = $true
        $GPOXML = [xml]( Get-GPO -Guid $objGPO.id | Get-GPOReport -ReportType xml )  

        if (!$GPOXML.GPO.LinksTo) {
            $GPONotLinked += $objGPO
            Write-Verbose "Policy Not Linked"
            continue
        }

        $UserSettingsEnabled = [bool]$GPOXML.GPO.User.Enabled
        $ComputerSettingsEnabled = [bool]$GPOXML.GPO.Computer.Enabled

        $UserSettingsDefined = $GPOXML.GPO.User.ExtensionData
        $ComputerSettingsDefined = $GPOXML.GPO.Computer.ExtensionData

        if ((!$UserSettingsDefined) -and $UserSettingsEnabled) {
            $GPOUserSettingsNotDefinedEnabled += $objGPO
            Write-Verbose "User Settings are Enabled but None are Defined"
            $Clean = $false
        }
        elseif ($UserSettingsDefined -and (!$UserSettingsEnabled)) {
            $GPOUserSettingsDefinedNotEnabled += $objGPO
            Write-Verbose "User Settings are Defined but Not Enabled!"
            $Clean = $false
        }

        if ((!$ComputerSettingsDefined) -and $ComputerSettingsEnabled) {
            $GPOComputerSettingsNotDefinedEnabled += $objGPO
            Write-Verbose "Computer Settings are Enabled but None are Defined"
            $Clean = $false
        }
        elseif ($ComputerSettingsDefined -and (!$ComputerSettingsEnabled)) {
            $GPOComputerSettingsDefinedNotEnabled += $objGPO
            Write-Verbose "Computer Settings are Defined but None are Enabled!"
            $Clean = $false
        }

        if ($Clean) {
            $GPOClean += $objGPO
            Write-Verbose "All Good"
        }

    }

    if ($OutputPreference) {
        $report = @(
            if ($GPONotLinked) {
                "Unlinked GPOs:"
                $GPONotLinked.DisplayName
                ""
            }
            if ($GPOClean) {
                "Clean GPOs:"
                $GPOClean.DisplayName
                ""
            }
            if ($GPOUserSettingsNotDefinedEnabled) {
                "GPOs With No User Settings Defined, But User Scope Enabled:"
                "Recommended Action - Disable User Scope"
                $GPOUserSettingsNotDefinedEnabled.DisplayName
                ""
            }
            if ($GPOUserSettingsDefinedNotEnabled) {
                "GPOs With No User Settings Enabled, But User Scope Defined:"
                "Recommended Action - Enable User Scope"
                $GPOUserSettingsDefinedNotEnabled.DisplayName
                ""
            }
            if ($GPOComputerSettingsNotDefinedEnabled) {
                "GPOs With No Computer Settings Defined, But User Scope Enabled:"
                "Recommended Action - Disable Computer Scope"
                $GPOComputerSettingsNotDefinedEnabled.DisplayName
                ""
            }
            if ($GPOComputerSettingsDefinedNotEnabled) {
                "GPOs With No Computer Settings Enabled, But User Scope Defined:"
                "Recommended Action - Enable Computer Scope"
                $GPOComputerSettingsDefinedNotEnabled.DisplayName
                ""
            }
        )

        if ($OutputPreference -contains "Screen") {
            $report
        }
        if ($OutputPreference -contains "File") {
            $OutputPath = "$Filepath\GPO_Autit_Report.log"
            Write-Verbose "Outputting Report to $($OutputPath)"

            $report | Out-File $OutputPath
        }
    }
}

Invoke-GPOSettingCheck -OutputPreference Screen, File
