function Get-ConfluencePageContent {
    <#
    .SYNOPSIS
        Get the raw content (basically HTML) of a confluence page via the API
    .Parameter PageID
        The ID of the confluence page, you can get this from edit view or "view source" url
    .Parameter ConfluenceServerName
        The hostname of your confluence server, FQDN for best results
    .Parameter Credential
        PS Credential object used to authenticate to confluence
    .EXAMPLE
        $PageID = "123454567"
        $ConfluenceServerName = "confluence.server.name"
        $ConfluenceCreds = $(Get-Credential)

        $PageContent = Get-ConfluencePageContent -PageID $PageID -ConfluenceServerName $ConfluenceServerName -Credential $Credential
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PageID,
        [Parameter(Mandatory = $true)]
        [string]$ConfluenceServerName,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    $AuthHeader = ConvertTo-BasicAuthHeader -Credential $Credential

    $PageAPIURL = "https://$($ConfluenceServerName)/wiki/rest/api/content/$($PageID)"
    $PageBodyStorageAPIURL = "$($PageAPIURL)?expand=body.storage,version"

    $GetPageDataSplat = @{
        Method          = "GET"
        UseBasicParsing = $True
        URI             = $PageBodyStorageAPIURL
        Headers         = $AuthHeader 
        ContentType     = 'application/json'
    }

    try {
        Invoke-RestMethod @GetPageDataSplat
    }
    catch {
        $_.Exception
        throw Get-WebRequestFailureData
    }
}

function Publish-PSTableToConfluence {
    <#
    .SYNOPSIS
        Get the raw content (basically HTML) of a confluence page via the API
    .Parameter PageID
        The ID of the confluence page, you can get this from edit view or "view source" url
    .Parameter ConfluenceServerName
        The hostname of your confluence server, FQDN for best results
    .Parameter Credential
        PS Credential object used to authenticate to confluence
    .Parameter PSTable
        Some sort of powershell table-like object as an input. Can be an array or a [pscustomobject]
    .Parameter SectionHeader
        Optional parameter to define a section header you would like to search for in the page content and replace the first table it finds under that header.
        If you do not specify a section header, the entire page will be replaced with the PSTable content

        Warning: If there is no table found in the section defined the next table found will be replaced, even if that table is in a further section.
        Please make sure a table is defined in the section requested to avoid any false positives
    .Parameter IncludeFooter
        Optional parameter to include a foot note with the timestamp of the last automated update
    .Parameter CustomFooterText
        Optional parameter to be used in conjunction with the IncludeFooter switch.
        You can define custom text string as the footer data
        If not specified the default is "Content Updated by Automation"
    .Parameter Force
        Optional parameter to bypass the content check.
        If used the page will be updated regardless if the content is the same
    .Parameter SkipHTMLConversion
    .EXAMPLE
        $PageID = "123454567"
        $ConfluenceServerName = "confluence.server.name"
        $ConfluenceCreds = $(Get-Credential)

        $DomainControllerInfo = Get-ADDomainController -Filter * | Select-Object Name, Site, OperatingSystem, IsGlobalCatalog, IsReadOnly, IPv4Address, @{Name = "FSMO Roles"; Expression = { if ( $_.OperationMasterRoles.count -eq 5) { "All" } else { $_.OperationMasterRoles } } } | Sort-Object -Property Name

        Publish-PSTableToConfluence -PageID $PageID -ConfluenceServerName $ConfluenceServerName -Credential $ConfluenceCreds -PSTable $DomainControllerInfo -IncludeFooter -SectionHeader "Prod Domain Controller List"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PageID,
        [Parameter(Mandatory = $true)]
        [string]$ConfluenceServerName,
        [Parameter(Mandatory = $true)]
        $PSTable,
        [System.Management.Automation.PSCredential]
        $Credential,
        [string]$SectionHeader,
        [switch]$IncludeFooter,
        [switch]$AddTableOfContents,
        [switch]$AddViewTracker,
        [string]$CustomFooterText,
        [switch]$Force,
        [switch]$SkipHTMLConversion
    )

    if ( $SkipHTMLConversion) {
        $PSTableAsHTML = $PSTable
    }
    else {
        $PSTableAsHTML = ($PSTable | ConvertTo-Html -Fragment) -join ""
        # If there are line breaks in the cells, replace them with HTML breaks for confluence to parse
        if ($PSTableAsHTML -match "`n") {
            $PSTableAsHTML = $PSTableAsHTML -replace "`n", "<br />"
        }
    }
    
    $PageContent = Get-ConfluencePageContent -PageID $PageID -ConfluenceServerName $ConfluenceServerName -Credential $Credential -ErrorAction Stop
    $PageContentBodyStorageValue = $PageContent.body.storage.value

    $PSTableAsHTMLNoTagsEscaped = $PSTableAsHTML -replace "(<.*?>)" -replace "\\|\^|\$|\.|\||\?|\*|\+|\(|\)|\[|\]|\{|\}|\/", "\`$&"
    $PageContentBodyStorageValueNoTags = $PageContentBodyStorageValue -replace "(<.*?>)"

    if ((!$Force) -and ($PageContentBodyStorageValueNoTags -match $PSTableAsHTMLNoTagsEscaped)) {
        return Write-Output "Page:`"$($PageContent.title)`", Header: `"$SectionHeader`" - is already up to date, no publishing necessary."
    }

    if ($CustomFooterText) {
        $FooterText = $CustomFooterText
    }
    else {
        $FooterText = "Content Updated by Automation"
    }

    if ($IncludeFooter) {
        $FooterData = "<p><sub><em>"
        $footerData += "$FooterText $(Get-Date) $((Get-TimeZone).id)"
        $FooterData += "</em></sub></p>"
        $PSTableAsHTML = $PSTableAsHTML + $FooterData
    }

    if ($SectionHeader) {
        $NewBody = $PageContentBodyStorageValue -replace "($($SectionHeader).+?)(<table.+?<\/table>(.*?$($FooterText).*?<\/em><\/sub><\/p>)?)", "`$1 $PSTableAsHTML"
    }
    else {
        if ($AddTableOfContents) {
            $NewBody = "<ac:structured-macro ac:name=`"toc`" ac:schema-version=`"1`" ac:macro-id=`"590899dd-accd-4453-81a1-3e00e38a3e28`"><ac:parameter ac:name=`"maxLevel`">3</ac:parameter></ac:structured-macro>" + $PSTableAsHTML | Out-String
        }
        else {
            $NewBody = $PSTableAsHTML
        }
        if ($AddViewTracker) {
            $NewBody += "<p><br /></p><p><ac:structured-macro ac:name=`"viewtracker`" ac:schema-version=`"1`" ac:macro-id=`"84423050-f1fe-467c-88a6-2137392217ea`" /></p>"
        }
    }

    $PageAPIURL = "https://$($ConfluenceServerName)/wiki/rest/api/content/$($PageID)"
    $AuthHeader = ConvertTo-BasicAuthHeader -Credential $Credential

    $RequestBody = @{
        version = @{
            number = $PageContent.version.number + 1
        }
        title   = $PageContent.title
        type    = $PageContent.type
        body    = @{
            storage = @{
                value          = $NewBody
                representation = "storage"
            }
        }
    } | ConvertTo-Json

    $UpdatePageSplat = @{
        Method          = "PUT"
        UseBasicParsing = $True
        URI             = $PageAPIURL
        Headers         = $AuthHeader
        Body            = $RequestBody
        ContentType     = 'application/json'
    }

    if ($PSCmdlet.ShouldProcess("$($PageContent.title)", "Update Content")) {
        try {
            Write-Verbose "Updating Page:`"$($PageContent.title)`", Header: `"$SectionHeader`""
            Invoke-RestMethod @UpdatePageSplat
        }
        catch {
            $_.Exception
            throw Get-WebRequestFailureData
        }
    }

}

function Get-WebRequestFailureData {
    <#
    .SYNOPSIS
    Helper function to get the web request error data
    #>

    # Isolate the web request response stream bits
    $result = $_.Exception.Response.GetResponseStream()
    # Read the data stream
    $reader = New-Object System.IO.StreamReader($result)
    # Move the read head to position 0 for playback
    $reader.BaseStream.Position = 0
    # Store the response in a var
    $responseBody = $reader.ReadToEnd();
    # Try to convert the response data from json
    # If it's not json data, throw the raw data
    try {
        if ($responseBody -match "(\{[^{}]+\})") {
            return $responseBody | ConvertFrom-Json
        }
        else {
            return $responseBody.ToString()
        }
    }
    catch {
        return $responseBody
    }
}

function ConvertTo-BasicAuthHeader {
    <#
    .SYNOPSIS
        Helper function to intake a PS Credential and output a basicauth header for REST endpoints.
        Use caution in storing this data, the credential returned is not encrypted it is only encoded.
        Suggested use of this function is only to be used with other functions to limit the amount of time the encoded data is stored in memory.
    .PARAMETER Credential
        PS Credential input
    .EXAMPLE
        $Credential = Get-Credential
        $AuthHeader = ConvertTo-BasicAuthHeader -Credential $Credential
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    $Base64Creds = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes(
            "$($Credential.UserName):$($Credential.GetNetworkCredential().password)"
        )
    )

    $AuthHeader = @{
        Authorization = "Basic $Base64Creds"
    }

    return $AuthHeader
}
