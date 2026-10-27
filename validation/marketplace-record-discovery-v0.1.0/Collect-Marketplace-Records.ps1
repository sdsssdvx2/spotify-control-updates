param(
    [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'marketplace-records-latest.json'),
    [string]$ReaderPath = (Join-Path $PSScriptRoot 'LevelDbReadOnly.cs')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$CollectorVersion = '0.1.0'
$DbName = 'spicetify-marketplace'
$StoreName = 'settings'
$MigrationMarker = 'internal:local-storage-migrated'
$InstalledLists = [ordered]@{
    extension = 'marketplace:installed-extensions'
    theme = 'marketplace:installed-themes'
    snippet = 'marketplace:installed-snippets'
}

function New-Utf8NoBom { return New-Object System.Text.UTF8Encoding($false) }
function Write-JsonFile([string]$Path,[object]$Value) {
    $parent=Split-Path -Parent $Path
    if($parent -and -not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    [IO.File]::WriteAllBytes($Path,(New-Utf8NoBom).GetBytes(($Value|ConvertTo-Json -Depth 30)+"`n"))
}
function Get-StringSha256([string]$Text) {
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$h.Dispose()}
}
function Get-LevelDbFileFingerprint([string]$Directory) {
    if(-not(Test-Path -LiteralPath $Directory -PathType Container)){return $null}
    $parts=New-Object System.Collections.Generic.List[string]
    foreach($pattern in @('*.ldb','*.sst','*.log')){
        foreach($item in @(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -Force -ErrorAction Stop|Sort-Object Name)){
            $parts.Add(('{0}|{1}|{2}' -f $item.Name,[int64]$item.Length,$item.LastWriteTimeUtc.Ticks))
        }
    }
    return ($parts.ToArray() -join ';')
}
function Read-LevelDbStable([string]$Directory) {
    if(-not(Test-Path -LiteralPath $Directory -PathType Container)){
        return [pscustomobject]@{exists=$false;stable=$true;complete=$false;records=@();errors=@('leveldb-directory-missing');attempts=0}
    }
    for($attempt=1;$attempt -le 3;$attempt++){
        try{
            $before=Get-LevelDbFileFingerprint $Directory
            $read=[SpotifyControlValidation.LevelDbReadOnly]::ReadDirectory($Directory)
            $after=Get-LevelDbFileFingerprint $Directory
            if($before -ceq $after){
                return [pscustomobject]@{exists=$true;stable=$true;complete=[bool]$read.Complete;records=@($read.Records);errors=@($read.Errors);attempts=$attempt}
            }
        }catch{
            if($attempt -eq 3){return [pscustomobject]@{exists=$true;stable=$false;complete=$false;records=@();errors=@(('read-exception:'+$_.Exception.Message));attempts=$attempt}}
        }
        Start-Sleep -Milliseconds (150*$attempt)
    }
    return [pscustomobject]@{exists=$true;stable=$false;complete=$false;records=@();errors=@('leveldb-files-changed-during-read');attempts=3}
}
function Get-IndexedDbDirectories([string]$ProfileRoot) {
    $root=Join-Path $ProfileRoot 'IndexedDB'
    if(-not(Test-Path -LiteralPath $root -PathType Container)){return @()}
    $dirs=@(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue|Where-Object{$_.Name -like '*.leveldb'})
    if($dirs.Count -gt 32){return @()}
    return @($dirs|ForEach-Object{$_.FullName})
}
function Get-RecordIdentity([string]$PrimaryKey,[string]$Kind,[string]$EvidenceSource,[string]$Profile,[bool]$RecordPresent,[bool]$Ambiguous) {
    $owner=$null;$repo=$null;$artifact=$null;$sourceKind='unknown';$sourceUrl=$null
    if($PrimaryKey -like 'marketplace:installed:snippet:*'){
        $sourceKind='snippet-key';$artifact=$PrimaryKey.Substring('marketplace:installed:snippet:'.Length)
    } elseif($PrimaryKey -match '^marketplace:installed:([^/]+)/([^/]+)/(.+)$') {
        $owner=[string]$matches[1];$repo=[string]$matches[2];$artifact=[string]$matches[3]
        $sourceKind='github-repository-key';$sourceUrl=('https://github.com/{0}/{1}' -f $owner,$repo)
    }
    return [pscustomobject]@{
        key=$PrimaryKey;kind=$Kind;record_present=$RecordPresent;profile=$Profile;evidence_source=$EvidenceSource
        source_kind=$sourceKind;github_owner=$owner;github_repo=$repo;artifact_path=$artifact;repository_url=$sourceUrl
        identity_from_marketplace_key=($sourceKind -ne 'unknown');ambiguous=$Ambiguous;mutation_authorized=$false
    }
}
function New-SettingsStoreResult([string]$Profile,[string]$Source,[bool]$Authoritative,[hashtable]$Entries,[string[]]$Errors) {
    $records=New-Object System.Collections.Generic.List[object]
    $individual=@($Entries.Keys|Where-Object{$_ -like 'marketplace:installed:*'}|Sort-Object -Unique)
    foreach($key in $individual){
        $kinds=New-Object System.Collections.Generic.List[string]
        foreach($pair in $InstalledLists.GetEnumerator()){
            if($Entries.ContainsKey([string]$pair.Value)){
                $listEntry=$Entries[[string]$pair.Value]
                if([SpotifyControlValidation.ChromiumIndexedDb]::ContainsEncodedText($listEntry.Value,$key)){$kinds.Add([string]$pair.Key)}
            }
        }
        $kind=if($kinds.Count -eq 1){$kinds[0]}elseif($kinds.Count -eq 0){'unlisted'}else{'ambiguous-multiple-lists'}
        $records.Add((Get-RecordIdentity -PrimaryKey $key -Kind $kind -EvidenceSource $Source -Profile $Profile -RecordPresent $true -Ambiguous ($kinds.Count -ne 1)))
    }
    $dangling=New-Object System.Collections.Generic.List[object]
    foreach($pair in $InstalledLists.GetEnumerator()){
        if(-not $Entries.ContainsKey([string]$pair.Value)){continue}
        $listEntry=$Entries[[string]$pair.Value]
        # We cannot safely deserialize arbitrary Chromium/V8 payloads. Instead, every live individual record key is
        # cross-checked against the list above. Fixture coverage separately proves dangling list references are flagged.
        if($records.Count -eq 0 -and $listEntry.Value.Length -gt 0){$dangling.Add([pscustomobject]@{kind=[string]$pair.Key;reason='nonempty-list-with-no-live-record-keys'})}
    }
    $keys=@($records|ForEach-Object{$_.key}|Sort-Object -Unique)
    return [pscustomobject]@{
        profile=$Profile;source=$Source;authoritative=$Authoritative;status='ok';record_count=$records.Count
        identity_fingerprint=(Get-StringSha256 ($keys -join "`n"));records=$records.ToArray();dangling_signals=$dangling.ToArray();errors=@($Errors)
    }
}
function Get-IndexedDbMarketplaceRecords([string]$Directory,[string]$Profile) {
    $read=Read-LevelDbStable $Directory
    if(-not $read.exists){return [pscustomobject]@{profile=$Profile;source='indexeddb';status='unavailable';authoritative=$false;record_count=0;records=@();errors=@($read.errors)}}
    if(-not $read.stable -or -not $read.complete){return [pscustomobject]@{profile=$Profile;source='indexeddb';status='inconclusive';authoritative=$false;record_count=0;records=@();errors=@($read.errors)}}
    $live=@($read.records|Where-Object{-not $_.Deleted});$dbIds=@()
    foreach($entry in $live){$info=[SpotifyControlValidation.ChromiumIndexedDb]::DecodeDatabaseName($entry);if($info.Success -and [string]$info.Name -ceq $DbName){$dbIds+=[uint64]$info.DatabaseId}}
    $dbIds=@($dbIds|Sort-Object -Unique)
    if($dbIds.Count -eq 0){return [pscustomobject]@{profile=$Profile;source='indexeddb';status='clean-no-marketplace-db';authoritative=$false;record_count=0;records=@();errors=@()}}
    $stores=New-Object System.Collections.Generic.List[object]
    foreach($dbId in $dbIds){
        $storeIds=@()
        foreach($entry in $live){$info=[SpotifyControlValidation.ChromiumIndexedDb]::DecodeObjectStoreName($entry,[uint64]$dbId);if($info.Success -and [string]$info.Name -ceq $StoreName){$storeIds+=[uint64]$info.ObjectStoreId}}
        foreach($storeId in @($storeIds|Sort-Object -Unique)){
            $entries=@{};$dupes=New-Object System.Collections.Generic.List[string]
            foreach($entry in $live){
                $ki=[SpotifyControlValidation.ChromiumIndexedDb]::DecodeObjectStoreStringKey($entry,[uint64]$dbId,[uint64]$storeId)
                if(-not $ki.Success){continue};$pk=[string]$ki.PrimaryKey
                if($entries.ContainsKey($pk)){$dupes.Add($pk)}else{$entries[$pk]=$entry}
            }
            if($dupes.Count){$stores.Add([pscustomobject]@{status='inconclusive-duplicate-primary-keys';authoritative=$false;records=@();errors=@(('duplicate-primary-keys:' + (($dupes.ToArray()|Sort-Object -Unique)-join ','))) });continue}
            $auth=$entries.ContainsKey($MigrationMarker)
            $stores.Add((New-SettingsStoreResult -Profile $Profile -Source 'indexeddb' -Authoritative $auth -Entries $entries -Errors @()))
        }
    }
    if($stores.Count -eq 0){return [pscustomobject]@{profile=$Profile;source='indexeddb';status='inconclusive-no-settings-store';authoritative=$false;record_count=0;records=@();errors=@()}}
    $authStores=@($stores|Where-Object{$_.authoritative})
    if($authStores.Count -gt 1){return [pscustomobject]@{profile=$Profile;source='indexeddb';status='inconclusive-multiple-authoritative-stores';authoritative=$false;record_count=0;records=@();errors=@()}}
    if($authStores.Count -eq 1){return $authStores[0]}
    if($stores.Count -eq 1){return $stores[0]}
    return [pscustomobject]@{profile=$Profile;source='indexeddb';status='inconclusive-multiple-nonauthoritative-stores';authoritative=$false;record_count=0;records=@();errors=@()}
}
function Get-EncodedMarketplaceKeyCandidates([byte[]]$Bytes) {
    if($null -eq $Bytes -or $Bytes.Length -eq 0){return @()}
    $texts=New-Object System.Collections.Generic.List[string]
    try{$texts.Add([Text.Encoding]::UTF8.GetString($Bytes))}catch{}
    foreach($enc in @([Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode)){
        foreach($offset in @(0,1)){
            if($Bytes.Length - $offset -lt 2){continue}
            try{$texts.Add($enc.GetString($Bytes,$offset,$Bytes.Length-$offset))}catch{}
        }
    }
    $found=New-Object System.Collections.Generic.List[string]
    $patterns=@(
        'marketplace:installed-(?:extensions|themes|snippets)',
        'marketplace:installed:snippet:[A-Za-z0-9._+@()\[\]{} -]+',
        'marketplace:installed:[A-Za-z0-9._+@-]+/[A-Za-z0-9._+@-]+/[A-Za-z0-9._+@/\\ -]+'
    )
    foreach($text in $texts){foreach($pattern in $patterns){foreach($m in [regex]::Matches($text,$pattern)){if($m.Value){$found.Add($m.Value.TrimEnd(' ',[char]0))}}}}
    return @($found.ToArray()|Sort-Object -Unique)
}
function Get-LocalStorageMarketplaceRecords([string]$Directory,[string]$Profile) {
    $read=Read-LevelDbStable $Directory
    if(-not $read.exists){return [pscustomobject]@{profile=$Profile;source='local-storage';status='unavailable';authoritative=$false;record_count=0;records=@();errors=@($read.errors)}}
    if(-not $read.stable -or -not $read.complete){return [pscustomobject]@{profile=$Profile;source='local-storage';status='inconclusive';authoritative=$false;record_count=0;records=@();errors=@($read.errors)}}
    $entries=@{};$ambiguous=$false
    foreach($entry in @($read.records|Where-Object{-not $_.Deleted})){
        $candidates=@(Get-EncodedMarketplaceKeyCandidates $entry.Key)
        foreach($pk in $candidates){
            if($entries.ContainsKey($pk)){$ambiguous=$true}else{$entries[$pk]=$entry}
        }
    }
    if($ambiguous){return [pscustomobject]@{profile=$Profile;source='local-storage';status='inconclusive-ambiguous-live-records';authoritative=$false;record_count=0;records=@();errors=@()}}
    return New-SettingsStoreResult -Profile $Profile -Source 'local-storage' -Authoritative $false -Entries $entries -Errors @()
}
function Get-ProfileMarketplaceRecords([string]$Profile,[string]$ProfileRoot) {
    if(-not(Test-Path -LiteralPath $ProfileRoot -PathType Container)){return [pscustomobject]@{profile=$Profile;exists=$false;status='not-present';selected_source=$null;record_count=0;records=@();indexeddb=@();local_storage=$null}}
    $idb=@();foreach($dir in @(Get-IndexedDbDirectories $ProfileRoot)){$idb+=Get-IndexedDbMarketplaceRecords $dir $Profile}
    $local=Get-LocalStorageMarketplaceRecords (Join-Path $ProfileRoot 'Local Storage\leveldb') $Profile
    $auth=@($idb|Where-Object{$_.authoritative -and $_.status -eq 'ok'})
    if($auth.Count -eq 1){$selected=$auth[0];$status='indexeddb-authoritative'}
    elseif($auth.Count -gt 1){$selected=$null;$status='inconclusive-multiple-authoritative-indexeddb'}
    else{
        $okIdb=@($idb|Where-Object{$_.status -eq 'ok'})
        if($okIdb.Count -eq 1 -and $okIdb[0].record_count -gt 0){$selected=$okIdb[0];$status='indexeddb-fallback'}
        elseif($local.status -eq 'ok' -and $local.record_count -gt 0){$selected=$local;$status='local-storage-fallback'}
        elseif(@($idb|Where-Object{$_.status -like 'inconclusive*'}).Count -gt 0 -or $local.status -like 'inconclusive*'){$selected=$null;$status='inconclusive'}
        else{$selected=[pscustomobject]@{records=@();record_count=0;source='none'};$status='empty'}
    }
    return [pscustomobject]@{profile=$Profile;exists=$true;status=$status;selected_source=$(if($selected){$selected.source}else{$null});record_count=$(if($selected){[int]$selected.record_count}else{0});records=$(if($selected){@($selected.records)}else{@()});indexeddb=$idb;local_storage=$local}
}

if(-not(Test-Path -LiteralPath $ReaderPath -PathType Leaf)){throw "Reader source missing: $ReaderPath"}
Add-Type -Path $ReaderPath -ErrorAction Stop
$profiles=@(
    Get-ProfileMarketplaceRecords -Profile 'Browser' -ProfileRoot (Join-Path $LocalAppDataRoot 'Spotify\Browser')
    Get-ProfileMarketplaceRecords -Profile 'Default' -ProfileRoot (Join-Path $LocalAppDataRoot 'Spotify\Default')
)
$all=New-Object System.Collections.Generic.List[object]
foreach($p in $profiles){foreach($r in @($p.records)){$all.Add($r)}}
$grouped=@($all.ToArray()|Group-Object key|Sort-Object Name)
$union=New-Object System.Collections.Generic.List[object];$conflicts=New-Object System.Collections.Generic.List[string]
foreach($g in $grouped){
    $rows=@($g.Group);$kinds=@($rows|ForEach-Object{$_.kind}|Sort-Object -Unique);$sources=@($rows|ForEach-Object{$_.source_kind}|Sort-Object -Unique)
    if($kinds.Count -gt 1 -or $sources.Count -gt 1){$conflicts.Add([string]$g.Name)}
    $first=$rows[0]
    $union.Add([pscustomobject]@{key=[string]$g.Name;kind=$(if($kinds.Count -eq 1){$kinds[0]}else{'conflict'});source_kind=$(if($sources.Count -eq 1){$sources[0]}else{'conflict'});github_owner=$first.github_owner;github_repo=$first.github_repo;artifact_path=$first.artifact_path;repository_url=$first.repository_url;profiles=@($rows|ForEach-Object{$_.profile}|Sort-Object -Unique);mutation_authorized=$false})
}
$profileInconclusive=@($profiles|Where-Object{$_.status -like 'inconclusive*'})
$status=if($profileInconclusive.Count -gt 0 -or $conflicts.Count -gt 0){'inconclusive'}else{'ok'}
$keys=@($union.ToArray()|ForEach-Object{$_.key}|Sort-Object -Unique)
$report=[ordered]@{
    schema=1;collector_version=$CollectorVersion;generated_utc=[DateTime]::UtcNow.ToString('o');read_only=$true;mutation_performed=$false
    marketplace_contract=[ordered]@{database=$DbName;store=$StoreName;migration_marker=$MigrationMarker;installed_lists=$InstalledLists;source_key_rule='marketplace:installed:<github-owner>/<github-repo>/<artifact-path>';upstream_commit='7f357885a3514a55d426fd43edfd705d583a5cdd'}
    status=$status;record_count=$union.Count;identity_fingerprint=(Get-StringSha256 ($keys -join "`n"));records=$union.ToArray();profile_conflicts=$conflicts.ToArray();profiles=$profiles
    derived=[ordered]@{safe_to_expand_mutation_authority=$false;next_decision='merge-read-only-marketplace-identity-with-lifecycle-ledger-after-real-pc-evidence'}
}
Write-JsonFile $OutputPath $report
Write-Host ('Marketplace record discovery: {0}; records={1}' -f $status,$union.Count)
Write-Host 'No Spotify, Spicetify, Marketplace, IndexedDB, Local Storage, or addon data was modified.'
Write-Host ('Report: {0}' -f $OutputPath)
