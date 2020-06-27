#Scrapes scryfall website for all card images of a single set
#Then creates tabletop simulator templates to import into TTS
#Needs ImageMagick installed to work (v7.0.8 last tested)

Param(
	[Parameter(Mandatory=$true)] [string] $outDir, #default Dir where images are saved
	[Parameter(Mandatory=$true)] [string] $set, #set code that website uses  (EX: soi = shadows over innistrad)
	[string] $bgColor = '#000000', # white = #FFFFFF, black = #000000
	[bool] $templateOnly = $FALSE #only make template, skip downloading images
	)
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$url_base = "https://scryfall.com/"
$blankCard = (Get-ChildItem blank.jpg).FullName
$backCard = (Get-ChildItem back.jpg).FullName
$rarities = @('C','U','R','M')

if(!(Test-Path -Path $outDir)) {
	mkdir -Path $outDir
}

if( (Get-ChildItem $outDir -Filter '*template*.jpg').Count -gt 0) {
	"[$outDir] must be empty of template files in order to run." | Write-Warning
	Exit
}

#get card border color (white/black)
function getBGColor {
	Param(
		[string]$link,
		[string]$set
	)
	$webResponse = Invoke-WebRequest -uri $link
	$imgTags = $webResponse.ParsedHtml.getElementsByClassName('card ' + $set.ToLower() + ' border-white')
	
	if($imgTags.Length -gt 0) {
		return '#FFFFFF' #white
	} else {
		return '#000000' #black
	}
}

#download card image from link
function getCardImage {
	Param(
		[string]$link,
		[string]$name,
		[string]$rarity
	)
	try {
		Invoke-WebRequest $link -OutFile ($outDir + '\' + $name + '_' + $rarity + '.jpg')
	} catch {
		#Write-Warning ('Couldnt find ' + $link)
		return $FALSE
	}
	return $TRUE
}

#create image templates using ImageMagick
function createTemplates {
	Param (
		[string] $rarity = '',
		[Array[]] $images
	)
	#Grabs cards in chunks of 69 by rarity to add to 10x7 templates for TTS
	$start = 0
	$end = $start + 68
	$x = 1
	if($rarity.length -gt 0) {
		$rarity = '_' + $rarity
	}
	
	chdir $outDir
	
	while ($start -lt $images.Count) {
		$imgSet = $images[$start..$end] #get images to work with in chunks
		
		#add blank cards to fill out template if less than 69 cards
		while($imgSet.Count -lt 69) {
			$imgSet += $blankCard
		}
		
		#add card back to 70th spot
		$imgSet += $backCard
		
		#run imagemagick to create template montage
 		&"magick" "montage" "-background" $bgColor $imgSet "-tile" "10x7" "-geometry" "+2+2" ('__' + $set + $rarity + '_template_' + [string] $x + '.jpg')
		$start = $end+1
		$end = $start + 68
		$x++
	}
	
	chdir $scriptPath
}

if(! $templateOnly) {
	#get list of all cards in set
	Write-Host "Grabbing set list from website..."
#	$url = ('https://scryfall.com/sets/' + $set + '?as=checklist&order=set')
	foreach ($rarity in ($rarities)) {
		$url = ('https://scryfall.com/search?q=set%3A' + $set + '+rarity%3A' + $rarity + '&order=set&as=checklist&unique=cards')
		$webResponse = Invoke-WebRequest -Uri $url
		$rows = $webResponse.ParsedHtml.getElementsByTagName('tr')
		Write-Host ([string]($rows.Length - 1) + " cards found for $rarity.")
		
		#get border color from page metadata
		if($rows[1].innerhtml -match 'href=\"(.*?)\"') {
			$bgColor = getBGColor -link ($url_base + $Matches[1]) -set $set
		}
		
		#grab the img, name, and rarity for each card
		foreach ($row in ($rows | select -Skip 1) ) { #skip header row
			$attributes = $row.attributes
			foreach($att in $attributes) {
				if($att.Name -eq 'data-card-image') {
					$imgURL = $att.value
				}
			}
			if($row.childNodes.item(1).innertext -match '(\d+)') { #clean out extra spaces for card number
				$cardName = $Matches[1]
			}
			$cardName = $cardName -replace ' // ','--' #fix name for dual cards
			if($row.childNodes.item(4).innertext -match 'Basic Land') { #check for basic lands
				$rarity = 'L'
			} else {
				$rarity = ($row.childNodes.item(5).innertext -replace ' ','') #remove extra spaces
			}
			$rarities += $rarity
			
			#check if back side exists for card
			$backURL = $imgURL -replace '/front/','/back/'
			if(getCardImage -link $backURL -name ($cardName + 'b') -rarity $rarity) {
				#get a-side since already got b side
				$tempName = $cardName + 'a'
				$t = getCardImage -link $imgURL -name $tempName -rarity $rarity
			} else { #normal card, get regular img
				$t = getCardImage -link $imgURL -name $cardName -rarity $rarity
			}
		}
	}
}

if($templateOnly) {
	#get all images regardless of rarity
	$images = Get-ChildItem -Path $outDir
	createTemplates -images $images
} else {
	#get all images and split by rarity
	foreach ($rarity in ($rarities | Sort-Object | Get-Unique)) {
		$images = Get-ChildItem -Path $outDir | Where-Object { $_.Name -match "\d+[a]?_$rarity.jpg" }
		#create templates by rarity, skip b side cards
		createTemplates -rarity $rarity -images $images
	}
	#create b side template if set contains b side cards
	$images2 = Get-ChildItem -Path $outDir | Where-Object { $_.Name -match '\d+b_.*' }
	if($images2.Count -gt 0) {
		createTemplates -rarity 'B-Side' -images $images2
	}
}