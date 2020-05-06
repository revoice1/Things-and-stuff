$InputFile = "G:\temp\LoginHistory1588364791509.csv"
$OutputFile = "G:\temp\LoginHistory1588364791509_Unique.csv"

# How many rows should progress be printed
$ShowCountEvery = 10000

$DeDupeOn = "Username", "Browser", "Platform"

# Include or exclude the data headers in the $DataForReport array from your output file
$IncludeOrExclude = "include"
# Data headers for the final report
# included or excluded base on $IncludeOrExclude
$DataForReport = "Username", "Browser", "Platform", "Login Type"

# Some pre-loop vars
$htUnique = @{ } # Empty hash table to store unique data
$Start = Get-Date # Starting date/time for compare
$n = 0 # counter
$LastItemTime = $null # Clearing a var for subsequent runs
$LastCount = $null
$AllProgressData = @()

# Count total lines for progress %
$ReadLinesBy = 100
$TotalLines = (Get-Content $InputFile -read $ReadLinesBy | Measure-Object -line).lines * $ReadLinesBy

foreach ($row in [System.IO.File]::ReadLines($InputFile)) {
    
    # Grab the header row for processing data and export later
    if ($n -eq 0) {
        $arrHeader = ($row).Replace("`"", "") -split ","
        
        if ($IncludeOrExclude -eq "Include") { 
            $csvHeader = ($arrHeader | Where-Object { $DataForReport -contains $_ }) -join ","
        }
        else {
            $csvHeader = ($arrHeader | Where-Object { $DataForReport -notcontains $_ }) -join ","
        }

        $n++
        continue
    }

    $n++ # Increment the counter

    # Show progress time to the screen at $ShowCountEvery interval
    if ($n % $ShowCountEvery -eq 0) {
        $UniqueCount = $htUnique.count
        if ($LastItemTime) {
            $DeltaTime = $(New-TimeSpan $LastItemTime $(Get-Date)).ToString() -replace "(.*\.\d{2}).*", '$1'
        }
        else {
            $DeltaTime = $(New-TimeSpan $Start $(Get-Date)).ToString() -replace "(.*\.\d{2}).*", '$1'
        }

        $TotalTimeSpan = (New-TimeSpan $Start $(Get-Date)).ToString() -replace "(.*\.\d{2}).*", '$1'
        
        $ProgressData = [PSCustomObject]@{
            "Processed rows [%]"  = "$n [$(($n/$TotalLines).ToString("P"))]"
            "Unique rows [Delta]" = "$UniqueCount [$($UniqueCount-$LastCount)]"
            "Total Time [Delta]"  = "$TotalTimeSpan [$DeltaTime]"
        }
        Write-Output $ProgressData
        $AllProgressData += $ProgressData
        
        $LastCount = $UniqueCount
        $LastItemTime = Get-Date
    }

    # Convert the CSV data to a psObj using the header
    $psObjRow = $row | ConvertFrom-Csv -Header $arrHeader
    
    #region normalization
    # Do any data normalization here

    $psObjRow.Browser = switch -Wildcard ($psObjRow.Browser) {
        "*Chrome*" { "Chrome" }
        "*Edge*" { "Edge" }
        "*Firefox*" { "Firefox" }
        "*Safari*" { "Safari" }
        "*IE*" { "IE" }
        default { $psObjRow.Browser }
    }

    #endregion normalization

    # Generate key and value pairs for hash table
    # Selecting item 1 of the CSV output just strips the header row
    $key = $($psObjRow | Select-Object $DeDupeOn | ConvertTo-Csv -NoTypeInformation)[1]
    if ($IncludeOrExclude -eq "Include") { 
        $value = $($psObjRow | Select-Object $DataForReport | ConvertTo-Csv -NoTypeInformation)[1]
    }
    else {
        $value = $($psObjRow | Select-Object * -ExcludeProperty $DataForReport | ConvertTo-Csv -NoTypeInformation)[1]
    }
    
    # If the key doesn't already exist, add it to the HT
    if (!$htUnique[$key]) {
        $htUnique += @{$key = $value }
    }

}

# Export the HT values to a csv
$csvHeader | Out-File $OutputFile
$htUnique.Values | Out-File $OutputFile -Append
