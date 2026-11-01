$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSchema = 1
$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionManagedBy = 'custom-app-production-recovery-aware-permit-post-swap-apply-admission-v1'
$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationHead = '0c32a30cf61dc9f3e61725d30d5df1df9a73ef56'
$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationCoreBlob = '9c725e47d432addac24fe4a6cd59e37af393b6c7'
$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericHead = 'a4f6d4772afb895dd253a4c82a21643711ac0829'
$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericCoreBlob = '190382903e23d7abc59b525829c5ecd5c76f7ff1'

function Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;decision=$null;apply_eligible=$false;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        admission_is_authority=$false;requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true
        apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareFinalizationResult,
        [Parameter(Mandatory=$true)]$RecoveryAwareAtomicResult,
        [Parameter(Mandatory=$true)]$GenericPreparedResult,
        [Parameter(Mandatory=$true)]$GenericStageResult
    )
    $r=[pscustomobject]@{
        schema=$CustomAppProductionTransactionFinalizationSchema;managed_by=$CustomAppProductionTransactionFinalizationManagedBy;qualified_atomic_head=$CustomAppProductionTransactionFinalizationQualifiedAtomicHead;status='transaction-workspace-finalized-live-and-persistence-reverified'
        name=[string]$RecoveryAwareFinalizationResult.name;live_path=[string]$RecoveryAwareFinalizationResult.live_path;transaction_root=[string]$RecoveryAwareFinalizationResult.transaction_root
        consumption_id=([string]$RecoveryAwareFinalizationResult.consumption_id).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$GenericStageResult.result_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$GenericPreparedResult.preparation_fingerprint).Trim().ToLowerInvariant();atomic_fresh_admission_fingerprint=([string]$RecoveryAwareAtomicResult.recovery_pre_mutation_admission_fingerprint).Trim().ToLowerInvariant()
        old_live_tree_sha256=([string]$RecoveryAwareFinalizationResult.old_live_tree_sha256).Trim().ToLowerInvariant();live_runtime_tree_sha256=([string]$RecoveryAwareFinalizationResult.live_runtime_tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($RecoveryAwareFinalizationResult.PSObject.Properties['preserved_git_tree_sha256']){[string]$RecoveryAwareFinalizationResult.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$RecoveryAwareFinalizationResult.persistence_fingerprint).Trim().ToLowerInvariant();finalized_at=[string]$RecoveryAwareFinalizationResult.finalized_at
        stage_workspace_path=[string]$RecoveryAwareFinalizationResult.stage_workspace_path;app_backup_path=[string]$RecoveryAwareFinalizationResult.app_backup_path;persistence_backup_path=[string]$RecoveryAwareFinalizationResult.persistence_backup_path
        transaction_workspace_deleted=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;requires_spicetify_apply_phase=$true
        result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false;finalization_fingerprint=$null
    }
    $r.finalization_fingerprint=Get-CustomAppProductionTransactionFinalizationSha256V010 -Text (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $r)
    return $r
}

function Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyContinuityV010 {
    param(
        [Parameter(Mandatory=$true)]$FinalizationResult,[Parameter(Mandatory=$true)]$AtomicResult,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)][string]$Name
    )
    if(([string]$FinalizationResult.recovery_atomic_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$AtomicResult.result_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-finalization-atomic-fingerprint-mismatch'}}
    if(([string]$FinalizationResult.recovery_pre_apply_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$PreparedResult.result_fingerprint).Trim().ToLowerInvariant() -or ([string]$AtomicResult.recovery_pre_apply_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$PreparedResult.result_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-pre-apply-fingerprint-mismatch'}}
    if(([string]$FinalizationResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageResult.result_fingerprint).Trim().ToLowerInvariant() -or ([string]$AtomicResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageResult.result_fingerprint).Trim().ToLowerInvariant() -or ([string]$PreparedResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageResult.result_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-stage-fingerprint-mismatch'}}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','consumption_id','binding_fingerprint')){
        $a=([string]$FinalizationResult.$f).Trim().ToLowerInvariant();$b=([string]$AtomicResult.$f).Trim().ToLowerInvariant();$c=([string]$PreparedResult.$f).Trim().ToLowerInvariant();$d=([string]$StageResult.$f).Trim().ToLowerInvariant()
        if($a-cne$b -or $a-cne$c -or $a-cne$d){return [pscustomobject]@{ok=$false;reason=('recovery-aware-post-swap-identity-continuity-mismatch-'+$f)}}
    }
    if(([string]$FinalizationResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-name-mismatch'}}
    $historical=([string]$FinalizationResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()
    foreach($x in @(([string]$AtomicResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant(),([string]$PreparedResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant(),([string]$StageResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant())){if($historical-cne$x){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-historical-consumption-envelope-mismatch'}}}
    try{if([int64]$FinalizationResult.current_consumption_revision -lt [int64]$AtomicResult.current_consumption_revision){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-finalization-consumption-revision-regressed'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-consumption-revision-invalid'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-post-swap-receipt-continuity-valid'}
}

function Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @(
        [string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_recovery_aware_finalization_head,[string]$Decision.qualified_recovery_aware_finalization_core_blob,[string]$Decision.qualified_generic_post_swap_admission_head,[string]$Decision.qualified_generic_post_swap_admission_core_blob,[string]$Decision.reason,
        [string]$Decision.name,[string]$Decision.source_identity,[string]$Decision.transaction_id,[string]$Decision.github_repo_id,[string]$Decision.surface_kind,[string]$Decision.remote_commit_sha,[string]$Decision.binding_fingerprint,
        [string]$Decision.consumption_id,[string]$Decision.historical_consumption_envelope_sha256,[string]$Decision.current_consumption_envelope_sha256,[string]$Decision.current_consumption_revision,
        [string]$Decision.recovery_finalization_result_fingerprint,[string]$Decision.recovery_atomic_result_fingerprint,[string]$Decision.recovery_pre_apply_result_fingerprint,[string]$Decision.recovery_stage_result_fingerprint,
        [string]$Decision.generic_finalization_fingerprint,[string]$Decision.generic_preparation_fingerprint,[string]$Decision.generic_stage_result_fingerprint,[string]$Decision.generic_admission_fingerprint,
        [string]$Decision.live_tree_sha256,[string]$Decision.remote_tree_sha256,[string]$Decision.preserved_git_tree_sha256,[string]$Decision.persistence_fingerprint,[string]$Decision.evaluated_at,[string]$Decision.apply_eligibility_expires_at,
        [string]$Decision.apply_eligible,[string]$Decision.session_key_accepted,[string]$Decision.session_key_persisted,[string]$Decision.session_key_exposed,[string]$Decision.admission_is_authority,
        [string]$Decision.requires_immediate_rerun_by_apply_executor,[string]$Decision.requires_exact_spicetify_apply_executor,[string]$Decision.requires_exact_rollback_on_apply_failure,
        [string]$Decision.apply_execution_authorized,[string]$Decision.spicetify_apply_authorized,[string]$Decision.additional_mutation_authorized,[string]$Decision.live_destination_authorized,[string]$Decision.production_execution_authorized,[string]$Decision.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 {
    param([AllowNull()]$Decision)
    if($null-eq$Decision){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-null'}}
    foreach($f in @('schema','managed_by','qualified_recovery_aware_finalization_head','qualified_recovery_aware_finalization_core_blob','qualified_generic_post_swap_admission_head','qualified_generic_post_swap_admission_core_blob','reason','name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','current_consumption_revision','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_finalization_fingerprint','generic_preparation_fingerprint','generic_stage_result_fingerprint','generic_admission_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','evaluated_at','apply_eligibility_expires_at','apply_eligible','session_key_accepted','session_key_persisted','session_key_exposed','admission_is_authority','requires_immediate_rerun_by_apply_executor','requires_exact_spicetify_apply_executor','requires_exact_rollback_on_apply_failure','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized','admission_fingerprint')){if(-not$Decision.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-post-swap-admission-required-field-missing-'+$f)}}}
    if([int]$Decision.schema-ne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSchema -or [string]$Decision.managed_by-cne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionManagedBy -or [string]$Decision.reason-cne'recovery-aware-post-swap-current-state-eligible-for-bounded-apply-executor'){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-owner-schema-or-reason-invalid'}}
    if([string]$Decision.qualified_recovery_aware_finalization_head-cne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationHead -or [string]$Decision.qualified_recovery_aware_finalization_core_blob-cne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationCoreBlob -or [string]$Decision.qualified_generic_post_swap_admission_head-cne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericHead -or [string]$Decision.qualified_generic_post_swap_admission_core_blob-cne$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-lineage-invalid'}}
    foreach($f in @('transaction_id','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_finalization_fingerprint','generic_preparation_fingerprint','generic_stage_result_fingerprint','generic_admission_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','admission_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010(([string]$Decision.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-post-swap-admission-invalid-'+$f)}}}
    if($Decision.PSObject.Properties['preserved_git_tree_sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Decision.preserved_git_tree_sha256) -and -not(Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010(([string]$Decision.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-invalid-preserved-git-tree'}}
    if(([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-invalid-remote-commit'}}
    try{if([int64]$Decision.github_repo_id-le0 -or [int64]$Decision.current_consumption_revision-lt1){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-numeric-field-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-numeric-field-invalid'}}
    foreach($f in @('apply_eligible','session_key_accepted','requires_immediate_rerun_by_apply_executor','requires_exact_spicetify_apply_executor','requires_exact_rollback_on_apply_failure')){if(-not[bool]$Decision.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-post-swap-admission-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','admission_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-post-swap-admission-authority-or-key-escaped-'+$f)}}}
    $at=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Decision.evaluated_at,[ref]$at)-or-not[DateTimeOffset]::TryParse([string]$Decision.apply_eligibility_expires_at,[ref]$expires)-or$expires-le$at-or$expires-gt$at.AddSeconds(20)){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-time-window-invalid'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionMaterialV010 -Decision $Decision)
    if(([string]$Decision.admission_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-post-swap-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-post-swap-admission-valid-zero-authority';admission_fingerprint=$expected;production_mutation_authorized=$false}
}

function Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareFinalizationResult,[Parameter(Mandatory=$true)]$RecoveryAwareAtomicResult,[Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDeniedV010 -Reason $Reason}
    if($SessionKey.Length-lt32){return & $deny 'recovery-aware-post-swap-session-key-too-short'}
    $fc=Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultV010 -Result $RecoveryAwareFinalizationResult;if(-not[bool]$fc.ok){return & $deny ('recovery-aware-post-swap-finalization-result-invalid:'+[string]$fc.reason)}
    $ac=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $RecoveryAwareAtomicResult;if(-not[bool]$ac.ok){return & $deny ('recovery-aware-post-swap-atomic-result-invalid:'+[string]$ac.reason)}
    $pc=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreparedResult;if(-not[bool]$pc.ok){return & $deny ('recovery-aware-post-swap-prepared-result-invalid:'+[string]$pc.reason)}
    $sc=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult;if(-not[bool]$sc.ok){return & $deny ('recovery-aware-post-swap-stage-result-invalid:'+[string]$sc.reason)}
    $continuity=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyContinuityV010 -FinalizationResult $RecoveryAwareFinalizationResult -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageResult $RecoveryAwareStageExecutorResult -Name $Name;if(-not[bool]$continuity.ok){return & $deny ([string]$continuity.reason)}

    $before=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if($null-eq$before -or -not[bool]$before.ok){return & $deny ('recovery-aware-post-swap-pre-generic-consumption-denied:'+[string]$before.reason)}
    try{$finalRevision=[int64]$RecoveryAwareFinalizationResult.current_consumption_revision;$beforeRevision=[int64]$before.current_revision}catch{return & $deny 'recovery-aware-post-swap-pre-generic-consumption-revision-invalid'}
    if($beforeRevision-lt$finalRevision){return & $deny 'recovery-aware-post-swap-pre-generic-consumption-revision-regressed'}
    if($beforeRevision-eq$finalRevision -and ([string]$before.current_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$RecoveryAwareFinalizationResult.current_consumption_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-post-swap-pre-generic-consumption-envelope-drift'}
    if(([string]$before.historical_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$RecoveryAwareFinalizationResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-post-swap-pre-generic-historical-envelope-drift'}

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $RecoveryAwareStageExecutorResult
    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreparedResult
    $genericFinal=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 -RecoveryAwareFinalizationResult $RecoveryAwareFinalizationResult -RecoveryAwareAtomicResult $RecoveryAwareAtomicResult -GenericPreparedResult $genericPrepared -GenericStageResult $genericStage
    $gsc=Test-CustomAppProductionStageExecutorResultV010 -Result $genericStage;if(-not[bool]$gsc.ok){return & $deny ('recovery-aware-post-swap-generic-stage-conversion-invalid:'+[string]$gsc.reason)}
    $gpc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $genericPrepared;if(-not[bool]$gpc.ok){return & $deny ('recovery-aware-post-swap-generic-prepared-conversion-invalid:'+[string]$gpc.reason)}
    $gfc=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $genericFinal;if(-not[bool]$gfc.ok){return & $deny ('recovery-aware-post-swap-generic-finalization-conversion-invalid:'+[string]$gfc.reason)}

    $generic=Resolve-CustomAppProductionPostSwapApplyAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareFinalizationResult.consumption_id) -Permit $Permit -FinalizationResult $genericFinal -PreparedResult $genericPrepared -StageExecutorResult $genericStage -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$generic -or -not[bool]$generic.ok -or $null-eq$generic.decision){return & $deny ('recovery-aware-post-swap-generic-admission-denied:'+[string]$generic.reason)}
    $gdc=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 -Decision $generic.decision;if(-not[bool]$gdc.ok){return & $deny ('recovery-aware-post-swap-generic-decision-invalid:'+[string]$gdc.reason)}

    $after=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    if($null-eq$after -or -not[bool]$after.ok){return & $deny ('recovery-aware-post-swap-post-generic-consumption-denied:'+[string]$after.reason)}
    try{$afterRevision=[int64]$after.current_revision}catch{return & $deny 'recovery-aware-post-swap-post-generic-consumption-revision-invalid'}
    if($afterRevision-lt$beforeRevision){return & $deny 'recovery-aware-post-swap-post-generic-consumption-revision-regressed'}
    if($afterRevision-eq$beforeRevision -and ([string]$after.current_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$before.current_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-post-swap-post-generic-consumption-envelope-drift'}
    if(([string]$after.historical_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$before.historical_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-post-swap-post-generic-historical-envelope-drift'}
    if(([string]$generic.decision.current_consumption_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$after.current_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-post-swap-ledger-race-after-generic-admission'}
    foreach($pair in @(@('live-tree',[string]$generic.decision.live_tree_sha256,[string]$RecoveryAwareFinalizationResult.live_runtime_tree_sha256),@('remote-tree',[string]$generic.decision.remote_tree_sha256,[string]$RecoveryAwareStageExecutorResult.remote_tree_sha256),@('remote-commit',[string]$generic.decision.remote_commit_sha,[string]$RecoveryAwareFinalizationResult.remote_commit_sha),@('binding',[string]$generic.decision.binding_fingerprint,[string]$RecoveryAwareFinalizationResult.binding_fingerprint),@('persistence',[string]$generic.decision.persistence_fingerprint,[string]$RecoveryAwareFinalizationResult.persistence_fingerprint))){if(([string]$pair[1]).Trim().ToLowerInvariant()-cne([string]$pair[2]).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-post-swap-generic-decision-continuity-mismatch-'+[string]$pair[0])}}

    $decision=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSchema;managed_by=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionManagedBy;qualified_recovery_aware_finalization_head=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationHead;qualified_recovery_aware_finalization_core_blob=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedFinalizationCoreBlob;qualified_generic_post_swap_admission_head=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericHead;qualified_generic_post_swap_admission_core_blob=$CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionQualifiedGenericCoreBlob;reason='recovery-aware-post-swap-current-state-eligible-for-bounded-apply-executor'
        name=$Name;source_identity=([string]$RecoveryAwareFinalizationResult.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$RecoveryAwareFinalizationResult.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$RecoveryAwareFinalizationResult.github_repo_id;surface_kind=([string]$RecoveryAwareFinalizationResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareFinalizationResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareFinalizationResult.binding_fingerprint).Trim().ToLowerInvariant()
        consumption_id=([string]$RecoveryAwareFinalizationResult.consumption_id).Trim().ToLowerInvariant();historical_consumption_envelope_sha256=([string]$after.historical_envelope_sha256).Trim().ToLowerInvariant();current_consumption_envelope_sha256=([string]$after.current_envelope_sha256).Trim().ToLowerInvariant();current_consumption_revision=$afterRevision
        recovery_finalization_result_fingerprint=([string]$RecoveryAwareFinalizationResult.result_fingerprint).Trim().ToLowerInvariant();recovery_atomic_result_fingerprint=([string]$RecoveryAwareAtomicResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        generic_finalization_fingerprint=([string]$genericFinal.finalization_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$genericPrepared.preparation_fingerprint).Trim().ToLowerInvariant();generic_stage_result_fingerprint=([string]$genericStage.result_fingerprint).Trim().ToLowerInvariant();generic_admission_fingerprint=([string]$generic.decision.admission_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$generic.decision.live_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$generic.decision.remote_tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($generic.decision.PSObject.Properties['preserved_git_tree_sha256']){[string]$generic.decision.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$generic.decision.persistence_fingerprint).Trim().ToLowerInvariant();evaluated_at=[string]$generic.decision.evaluated_at;apply_eligibility_expires_at=[string]$generic.decision.apply_eligibility_expires_at
        apply_eligible=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;admission_is_authority=$false;requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true
        apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;admission_fingerprint=$null
    }
    $decision.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionMaterialV010 -Decision $decision)
    $check=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 -Decision $decision;if(-not[bool]$check.ok){return & $deny ('recovery-aware-post-swap-self-validation-failed:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason=[string]$decision.reason;decision=$decision;apply_eligible=$true;admission_fingerprint=[string]$decision.admission_fingerprint;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;admission_is_authority=$false;requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
