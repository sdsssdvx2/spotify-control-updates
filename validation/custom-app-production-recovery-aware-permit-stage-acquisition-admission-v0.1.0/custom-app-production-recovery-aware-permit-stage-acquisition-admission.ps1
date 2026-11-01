$CustomAppProductionRecoveryAwarePermitStageAdmissionSchema = 1
$CustomAppProductionRecoveryAwarePermitStageAdmissionManagedBy = 'custom-app-production-recovery-aware-permit-stage-acquisition-admission-v1'
$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartHead = 'b8f7267519a6f09ccb7b2948a319b6c2cde73205'
$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartCoreBlob = '2942f9422bdc2681435cc695a18a5cd1340a0ea5'
$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageHead = 'c420a1df6f306c7ba74772b91241cb14abd04738'
$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageCoreBlob = 'e2f2fc656235883d2a82b106289973f6ded409a5'

function Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitStageAdmissionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;decision=$null;stage_acquisition_eligible=$false
        recovery_aware_executor_start_revalidated=$false;stage_binding_attested=$false;stage_workspace_bound=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false;admission_is_authority=$false
        requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_recovery_aware_executor_start_head,[string]$Receipt.qualified_recovery_aware_executor_start_core_blob,
        [string]$Receipt.qualified_stage_contract_head,[string]$Receipt.qualified_stage_contract_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.consumption_id,[string]$Receipt.consumption_persistence_fingerprint,[string]$Receipt.historical_consumption_envelope_sha256,
        [string]$Receipt.pre_stage_executor_start_fingerprint,[string]$Receipt.post_stage_executor_start_fingerprint,
        [string]$Receipt.binding_fingerprint,[string]$Receipt.stage_workspace_root,
        [string]$Receipt.evaluated_at,[string]$Receipt.stage_eligibility_expires_at,[string]$Receipt.stage_acquisition_eligible,
        [string]$Receipt.recovery_aware_executor_start_revalidated,[string]$Receipt.stage_binding_attested,[string]$Receipt.stage_workspace_bound,
        [string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,[string]$Receipt.admission_is_authority,
        [string]$Receipt.requires_immediate_gate_rerun_by_stage_executor,[string]$Receipt.requires_exact_stage_contract,[string]$Receipt.requires_fresh_revalidation_after_stage,[string]$Receipt.requires_fresh_revalidation_before_apply,
        [string]$Receipt.stage_acquisition_authorized,[string]$Receipt.live_destination_authorized,[string]$Receipt.apply_authorized,
        [string]$Receipt.executor_may_start,[string]$Receipt.executor_may_stage,[string]$Receipt.executor_may_apply,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-receipt-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_recovery_aware_executor_start_head','qualified_recovery_aware_executor_start_core_blob','qualified_stage_contract_head','qualified_stage_contract_core_blob',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256',
        'pre_stage_executor_start_fingerprint','post_stage_executor_start_fingerprint','binding_fingerprint','stage_workspace_root','evaluated_at','stage_eligibility_expires_at','stage_acquisition_eligible',
        'recovery_aware_executor_start_revalidated','stage_binding_attested','stage_workspace_bound','session_key_accepted','session_key_persisted','session_key_exposed','admission_is_authority',
        'requires_immediate_gate_rerun_by_stage_executor','requires_exact_stage_contract','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply',
        'stage_acquisition_authorized','live_destination_authorized','apply_authorized','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','admission_fingerprint'
    )){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-stage-admission-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitStageAdmissionSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitStageAdmissionManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_recovery_aware_executor_start_head -cne $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartHead -or [string]$Receipt.qualified_recovery_aware_executor_start_core_blob -cne $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartCoreBlob -or [string]$Receipt.qualified_stage_contract_head -cne $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageHead -or [string]$Receipt.qualified_stage_contract_core_blob -cne $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_persistence_fingerprint','historical_consumption_envelope_sha256','pre_stage_executor_start_fingerprint','post_stage_executor_start_fingerprint','binding_fingerprint','admission_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-stage-admission-invalid-'+$f)}}}
    if(([string]$Receipt.pre_stage_executor_start_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_stage_executor_start_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-executor-start-drift'}}
    foreach($f in @('stage_acquisition_eligible','recovery_aware_executor_start_revalidated','stage_binding_attested','stage_workspace_bound','session_key_accepted','requires_immediate_gate_rerun_by_stage_executor','requires_exact_stage_contract','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-stage-admission-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','admission_is_authority','stage_acquisition_authorized','live_destination_authorized','apply_authorized','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-stage-admission-authority-escaped-'+$f)}}}
    try{$repo=[int64]$Receipt.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-repo-id-invalid'}}
    if($repo -le 0){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-repo-id-invalid'}}
    try{$workspace=[IO.Path]::GetFullPath([string]$Receipt.stage_workspace_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$expectedWorkspace=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-workspace-root-invalid'}}
    if(-not $workspace.Equals($expectedWorkspace,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-workspace-root-drift'}}
    $evaluated=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.evaluated_at,[ref]$evaluated) -or -not [DateTimeOffset]::TryParse([string]$Receipt.stage_eligibility_expires_at,[ref]$expires)){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-time-invalid'}}
    if($expires -le $evaluated -or $expires -gt $evaluated.AddSeconds(5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-window-invalid'}}
    if($Now -lt $evaluated.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-not-yet-valid'}}
    if($Now -ge $expires){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-expired'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-stage-acquisition-eligible-zero-authority';admission_fingerprint=$expected;production_mutation_authorized=$false}
}

function Test-CustomAppProductionRecoveryAwarePermitStageBindingContinuityV010 {
    param([AllowNull()]$StartDecision,[AllowNull()]$StageBinding)
    if($null -eq $StartDecision -or $null -eq $StageBinding){return [pscustomobject]@{ok=$false;reason='recovery-aware-stage-binding-continuity-null'}}
    foreach($pair in @(@('name','name'),@('source_identity','source'),@('github_repo_id','repo_id'),@('surface_kind','surface'),@('remote_tree_sha256','remote_tree_sha256'),@('remote_commit_sha','commit_sha'))){
        $a=([string]$StartDecision.($pair[0])).Trim().ToLowerInvariant();$b=([string]$StageBinding.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-stage-start-binding-'+$pair[0]+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-stage-start-binding-continuity-exact'}
}

function Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitStageAdmissionDeniedV010 -Reason $Reason}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-stage-admission-session-key-too-short'}
    $invokeStart={param([DateTimeOffset]$At)
        Resolve-CustomAppProductionRecoveryAwarePermitExecutorStartGateV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -RecoveryStoreDirectory $RecoveryStoreDirectory -ConsumptionStoreDirectory $ConsumptionStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -ConsumptionPersistenceResult $ConsumptionPersistenceResult -Permit $Permit -SessionKey $SessionKey -Now $At -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }
    $pre=& $invokeStart $Now
    if($null -eq $pre -or -not [bool]$pre.ok -or -not [bool]$pre.staging_eligible -or $null -eq $pre.receipt -or $null -eq $pre.decision){return & $deny ('recovery-aware-stage-admission-pre-start-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-stage-admission-pre-start-invalid:'+[string]$preCheck.reason)}
    $stageBinding=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$stageBinding.ok){return & $deny ('recovery-aware-stage-admission-stage-binding-denied:'+[string]$stageBinding.reason)}
    $continuity=Test-CustomAppProductionRecoveryAwarePermitStageBindingContinuityV010 -StartDecision $pre.decision -StageBinding $stageBinding
    if(-not [bool]$continuity.ok){return & $deny ([string]$continuity.reason)}
    try{$workspace=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return & $deny 'recovery-aware-stage-admission-workspace-root-invalid'}
    $post=& $invokeStart $Now
    if($null -eq $post -or -not [bool]$post.ok -or -not [bool]$post.staging_eligible -or $null -eq $post.receipt){return & $deny ('recovery-aware-stage-admission-post-start-denied:'+[string]$post.reason)}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not [bool]$postCheck.ok){return & $deny ('recovery-aware-stage-admission-post-start-invalid:'+[string]$postCheck.reason)}
    if(([string]$pre.receipt.start_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.start_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-stage-admission-executor-start-drift'}
    $preExpiry=[DateTimeOffset]::MinValue;$postExpiry=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$pre.receipt.staging_eligibility_expires_at,[ref]$preExpiry) -or -not [DateTimeOffset]::TryParse([string]$post.receipt.staging_eligibility_expires_at,[ref]$postExpiry)){return & $deny 'recovery-aware-stage-admission-parent-expiry-invalid'}
    $expires=$Now.AddSeconds(5);if($preExpiry -lt $expires){$expires=$preExpiry};if($postExpiry -lt $expires){$expires=$postExpiry};if($expires -le $Now){return & $deny 'recovery-aware-stage-admission-window-empty'}
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitStageAdmissionSchema;managed_by=$CustomAppProductionRecoveryAwarePermitStageAdmissionManagedBy
        qualified_recovery_aware_executor_start_head=$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartHead;qualified_recovery_aware_executor_start_core_blob=$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartCoreBlob
        qualified_stage_contract_head=$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageHead;qualified_stage_contract_core_blob=$CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageCoreBlob
        name=[string]$pre.receipt.name;source_identity=([string]$pre.receipt.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$pre.receipt.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$pre.receipt.github_repo_id;surface_kind=([string]$pre.receipt.surface_kind).Trim().ToLowerInvariant()
        consumption_id=([string]$pre.receipt.consumption_id).Trim().ToLowerInvariant();consumption_persistence_fingerprint=([string]$pre.receipt.consumption_persistence_fingerprint).Trim().ToLowerInvariant();historical_consumption_envelope_sha256=([string]$pre.receipt.historical_persistence_envelope_sha256).Trim().ToLowerInvariant()
        pre_stage_executor_start_fingerprint=([string]$pre.receipt.start_fingerprint).Trim().ToLowerInvariant();post_stage_executor_start_fingerprint=([string]$post.receipt.start_fingerprint).Trim().ToLowerInvariant();binding_fingerprint=([string]$stageBinding.binding_fingerprint).Trim().ToLowerInvariant();stage_workspace_root=$workspace
        evaluated_at=$Now.ToUniversalTime().ToString('o');stage_eligibility_expires_at=$expires.ToUniversalTime().ToString('o');stage_acquisition_eligible=$true;admission_fingerprint=$null
        recovery_aware_executor_start_revalidated=$true;stage_binding_attested=$true;stage_workspace_bound=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;admission_is_authority=$false
        requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $receipt.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $receipt)
    $check=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $receipt -Now $Now
    if(-not [bool]$check.ok){return & $deny ('recovery-aware-stage-admission-output-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-persisted-consumption-stage-acquisition-eligible-zero-authority';receipt=$receipt;decision=$receipt;stage_acquisition_eligible=$true
        recovery_aware_executor_start_revalidated=$true;stage_binding_attested=$true;stage_workspace_bound=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;admission_is_authority=$false
        requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
