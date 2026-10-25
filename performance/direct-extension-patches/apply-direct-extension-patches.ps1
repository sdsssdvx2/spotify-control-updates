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
if (-not $TargetMetadataPath) { $TargetMetadataPath = Join-Path $ScriptRoot 'targets.json' }
if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'StateRoot is required when LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'SpotifyControl\direct-extension-performance-patches'
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-Utf8Exact([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset=0; $count=$bytes.Length
    if($hasBom){$offset=3;$count-=3}
    $enc=New-Object Text.UTF8Encoding($false,$true)
    try { $text=$enc.GetString($bytes,$offset,$count) }
    catch { throw "Refusing patch because $Path is not strict UTF-8: $($_.Exception.Message)" }
    return [pscustomobject]@{Bytes=$bytes;Text=$text;HasBom=$hasBom}
}

function ConvertTo-Utf8ExactBytes([string]$Text,[bool]$HasBom) {
    $enc=New-Object Text.UTF8Encoding($false)
    $body=$enc.GetBytes($Text)
    if(-not $HasBom){return $body}
    $out=New-Object byte[] ($body.Length+3)
    $out[0]=0xEF;$out[1]=0xBB;$out[2]=0xBF
    [Array]::Copy($body,0,$out,3,$body.Length)
    return $out
}

function Write-BytesAtomic([string]$Path,[byte[]]$Bytes) {
    $dir=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $dir -PathType Container)){throw "Parent directory missing: $dir"}
    $leaf=[IO.Path]::GetFileName($Path);$nonce=[Guid]::NewGuid().ToString('N')
    $tmp=Join-Path $dir ($leaf+'.scperf.'+$nonce+'.tmp')
    $replaceBackup=Join-Path $dir ($leaf+'.scperf.'+$nonce+'.replace-backup')
    try {
        [IO.File]::WriteAllBytes($tmp,$Bytes)
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,$replaceBackup)}else{[IO.File]::Move($tmp,$Path)}
    } finally {
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
        if(Test-Path -LiteralPath $replaceBackup){Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue}
    }
}

function Write-JsonUtf8([string]$Path,[object]$Value) {
    $parent=Split-Path -Parent $Path
    if($parent){New-Item -ItemType Directory -Force -Path $parent | Out-Null}
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Value|ConvertTo-Json -Depth 20))
    [IO.File]::WriteAllBytes($Path,$bytes)
}

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw "Expected transform anchor missing: $Label"}
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw "Expected transform anchor is ambiguous: $Label"}
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

function Transform-PopupLyrics([string]$Text) {
    $nl=$(if($Text.Contains("`r`n")){"`r`n"}else{"`n"});$tab="`t"
    $old=@(
        $tab+'let workerIsRunning = null;',
        $tab+'document.addEventListener("visibilitychange", (e) => {',
        $tab+$tab+'if (e.target.hidden) {',
        $tab+$tab+$tab+'if (!workerIsRunning) {',
        $tab+$tab+$tab+$tab+'worker.postMessage("popup-lyric-request-update");',
        $tab+$tab+$tab+$tab+'workerIsRunning = true;',
        $tab+$tab+$tab+'}',
        $tab+$tab+'} else {',
        $tab+$tab+$tab+'if (workerIsRunning) {',
        $tab+$tab+$tab+$tab+'worker.postMessage("popup-lyric-stop-update");',
        $tab+$tab+$tab+$tab+'workerIsRunning = false;',
        $tab+$tab+$tab+'}',
        $tab+$tab+'}',
        $tab+'});'
    ) -join $nl
    $new=@(
        $tab+'let workerIsRunning = false;',
        $tab+'function syncWorkerState() {',
        $tab+$tab+'const shouldRun = lyricVideoIsOpen && document.hidden;',
        $tab+$tab+'if (shouldRun === workerIsRunning) return;',
        $tab+$tab+'worker.postMessage(shouldRun ? "popup-lyric-request-update" : "popup-lyric-stop-update");',
        $tab+$tab+'workerIsRunning = shouldRun;',
        $tab+'}',
        $tab+'document.addEventListener("visibilitychange", syncWorkerState);'
    ) -join $nl
    $Text=Replace-ExactOnce $Text $old $new 'popup visibility worker gate'

    $old2=@(
        $tab+'lyricVideo.onenterpictureinpicture = () => {',
        $tab+$tab+'lyricVideo.play();',
        $tab+$tab+'lyricVideoIsOpen = true;',
        $tab+$tab+'tick(userConfigs);',
        $tab+$tab+'updateTrack();',
        $tab+'};',
        $tab+'lyricVideo.onleavepictureinpicture = () => {',
        $tab+$tab+'lyricVideoIsOpen = false;',
        $tab+'};'
    ) -join $nl
    $new2=@(
        $tab+'lyricVideo.onenterpictureinpicture = () => {',
        $tab+$tab+'lyricVideo.play();',
        $tab+$tab+'lyricVideoIsOpen = true;',
        $tab+$tab+'syncWorkerState();',
        $tab+$tab+'tick(userConfigs);',
        $tab+$tab+'updateTrack();',
        $tab+'};',
        $tab+'lyricVideo.onleavepictureinpicture = () => {',
        $tab+$tab+'lyricVideoIsOpen = false;',
        $tab+$tab+'syncWorkerState();',
        $tab+'};'
    ) -join $nl
    return Replace-ExactOnce $Text $old2 $new2 'popup PiP lifecycle worker sync'
}

function Transform-StarRatings([string]$Text) {
    $Text=Replace-ExactOnce $Text 'c=new MutationObserver(()=>{De()})' 'c=new MutationObserver(()=>{clearTimeout(c.__spotifyControlPerfTimer),c.__spotifyControlPerfTimer=setTimeout(()=>De(),75)})' 'star tracklist observer debounce'
    $Text=Replace-ExactOnce $Text 'var a=new MutationObserver(async()=>{await Be(e)});await Be(e),a.observe(document.body,{childList:!0,subtree:!0}),Ce()' 'var a=new MutationObserver(()=>{clearTimeout(a.__spotifyControlPerfTimer),a.__spotifyControlPerfTimer=setTimeout(()=>{Be(e)},75)});await Be(e),a.observe(document.body,{childList:!0,subtree:!0}),Ce()' 'star body observer debounce'
    $Text=Replace-ExactOnce $Text 'for(let e=0;e<f.length;e++)f[e].isEqualNode(y[e])||(t=!0);' 'for(let e=0;e<f.length;e++)f[e]!==y[e]&&(t=!0);' 'star tracklist identity comparison'
    $Text=Replace-ExactOnce $Text '(l=document.querySelector("main"))&&!l.isEqualNode(a)&&' '(l=document.querySelector("main"))&&l!==a&&' 'star main element identity comparison'
    $Text=Replace-ExactOnce $Text '(b=document.querySelector(t))&&!b.isEqualNode(O)&&' '(b=document.querySelector(t))&&b!==O&&' 'star now-playing identity comparison'
    $Text=Replace-ExactOnce $Text '(o=document.querySelector(".main-actionBar-ActionBar .ix_8kg3iUb9VS5SmTnBY"))&&!o.isEqualNode(_)&&' '(o=document.querySelector(".main-actionBar-ActionBar .ix_8kg3iUb9VS5SmTnBY"))&&o!==_&&' 'star album action identity comparison'
    return $Text
}

function Transform-Target([object]$Target,[string]$Text) {
    switch([string]$Target.patch_kind){
        'popup-worker-gate' { return Transform-PopupLyrics $Text }
        'star-ratings-observer-debounce' { return Transform-StarRatings $Text }
        default { throw "Unsupported patch kind: $($Target.patch_kind)" }
    }
}

function Get-Plan([object]$Target,[string]$XpuiRoot) {
    $path=Join-Path $XpuiRoot (([string]$Target.relative_path)-replace '/','\')
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
        return [pscustomobject]@{id=$Target.id;path=$path;eligible=$false;reason='active-file-absent';expected_sha256=$Target.expected_sha256;active_sha256=$null;active_size=$null;transformed_sha256=$null;transformed_bytes=$null}
    }
    $size=[int64](Get-Item -LiteralPath $path).Length;$sha=Get-FileSha256 $path
    if($size -ne [int64]$Target.expected_size -or $sha -ne [string]$Target.expected_sha256){
        return [pscustomobject]@{id=$Target.id;path=$path;eligible=$false;reason='active-bytes-not-exact-pinned-upstream';expected_sha256=$Target.expected_sha256;active_sha256=$sha;active_size=$size;transformed_sha256=$null;transformed_bytes=$null}
    }
    $read=Read-Utf8Exact $path
    $transformed=Transform-Target $Target $read.Text
    $bytes=ConvertTo-Utf8ExactBytes $transformed $read.HasBom
    return [pscustomobject]@{id=$Target.id;path=$path;eligible=$true;reason='exact-active-bytes';expected_sha256=$Target.expected_sha256;active_sha256=$sha;active_size=$size;transformed_sha256=(Get-BytesSha256 $bytes);transformed_bytes=$bytes}
}

if(-not (Test-Path -LiteralPath $TargetMetadataPath -PathType Leaf)){throw "Target metadata missing: $TargetMetadataPath"}
$doc=Get-Content -LiteralPath $TargetMetadataPath -Raw|ConvertFrom-Json
if([int]$doc.schema -ne 1){throw 'Unsupported target metadata schema.'}
$activeStatePath=Join-Path $StateRoot 'active-state.json'

if($Mode -eq 'Restore'){
    if(-not (Test-Path -LiteralPath $activeStatePath -PathType Leaf)){
        [pscustomobject]@{schema=1;mode='Restore';status='no-active-state';targets=@()}|ConvertTo-Json -Depth 12
        exit 0
    }
    $state=Get-Content -LiteralPath $activeStatePath -Raw|ConvertFrom-Json
    $results=New-Object Collections.Generic.List[object]
    $allResolved=$true
    foreach($entry in @($state.targets)){
        $path=[string]$entry.path;$backup=[string]$entry.backup_path
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
            $allResolved=$false;$results.Add([pscustomobject]@{id=$entry.id;status='conflict-active-file-missing'});continue
        }
        $sha=Get-FileSha256 $path
        if($sha -eq [string]$entry.original_sha256){$results.Add([pscustomobject]@{id=$entry.id;status='already-original'});continue}
        if($sha -ne [string]$entry.transformed_sha256){$allResolved=$false;$results.Add([pscustomobject]@{id=$entry.id;status='conflict-newer-or-unknown-active-bytes';active_sha256=$sha});continue}
        if(-not (Test-Path -LiteralPath $backup -PathType Leaf)){throw "Backup missing for $($entry.id): $backup"}
        $bytes=[IO.File]::ReadAllBytes($backup)
        if((Get-BytesSha256 $bytes) -ne [string]$entry.original_sha256){throw "Backup SHA mismatch for $($entry.id)"}
        Write-BytesAtomic $path $bytes
        if((Get-FileSha256 $path) -ne [string]$entry.original_sha256){throw "Restore verification failed for $($entry.id)"}
        $results.Add([pscustomobject]@{id=$entry.id;status='restored-exact-original'})
    }
    if($allResolved){
        $archive=Join-Path $StateRoot ('restored-state-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'.json')
        Move-Item -LiteralPath $activeStatePath -Destination $archive -Force
    }
    [pscustomobject]@{schema=1;mode='Restore';status=$(if($allResolved){'restored'}else{'restore-conflict-preserved'});targets=$results.ToArray()}|ConvertTo-Json -Depth 12
    exit $(if($allResolved){0}else{2})
}

if(-not $XpuiRoot){throw 'XpuiRoot is required for Audit/Apply.'}
if(-not (Test-Path -LiteralPath $XpuiRoot -PathType Container)){throw "xpui root missing: $XpuiRoot"}
$plans=New-Object Collections.Generic.List[object]
foreach($target in @($doc.targets)){$plans.Add((Get-Plan $target $XpuiRoot))}

if($Mode -eq 'Audit'){
    $view=@($plans|ForEach-Object{[pscustomobject]@{id=$_.id;path=$_.path;eligible=$_.eligible;reason=$_.reason;expected_sha256=$_.expected_sha256;active_sha256=$_.active_sha256;active_size=$_.active_size;transformed_sha256=$_.transformed_sha256}})
    [pscustomobject]@{schema=1;mode='Audit';status='audited';targets=$view}|ConvertTo-Json -Depth 12
    exit 0
}

New-Item -ItemType Directory -Force -Path $StateRoot|Out-Null
$existing=@{}
if(Test-Path -LiteralPath $activeStatePath -PathType Leaf){
    $old=Get-Content -LiteralPath $activeStatePath -Raw|ConvertFrom-Json
    foreach($entry in @($old.targets)){$existing[[string]$entry.id]=$entry}
}
$stateTargets=New-Object Collections.Generic.List[object]
$results=New-Object Collections.Generic.List[object]
foreach($plan in $plans){
    if($existing.ContainsKey([string]$plan.id)){
        $entry=$existing[[string]$plan.id];$current=$(if(Test-Path -LiteralPath $entry.path -PathType Leaf){Get-FileSha256 $entry.path}else{$null})
        if($current -eq [string]$entry.transformed_sha256){$stateTargets.Add($entry);$results.Add([pscustomobject]@{id=$plan.id;status='already-applied'});continue}
        if($current -ne [string]$entry.original_sha256){$stateTargets.Add($entry);$results.Add([pscustomobject]@{id=$plan.id;status='conflict-newer-or-unknown-active-bytes';active_sha256=$current});continue}
    }
    if(-not $plan.eligible){$results.Add([pscustomobject]@{id=$plan.id;status='skipped';reason=$plan.reason;active_sha256=$plan.active_sha256});continue}
    if((Get-FileSha256 $plan.path) -ne [string]$plan.expected_sha256){$results.Add([pscustomobject]@{id=$plan.id;status='skipped-toctou-active-bytes-changed'});continue}
    $targetDir=Join-Path $StateRoot ([string]$plan.id)
    New-Item -ItemType Directory -Force -Path $targetDir|Out-Null
    $backup=Join-Path $targetDir 'original.bin'
    $original=[IO.File]::ReadAllBytes($plan.path)
    if((Get-BytesSha256 $original) -ne [string]$plan.expected_sha256){$results.Add([pscustomobject]@{id=$plan.id;status='skipped-toctou-active-bytes-changed'});continue}
    [IO.File]::WriteAllBytes($backup,$original)
    if((Get-FileSha256 $backup) -ne [string]$plan.expected_sha256){throw "Backup verification failed for $($plan.id)"}
    $entry=[pscustomobject]@{id=$plan.id;path=$plan.path;backup_path=$backup;original_sha256=$plan.expected_sha256;transformed_sha256=$plan.transformed_sha256;status='prepared';prepared_at=(Get-Date).ToString('o')}
    $stateTargets.Add($entry)
    Write-JsonUtf8 $activeStatePath ([pscustomobject]@{schema=1;updated_at=(Get-Date).ToString('o');targets=$stateTargets.ToArray()})
    Write-BytesAtomic $plan.path $plan.transformed_bytes
    if((Get-FileSha256 $plan.path) -ne [string]$plan.transformed_sha256){throw "Post-patch verification failed for $($plan.id)"}
    $entry.status='applied';$entry|Add-Member -NotePropertyName applied_at -NotePropertyValue ((Get-Date).ToString('o')) -Force
    Write-JsonUtf8 $activeStatePath ([pscustomobject]@{schema=1;updated_at=(Get-Date).ToString('o');targets=$stateTargets.ToArray()})
    $results.Add([pscustomobject]@{id=$plan.id;status='applied';original_sha256=$plan.expected_sha256;transformed_sha256=$plan.transformed_sha256})
}

[pscustomobject]@{schema=1;mode='Apply';status='completed';targets=$results.ToArray()}|ConvertTo-Json -Depth 12
