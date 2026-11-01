$CustomAppProductionRecoveryAwarePermitTransactionFinalizationSchema = 1
$CustomAppProductionRecoveryAwarePermitTransactionFinalizationManagedBy = 'custom-app-production-recovery-aware-permit-transaction-finalization-v1'
$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicHead = 'cb2e50b715a7d7f1bbc7b3b810104cefff7f7d50'
$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicCoreBlob = 'e3506fd65de02978b4c79c1a367461b5496ae3b9'
$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationHead = '75a39eea7b0ef7d35d193962607752ef1a873ae0'
$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationCoreBlob = '2958ae3f92173215d32ef8bf284a9433c52caa61'

function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function for bounded faults.
}

function New-CustomAppProductionRecoveryAwarePermitTransactionFinalizationDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$CleanupAttempted=$false,[bool]$TransactionWorkspaceDeleted=$false,[bool]$RequiresRecovery=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;cleanup_attempted=$CleanupAttempted;transaction_workspace_deleted=$TransactionWorkspaceDeleted
        stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;historical_consumption_reverified_before_cleanup=$false;historical_consumption_reverified_after_cleanup=$false;same_app_newer_consumption_absent=$false
        requires_spicetify_apply_phase=$true;requires_fresh_post_swap_apply_admission=$true;requires_recovery_if_post_cleanup_validation_fails=$RequiresRecovery
        result_is_authority=$false;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 {
    param(
        [Parameter(Mandatory=$true)]$AtomicResult,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$StageExecutorResult,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,[Parameter(Mandatory=$true)][string]$Name
    )
    if($null -eq $ConsumptionPersistenceResult.receipt -or $null -eq $ConsumptionPersistenceResult.persisted_snapshot -or $null -eq $ConsumptionPersistenceResult.persisted_snapshot.state){return [pscustomobject]@{ok=$false;reason='consumption-persistence-evidence-null'}}
    try{$targetRevision=[int64]$ConsumptionPersistenceResult.receipt.persisted_revision}catch{return [pscustomobject]@{ok=$false;reason='consumption-target-revision-invalid'}}
    if($targetRevision -lt 1){return [pscustomobject]@{ok=$false;reason='consumption-target-revision-invalid'}}
    $target=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -TargetState $ConsumptionPersistenceResult.persisted_snapshot.state -TargetRevision $targetRevision -ExpectedConsumptionId ([string]$AtomicResult.consumption_id)
    if($null -eq $target -or -not [bool]$target.ok -or $null -eq $target.target_envelope -or $null -eq $target.current_envelope -or $null -eq $target.current_state){return [pscustomobject]@{ok=$false;reason=('consumption-reload-denied:'+[string]$target.reason)}}
    $historical=([string]$target.target_envelope.envelope_sha256).Trim().ToLowerInvariant()
    foreach($expected in @(([string]$AtomicResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant(),([string]$PreparedResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant(),([string]$StageExecutorResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant())){if($historical -cne $expected){return [pscustomobject]@{ok=$false;reason='historical-consumption-envelope-drift'}}}
    try{$currentRevision=[int64]$target.current_revision;$atomicRevision=[int64]$AtomicResult.current_consumption_revision}catch{return [pscustomobject]@{ok=$false;reason='current-consumption-revision-invalid'}}
    if($currentRevision -lt $targetRevision -or $currentRevision -lt $atomicRevision){return [pscustomobject]@{ok=$false;reason='current-consumption-revision-regressed'}}
    $currentEnvelope=([string]$target.current_envelope.envelope_sha256).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 $currentEnvelope)){return [pscustomobject]@{ok=$false;reason='current-consumption-envelope-invalid'}}
    if($currentRevision -eq $atomicRevision -and $currentEnvelope -cne ([string]$AtomicResult.current_consumption_envelope_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='current-consumption-envelope-drift-at-same-revision'}}
    $rows=@($target.current_state.consumptions);$sameAppNewer=@()
    if($rows.Count -gt $targetRevision){$sameAppNewer=@($rows[$targetRevision..($rows.Count-1)]|Where-Object{([string]$_.name).Trim().ToLowerInvariant() -ceq $Name.Trim().ToLowerInvariant()})}
    if($sameAppNewer.Count -gt 0){return [pscustomobject]@{ok=$false;reason='same-app-newer-consumption'}}
    return [pscustomobject]@{ok=$true;reason='historical-consumption-current-ledger-valid';target_revision=$targetRevision;historical_envelope_sha256=$historical;current_revision=$currentRevision;current_envelope_sha256=$currentEnvelope;same_app_newer_consumption_absent=$true}
}

function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_recovery_aware_atomic_head,[string]$Result.qualified_recovery_aware_atomic_core_blob,[string]$Result.qualified_generic_finalization_head,[string]$Result.qualified_generic_finalization_core_blob,[string]$Result.status,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,[string]$Result.binding_fingerprint,
        [string]$Result.consumption_id,[string]$Result.historical_consumption_envelope_sha256,[string]$Result.current_consumption_envelope_sha256,[string]$Result.current_consumption_revision,
        [string]$Result.recovery_atomic_result_fingerprint,[string]$Result.recovery_pre_apply_result_fingerprint,[string]$Result.recovery_stage_result_fingerprint,
        [string]$Result.live_path,[string]$Result.transaction_root,[string]$Result.old_live_tree_sha256,[string]$Result.live_runtime_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.finalized_at,
        [string]$Result.stage_workspace_path,[string]$Result.app_backup_path,[string]$Result.persistence_backup_path,[string]$Result.transaction_workspace_deleted,[string]$Result.stage_workspace_preserved,[string]$Result.app_backup_preserved,[string]$Result.persistence_backup_preserved,
        [string]$Result.historical_consumption_reverified_before_cleanup,[string]$Result.historical_consumption_reverified_after_cleanup,[string]$Result.same_app_newer_consumption_absent,
        [string]$Result.requires_spicetify_apply_phase,[string]$Result.requires_fresh_post_swap_apply_admission,[string]$Result.requires_recovery_if_post_cleanup_validation_fails,
        [string]$Result.result_is_authority,[string]$Result.apply_execution_authorized,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-null'}}
    foreach($f in @('schema','managed_by','qualified_recovery_aware_atomic_head','qualified_recovery_aware_atomic_core_blob','qualified_generic_finalization_head','qualified_generic_finalization_core_blob','status','name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','current_consumption_revision','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','live_path','transaction_root','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','finalized_at','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_workspace_deleted','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','historical_consumption_reverified_before_cleanup','historical_consumption_reverified_after_cleanup','same_app_newer_consumption_absent','requires_spicetify_apply_phase','requires_fresh_post_swap_apply_admission','requires_recovery_if_post_cleanup_validation_fails','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint')){if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-field-missing-'+$f)}}}
    if([int]$Result.schema -ne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationSchema -or [string]$Result.managed_by -cne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationManagedBy -or [string]$Result.status -cne 'recovery-aware-transaction-workspace-finalized-live-persistence-consumption-reverified'){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-owner-schema-status-mismatch'}}
    if([string]$Result.qualified_recovery_aware_atomic_head -cne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicHead -or [string]$Result.qualified_recovery_aware_atomic_core_blob -cne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicCoreBlob -or [string]$Result.qualified_generic_finalization_head -cne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationHead -or [string]$Result.qualified_generic_finalization_core_blob -cne $CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-lineage-mismatch'}}
    foreach($f in @('transaction_id','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-remote-commit-invalid'}}
    try{if([int64]$Result.github_repo_id -le 0 -or [int64]$Result.current_consumption_revision -lt 1){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-numeric-field-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-numeric-field-invalid'}}
    foreach($f in @('transaction_workspace_deleted','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','historical_consumption_reverified_before_cleanup','historical_consumption_reverified_after_cleanup','same_app_newer_consumption_absent','requires_spicetify_apply_phase','requires_fresh_post_swap_apply_admission','requires_recovery_if_post_cleanup_validation_fails')){if(-not [bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-required-flag-false-'+$f)}}}
    foreach($f in @('result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-authority-escaped-'+$f)}}}
    $at=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Result.finalized_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-time-invalid'}}
    try{
        if(Test-Path -LiteralPath ([string]$Result.transaction_root){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-transaction-root-still-exists'}}
        if(-not (Test-Path -LiteralPath ([string]$Result.live_path) -PathType Container)){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-live-path-missing'}}
        foreach($f in @('stage_workspace_path','app_backup_path','persistence_backup_path')){if(-not (Test-Path -LiteralPath ([string]$Result.$f) -PathType Container)){return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-preserved-path-missing-'+$f)}}}
    }catch{return [pscustomobject]@{ok=$false;reason=('recovery-aware-finalization-result-path-check-failed:'+[string]$_.Exception.Message)}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 (Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-finalization-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-finalization-result-valid-zero-apply-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareAtomicResult,[Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,[Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[bool]$Attempted=$false,[bool]$Deleted=$false,[bool]$Recovery=$false) New-CustomAppProductionRecoveryAwarePermitTransactionFinalizationDeniedV010 -Reason $Reason -CleanupAttempted $Attempted -TransactionWorkspaceDeleted $Deleted -RequiresRecovery $Recovery}
    $atomicCheck=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $RecoveryAwareAtomicResult
    if(-not [bool]$atomicCheck.ok){return & $deny ('recovery-aware-finalization-atomic-result-invalid:'+[string]$atomicCheck.reason)}
    $preparedCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreparedResult
    if(-not [bool]$preparedCheck.ok){return & $deny ('recovery-aware-finalization-prepared-result-invalid:'+[string]$preparedCheck.reason)}
    $stageCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('recovery-aware-finalization-stage-result-invalid:'+[string]$stageCheck.reason)}
    if(([string]$RecoveryAwareAtomicResult.recovery_pre_apply_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-pre-apply-fingerprint-continuity-mismatch'}
    if(([string]$RecoveryAwareAtomicResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant() -or ([string]$RecoveryAwarePreparedResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-stage-fingerprint-continuity-mismatch'}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','consumption_id','binding_fingerprint')){if(([string]$RecoveryAwareAtomicResult.$f).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreparedResult.$f).Trim().ToLowerInvariant() -or ([string]$RecoveryAwareAtomicResult.$f).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-finalization-identity-continuity-mismatch-'+$f)}}
    if(([string]$RecoveryAwareAtomicResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-name-mismatch'}
    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or -not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){return & $deny 'recovery-aware-finalization-lifecycle-not-safe-current-single-location'}

    try{
        $livePath=[IO.Path]::GetFullPath([string]$LifecycleRow.locations[0]).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if(-not $livePath.Equals([IO.Path]::GetFullPath([string]$RecoveryAwareAtomicResult.live_path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){return & $deny 'recovery-aware-finalization-live-path-mismatch'}
        $parent=[IO.Path]::GetDirectoryName($livePath)
        $transactionRoot=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$RecoveryAwareAtomicResult.transaction_root) -Label 'transaction-root'
        if(-not ([IO.Path]::GetDirectoryName($transactionRoot)).Equals($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($transactionRoot) -notmatch '^\.spotify-control-txn-[0-9a-fA-F]{32}$'){return & $deny 'recovery-aware-finalization-transaction-root-shape-invalid'}
        $oldLive=Assert-CustomAppAtomicSafeDirectoryV010 -Path (Join-Path $transactionRoot 'old-live') -Label 'old-live'
        $expectedOld=[IO.Path]::GetFullPath([string]$RecoveryAwareAtomicResult.old_live_path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if(-not $oldLive.Equals($expectedOld,[StringComparison]::OrdinalIgnoreCase)){return & $deny 'recovery-aware-finalization-old-live-path-mismatch'}
        $children=@(Get-ChildItem -LiteralPath $transactionRoot -Force -ErrorAction Stop)
        if($children.Count -ne 1 -or -not $children[0].PSIsContainer -or [string]$children[0].Name -cne 'old-live' -or ($children[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return & $deny 'recovery-aware-finalization-transaction-root-contents-not-exact-old-live-only'}
        $oldSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $oldLive
        $backupSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$RecoveryAwarePreparedResult.app_backup_path)
        if(([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareAtomicResult.old_live_tree_sha256).Trim().ToLowerInvariant() -or ([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreparedResult.app_backup_tree_sha256).Trim().ToLowerInvariant() -or [int]$oldSnapshot.file_count -ne [int]$RecoveryAwarePreparedResult.app_backup_file_count -or [int64]$oldSnapshot.total_bytes -ne [int64]$RecoveryAwarePreparedResult.app_backup_total_bytes){return & $deny 'recovery-aware-finalization-old-live-not-exact-pre-swap-tree'}
        if(([string]$backupSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant() -or [int]$backupSnapshot.file_count -ne [int]$oldSnapshot.file_count -or [int64]$backupSnapshot.total_bytes -ne [int64]$oldSnapshot.total_bytes){return & $deny 'recovery-aware-finalization-app-backup-byte-drift'}
        if(-not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.stage_workspace_path) -PathType Container) -or -not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.stage_path) -PathType Container)){return & $deny 'recovery-aware-finalization-stage-workspace-or-stage-missing'}
        $stageRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$RecoveryAwarePreparedResult.stage_path)
        $liveRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath
        if(-not [bool]$stageRuntime.safe -or -not [bool]$stageRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stageRuntime) -or ([string]$stageRuntime.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-stage-runtime-drift'}
        foreach($expected in @(([string]$RecoveryAwareAtomicResult.post_runtime_tree_sha256).Trim().ToLowerInvariant(),([string]$RecoveryAwarePreparedResult.stage_tree_sha256).Trim().ToLowerInvariant(),([string]$RecoveryAwareStageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant())){if(-not [bool]$liveRuntime.safe -or -not [bool]$liveRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveRuntime) -or ([string]$liveRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $expected){return & $deny 'recovery-aware-finalization-live-runtime-no-longer-exact-staged-tree'}}
        $liveGit=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath;$oldGit=Get-CustomAppAtomicGitSnapshotV010 -LivePath $oldLive
        if([bool]$liveGit.present -ne [bool]$oldGit.present){return & $deny 'recovery-aware-finalization-git-presence-drift'}
        if([bool]$liveGit.present){if(([string]$liveGit.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$oldGit.tree_sha256).Trim().ToLowerInvariant() -or [int]$liveGit.file_count -ne [int]$oldGit.file_count -or [int64]$liveGit.total_bytes -ne [int64]$oldGit.total_bytes){return & $deny 'recovery-aware-finalization-git-tree-drift'};if(-not $RecoveryAwareAtomicResult.PSObject.Properties['preserved_git_tree_sha256'] -or ([string]$RecoveryAwareAtomicResult.preserved_git_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$liveGit.tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-atomic-preserved-git-mismatch'}}
        elseif($RecoveryAwareAtomicResult.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$RecoveryAwareAtomicResult.preserved_git_tree_sha256)){return & $deny 'recovery-aware-finalization-atomic-reported-git-when-none-exists'}
        $persistenceBackup=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$RecoveryAwarePreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$RecoveryAwarePreparedResult.persistence_fingerprint)
        if(-not [bool]$persistenceBackup.ok){return & $deny ('recovery-aware-finalization-persistence-backup-invalid:'+[string]$persistenceBackup.reason)}
        $persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if(([string]$persistence.fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreparedResult.persistence_fingerprint).Trim().ToLowerInvariant() -or ([string]$persistence.fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareAtomicResult.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-protected-persistence-drift-before-cleanup'}
    }catch{return & $deny ('recovery-aware-finalization-precondition-read-failed:'+[string]$_.Exception.Message)}

    $consumptionBefore=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if(-not [bool]$consumptionBefore.ok){return & $deny ('recovery-aware-finalization-pre-cleanup-consumption-denied:'+[string]$consumptionBefore.reason)}
    try{Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationValidationHookV010 -Checkpoint 'before-cleanup' -Context ([pscustomobject]@{live_path=$livePath;transaction_root=$transactionRoot;old_live_path=$oldLive;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot;consumption_store=$ConsumptionStoreDirectory})}catch{return & $deny ('recovery-aware-finalization-before-cleanup-hook-failed:'+[string]$_.Exception.Message)}

    $cleanup=Remove-CustomAppProductionRecoveryAwarePermitAtomicTransactionV010 -TransactionRoot $transactionRoot -LivePath $livePath
    $deleted=(-not (Test-Path -LiteralPath $transactionRoot))
    if($null -eq $cleanup -or -not [bool]$cleanup.ok -or -not $deleted){return & $deny ('recovery-aware-finalization-transaction-cleanup-denied:'+[string]$cleanup.reason) $true $deleted $deleted}
    try{Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationValidationHookV010 -Checkpoint 'after-cleanup' -Context ([pscustomobject]@{live_path=$livePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot;consumption_store=$ConsumptionStoreDirectory})}catch{return & $deny ('recovery-aware-finalization-after-cleanup-hook-failed:'+[string]$_.Exception.Message) $true $true $true}

    try{
        $liveAfter=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath
        if(-not [bool]$liveAfter.safe -or -not [bool]$liveAfter.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveAfter) -or ([string]$liveAfter.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$liveRuntime.tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-post-cleanup-live-runtime-drift' $true $true $true}
        $gitAfter=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath
        if([bool]$gitAfter.present -ne [bool]$liveGit.present -or ([bool]$gitAfter.present -and (([string]$gitAfter.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$liveGit.tree_sha256).Trim().ToLowerInvariant() -or [int]$gitAfter.file_count -ne [int]$liveGit.file_count -or [int64]$gitAfter.total_bytes -ne [int64]$liveGit.total_bytes))){return & $deny 'recovery-aware-finalization-post-cleanup-git-drift' $true $true $true}
        $persistenceAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if(([string]$persistenceAfter.fingerprint).Trim().ToLowerInvariant() -cne ([string]$persistence.fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-finalization-post-cleanup-protected-persistence-drift' $true $true $true}
        if(-not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.stage_workspace_path) -PathType Container) -or -not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.stage_path) -PathType Container) -or -not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.app_backup_path) -PathType Container) -or -not (Test-Path -LiteralPath ([string]$RecoveryAwarePreparedResult.persistence_backup_path) -PathType Container)){return & $deny 'recovery-aware-finalization-post-cleanup-preserved-evidence-missing' $true $true $true}
        $backupAfter=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$RecoveryAwarePreparedResult.app_backup_path)
        if(([string]$backupAfter.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$backupSnapshot.tree_sha256).Trim().ToLowerInvariant() -or [int]$backupAfter.file_count -ne [int]$backupSnapshot.file_count -or [int64]$backupAfter.total_bytes -ne [int64]$backupSnapshot.total_bytes){return & $deny 'recovery-aware-finalization-post-cleanup-app-backup-drift' $true $true $true}
        $persistenceBackupAfter=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$RecoveryAwarePreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$RecoveryAwarePreparedResult.persistence_fingerprint)
        if(-not [bool]$persistenceBackupAfter.ok){return & $deny ('recovery-aware-finalization-post-cleanup-persistence-backup-drift:'+[string]$persistenceBackupAfter.reason) $true $true $true}
    }catch{return & $deny ('recovery-aware-finalization-post-cleanup-read-failed:'+[string]$_.Exception.Message) $true $true $true}

    $consumptionAfter=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if(-not [bool]$consumptionAfter.ok){return & $deny ('recovery-aware-finalization-post-cleanup-consumption-denied:'+[string]$consumptionAfter.reason) $true $true $true}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationSchema;managed_by=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationManagedBy;qualified_recovery_aware_atomic_head=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicHead;qualified_recovery_aware_atomic_core_blob=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedAtomicCoreBlob;qualified_generic_finalization_head=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationHead;qualified_generic_finalization_core_blob=$CustomAppProductionRecoveryAwarePermitTransactionFinalizationQualifiedGenericFinalizationCoreBlob;status='recovery-aware-transaction-workspace-finalized-live-persistence-consumption-reverified'
        name=$Name;source_identity=([string]$RecoveryAwareAtomicResult.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$RecoveryAwareAtomicResult.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$RecoveryAwareAtomicResult.github_repo_id;surface_kind=([string]$RecoveryAwareAtomicResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareAtomicResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareAtomicResult.binding_fingerprint).Trim().ToLowerInvariant()
        consumption_id=([string]$RecoveryAwareAtomicResult.consumption_id).Trim().ToLowerInvariant();historical_consumption_envelope_sha256=([string]$consumptionAfter.historical_envelope_sha256).Trim().ToLowerInvariant();current_consumption_envelope_sha256=([string]$consumptionAfter.current_envelope_sha256).Trim().ToLowerInvariant();current_consumption_revision=[int64]$consumptionAfter.current_revision
        recovery_atomic_result_fingerprint=([string]$RecoveryAwareAtomicResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        live_path=$livePath;transaction_root=$transactionRoot;old_live_tree_sha256=([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant();live_runtime_tree_sha256=([string]$liveAfter.tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if([bool]$gitAfter.present){([string]$gitAfter.tree_sha256).Trim().ToLowerInvariant()}else{$null});persistence_fingerprint=([string]$persistenceAfter.fingerprint).Trim().ToLowerInvariant();finalized_at=$Now.ToUniversalTime().ToString('o')
        stage_workspace_path=[string]$RecoveryAwarePreparedResult.stage_workspace_path;app_backup_path=[string]$RecoveryAwarePreparedResult.app_backup_path;persistence_backup_path=[string]$RecoveryAwarePreparedResult.persistence_backup_path;transaction_workspace_deleted=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;historical_consumption_reverified_before_cleanup=$true;historical_consumption_reverified_after_cleanup=$true;same_app_newer_consumption_absent=$true
        requires_spicetify_apply_phase=$true;requires_fresh_post_swap_apply_admission=$true;requires_recovery_if_post_cleanup_validation_fails=$true;result_is_authority=$false;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationSha256V010 (Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultMaterialV010 -Result $result)
    return [pscustomobject]@{ok=$true;reason='recovery-aware-transaction-workspace-finalized-live-persistence-consumption-reverified';result=$result;cleanup_attempted=$true;transaction_workspace_deleted=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;historical_consumption_reverified_before_cleanup=$true;historical_consumption_reverified_after_cleanup=$true;same_app_newer_consumption_absent=$true;requires_spicetify_apply_phase=$true;requires_fresh_post_swap_apply_admission=$true;requires_recovery_if_post_cleanup_validation_fails=$true;result_is_authority=$false;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}