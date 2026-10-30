$CustomAppProductionRecoveryArtifactRetirementAdmissionSchema = 1
$CustomAppProductionRecoveryArtifactRetirementAdmissionManagedBy = 'custom-app-production-recovery-artifact-retirement-admission-v1'
$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedRestoreExecutorHead = 'c3e1f960447ba84d2410af9c37a22a384f2a5436'
$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'
$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'

function Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_restore_executor_head,[string]$Receipt.qualified_evidence_head,[string]$Receipt.qualified_journal_head,
        [string]$Receipt.transaction_id,[string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.remote_commit_sha,[string]$Receipt.consumption_id,[string]$Receipt.preparation_fingerprint,[string]$Receipt.evidence_fingerprint,[string]$Receipt.restore_result_fingerprint,
        [string]$Receipt.phase,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,
        [string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.stage_workspace_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,
        [string]$Receipt.transaction_status,[string]$Receipt.transaction_old_status,[string]$Receipt.transaction_candidate_status,[string]$Receipt.stage_status,[string]$Receipt.app_backup_status,[string]$Receipt.persistence_backup_status,
        [string]$Receipt.live_tree_sha256,[string]$Receipt.persistence_fingerprint,[string]$Receipt.retirement_needed,[string]$Receipt.retirement_eligible,[string]$Receipt.retirement_already_complete,[string]$Receipt.requires_bounded_artifact_retirement,[string]$Receipt.requires_future_executor_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.admission_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_restore_executor_head','qualified_evidence_head','qualified_journal_head','transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','evidence_fingerprint','restore_result_fingerprint','phase','journal_revision','journal_entry_sha256','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_status','transaction_old_status','transaction_candidate_status','stage_status','app_backup_status','persistence_backup_status','live_tree_sha256','persistence_fingerprint','retirement_needed','retirement_eligible','retirement_already_complete','requires_bounded_artifact_retirement','requires_future_executor_fresh_revalidation','checked_at','eligible_until','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','receipt_fingerprint')){
        if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-admission-field-missing-'+$f)}}
    }
    if([int]$Receipt.schema -ne 1 -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryArtifactRetirementAdmissionManagedBy -or [string]$Receipt.qualified_restore_executor_head -cne $CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedRestoreExecutorHead -or [string]$Receipt.qualified_evidence_head -cne $CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedEvidenceHead -or [string]$Receipt.qualified_journal_head -cne $CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedJournalHead){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-owner-schema-parent-invalid'}}
    foreach($f in @('transaction_id','consumption_id','preparation_fingerprint','evidence_fingerprint','restore_result_fingerprint','journal_entry_sha256','live_tree_sha256','persistence_fingerprint','receipt_fingerprint')){if(-not(Test-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-admission-invalid-'+$f)}}}
    if(([string]$Receipt.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-remote-commit-invalid'}}
    if([string]$Receipt.phase -cne 'rollback-complete'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-phase-invalid'}}
    foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){if([string]$Receipt.$f -notin @('present-verified','already-absent')){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-admission-status-invalid-'+$f)}}}
    foreach($f in @('transaction_old_status','transaction_candidate_status')){if([string]$Receipt.$f -notin @('present-verified','absent')){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-admission-status-invalid-'+$f)}}}
    if([string]$Receipt.transaction_status -ceq 'already-absent' -and ([string]$Receipt.transaction_old_status -cne 'absent' -or [string]$Receipt.transaction_candidate_status -cne 'absent')){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-transaction-child-status-drift'}}
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-admission-authority-escaped-'+$f)}}}
    if(-not [bool]$Receipt.requires_future_executor_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-fresh-revalidation-contract-missing'}}
    $expectedNeeded=([string]$Receipt.transaction_status -ceq 'present-verified' -or [string]$Receipt.stage_status -ceq 'present-verified' -or [string]$Receipt.app_backup_status -ceq 'present-verified' -or [string]$Receipt.persistence_backup_status -ceq 'present-verified')
    if([bool]$Receipt.retirement_needed -ne [bool]$expectedNeeded){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-semantic-status-drift'}}
    $needed=[bool]$expectedNeeded
    if($needed){if(-not[bool]$Receipt.retirement_eligible -or [bool]$Receipt.retirement_already_complete -or -not[bool]$Receipt.requires_bounded_artifact_retirement){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-needed-semantics-invalid'}}}
    else{if([bool]$Receipt.retirement_eligible -or -not[bool]$Receipt.retirement_already_complete -or [bool]$Receipt.requires_bounded_artifact_retirement){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-complete-semantics-invalid'}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start) -or -not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-time-invalid'}}
    if($end -le $start -or $end -gt $start.AddSeconds(15)){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-window-invalid'}}
    if($Now -lt $start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-not-yet-valid'}}
    if($Now -ge $end){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-expired'}}
    $expected=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.receipt_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-artifact-retirement-admission-valid-zero-authority';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();retirement_needed=$needed;retirement_eligible=[bool]$Receipt.retirement_eligible}
}

function Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$RestoreExecutorResult,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not(Test-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 $tx)){return & $deny 'recovery-artifact-retirement-admission-transaction-id-invalid'}

    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $RestoreExecutorResult
    if(-not[bool]$rc.ok){return & $deny ('recovery-artifact-retirement-admission-restore-result-invalid:'+[string]$rc.reason)}
    if(([string]$RestoreExecutorResult.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-artifact-retirement-admission-restore-result-transaction-mismatch'}
    if(-not[bool]$RestoreExecutorResult.rollback_complete_persisted -or -not[bool]$RestoreExecutorResult.requires_recovery_artifact_retirement){return & $deny 'recovery-artifact-retirement-admission-restore-result-contract-invalid'}

    try{$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('recovery-artifact-retirement-admission-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$journal -or -not[bool]$journal.ok -or $null-eq$journal.entry){return & $deny 'recovery-artifact-retirement-admission-journal-invalid'}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$journal.entry.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-artifact-retirement-admission-journal-transaction-mismatch'}
    if([string]$journal.entry.phase -cne 'rollback-complete'){return & $deny 'recovery-artifact-retirement-admission-phase-not-rollback-complete'}
    if([int64]$RestoreExecutorResult.rollback_complete_revision -ne [int64]$journal.revision -or ([string]$RestoreExecutorResult.rollback_complete_entry_sha256).Trim().ToLowerInvariant() -cne ([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-artifact-retirement-admission-restore-result-journal-completion-mismatch'}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$evidence -or -not[bool]$evidence.ok){return & $deny ('recovery-artifact-retirement-admission-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$e.$f){return & $deny ('recovery-artifact-retirement-admission-evidence-authority-escaped-'+$f)}}

    $identityPairs=@(
        @('name',[string]$journal.entry.name),@('source_identity',[string]$journal.entry.source_identity),@('remote_commit_sha',[string]$journal.entry.remote_commit_sha),@('consumption_id',[string]$journal.entry.consumption_id),@('preparation_fingerprint',[string]$journal.entry.preparation_fingerprint)
    )
    foreach($p in $identityPairs){$field=[string]$p[0];$jv=[string]$p[1];if(([string]$e.$field).Trim().ToLowerInvariant() -cne $jv.Trim().ToLowerInvariant()){return & $deny ('recovery-artifact-retirement-admission-evidence-journal-mismatch-'+$field)};if(([string]$RestoreExecutorResult.$field).Trim().ToLowerInvariant() -cne ([string]$e.$field).Trim().ToLowerInvariant()){return & $deny ('recovery-artifact-retirement-admission-restore-result-evidence-mismatch-'+$field)}}
    if(([string]$RestoreExecutorResult.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$e.evidence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-artifact-retirement-admission-restore-result-evidence-fingerprint-mismatch'}
    foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){
        if(-not(Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 -A ([string]$e.$f) -B ([string]$journal.entry.$f))){return & $deny ('recovery-artifact-retirement-admission-evidence-journal-path-mismatch-'+$f)}
        if(-not(Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 -A ([string]$RestoreExecutorResult.$f) -B ([string]$e.$f))){return & $deny ('recovery-artifact-retirement-admission-restore-result-evidence-path-mismatch-'+$f)}
    }
    if(([string]$RestoreExecutorResult.app_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$e.app_backup_tree_sha256).Trim().ToLowerInvariant() -or ([string]$RestoreExecutorResult.persistence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$e.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-artifact-retirement-admission-restored-state-fingerprint-mismatch'}

    $live=Get-CustomAppProductionRecoveryRestoreResumeLiveStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if($null-eq$live -or -not[bool]$live.ok -or [string]$live.state -cne 'old-live-exact'){return & $deny ('recovery-artifact-retirement-admission-live-not-exact-old-state:'+[string]$live.reason)}
    try{$fullLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$e.live_path)}catch{return & $deny ('recovery-artifact-retirement-admission-live-full-tree-read-failed:'+[string]$_.Exception.Message)}
    if([string]$fullLive.tree_sha256 -cne [string]$e.app_backup_tree_sha256 -or [int]$fullLive.file_count -ne [int]$e.app_backup_file_count -or [int64]$fullLive.total_bytes -ne [int64]$e.app_backup_total_bytes){return & $deny 'recovery-artifact-retirement-admission-live-full-tree-mismatch'}
    try{$persistNow=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('recovery-artifact-retirement-admission-persistence-read-failed:'+[string]$_.Exception.Message)}
    if([string]$persistNow.fingerprint -cne [string]$e.persistence_fingerprint){return & $deny 'recovery-artifact-retirement-admission-protected-persistence-mismatch'}

    $txn=Get-CustomAppProductionRecoveryRestoreResumeTransactionStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if($null-eq$txn -or -not[bool]$txn.ok){return & $deny ('recovery-artifact-retirement-admission-transaction-state-invalid:'+[string]$txn.reason)}
    $stage=Test-CustomAppProductionRecoveryCleanupResumeStageArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot
    if($null-eq$stage -or -not[bool]$stage.ok){return & $deny ('recovery-artifact-retirement-admission-stage-state-invalid:'+[string]$stage.reason)}
    $app=Test-CustomAppProductionRecoveryCleanupResumeAppBackupArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot
    if($null-eq$app -or -not[bool]$app.ok){return & $deny ('recovery-artifact-retirement-admission-app-backup-state-invalid:'+[string]$app.reason)}
    $persist=Test-CustomAppProductionRecoveryCleanupResumePersistenceArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot
    if($null-eq$persist -or -not[bool]$persist.ok){return & $deny ('recovery-artifact-retirement-admission-persistence-backup-state-invalid:'+[string]$persist.reason)}

    $needed=([string]$txn.status -ceq 'present-verified' -or [string]$stage.status -ceq 'present-verified' -or [string]$app.status -ceq 'present-verified' -or [string]$persist.status -ceq 'present-verified')
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryArtifactRetirementAdmissionSchema;managed_by=$CustomAppProductionRecoveryArtifactRetirementAdmissionManagedBy;qualified_restore_executor_head=$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedRestoreExecutorHead;qualified_evidence_head=$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedEvidenceHead;qualified_journal_head=$CustomAppProductionRecoveryArtifactRetirementAdmissionQualifiedJournalHead
        transaction_id=$tx;name=([string]$e.name).Trim().ToLowerInvariant();source_identity=([string]$e.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$e.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$e.consumption_id).Trim().ToLowerInvariant();preparation_fingerprint=([string]$e.preparation_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=([string]$e.evidence_fingerprint).Trim().ToLowerInvariant();restore_result_fingerprint=([string]$RestoreExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        phase='rollback-complete';journal_revision=[int64]$journal.revision;journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()
        live_path=[string]$e.live_path;transaction_root=[string]$e.transaction_root;stage_workspace_path=[string]$e.stage_workspace_path;app_backup_path=[string]$e.app_backup_path;persistence_backup_path=[string]$e.persistence_backup_path
        transaction_status=[string]$txn.status;transaction_old_status=[string]$txn.old_status;transaction_candidate_status=[string]$txn.candidate_status;stage_status=[string]$stage.status;app_backup_status=[string]$app.status;persistence_backup_status=[string]$persist.status
        live_tree_sha256=([string]$fullLive.tree_sha256).Trim().ToLowerInvariant();persistence_fingerprint=([string]$persistNow.fingerprint).Trim().ToLowerInvariant();retirement_needed=[bool]$needed;retirement_eligible=[bool]$needed;retirement_already_complete=(-not[bool]$needed);requires_bounded_artifact_retirement=[bool]$needed;requires_future_executor_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(15).ToUniversalTime().ToString('o')
        admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;receipt_fingerprint=$null
    }
    $receipt.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 -Receipt $receipt)
    return [pscustomobject]@{ok=$true;reason=$(if($needed){'recovery-artifact-retirement-eligible-zero-authority'}else{'recovery-artifact-retirement-already-complete-zero-authority'});receipt=$receipt;evidence=$e;artifacts=[pscustomobject]@{transaction=$txn;stage=$stage;app_backup=$app;persistence_backup=$persist}}
}
