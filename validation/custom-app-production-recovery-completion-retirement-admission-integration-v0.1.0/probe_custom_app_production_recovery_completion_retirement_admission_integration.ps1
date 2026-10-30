param(
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
    [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
    [Parameter(Mandatory=$true)][string]$AppDataRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Core-only load: no parent test harness and no RestoreExecutorResult input.
$load=@(
    'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1',
    'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
    'validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1',
    'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
    'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
    'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1',
    'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1',
    'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1',
    'validation/custom-app-production-recovery-artifact-retirement-admission-v0.1.0/custom-app-production-recovery-artifact-retirement-admission.ps1',
    'validation/custom-app-production-recovery-completion-evidence-v0.1.0/custom-app-production-recovery-completion-evidence.ps1',
    'validation/custom-app-production-recovery-completion-retirement-admission-integration-v0.1.0/custom-app-production-recovery-completion-retirement-admission-integration.ps1'
)
foreach($rel in $load){$path=Join-Path $root $rel;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "bridge probe dependency missing: $rel"};. $path}

$r=Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now ([DateTimeOffset]::UtcNow)
if($null-eq$r){throw 'bridge probe returned null'}
if(-not[bool]$r.ok){throw ('bridge probe denied: '+[string]$r.reason)}
$c=Test-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationReceiptV010 -Receipt $r.receipt -Now ([DateTimeOffset]::UtcNow)
if(-not[bool]$c.ok){throw ('bridge probe receipt invalid: '+[string]$c.reason)}
[ordered]@{
    ok=$true
    reason=[string]$r.reason
    transaction_id=[string]$r.receipt.transaction_id
    completion_fingerprint=[string]$r.receipt.completion_fingerprint
    executor_result_fingerprint=[string]$r.receipt.executor_result_fingerprint
    retirement_admission_fingerprint=[string]$r.receipt.retirement_admission_fingerprint
    evidence_fingerprint=[string]$r.receipt.evidence_fingerprint
    journal_revision=[int64]$r.receipt.rollback_complete_revision
    journal_entry_sha256=[string]$r.receipt.rollback_complete_entry_sha256
    retirement_needed=[bool]$r.receipt.retirement_needed
    retirement_eligible=[bool]$r.receipt.retirement_eligible
    retirement_already_complete=[bool]$r.receipt.retirement_already_complete
    transaction_status=[string]$r.receipt.transaction_status
    stage_status=[string]$r.receipt.stage_status
    app_backup_status=[string]$r.receipt.app_backup_status
    persistence_backup_status=[string]$r.receipt.persistence_backup_status
    durable_completion_reloaded=[bool]$r.receipt.durable_completion_reloaded
    embedded_restore_result_revalidated=[bool]$r.receipt.embedded_restore_result_revalidated
    fresh_retirement_admission_revalidated=[bool]$r.receipt.fresh_retirement_admission_revalidated
    requires_future_executor_fresh_revalidation=[bool]$r.receipt.requires_future_executor_fresh_revalidation
    requires_new_update_permit=[bool]$r.receipt.requires_new_update_permit
    integration_is_authority=[bool]$r.receipt.integration_is_authority
    execution_authorized=[bool]$r.receipt.execution_authorized
    restore_authorized=[bool]$r.receipt.restore_authorized
    apply_authorized=[bool]$r.receipt.apply_authorized
    cleanup_authorized=[bool]$r.receipt.cleanup_authorized
    production_mutation_authorized=[bool]$r.receipt.production_mutation_authorized
    integration_fingerprint=[string]$r.receipt.integration_fingerprint
}|ConvertTo-Json -Compress
