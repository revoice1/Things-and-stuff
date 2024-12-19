
Function Invoke-OktaAPI {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubDomain,
        [ValidateSet("Production", "Preview")]
        [string]$Environment = "Production",
        $Token,
        [string]$Endpoint,
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        $Method = "GET",
        $Body,
        $ContentType = "application/json"
    )

    if ($Token.gettype().Name -eq "SecureString") {
        $Headers = @{Authorization = "SSWS $(ConvertFrom-SecureString -SecureString $Token -AsPlainText)" }
    }
    else {
        $Headers = @{Authorization = "SSWS $($Token)" }
    }
    
    if ($Environment -eq "Preview") {
        $OktaDomain = "oktapreview.com" 
    }
    else {
        $OktaDomain = "okta.com" 
    }

    $FullURI = "https://$($SubDomain).$($OktaDomain)/api/v1/$Endpoint"

    if ($Method -eq "GET") {
        $Body = $Body
    }
    else {
        $Body = $Body | ConvertTo-Json -Depth 100
    }

    $Splat = @{
        URI         = $FullURI
        Headers     = $Headers
        Method      = $Method
        ContentType = $ContentType
        Body        = $Body
    }

    try {
        if ($Method -ne "GET") {
            if ($PSCmdlet.ShouldProcess($Endpoint, $Method)) {
                $Response = Invoke-WebRequest @Splat
            }
        }
        else {
            $Response = Invoke-WebRequest @Splat
        }
    }
    catch {
        throw $_
    }
    
    if ($Response.Content) {
        $ResponseContent = $Response.Content | ConvertFrom-Json

        Write-Verbose "Rate limit remaining $($Response.headers.'x-rate-limit-remaining')"
        if ($Response.headers.'x-rate-limit-remaining' -eq 1) {
            $WaitSpan = New-TimeSpan -Start $(Get-Date) -End ([System.DateTimeOffset]::FromUnixTimeSeconds([int]::parse($Response.headers.'x-rate-limit-reset'))).LocalDateTime
            Write-Verbose "Sleeping for $($Waitspan.totalseconds) seconds due to API rate limit"
            Sleep $($WaitSpan.TotalSeconds + 1)
        }

        if ($Response.RelationLink.next -and ($Response.RelationLink.next -ne $Response.RelationLink.self)) {
            $After = $Response.RelationLink.next -replace ".*after=(.*?)(&|$).*", '$1'
            if (!$Body) { $Body = @{} }
            $Body["after"] = $After

            $RecursiveSplat = @{
                SubDomain   = $SubDomain
                Environment = $Environment
                Token       = $Token
                Endpoint    = $Endpoint
                Method      = $Method
                ContentType = $ContentType
                Body        = $Body
            }
            $ResponseContent += Invoke-OktaAPI @RecursiveSplat
        }
    }
    else {
        $ResponseContent = "$($Response.StatusCode), $($Response.StatusDescription)"
    }
    
    return $ResponseContent
}

Function Get-OktaGroups {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$Search,
        [string]$Expand = "stats,app",
        [string]$Filter,
        [string]$Q,
        [int]$limit,
        [string]$sortBy,
        [ValidateSet("asc", "desc")]
        [string]$sortOrder,
        [string]$ID,
        [string]$UserID
    )
    
    $Body = @{}
    
    $UserParams = "search", "expand", "filter", "q", "limit", "sortBy", "sortOrder"
    foreach ($UserParam in $UserParams) {
        $ParamValue = Get-Variable $UserParam -ValueOnly
        if ($ParamValue) {
            $Body[$UserParam] = $ParamValue
        }
    }

    if ($ID) {
        $Endpoint = "groups/$ID"
    }
    elseif ($UserID) {
        $Endpoint = "users/$UserID/groups"
    }
    else {
        $Endpoint = "groups"
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Remove-OktaGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$ID
    )    

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/$ID"
        Body        = $Body
        Method      = "DELETE"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function New-OktaGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        $Name,
        $Description
    )    

    $Body = @{
        profile = @{
            name        = $Name
            description = $Description                
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/"
        Body        = $Body
        Method      = "POST"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Remove-OktaRule {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$ID,
        [switchj]$DeactivateFirst
    )    

    if ($DeactivateFirst) {
        $Splat = @{
            SubDomain   = $SubDomain
            Environment = $Environment
            Token       = $Token
            Endpoint    = "/groups/rules/$ID/lifecycle/deactivate"
            Method      = "POST"
        }
        Write-Verbose $($Body | Out-String)
        Invoke-OktaAPI @Splat
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules/$ID"
        Method      = "DELETE"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Get-OktaGroupRules {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$Search,
        [string]$Expand = "groupIdToGroupNameMap",
        [int]$limit,
        $ID
    )
    
    $Body = @{}
    
    $UserParams = "search", "expand", "limit"
    foreach ($UserParam in $UserParams) {
        $ParamValue = Get-Variable $UserParam -ValueOnly
        if ($ParamValue) {
            $Body[$UserParam] = $ParamValue
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules"
        Body        = $Body
    }
    if($ID){$Splat.Endpoint+="/$ID"}
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function New-OktaGroupRule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$Name,
        [string]$Expression,
        [array]$UserIDsExcluded,
        [array]$AssignGroupIDs
    )
    
    $Body = @{}
    $Body.type = "group_rule"
    $Body.name = $Name
    $Body.conditions = @{}
    $Body.conditions.expression = @{}
    $Body.conditions.expression.type = "urn:okta:expression:1.0"    
    $Body.conditions.expression.value = $Expression
    $Body.conditions.people = @{}
    $Body.conditions.people.users = @{}
    $Body.conditions.people.users.exclude = @()
    if ($UserIDsExcluded) {
        $Body.conditions.people.users.exclude += $UserIDsExcluded
    }
    $Body.actions = @{}
    $Body.actions.assignUserToGroups = @{}
    $Body.actions.assignUserToGroups.groupIds = @()
    $Body.actions.assignUserToGroups.groupIds += $AssignGroupIDs

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules"
        Body        = $Body
        Method      = "POST"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Set-OktaGroupRule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$ID,
        [string]$Name,
        [string]$Expression,
        [array]$UserIDsExcluded,
        [array]$AssignGroupIDs
    )
    
    $Body = @{}
    $Body.type = "group_rule"
    $Body.name = $Name
    $Body.conditions = @{}
    $Body.conditions.expression = @{}
    $Body.conditions.expression.type = "urn:okta:expression:1.0"    
    $Body.conditions.expression.value = $Expression
    $Body.conditions.people = @{}
    $Body.conditions.people.users = @{}
    $Body.conditions.people.users.exclude = @()
    if ($UserIDsExcluded) {
        $Body.conditions.people.users.exclude += $UserIDsExcluded
    }
    $Body.actions = @{}
    $Body.actions.assignUserToGroups = @{}
    $Body.actions.assignUserToGroups.groupIds = @()
    $Body.actions.assignUserToGroups.groupIds += $AssignGroupIDs

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules/$ID"
        Body        = $Body
        Method      = "PUT"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Enable-OktaGroupRule {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        $ID
    )
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules/$($ID)/lifecycle/activate"
        Method      = "POST"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Disable-OktaGroupRule {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        $ID
    )
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/rules/$($ID)/lifecycle/deactivate"
        Method      = "POST"
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Get-OktaGroupApps {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$GroupName,
        [string]$GroupID,
        [int]$limit
        
    )
    
    $Body = @{}
    
    if ($limit) {
        $Body.limit = $limit
    }

    if ($GroupName) {
        Write-Verbose "Attempting to looking id for group $GroupName"
        try {
            $GroupID = (Get-OktaGroups -Search "profile.name eq `"$GroupName`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $GroupID"
        }
        catch {
            throw $_
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/$($GroupID)/apps"
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Get-OktaGroupMembers {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$Name,
        [string]$ID,
        [int]$limit
        
    )
    
    $Body = @{}
    
    if ($limit) {
        $Body.limit = $limit
    }

    if ($Name) {
        Write-Verbose "Attempting to looking id for group $Name"
        try {
            $ID = (Get-OktaGroups -Search "profile.name eq `"$Name`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $ID"
        }
        catch {
            throw $_
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/$($ID)/users"
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}


Function Add-OktaGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$GroupName,
        [string]$GroupID,
        [string]$UserLogin,
        [string]$UserID
    )

    if ($GroupName) {
        Write-Verbose "Attempting to looking id for group $GroupName"
        try {
            $GroupID = (Get-OktaGroups -Search "profile.name eq `"$GroupName`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $GroupID"
        }
        catch {
            throw $_
        }
    }

    if ($UserLogin) {
        Write-Verbose "Attempting to looking id for user $UserID"
        try {
            $UserID = (Get-OktaUsers -Search "profile.login eq `"$UserLogin`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $UserID"
        }
        catch {
            throw $_
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/$($GroupID)/users/$($UserID)"
        Method      = "PUT"
    }

    Invoke-OktaAPI @Splat
}

Function Remove-OktaGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$GroupName,
        [string]$GroupID,
        [string]$UserLogin,
        [string]$UserID
    )

    if ($GroupName) {
        Write-Verbose "Attempting to looking id for group $GroupName"
        try {
            $GroupID = (Get-OktaGroups -Search "profile.name eq `"$GroupName`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $GroupID"
        }
        catch {
            throw $_
        }
    }

    if ($UserLogin) {
        Write-Verbose "Attempting to looking id for user $UserID"
        try {
            $UserID = (Get-OktaUsers -Search "profile.login eq `"$UserLogin`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $UserID"
        }
        catch {
            throw $_
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "groups/$($GroupID)/users/$($UserID)"
        Method      = "DELETE"
    }

    Invoke-OktaAPI @Splat
}

Function Get-OktaUsers {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$Search,
        [string]$Filter,
        [string]$Q,
        [int]$limit,
        [string]$sortBy,
        [ValidateSet("asc", "desc")]
        [string]$sortOrder,
        [string]$AppId,
        [switch]$AllIncludingDeprovisioned,
        [string]$ID

    )

    if (($Filter -or $Search -or $Q) -and ($AllIncludingDeprovisioned)) {
        throw "You cannot use a search parameter and the AllIncludingDeprovisioned switch togeher"
    }
    elseif ($AllIncludingDeprovisioned) {
        $Search = "created lt `"$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK"))`""
    }
    
    $Body = @{}
    
    $UserParams = "search", "filter", "q", "limit", "sortBy", "sortOrder"
    foreach ($UserParam in $UserParams) {
        $ParamValue = Get-Variable $UserParam -ValueOnly
        if ($ParamValue) {
            $Body[$UserParam] = $ParamValue
        }
    }

    if ($AppId) {
        $Endpoint = "apps/$AppId/users" 
    }
    else {
        $Endpoint = "users"
    }

    if ($ID) {
        $Endpoint = "$Endpoint/$ID"
    }

    Write-Verbose $($Body | Out-String)
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Body        = $Body
    }
    Invoke-OktaAPI @Splat
}

Function New-OktaUser {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$Login,
        [bool]$Activate = $False,
        [ValidateSet("changePassword")]
        [string]$nextLogin,
        [hashtable]$Profile
    )
    
    if ($Login) {
        $Profile.login = $Login
        $Profile.email = $Login
    }
 
    $Endpoint = "users"
    if (($null -ne $Activate) -or $nextLogin) { $Endpoint += "?" }
    if ($null -ne $Activate) {
        $Endpoint += "activate=$activate"
        if ($nextLogin) { $Endpoint += "&" }
    }
    if ($nextLogin) { $Endpoint += "nextlogin=$nextLogin" }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Body        = @{profile = $Profile }
        Method      = "POST"
    }
    Invoke-OktaAPI @Splat
}

Function Set-OktaUser {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$ID,
        [string]$Login,
        [hashtable]$Body,
        [switch]$DeleteUnspecified,
        [string]$AppId,
        [ValidateSet("GROUP", "USER")]
        [string]$Scope,
        [hashtable]$Credentials
    )

    if ($Login) {
        Write-Verbose "Attempting to looking id for user $Login"
        try {
            $ID = (Get-OktaUsers -Search "profile.login eq `"$Login`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $Login"
        }
        catch {
            throw $_
        }
    }

    if ($DeleteUnspecified) {
        if ($PSCmdlet.ShouldContinue("$ID", "This operation will overwrite all non-specified attributes on the Okta user")) {
            $Method = "PUT"
        }
    }
    else {
        $Method = "POST"    
    }


    if ($AppId) {
        $Endpoint = "apps/$AppId/users/$ID" 
    }
    else {
        $Endpoint = "users/$ID"
    }


    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Body        = @{}
        Method      = $Method
    }
    if ($Body) { $Splat.Body["profile"] = $Body }
    if ($Scope) { $Splat.Body["scope"] = $Scope }
    if ($Credentials) { $Splat.Body["credentials"] = $Credentials }
    Invoke-OktaAPI @Splat
}

Function Get-OktaApps {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$Expand,
        [string]$Filter,
        [string]$Q,
        [int]$limit = 200,
        [string]$UserID
    )
    
    $Body = @{}

    if ($UserID) {
        if ($Filter) {
            $Filter += "&"
        }
        $Filter += "user.id eq `"$UserID`""
    }
    
    $UserParams = "expand", "filter", "q", "limit"
    foreach ($UserParam in $UserParams) {
        $ParamValue = Get-Variable $UserParam -ValueOnly
        if ($ParamValue) {
            $Body[$UserParam] = $ParamValue
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "apps"
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Get-OktaAppConnections {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        $ID,
        $Connection = "default"
    )
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "apps/$ID/connections/default"
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}

Function Get-OktaAppAssignments {
    [CmdletBinding()]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [ValidateSet("Users", "Groups", "Policies")]
        [string]$Type = "Users",
        [string]$Name,
        [string]$ID,
        [int]$limit = 200
    )
    
    $Body = @{}
    
    if ($limit) {
        $Body.limit = $limit
    }

    if ($Name) {
        Write-Verbose "Attempting to looking id for app $Name"
        try {
            $ID = (Get-OktaApps -Filter "name eq `"$Name`"" -Token $Token -SubDomain $SubDomain -Environment $Environment).id
            Write-Verbose "Found id $ID"
        }
        catch {
            throw $_
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "apps/$($ID)/$($Type.tolower())"
        Body        = $Body
    }
    Write-Verbose $($Body | Out-String)
    Invoke-OktaAPI @Splat
}


Function Get-OktaMappings {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [int]$limit = 200,
        [string]$SourceId,
        [string]$TargetId,
        [string]$ID
    )
    
    $Body = @{}
    
    $UserParams = "limit", "sourceId", "targetId"
    foreach ($UserParam in $UserParams) {
        $ParamValue = Get-Variable $UserParam -ValueOnly
        if ($ParamValue) {
            $Body[$UserParam] = $ParamValue
        }
    }

    if ($ID) {
        $Endpoint = "mappings/$ID"
    }
    else {
        $Endpoint = "mappings"
    }
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Body        = $Body
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaSchemas {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$type = "default"
    )
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "/meta/schemas/user/$type"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaAppGroups {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        [string]$AppID
    )
    
    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "/apps/$AppID/groups"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaAppPushGroups {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $SessionID = $OktaSID,
        [string]$AppName,
        [string]$AppID,
        [int]$limit = 100,
        $lastSeenMappingId
    )

    if ($Environment -eq "Preview") {
        $OktaDomain = "oktapreview.com" 
    }
    else {
        $OktaDomain = "okta.com" 
    }

    if ($AppName) {
        $AppID = (Get-OktaApps -Q $AppName).id
    }

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
    if ($SessionID.gettype().Name -eq "SecureString") {
        $session.Cookies.Add((New-Object System.Net.Cookie("sid", $(ConvertFrom-SecureString -AsPlainText $OktaSID), "/", "$($SubDomain.ToLower()).okta.com")))
    }
    else {
        $session.Cookies.Add((New-Object System.Net.Cookie("sid", $($OktaSID), "/", "$($SubDomain.ToLower())-admin.okta.com")))
    }
    
    $Splat = @{
        URI             = "https://$($SubDomain)-admin.$($OktaDomain)/api/internal/instance/$($AppID)/grouppush" 
        WebSession      = $session
        UseBasicParsing = $true
        Body            = @{}
        ContentType     = "application/x-www-form-urlencoded"
    }

    if ($limit) { $Splat.Body.limit = $limit }
    if ($lastSeenMappingId) { $Splat.Body.lastSeenMappingId = $lastSeenMappingId }

    $Response = Invoke-WebRequest @Splat
    $Content = $Response.Content | ConvertFrom-Json
    $Mappings = @()
    $Mappings += $Content.mappings
    
    if ($Content.nextMappingsPageUrl) {
        $lastSeenMappingId = $Content.nextMappingsPageUrl -replace ".*lastSeenMappingId=(.*?)(&|$).*", '$1'
        $limit = $Content.nextMappingsPageUrl -replace ".*limit=(.*?)(&|$).*", '$1'
        $Splat = @{
            SubDomain         = $SubDomain
            Environment       = $Environment
            SessionID         = $SessionID
            AppID             = $AppID
            limit             = $limit
            lastSeenMappingId = $lastSeenMappingId
        }
        $Mappings += Get-OktaAppPushGroups @Splat
    }
    
    return $Mappings 
    
}

Function Get-DependentGroupRules {
    [CmdletBinding()]
    param(
        [string]$SubDomain,
        [string]$Environment = "Production",
        $Token = $OktaToken,
        $GroupName,
        $GroupId,
        [switch]$Recursive
    )

    if ($GroupName) {
        $GroupId = (Get-OktaGroups -Q $GroupName).id
    }

    $Splat = @{
        Token       = $Token
        SubDomain   = $SubDomain
        Environment = $Environment
        Search      = $GroupId
    }

    $Results = @()
    $Results += Get-OktaGroupRules @Splat

    $Report = @()
    if ($Results) {
        Foreach ($Result in $Results) {
            $Report += [PSCustomObject]@{
                Parent    = $GroupId
                Dependent = $Result
            }
        }
    }
    else {
        $Report += [PSCustomObject]@{
            Parent    = $GroupID
            Dependent = "N/A"
        }
    }

    if ($Recursive) {
        Foreach ($Result in $Results) {
            $Groups = $Result.actions.assignUserToGroups.groupIds
            foreach ($Group in $Groups) {
                $Splat = @{
                    SubDomain   = $SubDomain
                    Environment = $Environment
                    Token       = $Token
                    GroupId     = $Group
                    Recursive   = $Recursive
                }
                $Report += Get-DependentGroupRules @Splat
            }
        }
    }

    return $Report

}

Function Get-OktaAuthenticator {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$ID
    )    


    if ($ID) {
        $Endpoint = "authenticators/$ID"
    }
    else {
        $Endpoint = "authenticators"
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Method      = "GET"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$ID,
        $Type
    )    

    if ($ID) {
        $Endpoint = "policies/$ID"
    }
    elseif ($Type) {
        $Endpoint = "policies?type=$Type"
    }
    else {
        $Endpoint = "policies"
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Method      = "GET"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaPolicyRules {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$PolicyID
    )    

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "policies/$PolicyId/rules"
        Method      = "GET"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaPolicyResources {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$PolicyID
    )    

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "policies/$PolicyId/mappings"
        Method      = "GET"
    }
    Invoke-OktaAPI @Splat
}

Function Add-OktaAppToAuthPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$PolicyID,
        $AppID
    )    

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "apps/$($AppID)/policies/$($PolicyID)"
        Method      = "PUT"
    }
    Invoke-OktaAPI @Splat
}

Function Get-OktaDevices {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [int]$limit = 100,
        [string]$Search,
        [string]$expand = "userSummary",
        [string]$ID
    )    

    if ($ID) {
        $Endpoint = "devices/$ID"
        
    }
    else {
        $Endpoint = "devices"
        $Body = @{limit = $Limit; expand = $expand }
        if ($Search) {
            $Body['search'] = $Search
        }
    }

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = $Endpoint
        Method      = "GET"
        Body        = $Body
    }
    Invoke-OktaAPI @Splat
}

Function Set-OktaDevice {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [int]$limit = 100,
        [string]$Search,
        [string]$expand = "user",
        [string]$ID,
        [ValidateSet("Activate", "Deactivate", "Suspend", "Unsuspend", "Delete")]
        [string]$Operation
    )    

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Body        = $Body
    }
    if ($Operation -eq "Delete") {
        $Splat.Endpoint = "devices/$($ID)"
        $Splat.Method = "DELETE"
    }
    else {
        $Splat.Endpoint = "devices/$($ID)/lifecycle/$($Operation.ToLower())"
        $Splat.Method = "POST"
    }

    Invoke-OktaAPI @Splat
}

Function Get-OktaLogs {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $SubDomain,
        $Environment = "Production",
        $Token = $OktaToken,
        [string]$q,
        [string]$filter,
        [int]$limit = 1000,
        $Days = 95
    )    

    $Body = @{}
    if ($q) { $Body["q"] = $q }
    if ($filter) { $Body["filter"] = $filter }
    $Body["limit"] = $limit
    $Body["since"] = (Get-Date).AddDays(-$Days) | Get-Date -Format "o"

    $Splat = @{
        SubDomain   = $SubDomain
        Environment = $Environment
        Token       = $Token
        Endpoint    = "logs"
        Method      = "GET"
        Body        = $Body
    }
    Invoke-OktaAPI @Splat
}
