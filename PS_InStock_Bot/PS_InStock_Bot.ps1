Start-Transcript ".\newegg_parser.log"
$DiscordWebhook = "URL TO YOUR GENERAL DISCORD WEBHOOK GOES HERE"

$ReplayThresholdInMinutes = 60 # Threshold before an item can alert again

$Pages = @(
    @{
        Site  = "Newegg"
        Label = "GeForce RTX 30 Series (...no 3090's):"
        URL   = "https://www.newegg.com/p/pl?N=100007709%208000%204814%20601359415%20601357250%20601357247&PageSize=96"
    }
    @{
        Site    = "Newegg"
        Label   = "Ryzen 5000 series"
        URL     = "https://www.newegg.com/p/pl?N=100007671%208000%20601359163"
        Webhook = "URL TO YOUR MORE SPECIFIC DISCORD WEBHOOK GOES HERE"
    }
    @{
        Site  = "B&H"
        Label = "Geforce RTX 30 Series"
        URL   = "https://www.bhphotovideo.com/c/products/Graphic-Cards/ci/6567/N/3668461602?filters=fct_nvidia-geforce-series_5011%3Ageforce-rtx-3060-ti%7Cgeforce-rtx-3070%7Cgeforce-rtx-3080"
    }
    @{
        Site  = "BestBuy"
        Label = "Geforce RTX 30 Series"
        URL   = "https://www.bestbuy.com/site/computer-cards-components/video-graphics-cards/abcat0507002.c?id=abcat0507002&qp=gpusv_facet%3DGraphics%20Processing%20Unit%20(GPU)~NVIDIA%20GeForce%20RTX%203060%20Ti%5Egpusv_facet%3DGraphics%20Processing%20Unit%20(GPU)~NVIDIA%20GeForce%20RTX%203070%5Egpusv_facet%3DGraphics%20Processing%20Unit%20(GPU)~NVIDIA%20GeForce%20RTX%203080"
    }
    @{
        Site  = "MSI"
        Label = "Geforce RTX 30 Series"
        Url   = "https://us-store.msi.com/index.php?route=product/category&path=75_76_246&limit=60"
    }
    @{
        Site  = "EVGA"
        Label = "Geforce RTX 30 Series"
        URL   = "https://www.evga.com/products/ProductList.aspx?type=0&family=GeForce+30+Series+Family"
    }
)

Clear-Host

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    [array]$PastInStockItems = Import-Clixml .\PastInStockItems.xml -ErrorAction stop
}
catch {
    $PastInStockItems = @()
}

Foreach ($Page in $Pages) {
    Write-Output "$($Page["Site"]) | $($Page["Label"])"

    Try {
        $Request = Invoke-WebRequest $Page["URL"] -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache" } -TimeoutSec 5
    }
    catch {
        "Web request timed out!"; ""
        continue
    }

    Switch ($Page["Site"]) {
        "Newegg" {
            $Pattern = '(?s)<div class="item-container">.*?<a href="(?<ItemLink>.*?)" class="item-img".*?img src="(?<ItemImage>.*?)"\ .*?class="item-title" title="View Details">(?<ItemName>.*?)<\/a>.*?(?:<p class="item-promo"><i class="item-promo-icon"><\/i>(?<ItemStock>.*?)<\/p>)?.*?<li><strong>Model #: <\/strong>(?<ItemModel>.*?)<\/li>(?:.*?<span class="price-current-label"><\/span>\$<strong>(?<ItemDollars>.*?)<\/strong><sup>(?<ItemCents>.*?)?<\/sup>)?.*?<div class="item-stock"'
            $Color = 0xfa9d28
            $Icon = "https://c1.neweggimages.com/webResource/Themes/Nest/logos/logo_424x210.png"
            break
        }
        "B&H" {
            $Pattern = '(?s)<div data-selenium="miniProductPageProduct".*?href="\/c\/product\/(?<ItemImage>.*?)-.*?href="(?<ItemLink>.*?)".*?<span data-selenium="miniProductPageProductName">(?<ItemName>.*?)<.*?MFR # (?<ItemModel>.*?)<\/div><div data-selenium="miniProductPage.*?"uppedDecimalPriceFirst">\$(?<ItemDollars>.*?)<.*?"uppedDecimalPriceSecond".*?>(?<ItemCents>.*?)<.*?"stockStatus">(?<ItemStock>.*?)<.*?'
            $Color = 0xbf281a
            $Icon = "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c9/B%26H_Foto_%26_Electronics_Logo.svg/320px-B%26H_Foto_%26_Electronics_Logo.svg.png"
            break
        }
        "BestBuy" {
            $Pattern = '(?s)<li class="sku-item" data-sku-id.*?<a class="image-link" href="(?<ItemLink>.*?)".*?<img class="product-image" alt=".*?src="(?<ItemImage>.*?)".*?<span class="sku-value">(?<ItemModel>.*?)<.*?"displayText\\":\\"(?<ItemStock>.*?)\\".*?\\"currentPrice\\":(?<ItemPrice>.*?),.*?"name\\":\\"(?<ItemName>.*?)\\".*?<\/li>'
            $Color = 0xffe000
            $Icon = "https://pisces.bbystatic.com/image2/BestBuy_US/Gallery/BestBuy_Logo_2020-190616.png"
            break
        }
        "MSI" {
            $Pattern = '(?s)<div class="product-layout product-grid col".*?<a href="(?<ItemLink>.*?)".*?<img src="(?<ItemImage>.*?)".*?alt="(?<ItemName>.*?)".*?<span class="price-new">\$(?<ItemPrice>.*?)<.*?class="btn btn-sm float-right add-cart-button-(?<ItemStock>.).*?COMPARE<\/button>'
            $color = 0xdc3545
            $icon = "https://us-store.msi.com/image/catalog/msi_logo-156x60-3.png"
            break
        }
        "EVGA" {
            $Pattern = '(?s)<div class="list-item">.*?href="(?<ItemLink>.*?)".*?data-src="(?<ItemImage>.*?)".*?<div class="pl-list-pname">\s+<a href=".*?>(?<ItemName>.*?)<.*?P\/N:\ (?<ItemModel>.*?)<.*?\$<strong>(?<ItemDollars>.*?)<\/strong><sup>(?<ItemCents>.*?)<.*?<span class="pl-list-rebate"><\/span>\s+ <\/p>\s+<\/div>\s+<div id="LFrame_prdList_rlvProdList_ctrl\d+_pnl(?<ItemStock>.*?)_'
            $Color = 0x161415
            $Icon = "https://static.techspot.com/images2/downloads/topdownload/2014/10/EVGA.png"
            break
        }
    }

    $ItemMatches = @()
    
    $ItemMatches = [regex]::Matches($Request.Content, $Pattern)
    
    $ItemTable = foreach ($Item in $ItemMatches) {
        $MatchGroups = $Item.Groups
        $ItemDollars = $MatchGroups['ItemDollars'].Value
        $ItemCents = $MatchGroups['ItemCents'].Value 
        $ItemImage = $MatchGroups['ItemImage'].Value
        $ItemStock = $MatchGroups['ItemStock'].Value
        $ItemModel = $MatchGroups['ItemModel'].Value

        Switch ($Page["Site"]) {
            "Newegg" {
                $ItemInStock = if ($ItemStock -ne "OUT OF STOCK") { $true } else { $false }
                $ItemLink = $MatchGroups['ItemLink'].Value
                $ItemPrice = if ($ItemDollars -or $ItemCents) { "`$$ItemDollars$ItemCents" } else { "Unknown" }
                break
            }
            "B&H" {
                $OrderTerms = "Special Order", "In Stock"
                $ItemInStock = if ($OrderTerms -contains $ItemStock) { $true } else { $false }
                $ItemLink = "https://www.bhphotovideo.com$($MatchGroups['ItemLink'].Value)"
                $ItemPrice = if ($ItemDollars -or $ItemCents) { "`$$ItemDollars.$ItemCents" } else { "Unknown" }
                $ItemImage = "https://static.bhphoto.com/images/images345x345/$ItemImage.jpg"
                break
            }
            "BestBuy" {
                $ItemInStock = if ($ItemStock -like "Get it in*") { $true } else { $false }
                $ItemLink = "https://www.bestbuy.com" + $MatchGroups['ItemLink'].Value
                $ItemPrice = if ($MatchGroups['ItemPrice'].Value ) { "`$$($MatchGroups['ItemPrice'].Value)" } else { "Unknown" }
                break
            }
            "MSI" {
                $ItemInStock = if ($ItemStock -eq "2") { $true } else { $false }
                $ItemLink = $MatchGroups['ItemLink'].Value -replace "amp;", ""
                $ItemModel = ($ItemImage -split "/")[8]
                break
            }
            "EVGA" {
                $ItemInStock = if ($ItemStock -eq "Buy") { $true } else { $false }
                $ItemLink = "https://www.evga.com" + $MatchGroups['ItemLink'].Value
                $ItemPrice = if ($ItemDollars -or $ItemCents) { "`$$ItemDollars$ItemCents" } else { "Unknown" }
                break
            }
        }
    
        [PSCustomObject]@{
            Name    = $MatchGroups['ItemName'].Value -replace [char]160, [char]32 # Some entry had a non-breaking space that discord didn't like, replace with normal space
            Model   = $ItemModel
            Link    = $ItemLink
            Price   = $ItemPrice
            InStock = $ItemInStock
            Image   = $ItemImage
            Site    = $Page["Site"]
        }
    }

    #$ItemTable | Select-Object name, InStock

    $InStockItems = $ItemTable | Where-Object { $_.InStock }
    $ItemsToAlert = $InStockItems | Where-Object { $PastInStockItems.link -notcontains $_.link }
    
    Write-Host "Items Found   : $(@($ItemTable).Count)"
    Write-Host "In Stock Items: $(@($InStockItems).Count)"
    Write-Host "Items To Alert: $(@($ItemsToAlert).Count)"

    if ($ItemsToAlert) {
        $PastInStockItems += $ItemsToAlert | Select-Object link, model, Site, Name, @{N = "LastAlerted"; E = { Get-Date } }

        $ItemsToAlert | Select-Object ShortName, price, InStock, Link | Format-Table -AutoSize
        $Embeds = @()
        foreach ($Item in $ItemsToAlert) {
            $Embeds += @{
                color       = $Color
                title       = "In Stock"
                author      = @{
                    icon_url = $Icon
                    name     = $Item.Site
                }
                thumbnail   = @{
                    url = $Item.Image
                }
                description = "[$($item.Name)]($($Item.Link))"
                fields      = @(
                    @{
                        name  = "Model"
                        value = if ($item.Model) { $item.Model }else { "Unknown" }
                    }
                    @{
                        name  = "Price"
                        value = $item.price
                    }
                    @{
                        name = "Monitored Page"
                        value = "[Link]($($Page["URL"]))"
                    }
                )
                url         = $Item.link
            }
        }

        $Groups = @($Embeds).count / 10
        if ($Groups % 1 -ne 0) { $Groups = ($Groups + 1).ToString().split(".")[0] }

        foreach ($GroupNumber in 0..($Groups - 1)) {
            $StartIndex = 10 * $GroupNumber
            $EndIndex = $StartIndex + 9
            $Body = @{ embeds = @($Embeds)[$StartIndex..$EndIndex] } | ConvertTo-Json -Depth 4
            if ($Page["Webhook"]) {
                # Use page specific webhook if there is one
                $Webhook = Invoke-RestMethod -Uri $Page["Webhook"] -Body $Body -Method Post -ContentType "application/json"     
            }
            else {
                # Use general webhook if there isn't a page specific one
                $Webhook = Invoke-RestMethod -Uri $DiscordWebhook -Body $Body -Method Post -ContentType "application/json"    
            }
        }
    }
    else { "No Items To Alert!"; "" }
}

$PastInStockItems | Where-Object { ([datetime]$_.LastAlerted).AddMinutes($ReplayThresholdInMinutes) -ge $(Get-Date) }  | Export-Clixml .\PastInStockItems.xml

Stop-Transcript
