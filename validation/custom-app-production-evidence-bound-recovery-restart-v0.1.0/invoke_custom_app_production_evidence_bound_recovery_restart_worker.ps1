param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$load=@(
    'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1',
    'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
    'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
    'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1',
    'validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1',
    'validation/custom-app-production-recovery-execution-admission-v0.1.0/custom-app-production-recovery-execution-admission.ps1',
    'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/custom-app-production-recovery-evidence-admission-integration.ps1',
    'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1',
    'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1',
    'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
    'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1',
    'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1'
)
foreach($relative in $load){
    $p=Join-Path $root $relative
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "recovery restart worker dependency missing: $relative"}
    . $p
}

$state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
$out=[ordered]@{
    schema=1
    managed_by='custom-app-production-evidence-bound-recovery-restart-worker-v1'
    success=$false
    error=''
    process_id=$PID
    transaction_id=[string]$state.transaction_id
    expected_start_phase=[string]$state.expected_start_phase
    admission_ok=$false
    admission_reason=''
    admission_phase=''
    admission_fingerprint=''
    executor_ok=$false
    executor_reason=''
    executor_started_phase=''
    rollback_required_was_appended=$false
    restore_performed=$false
    recovery_apply_executed=$false
    rollback_complete_persisted=$false
    executor_result_fingerprint=''
    final_phase=''
    final_revision=-1
    final_entry_sha256=''
    evidence_fingerprint_after=''
    apply_count=0
}

try {
    foreach($name in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $env:SC_RX_COUNT=[string]$state.apply_count_path
    $env:SC_RX_LIVE=[string]$state.live_probe_path
    $env:SC_RX_APPLIED=[string]$state.applied_probe_path
    $env:SC_RX_MODE='success'

    $now=[DateTimeOffset]::UtcNow
    $admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 `
        -AllowedRoot ([string]$state.allowed_root) `
        -StoreDirectory ([string]$state.store_directory) `
        -ExpectedTransactionId ([string]$state.transaction_id) `
        -LocalAppDataRoot ([string]$state.local_app_data_root) `
        -AppDataRoot ([string]$state.app_data_root) `
        -SpicetifyAllowedRoot ([string]$state.spicetify_allowed_root) `
        -SpicetifyPath ([string]$state.spicetify_path) `
        -ExpectedSpicetifySha256 ([string]$state.spicetify_sha256) `
        -Now $now
    $out.admission_ok=[bool]$admission.ok
    $out.admission_reason=[string]$admission.reason
    if(-not [bool]$admission.ok){throw ('cross-process restore admission denied: '+[string]$admission.reason)}
    $ac=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $admission.receipt -Now $now.AddSeconds(1)
    if(-not [bool]$ac.ok){throw ('cross-process restore admission receipt invalid: '+[string]$ac.reason)}
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if([bool]$admission.receipt.$f){throw ('cross-process restore admission authority escaped '+$f)}
    }
    $out.admission_phase=[string]$admission.receipt.phase
    $out.admission_fingerprint=[string]$admission.receipt.restore_resume_admission_fingerprint
    if([string]$admission.receipt.phase -cne [string]$state.expected_start_phase){throw "cross-process admission phase mismatch actual=$([string]$admission.receipt.phase) expected=$([string]$state.expected_start_phase)"}

    $exec=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 `
        -AllowedRoot ([string]$state.allowed_root) `
        -StoreDirectory ([string]$state.store_directory) `
        -ExpectedTransactionId ([string]$state.transaction_id) `
        -LocalAppDataRoot ([string]$state.local_app_data_root) `
        -AppDataRoot ([string]$state.app_data_root) `
        -SpicetifyAllowedRoot ([string]$state.spicetify_allowed_root) `
        -SpicetifyPath ([string]$state.spicetify_path) `
        -ExpectedSpicetifySha256 ([string]$state.spicetify_sha256) `
        -Now ([DateTimeOffset]::UtcNow) `
        -TimeoutSeconds 30
    $out.executor_ok=[bool]$exec.ok
    $out.executor_reason=[string]$exec.reason
    if(-not [bool]$exec.ok){throw ('cross-process restore executor denied: '+[string]$exec.reason)}
    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $exec.result
    if(-not [bool]$rc.ok){throw ('cross-process restore executor result invalid: '+[string]$rc.reason)}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if([bool]$exec.result.$f){throw ('cross-process restore executor authority escaped '+$f)}
    }
    $out.executor_started_phase=[string]$exec.result.started_phase
    $out.rollback_required_was_appended=[bool]$exec.result.rollback_required_was_appended
    $out.restore_performed=[bool]$exec.result.restore_performed
    $out.recovery_apply_executed=[bool]$exec.result.recovery_apply_executed
    $out.rollback_complete_persisted=[bool]$exec.result.rollback_complete_persisted
    $out.executor_result_fingerprint=[string]$exec.result.result_fingerprint
    if([string]$exec.result.started_phase -cne [string]$state.expected_start_phase){throw 'cross-process executor started-phase mismatch'}

    $final=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
    if($null -eq $final -or -not [bool]$final.ok){throw 'cross-process final journal read denied'}
    $out.final_phase=[string]$final.entry.phase
    $out.final_revision=[int64]$final.revision
    $out.final_entry_sha256=[string]$final.entry.entry_sha256
    if([string]$final.entry.phase -cne 'rollback-complete'){throw 'cross-process final journal phase is not rollback-complete'}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id)
    if($null -eq $evidence -or -not [bool]$evidence.ok){throw ('cross-process evidence unreadable after rollback-complete: '+[string]$evidence.reason)}
    $out.evidence_fingerprint_after=[string]$evidence.evidence_fingerprint
    if([string]$evidence.evidence_fingerprint -cne [string]$state.evidence_fingerprint){throw 'cross-process recovery evidence fingerprint drift'}

    if(Test-Path -LiteralPath ([string]$state.apply_count_path) -PathType Leaf){$out.apply_count=[int]([IO.File]::ReadAllText([string]$state.apply_count_path).Trim())}
    if([int]$out.apply_count -ne 1){throw "cross-process recovery apply count mismatch $($out.apply_count)"}
    $out.success=$true
} catch {
    $out.error=[string]$_.Exception.Message
} finally {
    foreach($name in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $json=$out | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($ResultPath,$json,[Text.UTF8Encoding]::new($false))
}
if(-not [bool]$out.success){throw ('recovery restart worker failed: '+[string]$out.error)}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTART_WORKER_PASS phase=$($out.executor_started_phase) pid=$PID"
