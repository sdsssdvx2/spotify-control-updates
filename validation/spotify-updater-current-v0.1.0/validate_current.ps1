param()
$ErrorActionPreference='Stop'

$auditPath=Join-Path $PSScriptRoot '..\..\spotify-updater-current-audit.json'
$auditPath=[IO.Path]::GetFullPath($auditPath)
if(-not (Test-Path -LiteralPath $auditPath -PathType Leaf)){throw "Audit report missing: $auditPath"}
$r=Get-Content -LiteralPath $auditPath -Raw|ConvertFrom-Json
if($r.result -ne 'AUDIT_PASS'){throw "Unexpected audit result: $($r.result)"}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$mainPath=Join-Path $repoRoot 'validation\v0.6.20\out\bin\spotify-control.ps1'
$main=Get-Content -LiteralPath $mainPath -Raw

foreach($n in @('Normalize-Etag','Get-SpotifyVersion','Get-SpotifyPublisherSignature','Test-SpotifyInstallerIdentity','Get-LatestSpotifyWindowsCandidate','Get-VerifiedSpotifyInstaller','Get-SmartUpdateGuardPlan','Set-SpotifyUpdateGuardState','Invoke-SmartUpdateGuard','Invoke-SpotifyPreflight','Invoke-SpotifyTransactionalMaintenance','Restore-SpotifyTransactionSnapshot','Rollback-SpotifyTransaction','Repair-PendingSpotifyTransaction')){
    if(-not $r.target_functions.PSObject.Properties[$n]){throw "Missing updater evidence for $n"}
}
foreach($x in @(
    'https://download.scdn.co/SpotifyFullSetupX64.exe',
    'https://robyrew.github.io/spotify-versions-history/api/v1/windows-x64.json',
    'Spotify official installer HEAD did not return an ETag.',
    'No Windows x64 feed entry matched Spotify''s current official installer ETag.',
    'Matched feed record is missing a valid SHA-256:',
    'Matched feed record is missing a valid installer size:',
    '''If-Match''=[string]$Candidate.Etag',
    'Installer SHA-256 mismatch.',
    'Installer size mismatch.',
    'Installer signature verification failed:',
    'Installer ProductVersion mismatch.',
    'Signer is not Spotify AB:',
    'Spotify installer changed protected user data; rolling back.',
    'Spicetify configuration changed outside allowed Backup version fields.',
    'Spicetify extension/custom-app/theme source assets changed during Spotify repair.',
    'Smart Update Guard was not verified blocked after Spotify update.',
    'Automatic Spotify downgrade is refused:'
)){
    if($main.IndexOf($x,[StringComparison]::Ordinal) -lt 0){throw "Production Spotify updater contract missing: $x"}
}
Write-Host ("SPOTIFY_UPDATER_STATIC_CONTRACT_PASS functions={0} urls={1}" -f @($r.target_functions.PSObject.Properties).Count,@($r.production_spotify_urls).Count)

# Define the exact production ETag normalizer from the audited production source.
$normalizeSource=[string]$r.target_functions.'Normalize-Etag'.excerpt
if([string]::IsNullOrWhiteSpace($normalizeSource) -or $normalizeSource -notmatch '(?m)^function\s+Normalize-Etag\s*\{'){throw 'Exact production Normalize-Etag function was not captured.'}
Invoke-Expression $normalizeSource

function Compare3([string]$A,[string]$B){
    $aa=@($A.Split('.'));$bb=@($B.Split('.'))
    for($i=0;$i -lt 3;$i++){
        $av=0;$bv=0
        if($i -lt $aa.Count){if(-not [int]::TryParse(($aa[$i] -replace '[^0-9].*$',''),[ref]$av)){return $null}}
        if($i -lt $bb.Count){if(-not [int]::TryParse(($bb[$i] -replace '[^0-9].*$',''),[ref]$bv)){return $null}}
        if($av -lt $bv){return -1};if($av -gt $bv){return 1}
    }
    return 0
}

$official='https://download.scdn.co/SpotifyFullSetupX64.exe'
$feedUrl='https://robyrew.github.io/spotify-versions-history/api/v1/windows-x64.json'
$ua='SpotifyControl-validation/0.1.0'
$head=Invoke-WebRequest -Uri $official -Method Head -UseBasicParsing -MaximumRedirection 5 -Headers @{'User-Agent'=$ua}
$officialEtag=Normalize-Etag ([string]$head.Headers['ETag'])
if([string]::IsNullOrWhiteSpace([string]$officialEtag)){throw 'Official Spotify installer HEAD returned no usable production-normalized ETag.'}
$feed=Invoke-RestMethod -Uri $feedUrl -Headers @{'User-Agent'=$ua}
$matches=@()
foreach($p in $feed.PSObject.Properties){
    $entry=$p.Value
    if($null -eq $entry -or $null -eq $entry.win -or $null -eq $entry.win.x64){continue}
    $asset=$entry.win.x64
    $feedEtag=Normalize-Etag ([string]$asset.etag)
    if([string]::IsNullOrWhiteSpace([string]$feedEtag) -or $feedEtag -ne $officialEtag){continue}
    if(([string]$asset.official -ne $official) -and ([string]$asset.url -ne $official)){continue}
    $sha=([string]$asset.sha256).Trim().ToLowerInvariant();$size=[int64]0;try{$size=[int64]$asset.size}catch{$size=0}
    $matches += [pscustomobject]@{Version=[string]$p.Name;FullVersion=[string]$entry.fullversion;Etag=$feedEtag;Sha256=$sha;Size=$size}
}
if($matches.Count -ne 1){throw "Expected exactly one feed record matching current official Spotify ETag; got $($matches.Count)"}
$c=$matches[0]
if($c.Version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$'){throw "Invalid candidate version: $($c.Version)"}
if([string]::IsNullOrWhiteSpace([string]$c.FullVersion)){$c.FullVersion=$c.Version}
if($c.Sha256 -notmatch '^[0-9a-f]{64}$'){throw 'Candidate feed SHA-256 invalid.'}
if($c.Size -le 0){throw 'Candidate feed size invalid.'}

$work=Join-Path $env:RUNNER_TEMP ('spotify-current-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work|Out-Null
try {
    $installer=Join-Path $work 'SpotifyFullSetupX64.exe'
    # This is exactly the production conditional download contract: production-normalized ETag in If-Match.
    Invoke-WebRequest -Uri $official -Headers @{'User-Agent'=$ua;'If-Match'=[string]$c.Etag} -UseBasicParsing -OutFile $installer -MaximumRedirection 5
    $actualSha=(Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant();$actualSize=(Get-Item $installer).Length
    if($actualSha -cne $c.Sha256){throw "Current Spotify installer SHA mismatch: $actualSha != $($c.Sha256)"}
    if($actualSize -ne $c.Size){throw "Current Spotify installer size mismatch: $actualSize != $($c.Size)"}
    $sig=Get-AuthenticodeSignature -LiteralPath $installer
    if([string]$sig.Status -ne 'Valid'){throw "Current Spotify installer Authenticode status=$($sig.Status)"}
    $subject=[string]$sig.SignerCertificate.Subject
    if([string]::IsNullOrWhiteSpace($subject) -or $subject -notmatch '(?i)(^|,\s*)(O|CN)=Spotify AB(,|$)'){throw "Current Spotify installer signer is not Spotify AB: $subject"}
    $product=[string](Get-Item $installer).VersionInfo.ProductVersion
    if([string]::IsNullOrWhiteSpace($product) -or $product.Trim() -cne ([string]$c.FullVersion).Trim()){throw "Current Spotify installer ProductVersion mismatch: $product != $($c.FullVersion)"}

    $spice=Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -Headers @{'User-Agent'=$ua;'Accept'='application/vnd.github+json'}
    if([bool]$spice.draft -or [bool]$spice.prerelease){throw 'Latest Spicetify release is not stable.'}
    $winLine=@(([string]$spice.body -split "`r?`n")|Where-Object{$_ -match 'Spotify\s+for\s+\*\*[^*]*Windows[^*]*\*\*'})|Select-Object -First 1
    if([string]::IsNullOrWhiteSpace([string]$winLine)){throw 'Latest Spicetify release has no Windows compatibility line.'}
    $vm=[regex]::Matches([string]$winLine,'(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if($vm.Count -ne 2){throw "Could not parse latest Spicetify Windows range: $winLine"}
    $min=$vm[0].Groups[1].Value;$max=$vm[1].Groups[1].Value
    $lo=Compare3 $c.Version $min;$hi=Compare3 $c.Version $max
    if($null -eq $lo -or $null -eq $hi -or $lo -lt 0 -or $hi -gt 0){throw "Current Spotify candidate $($c.Version) is outside latest Spicetify $($spice.tag_name) Windows range $min -> $max"}

    $evidence=[ordered]@{
        schema=1;official_url=$official;official_etag=[string]$officialEtag;feed_url=$feedUrl;
        candidate_version=[string]$c.Version;candidate_fullversion=[string]$c.FullVersion;candidate_sha256=[string]$c.Sha256;candidate_size=[int64]$c.Size;
        actual_sha256=$actualSha;actual_size=[int64]$actualSize;authenticode_status=[string]$sig.Status;signer_subject=$subject;
        signer_thumbprint=[string]$sig.SignerCertificate.Thumbprint;product_version=$product;if_match_mode='production-normalized-etag';
        spicetify_tag=[string]$spice.tag_name;spicetify_min=$min;spicetify_max=$max;compatible_with_latest_spicetify=$true
    }
    $evidence|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $repoRoot 'spotify-current-candidate-evidence.json') -Encoding UTF8
    Write-Host "SPOTIFY_CURRENT_CANDIDATE_SANDBOX_PASS version=$($c.Version) full=$($c.FullVersion) size=$actualSize sha=$actualSha etag=$officialEtag spicetify=$($spice.tag_name) range=$min->$max"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
