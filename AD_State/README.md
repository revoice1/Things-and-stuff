# M&A AD Report

- [M&A AD Report](#ma-ad-report)
  - [Requirements](#requirements)
  - [Usage](#usage)

## Requirements

1. Run script on Windows 2012 or greater
   - Required for RSAT version
2. Powershell 5.x
3. **Activedirectory** Powershell module
4. A Domain admin level account
   - This is required to report
     - Fine-grained password policies by default
     - Domain trusts
5. Network level access to query all AD domain controllers (to collect replication data)

## Usage

1. Place both ps1 files in the same directory
2. Run the "M&A Report.ps1" file with powershell
   - On a machine that meets the requirements above
   - With an account that meets the requirements above
3. An html copy of the report will be placed in the folder you are running the script from "(Domain NetBIOS name)_ad_report.html"

