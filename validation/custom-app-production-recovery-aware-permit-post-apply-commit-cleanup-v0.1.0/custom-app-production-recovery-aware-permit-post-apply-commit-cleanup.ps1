$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupSchema = 1
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupManagedBy = 'custom-app-production-recovery-aware-permit-post-apply-commit-cleanup-v1'
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyHead = 'ca48e2e97002a09774b81664345f50ea8aed3506'
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyCoreBlob = 'cc42e15cc891d233c59c934a5928ff14371c3f80'
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericHead = '67458cbb96b5d1ed92e26c2b81debd6894044749'
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericCoreBlob = '3b14280d727287252f71611e4424d78e5705c2f1'
$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericReceiptBlob = '31da8fa6253679f22edc07a6b5c00a47eb26c64d'

function Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 {
    param([AllowNull()]$Value,[string]$NullReason='null',[string]$MissingReason='reason-missing')
    if($null-eq$Value){return $NullReason}
    if($Value.PSObject.Properties['reason']){return [string]$Value.reason}
    return $MissingReason
}

function New-CustomAppProductionRecoveryAwarePermitPostApplyCleanupDeniedV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [AllowNull()]$GenericResult=$null,
        [bool]$CleanupAttempted=$false,
        [string]$StageStatus='not-attempted',
        [string]$AppStatus='not-attempted',
        [string]$PersistenceStatus='not-attempted',
        [AllowNull()]$PostConsumption=$null
    )
    return [pscustomobject]@{
        ok=$false;reason=$Reason;generic_result=$GenericResult;cleanup_attempted=$CleanupAttempted
        stage_cleanup_status=$StageStatus;app_backup_cleanup_status=$AppStatus;persistence_backup_cleanup_status=$PersistenceStatus
        partial_cleanup_possible=$CleanupAttempted;requires_idempotent_cleanup_resume=$CleanupAttempted;post_consumption=$PostConsumption
        rollback_attempted=$false;spicetify_apply_executed=$false;session_key_persisted=$false;session_key_exposed=$false
        result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericApplyResultV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareApplyResult,
        [Parameter(Mandatory=$true)]$GenericFinalizationResult,
        [Parameter(Mandatory=$true)]$GenericPreparedResult,
        [Parameter(Mandatory=$true)]$GenericStageResult
    )
    $r=[pscustomobject]@{
        schema=$CustomAppProductionSpicetifyApplyExecutorSchema;managed_by=$CustomAppProductionSpicetifyApplyExecutorManagedBy;qualified_admission_head=$CustomAppProductionSpicetifyApplyExecutorQualifiedAdmissionHead
        status='spicetify-apply-verified-awaiting-commit-cleanup';reason='exact-spicetify-apply-succeeded-and-post-state-verified'
        name=[string]$RecoveryAwareApplyResult.name;consumption_id=([string]$RecoveryAwareApplyResult.consumption_id).Trim().ToLowerInvariant()
        finalization_fingerprint=([string]$GenericFinalizationResult.finalization_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$GenericPreparedResult.preparation_fingerprint).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$GenericStageResult.result_fingerprint).Trim().ToLowerInvariant();apply_admission_fingerprint=([string]$RecoveryAwareApplyResult.generic_apply_admission_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$RecoveryAwareApplyResult.live_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$RecoveryAwareApplyResult.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareApplyResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareApplyResult.binding_fingerprint).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($RecoveryAwareApplyResult.PSObject.Properties['preserved_git_tree_sha256']){[string]$RecoveryAwareApplyResult.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$RecoveryAwareApplyResult.persistence_fingerprint).Trim().ToLowerInvariant()
        spicetify_executable_sha256=([string]$RecoveryAwareApplyResult.spicetify_executable_sha256).Trim().ToLowerInvariant();primary_exit_code=[int]$RecoveryAwareApplyResult.primary_exit_code;primary_timed_out=[bool]$RecoveryAwareApplyResult.primary_timed_out;apply_started_at=[string]$RecoveryAwareApplyResult.apply_started_at;apply_finished_at=[string]$RecoveryAwareApplyResult.apply_finished_at
        spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false;requires_post_apply_commit_cleanup=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true
        result_fingerprint=([string]$RecoveryAwareApplyResult.generic_apply_result_fingerprint).Trim().ToLowerInvariant();result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    return $r
}

function Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupLineageV010 {
    param(
        [Parameter(Mandatory=$true)]$ApplyResult,[Parameter(Mandatory=$true)]$FinalizationResult,[Parameter(Mandatory=$true)]$AtomicResult,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)][string]$Name
    )
    $checks=@(
        @((Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 -Result $ApplyResult),'apply'),
        @((Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultV010 -Result $FinalizationResult),'finalization'),
        @((Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $AtomicResult),'atomic'),
        @((Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $PreparedResult),'prepared'),
        @((Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $StageResult),'stage')
    )
    foreach($entry in $checks){$check=$entry[0];$label=[string]$entry[1];if($null-eq$check){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-'+$label+'-result-invalid:null')}};if(-not[bool]$check.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-'+$label+'-result-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $check))}}}
    $continuity=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyContinuityV010 -FinalizationResult $FinalizationResult -AtomicResult $AtomicResult -PreparedResult $PreparedResult -StageResult $StageResult -Name $Name
    if($null-eq$continuity){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-upstream-continuity-invalid:null'}}
    if(-not[bool]$continuity.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-upstream-continuity-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $continuity))}}
    $pairs=@(
        @('recovery_finalization_result_fingerprint',[string]$ApplyResult.recovery_finalization_result_fingerprint,[string]$FinalizationResult.result_fingerprint),
        @('recovery_atomic_result_fingerprint',[string]$ApplyResult.recovery_atomic_result_fingerprint,[string]$AtomicResult.result_fingerprint),
        @('recovery_pre_apply_result_fingerprint',[string]$ApplyResult.recovery_pre_apply_result_fingerprint,[string]$PreparedResult.result_fingerprint),
        @('recovery_stage_result_fingerprint',[string]$ApplyResult.recovery_stage_result_fingerprint,[string]$StageResult.result_fingerprint),
        @('name',[string]$ApplyResult.name,[string]$Name),
        @('source_identity',[string]$ApplyResult.source_identity,[string]$FinalizationResult.source_identity),
        @('transaction_id',[string]$ApplyResult.transaction_id,[string]$FinalizationResult.transaction_id),
        @('surface_kind',[string]$ApplyResult.surface_kind,[string]$FinalizationResult.surface_kind),
        @('remote_commit_sha',[string]$ApplyResult.remote_commit_sha,[string]$FinalizationResult.remote_commit_sha),
        @('binding_fingerprint',[string]$ApplyResult.binding_fingerprint,[string]$FinalizationResult.binding_fingerprint),
        @('consumption_id',[string]$ApplyResult.consumption_id,[string]$FinalizationResult.consumption_id),
        @('historical_consumption_envelope_sha256',[string]$ApplyResult.historical_consumption_envelope_sha256,[string]$FinalizationResult.historical_consumption_envelope_sha256)
    )
    foreach($p in $pairs){if(([string]$p[1]).Trim().ToLowerInvariant()-cne([string]$p[2]).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-apply-continuity-mismatch-'+[string]$p[0])}}}
    try{if([int64]$ApplyResult.github_repo_id-ne[int64]$FinalizationResult.github_repo_id -or [int64]$ApplyResult.current_consumption_revision-lt[int64]$FinalizationResult.current_consumption_revision){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-apply-repo-or-consumption-revision-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-apply-repo-or-consumption-revision-invalid'}}

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $StageResult
    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $PreparedResult
    $genericFinal=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 -RecoveryAwareFinalizationResult $FinalizationResult -RecoveryAwareAtomicResult $AtomicResult -GenericPreparedResult $genericPrepared -GenericStageResult $genericStage
    $genericApply=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericApplyResultV010 -RecoveryAwareApplyResult $ApplyResult -GenericFinalizationResult $genericFinal -GenericPreparedResult $genericPrepared -GenericStageResult $genericStage
    $gs=Test-CustomAppProductionPostApplyStageReceiptV010 -Result $genericStage;if($null-eq$gs){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-generic-stage-invalid:null'}};if(-not[bool]$gs.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-generic-stage-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $gs))}}
    $gp=Test-CustomAppProductionPostApplyPreparedReceiptV010 -Result $genericPrepared;if($null-eq$gp){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-generic-prepared-invalid:null'}};if(-not[bool]$gp.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-generic-prepared-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $gp))}}
    $gf=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $genericFinal;if($null-eq$gf){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-generic-finalization-invalid:null'}};if(-not[bool]$gf.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-generic-finalization-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $gf))}}
    $ga=Test-CustomAppProductionSpicetifyApplyResultV010 -Result $genericApply;if($null-eq$ga){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-generic-apply-invalid:null'}};if(-not[bool]$ga.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-generic-apply-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $ga))}}
    if(([string]$genericApply.result_fingerprint).Trim().ToLowerInvariant()-cne([string]$ApplyResult.generic_apply_result_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-generic-apply-fingerprint-continuity-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-cleanup-lineage-and-generic-bridges-valid';generic_stage=$genericStage;generic_prepared=$genericPrepared;generic_finalization=$genericFinal;generic_apply=$genericApply}
}

function Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_recovery_aware_apply_head,[string]$Result.qualified_recovery_aware_apply_core_blob,[string]$Result.qualified_generic_cleanup_head,[string]$Result.qualified_generic_cleanup_core_blob,[string]$Result.qualified_generic_cleanup_receipt_blob,[string]$Result.status,[string]$Result.reason,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,[string]$Result.binding_fingerprint,[string]$Result.consumption_id,
        [string]$Result.historical_consumption_envelope_sha256,[string]$Result.current_consumption_envelope_sha256,[string]$Result.current_consumption_revision,
        [string]$Result.recovery_apply_result_fingerprint,[string]$Result.recovery_finalization_result_fingerprint,[string]$Result.recovery_atomic_result_fingerprint,[string]$Result.recovery_pre_apply_result_fingerprint,[string]$Result.recovery_stage_result_fingerprint,
        [string]$Result.generic_apply_result_fingerprint,[string]$Result.generic_finalization_fingerprint,[string]$Result.generic_preparation_fingerprint,[string]$Result.generic_stage_result_fingerprint,[string]$Result.generic_cleanup_fingerprint,
        [string]$Result.live_tree_sha256,[string]$Result.remote_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.stage_cleanup_status,[string]$Result.app_backup_cleanup_status,[string]$Result.persistence_backup_cleanup_status,[string]$Result.cleanup_completed_at,
        [string]$Result.cleanup_attempted,[string]$Result.update_commit_complete,[string]$Result.all_transaction_artifacts_clean,[string]$Result.requires_new_permit_for_future_update,[string]$Result.rollback_attempted,[string]$Result.spicetify_apply_executed,
        [string]$Result.session_key_persisted,[string]$Result.session_key_exposed,[string]$Result.result_is_authority,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-null'}}
    foreach($f in @('schema','managed_by','qualified_recovery_aware_apply_head','qualified_recovery_aware_apply_core_blob','qualified_generic_cleanup_head','qualified_generic_cleanup_core_blob','qualified_generic_cleanup_receipt_blob','status','reason','name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','current_consumption_revision','recovery_apply_result_fingerprint','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_apply_result_fingerprint','generic_finalization_fingerprint','generic_preparation_fingerprint','generic_stage_result_fingerprint','generic_cleanup_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','stage_cleanup_status','app_backup_cleanup_status','persistence_backup_cleanup_status','cleanup_completed_at','cleanup_attempted','update_commit_complete','all_transaction_artifacts_clean','requires_new_permit_for_future_update','rollback_attempted','spicetify_apply_executed','session_key_persisted','session_key_exposed','result_fingerprint','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-result-required-field-missing-'+$f)}}}
    if([int]$Result.schema-ne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupSchema -or [string]$Result.managed_by-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupManagedBy -or [string]$Result.qualified_recovery_aware_apply_head-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyHead -or [string]$Result.qualified_recovery_aware_apply_core_blob-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyCoreBlob -or [string]$Result.qualified_generic_cleanup_head-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericHead -or [string]$Result.qualified_generic_cleanup_core_blob-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericCoreBlob -or [string]$Result.qualified_generic_cleanup_receipt_blob-cne$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericReceiptBlob -or [string]$Result.status-cne'recovery-aware-post-apply-transaction-committed-artifacts-clean' -or [string]$Result.reason-cne'generic-bounded-cleanup-succeeded-and-recovery-ledger-reverified'){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-owner-lineage-status-invalid'}}
    foreach($f in @('transaction_id','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','recovery_apply_result_fingerprint','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_apply_result_fingerprint','generic_finalization_fingerprint','generic_preparation_fingerprint','generic_stage_result_fingerprint','generic_cleanup_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not(Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010(([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-invalid-remote-commit'}}
    try{if([int64]$Result.github_repo_id-le0 -or [int64]$Result.current_consumption_revision-lt1){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-numeric-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-numeric-invalid'}}
    foreach($f in @('cleanup_attempted','update_commit_complete','all_transaction_artifacts_clean','requires_new_permit_for_future_update')){if(-not[bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-result-required-flag-false-'+$f)}}}
    foreach($f in @('rollback_attempted','spicetify_apply_executed','session_key_persisted','session_key_exposed','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-result-authority-or-execution-escaped-'+$f)}}}
    foreach($f in @('stage_cleanup_status','app_backup_cleanup_status','persistence_backup_cleanup_status')){if([string]$Result.$f-notin@('deleted-now','already-absent')){return [pscustomobject]@{ok=$false;reason=('recovery-aware-cleanup-result-invalid-'+$f)}}}
    $at=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Result.cleanup_completed_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010 (Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-cleanup-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-cleanup-result-valid-zero-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareApplyResult,[Parameter(Mandatory=$true)]$RecoveryAwareFinalizationResult,[Parameter(Mandatory=$true)]$RecoveryAwareAtomicResult,[Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,$Generic=$null,[bool]$Attempted=$false,[string]$Stage='not-attempted',[string]$App='not-attempted',[string]$Persistence='not-attempted',$Post=$null) New-CustomAppProductionRecoveryAwarePermitPostApplyCleanupDeniedV010 -Reason $Reason -GenericResult $Generic -CleanupAttempted $Attempted -StageStatus $Stage -AppStatus $App -PersistenceStatus $Persistence -PostConsumption $Post}
    if($SessionKey.Length-lt32){return & $deny 'recovery-aware-cleanup-session-key-too-short'}
    $lineage=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupLineageV010 -ApplyResult $RecoveryAwareApplyResult -FinalizationResult $RecoveryAwareFinalizationResult -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageResult $RecoveryAwareStageExecutorResult -Name $Name
    if($null-eq$lineage){return & $deny 'recovery-aware-cleanup-lineage-denied:null'}
    if(-not[bool]$lineage.ok){return & $deny ('recovery-aware-cleanup-lineage-denied:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $lineage))}
    $pre=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if($null-eq$pre){return & $deny 'recovery-aware-cleanup-pre-consumption-denied:null'}
    if(-not[bool]$pre.ok){return & $deny ('recovery-aware-cleanup-pre-consumption-denied:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $pre))}
    if(([string]$pre.historical_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$RecoveryAwareApplyResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-cleanup-pre-historical-envelope-drift'}
    try{$preRevision=[int64]$pre.current_revision;$applyRevision=[int64]$RecoveryAwareApplyResult.current_consumption_revision}catch{return & $deny 'recovery-aware-cleanup-pre-current-revision-invalid'}
    if($preRevision-lt$applyRevision){return & $deny 'recovery-aware-cleanup-pre-current-revision-regressed'}
    if($preRevision-eq$applyRevision -and ([string]$pre.current_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$RecoveryAwareApplyResult.current_consumption_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-cleanup-pre-current-envelope-drift-at-same-revision'}

    $generic=Invoke-CustomAppProductionPostApplyCommitCleanupV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareApplyResult.consumption_id) -Permit $Permit -ApplyResult $lineage.generic_apply -FinalizationResult $lineage.generic_finalization -PreparedResult $lineage.generic_prepared -StageExecutorResult $lineage.generic_stage -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if($null-eq$generic){return & $deny 'recovery-aware-cleanup-generic-cleanup-null'}
    if(-not[bool]$generic.ok){
        $attempted=[bool]$generic.cleanup_attempted;$stage=$(if($generic.PSObject.Properties['stage_cleanup_status']){[string]$generic.stage_cleanup_status}else{'not-attempted'});$app=$(if($generic.PSObject.Properties['app_backup_cleanup_status']){[string]$generic.app_backup_cleanup_status}else{'not-attempted'});$persist=$(if($generic.PSObject.Properties['persistence_backup_cleanup_status']){[string]$generic.persistence_backup_cleanup_status}else{'not-attempted'})
        $post=$null;if($attempted){$post=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name}
        return & $deny ('recovery-aware-cleanup-generic-cleanup-denied:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $generic)) $generic $attempted $stage $app $persist $post
    }
    $gc=Test-CustomAppProductionPostApplyCommitCleanupResultV010 -Result $generic.result
    if($null-eq$gc){return & $deny 'recovery-aware-cleanup-generic-result-invalid:null' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status)}
    if(-not[bool]$gc.ok){return & $deny ('recovery-aware-cleanup-generic-result-invalid:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $gc)) $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status)}
    $post=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if($null-eq$post){return & $deny 'recovery-aware-cleanup-post-consumption-denied:null' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status)}
    if(-not[bool]$post.ok){return & $deny ('recovery-aware-cleanup-post-consumption-denied:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $post)) $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    if(([string]$post.historical_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$pre.historical_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-cleanup-post-historical-envelope-drift' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    try{$postRevision=[int64]$post.current_revision}catch{return & $deny 'recovery-aware-cleanup-post-current-revision-invalid' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    if($postRevision-lt$preRevision){return & $deny 'recovery-aware-cleanup-post-current-revision-regressed' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    if($postRevision-eq$preRevision -and ([string]$post.current_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$pre.current_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-cleanup-post-current-envelope-drift-at-same-revision' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupSchema;managed_by=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupManagedBy;qualified_recovery_aware_apply_head=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyHead;qualified_recovery_aware_apply_core_blob=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedApplyCoreBlob;qualified_generic_cleanup_head=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericHead;qualified_generic_cleanup_core_blob=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericCoreBlob;qualified_generic_cleanup_receipt_blob=$CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupQualifiedGenericReceiptBlob
        status='recovery-aware-post-apply-transaction-committed-artifacts-clean';reason='generic-bounded-cleanup-succeeded-and-recovery-ledger-reverified'
        name=$Name;source_identity=([string]$RecoveryAwareApplyResult.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$RecoveryAwareApplyResult.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$RecoveryAwareApplyResult.github_repo_id;surface_kind=([string]$RecoveryAwareApplyResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareApplyResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareApplyResult.binding_fingerprint).Trim().ToLowerInvariant();consumption_id=([string]$RecoveryAwareApplyResult.consumption_id).Trim().ToLowerInvariant()
        historical_consumption_envelope_sha256=([string]$post.historical_envelope_sha256).Trim().ToLowerInvariant();current_consumption_envelope_sha256=([string]$post.current_envelope_sha256).Trim().ToLowerInvariant();current_consumption_revision=[int64]$post.current_revision
        recovery_apply_result_fingerprint=([string]$RecoveryAwareApplyResult.result_fingerprint).Trim().ToLowerInvariant();recovery_finalization_result_fingerprint=([string]$RecoveryAwareFinalizationResult.result_fingerprint).Trim().ToLowerInvariant();recovery_atomic_result_fingerprint=([string]$RecoveryAwareAtomicResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        generic_apply_result_fingerprint=([string]$lineage.generic_apply.result_fingerprint).Trim().ToLowerInvariant();generic_finalization_fingerprint=([string]$lineage.generic_finalization.finalization_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$lineage.generic_prepared.preparation_fingerprint).Trim().ToLowerInvariant();generic_stage_result_fingerprint=([string]$lineage.generic_stage.result_fingerprint).Trim().ToLowerInvariant();generic_cleanup_fingerprint=([string]$generic.result.cleanup_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$RecoveryAwareApplyResult.live_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$RecoveryAwareApplyResult.remote_tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($RecoveryAwareApplyResult.PSObject.Properties['preserved_git_tree_sha256']){[string]$RecoveryAwareApplyResult.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$RecoveryAwareApplyResult.persistence_fingerprint).Trim().ToLowerInvariant()
        stage_cleanup_status=[string]$generic.result.stage_cleanup_status;app_backup_cleanup_status=[string]$generic.result.app_backup_cleanup_status;persistence_backup_cleanup_status=[string]$generic.result.persistence_backup_cleanup_status;cleanup_completed_at=[string]$generic.result.cleanup_completed_at
        cleanup_attempted=$true;update_commit_complete=$true;all_transaction_artifacts_clean=$true;requires_new_permit_for_future_update=$true;rollback_attempted=$false;spicetify_apply_executed=$false
        session_key_persisted=$false;session_key_exposed=$false;result_fingerprint=$null;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSha256V010 (Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 -Result $result
    if($null-eq$check){return & $deny 'recovery-aware-cleanup-result-self-validation-failed:null' $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    if(-not[bool]$check.ok){return & $deny ('recovery-aware-cleanup-result-self-validation-failed:'+(Get-CustomAppProductionRecoveryAwarePermitPostApplyCleanupSafeReasonV010 $check)) $generic $true ([string]$generic.result.stage_cleanup_status) ([string]$generic.result.app_backup_cleanup_status) ([string]$generic.result.persistence_backup_cleanup_status) $post}
    return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;cleanup_attempted=$true;partial_cleanup_possible=$false;requires_idempotent_cleanup_resume=$false;rollback_attempted=$false;spicetify_apply_executed=$false;requires_new_permit_for_future_update=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
