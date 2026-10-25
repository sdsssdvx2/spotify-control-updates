param(
    [Parameter(Mandatory=$true)][string]$CandidateAddon,
    [Parameter(Mandatory=$true)][string]$BetterLocalFilesExtension,
    [Parameter(Mandatory=$true)][string]$PlaylistMakerExtension
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "ASSERT FAILED: $Message" } }
function Write-Utf8NoBom([string]$Path,[string]$Text) { [IO.File]::WriteAllBytes($Path,(New-Object Text.UTF8Encoding($false)).GetBytes($Text)) }

$addonText=Get-Content -LiteralPath $CandidateAddon -Raw
$begin='# BEGIN SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8'
$end='# END SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8'
$start=$addonText.IndexOf($begin,[StringComparison]::Ordinal)
$finish=$addonText.IndexOf($end,[StringComparison]::Ordinal)
Assert-True ($start -ge 0 -and $finish -gt $start) 'expanded wrapper markers present'
$finish += $end.Length
$wrapperText=$addonText.Substring($start,$finish-$start)
$wrapperPath=Join-Path $env:RUNNER_TEMP 'expanded-performance-overlay-wrapper.ps1'
Write-Utf8NoBom $wrapperPath $wrapperText
. $wrapperPath

$script:Logs=New-Object Collections.Generic.List[string]
$script:AppsRoot=$null
$script:PlaylistRevisionMismatch=$false
$script:SpotifyRunning=$false

function Write-AddonLog { param([string]$Message,[string]$Level='INFO'); $script:Logs.Add("$Level $Message") }
function Get-SpicetifyAssetRoots { param([string]$Kind); return @($script:AppsRoot) }
function Resolve-SpicetifyAsset { param([string]$Name,[string]$Kind,[object[]]$Roots); return [pscustomobject]@{status='resolved';selected_path=(Join-Path $script:AppsRoot $Name)} }
function Get-DirectoryGitSnapshot {
    param([string]$Path)
    $name=Split-Path -Leaf $Path
    $fp=switch ($name) {
        'better-local-files' { '7295540798b15d02b1b26975f500ce6ad8a987cfd08a1a93684e5deb650f3e38' }
        'playlist-maker' { 'bdc9e19393f0f08349448769b304b0eb5180bb47d183a8019f101a30e45a408f' }
        default { 'unknown' }
    }
    return [pscustomobject]@{fingerprint=$fp}
}
function Get-PithayaKnownBaseline {
    param([string]$Name)
    switch ($Name) {
        'better-local-files' { return [pscustomobject]@{revision='bf467fab93e6c1f8b8d4189dc1054bd1cafb3f3a';fingerprint='7295540798b15d02b1b26975f500ce6ad8a987cfd08a1a93684e5deb650f3e38'} }
        'playlist-maker' {
            if ($script:PlaylistRevisionMismatch) { return [pscustomobject]@{revision='new-upstream-revision';fingerprint='different-tree'} }
            return [pscustomobject]@{revision='9fd89fb40a53e4cfbf0953d34f806f4a8a36fc64';fingerprint='bdc9e19393f0f08349448769b304b0eb5180bb47d183a8019f101a30e45a408f'}
        }
        default { return $null }
    }
}
function Test-PerformanceOverlaySpotifyRunning { return $script:SpotifyRunning }

$baseIndex=@'
<!doctype html>
<html><head>
<script src="extensions/sc-cover-ambience.js"></script>
<script data-protected="ivLyrics" src="extensions/ivLyrics/extension.js"></script>
<script src="extensions/better-local-files/extension.js"></script>
<script src="extensions/playlist-maker/extension.js"></script>
<link rel="stylesheet" href="user.css">
<script src="extensions/tagify/extension.js"></script>
<script src="extensions/splitify/extension.js"></script>
<script src="extensions/marketplace/extension.js"></script>
</head><body></body></html>
'@

function New-SyntheticInstall([string]$Root,[string]$IndexText) {
    $roaming=Join-Path $Root 'AppData\Roaming'
    $local=Join-Path $Root 'AppData\Local'
    $xpui=Join-Path $roaming 'Spotify\Apps\xpui'
    $ext=Join-Path $xpui 'extensions'
    $apps=Join-Path $Root 'CustomApps'
    New-Item -ItemType Directory -Force -Path (Join-Path $ext 'better-local-files'),(Join-Path $ext 'playlist-maker'),(Join-Path $ext 'ivLyrics'),(Join-Path $ext 'tagify'),(Join-Path $ext 'splitify'),(Join-Path $ext 'marketplace'),(Join-Path $apps 'better-local-files'),(Join-Path $apps 'playlist-maker') | Out-Null
    Copy-Item -LiteralPath $BetterLocalFilesExtension -Destination (Join-Path $ext 'better-local-files\extension.js') -Force
    Copy-Item -LiteralPath $PlaylistMakerExtension -Destination (Join-Path $ext 'playlist-maker\extension.js') -Force
    Write-Utf8NoBom (Join-Path $xpui 'index.html') $IndexText
    return [pscustomobject]@{Roaming=$roaming;Local=$local;Xpui=$xpui;Apps=$apps;Index=(Join-Path $xpui 'index.html')}
}

$temp=Join-Path $env:RUNNER_TEMP ('spotify-control-v0619-wrapper-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$oldAppData=$env:APPDATA; $oldLocalAppData=$env:LOCALAPPDATA
try {
    $f1=New-SyntheticInstall (Join-Path $temp 'exact') $baseIndex
    $env:APPDATA=$f1.Roaming; $env:LOCALAPPDATA=$f1.Local; $script:AppsRoot=$f1.Apps
    $blfPath=Join-Path $f1.Xpui 'extensions\better-local-files\extension.js'
    $pmPath=Join-Path $f1.Xpui 'extensions\playlist-maker\extension.js'
    $blfBefore=(Get-FileHash $blfPath -Algorithm SHA256).Hash
    $pmBefore=(Get-FileHash $pmPath -Algorithm SHA256).Hash
    Invoke-PerformanceOverlayBestEffort -Reason 'ci-exact'
    $patched=[IO.File]::ReadAllText($f1.Index)
    Assert-True ($patched.Contains('spotify-control-performance-overlay:lazy:better-local-files')) 'exact Better Local Files is lazy'
    Assert-True ($patched.Contains('spotify-control-performance-overlay:lazy:playlist-maker')) 'exact Playlist Maker is lazy'
    foreach ($protected in @('extensions/sc-cover-ambience.js','extensions/ivLyrics/extension.js','extensions/tagify/extension.js','extensions/splitify/extension.js','extensions/marketplace/extension.js','href="user.css"')) { Assert-True ($patched.Contains($protected)) "protected hook preserved: $protected" }
    Assert-True ((Get-FileHash $blfPath -Algorithm SHA256).Hash -eq $blfBefore) 'Better Local Files payload unchanged'
    Assert-True ((Get-FileHash $pmPath -Algorithm SHA256).Hash -eq $pmBefore) 'Playlist Maker payload unchanged'

    # Simulate a fresh Spicetify/upstream index and an updated Playlist Maker tree. The
    # optimization must be re-evaluated from the new index and skip only the changed app.
    $newUpstream=$baseIndex.Replace('<body>','<!-- new-upstream-index -->' + [Environment]::NewLine + '<body>')
    Write-Utf8NoBom $f1.Index $newUpstream
    $script:PlaylistRevisionMismatch=$true
    Invoke-PerformanceOverlayBestEffort -Reason 'ci-upstream-change'
    $reapplied=[IO.File]::ReadAllText($f1.Index)
    Assert-True ($reapplied.Contains('new-upstream-index')) 'new upstream index content preserved'
    Assert-True ($reapplied.Contains('spotify-control-performance-overlay:lazy:better-local-files')) 'still-exact app remains optimized'
    Assert-True (-not $reapplied.Contains('spotify-control-performance-overlay:lazy:playlist-maker')) 'changed app optimization skipped'
    Assert-True ($reapplied.Contains('src="extensions/playlist-maker/extension.js"')) 'changed app original eager hook preserved'

    # Spotify-running path must return before engine/state materialization or index mutation.
    $f2=New-SyntheticInstall (Join-Path $temp 'spotify-running') $baseIndex
    $env:APPDATA=$f2.Roaming; $env:LOCALAPPDATA=$f2.Local; $script:AppsRoot=$f2.Apps
    $script:PlaylistRevisionMismatch=$false; $script:SpotifyRunning=$true
    $before=[IO.File]::ReadAllBytes($f2.Index)
    Invoke-PerformanceOverlayBestEffort -Reason 'ci-spotify-running'
    $after=[IO.File]::ReadAllBytes($f2.Index)
    Assert-True (([BitConverter]::ToString($before)) -eq ([BitConverter]::ToString($after))) 'Spotify-running index byte-exact no-op'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $f2.Local 'SpotifyControl\performance-overlay'))) 'Spotify-running path creates no overlay engine/state'

    Write-Host 'V0619 PRODUCTION OVERLAY WRAPPER TEST PASS'
} finally {
    $env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocalAppData
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
