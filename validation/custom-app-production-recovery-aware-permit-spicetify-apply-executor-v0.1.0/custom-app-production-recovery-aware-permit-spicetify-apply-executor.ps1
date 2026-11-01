$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSchema = 1
$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorManagedBy = 'custom-app-production-recovery-aware-permit-spicetify-apply-executor-v1'
$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionHead = 'efdbdfcd8cca6549adc6e90809969e98f7bc7109'
$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionCoreBlob = 'b8c1462224a2b852efc7294aca233148d658f3f8'
$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericHead = 'fe07d410531ea13c8fca379b01405631a3763e84'
$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericCoreBlob = 'f7372b069fbfe6a0f8d8a0aad45312ffd33d9f0a'

function Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value) -and $Value-cmatch'^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitSpicetifyApplyDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,$GenericResult=$null,[bool]$ApplyExecuted=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$RollbackResult=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;generic_result=$GenericResult;spicetify_apply_executed=$ApplyExecuted;rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$RollbackResult
        session_key_persisted=$false;session_key_exposed=$false;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;requires_post_apply_commit_cleanup=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyLineageV010 {
    param(
        [Parameter(Mandatory=$true)]$AdmissionDecision,[Parameter(Mandatory=$true)]$FinalizationResult,[Parameter(Mandatory=$true)]$AtomicResult,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)][string]$Name
    )
    $dc=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 -Decision $AdmissionDecision
    if(-not[bool]$dc.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-apply-prior-admission-invalid:'+[string]$dc.reason)}}
    $pairs=@(
        @('recovery_finalization_result_fingerprint',[string]$AdmissionDecision.recovery_finalization_result_fingerprint,[string]$FinalizationResult.result_fingerprint),
        @('recovery_atomic_result_fingerprint',[string]$AdmissionDecision.recovery_atomic_result_fingerprint,[string]$AtomicResult.result_fingerprint),
        @('recovery_pre_apply_result_fingerprint',[string]$AdmissionDecision.recovery_pre_apply_result_fingerprint,[string]$PreparedResult.result_fingerprint),
        @('recovery_stage_result_fingerprint',[string]$AdmissionDecision.recovery_stage_result_fingerprint,[string]$StageResult.result_fingerprint),
        @('name',[string]$AdmissionDecision.name,[string]$Name),
        @('source_identity',[string]$AdmissionDecision.source_identity,[string]$FinalizationResult.source_identity),
        @('transaction_id',[string]$AdmissionDecision.transaction_id,[string]$FinalizationResult.transaction_id),
        @('surface_kind',[string]$AdmissionDecision.surface_kind,[string]$FinalizationResult.surface_kind),
        @('remote_commit_sha',[string]$AdmissionDecision.remote_commit_sha,[string]$FinalizationResult.remote_commit_sha),
        @('binding_fingerprint',[string]$AdmissionDecision.binding_fingerprint,[string]$FinalizationResult.binding_fingerprint),
        @('consumption_id',[string]$AdmissionDecision.consumption_id,[string]$FinalizationResult.consumption_id),
        @('historical_consumption_envelope_sha256',[string]$AdmissionDecision.historical_consumption_envelope_sha256,[string]$FinalizationResult.historical_consumption_envelope_sha256)
    )
    foreach($p in $pairs){if(([string]$p[1]).Trim().ToLowerInvariant()-cne([string]$p[2]).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-aware-apply-prior-admission-continuity-mismatch-'+[string]$p[0])}}}
    try{if([int64]$AdmissionDecision.github_repo_id-ne[int64]$FinalizationResult.github_repo_id){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-prior-admission-continuity-mismatch-github_repo_id'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-prior-admission-repo-id-invalid'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-apply-prior-admission-lineage-valid'}
}

function Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_recovery_aware_admission_head,[string]$Result.qualified_recovery_aware_admission_core_blob,[string]$Result.qualified_generic_apply_executor_head,[string]$Result.qualified_generic_apply_executor_core_blob,[string]$Result.status,[string]$Result.reason,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,[string]$Result.binding_fingerprint,[string]$Result.consumption_id,
        [string]$Result.historical_consumption_envelope_sha256,[string]$Result.current_consumption_envelope_sha256,[string]$Result.current_consumption_revision,
        [string]$Result.prior_recovery_admission_fingerprint,[string]$Result.fresh_recovery_admission_fingerprint,[string]$Result.recovery_finalization_result_fingerprint,[string]$Result.recovery_atomic_result_fingerprint,[string]$Result.recovery_pre_apply_result_fingerprint,[string]$Result.recovery_stage_result_fingerprint,[string]$Result.generic_apply_result_fingerprint,[string]$Result.generic_apply_admission_fingerprint,
        [string]$Result.live_tree_sha256,[string]$Result.remote_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.spicetify_executable_sha256,[string]$Result.primary_exit_code,[string]$Result.primary_timed_out,[string]$Result.apply_started_at,[string]$Result.apply_finished_at,
        [string]$Result.spicetify_apply_executed,[string]$Result.rollback_attempted,[string]$Result.rollback_ok,[string]$Result.requires_post_apply_commit_cleanup,[string]$Result.stage_workspace_preserved,[string]$Result.app_backup_preserved,[string]$Result.persistence_backup_preserved,
        [string]$Result.session_key_persisted,[string]$Result.session_key_exposed,[string]$Result.result_is_authority,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-null'}}
    foreach($f in @('schema','managed_by','qualified_recovery_aware_admission_head','qualified_recovery_aware_admission_core_blob','qualified_generic_apply_executor_head','qualified_generic_apply_executor_core_blob','status','reason','name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','current_consumption_revision','prior_recovery_admission_fingerprint','fresh_recovery_admission_fingerprint','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_apply_result_fingerprint','generic_apply_admission_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','spicetify_executable_sha256','primary_exit_code','primary_timed_out','apply_started_at','apply_finished_at','spicetify_apply_executed','rollback_attempted','rollback_ok','requires_post_apply_commit_cleanup','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','session_key_persisted','session_key_exposed','result_fingerprint','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-apply-result-required-field-missing-'+$f)}}}
    if([int]$Result.schema-ne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSchema -or [string]$Result.managed_by-cne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorManagedBy -or [string]$Result.qualified_recovery_aware_admission_head-cne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionHead -or [string]$Result.qualified_recovery_aware_admission_core_blob-cne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionCoreBlob -or [string]$Result.qualified_generic_apply_executor_head-cne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericHead -or [string]$Result.qualified_generic_apply_executor_core_blob-cne$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericCoreBlob -or [string]$Result.status-cne'recovery-aware-spicetify-apply-verified-awaiting-commit-cleanup' -or [string]$Result.reason-cne'exact-generic-spicetify-apply-succeeded-and-recovery-ledger-reverified'){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-owner-lineage-status-invalid'}}
    foreach($f in @('transaction_id','binding_fingerprint','consumption_id','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','prior_recovery_admission_fingerprint','fresh_recovery_admission_fingerprint','recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_apply_result_fingerprint','generic_apply_admission_fingerprint','live_tree_sha256','remote_tree_sha256','persistence_fingerprint','spicetify_executable_sha256','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-apply-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not(Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010(([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-invalid-remote-commit'}}
    try{if([int64]$Result.github_repo_id-le0 -or [int64]$Result.current_consumption_revision-lt1 -or [int]$Result.primary_exit_code-ne0){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-numeric-field-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-numeric-field-invalid'}}
    if(-not[bool]$Result.spicetify_apply_executed -or [bool]$Result.primary_timed_out -or [bool]$Result.rollback_attempted -or [bool]$Result.rollback_ok -or -not[bool]$Result.requires_post_apply_commit_cleanup -or -not[bool]$Result.stage_workspace_preserved -or -not[bool]$Result.app_backup_preserved -or -not[bool]$Result.persistence_backup_preserved){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-lifecycle-contract-invalid'}}
    foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-apply-result-authority-or-key-escaped-'+$f)}}}
    $started=[DateTimeOffset]::MinValue;$finished=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Result.apply_started_at,[ref]$started)-or-not[DateTimeOffset]::TryParse([string]$Result.apply_finished_at,[ref]$finished)-or$finished-lt$started){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-apply-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-apply-result-valid-zero-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorV010 {
    param(
        [Parameter(Mandatory=$true)]$PriorRecoveryAwareAdmissionDecision,[Parameter(Mandatory=$true)]$RecoveryAwareFinalizationResult,[Parameter(Mandatory=$true)]$RecoveryAwareAtomicResult,[Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyExecutablePath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,[int]$TimeoutSeconds=180
    )
    $deny={param([string]$Reason,$Generic=$null,[bool]$Executed=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$Rollback=$null) New-CustomAppProductionRecoveryAwarePermitSpicetifyApplyDeniedV010 -Reason $Reason -GenericResult $Generic -ApplyExecuted $Executed -RollbackAttempted $RollbackAttempted -RollbackOk $RollbackOk -RollbackResult $Rollback}
    if($SessionKey.Length-lt32){return & $deny 'recovery-aware-apply-session-key-too-short'}
    if($TimeoutSeconds-lt1-or$TimeoutSeconds-gt600){return & $deny 'recovery-aware-apply-timeout-policy-invalid'}
    $lineage=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyLineageV010 -AdmissionDecision $PriorRecoveryAwareAdmissionDecision -FinalizationResult $RecoveryAwareFinalizationResult -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageResult $RecoveryAwareStageExecutorResult -Name $Name
    if(-not[bool]$lineage.ok){return & $deny ([string]$lineage.reason)}

    $fresh=Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010 -RecoveryAwareFinalizationResult $RecoveryAwareFinalizationResult -RecoveryAwareAtomicResult $RecoveryAwareAtomicResult -RecoveryAwarePreparedResult $RecoveryAwarePreparedResult -RecoveryAwareStageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$fresh){return & $deny 'recovery-aware-apply-final-admission-denied:null'}
    if(-not[bool]$fresh.ok-or$null-eq$fresh.decision){return & $deny ('recovery-aware-apply-final-admission-denied:'+[string]$fresh.reason)}
    $freshCheck=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 -Decision $fresh.decision;if(-not[bool]$freshCheck.ok){return & $deny ('recovery-aware-apply-final-admission-invalid:'+[string]$freshCheck.reason)}
    foreach($f in @('recovery_finalization_result_fingerprint','recovery_atomic_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','historical_consumption_envelope_sha256')){if(([string]$fresh.decision.$f).Trim().ToLowerInvariant()-cne([string]$PriorRecoveryAwareAdmissionDecision.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-apply-prior-vs-fresh-lineage-mismatch-'+$f)}}

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $RecoveryAwareStageExecutorResult
    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreparedResult
    $genericFinal=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 -RecoveryAwareFinalizationResult $RecoveryAwareFinalizationResult -RecoveryAwareAtomicResult $RecoveryAwareAtomicResult -GenericPreparedResult $genericPrepared -GenericStageResult $genericStage
    $gsc=Test-CustomAppProductionStageExecutorResultV010 -Result $genericStage;if(-not[bool]$gsc.ok){return & $deny ('recovery-aware-apply-generic-stage-conversion-invalid:'+[string]$gsc.reason)}
    $gpc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $genericPrepared;if(-not[bool]$gpc.ok){return & $deny ('recovery-aware-apply-generic-prepared-conversion-invalid:'+[string]$gpc.reason)}
    $gfc=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $genericFinal;if(-not[bool]$gfc.ok){return & $deny ('recovery-aware-apply-generic-finalization-conversion-invalid:'+[string]$gfc.reason)}

    $generic=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareFinalizationResult.consumption_id) -Permit $Permit -FinalizationResult $genericFinal -PreparedResult $genericPrepared -StageExecutorResult $genericStage -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours -TimeoutSeconds $TimeoutSeconds
    if($null-eq$generic){return & $deny 'recovery-aware-apply-generic-executor-denied:null'}
    if(-not[bool]$generic.ok-or$null-eq$generic.result){
        $executed=[bool]$generic.spicetify_apply_executed;$ra=[bool]$generic.rollback_attempted;$ro=[bool]$generic.rollback_ok;$rr=$generic.rollback_result
        return & $deny ('recovery-aware-apply-generic-executor-denied:'+[string]$generic.reason) $generic $executed $ra $ro $rr
    }
    $grc=Test-CustomAppProductionSpicetifyApplyResultV010 -Result $generic.result;if(-not[bool]$grc.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $genericPrepared -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('recovery-aware-apply-generic-result-invalid:'+[string]$grc.reason) $generic $true $true ([bool]$rollback.ok) $rollback
    }

    $post=Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 -AtomicResult $RecoveryAwareAtomicResult -PreparedResult $RecoveryAwarePreparedResult -StageExecutorResult $RecoveryAwareStageExecutorResult -ConsumptionPersistenceResult $ConsumptionPersistenceResult -AllowedRoot $AllowedRoot -ConsumptionStoreDirectory $ConsumptionStoreDirectory -Name $Name
    $postReason=$null
    if($null-eq$post){$postReason='recovery-aware-apply-post-consumption-denied:null'}
    elseif(-not[bool]$post.ok){$postReason='recovery-aware-apply-post-consumption-denied:'+[string]$post.reason}
    else{
        try{$postRevision=[int64]$post.current_revision;$preRevision=[int64]$fresh.decision.current_consumption_revision}catch{$postReason='recovery-aware-apply-post-consumption-revision-invalid'}
        if($null-eq$postReason-and$postRevision-lt$preRevision){$postReason='recovery-aware-apply-post-consumption-revision-regressed'}
        if($null-eq$postReason-and$postRevision-eq$preRevision-and([string]$post.current_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$fresh.decision.current_consumption_envelope_sha256).Trim().ToLowerInvariant()){$postReason='recovery-aware-apply-post-consumption-envelope-drift'}
        if($null-eq$postReason-and([string]$post.historical_envelope_sha256).Trim().ToLowerInvariant()-cne([string]$fresh.decision.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()){$postReason='recovery-aware-apply-post-historical-consumption-envelope-drift'}
    }
    if($null-ne$postReason){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $genericPrepared -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny $postReason $generic $true $true ([bool]$rollback.ok) $rollback
    }

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSchema;managed_by=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorManagedBy;qualified_recovery_aware_admission_head=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionHead;qualified_recovery_aware_admission_core_blob=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedAdmissionCoreBlob;qualified_generic_apply_executor_head=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericHead;qualified_generic_apply_executor_core_blob=$CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorQualifiedGenericCoreBlob;status='recovery-aware-spicetify-apply-verified-awaiting-commit-cleanup';reason='exact-generic-spicetify-apply-succeeded-and-recovery-ledger-reverified'
        name=$Name;source_identity=([string]$RecoveryAwareFinalizationResult.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$RecoveryAwareFinalizationResult.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$RecoveryAwareFinalizationResult.github_repo_id;surface_kind=([string]$RecoveryAwareFinalizationResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareFinalizationResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwareFinalizationResult.binding_fingerprint).Trim().ToLowerInvariant();consumption_id=([string]$RecoveryAwareFinalizationResult.consumption_id).Trim().ToLowerInvariant()
        historical_consumption_envelope_sha256=([string]$post.historical_envelope_sha256).Trim().ToLowerInvariant();current_consumption_envelope_sha256=([string]$post.current_envelope_sha256).Trim().ToLowerInvariant();current_consumption_revision=[int64]$post.current_revision
        prior_recovery_admission_fingerprint=([string]$PriorRecoveryAwareAdmissionDecision.admission_fingerprint).Trim().ToLowerInvariant();fresh_recovery_admission_fingerprint=([string]$fresh.decision.admission_fingerprint).Trim().ToLowerInvariant();recovery_finalization_result_fingerprint=([string]$RecoveryAwareFinalizationResult.result_fingerprint).Trim().ToLowerInvariant();recovery_atomic_result_fingerprint=([string]$RecoveryAwareAtomicResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();generic_apply_result_fingerprint=([string]$generic.result.result_fingerprint).Trim().ToLowerInvariant();generic_apply_admission_fingerprint=([string]$generic.result.apply_admission_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$generic.result.live_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$generic.result.remote_tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($generic.result.PSObject.Properties['preserved_git_tree_sha256']){[string]$generic.result.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$generic.result.persistence_fingerprint).Trim().ToLowerInvariant();spicetify_executable_sha256=([string]$generic.result.spicetify_executable_sha256).Trim().ToLowerInvariant();primary_exit_code=[int]$generic.result.primary_exit_code;primary_timed_out=[bool]$generic.result.primary_timed_out;apply_started_at=[string]$generic.result.apply_started_at;apply_finished_at=[string]$generic.result.apply_finished_at
        spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false;requires_post_apply_commit_cleanup=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;session_key_persisted=$false;session_key_exposed=$false;result_fingerprint=$null;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 -Result $result
    if(-not[bool]$check.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $genericPrepared -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('recovery-aware-apply-self-validation-failed:'+[string]$check.reason) $generic $true $true ([bool]$rollback.ok) $rollback
    }
    return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false;requires_post_apply_commit_cleanup=$true;session_key_persisted=$false;session_key_exposed=$false;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
