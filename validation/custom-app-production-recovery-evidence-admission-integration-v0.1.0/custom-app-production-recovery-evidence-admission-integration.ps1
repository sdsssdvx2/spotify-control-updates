$CustomAppProductionRecoveryEvidenceAdmissionIntegrationSchema = 1
$CustomAppProductionRecoveryEvidenceAdmissionIntegrationManagedBy = 'custom-app-production-recovery-evidence-admission-integration-v1'
$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedAdmissionHead = 'ffb5aad4a605691ee7b80392498b0cb6fa4e4052'
$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'

function Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 {param([AllowNull()][string]$Value)return(-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')}

function Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_admission_head,[string]$Receipt.qualified_evidence_head,
        [string]$Receipt.transaction_id,[string]$Receipt.phase,[string]$Receipt.classification,[string]$Receipt.executor_class,
        [string]$Receipt.plan_fingerprint,[string]$Receipt.admission_fingerprint,[string]$Receipt.evidence_fingerprint,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.remote_commit_sha,[string]$Receipt.consumption_id,[string]$Receipt.preparation_fingerprint,
        [string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.stage_workspace_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,
        [string]$Receipt.app_backup_tree_sha256,[string]$Receipt.app_backup_file_count,[string]$Receipt.app_backup_total_bytes,[string]$Receipt.persistence_fingerprint,[string]$Receipt.stage_tree_sha256,[string]$Receipt.live_tree_sha256,[string]$Receipt.spicetify_executable_sha256,
        [string]$Receipt.recovery_action_eligible,[string]$Receipt.requires_exact_restore,[string]$Receipt.requires_recovery_apply,[string]$Receipt.requires_idempotent_cleanup,[string]$Receipt.requires_new_permit,
        [string]$Receipt.backup_integrity_required,[string]$Receipt.backup_integrity_verified,[string]$Receipt.requires_future_executor_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.integration_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    )-join"`n"
}

function Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)]$PreflightReceipt,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,[AllowNull()][string]$SpicetifyPath=$null,[AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;integration_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 $tx)){return & $deny 'recovery-integration-transaction-id-invalid'}

    $admission=Resolve-CustomAppProductionRecoveryExecutionAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -Plan $Plan -PreflightReceipt $PreflightReceipt -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now
    if($null-eq$admission-or-not[bool]$admission.ok){return & $deny ('recovery-integration-fresh-admission-denied:'+[string]$admission.reason)}
    $ac=Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 -Decision $admission.decision -Now $Now
    if(-not[bool]$ac.ok){return & $deny ('recovery-integration-fresh-admission-invalid:'+[string]$ac.reason)}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$evidence-or-not[bool]$evidence.ok){return & $deny ('recovery-integration-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$e.$f){return & $deny ('recovery-integration-evidence-authority-escaped-'+$f)}}
    if(([string]$e.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'recovery-integration-evidence-transaction-mismatch'}
    if(([string]$e.preparation_fingerprint).Trim().ToLowerInvariant()-cne([string]$e.prepared_result.preparation_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-integration-preparation-fingerprint-mismatch'}
    if(([string]$e.name).Trim().ToLowerInvariant()-cne([string]$e.prepared_result.name).Trim().ToLowerInvariant()-or([string]$e.source_identity).Trim().ToLowerInvariant()-cne([string]$e.prepared_result.source_identity).Trim().ToLowerInvariant()-or([string]$e.remote_commit_sha).Trim().ToLowerInvariant()-cne([string]$e.prepared_result.remote_commit_sha).Trim().ToLowerInvariant()-or([string]$e.consumption_id).Trim().ToLowerInvariant()-cne([string]$e.prepared_result.consumption_id).Trim().ToLowerInvariant()){return & $deny 'recovery-integration-evidence-prepared-identity-mismatch'}

    $requiresRestore=[bool]$admission.decision.requires_exact_restore
    $backupVerified=$false
    if($requiresRestore){
        try{$app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$e.app_backup_path)}catch{return & $deny ('recovery-integration-app-backup-read-failed:'+[string]$_.Exception.Message)}
        if([string]$app.tree_sha256-cne[string]$e.app_backup_tree_sha256-or[int]$app.file_count-ne[int]$e.app_backup_file_count-or[int64]$app.total_bytes-ne[int64]$e.app_backup_total_bytes){return & $deny 'recovery-integration-app-backup-integrity-mismatch'}
        $pc=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$e.persistence_backup_path) -ExpectedFingerprint ([string]$e.persistence_fingerprint)
        if(-not[bool]$pc.ok){return & $deny ('recovery-integration-persistence-backup-invalid:'+[string]$pc.reason)}
        $backupVerified=$true
    }

    if([bool]$admission.decision.requires_recovery_apply){
        if(-not(Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 ([string]$admission.decision.spicetify_executable_sha256))){return & $deny 'recovery-integration-spicetify-pin-missing'}
    }

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryEvidenceAdmissionIntegrationSchema;managed_by=$CustomAppProductionRecoveryEvidenceAdmissionIntegrationManagedBy;qualified_admission_head=$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedAdmissionHead;qualified_evidence_head=$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedEvidenceHead
        transaction_id=$tx;phase=[string]$admission.decision.phase;classification=[string]$admission.decision.classification;executor_class=[string]$admission.decision.executor_class
        plan_fingerprint=([string]$admission.decision.plan_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$admission.decision.admission_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=([string]$e.evidence_fingerprint).Trim().ToLowerInvariant();journal_revision=[int64]$admission.decision.journal_revision;journal_entry_sha256=([string]$admission.decision.journal_entry_sha256).Trim().ToLowerInvariant()
        name=([string]$e.name).Trim().ToLowerInvariant();source_identity=([string]$e.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$e.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$e.consumption_id).Trim().ToLowerInvariant();preparation_fingerprint=([string]$e.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$e.live_path;transaction_root=[string]$e.transaction_root;stage_workspace_path=[string]$e.stage_workspace_path;app_backup_path=[string]$e.app_backup_path;persistence_backup_path=[string]$e.persistence_backup_path
        app_backup_tree_sha256=([string]$e.app_backup_tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$e.app_backup_file_count;app_backup_total_bytes=[int64]$e.app_backup_total_bytes;persistence_fingerprint=([string]$e.persistence_fingerprint).Trim().ToLowerInvariant();stage_tree_sha256=([string]$e.stage_tree_sha256).Trim().ToLowerInvariant();live_tree_sha256=([string]$e.live_tree_sha256).Trim().ToLowerInvariant();spicetify_executable_sha256=[string]$admission.decision.spicetify_executable_sha256
        recovery_action_eligible=[bool]$admission.decision.recovery_action_eligible;requires_exact_restore=$requiresRestore;requires_recovery_apply=[bool]$admission.decision.requires_recovery_apply;requires_idempotent_cleanup=[bool]$admission.decision.requires_idempotent_cleanup;requires_new_permit=[bool]$admission.decision.requires_new_permit
        backup_integrity_required=$requiresRestore;backup_integrity_verified=$backupVerified;requires_future_executor_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        integration_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;integration_fingerprint=$null
    }
    $receipt.integration_fingerprint=Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 (Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationMaterialV010 $receipt)
    return [pscustomobject]@{ok=$true;reason='recovery-evidence-admission-integrated-zero-authority';receipt=$receipt;admission=$admission.decision;evidence=$e}
}

function Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='recovery-integration-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_admission_head','qualified_evidence_head','transaction_id','phase','classification','executor_class','plan_fingerprint','admission_fingerprint','evidence_fingerprint','journal_revision','journal_entry_sha256','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_fingerprint','stage_tree_sha256','live_tree_sha256','spicetify_executable_sha256','recovery_action_eligible','requires_exact_restore','requires_recovery_apply','requires_idempotent_cleanup','requires_new_permit','backup_integrity_required','backup_integrity_verified','requires_future_executor_fresh_revalidation','checked_at','eligible_until','integration_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','integration_fingerprint')){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-integration-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne1-or[string]$Receipt.managed_by-cne$CustomAppProductionRecoveryEvidenceAdmissionIntegrationManagedBy-or[string]$Receipt.qualified_admission_head-cne$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedAdmissionHead-or[string]$Receipt.qualified_evidence_head-cne$CustomAppProductionRecoveryEvidenceAdmissionIntegrationQualifiedEvidenceHead){return [pscustomobject]@{ok=$false;reason='recovery-integration-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','plan_fingerprint','admission_fingerprint','evidence_fingerprint','journal_entry_sha256','preparation_fingerprint','app_backup_tree_sha256','persistence_fingerprint','stage_tree_sha256','live_tree_sha256','integration_fingerprint')){if(-not(Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-integration-invalid-'+$f)}}}
    foreach($f in @('integration_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-integration-authority-escaped-'+$f)}}}
    if(-not[bool]$Receipt.requires_future_executor_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='recovery-integration-future-revalidation-contract-missing'}}
    if([bool]$Receipt.requires_exact_restore){if(-not[bool]$Receipt.backup_integrity_required-or-not[bool]$Receipt.backup_integrity_verified){return [pscustomobject]@{ok=$false;reason='recovery-integration-restore-backup-proof-missing'}}}elseif([bool]$Receipt.backup_integrity_required-or[bool]$Receipt.backup_integrity_verified){return [pscustomobject]@{ok=$false;reason='recovery-integration-unneeded-backup-proof-set'}}
    if([bool]$Receipt.requires_recovery_apply-and-not(Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010([string]$Receipt.spicetify_executable_sha256))){return [pscustomobject]@{ok=$false;reason='recovery-integration-apply-pin-invalid'}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='recovery-integration-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='recovery-integration-window-invalid'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-integration-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='recovery-integration-expired'}}
    $expected=Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 (Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationMaterialV010 $Receipt);if(([string]$Receipt.integration_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-integration-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-evidence-admission-integration-valid-zero-authority';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();executor_class=[string]$Receipt.executor_class;eligible=[bool]$Receipt.recovery_action_eligible}
}
