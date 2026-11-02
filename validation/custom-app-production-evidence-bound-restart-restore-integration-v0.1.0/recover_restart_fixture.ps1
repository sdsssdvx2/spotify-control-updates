param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')

function Assert-EBRRTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-EBRREq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Assert-EBRRFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}

$state=Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
Assert-EBRREq ([int]$state.schema) 1 'handoff schema'
Assert-EBRREq ([string]$state.managed_by) 'custom-app-production-evidence-bound-restart-restore-fixture-v1' 'handoff owner'
Assert-EBRRTrue ([int]$state.producer_pid -ne [int]$PID) 'recovery executed in producer process instead of a fresh process'

$at=[DateTimeOffset]::UtcNow
$admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 `
    -AllowedRoot ([string]$state.allowed_root) `
    -StoreDirectory ([string]$state.store_directory) `
    -ExpectedTransactionId ([string]$state.transaction_id) `
    -LocalAppDataRoot ([string]$state.local_app_data_root) `
    -AppDataRoot ([string]$state.app_data_root) `
    -SpicetifyAllowedRoot ([string]$state.allowed_root) `
    -SpicetifyPath $fakeExe `
    -ExpectedSpicetifySha256 $fakeSha `
    -Now $at
Assert-EBRRTrue ([bool]$admission.ok) "fresh restart admission denied: $([string]$admission.reason)"
$admissionCheck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $admission.receipt -Now $at.AddMilliseconds(1)
Assert-EBRRTrue ([bool]$admissionCheck.ok) "fresh restart admission receipt invalid: $([string]$admissionCheck.reason)"
Assert-EBRREq ([string]$admission.receipt.transaction_id) ([string]$state.transaction_id) 'restart admission transaction continuity'
Assert-EBRREq ([string]$admission.receipt.evidence_fingerprint) ([string]$state.evidence_fingerprint) 'restart admission evidence continuity'
Assert-EBRREq ([string]$admission.receipt.phase) ([string]$state.journal_phase) 'restart admission phase continuity'
Assert-EBRRTrue ([bool]$admission.receipt.restore_resume_eligible) 'restart admission did not authorize eligibility evidence'
Assert-EBRRTrue ([bool]$admission.receipt.requires_exact_restore) 'restart admission lost exact restore requirement'
foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-EBRRFalse ([bool]$admission.receipt.$f) "restart admission authority escaped $f"}

$control=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ResultPath))) ('control-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($control)|Out-Null
$countPath=Join-Path $control 'count.txt'
$appliedPath=Join-Path $control 'applied.txt'
$env:SC_RX_COUNT=$countPath
$env:SC_RX_LIVE=Join-Path ([string]$state.live_path) 'index.js'
$env:SC_RX_APPLIED=$appliedPath
$env:SC_RX_MODE='success'
try {
    $execution=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 `
        -AllowedRoot ([string]$state.allowed_root) `
        -StoreDirectory ([string]$state.store_directory) `
        -ExpectedTransactionId ([string]$state.transaction_id) `
        -LocalAppDataRoot ([string]$state.local_app_data_root) `
        -AppDataRoot ([string]$state.app_data_root) `
        -SpicetifyAllowedRoot ([string]$state.allowed_root) `
        -SpicetifyPath $fakeExe `
        -ExpectedSpicetifySha256 $fakeSha `
        -Now $at.AddMilliseconds(10) `
        -TimeoutSeconds 15
} finally {
    foreach($n in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
}

Assert-EBRRTrue ([bool]$execution.ok) "restart restore executor denied: $([string]$execution.reason)"
$resultCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $execution.result
Assert-EBRRTrue ([bool]$resultCheck.ok) "restart restore executor result invalid: $([string]$resultCheck.reason)"
Assert-EBRREq ([string]$execution.result.transaction_id) ([string]$state.transaction_id) 'executor transaction continuity'
Assert-EBRREq ([string]$execution.result.evidence_fingerprint) ([string]$state.evidence_fingerprint) 'executor evidence continuity'
Assert-EBRREq ([string]$execution.result.started_phase) ([string]$state.journal_phase) 'executor start phase'
Assert-EBRRTrue ([bool]$execution.result.restore_performed) 'executor did not restore old app state'
Assert-EBRRTrue ([bool]$execution.result.recovery_apply_executed) 'executor did not run recovery apply'
Assert-EBRRTrue ([bool]$execution.result.rollback_complete_persisted) 'executor did not persist rollback-complete'
Assert-EBRRTrue ([bool]$execution.result.requires_recovery_artifact_retirement) 'executor lost artifact-retirement requirement'
foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-EBRRFalse ([bool]$execution.result.$f) "executor authority escaped $f"}

Assert-EBRRTrue (Test-Path -LiteralPath $countPath -PathType Leaf) 'fake spicetify count file missing'
$applyCount=[int]([IO.File]::ReadAllText($countPath).Trim())
Assert-EBRREq $applyCount 1 'recovery apply count'
Assert-EBRRTrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'fake spicetify applied snapshot missing'
$expectedApplied=[IO.File]::ReadAllText((Join-Path ([string]$state.app_backup_path) 'index.js'))
$actualApplied=[IO.File]::ReadAllText($appliedPath)
Assert-EBRRTrue ($actualApplied -ceq $expectedApplied) 'recovery apply did not observe restored old live state'

$live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$state.live_path)
Assert-EBRREq ([string]$live.tree_sha256) ([string]$state.app_backup_tree_sha256) 'restored live tree'
Assert-EBRREq ([int]$live.file_count) ([int]$state.app_backup_file_count) 'restored live file count'
Assert-EBRREq ([int64]$live.total_bytes) ([int64]$state.app_backup_total_bytes) 'restored live total bytes'
$persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root)
Assert-EBRREq ([string]$persistence.fingerprint) ([string]$state.persistence_fingerprint) 'restored protected persistence fingerprint'

$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
Assert-EBRRTrue ([bool]$journal.ok) "final journal unreadable: $([string]$journal.reason)"
Assert-EBRREq ([string]$journal.transaction_id) ([string]$state.transaction_id) 'final journal transaction id'
Assert-EBRREq ([string]$journal.entry.phase) 'rollback-complete' 'final journal phase'
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id)
Assert-EBRRTrue ([bool]$evidence.ok) "evidence unreadable after rollback-complete: $([string]$evidence.reason)"
Assert-EBRREq ([string]$evidence.evidence_fingerprint) ([string]$state.evidence_fingerprint) 'post-recovery evidence fingerprint'

foreach($artifact in @([string]$state.transaction_root,[string]$state.stage_workspace_path,[string]$state.app_backup_path,[string]$state.persistence_backup_path)){
    Assert-EBRRTrue (Test-Path -LiteralPath $artifact -PathType Container) "required recovery artifact was retired too early: $artifact"
}

$out=[ordered]@{
    schema=1
    managed_by='custom-app-production-evidence-bound-restart-restore-result-v1'
    label=[string]$state.label
    producer_pid=[int]$state.producer_pid
    recovery_pid=[int]$PID
    initial_phase=[string]$state.journal_phase
    final_phase=[string]$journal.entry.phase
    transaction_id=[string]$state.transaction_id
    evidence_fingerprint=[string]$state.evidence_fingerprint
    restore_resume_admission_fingerprint=[string]$admission.receipt.restore_resume_admission_fingerprint
    executor_result_fingerprint=[string]$execution.result.result_fingerprint
    apply_count=$applyCount
    live_tree_sha256=[string]$live.tree_sha256
    persistence_fingerprint=[string]$persistence.fingerprint
    recovery_artifacts_retained=$true
    authority_granted=$false
}
$resultFull=[IO.Path]::GetFullPath($ResultPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resultFull))|Out-Null
[IO.File]::WriteAllText($resultFull,($out|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RESTART_RESTORE_PASS label=$([string]$state.label) producer_pid=$([int]$state.producer_pid) recovery_pid=$PID apply_count=$applyCount"
