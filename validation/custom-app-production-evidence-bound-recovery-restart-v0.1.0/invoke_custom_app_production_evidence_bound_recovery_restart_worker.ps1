param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json

# This validation worker intentionally starts in a brand-new powershell.exe process.
# The production persistence core normally receives Test-PathSafe/Copy-TreeSafe from
# the Addon Manager host. Recreate only those two host contracts here, bounded to the
# fixture AllowedRoot, so restart validation cannot inherit parent-process helpers or
# gain an unbounded filesystem surface.
$script:ERAllowedRoot=[IO.Path]::GetFullPath([string]$state.allowed_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
if(-not (Test-Path -LiteralPath $script:ERAllowedRoot -PathType Container)){throw 'recovery restart worker allowed root missing'}

function Test-ERWorkerPathWithinAllowedRootV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$true)
    try{$p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return $false}
    if($p.Equals($script:ERAllowedRoot,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($script:ERAllowedRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Test-PathSafe {
    param([string]$Path,[ValidateSet('Leaf','Container')][string]$Kind)
    if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-ERWorkerPathWithinAllowedRootV010 -Path $Path)){return $false}
    if($Kind -ceq 'Leaf'){return (Test-Path -LiteralPath $Path -PathType Leaf)}
    return (Test-Path -LiteralPath $Path -PathType Container)
}
function Copy-TreeSafe {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $dst=[IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-ERWorkerPathWithinAllowedRootV010 -Path $src) -or -not (Test-ERWorkerPathWithinAllowedRootV010 -Path $dst)){throw 'recovery-restart-copy-path-outside-allowed-root'}
    if(-not (Test-Path -LiteralPath $src -PathType Container)){throw 'recovery-restart-copy-source-missing'}
    if(Test-Path -LiteralPath $dst){throw 'recovery-restart-copy-destination-exists'}
    $si=Get-Item -LiteralPath $src -Force -ErrorAction Stop
    if(($si.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-restart-copy-source-reparse-point'}
    [IO.Directory]::CreateDirectory($dst)|Out-Null
    foreach($dir in @(Get-ChildItem -LiteralPath $src -Force -Directory -Recurse -ErrorAction Stop|Sort-Object FullName)){
        if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-restart-copy-source-contains-reparse-point'}
        $rel=$dir.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if(-not [string]::IsNullOrWhiteSpace($rel)){[IO.Directory]::CreateDirectory((Join-Path $dst $rel))|Out-Null}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $src -Force -File -Recurse -ErrorAction Stop|Sort-Object FullName)){
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-restart-copy-source-contains-reparse-point'}
        $rel=$file.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $target=Join-Path $dst $rel
        $parent=[IO.Path]::GetDirectoryName($target)
        if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
        [IO.File]::Copy($file.FullName,$target,$false)
    }
    return $dst
}

$load=@(
    'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
    'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
    'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
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

# Fail at bootstrap with a precise dependency name instead of allowing a nested
# admission/executor call to hide a parent-process dependency behind "term not recognized".
$requiredFunctions=@(
    'Test-PathSafe','Copy-TreeSafe','Test-CustomAppRemoteRelativePath','Get-CustomAppLocalRuntimeBaseline','Test-CustomAppLocalRuntimeBaselineMutationAuthority',
    'Get-CustomAppStageWorkspaceRootV010','Get-CustomAppUpdateTreeSnapshotV010','Test-CustomAppProductionPersistenceBackupV010','Get-PathContentFingerprint','Get-SpotifyPersistenceSnapshot','Restore-SpotifyPersistenceBackup',
    'Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010','Read-CustomAppProductionCrashJournalV010','Append-CustomAppProductionCrashJournalPhaseV010','Read-CustomAppProductionRecoveryEvidenceV010',
    'Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010','Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010','Restore-CustomAppProductionAtomicLiveSwapV010',
    'Open-CustomAppProductionSpicetifyExecutableV010','Invoke-CustomAppProductionExactSpicetifyApplyProcessV010','Invoke-CustomAppProductionRecoveryRestoreExecutorV010','Test-CustomAppProductionRecoveryRestoreExecutorResultV010'
)
foreach($fn in $requiredFunctions){if(-not (Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)){throw "recovery restart worker bootstrap function missing: $fn"}}

# Observe the exact last #157 barrier reached without mutating any fixture state or
# changing recovery decisions. This also proves whether a denial occurs before or
# after the durable rollback-required barrier / exact restore / recovery apply.
$script:ERLastRestoreCheckpoint='not-entered'
function Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    $script:ERLastRestoreCheckpoint=$Checkpoint
}

$out=[ordered]@{
    schema=1
    managed_by='custom-app-production-evidence-bound-recovery-restart-worker-v1'
    success=$false
    error=''
    process_id=$PID
    transaction_id=[string]$state.transaction_id
    expected_start_phase=[string]$state.expected_start_phase
    bootstrap_dependency_count=$requiredFunctions.Count
    bootstrap_dependencies_verified=$true
    admission_ok=$false
    admission_reason=''
    admission_phase=''
    admission_fingerprint=''
    executor_ok=$false
    executor_reason=''
    executor_last_checkpoint=$script:ERLastRestoreCheckpoint
    executor_output_count=0
    executor_output_types=@()
    executor_output_reasons=@()
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

    $execItems=@(Invoke-CustomAppProductionRecoveryRestoreExecutorV010 `
        -AllowedRoot ([string]$state.allowed_root) `
        -StoreDirectory ([string]$state.store_directory) `
        -ExpectedTransactionId ([string]$state.transaction_id) `
        -LocalAppDataRoot ([string]$state.local_app_data_root) `
        -AppDataRoot ([string]$state.app_data_root) `
        -SpicetifyAllowedRoot ([string]$state.spicetify_allowed_root) `
        -SpicetifyPath ([string]$state.spicetify_path) `
        -ExpectedSpicetifySha256 ([string]$state.spicetify_sha256) `
        -Now ([DateTimeOffset]::UtcNow) `
        -TimeoutSeconds 30)
    $out.executor_last_checkpoint=$script:ERLastRestoreCheckpoint
    $out.executor_output_count=$execItems.Count
    $out.executor_output_types=@($execItems|ForEach-Object{if($null -eq $_){'<null>'}else{$_.GetType().FullName}})
    $out.executor_output_reasons=@($execItems|ForEach-Object{if($null -ne $_ -and $_.PSObject.Properties['reason']){[string]$_.reason}else{'<no-reason-property>'}})
    if($execItems.Count -ne 1){
        throw "cross-process restore executor output cardinality invalid count=$($execItems.Count) checkpoint=$script:ERLastRestoreCheckpoint types=$($out.executor_output_types -join ',') reasons=$($out.executor_output_reasons -join ',')"
    }
    $exec=$execItems[0]
    $out.executor_ok=[bool]$exec.ok
    $out.executor_reason=[string]$exec.reason
    if(-not [bool]$exec.ok){throw "cross-process restore executor denied checkpoint=$script:ERLastRestoreCheckpoint reason=$([string]$exec.reason)"}
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
    $out.executor_last_checkpoint=$script:ERLastRestoreCheckpoint
    $out.error=[string]$_.Exception.Message
} finally {
    foreach($name in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $json=$out | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($ResultPath,$json,[Text.UTF8Encoding]::new($false))
}
if(-not [bool]$out.success){throw ('recovery restart worker failed: '+[string]$out.error)}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTART_WORKER_PASS phase=$($out.executor_started_phase) pid=$PID bootstrap=$($out.bootstrap_dependency_count) checkpoint=$($out.executor_last_checkpoint)"