from __future__ import annotations

from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / "validation/v0.6.28/out/bin"
OUT = ROOT / "validation/persistence-transaction-guard-v0.1.0/out/bin"
REPORT = ROOT / "validation/persistence-transaction-guard-v0.1.0/candidate-report.json"

BASE_ADDON_SIZE = 323385
BASE_ADDON_SHA = "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
BASE_MAIN_SIZE = 284321
BASE_MAIN_SHA = "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"
AUTHORIZED_NAMES = ["better-local-files", "eternal-jukebox", "ivLyrics", "playlist-maker"]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def function_bounds(text: str, name: str) -> tuple[int, int]:
    marker = f"function {name} {{"
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"missing function {name}")
    nxt = text.find("\nfunction ", start + len(marker))
    if nxt < 0:
        nxt = len(text)
    return start, nxt


def function_block(text: str, name: str) -> str:
    a, b = function_bounds(text, name)
    return text[a:b].rstrip()


def replace_function(text: str, name: str, block: str) -> str:
    a, b = function_bounds(text, name)
    return text[:a] + block.rstrip() + text[b:]


def build_base() -> tuple[bytes, bytes]:
    subprocess.check_call([sys.executable, str(ROOT / "validation/v0.6.28/build_v0628.py"), "--build"], cwd=ROOT)
    main = (BASE_OUT / "spotify-control.ps1").read_bytes()
    addon = (BASE_OUT / "addon-manager.ps1").read_bytes()
    if (len(main), sha(main)) != (BASE_MAIN_SIZE, BASE_MAIN_SHA):
        raise RuntimeError(f"v0.6.28 main drift: {len(main)} {sha(main)}")
    if (len(addon), sha(addon)) != (BASE_ADDON_SIZE, BASE_ADDON_SHA):
        raise RuntimeError(f"r17 addon drift: {len(addon)} {sha(addon)}")
    return main, addon


HELPERS = r'''
function Get-SpotifyPersistenceGuardTargets {
    param([string]$SpotifyRoot=$(Join-Path $env:LOCALAPPDATA 'Spotify'))
    if([string]::IsNullOrWhiteSpace($SpotifyRoot)){throw 'Spotify persistence guard root is empty.'}
    $root=[System.IO.Path]::GetFullPath($SpotifyRoot).TrimEnd([char[]]@([char]92,[char]47))
    $items=New-Object System.Collections.Generic.List[object]
    foreach($profileName in @('Browser','Default')){
        $profile=Join-Path $root $profileName
        $prefix=$profileName.ToLowerInvariant()
        foreach($storage in @(
            [pscustomobject]@{Suffix='indexeddb';Name='IndexedDB'},
            [pscustomobject]@{Suffix='local-storage';Name='Local Storage'},
            [pscustomobject]@{Suffix='session-storage';Name='Session Storage'},
            [pscustomobject]@{Suffix='webstorage';Name='WebStorage'}
        )){
            $items.Add([pscustomobject]@{key=($prefix+'-'+[string]$storage.Suffix);type='directory';path=(Join-Path $profile ([string]$storage.Name))})
        }
        $items.Add([pscustomobject]@{key=($prefix+'-local-state');type='file';path=(Join-Path $profile 'Local State')})
        $items.Add([pscustomobject]@{key=($prefix+'-preferences');type='file';path=(Join-Path $profile 'Preferences')})
    }
    $items.Add([pscustomobject]@{key='root-indexeddb';type='directory';path=(Join-Path $root 'IndexedDB')})
    $items.Add([pscustomobject]@{key='root-local-storage';type='directory';path=(Join-Path $root 'Local Storage')})
    return @($items.ToArray())
}

function Get-SpotifyPersistenceGuardTargetSnapshot {
    param([Parameter(Mandatory=$true)]$Target)
    $key=[string]$Target.key;$type=[string]$Target.type;$path=[System.IO.Path]::GetFullPath([string]$Target.path)
    if($key -notmatch '^[a-z0-9-]+$'){throw "Unsafe persistence target key: $key"}
    if($type -notin @('directory','file')){throw "Unsupported persistence target type for ${key}: $type"}
    $exists=if($type -ceq 'directory'){Test-PathSafe $path 'Container'}else{Test-PathSafe $path 'Leaf'}
    if(-not $exists){return [pscustomobject]@{key=$key;type=$type;path=$path;exists=$false;size=[int64]0;count=0;fingerprint=$null;sha256=$null;backup_rel=$null}}
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "Persistence guard target is a reparse point: $path"}
    if($type -ceq 'directory'){
        $snap=Get-DirectoryGitSnapshot $path
        $size=[int64]0;foreach($file in @($snap.files)){$size += [int64]$file.size}
        return [pscustomobject]@{key=$key;type=$type;path=$path;exists=$true;size=$size;count=[int]$snap.count;fingerprint=[string]$snap.fingerprint;sha256=$null;backup_rel=($key+'.dir')}
    }
    $size=[int64]$item.Length
    $fileSha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $fp=Get-TextSha256 ("file`t{0}`t{1}`n" -f $size,$fileSha)
    return [pscustomobject]@{key=$key;type=$type;path=$path;exists=$true;size=$size;count=1;fingerprint=$fp;sha256=$fileSha;backup_rel=($key+'.file')}
}

function Get-SpotifyPersistenceGuardFingerprint {
    param([Parameter(Mandatory=$true)]$Entries)
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($row in @($Entries|Sort-Object -Property key)){
        $exists=if([bool]$row.exists){'1'}else{'0'}
        $fp=if([string]::IsNullOrWhiteSpace([string]$row.fingerprint)){'-'}else{[string]$row.fingerprint}
        $lines.Add(("{0}|{1}|{2}|{3}|{4}|{5}" -f [string]$row.key,[string]$row.type,$exists,[int64]$row.size,[int]$row.count,$fp))
    }
    return Get-TextSha256 (($lines.ToArray() -join "`n")+"`n")
}

function Assert-SpotifyPersistenceGuardBackup {
    param([string]$BackupPath,[string]$ManifestSha256)
    if([string]::IsNullOrWhiteSpace($BackupPath) -or -not (Test-PathSafe $BackupPath 'Container')){throw 'Persistence transaction backup root is missing.'}
    $rootItem=Get-Item -LiteralPath $BackupPath -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Persistence transaction backup root is a reparse point.'}
    $manifestPath=Join-Path $BackupPath 'manifest.json'
    if(-not(Test-PathSafe $manifestPath 'Leaf')){throw 'Persistence transaction manifest is missing.'}
    $actualManifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$actualManifestSha -cne [string]$ManifestSha256){throw 'Persistence transaction manifest SHA-256 mismatch.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if([int]$manifest.schema -ne 1){throw "Unsupported persistence transaction manifest schema: $($manifest.schema)"}
    if([string]::IsNullOrWhiteSpace([string]$manifest.spotify_root)){throw 'Persistence transaction manifest Spotify root is empty.'}
    $expectedTargets=@(Get-SpotifyPersistenceGuardTargets -SpotifyRoot ([string]$manifest.spotify_root))
    $entries=@($manifest.entries)
    if($entries.Count -ne $expectedTargets.Count){throw 'Persistence transaction manifest target cardinality mismatch.'}
    $expectedByKey=@{};foreach($target in $expectedTargets){$expectedByKey[[string]$target.key]=$target}
    foreach($entry in $entries){
        $key=[string]$entry.key
        if(-not $expectedByKey.ContainsKey($key)){throw "Unknown persistence transaction target key: $key"}
        $expected=$expectedByKey[$key]
        if([string]$entry.type -cne [string]$expected.type){throw "Persistence transaction target type mismatch: $key"}
        $entryPath=[System.IO.Path]::GetFullPath([string]$entry.path)
        $expectedPath=[System.IO.Path]::GetFullPath([string]$expected.path)
        if($entryPath -cne $expectedPath){throw "Persistence transaction target path mismatch: $key"}
        if([bool]$entry.exists){
            $rel=[string]$entry.backup_rel
            if($rel -cne ($key+$(if([string]$entry.type -ceq 'directory'){'.dir'}else{'.file'}))){throw "Persistence transaction backup relative path mismatch: $key"}
            $backup=Join-Path $BackupPath $rel
            if([string]$entry.type -ceq 'directory'){
                if(-not(Test-PathSafe $backup 'Container')){throw "Persistence directory backup is missing: $key"}
                $snap=Get-DirectoryGitSnapshot $backup
                $size=[int64]0;foreach($file in @($snap.files)){$size += [int64]$file.size}
                if([string]$snap.fingerprint -cne [string]$entry.fingerprint -or [int]$snap.count -ne [int]$entry.count -or $size -ne [int64]$entry.size){throw "Persistence directory backup verification failed: $key"}
            }else{
                if(-not(Test-PathSafe $backup 'Leaf')){throw "Persistence file backup is missing: $key"}
                $bi=Get-Item -LiteralPath $backup -Force -ErrorAction Stop
                if(($bi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "Persistence file backup is a reparse point: $key"}
                $bsha=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant()
                if([int64]$bi.Length -ne [int64]$entry.size -or [string]$bsha -cne [string]$entry.sha256){throw "Persistence file backup verification failed: $key"}
            }
        }elseif(-not [string]::IsNullOrWhiteSpace([string]$entry.backup_rel)){throw "Absent persistence target unexpectedly has a backup path: $key"}
    }
    $before=Get-SpotifyPersistenceGuardFingerprint -Entries $entries
    if([string]$before -cne [string]$manifest.before_fingerprint){throw 'Persistence transaction manifest canonical fingerprint mismatch.'}
    return $manifest
}

function New-SpotifyPersistenceTransactionSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$SnapshotId,
        [string]$SpotifyRoot=$(Join-Path $env:LOCALAPPDATA 'Spotify'),
        [string]$BackupBaseRoot=$AddonTransactionBackupRoot
    )
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing persistence transaction snapshot.'}
    if($SnapshotId -notmatch '^[A-Za-z0-9._-]+$'){throw 'Persistence transaction snapshot id is unsafe.'}
    $backupPath=Join-Path (Join-Path $BackupBaseRoot $SnapshotId) 'persistence'
    if(Test-PathSafe $backupPath 'Any'){throw "Persistence transaction snapshot already exists: $backupPath"}
    New-Item -ItemType Directory -Force -Path $backupPath|Out-Null
    try{
        $entries=New-Object System.Collections.Generic.List[object]
        foreach($target in @(Get-SpotifyPersistenceGuardTargets -SpotifyRoot $SpotifyRoot)){
            $snap=Get-SpotifyPersistenceGuardTargetSnapshot -Target $target
            if([bool]$snap.exists){
                $backup=Join-Path $backupPath ([string]$snap.backup_rel)
                if([string]$snap.type -ceq 'directory'){
                    New-Item -ItemType Directory -Force -Path $backup|Out-Null
                    Copy-DirectoryContentsExact -Source ([string]$snap.path) -Destination $backup
                }else{
                    Copy-Item -LiteralPath ([string]$snap.path) -Destination $backup -Force
                }
            }
            $entries.Add($snap)
        }
        $before=Get-SpotifyPersistenceGuardFingerprint -Entries $entries.ToArray()
        $manifest=[pscustomobject]@{schema=1;created_at=(Get-Date).ToString('o');spotify_root=[System.IO.Path]::GetFullPath($SpotifyRoot);before_fingerprint=$before;entries=$entries.ToArray()}
        $manifestPath=Join-Path $backupPath 'manifest.json'
        $manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $manifestPath -Encoding UTF8
        $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [void](Assert-SpotifyPersistenceGuardBackup -BackupPath $backupPath -ManifestSha256 $manifestSha)
        return [pscustomobject]@{schema=1;backup_path=$backupPath;manifest_sha256=$manifestSha;before_fingerprint=$before;target_count=$entries.Count}
    }catch{
        if(Test-PathSafe $backupPath 'Container'){Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue}
        throw
    }
}

function Test-SpotifyPersistenceTransactionSnapshot {
    param([string]$BackupPath,[string]$ManifestSha256)
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing persistence transaction verification.'}
    $manifest=Assert-SpotifyPersistenceGuardBackup -BackupPath $BackupPath -ManifestSha256 $ManifestSha256
    $current=New-Object System.Collections.Generic.List[object]
    $drift=New-Object System.Collections.Generic.List[string]
    foreach($entry in @($manifest.entries)){
        $target=[pscustomobject]@{key=[string]$entry.key;type=[string]$entry.type;path=[string]$entry.path}
        $now=Get-SpotifyPersistenceGuardTargetSnapshot -Target $target
        $current.Add($now)
        if([bool]$now.exists -ne [bool]$entry.exists -or [int64]$now.size -ne [int64]$entry.size -or [int]$now.count -ne [int]$entry.count -or [string]$now.fingerprint -cne [string]$entry.fingerprint){$drift.Add([string]$entry.key)}
    }
    $fingerprint=Get-SpotifyPersistenceGuardFingerprint -Entries $current.ToArray()
    return [pscustomobject]@{Valid=($drift.Count -eq 0 -and [string]$fingerprint -ceq [string]$manifest.before_fingerprint);ExpectedFingerprint=[string]$manifest.before_fingerprint;CurrentFingerprint=$fingerprint;DriftKeys=$drift.ToArray()}
}

function Restore-SpotifyPersistenceTransactionSnapshot {
    param([string]$BackupPath,[string]$ManifestSha256)
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing persistence transaction restore.'}
    # This verifies every backup and every fixed target path before the first live persistence mutation.
    $manifest=Assert-SpotifyPersistenceGuardBackup -BackupPath $BackupPath -ManifestSha256 $ManifestSha256
    foreach($entry in @($manifest.entries)){
        $path=[string]$entry.path;$type=[string]$entry.type;$key=[string]$entry.key
        if(-not [bool]$entry.exists){
            if(Test-PathSafe $path 'Any'){Remove-Item -LiteralPath $path -Recurse -Force}
            continue
        }
        $backup=Join-Path $BackupPath ([string]$entry.backup_rel)
        $parent=Split-Path -Parent $path
        New-Item -ItemType Directory -Force -Path $parent|Out-Null
        if($type -ceq 'directory'){
            $stage=Join-Path $parent ('.spotifycontrol-persistence-restore-'+$key+'-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $stage|Out-Null
            try{
                Copy-DirectoryContentsExact -Source $backup -Destination $stage
                $ss=Get-DirectoryGitSnapshot $stage
                if([string]$ss.fingerprint -cne [string]$entry.fingerprint){throw "Persistence restore staging verification failed: $key"}
                $old=$null
                if(Test-PathSafe $path 'Container'){$old=Join-Path $parent ('.spotifycontrol-persistence-old-'+$key+'-'+[guid]::NewGuid().ToString('N'));Move-Item -LiteralPath $path -Destination $old}
                try{Move-Item -LiteralPath $stage -Destination $path}
                catch{if($old -and (Test-PathSafe $old 'Container') -and -not(Test-PathSafe $path 'Container')){Move-Item -LiteralPath $old -Destination $path -ErrorAction SilentlyContinue};throw}
                $final=Get-DirectoryGitSnapshot $path
                if([string]$final.fingerprint -cne [string]$entry.fingerprint){throw "Persistence restore final verification failed: $key"}
                if($old -and (Test-PathSafe $old 'Container')){Remove-Item -LiteralPath $old -Recurse -Force}
            }finally{if(Test-PathSafe $stage 'Container'){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
        }else{
            $stage=Join-Path $parent ('.spotifycontrol-persistence-restore-'+$key+'-'+[guid]::NewGuid().ToString('N')+'.tmp')
            $old=$null
            try{
                Copy-Item -LiteralPath $backup -Destination $stage -Force
                $stageSha=(Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash.ToLowerInvariant();$stageItem=Get-Item -LiteralPath $stage -Force
                if([string]$stageSha -cne [string]$entry.sha256 -or [int64]$stageItem.Length -ne [int64]$entry.size){throw "Persistence file restore staging verification failed: $key"}
                if(Test-PathSafe $path 'Leaf'){$old=Join-Path $parent ('.spotifycontrol-persistence-old-'+$key+'-'+[guid]::NewGuid().ToString('N')+'.tmp');Move-Item -LiteralPath $path -Destination $old}
                try{Move-Item -LiteralPath $stage -Destination $path}
                catch{if($old -and (Test-PathSafe $old 'Leaf') -and -not(Test-PathSafe $path 'Leaf')){Move-Item -LiteralPath $old -Destination $path -ErrorAction SilentlyContinue};throw}
                $finalSha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();$finalItem=Get-Item -LiteralPath $path -Force
                if([string]$finalSha -cne [string]$entry.sha256 -or [int64]$finalItem.Length -ne [int64]$entry.size){throw "Persistence file restore final verification failed: $key"}
                if($old -and(Test-PathSafe $old 'Leaf')){Remove-Item -LiteralPath $old -Force}
            }finally{if(Test-PathSafe $stage 'Leaf'){Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue}}
        }
    }
    $check=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $BackupPath -ManifestSha256 $ManifestSha256
    if(-not [bool]$check.Valid){throw ('Persistence transaction restore did not return to the exact snapshot: '+(@($check.DriftKeys)-join ','))}
    return $check
}

function Get-SpotifyPersistenceGuardFromTransaction {
    param([Parameter(Mandatory=$true)]$Tx)
    $names=@('persistence_guard_schema','persistence_backup_path','persistence_manifest_sha256','persistence_before_fingerprint')
    $present=@($names|Where-Object{$Tx.PSObject.Properties.Name -contains $_ -and $null -ne $Tx.$_ -and -not [string]::IsNullOrWhiteSpace([string]$Tx.$_)})
    if($present.Count -eq 0){return $null}
    if($present.Count -ne $names.Count){throw 'Addon transaction has partial persistence-guard metadata.'}
    if([int]$Tx.persistence_guard_schema -ne 1){throw "Unsupported persistence guard schema: $($Tx.persistence_guard_schema)"}
    if([string]$Tx.persistence_manifest_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Tx.persistence_before_fingerprint -notmatch '^[0-9a-f]{64}$'){throw 'Addon transaction persistence guard hash metadata is invalid.'}
    $manifest=Assert-SpotifyPersistenceGuardBackup -BackupPath ([string]$Tx.persistence_backup_path) -ManifestSha256 ([string]$Tx.persistence_manifest_sha256)
    if([string]$manifest.before_fingerprint -cne [string]$Tx.persistence_before_fingerprint){throw 'Addon transaction persistence guard fingerprint does not match its manifest.'}
    return [pscustomobject]@{BackupPath=[string]$Tx.persistence_backup_path;ManifestSha256=[string]$Tx.persistence_manifest_sha256;BeforeFingerprint=[string]$Tx.persistence_before_fingerprint}
}

function Invoke-SpotifyPersistenceTransactionSelfTest {
    $root=$null
    try{
        $root=Join-Path $env:TEMP ('SpotifyControl-PersistenceGuard-'+[guid]::NewGuid().ToString('N'))
        $spotify=Join-Path $root 'Spotify';$backupBase=Join-Path $root 'backups'
        $browserLocal=Join-Path $spotify 'Browser\Local Storage';$defaultIndexed=Join-Path $spotify 'Default\IndexedDB'
        New-Item -ItemType Directory -Force -Path $browserLocal,$defaultIndexed,$backupBase|Out-Null
        Set-Content -LiteralPath (Join-Path $browserLocal 'leveldb.bin') -Value 'local-storage-before' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $defaultIndexed 'db.bin') -Value 'indexed-before' -Encoding UTF8
        $prefs=Join-Path $spotify 'Browser\Preferences';New-Item -ItemType Directory -Force -Path (Split-Path -Parent $prefs)|Out-Null;Set-Content -LiteralPath $prefs -Value '{"before":true}' -Encoding UTF8
        $guard=New-SpotifyPersistenceTransactionSnapshot -SnapshotId 'fixture' -SpotifyRoot $spotify -BackupBaseRoot $backupBase
        $initial=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $guard.backup_path -ManifestSha256 $guard.manifest_sha256
        if(-not [bool]$initial.Valid){throw 'Persistence self-test rejected the exact initial snapshot.'}
        Set-Content -LiteralPath $prefs -Value '{"after":true}' -Encoding UTF8
        $rootLocal=Join-Path $spotify 'Local Storage';New-Item -ItemType Directory -Force -Path $rootLocal|Out-Null;Set-Content -LiteralPath (Join-Path $rootLocal 'unexpected.bin') -Value 'unexpected' -Encoding UTF8
        $drift=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $guard.backup_path -ManifestSha256 $guard.manifest_sha256
        if([bool]$drift.Valid -or @($drift.DriftKeys).Count -lt 2){throw 'Persistence self-test failed to detect changed and newly-created storage.'}
        [void](Restore-SpotifyPersistenceTransactionSnapshot -BackupPath $guard.backup_path -ManifestSha256 $guard.manifest_sha256)
        $restored=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $guard.backup_path -ManifestSha256 $guard.manifest_sha256
        if(-not [bool]$restored.Valid -or (Test-PathSafe $rootLocal 'Any')){throw 'Persistence self-test exact restore/absent-state restore failed.'}
        if((Get-Content -LiteralPath $prefs -Raw).Trim() -cne '{"before":true}'){throw 'Persistence self-test Preferences bytes were not restored.'}
        Set-Content -LiteralPath $prefs -Value '{"mutated-again":true}' -Encoding UTF8
        $liveBeforeFailure=(Get-FileHash -LiteralPath $prefs -Algorithm SHA256).Hash.ToLowerInvariant()
        $backupPrefs=Join-Path ([string]$guard.backup_path) 'browser-preferences.file'
        Set-Content -LiteralPath $backupPrefs -Value 'corrupt-backup' -Encoding UTF8
        $failed=$false;try{[void](Restore-SpotifyPersistenceTransactionSnapshot -BackupPath $guard.backup_path -ManifestSha256 $guard.manifest_sha256)}catch{$failed=$true}
        if(-not $failed){throw 'Persistence self-test corrupted backup was incorrectly accepted.'}
        $liveAfterFailure=(Get-FileHash -LiteralPath $prefs -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]$liveBeforeFailure -cne [string]$liveAfterFailure){throw 'Persistence self-test corrupted-backup rejection mutated live persistence.'}
        Write-AddonLog 'Persistence transaction self-test passed: exact snapshot, drift/new-path detection, exact restore, absent-state restore, and corrupt-backup fail-closed behavior.'
    }finally{if($root -and(Test-PathSafe $root 'Container')){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
}
'''


def patch_addon(base: bytes) -> bytes:
    bom = b"\xef\xbb\xbf" if base.startswith(b"\xef\xbb\xbf") else b""
    text = base[len(bom):].decode("utf-8")
    if "\r\n" in text:
        raise RuntimeError("unexpected CRLF in r17 addon base")

    if text.count('$Version = "0.6.5-r17"') != 1:
        raise RuntimeError("r17 version anchor drifted")
    text = text.replace('$Version = "0.6.5-r17"', '$Version = "0.6.5-r18-candidate"', 1)

    insert = text.find("\nfunction Backup-SpotifyWebData {")
    if insert < 0:
        raise RuntimeError("persistence helper insertion anchor drifted")
    text = text[:insert] + "\n" + HELPERS + text[insert:]

    normalize = function_block(text, "Normalize-PithayaTransaction")
    old_optional = 'foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256")) {'
    new_optional = 'foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256","persistence_guard_schema","persistence_backup_path","persistence_manifest_sha256","persistence_before_fingerprint")) {'
    if normalize.count(old_optional) != 1:
        raise RuntimeError("Normalize-PithayaTransaction optional-property anchor drifted")
    normalize = normalize.replace(old_optional, new_optional, 1)
    text = replace_function(text, "Normalize-PithayaTransaction", normalize)

    update = function_block(text, "Update-AutoApps")
    txid_anchor = '$txid=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)\n        $changes=New-Object System.Collections.Generic.List[object]'
    txid_repl = '$txid=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)\n        # Fresh, transaction-bound persistence snapshot. Unlike the weekly backup this can never be skipped as not-due.\n        $persistenceGuard=New-SpotifyPersistenceTransactionSnapshot -SnapshotId $txid\n        $changes=New-Object System.Collections.Generic.List[object]'
    if update.count(txid_anchor) != 1:
        raise RuntimeError("Update-AutoApps txid anchor drifted")
    update = update.replace(txid_anchor, txid_repl, 1)
    tx_anchor = '$tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'
    tx_repl = '$tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; persistence_guard_schema=1; persistence_backup_path=[string]$persistenceGuard.backup_path; persistence_manifest_sha256=[string]$persistenceGuard.manifest_sha256; persistence_before_fingerprint=[string]$persistenceGuard.before_fingerprint; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }'
    if update.count(tx_anchor) != 1:
        raise RuntimeError("Update-AutoApps transaction anchor drifted")
    update = update.replace(tx_anchor, tx_repl, 1)
    text = replace_function(text, "Update-AutoApps", update)

    commit = function_block(text, "Commit-LastTransaction")
    commit_anchor = '    $state=Load-AddonState\n'
    commit_guard = '''    $persistenceGuard=Get-SpotifyPersistenceGuardFromTransaction -Tx $tx
    if($persistenceGuard){
        $persistenceCheck=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $persistenceGuard.BackupPath -ManifestSha256 $persistenceGuard.ManifestSha256
        if(-not [bool]$persistenceCheck.Valid){
            $drift=@($persistenceCheck.DriftKeys)-join ','
            Write-AddonLog ("Persistence changed during the closed addon/apply transaction; rolling back before Spotify can restart. drift="+$drift) 'ERROR'
            try{Rollback-LastTransaction}catch{throw ("Persistence drift detected, but automatic transaction rollback failed: "+$_.Exception.Message)}
            throw ("Persistence drift detected during addon update/apply; exact pre-update persistence and app trees were restored. drift="+$drift)
        }
    }
    $state=Load-AddonState
'''
    if commit.count(commit_anchor) != 1:
        raise RuntimeError("Commit-LastTransaction state anchor drifted")
    commit = commit.replace(commit_anchor, commit_guard, 1)
    text = replace_function(text, "Commit-LastTransaction", commit)

    rollback = function_block(text, "Rollback-LastTransaction")
    rollback_anchor = '    $changes=@($tx.changes)\n'
    rollback_guard = '''    $persistenceGuard=Get-SpotifyPersistenceGuardFromTransaction -Tx $tx
    if($persistenceGuard){
        $persistenceCheck=Test-SpotifyPersistenceTransactionSnapshot -BackupPath $persistenceGuard.BackupPath -ManifestSha256 $persistenceGuard.ManifestSha256
        if(-not [bool]$persistenceCheck.Valid){
            [void](Restore-SpotifyPersistenceTransactionSnapshot -BackupPath $persistenceGuard.BackupPath -ManifestSha256 $persistenceGuard.ManifestSha256)
            Write-AddonLog 'Restored exact pre-update Spotify WebView persistence before addon tree rollback.' 'WARN'
        }
    }
    $changes=@($tx.changes)
'''
    if rollback.count(rollback_anchor) != 1:
        raise RuntimeError("Rollback-LastTransaction changes anchor drifted")
    rollback = rollback.replace(rollback_anchor, rollback_guard, 1)
    text = replace_function(text, "Rollback-LastTransaction", rollback)

    selftest = function_block(text, "Invoke-TransactionSelfTest")
    log_anchor = '        Write-AddonLog "Pithaya transaction self-test passed: exact-tree corruption/missing/extra rejection, swap, exact rollback, corrupted-backup fail-closed behavior, legacy-ledger lifecycle migration, and stale-flag before/after reconciliation fixtures."'
    if selftest.count(log_anchor) != 1:
        raise RuntimeError("Invoke-TransactionSelfTest final-log anchor drifted")
    selftest = selftest.replace(log_anchor, '        Invoke-SpotifyPersistenceTransactionSelfTest\n' + log_anchor, 1)
    text = replace_function(text, "Invoke-TransactionSelfTest", selftest)

    return bom + text.encode("utf-8")


def validate_candidate(base_addon: bytes, candidate: bytes) -> dict:
    base = base_addon.decode("utf-8-sig").replace("\r\n", "\n")
    cand = candidate.decode("utf-8-sig").replace("\r\n", "\n")

    def fmap(text: str) -> dict[str, str]:
        matches = list(re.finditer(r"(?m)^function ([A-Za-z0-9_-]+) \{", text))
        out: dict[str, str] = {}
        for i, m in enumerate(matches):
            end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
            out[m.group(1)] = text[m.start():end].rstrip()
        return out

    bf = fmap(base)
    cf = fmap(cand)
    allowed_changed = {"Normalize-PithayaTransaction", "Update-AutoApps", "Commit-LastTransaction", "Rollback-LastTransaction", "Invoke-TransactionSelfTest"}
    new_helpers = {
        "Get-SpotifyPersistenceGuardTargets",
        "Get-SpotifyPersistenceGuardTargetSnapshot",
        "Get-SpotifyPersistenceGuardFingerprint",
        "Assert-SpotifyPersistenceGuardBackup",
        "New-SpotifyPersistenceTransactionSnapshot",
        "Test-SpotifyPersistenceTransactionSnapshot",
        "Restore-SpotifyPersistenceTransactionSnapshot",
        "Get-SpotifyPersistenceGuardFromTransaction",
        "Invoke-SpotifyPersistenceTransactionSelfTest",
    }
    for name, block in bf.items():
        if name in allowed_changed:
            continue
        if cf.get(name) != block:
            raise RuntimeError(f"unexpected existing function changed: {name}")
    if not new_helpers.issubset(cf):
        raise RuntimeError(f"missing persistence helpers: {sorted(new_helpers - set(cf))}")

    registry = cf["Get-AddonPolicyRegistry"]
    auto = re.findall(r"name='([^']+)'.*?mutation_mode='auto'", registry, re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED_NAMES):
        raise RuntimeError(f"auto authority drifted: {auto}")
    for marker in (
        "name='tagify'", "mutation_mode='deny'", "protect-ratings-tags-notes",
        "name='splitify'", "preserve-installed-content",
        "name='star-ratings'", "playlist-backed-ratings-preserve",
        "name='sc-cover-ambience.js'", "never-disable-or-optimize",
    ):
        if marker.lower() not in registry.lower():
            raise RuntimeError(f"protected registry marker missing: {marker}")

    if "Assert-AddonSourceAdapterTransactionAuthorization" in cf["Rollback-LastTransaction"]:
        raise RuntimeError("RollbackLast became source-adapter-dependent")
    update = cf["Update-AutoApps"]
    if "New-SpotifyPersistenceTransactionSnapshot -SnapshotId $txid" not in update:
        raise RuntimeError("fresh transaction-bound persistence snapshot is not wired before mutation")
    if update.find("New-SpotifyPersistenceTransactionSnapshot -SnapshotId $txid") > update.find("Invoke-AtomicDirectorySwap"):
        raise RuntimeError("persistence snapshot occurs after first live app swap")
    commit = cf["Commit-LastTransaction"]
    if "Test-SpotifyPersistenceTransactionSnapshot" not in commit or "Rollback-LastTransaction" not in commit:
        raise RuntimeError("commit does not fail closed on persistence drift")
    rollback = cf["Rollback-LastTransaction"]
    if "Restore-SpotifyPersistenceTransactionSnapshot" not in rollback:
        raise RuntimeError("rollback does not restore guarded persistence")
    normalize = cf["Normalize-PithayaTransaction"]
    for field in ("persistence_guard_schema", "persistence_backup_path", "persistence_manifest_sha256", "persistence_before_fingerprint"):
        if field not in normalize:
            raise RuntimeError(f"legacy-compatible transaction normalization missing {field}")
    st = cf["Invoke-SpotifyPersistenceTransactionSelfTest"]
    for marker in ("unexpected.bin", "corrupt-backup", "mutated-again", "Restore-SpotifyPersistenceTransactionSnapshot"):
        if marker not in st:
            raise RuntimeError(f"persistence self-test fixture missing: {marker}")

    return {
        "changed_existing_functions": sorted(allowed_changed),
        "new_helpers": sorted(new_helpers),
        "automatic_mutation_authority": auto,
        "protected_authority_unchanged": True,
        "rollback_last_source_adapter_independent": True,
        "fresh_snapshot_before_live_swap": True,
        "commit_persistence_fail_closed": True,
        "rollback_persistence_restore": True,
    }


def build() -> None:
    main, base_addon = build_base()
    addon = patch_addon(base_addon)
    checks = validate_candidate(base_addon, addon)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "spotify-control.ps1").write_bytes(main)
    (OUT / "addon-manager.ps1").write_bytes(addon)
    report = {
        "schema": 1,
        "base_commit": "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2",
        "base_main": {"size": len(main), "sha256": sha(main)},
        "base_addon": {"size": len(base_addon), "sha256": sha(base_addon)},
        "candidate_addon": {"size": len(addon), "sha256": sha(addon)},
        "candidate_version": "0.6.5-r18-candidate",
        "production_change": False,
        "checks": checks,
        "guard_scope": [
            "Browser/IndexedDB", "Browser/Local Storage", "Browser/Session Storage", "Browser/WebStorage", "Browser/Local State", "Browser/Preferences",
            "Default/IndexedDB", "Default/Local Storage", "Default/Session Storage", "Default/WebStorage", "Default/Local State", "Default/Preferences",
            "IndexedDB", "Local Storage",
        ],
        "excluded_from_guard": ["config-xpui.ini"],
        "reason": "config-xpui may be legitimately normalized by Spicetify apply and is covered by existing Spicetify/update transaction paths; WebView persistence is guarded byte-exactly while Spotify remains closed.",
    }
    REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print("PERSISTENCE_TRANSACTION_GUARD_CANDIDATE_BUILD_PASS", len(addon), sha(addon))
    print("AUTO_AUTHORITY=" + "|".join(checks["automatic_mutation_authority"]))
    print("PRODUCTION_CHANGE=false")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    if not args.build:
        parser.error("use --build")
    build()


if __name__ == "__main__":
    build() if "--build" in sys.argv else main()
