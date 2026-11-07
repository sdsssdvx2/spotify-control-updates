# V030 — verified actual V029 HMAC source + original rollback bytes ->
# original V010 append-only journal PREPARED CAS. Host-only validation, no
# Spotify installation, native refresh, mutation or cleanup permissions.
function Assert-ApprovedPreparedHostedV030 {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'V030_HOSTED_WINDOWS_FIXTURE_ONLY'
    }
}
function Test-ApprovedPreparedEqualTreeV030 {
    param($A,$B)
    return ([string]$A.tree_sha256 -ceq [string]$B.tree_sha256 -and
       [int]$A.file_count -eq [int]$B.file_count -and
       [int64]$A.total_bytes -eq [int64]$B.total_bytes)
}
function Get-ApprovedPreparedPathsV030 {
    param([Parameter(Mandatory=$true)][string]$WorkRoot,
          [Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$TokenId)
    Assert-ApprovedPreparedHostedV030
    if($TokenId -cnotmatch '^[a-f0-9]{64}$' -or
       $Name -notin @('better-local-files','eternal-jukebox','playlist-maker','ivLyrics')){
        throw 'V030_UNAPPROVED_NAME_OR_TOKEN'
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $work=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $WorkRoot -RequireExisting:$true
    if([IO.Path]::GetFileName($work) -cne 'v030-fixture'){throw 'V030_NOT_OWNED_DISPOSABLE_WORKSPACE'}
    $paths=[ordered]@{runner=$runner;work=$work;
      live=(Join-Path (Join-Path $work 'CustomApps') $Name);
      persist=(Join-Path $work 'ProtectedSpotify');
      transaction=(Join-Path (Join-Path $work 'transactions') $TokenId);
      app_backup=(Join-Path (Join-Path (Join-Path $work 'transactions') $TokenId) 'app-backup');
      persistence_backup=(Join-Path (Join-Path (Join-Path $work 'transactions') $TokenId) 'persistence-backup');
      journal=(Join-Path (Join-Path (Join-Path $work 'transactions') $TokenId) 'journal')}
    foreach($key in @('live','persist','transaction','app_backup','persistence_backup','journal')){
        $paths[$key]=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path ([string]$paths[$key]) -Label ('V030 '+$key)
    }
    if(-not[IO.Directory]::Exists($paths.live) -or -not[IO.Directory]::Exists($paths.persist)){
        throw 'V030_PROTECTED_TEST_INPUTS_NOT_PRESENT'
    }
    return [pscustomobject]$paths
}
function Get-ApprovedPreparedSealedPathV030 {
    param($Paths,[string]$TransactionId)
    if($TransactionId -cnotmatch '^[a-f0-9]{64}$'){throw 'V030_BAD_JOURNAL_TXID'}
    return Join-Path ([string]$Paths.journal) ('backup-proof-'+$TransactionId+'.dpapi')
}
function Save-ApprovedPreparedSealedV030 {
    param($Paths,$Record)
    Assert-ApprovedPreparedHostedV030
    $plain=[Text.Encoding]::UTF8.GetBytes(($Record|ConvertTo-Json -Compress -Depth 6))
    $entropy=[Text.Encoding]::UTF8.GetBytes('ApprovedPreparedJournal|v030|'+[string]$Record.transaction_id)
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    try{$cipher=[Security.Cryptography.ProtectedData]::Protect($plain,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)}
    finally{[Array]::Clear($plain,0,$plain.Length)}
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$digest=$hash.ComputeHash($cipher)}finally{$hash.Dispose()}
    $out=New-Object byte[] ($cipher.Length+32)
    [Array]::Copy($digest,0,$out,0,32)
    [Array]::Copy($cipher,0,$out,32,$cipher.Length)
    $file=Get-ApprovedPreparedSealedPathV030 -Paths $Paths -TransactionId ([string]$Record.transaction_id)
    $stream=[IO.FileStream]::new($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($out,0,$out.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    return $file
}
function Read-ApprovedPreparedSealedV030 {
    param($Paths,[string]$TransactionId)
    Assert-ApprovedPreparedHostedV030
    $path=Get-ApprovedPreparedSealedPathV030 -Paths $Paths -TransactionId $TransactionId
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $item.Length -lt 160 -or $item.Length -gt 32768){
        throw 'V030_BACKUP_PROOF_FILE_INVALID'
    }
    $all=[IO.File]::ReadAllBytes($path)
    if($all.Length -ne $item.Length){throw 'V030_BACKUP_PROOF_FILE_RACED'}
    $cipher=New-Object byte[] ($all.Length-32)
    [Array]::Copy($all,32,$cipher,0,$cipher.Length)
    $h=[Security.Cryptography.SHA256]::Create()
    try{$digest=$h.ComputeHash($cipher)}finally{$h.Dispose()}
    for($i=0;$i -lt 32;$i++){
        if($all[$i] -ne $digest[$i]){throw 'V030_SEALED_PROOF_CIPHER_HEADER_TAMPERED'}
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=$null
    try{
       $plain=[Security.Cryptography.ProtectedData]::Unprotect(
          $cipher,[Text.Encoding]::UTF8.GetBytes('ApprovedPreparedJournal|v030|'+$TransactionId),
          [Security.Cryptography.DataProtectionScope]::CurrentUser)
       $r=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
    }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
    if([string]$r.managed_by -cne 'approved-real-hmac-prepared-journal-v030' -or
       [int]$r.schema -ne 1 -or [string]$r.transaction_id -cne $TransactionId -or
       [bool]$r.production_mutation_authorized){
        throw 'V030_DPAPI_RECORD_SCHEMA_OR_AUTHORITY_MISMATCH'
    }
    return $r
}
function Read-ApprovedPreparedCentralJournalV030 {
    param([string]$WorkRoot,[string]$Name,[string]$TokenId,
          [string]$ReceiptStore,[string]$TransactionId)
    $deny={param([string]$Why)
      return [pscustomobject]@{ok=$false;reason=$Why;production_mutation_authorized=$false}}
    try{
       $p=Get-ApprovedPreparedPathsV030 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
       $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$p.runner) -StoreDirectory ([string]$p.journal)
       if(-not[bool]$j.ok -or [int64]$j.revision -ne 0 -or
          [string]$j.entry.phase -cne 'prepared' -or
          [string]$j.transaction_id -cne $TransactionId -or
          [string]$j.entry.consumption_id -cne $TokenId -or
          [string]$j.entry.name -cne $Name.ToLowerInvariant() -or
          [string]$j.entry.live_path -cne [string]$p.live -or
          [string]$j.entry.app_backup_path -cne [string]$p.app_backup -or
          [string]$j.entry.persistence_backup_path -cne [string]$p.persistence_backup){
           throw 'V030_CENTRAL_JOURNAL_UNEXPECTED_CURRENT_TRANSACTION'
       }
       $record=Read-ApprovedPreparedSealedV030 -Paths $p -TransactionId $TransactionId
       if([string]$record.consumed_token_id -cne $TokenId -or
          [string]$record.source -cne [string]$j.entry.source_identity -or
          [string]$record.commit -cne [string]$j.entry.remote_commit_sha -or
          [string]$record.stage_fingerprint -cne [string]$j.entry.stage_result_fingerprint -or
          [string]$record.preparation_fingerprint -cne [string]$j.entry.preparation_fingerprint){
           throw 'V030_DPAPI_BACKUP_RECORD_TO_JOURNAL_DRIFT'
       }
       $cons=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId $TokenId
       if(-not[bool]$cons.ok -or -not[bool]$cons.single_use_consumed -or
          [string]$cons.name -cne $Name -or
          [string]$cons.runtime_tree_sha256 -cne [string]$record.stage_runtime_tree_sha256 -or
          [string]$cons.source_provenance_sha256 -cne [string]$record.provenance_sha256){
           throw 'V030_REAL_CONSUMPTION_RECEIPT_DRIFT'
       }
       # After a crash the issuer key is unavailable, but the sealed V030
       # record must still bind the PREPARED journal to the exact original
       # V029 archive and staged runtime tree. Never treat backups alone
       # as sufficient authority to apply an altered candidate.
       $stageArgs=[pscustomobject]@{
           name=$Name
           workspace_path=[string]$record.workspace_path
           archive_path=[string]$record.archive_path
           stage_path=[string]$record.stage_path
       }
       $stagePaths=Assert-ApprovedLiveHmacStagePathsV029 -Acquired $stageArgs
       if([string]$stagePaths.root -cne [string]$j.entry.stage_workspace_path -or
          (Get-FileHash -LiteralPath ([string]$stagePaths.archive) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$record.archive_sha256){
          throw 'V030_SEALED_REAL_SOURCE_ARCHIVE_OR_WORKSPACE_CHANGED_AFTER_PREPARE'
       }
       $staged=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$stagePaths.stage)
       $stagedFull=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$stagePaths.stage)
       if(-not[bool]$staged.safe -or -not[bool]$staged.installable -or
          [string]$staged.manifest_name -cne [string]$record.manifest_name -or
          [string]$staged.tree_sha256 -cne [string]$record.stage_runtime_tree_sha256 -or
          [string]$stagedFull.tree_sha256 -cne [string]$record.stage_tree_sha256 -or
          [int]$stagedFull.file_count -ne [int]$record.stage_file_count -or
          [int64]$stagedFull.total_bytes -ne [int64]$record.stage_total_bytes){
          throw 'V030_SEALED_REAL_FULL_STAGE_BYTES_CHANGED_AFTER_PREPARE'
       }
       $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
       $backup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.app_backup)
       $persistence=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.persist)
       $persistBackup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.persistence_backup)
       if(-not(Test-ApprovedPreparedEqualTreeV030 $live $backup) -or
          -not(Test-ApprovedPreparedEqualTreeV030 $persistence $persistBackup) -or
          [string]$live.tree_sha256 -cne [string]$record.live_tree_sha256 -or
          [string]$persistence.tree_sha256 -cne [string]$record.persistence_tree_sha256){
          throw 'V030_EXACT_ORIGINAL_SOURCE_OR_PROTECTED_FIXTURE_BACKUP_CHANGED'
       }
       return [pscustomobject]@{ok=$true;reason='independently-verified-approved-HMAC-and-old-state-CAS-prepared'
          transaction_id=$TransactionId;phase='prepared';journal_revision=0
          original_tree_sha256=[string]$live.tree_sha256
          persistence_fixture_tree_sha256=[string]$persistence.tree_sha256
          original_hmac_key_needed=$false;real_spotify_persistence_covered=$false
          production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('V030_INDEPENDENT_PREPARED_READ_DENIED:'+ [string]$_.Exception.Message)}
}
function Invoke-ApprovedHmacToPreparedCentralJournalV030 {
    param($Item,$Acquired,$Permit,[byte[]]$SessionKey,
          [string]$ReceiptStore,[string]$WorkRoot)
    Assert-ApprovedPreparedHostedV030
    $admission=Test-ApprovedLiveHmacStagePermitV029 -Item $Item -Acquired $Acquired -Permit $Permit -SessionKey $SessionKey
    if(-not[bool]$admission.ok){throw ('V030_FRESH_HMAC_SOURCE_DENIED:'+ [string]$admission.reason)}
    $cons=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId ([string]$Permit.token_id)
    if(-not[bool]$cons.ok -or -not[bool]$cons.single_use_consumed -or
       [string]$cons.name -cne [string]$Item.name -or
       [string]$cons.runtime_tree_sha256 -cne [string]$Acquired.runtime_tree_sha256){
       throw 'V030_EXPECTED_GENUINELY_CONSUMED_V029_SOURCE_MISSING'
    }
    $p=Get-ApprovedPreparedPathsV030 -WorkRoot $WorkRoot -Name ([string]$Item.name) -TokenId ([string]$Permit.token_id)
    if([IO.Directory]::Exists([string]$p.transaction)){throw 'V030_TRANSACTION_ALREADY_EXISTS_NO_RESET'}
    foreach($path in @([string]$Acquired.stage_path,[string]$Acquired.workspace_path,
      [string]$p.live,[string]$p.persist)){
        if(Test-CustomAppAtomicPathsOverlapV010 -A $path -B ([string]$p.transaction)){
           throw 'V030_TRANSACTION_ROOT_OVERLAPS_PROTECTED_INPUT'
        }
    }
    $stage=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Item.name) -AppPath ([string]$Acquired.stage_path)
    $current=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Item.name) -AppPath ([string]$p.live)
    if(-not[bool]$stage.safe -or -not[bool]$stage.installable -or
       -not[bool]$current.safe -or -not[bool]$current.installable -or
       [string]$stage.tree_sha256 -cne [string]$Permit.runtime_tree_sha256 -or
       [string]$stage.manifest_name -cne [string]$current.manifest_name -or
       [string]$stage.tree_sha256 -ceq [string]$current.tree_sha256){
       throw 'V030_NOT_A_SAFE_EXISTING_DIFFERENT_VERSION_OF_SAME_CUSTOM_APP'
    }
    $before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
    $persistBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.persist)
    $stageBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Acquired.stage_path)
    # Source runtime digest hashes files only; V010 also includes directory
    # rows. Preserve BOTH instead of wrongly requiring hash equality.
    if([string]$stage.tree_sha256 -cne [string]$cons.runtime_tree_sha256 -or
       [string]$stageBefore.tree_sha256 -cnotmatch '^[a-f0-9]{64}$'){
       throw 'V046_SOURCE_RUNTIME_OR_FULL_TREE_NOT_AUTHENTICATED'
    }
    [IO.Directory]::CreateDirectory([string]$p.transaction)|Out-Null
    $appBackup=Copy-CustomAppAtomicTreeV010 -Source ([string]$p.live) -Destination ([string]$p.app_backup)
    $persistenceBackup=Copy-CustomAppAtomicTreeV010 -Source ([string]$p.persist) -Destination ([string]$p.persistence_backup)
    if(-not(Test-ApprovedPreparedEqualTreeV030 $before $appBackup) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $persistBefore $persistenceBackup) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $before (Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live))) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $persistBefore (Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.persist))) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $stageBefore (Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Acquired.stage_path)))){
       throw 'V030_COPY_OR_PROTECTED_SOURCE_CHANGED_BEFORE_JOURNAL'
    }
    $material=@('approved-v030-stage',[string]$Permit.token_id,[string]$Permit.source_provenance_sha256,
       [string]$Permit.archive_sha256,[string]$stageBefore.tree_sha256,[string]$Permit.registry_sha256)
    $stageFp=Get-CustomAppProductionCrashJournalSha256V010 ($material -join [char]10)
    $prep=@('approved-v030-backup',[string]$before.tree_sha256,[string]$before.file_count,
       [string]$before.total_bytes,[string]$persistBefore.tree_sha256,
       [string]$persistBefore.file_count,[string]$persistBefore.total_bytes,
       [string]$stageFp,[string]$p.live,[string]$p.persist,
       [string]$p.app_backup,[string]$p.persistence_backup)
    $prepFp=Get-CustomAppProductionCrashJournalSha256V010 ($prep -join [char]10)
    $args=@{Name=[string]$Item.name;ConsumptionId=[string]$Permit.token_id;
       SourceIdentity=[string]$Acquired.source;RemoteCommitSha=[string]$Acquired.source_snapshot.commit_sha;
       StageResultFingerprint=$stageFp;PreparationFingerprint=$prepFp;
       AllowedRoot=[string]$p.runner;LivePath=[string]$p.live;
       TransactionRoot=[string]$p.transaction;StageWorkspacePath=[string]$Acquired.workspace_path;
       AppBackupPath=[string]$p.app_backup;PersistenceBackupPath=[string]$p.persistence_backup}
    $identity=New-CustomAppProductionCrashJournalIdentityV010 @args
    [IO.Directory]::CreateDirectory([string]$p.journal)|Out-Null
    $record=[pscustomobject]@{
       schema=1;managed_by='approved-real-hmac-prepared-journal-v030'
       transaction_id=[string]$identity.transaction_id;consumed_token_id=[string]$Permit.token_id
       source=[string]$identity.source_identity;commit=[string]$identity.remote_commit_sha
       provenance_sha256=[string]$Permit.source_provenance_sha256
       archive_sha256=[string]$Acquired.archive_sha256
       workspace_path=[string]$Acquired.workspace_path
       archive_path=[string]$Acquired.archive_path
       stage_path=[string]$Acquired.stage_path
       manifest_name=[string]$stage.manifest_name
       stage_file_count=[int]$stageBefore.file_count
       stage_total_bytes=[int64]$stageBefore.total_bytes
       stage_tree_sha256=[string]$stageBefore.tree_sha256
       stage_runtime_tree_sha256=[string]$stage.tree_sha256
       live_tree_sha256=[string]$before.tree_sha256
       persistence_tree_sha256=[string]$persistBefore.tree_sha256
       stage_fingerprint=$stageFp;preparation_fingerprint=$prepFp
       fixture_persistence_only=$true;production_mutation_authorized=$false}
    $sealed=Save-ApprovedPreparedSealedV030 -Paths $p -Record $record
    if(-not[IO.File]::Exists($sealed)){throw 'V030_DPAPI_BACKUP_PROOF_NOT_DURABLE'}
    $j=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$p.runner) -StoreDirectory ([string]$p.journal) -Identity $identity
    if(-not[bool]$j.ok -or -not[bool]$j.persisted -or -not[bool]$j.read_after_write_verified){
        throw ('V030_REAL_CENTRAL_JOURNAL_PREPARED_INIT_DENIED:'+ [string]$j.reason)
    }
    $read=Read-ApprovedPreparedCentralJournalV030 -WorkRoot ([string]$p.work) -Name ([string]$Item.name) -TokenId ([string]$Permit.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$identity.transaction_id)
    if(-not[bool]$read.ok){throw ('V030_COLD_READBACK_AFTER_INIT_FAILED:'+ [string]$read.reason)}
    return [pscustomobject]@{
       ok=$true;reason='approved-real-source-HMAC-spent-original-backed-up-journal-prepared'
       name=[string]$Item.name;token_id=[string]$Permit.token_id
       transaction_id=[string]$identity.transaction_id;work_root=[string]$p.work
       journal_store=[string]$p.journal;app_backup=[string]$p.app_backup
       fixture_persistence_backup=[string]$p.persistence_backup
       phase='prepared';journal_revision=0;real_spotify_persistence_covered=$false
       actual_spotify_backup_and_native_apply_still_required=$true
       production_execution_authorized=$false;production_mutation_authorized=$false}
}
