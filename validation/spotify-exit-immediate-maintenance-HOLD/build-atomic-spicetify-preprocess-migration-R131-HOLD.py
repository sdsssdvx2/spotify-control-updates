"""R131 HOLD: experimental full upgrade with external preimage and crash-recovery.

Starts from exact R130 source (source-pinned). The official Spicetify CLI
requires its preprocessed backup to match the running CLI version. Unlike R112,
which used 'apply' after swapping the exe, R131 uses 'restore backup apply'
ONLY if BOTH external surfaces were byte-pinned and stored durably first.

This is for hosted Windows, not operating deployment.
"""
from __future__ import annotations
import hashlib, os, re
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"out/private-preprocessed-migration-gate-R130/spotify-control.ps1"
PARENT="db1784e96f5bc7a7a089d21a3f258cbedb7806e263f138fc360765fcaf5b6214"
OUT=HERE/"out/atomic-spicetify-preprocess-migration-R131/spotify-control.ps1"

HELPERS=r"""
function New-SpicetifyMigrationPreimage {
  param([string]$TransactionBackupDir,[string]$InstalledCliVersion)
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify\Apps'
  $cfg=Join-Path $spice 'config-xpui.ini'
  $actual=Get-ConfigPath
  if(-not $actual -or
    -not [string]::Equals([IO.Path]::GetFullPath($actual),
       [IO.Path]::GetFullPath($cfg),
       [StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_NONSTANDARD_SPICETIFY_CONFIG_HOLD'
  }
  $backupWith=Get-IniSectionValue -Path $cfg -Section 'Backup' -Key 'with'
  if([string]$backupWith -cne $InstalledCliVersion){
    throw 'R131_OLD_PREPROCESSOR_NOT_EXACT_CLI_HOLD'
  }
  if(Test-SpotifyRunning){throw 'R131_SPOTIFY_RUNNING_PREIMAGE_HOLD'}
  $sourceSpice=Get-SpicetifyRootManifest -Path $spice
  $sourceApps=Get-SpicetifyRootManifest -Path $apps
  $snapshotRoot=Join-Path $TransactionBackupDir 'preprocess-external-before'
  if(Test-Path -LiteralPath $snapshotRoot){
    throw 'R131_EXTERNAL_PREIMAGE_ALREADY_EXISTS'
  }
  # Capture both sources before any Spotify Apps or roaming Spicetify writes.
  $preSpice=Join-Path $snapshotRoot 'spicetify-roaming'
  $preApps=Join-Path $snapshotRoot 'spotify-apps'
  [void](Copy-SpicetifyRootExact -Source $spice -Destination $preSpice -ExpectedTreeSha256 $sourceSpice.TreeSha256)
  [void](Copy-SpicetifyRootExact -Source $apps -Destination $preApps -ExpectedTreeSha256 $sourceApps.TreeSha256)
  if((Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne $sourceSpice.TreeSha256 -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne $sourceApps.TreeSha256){
    throw 'R131_EXTERNAL_SOURCES_CHANGED_DURING_SNAPSHOT'
  }
  $semantic=Get-SpicetifyConfigSemanticHash
  return [pscustomobject]@{
    BackupRoot=$snapshotRoot;Roaming=$spice;Apps=$apps
    RoamingBackup=$preSpice;AppsBackup=$preApps
    RoamingTreeSha256=$sourceSpice.TreeSha256
    AppsTreeSha256=$sourceApps.TreeSha256
    SemanticHash=$semantic
  }
}

function Restore-SpicetifyMigrationSurface {
  param([string]$Path,[string]$Backup,[string]$BeforeSha256,
        [string]$TransactionId,[string]$Suffix)
  $base=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Spotify'))
  $allowedApps=[IO.Path]::GetFullPath((Join-Path $base 'Apps'))
  $allowedRoaming=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'spicetify'))
  $dest=[IO.Path]::GetFullPath($Path)
  if(-not ([string]::Equals($dest,$allowedApps,[StringComparison]::OrdinalIgnoreCase) -or
     [string]::Equals($dest,$allowedRoaming,[StringComparison]::OrdinalIgnoreCase))){
    throw 'R131_EXTERNAL_RESTORE_PATH_NOT_ALLOWED'
  }
  if($TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
     $Suffix -cnotin @('apps','roaming')){
    throw 'R131_RESTORE_TRANSACTION_ID_INVALID'
  }
  $backupManifest=Get-SpicetifyRootManifest -Path $Backup
  if($backupManifest.TreeSha256 -cne $BeforeSha256){
    throw 'R131_EXTERNAL_BACKUP_SHA_MISMATCH'
  }
  $live=$null
  if(Test-Path -LiteralPath $dest -PathType Container){
    $live=Get-SpicetifyRootManifest -Path $dest
    if($live.TreeSha256 -ceq $BeforeSha256){
      return [pscustomobject]@{Restored=$true;AlreadyExact=$true}
    }
  }
  if(Test-SpotifyRunning){throw 'R131_SPOTIFY_ACTIVE_DURING_RESTORE'}
  if(@(Get-Process -Name 'spicetify' -ErrorAction SilentlyContinue).Count -gt 0){
    throw 'R131_SPICETIFY_PROCESS_ACTIVE_DURING_RESTORE'
  }
  $parent=Split-Path -Parent $dest
  $stage=Join-Path $parent ('.spotifycontrol-r131-staged-'+$Suffix+'-'+$TransactionId)
  $held=Join-Path $parent ('.spotifycontrol-r131-quarantine-'+$Suffix+'-'+$TransactionId)
  $stagePresent=Test-Path -LiteralPath $stage
  $heldPresent=Test-Path -LiteralPath $held
  # Resume ONLY the interrupted destination->quarantine rename, when the
  # original destination is absent and the exact transaction quarantine exists.
  # Never overwrite an occupied destination, even during restart recovery.
  if($heldPresent -and -not (Test-Path -LiteralPath $dest)){
    $heldItem=Get-Item -LiteralPath $held -Force -ErrorAction Stop
    if(-not $heldItem.PSIsContainer -or
       ($heldItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'R131_INTERRUPTED_QUARANTINE_UNSAFE'
    }
    if($stagePresent){
      $stageItem=Get-Item -LiteralPath $stage -Force -ErrorAction Stop
      if(-not $stageItem.PSIsContainer -or
         ($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         (Get-SpicetifyRootManifest -Path $stage).TreeSha256 -cne $BeforeSha256){
        throw 'R131_INTERRUPTED_STAGE_INVALID'
      }
    }else{
      [void](Copy-SpicetifyRootExact -Source $Backup -Destination $stage -ExpectedTreeSha256 $BeforeSha256)
    }
    Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
    if((Get-SpicetifyRootManifest -Path $dest).TreeSha256 -cne $BeforeSha256){
      throw 'R131_INTERRUPTED_RESUME_SHA_MISMATCH'
    }
    # Retain the displaced modified tree for operator review.
    return [pscustomobject]@{Restored=$true;AlreadyExact=$false;Resumed=$true}
  }
  if($stagePresent -or $heldPresent){
    throw 'R131_RESTORE_RESERVED_PATH_ALREADY_EXISTS'
  }
  [void](Copy-SpicetifyRootExact -Source $Backup -Destination $stage -ExpectedTreeSha256 $BeforeSha256)
  if($live){Move-Item -LiteralPath $dest -Destination $held -ErrorAction Stop}
  try{
    Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
  }catch{
    if($live -and -not (Test-Path -LiteralPath $dest) -and
       (Test-Path -LiteralPath $held)){
      Move-Item -LiteralPath $held -Destination $dest -ErrorAction Stop
    }
    throw
  }
  if((Get-SpicetifyRootManifest -Path $dest).TreeSha256 -cne $BeforeSha256){
    throw 'R131_RESTORED_EXTERNAL_TREE_SHA_MISMATCH'
  }
  # The quarantine remains for operator review. Never delete unknown changed files.
  return [pscustomobject]@{Restored=$true;AlreadyExact=$false}
}

function Restore-SpicetifyMigrationPreimage {
  param($Txn)
  if(-not [bool]$Txn.migration_required){
    return [pscustomobject]@{Restored=$true;Status='NOT_REQUIRED'}
  }
  if(-not [bool]$Txn.migration_snapshot_ready){
    throw 'R131_EXTERNAL_PREIMAGE_NOT_CERTIFIED'
  }
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify\Apps'
  if(-not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_spicetify_root),
       [IO.Path]::GetFullPath($spice),[StringComparison]::OrdinalIgnoreCase) -or
     -not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_apps_root),
       [IO.Path]::GetFullPath($apps),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_EXTERNAL_PREIMAGE_OWNER_PATH_MISMATCH'
  }
  $back=[string]$Txn.backup_root
  $backupBase=Split-Path -Parent $back
  $expectedSnapshot=Join-Path $backupBase 'preprocess-external-before'
  if(-not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_snapshot_root),
      [IO.Path]::GetFullPath($expectedSnapshot),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_EXTERNAL_PREIMAGE_BACKUP_PATH_MISMATCH'
  }
  [void](Restore-SpicetifyMigrationSurface -Path $apps -Backup (Join-Path $expectedSnapshot 'spotify-apps') -BeforeSha256 ([string]$Txn.migration_apps_before_sha256) -TransactionId ([string]$Txn.id) -Suffix 'apps')
  [void](Restore-SpicetifyMigrationSurface -Path $spice -Backup (Join-Path $expectedSnapshot 'spicetify-roaming') -BeforeSha256 ([string]$Txn.migration_spicetify_before_sha256) -TransactionId ([string]$Txn.id) -Suffix 'roaming')
  if((Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne [string]$Txn.migration_apps_before_sha256 -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne [string]$Txn.migration_spicetify_before_sha256){
    throw 'R131_EXTERNAL_PREIMAGE_FINAL_SHA_MISMATCH'
  }
  return [pscustomobject]@{Restored=$true;Status='EXACT_EXTERNAL_PREIMAGE_RESTORED'}
}

function Write-SpicetifyJournalJsonAtomic {
  param([string]$Path,[string]$Json)
  if([string]::IsNullOrWhiteSpace($Path) -or
     [string]::IsNullOrWhiteSpace($Json)){
    throw 'R131_JOURNAL_EMPTY_TARGET_OR_CONTENT'
  }
  $full=[IO.Path]::GetFullPath($Path)
  $dir=Split-Path -Parent $full
  $parent=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
  if(-not $parent.PSIsContainer -or
     ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R131_JOURNAL_DIRECTORY_UNSAFE'
  }
  $present=Test-Path -LiteralPath $full
  $previous=$full+'.previous'
  foreach($check in @($full,$previous)){
    if(Test-Path -LiteralPath $check){
      $info=Get-Item -LiteralPath $check -Force -ErrorAction Stop
      if($info.PSIsContainer -or
         ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'R131_JOURNAL_TARGET_UNSAFE'
      }
    }
  }
  $stage=Join-Path $dir ('.spotifycontrol-journal-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Json)
  $hash=[Security.Cryptography.SHA256]::Create()
  try{$expected=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
  finally{$hash.Dispose()}
  $stream=$null
  try{
    $stream=[IO.FileStream]::new($stage,[IO.FileMode]::CreateNew,
         [IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush($true)
    $stream.Dispose();$stream=$null
    if((Get-ExactFileSha256 -Path $stage) -cne $expected){
      throw 'R131_JOURNAL_STAGE_READBACK_MISMATCH'
    }
    # The authoritative primary journal is replaced atomically before the
    # informational report. A crash can leave the report one revision behind,
    # but never silently truncate a previously committed primary JSON file.
    if($present){
      if(-not (Test-Path -LiteralPath $full -PathType Leaf)){
        throw 'R131_JOURNAL_TARGET_CHANGED_BEFORE_REPLACE'
      }
      [IO.File]::Replace($stage,$full,$previous,$true)
    }else{
      [IO.File]::Move($stage,$full)
    }
    if((Get-ExactFileSha256 -Path $full) -cne $expected){
      throw 'R131_JOURNAL_PUBLISHED_READBACK_MISMATCH'
    }
  }finally{
    if($null -ne $stream){$stream.Dispose()}
    if(Test-Path -LiteralPath $stage){
      Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
    }
  }
}

function Confirm-SpicetifyMigrationApplied {
  param($Txn)
  if(-not [bool]$Txn.migration_required){return $Txn}
  if(-not [bool]$Txn.migration_snapshot_ready -or
     -not [bool]$Txn.migration_started){
    throw 'R131_MIGRATION_NOT_PREPARED_OR_NOT_STARTED'
  }
  $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
  if([string](Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with') -cne
     [string]$Txn.after_version){
    throw 'R131_NEW_CLI_BACKUP_WITH_NOT_MIGRATED'
  }
  if((Get-SpicetifyConfigSemanticHash) -cne [string]$Txn.migration_semantic_before_sha256){
    throw 'R131_USER_CONFIG_SEMANTICS_CHANGED'
  }
  $apps=Get-SpicetifyRootManifest -Path ([string]$Txn.migration_apps_root)
  $spice=Get-SpicetifyRootManifest -Path ([string]$Txn.migration_spicetify_root)
  $Txn.migration_apps_after_sha256=$apps.TreeSha256
  $Txn.migration_spicetify_after_sha256=$spice.TreeSha256
  $Txn.migration_finished=$true
  return $Txn
}
"""

def fail(ok,label):
    if not ok:raise RuntimeError("R131_"+label)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def splice_fn(source,name,changes):
    marker="\nfunction "+name+" {"
    fail(source.count(marker)==1,"FUNCTION_NOT_UNIQUE_"+name)
    start=source.index(marker)+1
    end=source.find("\nfunction ",start+len(marker))
    if end<0:end=len(source)
    orig=source[start:end]
    cur=orig
    for old,new,label in changes:
        fail(cur.count(old)==1,"ANCHOR_"+name+"_"+label)
        cur=cur.replace(old,new,1)
    fail(cur!=orig,"UNCHANGED_"+name)
    return source[:start]+cur+source[end:],(orig,cur)

def main():
    fail(os.getenv("GITHUB_ACTIONS")=="true" and
         os.getenv("RUNNER_OS")=="Windows" and
         os.getenv("RUNNER_ENVIRONMENT")=="github-hosted",
         "HOSTED_WINDOWS_ONLY")
    raw=SOURCE.read_bytes()
    fail(sha(raw)==PARENT,"PARENT_PIN_CHANGED")
    newline="\r\n" if b"\r\n" in raw else "\n"
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    original=raw.decode("utf-8-sig").replace("\r\n","\n")
    text=original
    replacements=[]
    text,replay=splice_fn(text,"Start-SpicetifyCliTransaction",[
      ("""    if ($upgradeClass -cne 'BACKUP_PREPROCESSOR_CURRENT') {
        throw ('R130_PREPROCESSED_BACKUP_MIGRATION_HOLD:'+$upgradeClass)
    }""",
       """    if ($upgradeClass -cnotin @('BACKUP_PREPROCESSOR_CURRENT',
        'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING')) {
        throw ('R131_PREPROCESSOR_PREIMAGE_INVALID:'+$upgradeClass)
    }
    $migratePreprocessed=($upgradeClass -ceq 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING')""","admission"),
      ("    $txn = [pscustomobject]@{",
       """    $external=$null
    if($migratePreprocessed){
      $external=New-SpicetifyMigrationPreimage -TransactionBackupDir $txnBackupDir -InstalledCliVersion $currentVersion
    }
    $txn = [pscustomobject]@{""","external_snapshot_before_journal_and_swap"),
      ("rollback_reapply_succeeded=$null; rollback_reapply_at=$null; committed_at=$null; rolled_back_at=$null; error=$null",
       """rollback_reapply_succeeded=$null; rollback_reapply_at=$null; committed_at=$null; rolled_back_at=$null; error=$null
            migration_required=$migratePreprocessed; migration_snapshot_ready=($null -ne $external)
            migration_started=$false; migration_finished=$false; migration_external_rollback_restored=$false
            migration_snapshot_root=$(if($external){$external.BackupRoot}else{$null})
            migration_spicetify_root=$(if($external){$external.Roaming}else{$null})
            migration_apps_root=$(if($external){$external.Apps}else{$null})
            migration_spicetify_before_sha256=$(if($external){$external.RoamingTreeSha256}else{$null})
            migration_apps_before_sha256=$(if($external){$external.AppsTreeSha256}else{$null})
            migration_semantic_before_sha256=$(if($external){$external.SemanticHash}else{$null})
            migration_spicetify_after_sha256=$null; migration_apps_after_sha256=$null""","journal_preimage_fields")
    ]);replacements.append(("Start-SpicetifyCliTransaction",)+replay)
    text,replay=splice_fn(text,"Invoke-SpicetifyTransactionalMaintenance",[
      ("""$txnForApply.apply_attempted = $true
    Save-SpicetifyTransaction -Transaction $txnForApply
    try {
        [void](Invoke-Spice -Arguments @('apply','--no-restart'))
        $txnForApply = Get-SpicetifyTransaction
        $txnForApply.apply_succeeded = $true""",
       """$txnForApply.apply_attempted = $true
    if([bool]$txnForApply.migration_required){$txnForApply.migration_started=$true}
    Save-SpicetifyTransaction -Transaction $txnForApply
    try {
        if([bool]$txnForApply.migration_required){
            [void](Invoke-Spice -Arguments @('restore','backup','apply','--no-restart'))
            $txnForApply=Confirm-SpicetifyMigrationApplied (Get-SpicetifyTransaction)
            Save-SpicetifyTransaction -Transaction $txnForApply
        }else{
            [void](Invoke-Spice -Arguments @('apply','--no-restart'))
            $txnForApply=Get-SpicetifyTransaction
        }
        $txnForApply.apply_succeeded = $true""","official_full_preprocess")
    ]);replacements.append(("Invoke-SpicetifyTransactionalMaintenance",)+replay)
    text,replay=splice_fn(text,"Rollback-SpicetifyCliTransaction",[
      ("""if (Test-Path -LiteralPath $quarantine) { throw "Rollback quarantine path unexpectedly exists: $quarantine" }""",
       """if(Test-Path -LiteralPath $quarantine){
        # Only a displaced, byte-exact after-root from this transaction is
        # allowed to survive across an interrupted root rollback.
        $quarantineManifest=Get-SpicetifyRootManifest -Path $quarantine
        if($quarantineManifest.TreeSha256 -cne [string]$txn.after_tree_sha256 -or
           ($liveManifest -and $liveManifest.TreeSha256 -cne [string]$txn.before_tree_sha256)){
          throw 'R131_INTERRUPTED_CLI_QUARANTINE_CONFLICT_HOLD'
        }
    }""","resumable_root_quarantine"),
      ("""[void](Copy-SpicetifyRootExact -Source $backupRoot -Destination $restoreRoot -ExpectedTreeSha256 ([string]$txn.before_tree_sha256))""",
       """if(Test-Path -LiteralPath $restoreRoot){
        $restoreManifest=Get-SpicetifyRootManifest -Path $restoreRoot
        if($restoreManifest.TreeSha256 -cne [string]$txn.before_tree_sha256){
          throw 'R131_INTERRUPTED_CLI_RESTORE_STAGE_INVALID_HOLD'
        }
    }else{
        [void](Copy-SpicetifyRootExact -Source $backupRoot -Destination $restoreRoot -ExpectedTreeSha256 ([string]$txn.before_tree_sha256))
    }""","resumable_root_stage"),
      ("""if ([bool]$txn.apply_attempted) {
        $restoreApply=Invoke-NativeCapture -FilePath $targetExe -Arguments @('apply','--no-restart')""",
       """if([bool]$txn.migration_required){
        $restore=Restore-SpicetifyMigrationPreimage -Txn $txn
        if(-not $restore.Restored){throw 'R131_EXTERNAL_RESTORE_NOT_VERIFIED'}
        $txn.migration_external_rollback_restored=$true
        $txn.rollback_reapply_succeeded=$null
        $txn.rollback_reapply_at=$null
        Save-SpicetifyTransaction -Transaction $txn
    } elseif ([bool]$txn.apply_attempted) {
        $restoreApply=Invoke-NativeCapture -FilePath $targetExe -Arguments @('apply','--no-restart')""","restore_bytes_instead_of_reapply")
    ]);replacements.append(("Rollback-SpicetifyCliTransaction",)+replay)
    text,replay=splice_fn(text,"Save-SpicetifyTransaction",[
      ("""$Transaction | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpicetifyTransactionPath -Encoding UTF8
    $Transaction | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpicetifyTransactionReport -Encoding UTF8""",
       """$json=$Transaction | ConvertTo-Json -Depth 8
    Write-SpicetifyJournalJsonAtomic -Path $SpicetifyTransactionPath -Json $json
    Write-SpicetifyJournalJsonAtomic -Path $SpicetifyTransactionReport -Json $json""",
       "atomic_primary_then_report")
    ]);replacements.append(("Save-SpicetifyTransaction",)+replay)
    text,replay=splice_fn(text,"Commit-SpicetifyCliTransaction",[
      ("""foreach($leftover in @([string]$txn.same_dir_old_root,[string]$txn.same_dir_new_root))""",
       """if([bool]$txn.migration_required){
        if(-not [bool]$txn.migration_snapshot_ready -or
           -not [bool]$txn.migration_finished -or
           -not [bool]$txn.apply_succeeded -or
           -not [bool]$txn.post_apply_guard_succeeded){
            throw 'R131_COMMIT_MIGRATION_INCOMPLETE'
        }
        # Pin the original after-image values before mutating PSCustomObject.
        $pinnedApps=[string]$txn.migration_apps_after_sha256
        $pinnedRoaming=[string]$txn.migration_spicetify_after_sha256
        if($pinnedApps -cnotmatch '^[a-f0-9]{64}$' -or
           $pinnedRoaming -cnotmatch '^[a-f0-9]{64}$'){
            throw 'R131_COMMIT_EXTERNAL_AFTER_PINS_MISSING'
        }
        # Probe a detached in-memory copy: a rejected commit must not
        # overwrite pinned expectations even for a later invocation.
        $probe=$txn | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $current=Confirm-SpicetifyMigrationApplied $probe
        if([string]$current.migration_apps_after_sha256 -cne $pinnedApps -or
           [string]$current.migration_spicetify_after_sha256 -cne $pinnedRoaming){
            throw 'R131_COMMIT_EXTERNAL_AFTER_TREE_CHANGED'
        }
    }
    foreach($leftover in @([string]$txn.same_dir_old_root,[string]$txn.same_dir_new_root))""","durable_external_commit_proof")
    ]);replacements.append(("Commit-SpicetifyCliTransaction",)+replay)
    marker="\nfunction Start-SpicetifyCliTransaction {"
    fail(text.count(marker)==1 and text.count("function New-SpicetifyMigrationPreimage")==0,
         "HELPER_INSERTION_NOT_UNIQUE")
    text=text.replace(marker,HELPERS+marker,1)
    fail("restore','backup','apply','--no-restart" in text,"OFFICIAL_MIGRATION_MISSING")
    fail("R131_PREPROCESSOR_PREIMAGE_INVALID" in text,"PREIMAGE_ADMISSION_MISSING")
    # Exact reverse modified function bodies; prevents accidental unrelated edits.
    reverse=text.replace(HELPERS+marker,marker,1)
    for name,old,new in reversed(replacements):
        fail(reverse.count(new)==1,"REVERSE_NEW_BODY_NOT_UNIQUE_"+name)
        reverse=reverse.replace(new,old,1)
    fail(reverse==original,"UNRELATED_SOURCE_CHANGED")
    b=bom+text.replace("\n",newline).encode("utf-8")
    fail(not OUT.exists(),"OUTPUT_ALREADY_EXISTS")
    OUT.parent.mkdir(parents=True,exist_ok=True)
    with OUT.open("xb") as fh:fh.write(b)
    fail(sha(OUT.read_bytes())==sha(b),"OUTPUT_HASH_MISMATCH")
    print("R131_PARENT_R130_SHA=PASS")
    print("R131_OLD_CLI_BACKUP_PREIMAGE_BEFORE_SWAP=PASS")
    print("R131_OFFICIAL_RESTORE_BACKUP_APPLY_PATH=PASS")
    print("R131_PREIMAGE_ROLLBACK_AND_JOURNAL_FIELDS=PASS")
    print("R131_FIVE_FUNCTIONS_AND_FIVE_NEW_HELPERS_CHANGED=PASS")
    print("R131_PUBLIC_MAIN_AND_OWNER_FILES=UNCHANGED")
    print("R131_CANDIDATE_SHA256="+sha(b))

if __name__=="__main__":
    main()
