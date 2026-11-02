param(
    [Parameter(Mandatory=$true)][string]$StatePath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$state=(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)

# Load the exact validated dependency chain without importing test harness side effects.
. (Join-Path $root 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1')
. (Join-Path $root 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1')

$now=[DateTimeOffset]::UtcNow
$common=@{
    AllowedRoot=[string]$state.allowed_root
    StoreDirectory=[string]$state.store_directory
    ExpectedTransactionId=([string]$state.transaction_id).Trim().ToLowerInvariant()
    LocalAppDataRoot=[string]$state.local_appdata_root
    AppDataRoot=[string]$state.appdata_root
    SpicetifyAllowedRoot=[string]$state.spicetify_allowed_root
    SpicetifyPath=[string]$state.spicetify_path
    ExpectedSpicetifySha256=([string]$state.spicetify_sha256).Trim().ToLowerInvariant()
}

$admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 @common -Now $now
if($null -eq $admission -or -not [bool]$admission.ok){throw ('integration-worker-initial-admission-denied:'+[string]$admission.reason)}
$admissionCheck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $admission.receipt -Now $now.AddSeconds(1)
if(-not [bool]$admissionCheck.ok){throw ('integration-worker-initial-admission-invalid:'+[string]$admissionCheck.reason)}
if(([string]$admission.receipt.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$state.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-evidence-fingerprint-drift-before-executor'}
if(([string]$admission.receipt.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$state.preparation_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-preparation-fingerprint-drift-before-executor'}

$exec=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 @common -Now $now.AddMilliseconds(10) -TimeoutSeconds 30
if($null -eq $exec -or -not [bool]$exec.ok){throw ('integration-worker-executor-denied:'+[string]$exec.reason)}
$execCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $exec.result
if(-not [bool]$execCheck.ok){throw ('integration-worker-executor-result-invalid:'+[string]$execCheck.reason)}
if(([string]$exec.result.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$state.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-evidence-fingerprint-drift-after-executor'}
if(([string]$exec.result.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$state.preparation_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-preparation-fingerprint-drift-after-executor'}
if(([string]$exec.result.transaction_id).Trim().ToLowerInvariant() -cne ([string]$state.transaction_id).Trim().ToLowerInvariant()){throw 'integration-worker-transaction-id-drift-after-executor'}

$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
if($null -eq $journal -or -not [bool]$journal.ok -or [string]$journal.entry.phase -cne 'rollback-complete'){throw 'integration-worker-final-journal-not-rollback-complete'}
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id)
if($null -eq $evidence -or -not [bool]$evidence.ok){throw ('integration-worker-final-evidence-unreadable:'+[string]$evidence.reason)}
if(([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$state.evidence_fingerprint).Trim().ToLowerInvariant()){throw 'integration-worker-final-evidence-fingerprint-drift'}

$out=[pscustomobject]@{
    ok=$true
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
[IO.File]::WriteAllText([string]$state.worker_result_path,($out|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ('EVIDENCE_BOUND_RECOVERY_RESTORE_WORKER_PASS phase='+[string]$out.initial_phase+' tx='+[string]$out.transaction_id)
