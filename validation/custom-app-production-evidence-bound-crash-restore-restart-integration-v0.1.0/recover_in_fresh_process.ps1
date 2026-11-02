param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [switch]$ExpectReplayDeny
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

. (Join-Path $root 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1')
. (Join-Path $root 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1')
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1')

function Fail-FreshRecovery([string]$Message){throw ('fresh-process-recovery:'+ $Message)}
function Assert-FreshRecoveryFalse([bool]$Value,[string]$Message){if($Value){Fail-FreshRecovery $Message}}
function Assert-FreshRecoveryTrue([bool]$Value,[string]$Message){if(-not $Value){Fail-FreshRecovery $Message}}
function Assert-FreshRecoveryEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){Fail-FreshRecovery ("$Message actual=<$Actual> expected=<$Expected>")}}

if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){Fail-FreshRecovery 'state-file-missing'}
$s=Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
$required=@('allowed_root','store_directory','transaction_id','local_app_data_root','app_data_root','spicetify_allowed_root','spicetify_path','spicetify_sha256','expected_app_tree_sha256','expected_app_file_count','expected_app_total_bytes','expected_persistence_fingerprint','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_root','result_path')
foreach($f in $required){if(-not $s.PSObject.Properties[$f] -or [string]::IsNullOrWhiteSpace([string]$s.$f)){Fail-FreshRecovery ('state-field-missing-'+$f)}}
$now=[DateTimeOffset]::UtcNow

if($ExpectReplayDeny){
    $admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root) -SpicetifyAllowedRoot ([string]$s.spicetify_allowed_root) -SpicetifyPath ([string]$s.spicetify_path) -ExpectedSpicetifySha256 ([string]$s.spicetify_sha256) -Now $now
    Assert-FreshRecoveryFalse ([bool]$admission.ok) 'rollback-complete replay admission unexpectedly allowed'
    if([string]$admission.reason -notlike '*phase-not-auto-restorable*'){Fail-FreshRecovery ('replay-admission-reason-drift:'+ [string]$admission.reason)}
    $executor=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root) -SpicetifyAllowedRoot ([string]$s.spicetify_allowed_root) -SpicetifyPath ([string]$s.spicetify_path) -ExpectedSpicetifySha256 ([string]$s.spicetify_sha256) -Now $now -TimeoutSeconds 20
    Assert-FreshRecoveryFalse ([bool]$executor.ok) 'rollback-complete replay executor unexpectedly allowed'
    if([string]$executor.reason -notlike '*phase-not-auto-restorable*'){Fail-FreshRecovery ('replay-executor-reason-drift:'+ [string]$executor.reason)}
    $out=[pscustomobject]@{ok=$true;mode='replay-denied';transaction_id=[string]$s.transaction_id;admission_reason=[string]$admission.reason;executor_reason=[string]$executor.reason;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
    [IO.File]::WriteAllText([string]$s.result_path,($out|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    Write-Output 'CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_CRASH_RESTORE_FRESH_PROCESS_REPLAY_DENIED'
    exit 0
}

$before=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root) -SpicetifyAllowedRoot ([string]$s.spicetify_allowed_root) -SpicetifyPath ([string]$s.spicetify_path) -ExpectedSpicetifySha256 ([string]$s.spicetify_sha256) -Now $now
Assert-FreshRecoveryTrue ([bool]$before.ok) ('pre-executor admission denied:'+ [string]$before.reason)
$bc=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $before.receipt -Now $now
Assert-FreshRecoveryTrue ([bool]$bc.ok) ('pre-executor receipt invalid:'+ [string]$bc.reason)
if([string]$before.receipt.phase -notin @('live-moved-to-old','candidate-live')){Fail-FreshRecovery ('unexpected-start-phase:'+ [string]$before.receipt.phase)}
foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-FreshRecoveryFalse ([bool]$before.receipt.$f) ('admission-authority-escaped-'+$f)}

$run=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root) -SpicetifyAllowedRoot ([string]$s.spicetify_allowed_root) -SpicetifyPath ([string]$s.spicetify_path) -ExpectedSpicetifySha256 ([string]$s.spicetify_sha256) -Now $now.AddMilliseconds(10) -TimeoutSeconds 20
Assert-FreshRecoveryTrue ([bool]$run.ok) ('restore executor denied:'+ [string]$run.reason)
$rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $run.result
Assert-FreshRecoveryTrue ([bool]$rc.ok) ('restore executor result invalid:'+ [string]$rc.reason)
Assert-FreshRecoveryEq $run.result.started_phase $before.receipt.phase 'executor start phase drift'
Assert-FreshRecoveryTrue ([bool]$run.result.restore_performed) 'executor did not restore'
Assert-FreshRecoveryTrue ([bool]$run.result.recovery_apply_executed) 'executor did not recovery-apply'
Assert-FreshRecoveryTrue ([bool]$run.result.rollback_complete_persisted) 'executor did not persist rollback-complete'
foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-FreshRecoveryFalse ([bool]$run.result.$f) ('executor-authority-escaped-'+$f)}

$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory)
Assert-FreshRecoveryTrue ([bool]$journal.ok) ('final journal invalid:'+ [string]$journal.reason)
Assert-FreshRecoveryEq $journal.entry.phase 'rollback-complete' 'final journal phase'
Assert-FreshRecoveryEq ([string]$journal.transaction_id).Trim().ToLowerInvariant() ([string]$s.transaction_id).Trim().ToLowerInvariant() 'final transaction id'
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id)
Assert-FreshRecoveryTrue ([bool]$evidence.ok) ('evidence unreadable after rollback-complete:'+ [string]$evidence.reason)

$app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$evidence.envelope.live_path)
Assert-FreshRecoveryEq $app.tree_sha256 ([string]$s.expected_app_tree_sha256) 'restored app tree'
if([int]$app.file_count -ne [int]$s.expected_app_file_count){Fail-FreshRecovery 'restored app file-count drift'}
if([int64]$app.total_bytes -ne [int64]$s.expected_app_total_bytes){Fail-FreshRecovery 'restored app byte-count drift'}
$persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root)
Assert-FreshRecoveryEq $persistence.fingerprint ([string]$s.expected_persistence_fingerprint) 'restored persistence fingerprint'
foreach($p in @([string]$s.transaction_root,[string]$s.stage_workspace_path,[string]$s.app_backup_path,[string]$s.persistence_backup_path)){Assert-FreshRecoveryTrue (Test-Path -LiteralPath $p) ('recovery artifact retired too early:'+ $p)}

$out=[pscustomobject]@{
    ok=$true;mode='recovered';transaction_id=([string]$s.transaction_id).Trim().ToLowerInvariant();started_phase=[string]$run.result.started_phase;final_phase=[string]$journal.entry.phase
    evidence_fingerprint=([string]$evidence.envelope.evidence_fingerprint).Trim().ToLowerInvariant();executor_result_fingerprint=([string]$run.result.result_fingerprint).Trim().ToLowerInvariant();app_tree_sha256=[string]$app.tree_sha256;persistence_fingerprint=[string]$persistence.fingerprint
    restore_performed=$true;recovery_apply_executed=$true;rollback_complete_persisted=$true;artifacts_retained=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false
}
[IO.File]::WriteAllText([string]$s.result_path,($out|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ('CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_CRASH_RESTORE_FRESH_PROCESS_PASS phase='+[string]$out.started_phase)
