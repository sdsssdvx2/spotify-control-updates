$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema = 1
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy = 'custom-app-production-recovery-aware-permit-atomic-live-swap-v1'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead = '43f9a433354f56e2db19f4edfa1ffa8f4a245088'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob = 'eaad8a5f161f831bbbada1c1c0957a3dfc80edaa'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead = '574fe182168271fa3497d58e269e9af1f60d9033'
$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob = 'e91fa6a125f77352907c1119f6d9f47be9682550'

function Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapDeniedV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [bool]$RecoveryRevalidated=$false,[bool]$GenericAtomicInvoked=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,
        [bool]$CleanupRequired=$false,[AllowNull()]$RollbackResult=$null
    )
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;recovery_revalidated_immediately_before_swap=$RecoveryRevalidated;generic_atomic_invoked=$GenericAtomicInvoked
        rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$RollbackResult;live_code_swap_performed=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false;atomic_result_is_authority=$false
        requires_transaction_finalization=$true;requires_fresh_post_swap_apply_admission=$true;requires_spicetify_apply_phase=$true;requires_cleanup_if_not_promoted=$CleanupRequired
        apply_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitGenericAtomicSuccessV010 {
    param([AllowNull()]$Result,[Parameter(Mandatory=$true)][string]$ExpectedName)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-null'}}
    foreach($f in @('ok','reason','schema','managed_by','qualified_pre_apply_head','name','live_path','transaction_root','old_live_path','fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint','rollback_attempted','rollback_ok','live_code_swap_performed','requires_transaction_workspace_cleanup','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){
        if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-field-missing-'+$f)}}
    }
    if(-not [bool]$Result.ok -or [string]$Result.reason -cne 'atomic-live-code-swap-verified-no-spicetify-apply' -or [int]$Result.schema -ne $CustomAppProductionAtomicLiveSwapSchema -or [string]$Result.managed_by -cne $CustomAppProductionAtomicLiveSwapManagedBy -or [string]$Result.qualified_pre_apply_head -cne $CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-owner-schema-status-invalid'}}
    if(([string]$Result.name).Trim().ToLowerInvariant() -cne $ExpectedName.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-name-mismatch'}}
    if([bool]$Result.rollback_attempted -or [bool]$Result.rollback_ok -or -not [bool]$Result.live_code_swap_performed -or -not [bool]$Result.requires_transaction_workspace_cleanup -or -not [bool]$Result.requires_spicetify_apply_phase){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-lifecycle-contract-invalid'}}
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-authority-escaped-'+$f)}}}
    foreach($f in @('fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('generic-atomic-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='generic-atomic-result-invalid-preserved-git-tree'}}
    return [pscustomobject]@{ok=$true;reason='generic-atomic-success-result-valid-zero-future-authority'}
}

function Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_recovery_aware_pre_apply_head,[string]$Result.qualified_recovery_aware_pre_apply_core_blob,
        [string]$Result.qualified_generic_atomic_head,[string]$Result.qualified_generic_atomic_core_blob,[string]$Result.status,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,
        [string]$Result.consumption_id,[string]$Result.consumption_persistence_fingerprint,[string]$Result.historical_consumption_envelope_sha256,[string]$Result.current_consumption_envelope_sha256,
        [string]$Result.recovery_stage_result_fingerprint,[string]$Result.recovery_pre_apply_result_fingerprint,[string]$Result.recovery_pre_swap_admission_fingerprint,
        [string]$Result.generic_stage_result_fingerprint,[string]$Result.generic_preparation_fingerprint,[string]$Result.generic_atomic_fresh_admission_fingerprint,
        [string]$Result.binding_fingerprint,[string]$Result.live_path,[string]$Result.transaction_root,[string]$Result.old_live_path,[string]$Result.old_live_tree_sha256,[string]$Result.post_runtime_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.swapped_at,
        [string]$Result.recovery_revalidated_immediately_before_swap,[string]$Result.generic_atomic_invoked_once,[string]$Result.live_code_swap_performed,[string]$Result.transaction_workspace_retained,
        [string]$Result.session_key_accepted,[string]$Result.session_key_persisted,[string]$Result.session_key_exposed,[string]$Result.atomic_result_is_authority,
        [string]$Result.requires_transaction_finalization,[string]$Result.requires_fresh_post_swap_apply_admission,[string]$Result.requires_spicetify_apply_phase,[string]$Result.requires_cleanup_if_not_promoted,
        [string]$Result.apply_authorized,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_recovery_aware_pre_apply_head','qualified_recovery_aware_pre_apply_core_blob','qualified_generic_atomic_head','qualified_generic_atomic_core_blob','status',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','current_consumption_envelope_sha256',
        'recovery_stage_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_pre_swap_admission_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_atomic_fresh_admission_fingerprint',
        'binding_fingerprint','live_path','transaction_root','old_live_path','old_live_tree_sha256','post_runtime_tree_sha256','persistence_fingerprint','swapped_at',
        'recovery_revalidated_immediately_before_swap','generic_atomic_invoked_once','live_code_swap_performed','transaction_workspace_retained','session_key_accepted','session_key_persisted','session_key_exposed','atomic_result_is_authority',
        'requires_transaction_finalization','requires_fresh_post_swap_apply_admission','requires_spicetify_apply_phase','requires_cleanup_if_not_promoted','apply_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint'
    )){if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-field-missing-'+$f)}}}
    if([int]$Result.schema -ne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema -or [string]$Result.managed_by -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy -or [string]$Result.status -cne 'recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply'){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-owner-schema-status-invalid'}}
    if([string]$Result.qualified_recovery_aware_pre_apply_head -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead -or [string]$Result.qualified_recovery_aware_pre_apply_core_blob -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob -or [string]$Result.qualified_generic_atomic_head -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead -or [string]$Result.qualified_generic_atomic_core_blob -cne $CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','current_consumption_envelope_sha256','recovery_stage_result_fingerprint','recovery_pre_apply_result_fingerprint','recovery_pre_swap_admission_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_atomic_fresh_admission_fingerprint','binding_fingerprint','old_live_tree_sha256','post_runtime_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-remote-commit-invalid'}}
    try{if([int64]$Result.github_repo_id -le 0){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-repo-id-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-repo-id-invalid'}}
    $at=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Result.swapped_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-time-invalid'}}
    foreach($f in @('recovery_revalidated_immediately_before_swap','generic_atomic_invoked_once','live_code_swap_performed','transaction_workspace_retained','session_key_accepted','requires_transaction_finalization','requires_fresh_post_swap_apply_admission','requires_spicetify_apply_phase','requires_cleanup_if_not_promoted')){if(-not [bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','atomic_result_is_authority','apply_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-atomic-result-authority-escaped-'+$f)}}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-atomic-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-atomic-result-valid-zero-post-swap-apply-authority';result_fingerprint=$expected}
}

function Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwarePreApplyResult,[Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$LifecycleStageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $cleanupRequired=$false
    $deny={param([string]$Reason,[bool]$Recovery=$false,[bool]$Invoked=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$RollbackResult=$null) New-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapDeniedV010 -Reason $Reason -RecoveryRevalidated $Recovery -GenericAtomicInvoked $Invoked -RollbackAttempted $RollbackAttempted -RollbackOk $RollbackOk -CleanupRequired $cleanupRequired -RollbackResult $RollbackResult}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-atomic-session-key-too-short'}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreApplyResult
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-atomic-pre-apply-result-invalid:'+[string]$preCheck.reason)}
    $cleanupRequired=$true
    $stageCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('recovery-aware-atomic-stage-result-invalid:'+[string]$stageCheck.reason)}
    if(([string]$RecoveryAwarePreApplyResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant() -or ([string]$RecoveryAwareStageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-name-continuity-mismatch'}
    if(([string]$RecoveryAwarePreApplyResult.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant() -or ([string]$RecoveryAwareStageExecutorResult.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-transaction-continuity-mismatch'}
    if(([string]$RecoveryAwarePreApplyResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-stage-fingerprint-continuity-mismatch'}
    foreach($f in @('source_identity','github_repo_id','surface_kind','remote_commit_sha','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){
        if(([string]$RecoveryAwarePreApplyResult.$f).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-atomic-stage-pre-apply-continuity-mismatch-'+$f)}
    }

    if($null -eq $LifecycleRow -or @($LifecycleRow.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$LifecycleRow.locations[0])){return & $deny 'recovery-aware-atomic-live-location-not-single'}
    try{$livePath=[IO.Path]::GetFullPath([string]$LifecycleRow.locations[0]).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$actualLive=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath}
    catch{return & $deny ('recovery-aware-atomic-live-baseline-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$actualLive.safe -or -not [bool]$actualLive.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $actualLive) -or ([string]$actualLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreApplyResult.live_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-live-baseline-drift-before-swap'}

    $freshRecoveryLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshRecoveryLive.ok){return & $deny ('recovery-aware-atomic-fresh-recovery-live-denied:'+[string]$freshRecoveryLive.reason)}
    if(([string]$freshRecoveryLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-fresh-recovery-live-tree-mismatch'}
    $ctxAdmission=Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $LifecycleStageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $freshRecoveryLive.baseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -RecoveryStoreDirectory $RecoveryStoreDirectory -ConsumptionStoreDirectory $ConsumptionStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -ConsumptionPersistenceResult $ConsumptionPersistenceResult -Permit $Permit -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $ctxAdmission -or -not [bool]$ctxAdmission.ok -or -not [bool]$ctxAdmission.stage_acquisition_eligible -or $null -eq $ctxAdmission.receipt){return & $deny ('recovery-aware-atomic-pre-swap-admission-denied:'+[string]$ctxAdmission.reason)}
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $ctxAdmission.receipt -Now $Now
    if(-not [bool]$receiptCheck.ok){return & $deny ('recovery-aware-atomic-pre-swap-admission-invalid:'+[string]$receiptCheck.reason)}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){
        if(([string]$ctxAdmission.receipt.$f).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreApplyResult.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-atomic-pre-swap-admission-continuity-mismatch-'+$f)}
    }

    try{$storeBefore=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory}
    catch{return & $deny ('recovery-aware-atomic-consumption-store-pre-read-failed:'+[string]$_.Exception.Message) $true}
    if($null -eq $storeBefore -or -not [bool]$storeBefore.ok -or -not [bool]$storeBefore.reloaded_from_persistent_store -or $null -eq $storeBefore.envelope){return & $deny 'recovery-aware-atomic-consumption-store-pre-invalid' $true}
    $storeEnvelopeBefore=([string]$storeBefore.envelope.envelope_sha256).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 $storeEnvelopeBefore)){return & $deny 'recovery-aware-atomic-consumption-store-pre-envelope-invalid' $true}

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $RecoveryAwareStageExecutorResult
    $genericStageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $genericStage
    if(-not [bool]$genericStageCheck.ok){return & $deny ('recovery-aware-atomic-generic-stage-bridge-invalid:'+[string]$genericStageCheck.reason) $true}
    if(([string]$genericStage.result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreApplyResult.generic_stage_result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-atomic-generic-stage-fingerprint-drift' $true}
    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreApplyResult
    $genericPreparedCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $genericPrepared
    if(-not [bool]$genericPreparedCheck.ok){return & $deny ('recovery-aware-atomic-generic-prepared-bridge-invalid:'+[string]$genericPreparedCheck.reason) $true}

    $atomic=$null
    try{
        $atomic=Invoke-CustomAppProductionAtomicLiveSwapV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareStageExecutorResult.consumption_id) -StageExecutorResult $genericStage -PreparedResult $genericPrepared -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }catch{return & $deny ('recovery-aware-atomic-generic-atomic-threw:'+[string]$_.Exception.Message) $true $true}
    if($null -eq $atomic -or -not [bool]$atomic.ok){
        $ra=$(if($null -ne $atomic -and $atomic.PSObject.Properties['rollback_attempted']){[bool]$atomic.rollback_attempted}else{$false});$ro=$(if($null -ne $atomic -and $atomic.PSObject.Properties['rollback_ok']){[bool]$atomic.rollback_ok}else{$false});$rr=$(if($null -ne $atomic -and $atomic.PSObject.Properties['rollback_result']){$atomic.rollback_result}else{$null})
        return & $deny ('recovery-aware-atomic-generic-atomic-denied:'+[string]$atomic.reason) $true $true $ra $ro $rr
    }

    $rollbackAndDeny={param([string]$Reason)
        $rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$atomic.live_path) -AppBackupPath ([string]$RecoveryAwarePreApplyResult.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$RecoveryAwarePreApplyResult.app_backup_tree_sha256) -PersistenceBackupPath ([string]$RecoveryAwarePreApplyResult.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$RecoveryAwarePreApplyResult.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        return & $deny $Reason $true $true $true ([bool]$rb.ok) $rb
    }
    $atomicCheck=Test-CustomAppProductionRecoveryAwarePermitGenericAtomicSuccessV010 -Result $atomic -ExpectedName $Name
    if(-not [bool]$atomicCheck.ok){return & $rollbackAndDeny ('recovery-aware-atomic-generic-success-result-invalid:'+[string]$atomicCheck.reason)}
    try{$postLive=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath}catch{return & $rollbackAndDeny ('recovery-aware-atomic-post-live-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$postLive.safe -or -not [bool]$postLive.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $postLive) -or ([string]$postLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant() -or ([string]$postLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$atomic.post_runtime_tree_sha256).Trim().ToLowerInvariant()){return & $rollbackAndDeny 'recovery-aware-atomic-post-live-runtime-mismatch'}
    try{$oldSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$atomic.old_live_path)}catch{return & $rollbackAndDeny ('recovery-aware-atomic-old-live-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreApplyResult.app_backup_tree_sha256).Trim().ToLowerInvariant() -or [int]$oldSnapshot.file_count -ne [int]$RecoveryAwarePreApplyResult.app_backup_file_count -or [int64]$oldSnapshot.total_bytes -ne [int64]$RecoveryAwarePreApplyResult.app_backup_total_bytes){return & $rollbackAndDeny 'recovery-aware-atomic-old-live-not-exact-pre-swap-tree'}
    try{$postPersistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $rollbackAndDeny ('recovery-aware-atomic-post-persistence-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$postPersistence.fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwarePreApplyResult.persistence_fingerprint).Trim().ToLowerInvariant() -or ([string]$postPersistence.fingerprint).Trim().ToLowerInvariant() -cne ([string]$atomic.persistence_fingerprint).Trim().ToLowerInvariant()){return & $rollbackAndDeny 'recovery-aware-atomic-protected-persistence-drift-after-wrapper'}
    try{$storeAfter=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory}catch{return & $rollbackAndDeny ('recovery-aware-atomic-consumption-store-post-read-failed:'+[string]$_.Exception.Message)}
    if($null -eq $storeAfter -or -not [bool]$storeAfter.ok -or -not [bool]$storeAfter.reloaded_from_persistent_store -or $null -eq $storeAfter.envelope){return & $rollbackAndDeny 'recovery-aware-atomic-consumption-store-post-invalid'}
    $storeEnvelopeAfter=([string]$storeAfter.envelope.envelope_sha256).Trim().ToLowerInvariant()
    if($storeEnvelopeAfter -cne $storeEnvelopeBefore){return & $rollbackAndDeny 'recovery-aware-atomic-consumption-ledger-mutated-by-live-swap'}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSchema;managed_by=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapManagedBy
        qualified_recovery_aware_pre_apply_head=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyHead;qualified_recovery_aware_pre_apply_core_blob=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedPreApplyCoreBlob
        qualified_generic_atomic_head=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicHead;qualified_generic_atomic_core_blob=$CustomAppProductionRecoveryAwarePermitAtomicLiveSwapQualifiedGenericAtomicCoreBlob
        status='recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply'
        name=$Name;source_identity=([string]$RecoveryAwareStageExecutorResult.source_identity).Trim().ToLowerInvariant();transaction_id=$ExpectedTransactionId.Trim().ToLowerInvariant();github_repo_id=[int64]$RecoveryAwareStageExecutorResult.github_repo_id;surface_kind=([string]$RecoveryAwareStageExecutorResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareStageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$RecoveryAwareStageExecutorResult.consumption_id).Trim().ToLowerInvariant();consumption_persistence_fingerprint=([string]$RecoveryAwareStageExecutorResult.consumption_persistence_fingerprint).Trim().ToLowerInvariant();historical_consumption_envelope_sha256=([string]$RecoveryAwareStageExecutorResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant();current_consumption_envelope_sha256=$storeEnvelopeAfter
        recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreApplyResult.result_fingerprint).Trim().ToLowerInvariant();recovery_pre_swap_admission_fingerprint=([string]$ctxAdmission.receipt.admission_fingerprint).Trim().ToLowerInvariant()
        generic_stage_result_fingerprint=([string]$genericStage.result_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$genericPrepared.preparation_fingerprint).Trim().ToLowerInvariant();generic_atomic_fresh_admission_fingerprint=([string]$atomic.fresh_admission_fingerprint).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$RecoveryAwareStageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant();live_path=[string]$atomic.live_path;transaction_root=[string]$atomic.transaction_root;old_live_path=[string]$atomic.old_live_path;old_live_tree_sha256=([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant();post_runtime_tree_sha256=([string]$postLive.tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if($atomic.PSObject.Properties['preserved_git_tree_sha256']){[string]$atomic.preserved_git_tree_sha256}else{$null});persistence_fingerprint=([string]$postPersistence.fingerprint).Trim().ToLowerInvariant();swapped_at=$Now.ToUniversalTime().ToString('o')
        recovery_revalidated_immediately_before_swap=$true;generic_atomic_invoked_once=$true;live_code_swap_performed=$true;transaction_workspace_retained=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;atomic_result_is_authority=$false
        requires_transaction_finalization=$true;requires_fresh_post_swap_apply_admission=$true;requires_spicetify_apply_phase=$true;requires_cleanup_if_not_promoted=$true
        apply_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultMaterialV010 -Result $result)
    $resultCheck=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $result
    if(-not [bool]$resultCheck.ok){return & $rollbackAndDeny ('recovery-aware-atomic-output-self-validation-failed:'+[string]$resultCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply';result=$result;recovery_revalidated_immediately_before_swap=$true;generic_atomic_invoked=$true;rollback_attempted=$false;rollback_ok=$false;live_code_swap_performed=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;atomic_result_is_authority=$false;requires_transaction_finalization=$true;requires_fresh_post_swap_apply_admission=$true;requires_spicetify_apply_phase=$true;requires_cleanup_if_not_promoted=$true
        apply_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
