$InputFile = "G:\temp\LoginHistory.csv"
$OutputFile = "G:\temp\LoginHistory_Unique.csv"

# How many rows should progress be printed
$ShowCountEvery = 1000
# Unit of time between progress intervals
$DeltaUnit = "Seconds"
$DedupeOn = "Username","Browser","Platform"

# Include or exclude the data headers in the $DataForReport array from your ouput file
$IncludeOrExclude = "include"
# Data headers for the final report
# included or excluded base on $IncludeOrExclude
$DataForReport = "Username","Browser","Platform"

# Some pre-loop vars
$htUnique = @{} # Empty hash table to store unique data
$Start = get-date # Starting date/time for compare
$n = 0 # counter
$LastItemTime = $null # Clearing a var for subsqeuent runs

foreach($row in [System.IO.File]::ReadLines($InputFile)){
    
    # Grab the header row for processing data and export later
    if($n -eq 0){
        $csvHeader = $row
        $arrHeader = $row -split ","
        $n++
        continue
    }

    $n++ # Increment the counter

    # Show progress time to the screen at $ShowCountEvery interval
    if($n % $ShowCountEvery -eq 0){
        if ($LastItemTime){
            $DeltaTime = [math]::Round($(New-TimeSpan $LastItemTime $(get-date))."Total$($DeltaUnit)",2)
        }
        else{
            $DeltaTime = [math]::Round($(New-TimeSpan $Start $(get-date))."Total$($DeltaUnit)",2)
        }

        $TotalTimeSpan = New-TimeSpan $Start $(get-date)
        $SmallestTotalNonZero = (($TotalTimeSpan | select total*).psobject.properties | Where-Object {$_.MemberType -eq "NoteProperty" -and $_.value -ge 1 } | Sort-Object -Property value)[0]
        $TotalSpanUnit = $SmallestTotalNonZero.name.Replace("Total","")
        $TotalSpanValue = [math]::Round($SmallestTotalNonZero.value,2)
        
        [pscustomobject]@{
            number = $n
            "Delta ($DeltaUnit)" = $DeltaTime
            "Total Time (Dynamic)" = "$TotalSpanValue $TotalSpanUnit"
        }
        $LastItemTime = Get-Date
    }

    # Conver the CSV data to a psObj using the header
    $psObjRow = $row | convertfrom-csv -Header $arrHeader
    
    #region normalization
    # Do any data normalization here
    
    # Example to normalize some user agent string data
    # This would remove version info e.g. turns "Chrome 81" to "Chrome"
    # Since we are deduping on browser, this will be critical for proper dedupe
    $psObjRow.Browser = switch -Wildcard ($psObjRow.Browser){
        "*Chrome*" {"Chrome"}
        "*Edge*" {"Edge"}
        "*Firefox*" {"Firefox"}
        "*Safari*" {"Safari"}
        "*IE*" {"IE"}
        default {$psObjRow.Browser}
    }

    #endregion normalization

    # Generate key and value pairs for hash table
    # Selecting item 1 of the CSV output just strips the header row
    $key = $($psObjRow | select $DedupeOn | ConvertTo-Csv -NoTypeInformation)[1]
    if($IncludeOrExclude -eq "Include"){ 
        $value = $($psObjRow | select $DataForReport | ConvertTo-Csv -NoTypeInformation)[1]
    }
    else{
        $value = $($psObjRow | select * -ExcludeProperty $DataForReport | ConvertTo-Csv -NoTypeInformation)[1]
    }
    
    # If the key doesn't alraedy exist, add it to the HT
    if(!$htUnique[$key]){
        $htUnique += @{$key = $value}
    }

}

# Export the HT values to a csv
$csvHeader | Out-File $OutputFile
$htUnique.Values | Out-File $OutputFile -Append
