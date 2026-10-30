$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSchema = 1
$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationManagedBy = 'custom-app-production-recovery-completion-retirement-admission-integration-v1'
$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedCompletionHead = '6d0e964307aaf0c0a8aeece98d5597e81721538e'
$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedAdmissionHead = '16cac85b7bde1b652be67e8d657136409ec7f8b9'

function Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationPathEqualV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    return (Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 -A $A -B $B)
}

function Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_completion_head,[string]$Receipt.qualified_retirement_admission_head,
        [string]$Receipt.transaction_id,[string]$Receipt.completion_fingerprint,[string]$Receipt.executor_result_fingerprint,[string]$Receipt.retirement_admission_fingerprint,[string]$Receipt.evidence_fingerprint,
        [string]$Receipt.rollback_complete_revision,[string]$Receipt.rollback_complete_entry_sha256,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.remote_commit_sha,[string]$Receipt.consumption_id,[string]$Receipt.preparation_fingerprint,
        [string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.stage_workspace_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,
        [string]$Receipt.live_tree_sha256,[string]$Receipt.persistence_fingerprint,
        [string]$Receipt.transaction_status,[string]$Receipt.transaction_old_status,[string]$Receipt.transaction_candidate_status,[string]$Receipt.stage_status,[string]$Receipt.app_backup_status,[string]$Receipt.persistence_backup_status,
        [string]$Receipt.retirement_needed,[string]$Receipt.retirement_eligible,[string]$Receipt.retirement_already_complete,[string]$Receipt.requires_bounded_artifact_retirement,[string]$Receipt.requires_new_update_permit,
        [string]$Receipt.durable_completion_reloaded,[string]$Receipt.embedded_restore_result_revalidated,[string]$Receipt.fresh_retirement_admission_revalidated,[string]$Receipt.requires_future_executor_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.integration_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-receipt-null'}}
    $required=@('schema','managed_by','qualified_completion_head','qualified_retirement_admission_head','transaction_id','completion_fingerprint','executor_result_fingerprint','retirement_admission_fingerprint','evidence_fingerprint','rollback_complete_revision','rollback_complete_entry_sha256','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','live_tree_sha256','persistence_fingerprint','transaction_status','transaction_old_status','transaction_candidate_status','stage_status','app_backup_status','persistence_backup_status','retirement_needed','retirement_eligible','retirement_already_complete','requires_bounded_artifact_retirement','requires_new_update_permit','durable_completion_reloaded','embedded_restore_result_revalidated','fresh_retirement_admission_revalidated','requires_future_executor_fresh_revalidation','checked_at','eligible_until','integration_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','integration_fingerprint')
    foreach($f in $required){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne1-or[string]$Receipt.managed_by-cne$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationManagedBy-or[string]$Receipt.qualified_completion_head-cne$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedCompletionHead-or[string]$Receipt.qualified_retirement_admission_head-cne$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedAdmissionHead){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-owner-schema-parent-invalid'}}
    foreach($f in @('transaction_id','completion_fingerprint','executor_result_fingerprint','retirement_admission_fingerprint','evidence_fingerprint','rollback_complete_entry_sha256','consumption_id','preparation_fingerprint','live_tree_sha256','persistence_fingerprint','integration_fingerprint')){if(-not(Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-invalid-'+$f)}}}
    if(([string]$Receipt.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$' -or [int64]$Receipt.rollback_complete_revision-lt1){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-identity-or-revision-invalid'}}
    foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){if([string]$Receipt.$f-notin@('present-verified','already-absent')){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-status-invalid-'+$f)}}}
    foreach($f in @('transaction_old_status','transaction_candidate_status')){if([string]$Receipt.$f-notin@('present-verified','absent')){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-status-invalid-'+$f)}}}
    if([string]$Receipt.transaction_status-ceq'already-absent' -and ([string]$Receipt.transaction_old_status-cne'absent' -or [string]$Receipt.transaction_candidate_status-cne'absent')){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-transaction-child-status-drift'}}
    foreach($f in @('durable_completion_reloaded','embedded_restore_result_revalidated','fresh_retirement_admission_revalidated','requires_future_executor_fresh_revalidation','requires_new_update_permit')){if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-required-flag-false-'+$f)}}}
    foreach($f in @('integration_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-completion-retirement-integration-authority-escaped-'+$f)}}}
    $needed=([string]$Receipt.transaction_status-ceq'present-verified' -or [string]$Receipt.stage_status-ceq'present-verified' -or [string]$Receipt.app_backup_status-ceq'present-verified' -or [string]$Receipt.persistence_backup_status-ceq'present-verified')
    if([bool]$Receipt.retirement_needed-ne[bool]$needed){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-semantic-status-drift'}}
    if($needed){if(-not[bool]$Receipt.retirement_eligible-or[bool]$Receipt.retirement_already_complete-or-not[bool]$Receipt.requires_bounded_artifact_retirement){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-needed-semantics-invalid'}}}
    else{if([bool]$Receipt.retirement_eligible-or-not[bool]$Receipt.retirement_already_complete-or[bool]$Receipt.requires_bounded_artifact_retirement){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-complete-semantics-invalid'}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-window-invalid'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-expired'}}
    $expected=Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010 (Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.integration_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-completion-retirement-integration-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-completion-retirement-integration-valid-zero-authority';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();retirement_needed=[bool]$needed;retirement_eligible=[bool]$Receipt.retirement_eligible}
}

function Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;integration_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not(Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010 $tx)){return & $deny 'recovery-completion-retirement-integration-transaction-id-invalid'}

    $completion=Read-CustomAppProductionRecoveryCompletionEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -Now $Now
    if($null-eq$completion-or-not[bool]$completion.ok){return & $deny ('recovery-completion-retirement-integration-completion-read-denied:'+[string]$completion.reason)}
    if(-not[bool]$completion.reloaded_from_persistent_store-or$null-eq$completion.envelope){return & $deny 'recovery-completion-retirement-integration-completion-not-durable'}
    $ce=$completion.envelope
    $cc=Test-CustomAppProductionRecoveryCompletionEvidenceEnvelopeV010 -Envelope $ce -Now $Now
    if(-not[bool]$cc.ok){return & $deny ('recovery-completion-retirement-integration-completion-invalid:'+[string]$cc.reason)}
    if(-not[bool]$ce.executor_result_embedded-or-not[bool]$ce.retirement_admission_required-or-not[bool]$ce.requires_future_fresh_revalidation){return & $deny 'recovery-completion-retirement-integration-completion-contract-invalid'}
    $restore=$ce.executor_result
    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $restore
    if(-not[bool]$rc.ok){return & $deny ('recovery-completion-retirement-integration-embedded-restore-invalid:'+[string]$rc.reason)}
    if(([string]$ce.executor_result_fingerprint).Trim().ToLowerInvariant()-cne([string]$restore.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-retirement-integration-embedded-restore-fingerprint-mismatch'}

    $admission=Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -RestoreExecutorResult $restore -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if($null-eq$admission-or-not[bool]$admission.ok){return & $deny ('recovery-completion-retirement-integration-fresh-admission-denied:'+[string]$admission.reason)}
    $ar=$admission.receipt
    $ac=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $ar -Now $Now
    if(-not[bool]$ac.ok){return & $deny ('recovery-completion-retirement-integration-fresh-admission-invalid:'+[string]$ac.reason)}

    $pairs=@(
        @('transaction_id','transaction_id'),@('name','name'),@('source_identity','source_identity'),@('remote_commit_sha','remote_commit_sha'),@('consumption_id','consumption_id'),@('preparation_fingerprint','preparation_fingerprint'),@('recovery_evidence_fingerprint','evidence_fingerprint'),@('executor_result_fingerprint','restore_result_fingerprint'),@('rollback_complete_revision','journal_revision'),@('rollback_complete_entry_sha256','journal_entry_sha256'),@('live_tree_sha256','live_tree_sha256'),@('persistence_fingerprint','persistence_fingerprint')
    )
    foreach($p in $pairs){$left=[string]$ce.($p[0]);$right=[string]$ar.($p[1]);if($left.Trim().ToLowerInvariant()-cne$right.Trim().ToLowerInvariant()){return & $deny ('recovery-completion-retirement-integration-continuity-mismatch-'+[string]$p[0])}}
    foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){if(-not(Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationPathEqualV010 -A ([string]$ce.$f) -B ([string]$ar.$f))){return & $deny ('recovery-completion-retirement-integration-path-mismatch-'+$f)}}
    if(([string]$completion.completion_fingerprint).Trim().ToLowerInvariant()-cne([string]$ce.completion_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-retirement-integration-completion-fingerprint-return-mismatch'}

    $receipt=[pscustomobject]@{
        schema=1;managed_by=$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationManagedBy;qualified_completion_head=$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedCompletionHead;qualified_retirement_admission_head=$CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationQualifiedAdmissionHead
        transaction_id=$tx;completion_fingerprint=([string]$ce.completion_fingerprint).Trim().ToLowerInvariant();executor_result_fingerprint=([string]$ce.executor_result_fingerprint).Trim().ToLowerInvariant();retirement_admission_fingerprint=([string]$ar.receipt_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=([string]$ce.recovery_evidence_fingerprint).Trim().ToLowerInvariant()
        rollback_complete_revision=[int64]$ce.rollback_complete_revision;rollback_complete_entry_sha256=([string]$ce.rollback_complete_entry_sha256).Trim().ToLowerInvariant()
        name=([string]$ce.name).Trim().ToLowerInvariant();source_identity=([string]$ce.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$ce.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$ce.consumption_id).Trim().ToLowerInvariant();preparation_fingerprint=([string]$ce.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$ce.live_path;transaction_root=[string]$ce.transaction_root;stage_workspace_path=[string]$ce.stage_workspace_path;app_backup_path=[string]$ce.app_backup_path;persistence_backup_path=[string]$ce.persistence_backup_path
        live_tree_sha256=([string]$ce.live_tree_sha256).Trim().ToLowerInvariant();persistence_fingerprint=([string]$ce.persistence_fingerprint).Trim().ToLowerInvariant()
        transaction_status=[string]$ar.transaction_status;transaction_old_status=[string]$ar.transaction_old_status;transaction_candidate_status=[string]$ar.transaction_candidate_status;stage_status=[string]$ar.stage_status;app_backup_status=[string]$ar.app_backup_status;persistence_backup_status=[string]$ar.persistence_backup_status
        retirement_needed=[bool]$ar.retirement_needed;retirement_eligible=[bool]$ar.retirement_eligible;retirement_already_complete=[bool]$ar.retirement_already_complete;requires_bounded_artifact_retirement=[bool]$ar.requires_bounded_artifact_retirement;requires_new_update_permit=$true
        durable_completion_reloaded=$true;embedded_restore_result_revalidated=$true;fresh_retirement_admission_revalidated=$true;requires_future_executor_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        integration_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;integration_fingerprint=$null
    }
    $receipt.integration_fingerprint=Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationSha256V010 (Get-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationMaterialV010 -Receipt $receipt)
    $check=Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 -Receipt $receipt -Now $Now
    if(-not[bool]$check.ok){return & $deny ('recovery-completion-retirement-integration-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='recovery-completion-retirement-integrated-zero-authority';receipt=$receipt;completion=$ce;embedded_restore_result=$restore;retirement_admission=$ar;integration_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
