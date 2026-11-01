$CustomAppProductionRecoveryAwarePermitPreApplyPreparationSchema = 1
$CustomAppProductionRecoveryAwarePermitPreApplyPreparationManagedBy = 'custom-app-production-recovery-aware-permit-pre-apply-preparation-v1'
$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorHead = 'fa9854ede58d0ed0164c5fe787863449a39796ca'
$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorCoreBlob = '93a7c88270ebfd9de90fe638fde9f2408bf4cf28'
$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericHead = 'ddc84778ab4815d4174198727b8d1d052a02182e'
$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericCoreBlob = '9b039819e7b2278fe4cf15c8585336dd07a8e8e3'

function Get-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitPreApplyDeniedV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [bool]$BackupsPrepared=$false,
        [bool]$CleanupRequired=$false
    )
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;backups_prepared=$BackupsPrepared;recovery_revalidated_before_backups=$false;recovery_revalidated_after_backups=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false;preparation_is_authority=$false;backups_are_authority=$false
        requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$CleanupRequired
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 {
    param([Parameter(Mandatory=$true)]$RecoveryAwareResult)
    $r=[pscustomobject]@{
        schema=$CustomAppProductionStageExecutorSchema;managed_by=$CustomAppProductionStageExecutorManagedBy
        qualified_admission_head=$CustomAppProductionStageExecutorQualifiedAdmissionHead;qualified_stage_contract_head=$CustomAppProductionStageExecutorQualifiedStageContractHead
        status='staged-verified-post-stage-revalidated'
        consumption_id=([string]$RecoveryAwareResult.consumption_id).Trim().ToLowerInvariant()
        pre_stage_admission_fingerprint=([string]$RecoveryAwareResult.pre_stage_admission_fingerprint).Trim().ToLowerInvariant()
        post_stage_admission_fingerprint=([string]$RecoveryAwareResult.post_stage_admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$RecoveryAwareResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()
        name=[string]$RecoveryAwareResult.name;source_identity=([string]$RecoveryAwareResult.source_identity).Trim().ToLowerInvariant()
        github_repo_id=[int64]$RecoveryAwareResult.github_repo_id;surface_kind=([string]$RecoveryAwareResult.surface_kind).Trim().ToLowerInvariant()
        remote_commit_sha=([string]$RecoveryAwareResult.remote_commit_sha).Trim().ToLowerInvariant()
        local_tree_sha256=([string]$RecoveryAwareResult.local_tree_sha256).Trim().ToLowerInvariant()
        remote_tree_sha256=([string]$RecoveryAwareResult.remote_tree_sha256).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$RecoveryAwareResult.binding_fingerprint).Trim().ToLowerInvariant()
        archive_sha256=([string]$RecoveryAwareResult.archive_sha256).Trim().ToLowerInvariant()
        workspace_path=[string]$RecoveryAwareResult.workspace_path;stage_path=[string]$RecoveryAwareResult.stage_path
        staged_at=[string]$RecoveryAwareResult.staged_at;post_stage_revalidated_at=[string]$RecoveryAwareResult.post_stage_revalidated_at
        stage_performed=$true;live_runtime_unchanged=$true;post_stage_revalidated=$true;result_fingerprint=$null;result_is_authority=$false
        stage_workspace_retained_for_pre_apply=$true;requires_cleanup_if_not_promoted=$true;requires_fresh_revalidation_before_apply=$true
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $r.result_fingerprint=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 -Result $r)
    return $r
}

function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return [pscustomobject]@{
        schema=$CustomAppProductionPreApplyPreparationSchema;managed_by=$CustomAppProductionPreApplyPreparationManagedBy
        qualified_stage_executor_head=$CustomAppProductionPreApplyPreparationQualifiedStageHead;qualified_admission_head=$CustomAppProductionPreApplyPreparationQualifiedAdmissionHead
        qualified_persistence_head=$CustomAppProductionPreApplyPreparationQualifiedPersistenceHead;qualified_transaction_head=$CustomAppProductionPreApplyPreparationQualifiedTransactionHead
        status='pre-apply-backups-prepared-verified'
        name=[string]$Result.name;source_identity=[string]$Result.source_identity;github_repo_id=[int64]$Result.github_repo_id;surface_kind=[string]$Result.surface_kind;remote_commit_sha=[string]$Result.remote_commit_sha
        consumption_id=[string]$Result.consumption_id;stage_result_fingerprint=[string]$Result.generic_stage_result_fingerprint
        pre_apply_admission_fingerprint=[string]$Result.generic_pre_apply_admission_fingerprint;persistence_envelope_sha256=[string]$Result.historical_consumption_envelope_sha256
        live_tree_sha256=[string]$Result.live_tree_sha256;stage_tree_sha256=[string]$Result.stage_tree_sha256;binding_fingerprint=[string]$Result.binding_fingerprint
        stage_path=[string]$Result.stage_path;stage_workspace_path=[string]$Result.stage_workspace_path
        app_backup_root=[string]$Result.app_backup_root;app_backup_path=[string]$Result.app_backup_path;app_backup_tree_sha256=[string]$Result.app_backup_tree_sha256
        app_backup_file_count=[int]$Result.app_backup_file_count;app_backup_total_bytes=[int64]$Result.app_backup_total_bytes
        persistence_backup_root=[string]$Result.persistence_backup_root;persistence_backup_path=[string]$Result.persistence_backup_path;persistence_fingerprint=[string]$Result.persistence_fingerprint
        prepared_at=[string]$Result.prepared_at;preparation_fingerprint=[string]$Result.generic_preparation_fingerprint
        preparation_is_authority=$false;backups_are_authority=$false;requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionRecoveryAwarePermitPreApplyResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,
        [string]$Result.qualified_recovery_aware_stage_executor_head,[string]$Result.qualified_recovery_aware_stage_executor_core_blob,
        [string]$Result.qualified_generic_pre_apply_head,[string]$Result.qualified_generic_pre_apply_core_blob,[string]$Result.status,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.transaction_id,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,
        [string]$Result.consumption_id,[string]$Result.consumption_persistence_fingerprint,[string]$Result.historical_consumption_envelope_sha256,
        [string]$Result.recovery_pre_backup_admission_fingerprint,[string]$Result.recovery_post_backup_admission_fingerprint,
        [string]$Result.recovery_stage_result_fingerprint,[string]$Result.generic_stage_result_fingerprint,[string]$Result.generic_preparation_fingerprint,[string]$Result.generic_pre_apply_admission_fingerprint,
        [string]$Result.live_tree_sha256,[string]$Result.stage_tree_sha256,[string]$Result.binding_fingerprint,[string]$Result.stage_path,[string]$Result.stage_workspace_path,
        [string]$Result.app_backup_root,[string]$Result.app_backup_path,[string]$Result.app_backup_tree_sha256,[string]$Result.app_backup_file_count,[string]$Result.app_backup_total_bytes,
        [string]$Result.persistence_backup_root,[string]$Result.persistence_backup_path,[string]$Result.persistence_fingerprint,
        [string]$Result.prepared_at,[string]$Result.post_backup_revalidated_at,[string]$Result.backups_prepared,[string]$Result.recovery_revalidated_before_backups,[string]$Result.recovery_revalidated_after_backups,
        [string]$Result.session_key_accepted,[string]$Result.session_key_persisted,[string]$Result.session_key_exposed,[string]$Result.preparation_is_authority,[string]$Result.backups_are_authority,
        [string]$Result.requires_atomic_apply_rollback_executor,[string]$Result.requires_fresh_revalidation_before_apply,[string]$Result.requires_cleanup_if_not_applied,
        [string]$Result.apply_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_recovery_aware_stage_executor_head','qualified_recovery_aware_stage_executor_core_blob','qualified_generic_pre_apply_head','qualified_generic_pre_apply_core_blob','status',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','remote_commit_sha','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256',
        'recovery_pre_backup_admission_fingerprint','recovery_post_backup_admission_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint',
        'live_tree_sha256','stage_tree_sha256','binding_fingerprint','stage_path','stage_workspace_path','app_backup_root','app_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes',
        'persistence_backup_root','persistence_backup_path','persistence_fingerprint','prepared_at','post_backup_revalidated_at','backups_prepared','recovery_revalidated_before_backups','recovery_revalidated_after_backups',
        'session_key_accepted','session_key_persisted','session_key_exposed','preparation_is_authority','backups_are_authority','requires_atomic_apply_rollback_executor','requires_fresh_revalidation_before_apply','requires_cleanup_if_not_applied',
        'apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint'
    )){if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-pre-apply-result-field-missing-'+$f)}}}
    if([int]$Result.schema -ne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationSchema -or [string]$Result.managed_by -cne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationManagedBy -or [string]$Result.status -cne 'recovery-aware-pre-apply-backups-prepared-verified'){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-owner-schema-status-mismatch'}}
    if([string]$Result.qualified_recovery_aware_stage_executor_head -cne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorHead -or [string]$Result.qualified_recovery_aware_stage_executor_core_blob -cne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorCoreBlob -or [string]$Result.qualified_generic_pre_apply_head -cne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericHead -or [string]$Result.qualified_generic_pre_apply_core_blob -cne $CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','recovery_pre_backup_admission_fingerprint','recovery_post_backup_admission_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint','live_tree_sha256','stage_tree_sha256','binding_fingerprint','app_backup_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-pre-apply-result-invalid-'+$f)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-remote-commit-invalid'}}
    try{if([int64]$Result.github_repo_id -le 0 -or [int]$Result.app_backup_file_count -lt 1 -or [int64]$Result.app_backup_total_bytes -lt 1){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-count-or-repo-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-count-or-repo-invalid'}}
    foreach($f in @('backups_prepared','recovery_revalidated_before_backups','recovery_revalidated_after_backups','session_key_accepted','requires_atomic_apply_rollback_executor','requires_fresh_revalidation_before_apply','requires_cleanup_if_not_applied')){if(-not [bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-pre-apply-result-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','preparation_is_authority','backups_are_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-pre-apply-result-authority-escaped-'+$f)}}}
    $prepared=[DateTimeOffset]::MinValue;$post=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Result.prepared_at,[ref]$prepared) -or -not [DateTimeOffset]::TryParse([string]$Result.post_backup_revalidated_at,[ref]$post) -or $post -lt $prepared){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-time-invalid'}}
    $generic=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $Result
    $genericCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $generic
    if(-not [bool]$genericCheck.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-pre-apply-generic-result-invalid:'+[string]$genericCheck.reason)}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 (Get-CustomAppProductionRecoveryAwarePermitPreApplyResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-pre-apply-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-pre-apply-result-valid-zero-apply-authority';result_fingerprint=$expected;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitPreApplyPreparationV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$LifecycleStageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$RollbackBackupRoot,[Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[Nullable[DateTimeOffset]]$PostBackupNow=$null,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[bool]$Prepared=$false,[bool]$CleanupRequired=$false) New-CustomAppProductionRecoveryAwarePermitPreApplyDeniedV010 -Reason $Reason -BackupsPrepared $Prepared -CleanupRequired $CleanupRequired}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-pre-apply-session-key-too-short'}
    $stageCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('recovery-aware-pre-apply-stage-result-invalid:'+[string]$stageCheck.reason)}
    if(([string]$RecoveryAwareStageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-pre-apply-stage-name-mismatch'}
    if(([string]$RecoveryAwareStageExecutorResult.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-pre-apply-transaction-mismatch'}
    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$binding.ok){return & $deny ('recovery-aware-pre-apply-binding-denied:'+[string]$binding.reason)}
    foreach($pair in @(@('source_identity','source'),@('surface_kind','surface'),@('remote_commit_sha','commit_sha'),@('remote_tree_sha256','remote_tree_sha256'),@('binding_fingerprint','binding_fingerprint'))){
        if(([string]$RecoveryAwareStageExecutorResult.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$binding.($pair[1])).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-pre-apply-stage-binding-mismatch-'+$pair[0])}
    }
    try{if([int64]$RecoveryAwareStageExecutorResult.github_repo_id -ne [int64]$binding.repo_id){return & $deny 'recovery-aware-pre-apply-stage-binding-mismatch-github_repo_id'}}catch{return & $deny 'recovery-aware-pre-apply-stage-repo-id-invalid'}

    $freshPreLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshPreLive.ok){return & $deny ('recovery-aware-pre-apply-live-revalidation-denied:'+[string]$freshPreLive.reason)}
    if(([string]$RecoveryAwareStageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$freshPreLive.tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-pre-apply-stage-live-tree-continuity-mismatch'}

    $invokeRecoveryAdmission={param($Baseline,[DateTimeOffset]$At)
        Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $LifecycleStageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -RecoveryStoreDirectory $RecoveryStoreDirectory -ConsumptionStoreDirectory $ConsumptionStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -ConsumptionPersistenceResult $ConsumptionPersistenceResult -Permit $Permit -SessionKey $SessionKey -Now $At -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }
    $pre=& $invokeRecoveryAdmission $freshPreLive.baseline $Now
    if($null -eq $pre -or -not [bool]$pre.ok -or -not [bool]$pre.stage_acquisition_eligible -or $null -eq $pre.receipt){return & $deny ('recovery-aware-pre-apply-pre-backup-admission-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-pre-apply-pre-backup-admission-invalid:'+[string]$preCheck.reason)}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){
        if(([string]$RecoveryAwareStageExecutorResult.$f).Trim().ToLowerInvariant() -cne ([string]$pre.receipt.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-pre-apply-stage-admission-continuity-mismatch-'+$f)}
    }

    $genericStage=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 -RecoveryAwareResult $RecoveryAwareStageExecutorResult
    $genericStageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $genericStage
    if(-not [bool]$genericStageCheck.ok){return & $deny ('recovery-aware-pre-apply-generic-stage-bridge-invalid:'+[string]$genericStageCheck.reason)}
    $generic=$null
    try{
        $generic=Invoke-CustomAppProductionPreApplyPreparationV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$RecoveryAwareStageExecutorResult.consumption_id) -StageExecutorResult $genericStage -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -RollbackBackupRoot $RollbackBackupRoot -PersistenceBackupRoot $PersistenceBackupRoot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }catch{
        return & $deny ('recovery-aware-pre-apply-generic-preparation-threw:'+[string]$_.Exception.Message) $false $true
    }
    if($null -eq $generic -or -not [bool]$generic.ok -or $null -eq $generic.result){return & $deny ('recovery-aware-pre-apply-generic-preparation-denied:'+[string]$generic.reason) $false $true}
    $genericCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $generic.result
    if(-not [bool]$genericCheck.ok){return & $deny ('recovery-aware-pre-apply-generic-preparation-invalid:'+[string]$genericCheck.reason) $true $true}

    $postAt=$(if($null -ne $PostBackupNow){[DateTimeOffset]$PostBackupNow}else{[DateTimeOffset]::UtcNow})
    if($postAt -lt $Now){return & $deny 'recovery-aware-pre-apply-post-backup-time-before-pre-backup-time' $true $true}
    $freshPostLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshPostLive.ok){return & $deny ('recovery-aware-pre-apply-post-backup-live-revalidation-denied:'+[string]$freshPostLive.reason) $true $true}
    if(([string]$freshPostLive.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$generic.result.live_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-pre-apply-post-backup-live-tree-continuity-mismatch' $true $true}
    $post=& $invokeRecoveryAdmission $freshPostLive.baseline $postAt
    if($null -eq $post -or -not [bool]$post.ok -or -not [bool]$post.stage_acquisition_eligible -or $null -eq $post.receipt){return & $deny ('recovery-aware-pre-apply-post-backup-admission-denied:'+[string]$post.reason) $true $true}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $post.receipt -Now $postAt
    if(-not [bool]$postCheck.ok){return & $deny ('recovery-aware-pre-apply-post-backup-admission-invalid:'+[string]$postCheck.reason) $true $true}
    foreach($f in @('name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','binding_fingerprint')){
        if(([string]$pre.receipt.$f).Trim().ToLowerInvariant() -cne ([string]$post.receipt.$f).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-pre-apply-post-backup-admission-continuity-drift-'+$f) $true $true}
    }

    $g=$generic.result
    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationSchema;managed_by=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationManagedBy
        qualified_recovery_aware_stage_executor_head=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorHead;qualified_recovery_aware_stage_executor_core_blob=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedStageExecutorCoreBlob
        qualified_generic_pre_apply_head=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericHead;qualified_generic_pre_apply_core_blob=$CustomAppProductionRecoveryAwarePermitPreApplyPreparationQualifiedGenericCoreBlob
        status='recovery-aware-pre-apply-backups-prepared-verified'
        name=$Name;source_identity=([string]$RecoveryAwareStageExecutorResult.source_identity).Trim().ToLowerInvariant();transaction_id=$ExpectedTransactionId.Trim().ToLowerInvariant()
        github_repo_id=[int64]$RecoveryAwareStageExecutorResult.github_repo_id;surface_kind=([string]$RecoveryAwareStageExecutorResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$RecoveryAwareStageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$RecoveryAwareStageExecutorResult.consumption_id).Trim().ToLowerInvariant();consumption_persistence_fingerprint=([string]$RecoveryAwareStageExecutorResult.consumption_persistence_fingerprint).Trim().ToLowerInvariant()
        historical_consumption_envelope_sha256=([string]$RecoveryAwareStageExecutorResult.historical_consumption_envelope_sha256).Trim().ToLowerInvariant()
        recovery_pre_backup_admission_fingerprint=([string]$pre.receipt.admission_fingerprint).Trim().ToLowerInvariant();recovery_post_backup_admission_fingerprint=([string]$post.receipt.admission_fingerprint).Trim().ToLowerInvariant()
        recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();generic_stage_result_fingerprint=([string]$genericStage.result_fingerprint).Trim().ToLowerInvariant()
        generic_preparation_fingerprint=([string]$g.preparation_fingerprint).Trim().ToLowerInvariant();generic_pre_apply_admission_fingerprint=([string]$g.pre_apply_admission_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$g.live_tree_sha256).Trim().ToLowerInvariant();stage_tree_sha256=([string]$g.stage_tree_sha256).Trim().ToLowerInvariant();binding_fingerprint=([string]$g.binding_fingerprint).Trim().ToLowerInvariant()
        stage_path=[string]$g.stage_path;stage_workspace_path=[string]$g.stage_workspace_path
        app_backup_root=[string]$g.app_backup_root;app_backup_path=[string]$g.app_backup_path;app_backup_tree_sha256=([string]$g.app_backup_tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$g.app_backup_file_count;app_backup_total_bytes=[int64]$g.app_backup_total_bytes
        persistence_backup_root=[string]$g.persistence_backup_root;persistence_backup_path=[string]$g.persistence_backup_path;persistence_fingerprint=([string]$g.persistence_fingerprint).Trim().ToLowerInvariant()
        prepared_at=[string]$g.prepared_at;post_backup_revalidated_at=$postAt.ToUniversalTime().ToString('o')
        backups_prepared=$true;recovery_revalidated_before_backups=$true;recovery_revalidated_after_backups=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;preparation_is_authority=$false;backups_are_authority=$false
        requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 (Get-CustomAppProductionRecoveryAwarePermitPreApplyResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $result
    if(-not [bool]$check.ok){return & $deny ('recovery-aware-pre-apply-output-invalid:'+[string]$check.reason) $true $true}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-pre-apply-backups-prepared-verified-zero-apply-authority';result=$result;backups_prepared=$true;recovery_revalidated_before_backups=$true;recovery_revalidated_after_backups=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;preparation_is_authority=$false;backups_are_authority=$false
        requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
