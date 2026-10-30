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

# Exact stable v0.6.28 Addon Manager host primitive required by the validated lifecycle core.
function Test-PathSafe {
    param([AllowNull()][AllowEmptyString()][string]$Path,[string]$Type='Any')
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    try{
        if($Type-eq'Leaf'){return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)}
        if($Type-eq'Container'){return [bool](Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue)}
        return [bool](Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
    }catch{return $false}
}

$load=@(
    'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
    'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1',
    'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
    'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
    'validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1',
    'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
    'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
    'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1',
    'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1',
    'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1',
    'validation/custom-app-production-recovery-artifact-retirement-admission-v0.1.0/custom-app-production-recovery-artifact-retirement-admission.ps1',
    'validation/custom-app-production-recovery-completion-evidence-v0.1.0/custom-app-production-recovery-completion-evidence.ps1',
    'validation/custom-app-production-recovery-completion-retirement-admission-integration-v0.1.0/custom-app-production-recovery-completion-retirement-admission-integration.ps1',
    'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1',
    'validation/custom-app-production-recovery-artifact-retirement-executor-v0.1.0/custom-app-production-recovery-artifact-retirement-executor.ps1',
    'validation/custom-app-production-recovery-artifact-retirement-resume-executor-v0.1.0/custom-app-production-recovery-artifact-retirement-resume-executor.ps1'
)
foreach($rel in $load){$path=Join-Path $root $rel;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "retirement resume probe dependency missing: $rel"};. $path}

$r=Invoke-CustomAppProductionRecoveryArtifactRetirementResumeExecutorV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now ([DateTimeOffset]::UtcNow)
if($null-eq$r){throw 'retirement resume probe returned null'}
if(-not[bool]$r.ok){throw ('retirement resume probe denied: '+[string]$r.reason)}
$c=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $r.result
if(-not[bool]$c.ok){throw ('retirement resume probe result invalid: '+[string]$c.reason)}
[ordered]@{
    ok=$true
    reason=[string]$r.reason
    transaction_id=[string]$r.result.transaction_id
    completion_fingerprint=[string]$r.result.completion_fingerprint
    embedded_restore_result_fingerprint=[string]$r.result.embedded_restore_result_fingerprint
    retirement_executor_result_fingerprint=[string]$r.result.retirement_executor_result_fingerprint
    initial_bridge_fingerprint=[string]$r.result.initial_bridge_fingerprint
    final_bridge_fingerprint=[string]$r.result.final_bridge_fingerprint
    transaction_action=[string]$r.result.transaction_action
    stage_action=[string]$r.result.stage_action
    app_backup_action=[string]$r.result.app_backup_action
    persistence_backup_action=[string]$r.result.persistence_backup_action
    retirement_performed=[bool]$r.result.retirement_performed
    initially_already_complete=[bool]$r.result.initially_already_complete
    artifact_retirement_complete=[bool]$r.result.artifact_retirement_complete
    durable_completion_reloaded_before=[bool]$r.result.durable_completion_reloaded_before
    durable_completion_reloaded_after=[bool]$r.result.durable_completion_reloaded_after
    completion_evidence_retained=[bool]$r.result.completion_evidence_retained
    requires_new_update_permit=[bool]$r.result.requires_new_update_permit
    requires_future_fresh_revalidation=[bool]$r.result.requires_future_fresh_revalidation
    result_is_authority=[bool]$r.result.result_is_authority
    execution_authorized=[bool]$r.result.execution_authorized
    restore_authorized=[bool]$r.result.restore_authorized
    apply_authorized=[bool]$r.result.apply_authorized
    cleanup_authorized=[bool]$r.result.cleanup_authorized
    production_mutation_authorized=[bool]$r.result.production_mutation_authorized
    result_fingerprint=[string]$r.result.result_fingerprint
}|ConvertTo-Json -Compress
