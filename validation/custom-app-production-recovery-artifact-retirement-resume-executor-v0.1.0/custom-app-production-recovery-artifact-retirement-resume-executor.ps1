$CustomAppProductionRecoveryArtifactRetirementResumeExecutorSchema = 1
$CustomAppProductionRecoveryArtifactRetirementResumeExecutorManagedBy = 'custom-app-production-recovery-artifact-retirement-resume-executor-v1'
$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedBridgeHead = '894c5013df0a2f1c17483425a31f49d0f9eaa99d'
$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedExecutorHead = '3867ceeb56e5c21f0047946af87fb69f6601ef37'

function Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_bridge_head,[string]$Result.qualified_retirement_executor_head,
        [string]$Result.status,[string]$Result.reason,[string]$Result.transaction_id,[string]$Result.name,[string]$Result.source_identity,[string]$Result.remote_commit_sha,[string]$Result.consumption_id,[string]$Result.preparation_fingerprint,
        [string]$Result.completion_fingerprint,[string]$Result.evidence_fingerprint,[string]$Result.embedded_restore_result_fingerprint,[string]$Result.initial_bridge_fingerprint,[string]$Result.retirement_executor_result_fingerprint,[string]$Result.final_bridge_fingerprint,
        [string]$Result.rollback_complete_revision,[string]$Result.rollback_complete_entry_sha256,[string]$Result.live_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.transaction_action,[string]$Result.stage_action,[string]$Result.app_backup_action,[string]$Result.persistence_backup_action,
        [string]$Result.retirement_performed,[string]$Result.initially_already_complete,[string]$Result.artifact_retirement_complete,[string]$Result.durable_completion_reloaded_before,[string]$Result.durable_completion_reloaded_after,[string]$Result.embedded_restore_result_revalidated_before,[string]$Result.embedded_restore_result_revalidated_after,[string]$Result.fresh_retirement_admission_revalidated_before,[string]$Result.fresh_retirement_admission_revalidated_after,[string]$Result.retirement_executor_result_revalidated,[string]$Result.journal_retained,[string]$Result.recovery_evidence_retained,[string]$Result.completion_evidence_retained,[string]$Result.requires_new_update_permit,[string]$Result.requires_future_fresh_revalidation,[string]$Result.completed_at,
        [string]$Result.result_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-null'}}
    foreach($f in @('schema','managed_by','qualified_bridge_head','qualified_retirement_executor_head','status','reason','transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','completion_fingerprint','evidence_fingerprint','embedded_restore_result_fingerprint','initial_bridge_fingerprint','retirement_executor_result_fingerprint','final_bridge_fingerprint','rollback_complete_revision','rollback_complete_entry_sha256','live_tree_sha256','persistence_fingerprint','transaction_action','stage_action','app_backup_action','persistence_backup_action','retirement_performed','initially_already_complete','artifact_retirement_complete','durable_completion_reloaded_before','durable_completion_reloaded_after','embedded_restore_result_revalidated_before','embedded_restore_result_revalidated_after','fresh_retirement_admission_revalidated_before','fresh_retirement_admission_revalidated_after','retirement_executor_result_revalidated','journal_retained','recovery_evidence_retained','completion_evidence_retained','requires_new_update_permit','requires_future_fresh_revalidation','completed_at','result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','result_fingerprint')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-result-field-missing-'+$f)}}}
    if([int]$Result.schema-ne1-or[string]$Result.managed_by-cne$CustomAppProductionRecoveryArtifactRetirementResumeExecutorManagedBy-or[string]$Result.qualified_bridge_head-cne$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedBridgeHead-or[string]$Result.qualified_retirement_executor_head-cne$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedExecutorHead){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-owner-schema-parent-invalid'}}
    if([string]$Result.status-cne'recovery-artifact-retirement-resume-complete' -or [string]$Result.reason-cne'durable-completion-bounded-retirement-resume-complete'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-status-invalid'}}
    foreach($f in @('transaction_id','consumption_id','preparation_fingerprint','completion_fingerprint','evidence_fingerprint','embedded_restore_result_fingerprint','initial_bridge_fingerprint','retirement_executor_result_fingerprint','final_bridge_fingerprint','rollback_complete_entry_sha256','live_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-result-invalid-'+$f)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-remote-commit-invalid'}}
    try{if([int64]$Result.rollback_complete_revision-lt1){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-revision-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-revision-invalid'}}
    foreach($f in @('transaction_action','stage_action','app_backup_action','persistence_backup_action')){if([string]$Result.$f-notin@('deleted-now','already-absent')){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-result-action-invalid-'+$f)}}}
    foreach($f in @('artifact_retirement_complete','durable_completion_reloaded_before','durable_completion_reloaded_after','embedded_restore_result_revalidated_before','embedded_restore_result_revalidated_after','fresh_retirement_admission_revalidated_before','fresh_retirement_admission_revalidated_after','retirement_executor_result_revalidated','journal_retained','recovery_evidence_retained','completion_evidence_retained','requires_new_update_permit','requires_future_fresh_revalidation')){if(-not[bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-result-required-flag-false-'+$f)}}}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-result-authority-escaped-'+$f)}}}
    $didDelete=([string]$Result.transaction_action-ceq'deleted-now'-or[string]$Result.stage_action-ceq'deleted-now'-or[string]$Result.app_backup_action-ceq'deleted-now'-or[string]$Result.persistence_backup_action-ceq'deleted-now')
    if([bool]$Result.retirement_performed-ne[bool]$didDelete){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-action-semantics-drift'}}
    if([bool]$Result.initially_already_complete-and$didDelete){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-complete-state-mutated'}}
    $when=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Result.completed_at,[ref]$when)){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-resume-executor-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-artifact-retirement-resume-executor-result-valid-zero-authority';transaction_id=([string]$Result.transaction_id).Trim().ToLowerInvariant();result_fingerprint=$expected}
}
function Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorBridgeContinuityV010 {
    param([Parameter(Mandatory=$true)]$Initial,[Parameter(Mandatory=$true)]$Final)
    foreach($f in @('transaction_id','completion_fingerprint','executor_result_fingerprint','evidence_fingerprint','rollback_complete_revision','rollback_complete_entry_sha256','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','live_tree_sha256','persistence_fingerprint')){if(([string]$Initial.$f).Trim().ToLowerInvariant()-cne([string]$Final.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-resume-executor-bridge-continuity-mismatch-'+$f)}}}
    return [pscustomobject]@{ok=$true;reason='recovery-artifact-retirement-resume-executor-bridge-continuity-exact'}
}
function Invoke-CustomAppProductionRecoveryArtifactRetirementResumeExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;artifact_retirement_complete=$false;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 $tx)){return & $deny 'recovery-artifact-retirement-resume-executor-transaction-id-invalid'}

    $initial=Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if($null-eq$initial-or-not[bool]$initial.ok){return & $deny ('recovery-artifact-retirement-resume-executor-initial-bridge-denied:'+[string]$initial.reason)}
    $ic=Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 -Receipt $initial.receipt -Now $Now
    if(-not[bool]$ic.ok){return & $deny ('recovery-artifact-retirement-resume-executor-initial-bridge-invalid:'+[string]$ic.reason)}
    if(-not[bool]$initial.receipt.requires_new_update_permit-or-not[bool]$initial.receipt.requires_future_executor_fresh_revalidation){return & $deny 'recovery-artifact-retirement-resume-executor-initial-bridge-lifecycle-contract-invalid'}

    $restore=$initial.embedded_restore_result
    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $restore
    if(-not[bool]$rc.ok){return & $deny ('recovery-artifact-retirement-resume-executor-embedded-restore-invalid:'+[string]$rc.reason)}
    if(([string]$restore.result_fingerprint).Trim().ToLowerInvariant()-cne([string]$initial.receipt.executor_result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-artifact-retirement-resume-executor-embedded-restore-fingerprint-mismatch'}

    $execAt=$Now.AddMilliseconds(10)
    $exec=Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -RestoreExecutorResult $restore -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $execAt
    if($null-eq$exec-or-not[bool]$exec.ok){return & $deny ('recovery-artifact-retirement-resume-executor-bounded-executor-denied:'+[string]$exec.reason)}
    $er=$exec.result
    $ec=Test-CustomAppProductionRecoveryArtifactRetirementExecutorResultV010 -Result $er
    if(-not[bool]$ec.ok){return & $deny ('recovery-artifact-retirement-resume-executor-bounded-executor-result-invalid:'+[string]$ec.reason)}
    foreach($p in @(@('transaction_id','transaction_id'),@('name','name'),@('source_identity','source_identity'),@('remote_commit_sha','remote_commit_sha'),@('consumption_id','consumption_id'),@('preparation_fingerprint','preparation_fingerprint'),@('evidence_fingerprint','evidence_fingerprint'),@('executor_result_fingerprint','restore_result_fingerprint'),@('rollback_complete_revision','journal_revision'),@('rollback_complete_entry_sha256','journal_entry_sha256'),@('live_tree_sha256','live_tree_sha256'),@('persistence_fingerprint','persistence_fingerprint'))){if(([string]$initial.receipt.($p[0])).Trim().ToLowerInvariant()-cne([string]$er.($p[1])).Trim().ToLowerInvariant()){return & $deny ('recovery-artifact-retirement-resume-executor-result-continuity-mismatch-'+[string]$p[0])}}
    if(-not[bool]$er.artifact_retirement_complete-or-not[bool]$er.journal_retained-or-not[bool]$er.recovery_evidence_retained-or-not[bool]$er.requires_new_update_permit-or-not[bool]$er.requires_future_fresh_revalidation){return & $deny 'recovery-artifact-retirement-resume-executor-bounded-executor-lifecycle-contract-invalid'}

    $finalAt=$Now.AddSeconds(1)
    $final=Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $finalAt
    if($null-eq$final-or-not[bool]$final.ok){return & $deny ('recovery-artifact-retirement-resume-executor-final-bridge-denied:'+[string]$final.reason)}
    $fc=Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 -Receipt $final.receipt -Now $finalAt
    if(-not[bool]$fc.ok){return & $deny ('recovery-artifact-retirement-resume-executor-final-bridge-invalid:'+[string]$fc.reason)}
    $cont=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorBridgeContinuityV010 -Initial $initial.receipt -Final $final.receipt
    if(-not[bool]$cont.ok){return & $deny ([string]$cont.reason)}
    if([bool]$final.receipt.retirement_needed-or[bool]$final.receipt.retirement_eligible-or-not[bool]$final.receipt.retirement_already_complete-or[bool]$final.receipt.requires_bounded_artifact_retirement){return & $deny 'recovery-artifact-retirement-resume-executor-final-bridge-not-complete'}
    foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){if([string]$final.receipt.$f-cne'already-absent'){return & $deny ('recovery-artifact-retirement-resume-executor-final-artifact-not-absent-'+$f)}}
    if(-not[bool]$final.receipt.requires_new_update_permit-or-not[bool]$final.receipt.durable_completion_reloaded-or-not[bool]$final.receipt.embedded_restore_result_revalidated-or-not[bool]$final.receipt.fresh_retirement_admission_revalidated-or-not[bool]$final.receipt.requires_future_executor_fresh_revalidation){return & $deny 'recovery-artifact-retirement-resume-executor-final-bridge-lifecycle-contract-invalid'}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryArtifactRetirementResumeExecutorSchema;managed_by=$CustomAppProductionRecoveryArtifactRetirementResumeExecutorManagedBy;qualified_bridge_head=$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedBridgeHead;qualified_retirement_executor_head=$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedExecutorHead
        status='recovery-artifact-retirement-resume-complete';reason='durable-completion-bounded-retirement-resume-complete';transaction_id=$tx;name=[string]$final.receipt.name;source_identity=[string]$final.receipt.source_identity;remote_commit_sha=[string]$final.receipt.remote_commit_sha;consumption_id=[string]$final.receipt.consumption_id;preparation_fingerprint=[string]$final.receipt.preparation_fingerprint
        completion_fingerprint=[string]$final.receipt.completion_fingerprint;evidence_fingerprint=[string]$final.receipt.evidence_fingerprint;embedded_restore_result_fingerprint=[string]$final.receipt.executor_result_fingerprint;initial_bridge_fingerprint=[string]$initial.receipt.integration_fingerprint;retirement_executor_result_fingerprint=[string]$er.result_fingerprint;final_bridge_fingerprint=[string]$final.receipt.integration_fingerprint
        rollback_complete_revision=[int64]$final.receipt.rollback_complete_revision;rollback_complete_entry_sha256=[string]$final.receipt.rollback_complete_entry_sha256;live_tree_sha256=[string]$final.receipt.live_tree_sha256;persistence_fingerprint=[string]$final.receipt.persistence_fingerprint
        transaction_action=[string]$er.transaction_action;stage_action=[string]$er.stage_action;app_backup_action=[string]$er.app_backup_action;persistence_backup_action=[string]$er.persistence_backup_action
        retirement_performed=[bool]$er.retirement_performed;initially_already_complete=[bool]$er.initially_already_complete;artifact_retirement_complete=$true;durable_completion_reloaded_before=$true;durable_completion_reloaded_after=$true;embedded_restore_result_revalidated_before=$true;embedded_restore_result_revalidated_after=$true;fresh_retirement_admission_revalidated_before=$true;fresh_retirement_admission_revalidated_after=$true;retirement_executor_result_revalidated=$true;journal_retained=[bool]$er.journal_retained;recovery_evidence_retained=[bool]$er.recovery_evidence_retained;completion_evidence_retained=$true;requires_new_update_permit=$true;requires_future_fresh_revalidation=$true;completed_at=$finalAt.ToUniversalTime().ToString('o')
        result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $result
    if(-not[bool]$check.ok){return & $deny ('recovery-artifact-retirement-resume-executor-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='durable-completion-bounded-retirement-resume-complete';result=$result;initial_bridge=$initial.receipt;retirement_executor=$er;final_bridge=$final.receipt}
}
