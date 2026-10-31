$CustomAppProductionRecoveryAwarePermitReadinessSchema = 1
$CustomAppProductionRecoveryAwarePermitReadinessManagedBy = 'custom-app-production-recovery-aware-new-permit-readiness-v1'
$CustomAppProductionRecoveryAwarePermitReadinessQualifiedPromotionHead = '6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c'
$CustomAppProductionRecoveryAwarePermitReadinessQualifiedRecoveryResumeHead = '2ad528b8a969fd45e88168d22ea787984f5e2714'
$CustomAppProductionRecoveryAwarePermitReadinessQualifiedTerminalBridgeHead = '894c5013df0a2f1c17483425a31f49d0f9eaa99d'

function Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_promotion_head,[string]$Receipt.qualified_recovery_resume_head,[string]$Receipt.qualified_terminal_bridge_head,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.recovery_resume_result_fingerprint,[string]$Receipt.prior_final_bridge_fingerprint,[string]$Receipt.fresh_terminal_bridge_fingerprint,
        [string]$Receipt.completion_fingerprint,[string]$Receipt.restore_executor_result_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.rollback_complete_revision,[string]$Receipt.rollback_complete_entry_sha256,
        [string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,[string]$Receipt.current_promotion_decision_fingerprint,[string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.recovery_terminal_freshly_reloaded,[string]$Receipt.recovery_artifacts_absent,[string]$Receipt.current_promotion_freshly_revalidated,[string]$Receipt.stable_state_continuity_verified,[string]$Receipt.requires_new_update_permit,[string]$Receipt.requires_future_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,[string]$Receipt.eligible_to_request_new_update_permit,[string]$Receipt.readiness_is_authority,[string]$Receipt.promotion_token_issued,[string]$Receipt.permit_issued,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    )-join"`n"
}
function New-CustomAppProductionRecoveryAwarePermitReadinessDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{ok=$false;reason=$Reason;eligible_to_request_new_update_permit=$false;readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
function Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_promotion_head','qualified_recovery_resume_head','qualified_terminal_bridge_head','name','source_identity','transaction_id','recovery_resume_result_fingerprint','prior_final_bridge_fingerprint','fresh_terminal_bridge_fingerprint','completion_fingerprint','restore_executor_result_fingerprint','recovery_evidence_fingerprint','rollback_complete_revision','rollback_complete_entry_sha256','stable_live_tree_sha256','stable_persistence_fingerprint','current_promotion_decision_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','recovery_terminal_freshly_reloaded','recovery_artifacts_absent','current_promotion_freshly_revalidated','stable_state_continuity_verified','requires_new_update_permit','requires_future_fresh_revalidation','checked_at','eligible_until','eligible_to_request_new_update_permit','readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','readiness_fingerprint')){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-readiness-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne1-or[string]$Receipt.managed_by-cne$CustomAppProductionRecoveryAwarePermitReadinessManagedBy-or[string]$Receipt.qualified_promotion_head-cne$CustomAppProductionRecoveryAwarePermitReadinessQualifiedPromotionHead-or[string]$Receipt.qualified_recovery_resume_head-cne$CustomAppProductionRecoveryAwarePermitReadinessQualifiedRecoveryResumeHead-or[string]$Receipt.qualified_terminal_bridge_head-cne$CustomAppProductionRecoveryAwarePermitReadinessQualifiedTerminalBridgeHead){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','recovery_resume_result_fingerprint','prior_final_bridge_fingerprint','fresh_terminal_bridge_fingerprint','completion_fingerprint','restore_executor_result_fingerprint','recovery_evidence_fingerprint','rollback_complete_entry_sha256','stable_live_tree_sha256','stable_persistence_fingerprint','current_promotion_decision_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','readiness_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-readiness-invalid-'+$f)}}}
    if(([string]$Receipt.current_remote_commit_sha)-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-current-remote-commit-invalid'}}
    foreach($f in @('recovery_terminal_freshly_reloaded','recovery_artifacts_absent','current_promotion_freshly_revalidated','stable_state_continuity_verified','requires_new_update_permit','requires_future_fresh_revalidation','eligible_to_request_new_update_permit')){if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-readiness-required-flag-false-'+$f)}}}
    foreach($f in @('readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-readiness-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;$remoteAt=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)-or-not[DateTimeOffset]::TryParse([string]$Receipt.current_remote_observed_at,[ref]$remoteAt)){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-window-invalid'}}
    if($remoteAt-gt$start.AddSeconds(5)-or$remoteAt-lt$start.AddMinutes(-10)){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-remote-observation-not-fresh'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-expired'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.readiness_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-readiness-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-new-permit-readiness-valid-zero-authority';name=([string]$Receipt.name).Trim().ToLowerInvariant();source_identity=([string]$Receipt.source_identity).Trim().ToLowerInvariant();readiness_fingerprint=$expected}
}

function Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,
        [Parameter(Mandatory=$true)]$RetirementResumeResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitReadinessDeniedV010 -Reason $Reason}
    if([string]::IsNullOrWhiteSpace($Name)){return & $deny 'recovery-aware-readiness-name-empty'}
    $nameKey=$Name.Trim().ToLowerInvariant();$tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not(Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 $tx)){return & $deny 'recovery-aware-readiness-transaction-invalid'}

    $rr=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $RetirementResumeResult
    if(-not[bool]$rr.ok){return & $deny ('recovery-aware-readiness-retirement-resume-result-invalid:'+[string]$rr.reason)}
    if(([string]$RetirementResumeResult.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'recovery-aware-readiness-retirement-resume-transaction-mismatch'}
    foreach($f in @('artifact_retirement_complete','durable_completion_reloaded_before','durable_completion_reloaded_after','embedded_restore_result_revalidated_before','embedded_restore_result_revalidated_after','fresh_retirement_admission_revalidated_before','fresh_retirement_admission_revalidated_after','retirement_executor_result_revalidated','journal_retained','recovery_evidence_retained','completion_evidence_retained','requires_new_update_permit','requires_future_fresh_revalidation')){if(-not[bool]$RetirementResumeResult.$f){return & $deny ('recovery-aware-readiness-retirement-resume-contract-false-'+$f)}}

    $terminal=Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if($null-eq$terminal-or-not[bool]$terminal.ok){return & $deny ('recovery-aware-readiness-terminal-bridge-denied:'+[string]$terminal.reason)}
    $tb=$terminal.receipt;$tc=Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 -Receipt $tb -Now $Now
    if(-not[bool]$tc.ok){return & $deny ('recovery-aware-readiness-terminal-bridge-invalid:'+[string]$tc.reason)}
    if([bool]$tb.retirement_needed-or[bool]$tb.retirement_eligible-or-not[bool]$tb.retirement_already_complete-or[bool]$tb.requires_bounded_artifact_retirement-or-not[bool]$tb.requires_new_update_permit){return & $deny 'recovery-aware-readiness-terminal-recovery-not-closed'}
    foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){if([string]$tb.$f-cne'already-absent'){return & $deny ('recovery-aware-readiness-terminal-artifact-present-'+$f)}}
    if([string]$tb.transaction_old_status-cne'absent'-or[string]$tb.transaction_candidate_status-cne'absent'){return & $deny 'recovery-aware-readiness-terminal-transaction-child-present'}
    foreach($f in @('durable_completion_reloaded','embedded_restore_result_revalidated','fresh_retirement_admission_revalidated','requires_future_executor_fresh_revalidation')){if(-not[bool]$tb.$f){return & $deny ('recovery-aware-readiness-terminal-proof-false-'+$f)}}

    $pairs=@(
        @('transaction_id','transaction_id'),@('name','name'),@('source_identity','source_identity'),@('completion_fingerprint','completion_fingerprint'),@('embedded_restore_result_fingerprint','executor_result_fingerprint'),@('evidence_fingerprint','evidence_fingerprint'),@('rollback_complete_revision','rollback_complete_revision'),@('rollback_complete_entry_sha256','rollback_complete_entry_sha256'),@('live_tree_sha256','live_tree_sha256'),@('persistence_fingerprint','persistence_fingerprint')
    )
    foreach($p in $pairs){$l=[string]$RetirementResumeResult.($p[0]);$r=[string]$tb.($p[1]);if($l.Trim().ToLowerInvariant()-cne$r.Trim().ToLowerInvariant()){return & $deny ('recovery-aware-readiness-recovery-continuity-mismatch-'+[string]$p[0])}}
    if(([string]$RetirementResumeResult.name).Trim().ToLowerInvariant()-cne$nameKey){return & $deny 'recovery-aware-readiness-name-does-not-match-recovery'}

    $promotion=Resolve-CustomAppProductionPromotionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult
    if($null-eq$promotion-or-not[bool]$promotion.eligible_for_production_promotion){return & $deny ('recovery-aware-readiness-current-promotion-denied:'+[string]$promotion.reason)}
    if(-not[bool]$promotion.promotion_decision_only-or[bool]$promotion.promotion_token_issued-or[string]$promotion.mutation_mode-cne'deny'-or[bool]$promotion.mutation_authorized-or[bool]$promotion.auto_update_authorized-or[bool]$promotion.auto_install_authorized-or[bool]$promotion.production_mutation_authorized){return & $deny 'recovery-aware-readiness-current-promotion-authority-drift'}
    if($null-eq$promotion.evidence-or-not(Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 ([string]$promotion.decision_fingerprint))){return & $deny 'recovery-aware-readiness-current-promotion-evidence-invalid'}
    $pe=$promotion.evidence
    if(([string]$pe.name).Trim().ToLowerInvariant()-cne$nameKey-or([string]$pe.source_identity).Trim().ToLowerInvariant()-cne([string]$tb.source_identity).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-readiness-current-identity-does-not-match-stable-recovery'}
    if(([string]$pe.local_tree_sha256).Trim().ToLowerInvariant()-cne([string]$tb.live_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-readiness-current-local-tree-does-not-match-stable-recovery'}
    if(([string]$pe.persistence_fingerprint).Trim().ToLowerInvariant()-cne([string]$tb.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-readiness-current-persistence-does-not-match-stable-recovery'}
    $remoteAt=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$pe.remote_observed_at,[ref]$remoteAt)){return & $deny 'recovery-aware-readiness-current-remote-time-invalid'}
    if($remoteAt-gt$Now.AddSeconds(5)-or$remoteAt-lt$Now.AddMinutes(-10)){return & $deny 'recovery-aware-readiness-current-remote-observation-not-fresh'}
    foreach($f in @('remote_tree_sha256','binding_fingerprint','provenance_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 ([string]$pe.$f))){return & $deny ('recovery-aware-readiness-current-promotion-invalid-'+$f)}}
    if(([string]$pe.remote_commit_sha)-notmatch'^[0-9a-f]{40}$'){return & $deny 'recovery-aware-readiness-current-promotion-remote-commit-invalid'}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitReadinessSchema;managed_by=$CustomAppProductionRecoveryAwarePermitReadinessManagedBy;qualified_promotion_head=$CustomAppProductionRecoveryAwarePermitReadinessQualifiedPromotionHead;qualified_recovery_resume_head=$CustomAppProductionRecoveryAwarePermitReadinessQualifiedRecoveryResumeHead;qualified_terminal_bridge_head=$CustomAppProductionRecoveryAwarePermitReadinessQualifiedTerminalBridgeHead
        name=$nameKey;source_identity=([string]$tb.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;recovery_resume_result_fingerprint=([string]$RetirementResumeResult.result_fingerprint).Trim().ToLowerInvariant();prior_final_bridge_fingerprint=([string]$RetirementResumeResult.final_bridge_fingerprint).Trim().ToLowerInvariant();fresh_terminal_bridge_fingerprint=([string]$tb.integration_fingerprint).Trim().ToLowerInvariant()
        completion_fingerprint=([string]$tb.completion_fingerprint).Trim().ToLowerInvariant();restore_executor_result_fingerprint=([string]$tb.executor_result_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$tb.evidence_fingerprint).Trim().ToLowerInvariant();rollback_complete_revision=[int64]$tb.rollback_complete_revision;rollback_complete_entry_sha256=([string]$tb.rollback_complete_entry_sha256).Trim().ToLowerInvariant()
        stable_live_tree_sha256=([string]$tb.live_tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$tb.persistence_fingerprint).Trim().ToLowerInvariant();current_promotion_decision_fingerprint=([string]$promotion.decision_fingerprint).Trim().ToLowerInvariant();current_remote_tree_sha256=([string]$pe.remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$pe.remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$pe.binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$pe.provenance_fingerprint).Trim().ToLowerInvariant();current_remote_observed_at=$remoteAt.ToUniversalTime().ToString('o')
        recovery_terminal_freshly_reloaded=$true;recovery_artifacts_absent=$true;current_promotion_freshly_revalidated=$true;stable_state_continuity_verified=$true;requires_new_update_permit=$true;requires_future_fresh_revalidation=$true;checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o');eligible_to_request_new_update_permit=$true
        readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;readiness_fingerprint=$null
    }
    $receipt.readiness_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010 -Receipt $receipt)
    $check=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $receipt -Now $Now
    if(-not[bool]$check.ok){return & $deny ('recovery-aware-readiness-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='recovery-closed-current-proof-fresh-new-permit-request-ready';receipt=$receipt;promotion_decision=$promotion;fresh_terminal_bridge=$tb;eligible_to_request_new_update_permit=$true;readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
