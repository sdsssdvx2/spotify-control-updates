$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema = 1
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy = 'custom-app-production-recovery-aware-permit-atomic-live-swap-v1'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead = '43f9a433354f56e2db19f4edfa1ffa8f4a245088'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob = 'eaad8a5f161f831bbbada1c1c0957a3dfc80edaa'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead = '574fe182168271fa3497d58e269e9af1f60d9033'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob = 'e91fa6a125f77352907c1119f6d9f47be9682550'

function Get-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitAtomicDeniedV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [bool]$RollbackAttempted=$false,
        [bool]$RollbackOk=$false,
        [AllowNull()]$RollbackResult=$null
    )
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$RollbackResult
        recovery_revalidated_immediately_before_atomic=$false;live_code_swap_performed=$false;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        result_is_authority=$false;requires_exact_rollback_on_failure=$true;requires_transaction_finalization=$false;requires_spicetify_apply_phase=$true
        apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitGenericAtomicSuccessV010 {
    param([AllowNull()]$AtomicResult,[Parameter(Mandatory=$true)]$GenericPrepared,[Parameter(Mandatory=$true)]$GenericStage,[Parameter(Mandatory=$true)][string]$Name)
    if($null -eq $AtomicResult){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-null'}}
    foreach($f in @('ok','reason','schema','managed_by','qualified_pre_apply_head','name','live_path','transaction_root','old_live_path','fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint','rollback_attempted','rollback_ok','live_code_swap_performed','requires_transaction_workspace_cleanup','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){if(-not $AtomicResult.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-field-missing-'+$f)}}}
    if(-not [bool]$AtomicResult.ok -or [string]$AtomicResult.reason -cne 'atomic-live-code-swap-verified-no-spicetify-apply' -or [int]$AtomicResult.schema -ne $CustomAppProductionAtomicLiveSwapSchema -or [string]$AtomicResult.managed_by -cne $CustomAppProductionAtomicLiveSwapManagedBy -or [string]$AtomicResult.qualified_pre_apply_head -cne $CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-owner-schema-status-invalid'}}
    if(([string]$AtomicResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-name-mismatch'}}
    if([bool]$AtomicResult.rollback_attempted -or [bool]$AtomicResult.rollback_ok -or -not [bool]$AtomicResult.live_code_swap_performed -or -not [bool]$AtomicResult.requires_transaction_workspace_cleanup -or -not [bool]$AtomicResult.requires_spicetify_apply_phase){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-lifecycle-invalid'}}
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){if([bool]$AtomicResult.$f){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-authority-escaped-'+$f)}}}
    foreach($f in @('fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (([string]$AtomicResult.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-invalid-'+$f)}}}
    if($AtomicResult.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$AtomicResult.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (([string]$AtomicResult.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-invalid-preserved-git-tree'}}
    if(([string]$AtomicResult.post_runtime_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$GenericStage.remote_tree_sha256).Trim().ToLowerInvariant() -or ([string]$AtomicResult.post_runtime_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$GenericPrepared.stage_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-post-tree-continuity-mismatch'}}
    if(([string]$AtomicResult.persistence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$GenericPrepared.persistence_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-persistence-continuity-mismatch'}}
    foreach($f in @('live_path','transaction_root','old_live_path')){if([string]::IsNullOrWhiteSpace([string]$AtomicResult.$f)){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-empty-'+$f)}}}
    return [pscustomobject]@{ok=$true;reason='generic-atomic-success-valid-zero-apply-authority'}
}

function Get-CustomAppProductionRecoveryAwarePermitAtomicResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_recovery_aware_pre_apply_head,[string]$Result.qualified_recovery_aware_pre_apply_core_blob,
        [string]$Result.qualified_generic_atomic_head,[string]$Result.qualified_generic_atomic_core_blob,[string]$Result.status,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,
        [string]$Result.consumption_id,[string]$Result.consumption_persistence_fingerprint,[string]$Result.historical_consumption_envelope_sha256,
        [string]$Result.recovery_pre_atomic_admission_fingerprint,[string]$Result.recovery_pre_apply_result_fingerprint,[string]$Result.recovery_stage_result_fingerprint,
        [string]$Result.generic_stage_result_fingerprint,[string]$Result.generic_preparation_fingerprint,[string]$Result.generic_pre_apply_admission_fingerprint,[string]$Result.generic_atomic_fresh_admission_fingerprint,
        [string]$Result.old_live_tree_sha256,[string]$Result.post_runtime_tree_sha256,[string]$Result.binding_fingerprint,[string]$Result.live_path,[string]$Result.transaction_root,[string]$Result.old_live_path,
        [string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.swapped_at,
        [string]$Result.recovery_revalidated_immediately_before_atomic,[string]$Result.live_code_swap_performed,[string]$Result.rollback_attempted,[string]$Result.rollback_ok,
        [string]$Result.session_key_accepted,[string]$Result.session_key_persisted,[string]$Result.session_key_exposed,[string]$Result.result_is_authority,
        [string]$Result.requires_transaction_finalization,[string]$Result.requires_spicetify_apply_phase,[string]$Result.requires_exact_rollback_on_failure,
        [string]$Result.apply_execution_authorized,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_recovery_aware_pre_apply_head','qualified_recovery_aware_pre_apply_core_blob','qualified_generic_atomic_head','qualified_generic_atomic_core_blob','status',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256',
        'recovery_pre_atomic_admission_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint','generic_atomic_fresh_admission_fingerprint',
        'old_live_tree_sha256','post_runtime_tree_sha256','binding_fingerprint','live_path','transaction_root','old_live_path','persistence_fingerprint','swapped_at',
        'recovery_revalidated_immediately_before_atomic','live_code_swap_performed','rollback_attempted','rollback_ok','session_key_accepted','session_key_persisted','session_key_exposed','result_is_authority',
        'requires_transaction_finalization','requires_spicetify_apply_phase','requires_exact_rollback_on_failure','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint'
    )){if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-field-missing-'+$f)}}}
    if([int]$Result.schema -ne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema -or [string]$Result.managed_by -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy -or [string]$Result.status -cne 'recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply'){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-owner-schema-status-mismatch'}}
    if([string]$Result.qualified_recovery_aware_pre_apply_head -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead -or [string]$Result.qualified_recovery_aware_pre_apply_core_blob -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob -or [string]$Result.qualified_generic_atomic_head -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead -or [string]$Result.qualified_generic_atomic_core_blob -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','recovery_pre_atomic_admission_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint','generic_atomic_fresh_admission_fingerprint','old_live_tree_sha256','post_runtime_tree_sha256','binding_fingerprint','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-remote-commit-invalid'}}
    try{if([int64]$Result.github_repo_id -le 0){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-repo-id-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-repo-id-invalid'}}
    foreach($f in @('recovery_revalidated_immediately_before_atomic','live_code_swap_performed','session_key_accepted','requires_transaction_finalization','requires_spicetify_apply_phase','requires_exact_rollback_on_failure')){if(-not [bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-required-flag-false-'+$f)}}}
    foreach($f in @('rollback_attempted','rollback_ok','session_key_persisted','session_key_exposed','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-authority-or-failure-flag-true-'+$f)}}}
    $at=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Result.swapped_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-time-invalid'}}
    foreach($f in @('live_path','transaction_root','old_live_path','name','source_identity','surface_kind')){if([string]::IsNullOrWhiteSpace([string]$Result.$f)){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-empty-'+$f)}}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-atomic-result-valid-zero-apply-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,[Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$LifecycleStageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$RollbackResult=$null) New-CustomAppProductionRecoveryAwarePermitAtomicDeniedV010 -Reason $Reason -RollbackAttempted $RollbackAttempted -RollbackOk $RollbackOk -RollbackResult $RollbackResult}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-atomic-session-key-too-short'}
    $stageCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('recovery-aware-atomic-stage-result-invalid:'+[string]$stageCheck.reason)}
    $preparedCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreparedResult
    if(-not [bool]$preparedCheck.ok){return & $deny ('recovery-aware-atomic-prepared-result-invalid:'+[string]$preparedCheck.reason)}
    if(([string]$RecoveryAwareStageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant() -or ([string]$RecoveryAwarePreparedResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-name-mismatch'}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(([string]$RecoveryAwareStageExecutorResult.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$RecoveryAwarePreparedResult.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-aware-atomic-transaction-mismatch'}
    if(([string]$RecoveryAwarePreparedResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-stage-prepared-fingerprint-mismatch'}
    foreach($f in @('source_identity','github_repo_id','surface_kind','remote_commit_sha','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){if(([string]$RecoveryAwarePreparedResult.$f).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-atomic-stage-prepared-continuity-drift-'+$f)}}

    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$binding.ok){return & $deny ('recovery-aware-atomic-binding-denied:'+[string]$binding.reason)}
    foreach($pair in @(@('source_identity','source'),@('surface_kind','surface'),@('remote_commit_sha','commit_sha'),@('remote_tree_sha256','remote_tree_sha256'),@('binding_fingerprint','binding_fingerprint'))){if(([string]$RecoveryAwareStageExecutorResult.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$binding.($pair[1])).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-atomic-stage-binding-mismatch-'+$pair[0])}}
    try{if([int64]$RecoveryAwareStageExecutorResult.github_repo_id -ne [int64]$binding.repo_id){return & $deny 'recovery-aware-atomic-stage-binding-mismatch-github_repo_id'}}catch{return & $deny 'recovery-aware-atomic-stage-repo-id-invalid'}

    $freshLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshLive.ok){return & $deny ('recovery-aware-atomic-live-revalidation-denied:'+[string]$freshLive.reason)}
    if(([string]$freshLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-live-stage-local-tree-continuity-mismatch'}

    $recovery=Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $LifecycleStageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $freshLive.baseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -RecoveryStoreDirectory $RecoveryStoreDirectory -ConsumptionStoreDirectory $ConsumptionStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -ConsumptionPersistenceResult $ConsumptionPersistenceResult -Permit $Permit -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $recovery -or -not [bool]$recovery.ok -or -not [bool]$recovery.stage_acquisition_eligible -or $null -eq $recovery.receipt){return & $deny ('recovery-aware-atomic-pre-mutation-admission-denied:'+[string]$recovery.reason)}
    $recoveryCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $recovery.receipt -Now $Now
    if(-not [bool]$recoveryCheck.ok){return & $deny ('recovery-aware-atomic-pre-mutation-admission-invalid:'+[string]$recoveryCheck.reason)}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){if(([string]$RecoveryAwareStageExecutorResult.$f).Trim().ToLowerInvariant() -cne ([string]$recovery.receipt.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-atomic-pre-mutation-admission-continuity-drift-'+$f)}}
    if(([string]$RecoveryAwarePreparedResult.recovery_post_backup_admission_fingerprint).Trim().ToLowerInvariant() -eq ([string]$recovery.receipt.admission_fingerprint).Trim().ToLowerInvariant()){
        # Same evidence may legitimately produce the same deterministic receipt material; no authority is inferred from equality.
    }

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $RecoveryAwareStageExecutorResult
    $genericStageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $genericStage
    if(-not [bool]$genericStageCheck.ok){return & $deny ('recovery-aware-atomic-generic-stage-bridge-invalid:'+[string]$genericStageCheck.reason)}
    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreparedResult
    $genericPreparedCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $genericPrepared
    if(-not [bool]$genericPreparedCheck.ok){return & $deny ('recovery-aware-atomic-generic-prepared-bridge-invalid:'+[string]$genericPreparedCheck.reason)}

    $atomic=$null
    try{
        $atomic=Invoke-CustomAppProductionAtomicLiveSwapV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareStageExecutorResult.consumption_id) -StageExecutorResult $genericStage -PreparedResult $genericPrepared -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }catch{return & $deny ('recovery-aware-atomic-generic-atomic-threw:'+[string]$_.Exception.Message)}
    if($null -eq $atomic -or -not [bool]$atomic.ok){
        $ra=$false;$ro=$false;$rr=$null
        if($null -ne $atomic){if($atomic.PSObject.Properties['rollback_attempted']){$ra=[bool]$atomic.rollback_attempted};if($atomic.PSObject.Properties['rollback_ok']){$ro=[bool]$atomic.rollback_ok};if($atomic.PSObject.Properties['rollback_result']){$rr=$atomic.rollback_result}}
        return & $deny ('recovery-aware-atomic-generic-atomic-denied:'+[string]$atomic.reason) $ra $ro $rr
    }
    $atomicCheck=Test-CustomAppProductionRecoveryAwarePermitGenericAtomicSuccessV010 -AtomicResult $atomic -GenericPrepared $genericPrepared -GenericStage $genericStage -Name $Name
    if(-not [bool]$atomicCheck.ok){return & $deny ('recovery-aware-atomic-generic-atomic-result-invalid:'+[string]$atomicCheck.reason)}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema;managed_by=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy
        qualified_recovery_aware_pre_apply_head=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead;qualified_recovery_aware_pre_apply_core_blob=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob
        qualified_generic_atomic_head=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead;qualified_generic_atomic_core_blob=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob
        status='recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply'
        name=$Name;source_identity=([string]$RecoveryAwareStageExecutorResult.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$RecoveryAwareStageExecutorResult.github_repo_id;surface_kind=([string]$RecoveryAwareStageExecutorResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareStageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$RecoveryAwareStageExecutorResult.consumption_id).Trim().ToLowerInvariant();consumption_persistence_fingerprint=([string]$RecoveryAwareStageExecutorResult.consumption_persistence_fingerprint).Trim().ToLowerInvariant();historical_consumption_envelope_sha256=([string]$RecoveryAwareStageExecutorResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()
        recovery_pre_atomic_admission_fingerprint=([string]$recovery.receipt.admission_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        generic_stage_result_fingerprint=([string]$genericStage.result_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$genericPrepared.preparation_fingerprint).Trim().ToLowerInvariant();generic_pre_apply_admission_fingerprint=([string]$genericPrepared.pre_apply_admission_fingerprint).Trim().ToLowerInvariant();generic_atomic_fresh_admission_fingerprint=([string]$atomic.fresh_admission_fingerprint).Trim().ToLowerInvariant()
        old_live_tree_sha256=([string]$RecoveryAwarePreparedResult.app_backup_tree_sha256).Trim().ToLowerInvariant();post_runtime_tree_sha256=([string]$atomic.post_runtime_tree_sha256).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareStageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$atomic.live_path;transaction_root=[string]$atomic.transaction_root;old_live_path=[string]$atomic.old_live_path;preserved_git_tree_sha256=$(if($atomic.PSObject.Properties['preserved_git_tree_sha256']){[string]$atomic.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$atomic.persistence_fingerprint).Trim().ToLowerInvariant();swapped_at=$Now.ToUniversalTime().ToString('o')
        recovery_revalidated_immediately_before_atomic=$true;live_code_swap_performed=$true;rollback_attempted=$false;rollback_ok=$false;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;result_is_authority=$false
        requires_transaction_finalization=$true;requires_spicetify_apply_phase=$true;requires_exact_rollback_on_failure=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $result
    if(-not [bool]$check.ok){return & $deny ('recovery-aware-atomic-output-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-atomic-live-code-swap-verified-zero-apply-authority';result=$result;rollback_attempted=$false;rollback_ok=$false;rollback_result=$null
        recovery_revalidated_immediately_before_atomic=$true;live_code_swap_performed=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;result_is_authority=$false
        requires_exact_rollback_on_failure=$true;requires_transaction_finalization=$true;requires_spicetify_apply_phase=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
