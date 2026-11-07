# V031 — V028 GitHub ZIP + V029 spent HMAC, exact old app backup,
# the REAL pinned Addon Manager's guarded Spotify persistence backup, and
# the original V010 append-only central journal PREPARED at revision 0.
function Get-ApprovedRealPersistJournalPathsV031 {
    param([string]$WorkRoot,[string]$Name,[string]$TokenId)
    Assert-RealAddonPersistenceHostedV031
    if($Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker') -or
       $TokenId -cnotmatch '^[a-f0-9]{64}$'){throw 'V031_UNAUTHORIZED_APP_OR_TOKEN'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $work=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $WorkRoot -RequireExisting:$true
    if([IO.Path]::GetFileName($work) -cne 'v031-fixture'){throw 'V031_WORK_ROOT_IS_NOT_HOSTED_TEST_FIXTURE'}
    $txn=Join-Path (Join-Path $work 'transactions') $TokenId
    $p=[ordered]@{
       runner=$runner;work=$work
       live=(Join-Path (Join-Path $work 'CustomApps') $Name)
       local=(Join-Path $work 'ProtectedSpotify\Local')
       roaming=(Join-Path $work 'ProtectedSpotify\Roaming')
       transaction=$txn
       app_backup=(Join-Path $txn 'app-backup')
       persistence_root=(Join-Path $txn 'spotify-guarded-backups')
       journal=(Join-Path $txn 'journal')
    }
    foreach($key in @('live','local','roaming','transaction','app_backup','persistence_root','journal')){
       $p[$key]=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path ([string]$p[$key]) -Label ('V031 '+$key)
    }
    foreach($key in @('live','local','roaming')){
       if(-not[IO.Directory]::Exists([string]$p[$key])){throw ('V031_PROTECTED_FIXTURE_MISSING_'+$key)}
    }
    return [pscustomobject]$p
}
function Read-ApprovedRealPersistPreparedV031 {
    param([string]$WorkRoot,[string]$Name,[string]$TokenId,
          [string]$ReceiptStore,[string]$TransactionId)
    $deny={param([string]$Why) return [pscustomobject]@{
       ok=$false;reason=$Why;production_mutation_authorized=$false}}
    try{
       $p=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
       [void](Assert-RealAddonPersistenceRootsV031 -RunnerRoot ([string]$p.runner) -LocalRoot ([string]$p.local) -RoamingRoot ([string]$p.roaming))
       $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$p.runner) -StoreDirectory ([string]$p.journal)
       if(-not[bool]$j.ok -or [int64]$j.revision -ne 0 -or
          [string]$j.entry.phase -cne 'prepared' -or
          [string]$j.transaction_id -cne $TransactionId -or
          [string]$j.entry.name -cne $Name.ToLowerInvariant() -or
          [string]$j.entry.consumption_id -cne $TokenId -or
          [string]$j.entry.live_path -cne [string]$p.live -or
          [string]$j.entry.app_backup_path -cne [string]$p.app_backup -or
          [string]$j.entry.transaction_root -cne [string]$p.transaction){
           throw 'V031_EXISTING_CENTRAL_PREPARED_JOURNAL_IDENTITY_CHANGED'
       }
       $proof=Read-ApprovedPreparedSealedV030 -Paths $p -TransactionId $TransactionId
       if([string]$proof.evidence_kind -cne 'real-original-addon-persistence-snapshot-v031' -or
          [string]$proof.token_id -cne $TokenId -or
          [string]$proof.source -cne [string]$j.entry.source_identity -or
          [string]$proof.commit_sha -cne [string]$j.entry.remote_commit_sha -or
          [string]$proof.stage_fingerprint -cne [string]$j.entry.stage_result_fingerprint -or
          [string]$proof.preparation_fingerprint -cne [string]$j.entry.preparation_fingerprint -or
          [string]$proof.persistence_backup_path -cne [string]$j.entry.persistence_backup_path){
           throw 'V031_SEALED_ACTUAL_SPOTIFY_BACKUP_TO_CENTRAL_JOURNAL_MISMATCH'
       }
       $receipt=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId $TokenId
       if(-not[bool]$receipt.ok -or -not[bool]$receipt.single_use_consumed -or
          [string]$receipt.name -cne $Name -or
          [string]$receipt.runtime_tree_sha256 -cne [string]$proof.stage_tree_sha256 -or
          [string]$receipt.source_provenance_sha256 -cne [string]$proof.source_provenance_sha256){
           throw 'V031_SPENT_GENUINE_SOURCE_HMAC_DID_NOT_MATCH'
       }
       $stageRef=[pscustomobject]@{
           name=$Name;workspace_path=[string]$proof.workspace_path
           archive_path=[string]$proof.archive_path;stage_path=[string]$proof.stage_path
       }
       $paths=Assert-ApprovedLiveHmacStagePathsV029 -Acquired $stageRef
       if([string]$paths.root -cne [string]$j.entry.stage_workspace_path -or
          (Get-FileHash -LiteralPath ([string]$paths.archive) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$proof.archive_sha256){
           throw 'V031_GITHUB_SOURCE_ZIP_OR_WORKSPACE_CHANGED'
       }
       $stage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$paths.stage)
       $live=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$p.live)
       $liveFull=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
       $backup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.app_backup)
       if(-not[bool]$stage.safe -or -not[bool]$stage.installable -or
          [string]$stage.tree_sha256 -cne [string]$proof.stage_tree_sha256 -or
          [string]$stage.manifest_name -cne [string]$proof.manifest_name -or
          [string]$live.manifest_name -cne [string]$stage.manifest_name -or
          [string]$liveFull.tree_sha256 -cne [string]$proof.original_tree_sha256 -or
          -not(Test-ApprovedPreparedEqualTreeV030 $liveFull $backup)){
           throw 'V031_CURRENT_APP_OR_FULL_ROLLBACK_BACKUP_MISMATCH'
       }
       $pb=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot ([string]$p.runner) -Path ([string]$proof.persistence_backup_path) -RequireExisting:$true
       if(-not([IO.Path]::GetDirectoryName($pb)).Equals([string]$p.persistence_root,[StringComparison]::OrdinalIgnoreCase)){
           throw 'V031_GUARDED_PERSISTENCE_BACKUP_WRONG_OWNER'
       }
       $state=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$p.local) -AppDataRoot ([string]$p.roaming)
       if([string]$state.fingerprint -cne [string]$proof.persistence_fingerprint -or
          [int]$state.surface_count -ne [int]$proof.surface_count){
           throw 'V031_PROTECTED_SPOTIFY_SURFACES_CHANGED_AFTER_BACKUP'
       }
       $check=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $pb -ExpectedFingerprint ([string]$proof.persistence_fingerprint)
       if(-not[bool]$check.ok){throw ('V031_ORIGINAL_GUARDED_MANIFEST_OR_BACKUP_CORRUPTED:'+ [string]$check.reason)}
       return [pscustomobject]@{
           ok=$true;reason='real-generated-addon-spicetify-persistence-protected-before-central-prepared-CAS'
           transaction_id=$TransactionId;phase='prepared';journal_revision=0
           token_id=$TokenId;name=$Name
           source_tree_sha256=[string]$stage.tree_sha256
           original_app_sha256=[string]$liveFull.tree_sha256
           persistence_fingerprint=[string]$state.fingerprint
           protected_surface_count=[int]$state.surface_count
           genuine_generated_addon_persistence_contract=$true
           complete_coverage_of_all_possible_spotify_data_not_proven=$true
           issuer_key_not_needed_for_readback=$true
           production_mutation_authorized=$false
       }
    }catch{return & $deny ('V031_EXACT_ORIGINAL_PERSISTENCE_KEYLESS_READ_DENIED:'+ [string]$_.Exception.Message)}
}
function Invoke-ApprovedRealPersistPreparedV031 {
    param($Item,$Acquired,$Permit,[byte[]]$SessionKey,
          [string]$ReceiptStore,[string]$WorkRoot)
    Assert-RealAddonPersistenceHostedV031
    $fresh=Test-ApprovedLiveHmacStagePermitV029 -Item $Item -Acquired $Acquired -Permit $Permit -SessionKey $SessionKey
    if(-not[bool]$fresh.ok){throw ('V031_GENUINE_SOURCE_SIGNED_PERMIT_INVALID:'+ [string]$fresh.reason)}
    $receipt=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId ([string]$Permit.token_id)
    if(-not[bool]$receipt.ok -or -not[bool]$receipt.single_use_consumed -or
       [string]$receipt.name -cne [string]$Item.name -or
       [string]$receipt.runtime_tree_sha256 -cne [string]$Acquired.runtime_tree_sha256){
       throw 'V031_SIGNED_APPROVED_SOURCE_NOT_DURABLY_CONSUMED'
    }
    $p=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $WorkRoot -Name ([string]$Item.name) -TokenId ([string]$Permit.token_id)
    if([IO.Directory]::Exists([string]$p.transaction)){
        throw 'V031_EXISTING_CENTRAL_TRANSACTION_MUST_NOT_BE_RECREATED'
    }
    $old=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Item.name) -AppPath ([string]$p.live)
    $new=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Item.name) -AppPath ([string]$Acquired.stage_path)
    if(-not[bool]$old.safe -or -not[bool]$old.installable -or
       -not[bool]$new.safe -or -not[bool]$new.installable -or
       [string]$new.manifest_name -cne [string]$old.manifest_name -or
       [string]$new.tree_sha256 -cne [string]$Permit.runtime_tree_sha256 -or
       [string]$new.tree_sha256 -ceq [string]$old.tree_sha256){
       throw 'V031_NOT_APPROVED_EXISTING_DIFFERENT_VERSION_OF_REAL_APP'
    }
    foreach($source in @([string]$p.live,[string]$p.local,[string]$p.roaming,
                         [string]$Acquired.stage_path,[string]$Acquired.workspace_path)){
       if(Test-CustomAppAtomicPathsOverlapV010 -A $source -B ([string]$p.transaction)){
           throw 'V031_BACKUPS_OR_JOURNAL_OVERLAP_PROTECTED_SOURCE'
       }
    }
    $oldTree=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
    $newTree=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Acquired.stage_path)
    if([string]$newTree.tree_sha256 -cne [string]$new.tree_sha256){
       throw 'V031_SIGNED_RUNTIME_AND_FULL_CANDIDATE_TREE_DIFFER'
    }
    [IO.Directory]::CreateDirectory([string]$p.transaction)|Out-Null
    $copied=Copy-CustomAppAtomicTreeV010 -Source ([string]$p.live) -Destination ([string]$p.app_backup)
    $state=Invoke-ActualAddonPersistenceGuardedBackupV031 -RunnerRoot ([string]$p.runner) -LocalRoot ([string]$p.local) -RoamingRoot ([string]$p.roaming) -BackupRoot ([string]$p.persistence_root)
    if(-not[bool]$state.ok -or
       -not(Test-ApprovedPreparedEqualTreeV030 $oldTree $copied) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $oldTree (Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live))) -or
       -not(Test-ApprovedPreparedEqualTreeV030 $newTree (Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Acquired.stage_path)))){
       throw 'V031_SNAPSHOT_OR_FULL_SOURCE_ROLLBACK_DRIFT_BEFORE_PREPARED'
    }
    $stageFp=Get-CustomAppProductionCrashJournalSha256V010 (@(
       'approved-real-source-v031',[string]$Permit.token_id,
       [string]$Permit.source_provenance_sha256,[string]$Permit.archive_sha256,
       [string]$newTree.tree_sha256,[string]$Permit.registry_sha256) -join [char]10)
    $prepFp=Get-CustomAppProductionCrashJournalSha256V010 (@(
       'original-addon-persistence-v031',[string]$stageFp,[string]$oldTree.tree_sha256,
       [string]$oldTree.file_count,[string]$oldTree.total_bytes,
       [string]$state.persistence_fingerprint,[string]$state.surface_count,
       [string]$p.live,[string]$p.local,[string]$p.roaming,
       [string]$p.app_backup,[string]$state.backup_path) -join [char]10)
    $idArgs=@{
       Name=[string]$Item.name;ConsumptionId=[string]$Permit.token_id
       SourceIdentity=[string]$Acquired.source
       RemoteCommitSha=[string]$Acquired.source_snapshot.commit_sha
       StageResultFingerprint=$stageFp;PreparationFingerprint=$prepFp
       AllowedRoot=[string]$p.runner;LivePath=[string]$p.live
       TransactionRoot=[string]$p.transaction
       StageWorkspacePath=[string]$Acquired.workspace_path
       AppBackupPath=[string]$p.app_backup
       PersistenceBackupPath=[string]$state.backup_path
    }
    $identity=New-CustomAppProductionCrashJournalIdentityV010 @idArgs
    [IO.Directory]::CreateDirectory([string]$p.journal)|Out-Null
    $proof=[pscustomobject]@{
       schema=1;managed_by='approved-real-hmac-prepared-journal-v030'
       evidence_kind='real-original-addon-persistence-snapshot-v031'
       transaction_id=[string]$identity.transaction_id
       token_id=[string]$Permit.token_id;source=[string]$identity.source_identity
       commit_sha=[string]$identity.remote_commit_sha
       stage_fingerprint=$stageFp;preparation_fingerprint=$prepFp
       source_provenance_sha256=[string]$Permit.source_provenance_sha256
       stage_tree_sha256=[string]$newTree.tree_sha256
       original_tree_sha256=[string]$oldTree.tree_sha256
       archive_sha256=[string]$Acquired.archive_sha256
       manifest_name=[string]$new.manifest_name
       workspace_path=[string]$Acquired.workspace_path
       archive_path=[string]$Acquired.archive_path
       stage_path=[string]$Acquired.stage_path
       persistence_fingerprint=[string]$state.persistence_fingerprint
       surface_count=[int]$state.surface_count
       persistence_backup_path=[string]$state.backup_path
       all_possible_spotify_data_covered=$false
       production_mutation_authorized=$false
    }
    $sealed=Save-ApprovedPreparedSealedV030 -Paths $p -Record $proof
    if(-not[IO.File]::Exists($sealed)){throw 'V031_REAL_PERSISTENCE_PROOF_NOT_DURABLY_SEALED'}
    $journal=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$p.runner) -StoreDirectory ([string]$p.journal) -Identity $identity
    if(-not[bool]$journal.ok -or -not[bool]$journal.persisted -or -not[bool]$journal.read_after_write_verified){
       throw ('V031_REAL_PERSISTENCE_CENTRAL_CAS_PREPARED_DENIED:'+ [string]$journal.reason)
    }
    $check=Read-ApprovedRealPersistPreparedV031 -WorkRoot ([string]$p.work) -Name ([string]$Item.name) -TokenId ([string]$Permit.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$identity.transaction_id)
    if(-not[bool]$check.ok){throw ('V031_BACKUP_CENTRAL_JOURNAL_KEYLESS_READBACK_DENIED:'+ [string]$check.reason)}
    return [pscustomobject]@{
       ok=$true;transaction_id=[string]$identity.transaction_id
       name=[string]$Item.name;token_id=[string]$Permit.token_id
       protected_surface_count=[int]$state.surface_count
       persistence_fingerprint=[string]$state.persistence_fingerprint
       work_root=[string]$p.work;backup_path=[string]$state.backup_path
       central_phase='prepared';central_revision=0
       exact_original_addon_core_used=$true
       no_live_spotify_profile_changed=$true
       all_possible_spotify_data_covered=$false
       official_vendor_not_invoked=$true
       production_mutation_authorized=$false
    }
}
