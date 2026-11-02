$CustomAppProductionJournalAwareAtomicSchema = 1
$CustomAppProductionJournalAwareAtomicManagedBy = 'custom-app-production-journal-aware-atomic-mutation-v1'
$CustomAppProductionJournalAwareAtomicQualifiedMutationHead = 'e2b80822835bf5d59dc179e345e098b5bd79759e'
$CustomAppProductionJournalAwareAtomicQualifiedMutationCoreBlob = '394e7bda96501f9ac320ceabe96b4cf96661fe2d'
$CustomAppProductionJournalAwareAtomicQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'
$CustomAppProductionJournalAwareAtomicQualifiedJournalCoreBlob = 'a3df7e5d89c594083c10e240e13029ca5640b8ae'

function Get-CustomAppProductionJournalAwareAtomicSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionJournalAwareAtomicSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function to inject bounded crash windows.
}
function New-CustomAppProductionJournalAwareAtomicDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()][string]$TransactionRoot=$null,[AllowNull()][string]$JournalPhase=$null,[bool]$LiveMoveStarted=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;transaction_root=$TransactionRoot;journal_phase=$JournalPhase;live_move_started=$LiveMoveStarted
        journal_bound_before_live_side_effect=$false;result_is_authority=$false;requires_recovery=($LiveMoveStarted -or -not [string]::IsNullOrWhiteSpace($JournalPhase))
        spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionJournalAwareAtomicCanonicalV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Get-CustomAppProductionJournalAwareAtomicTransactionRootV010 {
    param([Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$TransactionNonce)
    if($TransactionNonce -notmatch '^[0-9a-fA-F]{32}$'){throw 'journal-aware-atomic-transaction-nonce-invalid'}
    $live=Get-CustomAppProductionJournalAwareAtomicCanonicalV010 $LivePath
    return (Join-Path ([IO.Path]::GetDirectoryName($live)) ('.spotify-control-txn-'+$TransactionNonce.ToLowerInvariant()))
}
function Assert-CustomAppProductionJournalAwareAtomicPreconditionsV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,
        [Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$AppBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    foreach($v in @($ExpectedLiveRuntimeTreeSha256,$ExpectedLiveFullTreeSha256,$ExpectedStageRuntimeTreeSha256,$ExpectedAppBackupTreeSha256,$ExpectedPersistenceFingerprint)){
        if(-not (Test-CustomAppProductionJournalAwareAtomicSha256V010 ([string]$v))){throw 'journal-aware-atomic-sha-input-invalid'}
    }
    if($ExpectedLiveFullFileCount -lt 1 -or $ExpectedLiveFullTotalBytes -lt 1 -or $ExpectedAppBackupFileCount -lt 1 -or $ExpectedAppBackupTotalBytes -lt 1){throw 'journal-aware-atomic-count-or-byte-input-invalid'}
    if($ExpectedLiveFullTreeSha256 -cne $ExpectedAppBackupTreeSha256 -or $ExpectedLiveFullFileCount -ne $ExpectedAppBackupFileCount -or $ExpectedLiveFullTotalBytes -ne $ExpectedAppBackupTotalBytes){throw 'journal-aware-atomic-live-backup-contract-mismatch'}
    $live=Assert-CustomAppAtomicSafeDirectoryV010 -Path $LivePath -Label 'journal-aware-live'
    $stage=Assert-CustomAppAtomicSafeDirectoryV010 -Path $StagePath -Label 'journal-aware-stage'
    $backup=Assert-CustomAppAtomicSafeDirectoryV010 -Path $AppBackupPath -Label 'journal-aware-app-backup'
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live
    if(-not [bool]$runtime.safe -or -not [bool]$runtime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -or ([string]$runtime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveRuntimeTreeSha256.Trim().ToLowerInvariant()){throw 'journal-aware-atomic-live-runtime-mismatch'}
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root $live
    if(([string]$full.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$full.file_count -ne $ExpectedLiveFullFileCount -or [int64]$full.total_bytes -ne $ExpectedLiveFullTotalBytes){throw 'journal-aware-atomic-live-full-tree-mismatch'}
    $stageRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage
    if(-not [bool]$stageRuntime.safe -or -not [bool]$stageRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stageRuntime) -or ([string]$stageRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){throw 'journal-aware-atomic-stage-runtime-mismatch'}
    if(Test-Path -LiteralPath (Join-Path $stage '.git')){throw 'journal-aware-atomic-stage-vcs-metadata-forbidden'}
    $backupSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $backup
    if(([string]$backupSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedAppBackupTreeSha256.Trim().ToLowerInvariant() -or [int]$backupSnapshot.file_count -ne $ExpectedAppBackupFileCount -or [int64]$backupSnapshot.total_bytes -ne $ExpectedAppBackupTotalBytes){throw 'journal-aware-atomic-app-backup-mismatch'}
    $pc=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $PersistenceBackupPath -ExpectedFingerprint $ExpectedPersistenceFingerprint
    if(-not [bool]$pc.ok){throw ('journal-aware-atomic-persistence-backup-invalid:'+[string]$pc.reason)}
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if(([string]$persist.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){throw 'journal-aware-atomic-protected-persistence-drift'}
    return [pscustomobject]@{live=$live;stage=$stage;backup=$backup;runtime=$runtime;full=$full;stage_runtime=$stageRuntime;backup_snapshot=$backupSnapshot;persistence=$persist}
}
function Get-CustomAppProductionJournalAwareAtomicResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_mutation_head,[string]$Result.qualified_mutation_core_blob,[string]$Result.qualified_journal_head,[string]$Result.qualified_journal_core_blob,
        [string]$Result.name,[string]$Result.transaction_id,[string]$Result.transaction_root,[string]$Result.old_live_path,[string]$Result.live_path,[string]$Result.stage_path,
        [string]$Result.pre_live_full_tree_sha256,[string]$Result.post_runtime_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.journal_revision,[string]$Result.journal_entry_sha256,
        [string]$Result.journal_bound_before_live_side_effect,[string]$Result.live_code_swap_performed,[string]$Result.requires_transaction_finalization,[string]$Result.requires_spicetify_apply_phase,
        [string]$Result.result_is_authority,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Invoke-CustomAppProductionJournalAwareAtomicMutationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$CallerAdmissionManagedBy,[Parameter(Mandatory=$true)][string]$CallerAdmissionFingerprint,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$TransactionNonce,
        [Parameter(Mandatory=$true)][string]$ConsumptionId,[Parameter(Mandatory=$true)][string]$SourceIdentity,[Parameter(Mandatory=$true)][string]$RemoteCommitSha,[Parameter(Mandatory=$true)][string]$StageResultFingerprint,[Parameter(Mandatory=$true)][string]$PreparationFingerprint,[Parameter(Mandatory=$true)][string]$StageWorkspacePath,
        [Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,
        [Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$AppBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[string]$Txn=$null,[string]$Phase=$null,[bool]$Started=$false) New-CustomAppProductionJournalAwareAtomicDeniedV010 -Reason $Reason -TransactionRoot $Txn -JournalPhase $Phase -LiveMoveStarted $Started}
    if([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($CallerAdmissionManagedBy) -or -not (Test-CustomAppProductionJournalAwareAtomicSha256V010 $CallerAdmissionFingerprint)){return & $deny 'journal-aware-atomic-caller-admission-invalid'}
    try{$pre=Assert-CustomAppProductionJournalAwareAtomicPreconditionsV010 -Name $Name -LivePath $LivePath -StagePath $StagePath -ExpectedLiveRuntimeTreeSha256 $ExpectedLiveRuntimeTreeSha256 -ExpectedLiveFullTreeSha256 $ExpectedLiveFullTreeSha256 -ExpectedLiveFullFileCount $ExpectedLiveFullFileCount -ExpectedLiveFullTotalBytes $ExpectedLiveFullTotalBytes -ExpectedStageRuntimeTreeSha256 $ExpectedStageRuntimeTreeSha256 -AppBackupPath $AppBackupPath -ExpectedAppBackupTreeSha256 $ExpectedAppBackupTreeSha256 -ExpectedAppBackupFileCount $ExpectedAppBackupFileCount -ExpectedAppBackupTotalBytes $ExpectedAppBackupTotalBytes -PersistenceBackupPath $PersistenceBackupPath -ExpectedPersistenceFingerprint $ExpectedPersistenceFingerprint -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('journal-aware-atomic-precondition-denied:'+[string]$_.Exception.Message)}
    $txn=Get-CustomAppProductionJournalAwareAtomicTransactionRootV010 -LivePath $pre.live -TransactionNonce $TransactionNonce
    $parent=[IO.Path]::GetDirectoryName($pre.live)
    if(-not ([IO.Path]::GetDirectoryName($txn)).Equals($parent,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $txn)){return & $deny 'journal-aware-atomic-transaction-root-invalid-or-collision' $txn}
    try{
        $identity=New-CustomAppProductionCrashJournalIdentityV010 -Name $Name -ConsumptionId $ConsumptionId -SourceIdentity $SourceIdentity -RemoteCommitSha $RemoteCommitSha -StageResultFingerprint $StageResultFingerprint -PreparationFingerprint $PreparationFingerprint -AllowedRoot $AllowedRoot -LivePath $pre.live -TransactionRoot $txn -StageWorkspacePath $StageWorkspacePath -AppBackupPath $AppBackupPath -PersistenceBackupPath $PersistenceBackupPath
        $init=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -Identity $identity -Now $Now
        if($null -eq $init -or -not [bool]$init.ok -or -not [bool]$init.read_after_write_verified){return & $deny ('journal-aware-atomic-journal-init-denied:'+[string]$init.reason) $txn}
    }catch{return & $deny ('journal-aware-atomic-journal-init-threw:'+[string]$_.Exception.Message) $txn}
    $phase='prepared'
    $candidate=Join-Path $txn 'candidate';$old=Join-Path $txn 'old-live'
    try{
        [IO.Directory]::CreateDirectory($txn)|Out-Null
        [void](Copy-CustomAppAtomicTreeV010 -Source $pre.stage -Destination $candidate)
        $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $pre.live
        if([bool]$git.present){[void](Copy-CustomAppAtomicTreeV010 -Source (Join-Path $pre.live '.git') -Destination (Join-Path $candidate '.git'))}
        $candidateRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $candidate
        if(-not [bool]$candidateRuntime.safe -or -not [bool]$candidateRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $candidateRuntime) -or ([string]$candidateRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){throw 'candidate-runtime-verification-failed'}
        $candidateGit=Test-CustomAppAtomicGitSnapshotV010 -LivePath $candidate -Expected $git
        if(-not [bool]$candidateGit.ok){throw ('candidate-'+[string]$candidateGit.reason)}
    }catch{
        try{if(Test-Path -LiteralPath $txn){Remove-CustomAppAtomicDirectoryV010 -Path $txn -ExpectedParent $parent -ExpectedName ([IO.Path]::GetFileName($txn))}}catch{}
        return & $deny ('journal-aware-atomic-candidate-preparation-failed:'+[string]$_.Exception.Message) $txn $phase
    }
    $current=$init;$liveMoveStarted=$false
    try{
        $current=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$current.revision) -ExpectedEntrySha256 ([string]$current.entry.entry_sha256) -Phase 'atomic-mutation-starting' -Now $Now.AddSeconds(1)
        if($null -eq $current -or -not [bool]$current.ok -or -not [bool]$current.read_after_write_verified){return & $deny ('journal-aware-atomic-start-barrier-denied:'+[string]$current.reason) $txn $phase}
        $phase='atomic-mutation-starting'
        Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 -Checkpoint 'after-atomic-starting-before-live-move' -Context ([pscustomobject]@{live_path=$pre.live;transaction_root=$txn;candidate_path=$candidate;old_live_path=$old;journal_store=$JournalStoreDirectory})
        [void](Assert-CustomAppProductionJournalAwareAtomicPreconditionsV010 -Name $Name -LivePath $pre.live -StagePath $pre.stage -ExpectedLiveRuntimeTreeSha256 $ExpectedLiveRuntimeTreeSha256 -ExpectedLiveFullTreeSha256 $ExpectedLiveFullTreeSha256 -ExpectedLiveFullFileCount $ExpectedLiveFullFileCount -ExpectedLiveFullTotalBytes $ExpectedLiveFullTotalBytes -ExpectedStageRuntimeTreeSha256 $ExpectedStageRuntimeTreeSha256 -AppBackupPath $AppBackupPath -ExpectedAppBackupTreeSha256 $ExpectedAppBackupTreeSha256 -ExpectedAppBackupFileCount $ExpectedAppBackupFileCount -ExpectedAppBackupTotalBytes $ExpectedAppBackupTotalBytes -PersistenceBackupPath $PersistenceBackupPath -ExpectedPersistenceFingerprint $ExpectedPersistenceFingerprint -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot)
        [IO.Directory]::Move($pre.live,$old);$liveMoveStarted=$true
        Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 -Checkpoint 'after-live-move-before-journal' -Context ([pscustomobject]@{live_path=$pre.live;transaction_root=$txn;candidate_path=$candidate;old_live_path=$old;journal_store=$JournalStoreDirectory})
        $current=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$current.revision) -ExpectedEntrySha256 ([string]$current.entry.entry_sha256) -Phase 'live-moved-to-old' -Now $Now.AddSeconds(2)
        if($null -eq $current -or -not [bool]$current.ok -or -not [bool]$current.read_after_write_verified){return & $deny ('journal-aware-atomic-live-moved-barrier-denied:'+[string]$current.reason) $txn $phase $true}
        $phase='live-moved-to-old'
        Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 -Checkpoint 'after-live-moved-before-candidate' -Context ([pscustomobject]@{live_path=$pre.live;transaction_root=$txn;candidate_path=$candidate;old_live_path=$old;journal_store=$JournalStoreDirectory})
        $oldSnap=Get-CustomAppUpdateTreeSnapshotV010 -Root $old
        if(([string]$oldSnap.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$oldSnap.file_count -ne $ExpectedLiveFullFileCount -or [int64]$oldSnap.total_bytes -ne $ExpectedLiveFullTotalBytes){return & $deny 'journal-aware-atomic-old-live-drift-before-candidate' $txn $phase $true}
        $persistMid=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if(([string]$persistMid.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-persistence-drift-before-candidate' $txn $phase $true}
        [IO.Directory]::Move($candidate,$pre.live)
        Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 -Checkpoint 'after-candidate-move-before-journal' -Context ([pscustomobject]@{live_path=$pre.live;transaction_root=$txn;candidate_path=$candidate;old_live_path=$old;journal_store=$JournalStoreDirectory})
        $current=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$current.revision) -ExpectedEntrySha256 ([string]$current.entry.entry_sha256) -Phase 'candidate-live' -Now $Now.AddSeconds(3)
        if($null -eq $current -or -not [bool]$current.ok -or -not [bool]$current.read_after_write_verified){return & $deny ('journal-aware-atomic-candidate-live-barrier-denied:'+[string]$current.reason) $txn $phase $true}
        $phase='candidate-live'
    }catch{return & $deny ('journal-aware-atomic-transition-threw:'+[string]$_.Exception.Message) $txn $phase $liveMoveStarted}
    try{
        $post=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $pre.live
        if(-not [bool]$post.safe -or -not [bool]$post.installable -or ([string]$post.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-post-runtime-mismatch' $txn $phase $true}
        $postGit=Test-CustomAppAtomicGitSnapshotV010 -LivePath $pre.live -Expected $git
        if(-not [bool]$postGit.ok){return & $deny ('journal-aware-atomic-post-git-mismatch:'+[string]$postGit.reason) $txn $phase $true}
        $persistAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if(([string]$persistAfter.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-post-persistence-drift' $txn $phase $true}
        $oldSnap=Get-CustomAppUpdateTreeSnapshotV010 -Root $old
        if(([string]$oldSnap.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-post-old-live-drift' $txn $phase $true}
        $r=[pscustomobject]@{
            schema=$CustomAppProductionJournalAwareAtomicSchema;managed_by=$CustomAppProductionJournalAwareAtomicManagedBy;qualified_mutation_head=$CustomAppProductionJournalAwareAtomicQualifiedMutationHead;qualified_mutation_core_blob=$CustomAppProductionJournalAwareAtomicQualifiedMutationCoreBlob;qualified_journal_head=$CustomAppProductionJournalAwareAtomicQualifiedJournalHead;qualified_journal_core_blob=$CustomAppProductionJournalAwareAtomicQualifiedJournalCoreBlob
            name=$Name;transaction_id=([string]$identity.transaction_id).Trim().ToLowerInvariant();transaction_root=$txn;old_live_path=$old;live_path=$pre.live;stage_path=$pre.stage;pre_live_full_tree_sha256=$ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant();post_runtime_tree_sha256=([string]$post.tree_sha256).Trim().ToLowerInvariant();persistence_fingerprint=([string]$persistAfter.fingerprint).Trim().ToLowerInvariant();journal_revision=[int64]$current.revision;journal_entry_sha256=([string]$current.entry.entry_sha256).Trim().ToLowerInvariant()
            journal_bound_before_live_side_effect=$true;live_code_swap_performed=$true;requires_transaction_finalization=$true;requires_spicetify_apply_phase=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
        }
        $r.result_fingerprint=Get-CustomAppProductionJournalAwareAtomicSha256V010 (Get-CustomAppProductionJournalAwareAtomicResultMaterialV010 $r)
        return [pscustomobject]@{ok=$true;reason='journal-aware-atomic-candidate-live-durable-zero-future-authority';result=$r;journal_bound_before_live_side_effect=$true;live_code_swap_performed=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('journal-aware-atomic-post-verification-threw:'+[string]$_.Exception.Message) $txn $phase $true}
}
function Get-CustomAppProductionJournalAwareAtomicStartingInspectionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @([string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.transaction_id,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,[string]$Receipt.state,[string]$Receipt.repair_phase,[string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.old_live_path,[string]$Receipt.candidate_path,[string]$Receipt.live_tree_sha256,[string]$Receipt.old_live_tree_sha256,[string]$Receipt.candidate_runtime_tree_sha256,[string]$Receipt.persistence_fingerprint,[string]$Receipt.inspection_is_authority,[string]$Receipt.production_mutation_authorized) -join "`n"
}
function Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,
        [Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;inspection_is_authority=$false;production_mutation_authorized=$false}}
    try{$read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory}catch{return & $deny ('journal-aware-atomic-inspection-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null -eq $read -or -not [bool]$read.ok -or [string]$read.entry.phase -cne 'atomic-mutation-starting'){return & $deny 'journal-aware-atomic-inspection-not-atomic-starting'}
    if(([string]$read.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-inspection-transaction-mismatch'}
    try{
        $live=Get-CustomAppProductionJournalAwareAtomicCanonicalV010 ([string]$read.entry.live_path);$txn=Get-CustomAppProductionJournalAwareAtomicCanonicalV010 ([string]$read.entry.transaction_root);$old=Join-Path $txn 'old-live';$candidate=Join-Path $txn 'candidate'
        if(-not (Test-Path -LiteralPath $txn -PathType Container)){return & $deny 'journal-aware-atomic-inspection-transaction-root-missing'}
        $children=@(Get-ChildItem -LiteralPath $txn -Force);foreach($child in $children){if(-not $child.PSIsContainer -or [string]$child.Name -notin @('candidate','old-live')){return & $deny 'journal-aware-atomic-inspection-transaction-contents-invalid'}}
        $backup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$read.entry.app_backup_path)
        if(([string]$backup.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedAppBackupTreeSha256.Trim().ToLowerInvariant() -or [int]$backup.file_count -ne $ExpectedAppBackupFileCount -or [int64]$backup.total_bytes -ne $ExpectedAppBackupTotalBytes){return & $deny 'journal-aware-atomic-inspection-app-backup-drift'}
        $pc=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$read.entry.persistence_backup_path) -ExpectedFingerprint $ExpectedPersistenceFingerprint;if(-not [bool]$pc.ok){return & $deny 'journal-aware-atomic-inspection-persistence-backup-drift'}
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot;if(([string]$persist.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-inspection-persistence-drift'}
        if(-not (Test-Path -LiteralPath $candidate -PathType Container)){return & $deny 'journal-aware-atomic-inspection-candidate-missing'}
        $cand=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $candidate;if(-not [bool]$cand.safe -or -not [bool]$cand.installable -or ([string]$cand.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-inspection-candidate-drift'}
        $liveExists=Test-Path -LiteralPath $live -PathType Container;$oldExists=Test-Path -LiteralPath $old -PathType Container
        $liveTree='';$oldTree=''
        if($liveExists){$ls=Get-CustomAppUpdateTreeSnapshotV010 -Root $live;$liveTree=([string]$ls.tree_sha256).Trim().ToLowerInvariant();if($liveTree -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$ls.file_count -ne $ExpectedLiveFullFileCount -or [int64]$ls.total_bytes -ne $ExpectedLiveFullTotalBytes){return & $deny 'journal-aware-atomic-inspection-live-drift'}}
        if($oldExists){$os=Get-CustomAppUpdateTreeSnapshotV010 -Root $old;$oldTree=([string]$os.tree_sha256).Trim().ToLowerInvariant();if($oldTree -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$os.file_count -ne $ExpectedLiveFullFileCount -or [int64]$os.total_bytes -ne $ExpectedLiveFullTotalBytes){return & $deny 'journal-aware-atomic-inspection-old-live-drift'}}
        if($liveExists -and -not $oldExists){$state='pre-first-rename-exact';$repair='rollback-required'}
        elseif(-not $liveExists -and $oldExists){$state='first-rename-complete-unjournaled';$repair='live-moved-to-old'}
        else{return & $deny 'journal-aware-atomic-inspection-filesystem-state-ambiguous'}
        $receipt=[pscustomobject]@{schema=$CustomAppProductionJournalAwareAtomicSchema;managed_by=$CustomAppProductionJournalAwareAtomicManagedBy;transaction_id=([string]$read.transaction_id).Trim().ToLowerInvariant();journal_revision=[int64]$read.revision;journal_entry_sha256=([string]$read.entry.entry_sha256).Trim().ToLowerInvariant();state=$state;repair_phase=$repair;live_path=$live;transaction_root=$txn;old_live_path=$old;candidate_path=$candidate;live_tree_sha256=$liveTree;old_live_tree_sha256=$oldTree;candidate_runtime_tree_sha256=([string]$cand.tree_sha256).Trim().ToLowerInvariant();persistence_fingerprint=([string]$persist.fingerprint).Trim().ToLowerInvariant();inspection_is_authority=$false;production_mutation_authorized=$false;inspection_fingerprint=$null}
        $receipt.inspection_fingerprint=Get-CustomAppProductionJournalAwareAtomicSha256V010 (Get-CustomAppProductionJournalAwareAtomicStartingInspectionMaterialV010 $receipt)
        return [pscustomobject]@{ok=$true;reason='journal-aware-atomic-starting-exact-filesystem-state';receipt=$receipt}
    }catch{return & $deny ('journal-aware-atomic-inspection-threw:'+[string]$_.Exception.Message)}
}
function Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,
        [Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Name $Name -ExpectedLiveFullTreeSha256 $ExpectedLiveFullTreeSha256 -ExpectedLiveFullFileCount $ExpectedLiveFullFileCount -ExpectedLiveFullTotalBytes $ExpectedLiveFullTotalBytes -ExpectedStageRuntimeTreeSha256 $ExpectedStageRuntimeTreeSha256 -ExpectedAppBackupTreeSha256 $ExpectedAppBackupTreeSha256 -ExpectedAppBackupFileCount $ExpectedAppBackupFileCount -ExpectedAppBackupTotalBytes $ExpectedAppBackupTotalBytes -ExpectedPersistenceFingerprint $ExpectedPersistenceFingerprint -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if($null -eq $i -or -not [bool]$i.ok){return [pscustomobject]@{ok=$false;reason=('journal-aware-atomic-starting-repair-inspection-denied:'+[string]$i.reason);repair_is_authority=$false;production_mutation_authorized=$false}}
    $r=$i.receipt
    $append=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$r.journal_revision) -ExpectedEntrySha256 ([string]$r.journal_entry_sha256) -Phase ([string]$r.repair_phase) -Now $Now
    if($null -eq $append -or -not [bool]$append.ok -or -not [bool]$append.read_after_write_verified){return [pscustomobject]@{ok=$false;reason=('journal-aware-atomic-starting-repair-append-denied:'+[string]$append.reason);repair_is_authority=$false;production_mutation_authorized=$false}}
    return [pscustomobject]@{ok=$true;reason='journal-aware-atomic-starting-phase-repaired-from-exact-filesystem-evidence';prior_state=[string]$r.state;phase=[string]$append.entry.phase;transaction_id=[string]$append.transaction_id;revision=[int64]$append.revision;entry_sha256=[string]$append.entry.entry_sha256;repair_is_authority=$false;restore_authorized=$false;apply_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
