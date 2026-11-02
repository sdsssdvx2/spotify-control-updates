param(
    [Parameter(Mandatory=$true)][string]$StatePath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# The exact #156 test harness is used only as a dependency loader/regression replay in
# this isolated validation worker. It recursively loads the complete historical
# recovery-plan/preflight/evidence/runtime dependency graph without inventing a new
# production loader. The actual recovery below uses the #156/#157 core functions.
. (Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/test_custom_app_production_recovery_restore_resume_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1')

# Load restart state only after the dependency harness has finished. Several historical
# validation harnesses intentionally use generic variables such as $state; loading after
# them proves the durable JSON is the sole restart input and prevents scope pollution.
$restartState=(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
$now=[DateTimeOffset]::UtcNow
$common=@{
    AllowedRoot=[string]$restartState.allowed_root
    StoreDirectory=[string]$restartState.store_directory
    ExpectedTransactionId=([string]$restartState.transaction_id).Trim().ToLowerInvariant()
    LocalAppDataRoot=[string]$restartState.local_appdata_root
    AppDataRoot=[string]$restartState.appdata_root
    SpicetifyAllowedRoot=[string]$restartState.spicetify_allowed_root
    SpicetifyPath=[string]$restartState.spicetify_path
    ExpectedSpicetifySha256=([string]$restartState.spicetify_sha256).Trim().ToLowerInvariant()
}

$admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 @common -Now $now
if($null -eq $admission -or -not [bool]$admission.ok){throw ('integration-worker-initial-admission-denied:'+[string]$admission.reason)}
$admissionCheck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $admission.receipt -Now $now.AddSeconds(1)
if(-not [bool]$admissionCheck.ok){throw ('integration-worker-initial-admission-invalid:'+[string]$admissionCheck.reason)}
if(([string]$admission.receipt.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$restartState.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-evidence-fingerprint-drift-before-executor'}
if(([string]$admission.receipt.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$restartState.preparation_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-preparation-fingerprint-drift-before-executor'}

$exec=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 @common -Now $now.AddMilliseconds(10) -TimeoutSeconds 30
if($null -eq $exec -or -not [bool]$exec.ok){throw ('integration-worker-executor-denied:'+[string]$exec.reason)}
$execCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $exec.result
if(-not [bool]$execCheck.ok){throw ('integration-worker-executor-result-invalid:'+[string]$execCheck.reason)}
if(([string]$exec.result.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$restartState.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-evidence-fingerprint-drift-after-executor'}
if(([string]$exec.result.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$restartState.preparation_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-preparation-fingerprint-drift-after-executor'}
if(([string]$exec.result.transaction_id).Trim().ToLowerInvariant() -cne ([string]$restartState.transaction_id).Trim().ToLowerInvariant()){throw 'integration-worker-transaction-id-drift-after-executor'}

$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$restartState.allowed_root) -StoreDirectory ([string]$restartState.store_directory)
if($null -eq $journal -or -not [bool]$journal.ok -or [string]$journal.entry.phase -cne 'rollback-complete'){throw 'integration-worker-final-journal-not-rollback-complete'}
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$restartState.allowed_root) -StoreDirectory ([string]$restartState.store_directory) -ExpectedTransactionId ([string]$restartState.transaction_id)
if($null -eq $evidence -or -not [bool]$evidence.ok){throw ('integration-worker-final-evidence-unreadable:'+[string]$evidence.reason)}
if(([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$restartState.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-final-evidence-fingerprint-drift'}

$out=[pscustomobject]@{
    ok=$true
    worker_pid=[int]$PID
    initial_phase=[string]$admission.receipt.phase
    initial_live_state=[string]$admission.receipt.live_state
    initial_transaction_status=[string]$admission.receipt.transaction_status
    initial_evidence_fingerprint=([string]$admission.receipt.evidence_fingerprint).Trim().ToLowerInvariant()
    executor_started_phase=[string]$exec.result.started_phase
    executor_result_fingerprint=([string]$exec.result.result_fingerprint).Trim().ToLowerInvariant()
    transaction_id=([string]$exec.result.transaction_id).Trim().ToLowerInvariant()
    evidence_fingerprint=([string]$exec.result.evidence_fingerprint).Trim().ToLowerInvariant()
    preparation_fingerprint=([string]$exec.result.preparation_fingerprint).Trim().ToLowerInvariant()
    rollback_required_was_appended=[bool]$exec.result.rollback_required_was_appended
    restore_performed=[bool]$exec.result.restore_performed
    recovery_apply_executed=[bool]$exec.result.recovery_apply_executed
    rollback_complete_persisted=[bool]$exec.result.rollback_complete_persisted
    final_phase=[string]$journal.entry.phase
    final_revision=[int64]$journal.revision
    result_is_authority=[bool]$exec.result.result_is_authority
    execution_authorized=[bool]$exec.result.execution_authorized
    restore_authorized=[bool]$exec.result.restore_authorized
    apply_authorized=[bool]$exec.result.apply_authorized
    cleanup_authorized=[bool]$exec.result.cleanup_authorized
    production_mutation_authorized=[bool]$exec.result.production_mutation_authorized
}
[IO.File]::WriteAllText([string]$restartState.worker_result_path,($out|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ('EVIDENCE_BOUND_RECOVERY_RESTORE_WORKER_PASS phase='+[string]$out.initial_phase+' tx='+[string]$out.transaction_id)
