param(
    [ValidateSet('Audit','Apply','Restore')]
    [string]$Mode = 'Audit',
    [string]$XpuiRoot,
    [string]$StateRoot,
    [string]$TargetMetadataPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $TargetMetadataPath) { $TargetMetadataPath = Join-Path $ScriptRoot 'target.json' }
if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'StateRoot is required when LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'SpotifyControl\star-ratings-performance\runtime-v1'
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-Utf8Exact([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = 0; $count = $bytes.Length
    if ($hasBom) { $offset = 3; $count -= 3 }
    $enc = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $enc.GetString($bytes, $offset, $count) }
    catch { throw "Refusing Star Ratings optimization because active bytes are not strict UTF-8: $($_.Exception.Message)" }
    return [pscustomobject]@{ Bytes = $bytes; Text = $text; HasBom = $hasBom }
}

function ConvertTo-Utf8ExactBytes([string]$Text, [bool]$HasBom) {
    $enc = New-Object Text.UTF8Encoding($false)
    $body = $enc.GetBytes($Text)
    if (-not $HasBom) { return $body }
    $out = New-Object byte[] ($body.Length + 3)
    $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
    [Array]::Copy($body, 0, $out, 3, $body.Length)
    return $out
}

function Write-BytesAtomic([string]$Path, [byte[]]$Bytes) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Parent directory missing: $dir" }
    $leaf = [IO.Path]::GetFileName($Path); $nonce = [Guid]::NewGuid().ToString('N')
    $tmp = Join-Path $dir ($leaf + '.scstar.' + $nonce + '.tmp')
    $replaceBackup = Join-Path $dir ($leaf + '.scstar.' + $nonce + '.replace-backup')
    try {
        [IO.File]::WriteAllBytes($tmp, $Bytes)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, $replaceBackup) }
        else { [IO.File]::Move($tmp, $Path) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}

function Write-JsonUtf8([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 16
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($json))
}

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Expected Star Ratings transform anchor missing: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Expected Star Ratings transform anchor ambiguous: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Transform-StarRatings([string]$Text) {
    $Text = Replace-ExactOnce $Text 'c=new MutationObserver(()=>{De()})' 'c=new MutationObserver(()=>{clearTimeout(c.__spotifyControlPerfTimer),c.__spotifyControlPerfTimer=setTimeout(()=>De(),75)})' 'tracklist observer debounce'
    $Text = Replace-ExactOnce $Text 'var a=new MutationObserver(async()=>{await Be(e)});await Be(e),a.observe(document.body,{childList:!0,subtree:!0}),Ce()' 'var a=new MutationObserver(()=>{clearTimeout(a.__spotifyControlPerfTimer),a.__spotifyControlPerfTimer=setTimeout(()=>{Be(e)},75)});await Be(e),a.observe(document.body,{childList:!0,subtree:!0}),Ce()' 'body observer debounce'
    $Text = Replace-ExactOnce $Text 'for(let e=0;e<f.length;e++)f[e].isEqualNode(y[e])||(t=!0);' 'for(let e=0;e<f.length;e++)f[e]!==y[e]&&(t=!0);' 'tracklist node identity comparison'
    $Text = Replace-ExactOnce $Text '(l=document.querySelector("main"))&&!l.isEqualNode(a)&&' '(l=document.querySelector("main"))&&l!==a&&' 'main node identity comparison'
    $Text = Replace-ExactOnce $Text '(b=document.querySelector(t))&&!b.isEqualNode(O)&&' '(b=document.querySelector(t))&&b!==O&&' 'now-playing node identity comparison'
    $Text = Replace-ExactOnce $Text '(o=document.querySelector(".main-actionBar-ActionBar .ix_8kg3iUb9VS5SmTnBY"))&&!o.isEqualNode(_)&&' '(o=document.querySelector(".main-actionBar-ActionBar .ix_8kg3iUb9VS5SmTnBY"))&&o!==_&&' 'album action node identity comparison'
    return $Text
}

if (-not (Test-Path -LiteralPath $TargetMetadataPath -PathType Leaf)) { throw "Target metadata missing: $TargetMetadataPath" }
$doc = Get-Content -LiteralPath $TargetMetadataPath -Raw | ConvertFrom-Json
if ([int]$doc.schema -ne 1 -or -not $doc.target) { throw 'Unsupported Star Ratings target metadata schema.' }
$target = $doc.target
$activeStatePath = Join-Path $StateRoot 'active-state.json'

if ($Mode -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $activeStatePath -PathType Leaf)) {
        [pscustomobject]@{ schema = 1; mode = 'Restore'; status = 'no-active-state' } | ConvertTo-Json -Depth 8
        exit 0
    }
    $state = Get-Content -LiteralPath $activeStatePath -Raw | ConvertFrom-Json
    $path = [string]$state.path; $backup = [string]$state.backup_path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [pscustomobject]@{ schema = 1; mode = 'Restore'; status = 'conflict-active-file-missing' } | ConvertTo-Json -Depth 8
        exit 0
    }
    $current = Get-FileSha256 $path
    if ($current -eq [string]$state.original_sha256) {
        $archive = Join-Path $StateRoot ('restored-state-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
        Move-Item -LiteralPath $activeStatePath -Destination $archive -Force
        [pscustomobject]@{ schema = 1; mode = 'Restore'; status = 'already-original' } | ConvertTo-Json -Depth 8
        exit 0
    }
    if ($current -ne [string]$state.transformed_sha256) {
        [pscustomobject]@{ schema = 1; mode = 'Restore'; status = 'conflict-newer-or-unknown-active-bytes'; active_sha256 = $current } | ConvertTo-Json -Depth 8
        exit 0
    }
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup missing: $backup" }
    $original = [IO.File]::ReadAllBytes($backup)
    if ((Get-BytesSha256 $original) -ne [string]$state.original_sha256) { throw 'Backup SHA-256 mismatch.' }
    Write-BytesAtomic $path $original
    if ((Get-FileSha256 $path) -ne [string]$state.original_sha256) { throw 'Exact Star Ratings restore verification failed.' }
    $archive = Join-Path $StateRoot ('restored-state-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
    Move-Item -LiteralPath $activeStatePath -Destination $archive -Force
    [pscustomobject]@{ schema = 1; mode = 'Restore'; status = 'restored-exact-original'; original_sha256 = $state.original_sha256 } | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $XpuiRoot -or -not (Test-Path -LiteralPath $XpuiRoot -PathType Container)) { throw 'XpuiRoot is required and must exist for Audit/Apply.' }
$path = Join-Path $XpuiRoot (([string]$target.relative_path) -replace '/', '\')
$exists = Test-Path -LiteralPath $path -PathType Leaf
$activeSize = $null; $activeSha = $null; $eligible = $false; $reason = 'active-file-absent'; $transformedBytes = $null; $transformedSha = $null
if ($exists) {
    $activeSize = [int64](Get-Item -LiteralPath $path).Length
    $activeSha = Get-FileSha256 $path
    if ($activeSize -ne [int64]$target.expected_size -or $activeSha -cne [string]$target.expected_sha256) {
        $reason = 'active-bytes-not-exact-pinned-upstream'
    } else {
        $read = Read-Utf8Exact $path
        $transformedText = Transform-StarRatings $read.Text
        $transformedBytes = ConvertTo-Utf8ExactBytes $transformedText $read.HasBom
        $transformedSha = Get-BytesSha256 $transformedBytes
        if ($transformedSha -cne [string]$target.transformed_sha256) { throw "Star Ratings transformed SHA mismatch: $transformedSha" }
        $eligible = $true; $reason = 'exact-active-bytes'
    }
}

if ($Mode -eq 'Audit') {
    [pscustomobject]@{
        schema = 1; mode = 'Audit'; status = 'audited'; id = $target.id; path = $path;
        eligible = $eligible; reason = $reason; expected_size = [int64]$target.expected_size;
        active_size = $activeSize; expected_sha256 = [string]$target.expected_sha256;
        active_sha256 = $activeSha; transformed_sha256 = $transformedSha;
        source_repository = [string]$target.source_repository; source_revision = [string]$target.source_revision
    } | ConvertTo-Json -Depth 12
    exit 0
}

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
if (Test-Path -LiteralPath $activeStatePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $activeStatePath -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath ([string]$state.path) -PathType Leaf) {
        $current = Get-FileSha256 ([string]$state.path)
        if ($current -eq [string]$state.transformed_sha256) {
            [pscustomobject]@{ schema = 1; mode = 'Apply'; status = 'already-applied'; active_sha256 = $current } | ConvertTo-Json -Depth 8
            exit 0
        }
        if ($current -ne [string]$state.original_sha256) {
            [pscustomobject]@{ schema = 1; mode = 'Apply'; status = 'skipped'; reason = 'state-conflict-newer-or-unknown-active-bytes'; active_sha256 = $current } | ConvertTo-Json -Depth 8
            exit 0
        }
    }
}

if (-not $eligible) {
    [pscustomobject]@{ schema = 1; mode = 'Apply'; status = 'skipped'; reason = $reason; active_sha256 = $activeSha; active_size = $activeSize } | ConvertTo-Json -Depth 8
    exit 0
}
if ((Get-FileSha256 $path) -cne [string]$target.expected_sha256) {
    [pscustomobject]@{ schema = 1; mode = 'Apply'; status = 'skipped'; reason = 'toctou-active-bytes-changed' } | ConvertTo-Json -Depth 8
    exit 0
}

$targetDir = Join-Path $StateRoot ([string]$target.id)
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$backup = Join-Path $targetDir 'original.bin'
$original = [IO.File]::ReadAllBytes($path)
if ((Get-BytesSha256 $original) -cne [string]$target.expected_sha256) {
    [pscustomobject]@{ schema = 1; mode = 'Apply'; status = 'skipped'; reason = 'toctou-active-bytes-changed' } | ConvertTo-Json -Depth 8
    exit 0
}
[IO.File]::WriteAllBytes($backup, $original)
if ((Get-FileSha256 $backup) -cne [string]$target.expected_sha256) { throw 'Star Ratings backup verification failed.' }
$state = [pscustomobject]@{
    schema = 1; id = [string]$target.id; path = $path; backup_path = $backup;
    original_sha256 = [string]$target.expected_sha256; transformed_sha256 = [string]$target.transformed_sha256;
    source_repository = [string]$target.source_repository; source_revision = [string]$target.source_revision;
    prepared_at = (Get-Date).ToString('o')
}
Write-JsonUtf8 $activeStatePath $state
Write-BytesAtomic $path $transformedBytes
$after = Get-FileSha256 $path
if ($after -cne [string]$target.transformed_sha256) { throw "Star Ratings post-write verification failed: $after" }
[pscustomobject]@{
    schema = 1; mode = 'Apply'; status = 'applied'; id = [string]$target.id;
    original_sha256 = [string]$target.expected_sha256; transformed_sha256 = $after
} | ConvertTo-Json -Depth 8
