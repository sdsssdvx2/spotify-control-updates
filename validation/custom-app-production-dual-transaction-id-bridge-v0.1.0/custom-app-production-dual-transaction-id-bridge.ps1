$CustomAppProductionDualTransactionIdBridgeSchema = 1
$CustomAppProductionDualTransactionIdBridgeManagedBy = 'custom-app-production-dual-transaction-id-bridge-v1'
$CustomAppProductionDualTransactionIdBridgeQualifiedPreparedHead = '43f9a433354f56e2db19f4edfa1ffa8f4a245088'
$CustomAppProductionDualTransactionIdBridgeQualifiedPreparedCoreBlob = 'eaad8a5f161f831bbbada1c1c0957a3dfc80edaa'
$CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicHead = 'c21a8c72dd8920df8e1faa59eb6aedee76a15e06'
$CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicCoreBlob = '55ca1e3c8d56b2e86a98d8b47e8ac1cc4ccbb6d0'
$CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'
$CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceCoreBlob = '910b1c500d33d6d6e0ad403c701f4c08f473f1a3'

function Get-CustomAppProductionDualTransactionIdBridgeSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionDualTransactionIdBridgeSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Test-CustomAppProductionDualTransactionIdBridgePathEqualV010 {
    param([AllowNull()][string]$A,[AllowNull()][string]$B)
    try{
        $x=[IO.Path]::GetFullPath($A).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $y=[IO.Path]::GetFullPath($B).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        return $x.Equals($y,[StringComparison]::OrdinalIgnoreCase)
    }catch{return $false}
}
function New-CustomAppProductionDualTransactionIdBridgeDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null
        bridge_is_authority=$false;execution_authorized=$false;finalization_authorized=$false;spicetify_apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionDualTransactionIdBridgeReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_recovery_aware_prepared_head,[string]$Receipt.qualified_recovery_aware_prepared_core_blob,
        [string]$Receipt.qualified_evidence_bound_atomic_head,[string]$Receipt.qualified_evidence_bound_atomic_core_blob,
        [string]$Receipt.qualified_recovery_evidence_head,[string]$Receipt.qualified_recovery_evidence_core_blob,
        [string]$Receipt.status,[string]$Receipt.reason,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,[string]$Receipt.remote_commit_sha,[string]$Receipt.binding_fingerprint,[string]$Receipt.consumption_id,
        [string]$Receipt.permit_transaction_id,[string]$Receipt.journal_transaction_id,[string]$Receipt.transaction_id_namespaces_distinct,
        [string]$Receipt.recovery_pre_apply_result_fingerprint,[string]$Receipt.recovery_stage_result_fingerprint,[string]$Receipt.generic_stage_result_fingerprint,[string]$Receipt.generic_preparation_fingerprint,
        [string]$Receipt.evidence_bound_atomic_result_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.prepared_result_material_sha256,
        [string]$Receipt.journal_phase,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,
        [string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.stage_workspace_path,[string]$Receipt.stage_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,
        [string]$Receipt.live_tree_sha256,[string]$Receipt.stage_tree_sha256,[string]$Receipt.app_backup_tree_sha256,[string]$Receipt.app_backup_file_count,[string]$Receipt.app_backup_total_bytes,[string]$Receipt.persistence_fingerprint,
        [string]$Receipt.requires_bridge_aware_finalization,[string]$Receipt.requires_crash_recovery_by_journal_id,[string]$Receipt.requires_forward_continuity_by_permit_id,
        [string]$Receipt.bridge_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.finalization_authorized,[string]$Receipt.spicetify_apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-null'}}
    $required=@(
        'schema','managed_by','qualified_recovery_aware_prepared_head','qualified_recovery_aware_prepared_core_blob','qualified_evidence_bound_atomic_head','qualified_evidence_bound_atomic_core_blob','qualified_recovery_evidence_head','qualified_recovery_evidence_core_blob','status','reason',
        'name','source_identity','github_repo_id','surface_kind','remote_commit_sha','binding_fingerprint','consumption_id','permit_transaction_id','journal_transaction_id','transaction_id_namespaces_distinct',
        'recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','evidence_bound_atomic_result_fingerprint','recovery_evidence_fingerprint','prepared_result_material_sha256','journal_phase','journal_revision','journal_entry_sha256',
        'live_path','transaction_root','stage_workspace_path','stage_path','app_backup_path','persistence_backup_path','live_tree_sha256','stage_tree_sha256','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_fingerprint',
        'requires_bridge_aware_finalization','requires_crash_recovery_by_journal_id','requires_forward_continuity_by_permit_id','bridge_is_authority','execution_authorized','finalization_authorized','spicetify_apply_authorized','cleanup_authorized','production_mutation_authorized','bridge_fingerprint'
    )
    foreach($f in $required){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('dual-id-bridge-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionDualTransactionIdBridgeSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionDualTransactionIdBridgeManagedBy -or [string]$Receipt.status -cne 'dual-transaction-id-namespaces-durably-bound' -or [string]$Receipt.reason -cne 'permit-forward-id-and-journal-recovery-id-bound-to-same-prepared-evidence'){
        return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-owner-schema-status-invalid'}
    }
    if([string]$Receipt.qualified_recovery_aware_prepared_head -cne $CustomAppProductionDualTransactionIdBridgeQualifiedPreparedHead -or [string]$Receipt.qualified_recovery_aware_prepared_core_blob -cne $CustomAppProductionDualTransactionIdBridgeQualifiedPreparedCoreBlob -or [string]$Receipt.qualified_evidence_bound_atomic_head -cne $CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicHead -or [string]$Receipt.qualified_evidence_bound_atomic_core_blob -cne $CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicCoreBlob -or [string]$Receipt.qualified_recovery_evidence_head -cne $CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceHead -or [string]$Receipt.qualified_recovery_evidence_core_blob -cne $CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceCoreBlob){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-lineage-invalid'}}
    foreach($f in @('binding_fingerprint','consumption_id','permit_transaction_id','journal_transaction_id','recovery_pre_apply_result_fingerprint','recovery_stage_result_fingerprint','generic_stage_result_fingerprint','generic_preparation_fingerprint','evidence_bound_atomic_result_fingerprint','recovery_evidence_fingerprint','prepared_result_material_sha256','journal_entry_sha256','live_tree_sha256','stage_tree_sha256','app_backup_tree_sha256','persistence_fingerprint','bridge_fingerprint')){if(-not(Test-CustomAppProductionDualTransactionIdBridgeSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('dual-id-bridge-receipt-invalid-'+$f)}}}
    if(([string]$Receipt.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-remote-commit-invalid'}}
    try{if([int64]$Receipt.github_repo_id -le 0 -or [int64]$Receipt.journal_revision -lt 3 -or [int]$Receipt.app_backup_file_count -lt 1 -or [int64]$Receipt.app_backup_total_bytes -lt 1){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-numeric-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-numeric-invalid'}}
    if([string]$Receipt.journal_phase -cne 'candidate-live'){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-journal-phase-invalid'}}
    if(-not [bool]$Receipt.transaction_id_namespaces_distinct -or ([string]$Receipt.permit_transaction_id).Trim().ToLowerInvariant() -ceq ([string]$Receipt.journal_transaction_id).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-transaction-namespaces-conflated'}}
    foreach($f in @('requires_bridge_aware_finalization','requires_crash_recovery_by_journal_id','requires_forward_continuity_by_permit_id')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-bridge-receipt-required-flag-false-'+$f)}}}
    foreach($f in @('bridge_is_authority','execution_authorized','finalization_authorized','spicetify_apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-bridge-receipt-authority-escaped-'+$f)}}}
    $expected=Get-CustomAppProductionDualTransactionIdBridgeSha256V010 (Get-CustomAppProductionDualTransactionIdBridgeReceiptMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.bridge_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='dual-id-bridge-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='dual-id-bridge-receipt-valid-zero-authority';bridge_fingerprint=$expected;production_mutation_authorized=$false}
}

function Resolve-CustomAppProductionDualTransactionIdBridgeV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,
        [Parameter(Mandatory=$true)]$RecoveryAwareStageExecutorResult,
        [Parameter(Mandatory=$true)]$EvidenceBoundAtomicResult,
        [Parameter(Mandatory=$true)][string]$ExpectedPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory
    )
    $deny={param([string]$Reason) New-CustomAppProductionDualTransactionIdBridgeDeniedV010 -Reason $Reason}
    if(-not(Test-CustomAppProductionDualTransactionIdBridgeSha256V010($ExpectedPermitTransactionId.Trim().ToLowerInvariant()))){return & $deny 'dual-id-bridge-expected-permit-transaction-id-invalid'}
    $pc=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreparedResult
    if($null-eq$pc -or -not[bool]$pc.ok){return & $deny ('dual-id-bridge-recovery-prepared-invalid:'+[string]$pc.reason)}
    $sc=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $RecoveryAwareStageExecutorResult
    if($null-eq$sc -or -not[bool]$sc.ok){return & $deny ('dual-id-bridge-recovery-stage-invalid:'+[string]$sc.reason)}
    $ac=Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 -Result $EvidenceBoundAtomicResult
    if($null-eq$ac -or -not[bool]$ac.ok){return & $deny ('dual-id-bridge-evidence-bound-atomic-invalid:'+[string]$ac.reason)}

    $permitId=$ExpectedPermitTransactionId.Trim().ToLowerInvariant();$journalId=([string]$EvidenceBoundAtomicResult.transaction_id).Trim().ToLowerInvariant()
    foreach($p in @(@('prepared',[string]$RecoveryAwarePreparedResult.transaction_id),@('stage',[string]$RecoveryAwareStageExecutorResult.transaction_id))){if(([string]$p[1]).Trim().ToLowerInvariant()-cne$permitId){return & $deny ('dual-id-bridge-permit-transaction-continuity-mismatch-'+[string]$p[0])}}
    if($journalId -ceq $permitId){return & $deny 'dual-id-bridge-transaction-namespaces-conflated'}
    if(([string]$RecoveryAwarePreparedResult.recovery_stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-bridge-recovery-stage-fingerprint-mismatch'}

    $genericPrepared=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreparedResult
    $gc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $genericPrepared
    if($null-eq$gc -or -not[bool]$gc.ok){return & $deny ('dual-id-bridge-generic-prepared-invalid:'+[string]$gc.reason)}

    $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory
    if($null-eq$journal -or -not[bool]$journal.ok){return & $deny ('dual-id-bridge-journal-read-denied:'+[string]$journal.reason)}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant()-cne$journalId){return & $deny 'dual-id-bridge-journal-transaction-mismatch'}
    if([string]$journal.entry.phase-cne'candidate-live' -or [int64]$journal.revision-lt3){return & $deny 'dual-id-bridge-journal-not-candidate-live'}
    if(([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()-cne([string]$EvidenceBoundAtomicResult.journal_entry_sha256).Trim().ToLowerInvariant()){return & $deny 'dual-id-bridge-journal-entry-fingerprint-mismatch'}
    if([int64]$journal.revision-ne[int64]$EvidenceBoundAtomicResult.journal_revision){return & $deny 'dual-id-bridge-journal-revision-mismatch'}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedTransactionId $journalId
    if($null-eq$evidence -or -not[bool]$evidence.ok){return & $deny ('dual-id-bridge-recovery-evidence-read-denied:'+[string]$evidence.reason)}
    if(([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant()-cne([string]$EvidenceBoundAtomicResult.recovery_evidence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'dual-id-bridge-recovery-evidence-fingerprint-mismatch'}
    if(([string]$evidence.transaction_id).Trim().ToLowerInvariant()-cne$journalId){return & $deny 'dual-id-bridge-recovery-evidence-transaction-mismatch'}

    $anchor=Test-CustomAppProductionRecoveryEvidencePreparedAnchorV010 -PreparedResult $genericPrepared -JournalEntry $journal.entry
    if($null-eq$anchor -or -not[bool]$anchor.ok){return & $deny ('dual-id-bridge-prepared-evidence-anchor-invalid:'+[string]$anchor.reason)}
    $env=$evidence.envelope
    $scalarPairs=@(
        @('name',[string]$RecoveryAwarePreparedResult.name,[string]$env.name),@('source_identity',[string]$RecoveryAwarePreparedResult.source_identity,[string]$env.source_identity),@('remote_commit_sha',[string]$RecoveryAwarePreparedResult.remote_commit_sha,[string]$env.remote_commit_sha),
        @('consumption_id',[string]$RecoveryAwarePreparedResult.consumption_id,[string]$env.consumption_id),@('generic_stage_result_fingerprint',[string]$RecoveryAwarePreparedResult.generic_stage_result_fingerprint,[string]$env.stage_result_fingerprint),@('generic_preparation_fingerprint',[string]$RecoveryAwarePreparedResult.generic_preparation_fingerprint,[string]$env.preparation_fingerprint),
        @('live_tree_sha256',[string]$RecoveryAwarePreparedResult.live_tree_sha256,[string]$env.live_tree_sha256),@('stage_tree_sha256',[string]$RecoveryAwarePreparedResult.stage_tree_sha256,[string]$env.stage_tree_sha256),@('app_backup_tree_sha256',[string]$RecoveryAwarePreparedResult.app_backup_tree_sha256,[string]$env.app_backup_tree_sha256),@('persistence_fingerprint',[string]$RecoveryAwarePreparedResult.persistence_fingerprint,[string]$env.persistence_fingerprint)
    )
    foreach($p in $scalarPairs){if(([string]$p[1]).Trim().ToLowerInvariant()-cne([string]$p[2]).Trim().ToLowerInvariant()){return & $deny ('dual-id-bridge-prepared-evidence-mismatch-'+[string]$p[0])}}
    $pathPairs=@(
        @('live_path',[string]$EvidenceBoundAtomicResult.live_path,[string]$env.live_path),@('transaction_root',[string]$EvidenceBoundAtomicResult.transaction_root,[string]$env.transaction_root),@('stage_workspace_path',[string]$RecoveryAwarePreparedResult.stage_workspace_path,[string]$env.stage_workspace_path),@('app_backup_path',[string]$RecoveryAwarePreparedResult.app_backup_path,[string]$env.app_backup_path),@('persistence_backup_path',[string]$RecoveryAwarePreparedResult.persistence_backup_path,[string]$env.persistence_backup_path),@('stage_path',[string]$RecoveryAwarePreparedResult.stage_path,[string]$EvidenceBoundAtomicResult.stage_path)
    )
    foreach($p in $pathPairs){if(-not(Test-CustomAppProductionDualTransactionIdBridgePathEqualV010 -A ([string]$p[1]) -B ([string]$p[2]))){return & $deny ('dual-id-bridge-path-mismatch-'+[string]$p[0])}}
    try{if([int]$RecoveryAwarePreparedResult.app_backup_file_count-ne[int]$env.app_backup_file_count -or [int64]$RecoveryAwarePreparedResult.app_backup_total_bytes-ne[int64]$env.app_backup_total_bytes){return & $deny 'dual-id-bridge-app-backup-count-mismatch'}}catch{return & $deny 'dual-id-bridge-app-backup-count-invalid'}
    if(([string]$anchor.prepared_material_sha256).Trim().ToLowerInvariant()-cne([string]$env.prepared_result_material_sha256).Trim().ToLowerInvariant()){return & $deny 'dual-id-bridge-prepared-material-fingerprint-mismatch'}

    $r=[pscustomobject]@{
        schema=$CustomAppProductionDualTransactionIdBridgeSchema;managed_by=$CustomAppProductionDualTransactionIdBridgeManagedBy
        qualified_recovery_aware_prepared_head=$CustomAppProductionDualTransactionIdBridgeQualifiedPreparedHead;qualified_recovery_aware_prepared_core_blob=$CustomAppProductionDualTransactionIdBridgeQualifiedPreparedCoreBlob
        qualified_evidence_bound_atomic_head=$CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicHead;qualified_evidence_bound_atomic_core_blob=$CustomAppProductionDualTransactionIdBridgeQualifiedEvidenceBoundAtomicCoreBlob
        qualified_recovery_evidence_head=$CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceHead;qualified_recovery_evidence_core_blob=$CustomAppProductionDualTransactionIdBridgeQualifiedRecoveryEvidenceCoreBlob
        status='dual-transaction-id-namespaces-durably-bound';reason='permit-forward-id-and-journal-recovery-id-bound-to-same-prepared-evidence'
        name=[string]$RecoveryAwarePreparedResult.name;source_identity=[string]$RecoveryAwarePreparedResult.source_identity;github_repo_id=[int64]$RecoveryAwarePreparedResult.github_repo_id;surface_kind=[string]$RecoveryAwarePreparedResult.surface_kind;remote_commit_sha=([string]$RecoveryAwarePreparedResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$RecoveryAwarePreparedResult.binding_fingerprint).Trim().ToLowerInvariant();consumption_id=([string]$RecoveryAwarePreparedResult.consumption_id).Trim().ToLowerInvariant()
        permit_transaction_id=$permitId;journal_transaction_id=$journalId;transaction_id_namespaces_distinct=$true
        recovery_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();recovery_stage_result_fingerprint=([string]$RecoveryAwareStageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();generic_stage_result_fingerprint=([string]$RecoveryAwarePreparedResult.generic_stage_result_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$RecoveryAwarePreparedResult.generic_preparation_fingerprint).Trim().ToLowerInvariant()
        evidence_bound_atomic_result_fingerprint=([string]$EvidenceBoundAtomicResult.result_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant();prepared_result_material_sha256=([string]$env.prepared_result_material_sha256).Trim().ToLowerInvariant()
        journal_phase=[string]$journal.entry.phase;journal_revision=[int64]$journal.revision;journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()
        live_path=[string]$EvidenceBoundAtomicResult.live_path;transaction_root=[string]$EvidenceBoundAtomicResult.transaction_root;stage_workspace_path=[string]$RecoveryAwarePreparedResult.stage_workspace_path;stage_path=[string]$RecoveryAwarePreparedResult.stage_path;app_backup_path=[string]$RecoveryAwarePreparedResult.app_backup_path;persistence_backup_path=[string]$RecoveryAwarePreparedResult.persistence_backup_path
        live_tree_sha256=([string]$RecoveryAwarePreparedResult.live_tree_sha256).Trim().ToLowerInvariant();stage_tree_sha256=([string]$RecoveryAwarePreparedResult.stage_tree_sha256).Trim().ToLowerInvariant();app_backup_tree_sha256=([string]$RecoveryAwarePreparedResult.app_backup_tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$RecoveryAwarePreparedResult.app_backup_file_count;app_backup_total_bytes=[int64]$RecoveryAwarePreparedResult.app_backup_total_bytes;persistence_fingerprint=([string]$RecoveryAwarePreparedResult.persistence_fingerprint).Trim().ToLowerInvariant()
        requires_bridge_aware_finalization=$true;requires_crash_recovery_by_journal_id=$true;requires_forward_continuity_by_permit_id=$true
        bridge_is_authority=$false;execution_authorized=$false;finalization_authorized=$false;spicetify_apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;bridge_fingerprint=$null
    }
    $r.bridge_fingerprint=Get-CustomAppProductionDualTransactionIdBridgeSha256V010 (Get-CustomAppProductionDualTransactionIdBridgeReceiptMaterialV010 -Receipt $r)
    $rc=Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 -Receipt $r
    if(-not[bool]$rc.ok){return & $deny ('dual-id-bridge-output-invalid:'+[string]$rc.reason)}
    return [pscustomobject]@{ok=$true;reason='dual-transaction-id-bridge-verified-zero-authority';receipt=$r;bridge_is_authority=$false;execution_authorized=$false;finalization_authorized=$false;spicetify_apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
