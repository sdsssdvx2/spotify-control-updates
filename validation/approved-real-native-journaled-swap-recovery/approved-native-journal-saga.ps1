# V032: REAL published approved CustomApp + the original Addon Manager's
# guarded Spotify persistence backup + V029 consumed HMAC + V031 central CAS.
# In one hosted, disposable filesystem transaction it copies the candidate,
# moves the exact old app to a durable recovery location, moves candidate live,
# invokes the genuine pinned official Spicetify CLI scoped refresh, records
# vendor success under the SAME V010 journal, and can independently recover
# an injected crash using original app bytes WITHOUT the issuer HMAC key.
#
# This is NOT an operational executor. There is no production path bypass;
# successful vendor output is in an isolated fake Spotify XPUI profile.
# There is deliberately NO committed-clean or destructive cleanup phase.
function Assert-ApprovedNativeSagaHostedV032 {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'V032_GENUINE_OFFICIAL_NATIVE_CAS_HOSTED_WINDOWS_ONLY'
    }
}
function Open-ApprovedNativeSagaLeaseV032 {
    param([Parameter(Mandatory=$true)]$Paths)
    Assert-ApprovedNativeSagaHostedV032
    if(-not[IO.Directory]::Exists([string]$Paths.transaction)){
        throw 'V032_NO_EXISTING_DURABLE_V031_TRANSACTION'
    }
    $lock=Join-Path ([string]$Paths.transaction) '.v032-transaction-lease'
    # A crashed process releases FileShare.None; no stale lock deletion.
    return [IO.File]::Open($lock,[IO.FileMode]::OpenOrCreate,
                          [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}
function Read-ApprovedNativeSagaRecoveryEvidenceV032 {
    param([Parameter(Mandatory=$true)]$Paths,
          [Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$TokenId,
          [Parameter(Mandatory=$true)][string]$ReceiptStore,
          [Parameter(Mandatory=$true)][string]$TransactionId)
    Assert-ApprovedNativeSagaHostedV032
    $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$Paths.runner) -StoreDirectory ([string]$Paths.journal)
    if(-not[bool]$journal.ok -or
       [string]$journal.transaction_id -cne $TransactionId -or
       [string]$journal.entry.consumption_id -cne $TokenId -or
       [string]$journal.entry.name -cne $Name.ToLowerInvariant() -or
       [string]$journal.entry.live_path -cne [string]$Paths.live -or
       [string]$journal.entry.transaction_root -cne [string]$Paths.transaction -or
       [string]$journal.entry.app_backup_path -cne [string]$Paths.app_backup){
        throw 'V032_CENTRAL_DURABLE_JOURNAL_IDENTITY_CHANGED'
    }
    $proof=Read-ApprovedPreparedSealedV030 -Paths $Paths -TransactionId $TransactionId
    if([string]$proof.evidence_kind -cne 'real-original-addon-persistence-snapshot-v031' -or
       [string]$proof.token_id -cne $TokenId -or
       [string]$proof.source -cne [string]$journal.entry.source_identity -or
       [string]$proof.commit_sha -cne [string]$journal.entry.remote_commit_sha -or
       [string]$proof.stage_fingerprint -cne [string]$journal.entry.stage_result_fingerprint -or
       [string]$proof.preparation_fingerprint -cne [string]$journal.entry.preparation_fingerprint -or
       [string]$proof.persistence_backup_path -cne [string]$journal.entry.persistence_backup_path){
        throw 'V032_DPAPI_REAL_PERSISTENCE_BACKUP_PROOF_CHANGED'
    }
    $spent=Read-ApprovedLiveHmacConsumedReceiptV029 -Store $ReceiptStore -TokenId $TokenId
    if(-not[bool]$spent.ok -or -not[bool]$spent.single_use_consumed -or
       [string]$spent.name -cne $Name -or
       [string]$spent.runtime_tree_sha256 -cne [string]$proof.stage_tree_sha256 -or
       [string]$spent.source_provenance_sha256 -cne [string]$proof.source_provenance_sha256){
        throw 'V032_ORIGINAL_DURABLY_CONSUMED_HMAC_SOURCE_CHANGED'
    }
    $staged=Assert-ApprovedLiveHmacStagePathsV029 -Acquired ([pscustomobject]@{
       name=$Name;workspace_path=[string]$proof.workspace_path
       archive_path=[string]$proof.archive_path;stage_path=[string]$proof.stage_path})
    if([string]$staged.root -cne [string]$journal.entry.stage_workspace_path -or
       (Get-FileHash -LiteralPath ([string]$staged.archive) -Algorithm SHA256).Hash.ToLowerInvariant() -cne
           [string]$proof.archive_sha256){
        throw 'V032_OFFICIAL_SOURCE_ZIP_CHANGED_SINCE_PREPARED'
    }
    $stage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$staged.stage)
    if(-not[bool]$stage.safe -or -not[bool]$stage.installable -or
       [string]$stage.tree_sha256 -cne [string]$proof.stage_tree_sha256 -or
       [string]$stage.manifest_name -cne [string]$proof.manifest_name){
        throw 'V032_PREPARED_AUTHENTIC_SOURCE_FULL_TREE_CHANGED'
    }
    $backup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Paths.app_backup)
    if([string]$backup.tree_sha256 -cne [string]$proof.original_tree_sha256 -or
       [int]$backup.file_count -le 1 -or [int64]$backup.total_bytes -le 0){
        throw 'V032_BACKUP_OF_PREEXISTING_APP_CHANGED'
    }
    $pb=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot ([string]$Paths.runner) -Path ([string]$proof.persistence_backup_path) -RequireExisting:$true
    if(-not([IO.Path]::GetDirectoryName($pb)).Equals([string]$Paths.persistence_root,[StringComparison]::OrdinalIgnoreCase)){
        throw 'V032_ORIGINAL_SPOTIFY_BACKUP_OWNER_MISMATCH'
    }
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$Paths.local) -AppDataRoot ([string]$Paths.roaming)
    if([string]$persist.fingerprint -cne [string]$proof.persistence_fingerprint -or
       [int]$persist.surface_count -ne [int]$proof.surface_count){
        throw 'V032_ORIGINAL_SPOTIFY_PROTECTED_DATA_CHANGED'
    }
    $manifest=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $pb -ExpectedFingerprint ([string]$proof.persistence_fingerprint)
    if(-not[bool]$manifest.ok){
        throw ('V032_ORIGINAL_GUARDED_SPOTIFY_BACKUP_CHANGED:'+ [string]$manifest.reason)
    }
    return [pscustomobject]@{journal=$journal;proof=$proof;stage=$stage;backup=$backup;
       persist=$persist;archive_path=[string]$staged.archive;stage_path=[string]$staged.stage}
}
function Append-ApprovedNativeSagaPhaseV032 {
    param([Parameter(Mandatory=$true)]$Paths,[Parameter(Mandatory=$true)]$Current,
          [Parameter(Mandatory=$true)][string]$Phase,
          [string]$FinalizationFingerprint=$null,
          [string]$ApplyResultFingerprint=$null)
    $args=@{
       AllowedRoot=[string]$Paths.runner
       StoreDirectory=[string]$Paths.journal
       ExpectedRevision=[int64]$Current.revision
       ExpectedEntrySha256=[string]$Current.entry.entry_sha256
       Phase=$Phase
    }
    if(-not[string]::IsNullOrWhiteSpace($FinalizationFingerprint)){
       $args.FinalizationFingerprint=$FinalizationFingerprint
    }
    if(-not[string]::IsNullOrWhiteSpace($ApplyResultFingerprint)){
       $args.ApplyResultFingerprint=$ApplyResultFingerprint
    }
    $a=Append-CustomAppProductionCrashJournalPhaseV010 @args
    if(-not[bool]$a.ok -or -not[bool]$a.persisted -or
       -not[bool]$a.read_after_write_verified -or
       [string]$a.entry.phase -cne $Phase -or
       [int64]$a.revision -ne ([int64]$Current.revision+1)){
       throw ('V032_CENTRAL_CAS_BARRIER_DENIED_'+$Phase+':'+[string]$a.reason)
    }
    return $a
}
function Get-ApprovedNativeSagaLiveStateV032 {
    param([Parameter(Mandatory=$true)]$Paths,
          [Parameter(Mandatory=$true)]$Evidence)
    $live=$null;$old=$null
    $oldPath=Join-Path ([string]$Paths.transaction) 'old-live'
    if(Test-Path -LiteralPath ([string]$Paths.live)){
       $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Paths.live)
    }
    if(Test-Path -LiteralPath $oldPath){
       $old=Get-CustomAppUpdateTreeSnapshotV010 -Root $oldPath
    }
    $expectedOld=[string]$Evidence.proof.original_tree_sha256
    $expectedNew=[string]$Evidence.proof.stage_tree_sha256
    $liveState=if($null-eq$live){'absent'}elseif([string]$live.tree_sha256 -ceq $expectedOld){'original'}elseif([string]$live.tree_sha256 -ceq $expectedNew){'candidate'}else{'unknown'}
    $oldState=if($null-eq$old){'absent'}elseif([string]$old.tree_sha256 -ceq $expectedOld){'original'}else{'unknown'}
    if($liveState -ceq 'unknown' -or $oldState -ceq 'unknown'){
       throw 'V032_UNRECOGNIZED_LIVE_OR_OLD_LIVE_TREE_FAIL_CLOSED'
    }
    return [pscustomobject]@{
       live=$live;old=$old;live_state=$liveState;old_state=$oldState
       old_path=$oldPath
    }
}
function Invoke-ApprovedNativeJournalApplyV032 {
    param([Parameter(Mandatory=$true)]$Item,
          [Parameter(Mandatory=$true)]$Acquired,
          [Parameter(Mandatory=$true)]$Prepared,
          [Parameter(Mandatory=$true)][string]$ReceiptStore,
          [Parameter(Mandatory=$true)][string]$OfficialExecutable,
          [Parameter(Mandatory=$true)][string]$VendorPrivateRoot,
          [AllowNull()][scriptblock]$NativePreLaunchGuard=$null,
          [ValidateSet('none','after-live-move-before-journal','before-official-cli','after-official-cli-before-pending')][string]$FailurePoint='none')
    Assert-ApprovedNativeSagaHostedV032
    $fail={param([string]$Reason,[string]$Phase)
       return [pscustomobject]@{ok=$false;reason=$Reason;phase=$Phase
          independent_recovery_required=$true;official_vendor_result_not_promoted=$true
          production_mutation_authorized=$false}}
    $name=[string]$Item.name
    $p=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot ([string]$Prepared.work_root) -Name $name -TokenId ([string]$Prepared.token_id)
    $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
    $phase='prepared'
    try{
        if([string]$Prepared.name -cne $name -or
           [string]$Prepared.central_phase -cne 'prepared' -or
           [int]$Prepared.central_revision -ne 0 -or
           [bool]$Prepared.production_mutation_authorized){
            throw 'V032_V031_PREPARED_RECEIPT_NOT_A_REAL_INERT_BACKUP'
        }
        $pre=Read-ApprovedRealPersistPreparedV031 -WorkRoot ([string]$p.work) -Name $name -TokenId ([string]$Prepared.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$Prepared.transaction_id)
        if(-not[bool]$pre.ok){throw ('V032_REAL_GUARDED_PREPARED_SOURCE_BACKUP_DENIED:'+ [string]$pre.reason)}
        $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $name -TokenId ([string]$Prepared.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$Prepared.transaction_id)
        if([int64]$e.journal.revision -ne 0 -or [string]$e.journal.entry.phase -cne 'prepared'){
           throw 'V032_CENTRAL_JOURNAL_ALREADY_ADVANCED'
        }
        if([string]$e.proof.stage_tree_sha256 -cne [string]$Acquired.runtime_tree_sha256 -or
           [string]$e.proof.source_provenance_sha256 -cne [string]$Acquired.source_provenance_sha256){
           throw 'V032_SIGNED_ACTUAL_SOURCE_TO_PREPARED_RECEIPT_DRIFT'
        }
        foreach($pair in @(@([string]$p.live,[string]$p.transaction),
                           @([string]$p.live,[string]$VendorPrivateRoot),
                           @([string]$Acquired.stage_path,[string]$p.transaction))){
            if(Test-CustomAppAtomicPathsOverlapV010 -A $pair[0] -B $pair[1]){
               throw 'V032_OPERATIONAL_PATHS_OVERLAP_PROTECTED_SOURCE'
            }
        }
        if([IO.Directory]::Exists($VendorPrivateRoot)){
           throw 'V032_NATIVE_PRIVATE_ROOT_MUST_BE_FRESH'
        }
        $original=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
        $candidate=Join-Path ([string]$p.transaction) 'candidate'
        $oldPath=Join-Path ([string]$p.transaction) 'old-live'
        if((Test-Path -LiteralPath $candidate) -or (Test-Path -LiteralPath $oldPath)){
           throw 'V032_ALREADY_EXISTING_CANDIDATE_OR_OLD_LIVE'
        }
        $copy=Copy-CustomAppAtomicTreeV010 -Source ([string]$Acquired.stage_path) -Destination $candidate
        $staged=Get-CustomAppUpdateTreeSnapshotV010 -Root $candidate
        if([string]$staged.tree_sha256 -cne [string]$e.proof.stage_tree_sha256 -or
           [string]$copy.tree_sha256 -cne [string]$staged.tree_sha256){
           throw 'V032_CANDIDATE_COPY_DIFFERENT_FROM_SIGNED_UPSTREAM_SOURCE'
        }
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $e.journal -Phase 'atomic-mutation-starting'
        $phase='atomic-mutation-starting'
        # Only filesystem evidence reloaded after the durable start barrier
        # may authorize the live directory move in this disposable lab.
        $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $name -TokenId ([string]$Prepared.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$Prepared.transaction_id)
        $actual=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
        if([string]$actual.tree_sha256 -cne [string]$original.tree_sha256 -or
           [string]$actual.tree_sha256 -cne [string]$e.proof.original_tree_sha256){
           throw 'V032_ORIGINAL_LIVE_CHANGED_AFTER_DURABLE_MUTATION_START'
        }
        [IO.Directory]::Move([string]$p.live,$oldPath)
        if($FailurePoint -ceq 'after-live-move-before-journal'){
           throw 'V032_INJECTED_CRASH_AFTER_LIVE_RENAME_BEFORE_JOURNAL'
        }
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'live-moved-to-old'
        $phase='live-moved-to-old'
        if((Get-CustomAppUpdateTreeSnapshotV010 -Root $oldPath).tree_sha256 -cne
             [string]$e.proof.original_tree_sha256){
           throw 'V032_OLD_LIVE_NOT_BYTE_EXACT_AFTER_MOVE'
        }
        [IO.Directory]::Move($candidate,[string]$p.live)
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'candidate-live'
        $phase='candidate-live'
        $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
        if($state.live_state -cne 'candidate' -or $state.old_state -cne 'original'){
           throw 'V032_CANDIDATE_LIVE_OR_BACKUP_MISSING_AFTER_BARRIER'
        }
        # Source, persistence, V029 consumption, original app backup and
        # V031 DPAPI proof still unchanged; no external journal authority.
        $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $name -TokenId ([string]$Prepared.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$Prepared.transaction_id)
        $final=Get-CustomAppProductionCrashJournalSha256V010 (@(
           'v032-real-approved-staged-swap',[string]$Prepared.transaction_id,
           [string]$Prepared.token_id,
           [string]$e.proof.original_tree_sha256,
           [string]$e.proof.stage_tree_sha256,
           [string]$e.proof.persistence_fingerprint,
           [string]$e.proof.source_provenance_sha256
        ) -join ([char]10))
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'transaction-finalized' -FinalizationFingerprint $final
        $phase='transaction-finalized'
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'apply-starting'
        $phase='apply-starting'
        if($FailurePoint -ceq 'before-official-cli'){
            throw 'V032_INJECTED_CRASH_AFTER_APPLY_STARTING_BARRIER'
        }
        $vendor=Invoke-ApprovedCustomAppScopedNativeHostedV026 -Item $Item -CandidateAppPath ([string]$p.live) -ExpectedRuntimeTreeSha256 ([string]$e.proof.stage_tree_sha256) -OfficialExecutable $OfficialExecutable -PrivateRoot $VendorPrivateRoot -NativePreLaunchGuard $NativePreLaunchGuard
        if(-not[bool]$vendor.ok -or
           -not[bool]$vendor.vendor_started -or
           -not[bool]$vendor.official_native_scoped_output_verified -or
           [string]$vendor.name -cne $name -or
           [string]$vendor.runtime_tree_sha256 -cne [string]$e.proof.stage_tree_sha256 -or
           [string]$vendor.official_binary_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db' -or
           [string]$vendor.target_xpui_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [bool]$vendor.production_mutation_authorized){
           throw ('V032_PINNED_GENUINE_OFFICIAL_SCOPED_NATIVE_FAILED:'+ [string]$vendor.reason)
        }
        # Crash test after the genuine vendor has already changed isolated XPUI,
        # but before the journal can assert success. V034 must restore XPUI too.
        if($FailurePoint -ceq 'after-official-cli-before-pending'){
            throw 'V034_INJECTED_CRASH_AFTER_GENUINE_XPUI_MUTATION_BEFORE_CAS'
        }
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'apply-returned-success-pending-verification'
        $phase='apply-returned-success-pending-verification'
        $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $name -TokenId ([string]$Prepared.token_id) -ReceiptStore $ReceiptStore -TransactionId ([string]$Prepared.transaction_id)
        $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
        if($state.live_state -cne 'candidate' -or $state.old_state -cne 'original'){
           throw 'V032_POST_OFFICIAL_VENDOR_SOURCE_OR_ORIGINAL_CHANGED'
        }
        $applySha=Get-CustomAppProductionCrashJournalSha256V010 (@(
           'v032-real-official-pinned-scoped-output',[string]$Prepared.transaction_id,
           [string]$vendor.name,[string]$vendor.source,
           [string]$vendor.runtime_tree_sha256,
           [string]$vendor.official_binary_sha256,
           [string]$vendor.target_xpui_sha256,
           [string]$e.proof.persistence_fingerprint
        ) -join ([char]10))
        $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'apply-verified' -ApplyResultFingerprint $applySha
        $phase='apply-verified'
        return [pscustomobject]@{ok=$true
           reason='real-published-app-source-guarded-original-backup-native-scope-and-journaled-apply-verified'
           transaction_id=[string]$Prepared.transaction_id
           phase='apply-verified';journal_revision=[int64]$current.revision
           original_app_backup_intact=$true
           original_guarded_persistence_backup_intact=$true
           official_vendor_sha256=[string]$vendor.official_binary_sha256
           isolated_xpui_target_sha256=[string]$vendor.target_xpui_sha256
           official_cli_executed=$true
           tested_only_with_fake_Spotify_xpui=$true
           rollback_backup_preserved=$true;cleanup_performed=$false
           actually_installed_Spotify_updated=$false
           production_execution_authorized=$false
           production_mutation_authorized=$false
        }
    }catch{return & $fail ([string]$_.Exception.Message) $phase}
    finally{if($null-ne$lease){$lease.Dispose()}}
}
function Get-ApprovedNativeRecoveryPathsV032 {
    param([Parameter(Mandatory=$true)][string]$WorkRoot,
          [Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$TokenId)
    Assert-ApprovedNativeSagaHostedV032
    if($Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker') -or
       $TokenId -cnotmatch '^[a-f0-9]{64}$'){
        throw 'V032_RECOVERY_UNKNOWN_NAME_OR_TOKEN'
    }
    # The original directory MAY be absent after a crash between two moves.
    # Do not fabricate it to satisfy the V031 pre-mutation path helper.
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $work=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $WorkRoot -RequireExisting:$true
    if([IO.Path]::GetFileName($work) -cne 'v031-fixture'){
        throw 'V032_RECOVERY_NOT_OWNED_DISPOSABLE_FIXTURE'
    }
    $live=Join-Path (Join-Path $work 'CustomApps') $Name
    if([IO.Directory]::Exists($live)){
        return Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $work -Name $Name -TokenId $TokenId
    }
    if(Test-Path -LiteralPath $live){throw 'V032_LIVE_REPLACED_WITH_NON_DIRECTORY'}
    $txn=Join-Path (Join-Path $work 'transactions') $TokenId
    $paths=[ordered]@{
        runner=$runner;work=$work;live=$live
        local=(Join-Path $work 'ProtectedSpotify\Local')
        roaming=(Join-Path $work 'ProtectedSpotify\Roaming')
        transaction=$txn;app_backup=(Join-Path $txn 'app-backup')
        persistence_root=(Join-Path $txn 'spotify-guarded-backups')
        journal=(Join-Path $txn 'journal')
    }
    foreach($key in @('live','local','roaming','transaction',
                      'app_backup','persistence_root','journal')){
        $exist=$key -ne 'live'
        $paths[$key]=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path ([string]$paths[$key]) -RequireExisting:$exist
        if($exist -and -not[IO.Directory]::Exists([string]$paths[$key])){
            throw ('V032_RECOVERY_REQUIRED_OWNED_DIRECTORY_MISSING_'+$key)
        }
    }
    return [pscustomobject]$paths
}
function Invoke-ApprovedNativeJournalRecoveryV032 {
    param([Parameter(Mandatory=$true)][string]$WorkRoot,
          [Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$TokenId,
          [Parameter(Mandatory=$true)][string]$ReceiptStore,
          [Parameter(Mandatory=$true)][string]$TransactionId,
          [switch]$DeferRollbackComplete)
    Assert-ApprovedNativeSagaHostedV032
    $deny={param([string]$Why)
       return [pscustomobject]@{ok=$false;reason=$Why
           manual_review_required=$true;production_mutation_authorized=$false}}
    $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
    $lease=$null
    try{
        $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
        $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
        $phase=[string]$e.journal.entry.phase
        if($phase -notin @('prepared','atomic-mutation-starting','live-moved-to-old',
          'candidate-live','transaction-finalized','apply-starting',
          'apply-returned-success-pending-verification','rollback-required')){
          throw ('V032_ROLLBACK_OUTSIDE_PRECOMMIT_AMBIGUOUS_WINDOW_'+$phase)
        }
        $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
        if($state.live_state -ceq 'candidate' -and $state.old_state -cne 'original'){
           throw 'V032_NEW_LIVE_CANNOT_REPLACE_WITHOUT_EXACT_OLD_LIVE_PROOF'
        }
        if($state.live_state -ceq 'absent' -and $state.old_state -cne 'original'){
           throw 'V032_ORIGINAL_LIVE_MISSING_NO_EXACT_RENAME_SOURCE'
        }
        if($state.live_state -ceq 'original' -and $state.old_state -ceq 'original'){
           throw 'V032_DUPLICATE_ORIGINAL_LIVE_UNEXPECTED'
        }
        if($phase -cne 'rollback-required'){
            $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $e.journal -Phase 'rollback-required'
        }else{$current=$e.journal}
        $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
        if($state.live_state -ceq 'candidate'){
           $quarantine=Join-Path ([string]$p.transaction) 'failed-candidate-retained'
           if([IO.Directory]::Exists($quarantine)){throw 'V032_RECOVERY_QUARANTINE_ALREADY_EXISTS'}
           [IO.Directory]::Move([string]$p.live,$quarantine)
           [IO.Directory]::Move([string]$state.old_path,[string]$p.live)
        }elseif($state.live_state -ceq 'absent'){
           [IO.Directory]::Move([string]$state.old_path,[string]$p.live)
        }elseif($state.live_state -cne 'original'){
           throw 'V032_ORIGINAL_UNRECOGNIZABLE_FAIL_CLOSED'
        }
        $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
        if([string]$live.tree_sha256 -cne [string]$e.proof.original_tree_sha256){
            throw 'V032_RECOVERED_ORIGINAL_APP_NOT_BYTE_EXACT'
        }
        $r=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
        if([string]$r.journal.entry.phase -cne 'rollback-required'){
           throw 'V032_CENTRAL_ROLLBACK_REQUIRED_JOURNAL_DISAPPEARED'
        }
        # V035 composite rollback: do not claim rollback-complete while the
        # official CLI's XPUI side effects have not yet been restored.
        # The V034 coordinator owns the final CAS after independent XPUI proof.
        if($DeferRollbackComplete){
           $terminal='rollback-required'
        }else{
           $current=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $current -Phase 'rollback-complete'
           $terminal='rollback-complete'
        }
        return [pscustomobject]@{ok=$true
            reason='fresh-process-keyless-exact-original-app-and-guarded-persistence-recovered'
            transaction_id=$TransactionId;phase=$terminal
            xpui_recovery_still_required=[bool]$DeferRollbackComplete
            journal_revision=[int64]$current.revision
            old_app_restored_byte_exact=$true
            persistence_fingerprint_unchanged=$true
            authentic_stage_and_zip_retained=$true
            deleted_backup_files=$false
            isolated_xpui_restored=$false
            isolated_xpui_restore_not_part_of_v032=$true
            actual_Spotify_profile_touched=$false
            production_mutation_authorized=$false}
    }catch{return & $deny ('V032_INDEPENDENT_RECOVERY_REFUSED:'+ [string]$_.Exception.Message)}
    finally{if($null-ne$lease){$lease.Dispose()}}
}
