param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [string]$OverrideTransactionId=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'PARTIAL_CLEANUP_RESTART_WINDOWS_ACTIONS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$state=Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$allowed=[IO.Path]::GetFullPath([string]$state.allowed_root).TrimEnd('\','/')
function Assert-CR([bool]$Condition,[string]$Reason){if(-not$Condition){throw ('TRIPLE_ID_PARTIAL_CLEANUP_RESTART_DENIED: '+$Reason)}}
function Within-CR([string]$Path){
    try{
        $p=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
        return ($p.StartsWith($runner+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and $p.Length -gt $runner.Length+9)
    }catch{return $false}
}
function Test-PathSafe {
    param([string]$Path,[ValidateSet('Leaf','Container')][string]$Kind)
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    try{$p=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')}catch{return $false}
    if(-not($p.Equals($allowed,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($allowed+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){return $false}
    if($Kind -ceq 'Leaf'){return (Test-Path -LiteralPath $Path -PathType Leaf)}
    return (Test-Path -LiteralPath $Path -PathType Container)
}
function Copy-TreeSafe {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    throw 'partial-cleanup-only-worker-forbids-copy-and-restore'
}
function Hash-CR([string]$Value){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
Assert-CR ([int]$state.schema -eq 1 -and [string]$state.scenario -ceq 'real-third-triple-id-partial-cleanup' -and [bool]$state.validation_only) 'state-schema-or-scenario-invalid'
Assert-CR (-not[bool]$state.production_execution_authorized -and -not[bool]$state.production_mutation_authorized) 'state-claims-authority'
foreach($field in @('allowed_root','store_directory','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','local_app_data_root','app_data_root','fake_apply_counter_path','fake_applied_index_path')){
    Assert-CR (Within-CR ([string]$state.$field)) ('unbounded-state-path-'+$field)
}
Assert-CR (Within-CR $StatePath) 'unbounded-child-state'
Assert-CR (Within-CR $ResultPath) 'unbounded-result-file'
Assert-CR (-not(Test-Path -LiteralPath $ResultPath)) 'result-overwrite-denied'
Assert-CR (-not[string]::IsNullOrWhiteSpace([string]$state.journal_entry_sha256) -and [string]$state.journal_entry_sha256 -cmatch '^[0-9a-f]{64}$') 'journal-anchor-invalid'
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
    'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
    'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1'
)
foreach($rel in $load){
    $p=Join-Path $root $rel
    Assert-CR (Test-Path -LiteralPath $p -PathType Leaf) ('qualified-dependency-missing-'+$rel)
    . $p
}
foreach($fn in @(
    'Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010',
    'Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010',
    'Remove-CustomAppProductionPostApplyBoundedArtifactV010',
    'Read-CustomAppProductionCrashJournalV010',
    'Append-CustomAppProductionCrashJournalPhaseV010',
    'Read-CustomAppProductionRecoveryEvidenceV010',
    'Get-CustomAppLocalRuntimeBaseline',
    'Get-CustomAppAtomicGitSnapshotV010',
    'Get-SpotifyPersistenceSnapshot'
)){
    Assert-CR ($null-ne(Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)) ('bootstrap-missing-'+$fn)
}
$out=[ordered]@{
    schema=1;managed_by='triple-id-partial-cleanup-independent-restart-fixture-v1';success=$false;reason='not-started'
    process_id=$PID;expected_transaction_id=[string]$state.transaction_id
    requested_transaction_id=$(if([string]::IsNullOrWhiteSpace($OverrideTransactionId)){[string]$state.transaction_id}else{$OverrideTransactionId})
    denied_wrong_id=$false;admission_ok=$false;admission_reason=''
    initial_phase='';initial_revision=-1;initial_entry_sha256='';cleanup_classification=''
    stage_previously_absent=$false;app_backup_present_before=$false;persistence_backup_present_before=$false
    bounded_app_cleanup_status='';bounded_persistence_cleanup_status=''
    after_cleanup_all_three_absent=$false;committed_clean_persisted=$false;final_phase='';final_revision=-1;final_entry_sha256=''
    finalization_fingerprint='';apply_result_fingerprint='';cleanup_result_fingerprint=''
    fake_apply_count_before=-1;fake_apply_count_after=-1;no_apply_reexecuted=$false
    live_git_preserved=$false;spotify_settings_preserved=$false;recovery_evidence_reverified=$false
    expired_admission_not_used=$true;session_key_not_needed=$true;no_restoration_or_apply=$true
    result_is_authority=$false;spicetify_apply_authorized=$false;production_mutation_authorized=$false
}
$expectedTx=([string]$state.transaction_id).Trim().ToLowerInvariant()
$requestTx=([string]$out.requested_transaction_id).Trim().ToLowerInvariant()
try{
    $pre=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory)
    Assert-CR ($null-ne$pre -and [bool]$pre.ok -and [bool]$pre.reloaded_from_persistent_store) 'journal-not-durably-readable'
    Assert-CR (([string]$pre.transaction_id).Trim().ToLowerInvariant() -ceq $expectedTx) 'journal-mismatch-with-state-anchored-transaction'
    Assert-CR ([string]$pre.entry.phase -ceq 'cleanup-starting') 'unexpected-precleanup-journal-phase'
    Assert-CR ([int64]$pre.revision -eq [int64]$state.journal_revision -and [string]$pre.entry.entry_sha256 -ceq [string]$state.journal_entry_sha256) 'journal-historical-entry-drift'
    Assert-CR ([string]$pre.entry.finalization_fingerprint -ceq [string]$state.finalization_fingerprint -and [string]$pre.entry.apply_result_fingerprint -ceq [string]$state.apply_fingerprint) 'prior-apply-or-finalization-fingerprint-drift'
    $out.initial_phase=[string]$pre.entry.phase
    $out.initial_revision=[int64]$pre.revision
    $out.initial_entry_sha256=[string]$pre.entry.entry_sha256
    $out.fake_apply_count_before=[int][IO.File]::ReadAllText([string]$state.fake_apply_counter_path).Trim()
    Assert-CR ($out.fake_apply_count_before -eq 1) 'fake-apply-count-before-not-exactly-one'
    $appliedHash=(Get-FileHash -LiteralPath ([string]$state.fake_applied_index_path) -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-CR ($appliedHash -ceq [string]$state.fake_applied_index_sha256) 'previously-applied-contents-changed'
    $cls=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $pre -ExpectedTransactionId $expectedTx
    Assert-CR ([bool]$cls.ok -and [bool]$cls.housekeeping_only -and [string]$cls.classification -ceq 'fresh-revalidate-then-idempotent-housekeeping-only') 'cleanup-classification-wrong-or-restoration-requested'
    $out.cleanup_classification=[string]$cls.classification

    $now=[DateTimeOffset]::UtcNow
    $adm=Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $requestTx -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -Now $now
    $out.admission_ok=[bool]$adm.ok
    $out.admission_reason=[string]$adm.reason
    if($requestTx -cne $expectedTx){
        Assert-CR (-not[bool]$adm.ok -and [int]([IO.File]::ReadAllText([string]$state.fake_apply_counter_path).Trim()) -eq 1) 'wrong-transaction-accepted-or-reapplied'
        $after=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory)
        Assert-CR ([int64]$after.revision -eq [int64]$pre.revision -and [string]$after.entry.entry_sha256 -ceq [string]$pre.entry.entry_sha256) 'wrong-transaction-mutated-journal'
        $out.denied_wrong_id=$true;$out.success=$true;$out.reason='wrong-identity-fail-closed-without-side-effects'
    }else{
        Assert-CR ([bool]$adm.ok) ('cross-process-cleanup-admission-denied:'+ [string]$adm.reason)
        $receipt=Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 -Receipt $adm.receipt -Now $now.AddSeconds(1)
        Assert-CR ([bool]$receipt.ok) ('restart-admission-receipt-invalid:'+[string]$receipt.reason)
        foreach($field in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
            Assert-CR (-not[bool]$adm.receipt.$field) ('restart-admission-grants-authority-'+$field)
        }
        $out.stage_previously_absent=([string]$adm.artifacts.stage.status -ceq 'already-absent')
        $out.app_backup_present_before=([string]$adm.artifacts.app_backup.status -ceq 'present-verified')
        $out.persistence_backup_present_before=([string]$adm.artifacts.persistence_backup.status -ceq 'present-verified')
        Assert-CR ($out.stage_previously_absent -and $out.app_backup_present_before -and $out.persistence_backup_present_before) 'partial-state-artifact-shapes-incorrect'
        Assert-CR (-not(Test-Path -LiteralPath ([string]$state.transaction_root))) 'atomic-transaction-root-reappeared'
        $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $expectedTx
        Assert-CR ([bool]$evidence.ok -and [string]$evidence.evidence_fingerprint -ceq [string]$state.evidence_fingerprint) 'immutable-recovery-evidence-drift'
        $out.recovery_evidence_reverified=$true
        $gitBefore=Get-CustomAppAtomicGitSnapshotV010 -LivePath ([string]$state.live_path)
        Assert-CR ([bool]$gitBefore.present -and [string]$gitBefore.tree_sha256 -ceq [string]$state.original_git_tree_sha256) 'original-git-not-preserved'
        $out.live_git_preserved=$true
        # The already-durable cleanup-starting barrier is reverified BEFORE
        # any new deletion, and the fresh admission is not treated as authority.
        $j2=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory)
        Assert-CR ([int64]$j2.revision -eq [int64]$pre.revision -and [string]$j2.entry.entry_sha256 -ceq [string]$pre.entry.entry_sha256) 'journal-raced-before-cleanup'
        $out.bounded_app_cleanup_status=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$adm.artifacts.app_backup.delete_path) -ExpectedRoot ([string]$adm.artifacts.app_backup.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'restart-app-backup'
        $out.bounded_persistence_cleanup_status=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$adm.artifacts.persistence_backup.delete_path) -ExpectedRoot ([string]$adm.artifacts.persistence_backup.root) -ExpectedNamePattern '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$' -Label 'restart-persistence-backup'
        $now2=[DateTimeOffset]::UtcNow
        $ad2=Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $expectedTx -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -Now $now2
        Assert-CR ([bool]$ad2.ok -and [string]$ad2.artifacts.stage.status -ceq 'already-absent' -and [string]$ad2.artifacts.app_backup.status -ceq 'already-absent' -and [string]$ad2.artifacts.persistence_backup.status -ceq 'already-absent') 'post-deletion-fresh-housekeeping-admission-denied'
        foreach($path in @($state.transaction_root,$state.stage_workspace_path,$state.app_backup_path,$state.persistence_backup_path)){
            Assert-CR (-not(Test-Path -LiteralPath ([string]$path))) 'post-cleanup-artifact-remains'
        }
        $runtime=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath ([string]$state.live_path)
        Assert-CR ([bool]$runtime.safe -and [bool]$runtime.installable -and -not(Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -and [string]$runtime.tree_sha256 -ceq [string]$state.expected_live_tree_sha256) 'post-cleanup-live-code-drift'
        $gitAfter=Get-CustomAppAtomicGitSnapshotV010 -LivePath ([string]$state.live_path)
        Assert-CR ([bool]$gitAfter.present -and [string]$gitAfter.tree_sha256 -ceq [string]$state.original_git_tree_sha256) 'post-cleanup-git-drift'
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root)
        Assert-CR ([string]$persist.fingerprint -ceq [string]$state.original_persistence_fingerprint) 'post-cleanup-spotify-persistence-drift'
        $out.spotify_settings_preserved=$true
        $out.after_cleanup_all_three_absent=$true
        $out.fake_apply_count_after=[int][IO.File]::ReadAllText([string]$state.fake_apply_counter_path).Trim()
        Assert-CR ($out.fake_apply_count_after -eq 1) 'cleanup-restarted-spicetify-apply'
        $appliedHash2=(Get-FileHash -LiteralPath ([string]$state.fake_applied_index_path) -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-CR ($appliedHash2 -ceq [string]$state.fake_applied_index_sha256) 'cleanup-mutated-applied-code'
        $beforeCommit=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory)
        Assert-CR ([string]$beforeCommit.entry.phase -ceq 'cleanup-starting' -and [int64]$beforeCommit.revision -eq [int64]$pre.revision -and [string]$beforeCommit.entry.entry_sha256 -ceq [string]$pre.entry.entry_sha256) 'commit-barrier-journal-drift'
        $fp=Hash-CR ((@('validation-only-cross-process-partial-cleanup',$expectedTx,[string]$state.finalization_fingerprint,[string]$state.apply_fingerprint,[string]$runtime.tree_sha256,[string]$gitAfter.tree_sha256,[string]$persist.fingerprint,'exact-three-bounded-transaction-artifacts-absent') -join [Environment]::NewLine))
        $now3=[DateTimeOffset]::UtcNow
        $last=[DateTimeOffset]::Parse([string]$beforeCommit.entry.recorded_at)
        if($now3 -le $last){$now3=$last.AddMilliseconds(2)}
        $commit=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory) -ExpectedRevision ([int64]$beforeCommit.revision) -ExpectedEntrySha256 ([string]$beforeCommit.entry.entry_sha256) -Phase 'committed-clean' -FinalizationFingerprint ([string]$state.finalization_fingerprint) -ApplyResultFingerprint ([string]$state.apply_fingerprint) -CleanupResultFingerprint $fp -Now $now3
        Assert-CR ([bool]$commit.ok -and [bool]$commit.persisted -and [bool]$commit.read_after_write_verified) ('committed-clean-journal-append-denied:'+[string]$commit.reason)
        $finished=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory ([string]$state.store_directory)
        Assert-CR ([bool]$finished.ok -and [bool]$finished.reloaded_from_persistent_store -and [string]$finished.entry.phase -ceq 'committed-clean' -and [int64]$finished.revision -eq [int64]$pre.revision+1 -and [string]$finished.entry.cleanup_result_fingerprint -ceq $fp) 'committed-clean-terminal-readback-invalid'
        $class2=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $finished -ExpectedTransactionId $expectedTx
        Assert-CR ([bool]$class2.ok -and [bool]$class2.no_action -and -not[bool]$class2.requires_recovery_executor) 'terminal-state-asks-to-restore-or-reapply'
        $out.committed_clean_persisted=$true;$out.final_phase=[string]$finished.entry.phase;$out.final_revision=[int64]$finished.revision;$out.final_entry_sha256=[string]$finished.entry.entry_sha256
        $out.finalization_fingerprint=[string]$finished.entry.finalization_fingerprint;$out.apply_result_fingerprint=[string]$finished.entry.apply_result_fingerprint;$out.cleanup_result_fingerprint=[string]$finished.entry.cleanup_result_fingerprint
        $out.success=$true;$out.reason='fresh-process-idempotent-housekeeping-only-committed-clean'
    }
}catch{
    $out.success=$false;$out.reason=[string]$_.Exception.Message
}
[IO.File]::WriteAllText($ResultPath,($out|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
if(-not[bool]$out.success){Write-Host ('TRIPLE_ID_PARTIAL_CLEANUP_RESTART_FAILED '+[string]$out.reason);exit 1}
if([bool]$out.denied_wrong_id){Write-Host 'TRIPLE_ID_PARTIAL_CLEANUP_WRONG_ID_DENIED_PASS no_mutation=true fake_apply_count=1';exit 0}
Write-Host 'TRIPLE_ID_PARTIAL_CLEANUP_FRESH_PROCESS_COMMITTED_PASS exact_journal=true admission_revalidated=true stage_already_absent=true remaining_backups_verified_and_retired=true live_git_persistence_unchanged=true fake_apply_count=1 no_rollback=true no_apply_reexecution=true committed_clean=true'
