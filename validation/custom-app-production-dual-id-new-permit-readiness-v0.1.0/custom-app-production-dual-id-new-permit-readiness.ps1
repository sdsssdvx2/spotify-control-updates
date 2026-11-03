$CustomAppProductionDualIdNewPermitReadinessSchema=1
$CustomAppProductionDualIdNewPermitReadinessManagedBy='custom-app-production-dual-id-new-permit-readiness-v1'
$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingHead='2a9bab36e14d0aa0d1b5c55738a6ffe44bb65ab4'
$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingCoreBlob='6cf870e37b2ad4afc6b4d7eec0538afda595ddb1'
$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionHead='6bc69d2c8b12d074fa68f3d2ed7688e0846cd23c'
$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionCoreBlob='1164c197405eac2295f789256e2886068611dd94'
$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeHead='408e24ce7f66d1f5f23025a196b19cd8a42fcda7'
$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeCoreBlob='c9a58a181d3c5f5a230fa895785c3a42a928c8cd'
$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceHead='993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'
$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceCoreBlob='910b1c500d33d6d6e0ad403c701f4c08f473f1a3'
$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalHead='7e26187e2360089024e9d72d0701be6f1577a1ef'
$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalCoreBlob='a3df7e5d89c594083c10e240e13029ca5640b8ae'

function Get-CustomAppProductionDualIdNewPermitReadinessSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
}
function Test-CustomAppProductionDualIdNewPermitReadinessSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function New-CustomAppProductionDualIdNewPermitReadinessDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{ok=$false;reason=$Reason;receipt=$null;eligible_to_request_new_update_permit=$false;readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
function Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_housekeeping_head,[string]$Receipt.qualified_housekeeping_core_blob,[string]$Receipt.qualified_promotion_head,[string]$Receipt.qualified_promotion_core_blob,[string]$Receipt.qualified_durable_bridge_head,[string]$Receipt.qualified_durable_bridge_core_blob,[string]$Receipt.qualified_evidence_head,[string]$Receipt.qualified_evidence_core_blob,[string]$Receipt.qualified_journal_head,[string]$Receipt.qualified_journal_core_blob,
        [string]$Receipt.status,[string]$Receipt.reason,[string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.permit_transaction_id,[string]$Receipt.journal_transaction_id,[string]$Receipt.housekeeping_cleanup_fingerprint,[string]$Receipt.precommit_fingerprint,[string]$Receipt.dual_id_bridge_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.committed_clean_revision,[string]$Receipt.committed_clean_entry_sha256,
        [string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,[string]$Receipt.current_promotion_decision_fingerprint,[string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.transaction_id_namespaces_distinct,[string]$Receipt.committed_clean_freshly_reloaded,[string]$Receipt.durable_dual_id_freshly_reloaded,[string]$Receipt.recovery_evidence_freshly_reloaded,[string]$Receipt.transaction_artifacts_absent,[string]$Receipt.current_stable_state_revalidated,[string]$Receipt.current_promotion_freshly_revalidated,[string]$Receipt.requires_new_update_permit,[string]$Receipt.requires_future_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,[string]$Receipt.eligible_to_request_new_update_permit,[string]$Receipt.readiness_is_authority,[string]$Receipt.promotion_token_issued,[string]$Receipt.permit_issued,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    )-join"`n"
}
function Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-null'}}
    $required=@('schema','managed_by','qualified_housekeeping_head','qualified_housekeeping_core_blob','qualified_promotion_head','qualified_promotion_core_blob','qualified_durable_bridge_head','qualified_durable_bridge_core_blob','qualified_evidence_head','qualified_evidence_core_blob','qualified_journal_head','qualified_journal_core_blob','status','reason','name','source_identity','permit_transaction_id','journal_transaction_id','housekeeping_cleanup_fingerprint','precommit_fingerprint','dual_id_bridge_fingerprint','recovery_evidence_fingerprint','committed_clean_revision','committed_clean_entry_sha256','stable_live_tree_sha256','stable_persistence_fingerprint','current_promotion_decision_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','transaction_id_namespaces_distinct','committed_clean_freshly_reloaded','durable_dual_id_freshly_reloaded','recovery_evidence_freshly_reloaded','transaction_artifacts_absent','current_stable_state_revalidated','current_promotion_freshly_revalidated','requires_new_update_permit','requires_future_fresh_revalidation','checked_at','eligible_until','eligible_to_request_new_update_permit','readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','readiness_fingerprint')
    foreach($f in $required){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('dual-id-readiness-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne$CustomAppProductionDualIdNewPermitReadinessSchema-or[string]$Receipt.managed_by-cne$CustomAppProductionDualIdNewPermitReadinessManagedBy-or[string]$Receipt.status-cne'dual-id-committed-clean-ready-for-new-permit-request'-or[string]$Receipt.reason-cne'committed-clean-dual-id-stable-state-and-current-promotion-revalidated'){
        return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-owner-status-invalid'}
    }
    if([string]$Receipt.qualified_housekeeping_head-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingHead-or[string]$Receipt.qualified_housekeeping_core_blob-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingCoreBlob-or[string]$Receipt.qualified_promotion_head-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionHead-or[string]$Receipt.qualified_promotion_core_blob-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionCoreBlob-or[string]$Receipt.qualified_durable_bridge_head-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeHead-or[string]$Receipt.qualified_durable_bridge_core_blob-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeCoreBlob-or[string]$Receipt.qualified_evidence_head-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceHead-or[string]$Receipt.qualified_evidence_core_blob-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceCoreBlob-or[string]$Receipt.qualified_journal_head-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalHead-or[string]$Receipt.qualified_journal_core_blob-cne$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalCoreBlob){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-lineage-invalid'}}
    foreach($f in @('permit_transaction_id','journal_transaction_id','housekeeping_cleanup_fingerprint','precommit_fingerprint','dual_id_bridge_fingerprint','recovery_evidence_fingerprint','committed_clean_entry_sha256','stable_live_tree_sha256','stable_persistence_fingerprint','current_promotion_decision_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','readiness_fingerprint')){if(-not(Test-CustomAppProductionDualIdNewPermitReadinessSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('dual-id-readiness-receipt-invalid-'+$f)}}}
    if(([string]$Receipt.current_remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-remote-commit-invalid'}}
    if(([string]$Receipt.permit_transaction_id).Trim().ToLowerInvariant()-ceq([string]$Receipt.journal_transaction_id).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-transaction-namespaces-conflated'}}
    foreach($f in @('transaction_id_namespaces_distinct','committed_clean_freshly_reloaded','durable_dual_id_freshly_reloaded','recovery_evidence_freshly_reloaded','transaction_artifacts_absent','current_stable_state_revalidated','current_promotion_freshly_revalidated','requires_new_update_permit','requires_future_fresh_revalidation','eligible_to_request_new_update_permit')){if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-readiness-receipt-required-flag-false-'+$f)}}}
    foreach($f in @('readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-readiness-receipt-authority-escaped-'+$f)}}}
    try{if([int64]$Receipt.committed_clean_revision-lt1){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-journal-revision-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-journal-revision-invalid'}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;$remoteAt=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)-or-not[DateTimeOffset]::TryParse([string]$Receipt.current_remote_observed_at,[ref]$remoteAt)){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-window-invalid'}}
    if($remoteAt-gt$start.AddSeconds(5)-or$remoteAt-lt$start.AddMinutes(-10)){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-remote-observation-not-fresh'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-expired'}}
    $expected=Get-CustomAppProductionDualIdNewPermitReadinessSha256V010(Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $Receipt)
    if(([string]$Receipt.readiness_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='dual-id-readiness-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-readiness-valid-zero-authority';readiness_fingerprint=$expected;permit_issued=$false;production_mutation_authorized=$false}
}
function Resolve-CustomAppProductionDualIdNewPermitReadinessV010 {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,
        [Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedPermitTransactionId,[Parameter(Mandatory=$true)][string]$ExpectedJournalTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)New-CustomAppProductionDualIdNewPermitReadinessDeniedV010 -Reason $Reason}
    if([string]::IsNullOrWhiteSpace($Name)){return & $deny 'dual-id-readiness-name-empty'}
    $nameKey=$Name.Trim().ToLowerInvariant();$permitId=$ExpectedPermitTransactionId.Trim().ToLowerInvariant();$journalId=$ExpectedJournalTransactionId.Trim().ToLowerInvariant()
    if(-not(Test-CustomAppProductionDualIdNewPermitReadinessSha256V010 $permitId)){return & $deny 'dual-id-readiness-permit-transaction-id-invalid'}
    if(-not(Test-CustomAppProductionDualIdNewPermitReadinessSha256V010 $journalId)){return & $deny 'dual-id-readiness-journal-transaction-id-invalid'}
    if($permitId-ceq$journalId){return & $deny 'dual-id-readiness-transaction-namespaces-conflated'}

    $hc=Test-CustomAppProductionDualIdHousekeepingResumeResultV010 -Result $HousekeepingResult
    if($null-eq$hc-or-not[bool]$hc.ok){return & $deny ('dual-id-readiness-housekeeping-result-invalid:'+[string]$hc.reason)}
    if(([string]$HousekeepingResult.name).Trim().ToLowerInvariant()-cne$nameKey){return & $deny 'dual-id-readiness-housekeeping-name-mismatch'}
    if(([string]$HousekeepingResult.permit_transaction_id).Trim().ToLowerInvariant()-cne$permitId){return & $deny 'dual-id-readiness-housekeeping-permit-id-mismatch'}
    if(([string]$HousekeepingResult.journal_transaction_id).Trim().ToLowerInvariant()-cne$journalId){return & $deny 'dual-id-readiness-housekeeping-journal-id-mismatch'}
    if(-not[bool]$HousekeepingResult.transaction_id_namespaces_distinct-or-not[bool]$HousekeepingResult.recovery_evidence_retained-or-not[bool]$HousekeepingResult.requires_new_permit_for_future_update-or[bool]$HousekeepingResult.spicetify_apply_executed){return & $deny 'dual-id-readiness-housekeeping-terminal-contract-invalid'}

    try{$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('dual-id-readiness-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$journal-or-not[bool]$journal.ok-or$null-eq$journal.entry){return & $deny 'dual-id-readiness-journal-invalid'}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant()-cne$journalId-or([string]$journal.entry.transaction_id).Trim().ToLowerInvariant()-cne$journalId){return & $deny 'dual-id-readiness-journal-id-mismatch'}
    if([string]$journal.entry.phase-cne'committed-clean'){return & $deny 'dual-id-readiness-journal-not-committed-clean'}
    if(([string]$journal.entry.cleanup_result_fingerprint).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.cleanup_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-cleanup-fingerprint-mismatch'}
    if([int64]$journal.revision-ne[int64]$HousekeepingResult.committed_clean_revision){return & $deny 'dual-id-readiness-committed-clean-revision-mismatch'}

    $identity=Get-CustomAppProductionDualIdHousekeepingResumeDurableIdentityV010 -AllowedRoot $AllowedRoot -JournalStoreDirectory $StoreDirectory -ExpectedJournalTransactionId $journalId -JournalRead $journal
    if($null-eq$identity-or-not[bool]$identity.ok){return & $deny ('dual-id-readiness-durable-identity-denied:'+[string]$identity.reason)}
    if(([string]$identity.permit_transaction_id).Trim().ToLowerInvariant()-cne$permitId-or([string]$identity.journal_transaction_id).Trim().ToLowerInvariant()-cne$journalId){return & $deny 'dual-id-readiness-durable-id-continuity-mismatch'}
    if(([string]$identity.precommit.name).Trim().ToLowerInvariant()-cne$nameKey){return & $deny 'dual-id-readiness-durable-name-mismatch'}
    $source=([string]$identity.precommit.source_identity).Trim().ToLowerInvariant();if([string]::IsNullOrWhiteSpace($source)){return & $deny 'dual-id-readiness-durable-source-empty'}
    if(([string]$identity.precommit_fingerprint).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.precommit_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-precommit-fingerprint-mismatch'}
    if(([string]$identity.bridge_fingerprint).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.bridge_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-bridge-fingerprint-mismatch'}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $journalId
    if($null-eq$evidence-or-not[bool]$evidence.ok){return & $deny ('dual-id-readiness-recovery-evidence-denied:'+[string]$evidence.reason)}
    if(([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.evidence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-recovery-evidence-fingerprint-mismatch'}

    foreach($p in @([string]$journal.entry.transaction_root,[string]$journal.entry.stage_workspace_path,[string]$journal.entry.app_backup_path,[string]$journal.entry.persistence_backup_path)){
        if([string]::IsNullOrWhiteSpace($p)){return & $deny 'dual-id-readiness-transaction-artifact-path-empty'}
        if(Test-Path -LiteralPath $p){return & $deny 'dual-id-readiness-transaction-artifact-reappeared'}
    }

    try{$runtime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$journal.entry.live_path)}catch{return & $deny ('dual-id-readiness-live-runtime-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$runtime-or-not[bool]$runtime.safe-or-not[bool]$runtime.installable-or(Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime)){return & $deny 'dual-id-readiness-live-runtime-unsafe'}
    if(([string]$runtime.tree_sha256).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.live_runtime_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-live-tree-drift'}
    try{$persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('dual-id-readiness-persistence-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$persistence.fingerprint).Trim().ToLowerInvariant()-cne([string]$HousekeepingResult.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-persistence-drift'}

    $promotion=Resolve-CustomAppProductionPromotionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult
    if($null-eq$promotion-or-not[bool]$promotion.eligible_for_production_promotion){return & $deny ('dual-id-readiness-current-promotion-denied:'+[string]$promotion.reason)}
    if(-not[bool]$promotion.promotion_decision_only-or[bool]$promotion.promotion_token_issued-or[string]$promotion.mutation_mode-cne'deny'-or[bool]$promotion.mutation_authorized-or[bool]$promotion.auto_update_authorized-or[bool]$promotion.auto_install_authorized-or[bool]$promotion.production_mutation_authorized){return & $deny 'dual-id-readiness-current-promotion-authority-drift'}
    if($null-eq$promotion.evidence-or-not(Test-CustomAppProductionDualIdNewPermitReadinessSha256V010 ([string]$promotion.decision_fingerprint))){return & $deny 'dual-id-readiness-current-promotion-evidence-invalid'}
    $pe=$promotion.evidence
    if(([string]$pe.name).Trim().ToLowerInvariant()-cne$nameKey-or([string]$pe.source_identity).Trim().ToLowerInvariant()-cne$source){return & $deny 'dual-id-readiness-current-identity-does-not-match-committed-state'}
    if(([string]$pe.local_tree_sha256).Trim().ToLowerInvariant()-cne([string]$runtime.tree_sha256).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-current-local-tree-does-not-match-committed-state'}
    if(([string]$pe.persistence_fingerprint).Trim().ToLowerInvariant()-cne([string]$persistence.fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-current-persistence-does-not-match-committed-state'}
    $remoteAt=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$pe.remote_observed_at,[ref]$remoteAt)){return & $deny 'dual-id-readiness-current-remote-time-invalid'}
    if($remoteAt-gt$Now.AddSeconds(5)-or$remoteAt-lt$Now.AddMinutes(-10)){return & $deny 'dual-id-readiness-current-remote-observation-not-fresh'}
    foreach($f in @('remote_tree_sha256','binding_fingerprint','provenance_fingerprint')){if(-not(Test-CustomAppProductionDualIdNewPermitReadinessSha256V010 ([string]$pe.$f))){return & $deny ('dual-id-readiness-current-promotion-invalid-'+$f)}}
    if(([string]$pe.binding_fingerprint).Trim().ToLowerInvariant()-cne([string]$BindingRow.binding_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-current-binding-fingerprint-drift'}
    if(([string]$pe.provenance_fingerprint).Trim().ToLowerInvariant()-cne([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-readiness-current-provenance-fingerprint-drift'}

    $receipt=[ordered]@{
        schema=$CustomAppProductionDualIdNewPermitReadinessSchema;managed_by=$CustomAppProductionDualIdNewPermitReadinessManagedBy
        qualified_housekeeping_head=$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingHead;qualified_housekeeping_core_blob=$CustomAppProductionDualIdNewPermitReadinessQualifiedHousekeepingCoreBlob
        qualified_promotion_head=$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionHead;qualified_promotion_core_blob=$CustomAppProductionDualIdNewPermitReadinessQualifiedPromotionCoreBlob
        qualified_durable_bridge_head=$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeHead;qualified_durable_bridge_core_blob=$CustomAppProductionDualIdNewPermitReadinessQualifiedDurableBridgeCoreBlob
        qualified_evidence_head=$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceHead;qualified_evidence_core_blob=$CustomAppProductionDualIdNewPermitReadinessQualifiedEvidenceCoreBlob
        qualified_journal_head=$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalHead;qualified_journal_core_blob=$CustomAppProductionDualIdNewPermitReadinessQualifiedJournalCoreBlob
        status='dual-id-committed-clean-ready-for-new-permit-request';reason='committed-clean-dual-id-stable-state-and-current-promotion-revalidated'
        name=$nameKey;source_identity=$source;permit_transaction_id=$permitId;journal_transaction_id=$journalId;housekeeping_cleanup_fingerprint=([string]$HousekeepingResult.cleanup_fingerprint).Trim().ToLowerInvariant();precommit_fingerprint=([string]$identity.precommit_fingerprint).Trim().ToLowerInvariant();dual_id_bridge_fingerprint=([string]$identity.bridge_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant();committed_clean_revision=[int64]$journal.revision;committed_clean_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()
        stable_live_tree_sha256=([string]$runtime.tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$persistence.fingerprint).Trim().ToLowerInvariant();current_promotion_decision_fingerprint=([string]$promotion.decision_fingerprint).Trim().ToLowerInvariant();current_remote_tree_sha256=([string]$pe.remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$pe.remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$pe.binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$pe.provenance_fingerprint).Trim().ToLowerInvariant();current_remote_observed_at=$remoteAt.ToUniversalTime().ToString('o')
        transaction_id_namespaces_distinct=$true;committed_clean_freshly_reloaded=$true;durable_dual_id_freshly_reloaded=$true;recovery_evidence_freshly_reloaded=$true;transaction_artifacts_absent=$true;current_stable_state_revalidated=$true;current_promotion_freshly_revalidated=$true;requires_new_update_permit=$true;requires_future_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o');eligible_to_request_new_update_permit=$true;readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false
    }
    $obj=[pscustomobject]$receipt;$obj|Add-Member -NotePropertyName readiness_fingerprint -NotePropertyValue (Get-CustomAppProductionDualIdNewPermitReadinessSha256V010(Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $obj))
    $check=Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $obj -Now $Now
    if(-not[bool]$check.ok){return & $deny ('dual-id-readiness-self-check-failed:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-readiness-issued-zero-authority';receipt=$obj;eligible_to_request_new_update_permit=$true;readiness_is_authority=$false;promotion_token_issued=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
