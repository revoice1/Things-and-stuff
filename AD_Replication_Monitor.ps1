<#
Script designed to run as a scheduled task and e-mail about Active directory domain controller replication issues.
The system the script runs on requires network level access to poll the domain controllers
>#

Write-Host "Script Start: $(Get-Date)" -ForegroundColor DarkMagenta

$ReplicationThreshold = 60 # Threshold in minutes for detecting "Last Replication Success" Issues
$CacheTimeoutThreshold = 60 # Threshold in minutes to resend e-mails for persistent alerts

# Cache file location, same path as running script
$CacheFilePath = "$(Split-Path $MyInvocation.MyCommand.Path -Parent)\AD_Replication_Issue_Cache.html"
# Test is cache file exists
$CachePresent = Test-Path $CacheFilePath
# Default mode to send alerts, unless otherwise prevented by logic.
$SendAlert = $true

# Dev Switches
$DevMode = $false # Only e-mail specific user, make false for production
$DontRefreshData = $false # Don't pull fresh data from DCs, make false for production
$ForceIssues = $false # EVERYTHING IS BROKEN!!!!! make false for production
$ForceClean = $false # EVERYTHING IS FIXED!!! takes precidence over ForceIssues, make false for production

# Dev Comments = ###, remove for prod

# SMTP Parameters
### Fill in required data here
$MailSplat = @{
    To         = ""
    SmtpServer = ""
    Body       = ""
    BodyAsHtml = $true
    From       = ""
    Subject    = "AD Replication Issues"
}

if ($DevMode) {
    Write-Host "Dev Mode on, only sending mail to you" -ForegroundColor Green
    $MailSplat.to = "" ### Developer e-mail goes here
}

$NonConnectable = @()

if (!$DontRefreshData) {
    # Grab all the DCs
    $AllDCs = Get-ADDomainController -Filter *

    # Declare null arrays for data storage
    $AllReplicationData = @()

    # For each DC, try to ping then gather the replication data
    foreach ($DC in $AllDCs) {
        "Collecting data from $($DC.Name)"
        $ConnectionTest = Test-Connection $DC -Quiet

        if ($ConnectionTest) {
            $ADReplicationData = Get-ADReplicationPartnerMetadata -Target $DC.name -Partition *
            $AllReplicationData += $ADReplicationData
        }
        else {
            Write-Warning "$($DC.name) is not currently connectable"
            $NonConnectable += $DC.Name
        }
    }
}

# Fancy stuff
# Create an array of attributes to select from the objects
Write-Host "Evaluating Collected Data." -ForegroundColor Cyan
$AttributesToSelect = @(
    @{ Name = 'Server' ; Expression = {
            $_.Server.toupper().split(".")[0] 
        } 
    }
    @{ Name = 'Partner' ; Expression = {
            $_.Partner -replace 'CN=NTDS Settings,CN=([a-zA-Z0-9\-]*).*', '$1' 
        } 
    }
    @{ Name = 'Partition' ; Expression = {
            switch -regex ($_.Partition) {
                "^CN=Configuration,.*" { "Configuration" }
                "^CN=Schema,.*" { "Schema" }
                "^DC=.*" { "Domain" }
                default { "$_.Partition" }
            }
        }
    }
    "LastReplicationAttempt"
    "LastReplicationResult"
    "LastReplicationSuccess"
    "ConsecutiveReplicationFailures"
)

# Filter the issues into groups
$ConsecutiveFailures = $AllReplicationData | `
    Where-Object { $_.ConsecutiveReplicationFailures -gt 0 } | `
    Select-Object -Property $AttributesToSelect | `
    Select-Object Server, Part*

$ReplicationResult = $AllReplicationData | `
    Where-Object { $_.LastReplicationResult -ne 0 } | `
    Select-Object -Property $AttributesToSelect | `
    Select-Object Server, Part*, LastReplicationResult

$LastReplicationTime = $AllReplicationData | `
    Where-Object { $_.LastReplicationSuccess -lt $($(Get-Date).addminutes(-$ReplicationThreshold)) } | `
    Select-Object -Property $AttributesToSelect | `
    Select-Object Server, Part*, LastReplicationSuccess

# If ForceIssues is set, make all data and issue...No filter
if ($ForceIssues) {
    $NonConnectable = $AllDCs.name
    $ConsecutiveFailures = $AllReplicationData | `
        Select-Object -Property $AttributesToSelect | `
        Select-Object Server, Part*

    $ReplicationResult = $AllReplicationData | `
        Select-Object -Property $AttributesToSelect | `
        Select-Object Server, Part*, LastReplicationResult

    $LastReplicationTime = $AllReplicationData | `
        Select-Object -Property $AttributesToSelect | `
        Select-Object Server, Part*, LastReplicationSuccess
}
if ($ForceClean) {
    $NonConnectable = $null
    $ConsecutiveFailures = $null
    $ReplicationResult = $null
    $LastReplicationTime = $null
}

# If there are issues, send e-mail
if ($NonConnectable -or $ConsecutiveFailures -or $ReplicationResult -or $LastReplicationTime) {

    Write-Host "Issues Found, Prepping E-Mail" -ForegroundColor Yellow

    # HTML CSS Style data
    $BodyStyle = "<style>" +
    "BODY{background-color:white;font-family:consolas;font-size:9pt;color:black;}" +
    "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}" +
    "TH{border-width: 1px;padding: 3px;padding-right: 5px;padding-left: 5px;border-style: solid;border-color: white;background-color:black;color:white;}" +
    "TD{border-width: 1px;padding-right: 5px;padding-left: 5px;padding-top: 2px;padding-bottom: 2px;border-style: solid;border-color: black;background-color: white;}" +
    "</style>"

    # Data for the body of the e-mail
    # Clear the mailbody again, this is unnecessary just for partial run troubleshooting
    $MailSplat.Body = ""

    $MailSplat.Body += "The following AD replication issues were found <br>"

    if ($NonConnectable) {
        $MailSplat.Body += "<h2>Non-Connectable:</h2>"
        $MailSplat.Body += "$(@($NonConnectable).count) Issues"
        $MailSplat.Body += "<br>"
        $MailSplat.Body += $NonConnectable -join "<br>"
        $MailSplat.Body += "<br>"
    }
    if ($ConsecutiveFailures) {
        $MailSplat.Body += "<h2>Consecutive Replication failures:</h2>"
        $MailSplat.Body += "$(@($ConsecutiveFailures).count) Issues"
        $MailSplat.Body += $($ConsecutiveFailures | ConvertTo-Html -Fragment | Out-String)
        $MailSplat.Body += "<br>"
    }
    if ($ReplicationResult) {
        $MailSplat.Body += "<h2>Non-Zero Replication Result:</h2>"
        $MailSplat.Body += "$(@($ReplicationResult).count) Issues"
        $MailSplat.Body += $($ReplicationResult | ConvertTo-Html -Fragment | Out-String)
        $MailSplat.Body += "<br>"
    }
    if ($LastReplicationTime) {
        $MailSplat.Body += "<h2>Last Successfuly Replicated > $($ReplicationThreshold) Min Ago:</h2>"
        $MailSplat.Body += "$(@($LastReplicationTime).count) Issues"
        $MailSplat.Body += $($LastReplicationTime | ConvertTo-Html -Fragment | Out-String)
        $MailSplat.Body += "<br>"
    }

    $MailSplat.Body += "<h3> Monitoring E-mail Logic: <br> </h3>"
    $MailSplat.Body += "If issues are persistent, alerts will be sent once $($CacheTimeoutThreshold) minutes.<br>"
    $MailSplat.Body += "If issues change, an update will be sent, at max, once per 15 minutes.<br>"
    $MailSplat.Body += "If issues clear, an all-clear e-mail will be sent.<br>"

    # Convert the E-mail to proper HTML with CSS header
    $MailSplat.Body = ConvertTo-Html -Body $MailSplat.Body -Head $BodyStyle | Out-String

    # If the cachefile exists
    if ($CachePresent) {
        Write-Host "Cache file present" -ForegroundColor Cyan
        # Get the cached content for compare, trim whitespace
        $CacheContent = $(Get-Content -Path $CacheFilePath -Raw | Out-String).Trim()
        # If the cache and current content are the same
        if ($CacheContent -eq $MailSplat.Body.Trim()) {
            Write-Host "Current cache matches current issues" -ForegroundColor Cyan
            # Store variables for cache age and cache expiration
            $CacheFileLastWrite = $(Get-Item -Path $CacheFilePath).LastWriteTime
            $CacheExpiration = $(Get-Date).AddMinutes(-$CacheTimeoutThreshold)

            $MinutesRemaining = [math]::Round((New-TimeSpan -Start $CacheFileLastWrite -End $CacheExpiration).totalminutes * - 1)

            # If the cache is un-expired, supress e-mail
            if ($CacheFileLastWrite -gt $CacheExpiration) {
                # Supress alert
                Write-Host "Current cache is still valid for $MinutesRemaining minutes, supressing e-mail" -ForegroundColor Cyan
                $SendAlert = $false
            }
            # If the cache file has expired, refresh the cache and send alert
            else {
                Write-Host "Current cache has been invalid for $($MinutesRemaining*-1) minutes, refreshing cache and sending e-mail" -ForegroundColor Cyan
                $MailSplat.Body | Out-File -FilePath $CacheFilePath
            }
        }
        # If the cache and current issues don't match
        # Replace the cache and send alert
        else {
            Write-Host "New issues found, not in cache, overwriting cache and sending e-mail" -ForegroundColor Cyan
            $MailSplat.Body | Out-File -FilePath $CacheFilePath
        }
    }
    # If there is no cache file, create one
    else {
        Write-Host "New issues found, no cache, creating cache and sending e-mail" -ForegroundColor Cyan
        $MailSplat.Body | Out-File -FilePath $CacheFilePath
    }

    # Send the mail
    if ($SendAlert) {
        Send-MailMessage @MailSplat
    }
}
else {
    Write-Host "No Issues Found" -ForegroundColor Green
    if ($CachePresent) {
        Write-Host "Clearing Cache" -ForegroundColor Green
        # Send Message if cache exists and no current issues found
        $MailSplat.Body = "All issues cleared"
        $MailSplat.Subject = "AD Replication Issues - Cleared"

        Send-MailMessage @MailSplat

        # Remove old cache file
        Remove-Item $CacheFilePath
    }
}
Write-Host "Script End:   $(Get-Date)" -ForegroundColor DarkMagenta
