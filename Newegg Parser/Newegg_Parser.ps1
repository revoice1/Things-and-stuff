Start-Transcript ".\newegg_parser.log"
$DiscordWebhook = "https://discord.com/api/webhooks/THING AND STUFF GO HERE"

$Pages = @(
    @{
        Label = "Ryzen 5000 Series:"
        URL   = "https://www.newegg.com/p/pl?N=100007671%20601359163%208000%204814&PageSize=96"
    }
    @{
        Label = "GeForce RTX 30 Series:"
        URL   = "https://www.newegg.com/p/pl?N=100007709%20601357282%208000%204814&PageSize=96"
    }
)

$AllInStockItems = @()

Foreach ($Page in $Pages) {
    Write-Output $Page["Label"]

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Request = Invoke-WebRequest $Page["URL"] -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache" } 

    $Pattern = '<div class="item-container">.*?<a href="(?<ItemLink>.*?)" class="item-img".*?img src="(?<ItemImage>.*?)"\ .*?class="item-title" title="View Details">(?<ItemName>.*?)<\/a>.*?(?:<p class="item-promo"><i class="item-promo-icon"><\/i>(?<ItemStock>.*?)<\/p>)?.*?<li><strong>Model #: <\/strong>(?<ItemModel>.*?)<\/li>(?:.*?<span class="price-current-label"><\/span>\$<strong>(?<ItemDollars>.*?)<\/strong><sup>(?<ItemCents>.*?)?<\/sup>)?.*?<div class="item-stock"'
    $ItemMatches = ([regex]$Pattern).Matches($Request.Content)

    $ItemTable = foreach ($Item in $ItemMatches) {
        $MatchGroups = $Item.Groups
        $ItemStock = $MatchGroups['ItemStock'].Value
        $ItemDollars = $MatchGroups['ItemDollars'].Value
        $ItemCents = $MatchGroups['ItemCents'].Value  
        $ItemLink = $MatchGroups['ItemLink'].Value  
        [PSCustomObject]@{
            Name      = $MatchGroups['ItemName'].Value
            Model     = $MatchGroups['ItemModel'].Value
            Link      = $ItemLink
            ShortName = $ItemLink -replace "https:\/\/www.newegg.com\/(.*?)\/.*", '$1'
            Price     = if ($ItemDollars -or $ItemCents) { "`$$ItemDollars$ItemCents" } else { "Unknown" }
            InStock   = if ($ItemStock -ne "OUT OF STOCK") { $true } else { $false }
            Image     = $MatchGroups['ItemImage'].Value
        }
    }

    try {
        $PastInStockItems = Import-Clixml .\PastInStockItems.xml
    }
    catch {
        $PastInStockItems = $null
    }

    $InStockItems = $ItemTable | Where-Object { $_.InStock }
    $AllInStockItems += $InStockItems

    $ItemsToAlert = $InStockItems | Where-Object { $PastInStockItems.link -notcontains $_.link }

    if ($ItemsToAlert) {
        $ItemsToAlert | Select-Object ShortName, price, InStock, Link | Format-Table -AutoSize
        $Embeds = @()
        foreach ($Item in $InStockItems) {
            $Embeds += @{
                color       = 0xfa9d28
                title       = "Newegg In Stock"
                thumbnail   = @{
                    url       = $Item.Image
                    proxy_url = $Item.link
                }
                description = "[$($item.Name)]($($Item.Link))"
                fields      = @(
                    @{
                        name   = "Model"
                        value  = $item.Model
                        inline = $True
                    }
                    @{
                        name  = "price"
                        value = $item.price
                    }
                )
                url         = $Item.link
            }
        }
        $Body = @{embeds = $Embeds } | ConvertTo-Json -Depth 4
        Invoke-RestMethod -Uri $DiscordWebhook -Body $Body -Method Post -ContentType "application/json"
        
    }
    else { "ALL OUT OF STOCK or ALREADY ALERTED"; "" }
}

$AllInStockItems | Export-Clixml .\PastInStockItems.xml
Stop-Transcript
