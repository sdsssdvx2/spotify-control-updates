# Hosted-Windows-only end-to-end validation. NO actual Spotify or user machine.
# Uses the real third Triple-ID HMAC permit and byte-real ZIP from the inherited
# preparation fixture; this has NO legacy-result impersonation or runtime authority.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'JOURNALED_FORWARD_GITHUB_HOSTED_WINDOWS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-triple-id-prepared-atomic-e2e-v0.1.0/test_triple_id_prepared_atomic_e2e.ps1')
foreach($rel in @(
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
    'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1',
    'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1',
    'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/custom-app-production-evidence-bound-journal-atomic.ps1',
    'validation/custom-app-production-transaction-finalization-v0.1.0/custom-app-production-transaction-finalization.ps1',
    'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1',
    'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1',
    'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1',
    'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1',
    'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup-finalization-receipt-v011.ps1'
)){. (Join-Path $root $rel)}
function Assert-JF([bool]$Ok,[string]$Why){if(-not$Ok){throw ('TRIPLE_ID_JOURNALED_FORWARD_FAIL: '+$Why)}}
function Hash-JF([string]$String){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($String))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Read-JF([string]$Phase){
    $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $script:JFAllowed -StoreDirectory $script:JFStore
    Assert-JF ([bool]$j.ok -and [bool]$j.reloaded_from_persistent_store) 'journal persistence reload failed'
    Assert-JF ([string]$j.transaction_id -ceq $script:JFTx) 'journal transaction ID drift'
    Assert-JF ([string]$j.entry.phase -ceq $Phase) ('journal wrong phase '+$Phase)
    return $j
}
function Append-JF([string]$From,[string]$To,[string]$Final,[string]$Apply=$null,[string]$Cleanup=$null){
    $old=Read-JF $From
    $at=[DateTimeOffset]::UtcNow
    $last=[DateTimeOffset]::Parse([string]$old.entry.recorded_at)
    if($at -le $last){$at=$last.AddMilliseconds(2)}
    $next=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $script:JFAllowed -StoreDirectory $script:JFStore -ExpectedRevision ([int64]$old.revision) -ExpectedEntrySha256 ([string]$old.entry.entry_sha256) -Phase $To -FinalizationFingerprint $Final -ApplyResultFingerprint $Apply -CleanupResultFingerprint $Cleanup -Now $at
    Assert-JF ([bool]$next.ok -and [bool]$next.persisted -and [bool]$next.read_after_write_verified) ('journal phase append denied '+$To+' '+[string]$next.reason)
    $new=Read-JF $To
    Assert-JF ([int64]$new.revision -eq ([int64]$old.revision+1) -and [string]$new.entry.entry_sha256 -ceq [string]$next.entry.entry_sha256) ('journal phase readback failed '+$To)
    return $new
}
function Snapshot-JF([bool]$OldRequired){
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
    Assert-JF ([bool]$runtime.safe -and [bool]$runtime.installable -and -not(Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -and [string]$runtime.tree_sha256 -ceq [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'live runtime drift'
    $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $script:TIDLive
    Assert-JF ([bool]$git.present -and [string]$git.tree_sha256 -ceq [string]$script:BeforeGit.tree_sha256) 'git provenance drift'
    $ps=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
    Assert-JF ([string]$ps.fingerprint -ceq [string]$script:BeforePersist.fingerprint) 'Spotify persistence drift'
    if($OldRequired){
        $old=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$script:JFAtomic.result.old_live_path)
        Assert-JF ([string]$old.tree_sha256 -ceq [string]$script:Before.tree_sha256 -and [int]$old.file_count -eq [int]$script:Before.file_count) 'old-live rollback bytes drift'
    }
    return [pscustomobject]@{runtime=$runtime;git=$git;persistence=$ps}
}
$script:JFCases=0
Assert-Original 'journaled forward entry exact original'
$script:JFAllowed=[string]$script:BRHAllowedRoot
$script:JFStore=Join-Path $env:RUNNER_TEMP ('triple-id-forward-journal-'+[Guid]::NewGuid().ToString('N'))
Assert-Isolated $script:JFStore 'journal store'
$p=$script:PPBValid.result
$pre=Test-CustomAppProductionAtomicPreconditionsV010 @TIDArgs
Assert-JF ([bool]$pre.ok) ('signed third Triple-ID preflight failed '+[string]$pre.reason)
$script:JFCases++
$bad=@{};foreach($k in $TIDArgs.Keys){$bad[$k]=$TIDArgs[$k]}
$bad.SessionKey=[byte[]](33..64)
$badPre=Test-CustomAppProductionAtomicPreconditionsV010 @bad
Assert-JF (-not[bool]$badPre.ok) 'wrong session key admitted'
Assert-Original 'wrong-key preflight'
$script:JFCases++
$nonce=[Guid]::NewGuid().ToString('N')
$atomic=Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 -GenericPreparedResult $p -Name 'tagify' -CallerAdmissionManagedBy ([string]$pre.fresh_admission.managed_by) -CallerAdmissionFingerprint ([string]$pre.fresh_admission.admission_fingerprint) -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -TransactionNonce $nonce -ConsumptionId ([string]$p.consumption_id) -SourceIdentity ([string]$p.source_identity) -RemoteCommitSha ([string]$p.remote_commit_sha) -StageResultFingerprint ([string]$p.stage_result_fingerprint) -PreparationFingerprint ([string]$p.preparation_fingerprint) -StageWorkspacePath ([string]$p.stage_workspace_path) -LivePath $script:TIDLive -StagePath ([string]$p.stage_path) -ExpectedLiveRuntimeTreeSha256 ([string]$script:BeforeRuntime.tree_sha256) -ExpectedLiveFullTreeSha256 ([string]$script:Before.tree_sha256) -ExpectedLiveFullFileCount ([int]$script:Before.file_count) -ExpectedLiveFullTotalBytes ([int64]$script:Before.total_bytes) -ExpectedStageRuntimeTreeSha256 ([string]$p.stage_tree_sha256) -AppBackupPath ([string]$p.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$p.app_backup_tree_sha256) -ExpectedAppBackupFileCount ([int]$p.app_backup_file_count) -ExpectedAppBackupTotalBytes ([int64]$p.app_backup_total_bytes) -PersistenceBackupPath ([string]$p.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$p.persistence_fingerprint) -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming -Now ([DateTimeOffset]::UtcNow.AddSeconds(-20))
Assert-JF ([bool]$atomic.ok -and [bool]$atomic.recovery_evidence_bound_before_atomic_barrier) ('evidence-bound journal atomic denied '+[string]$atomic.reason)
$script:JFAtomic=$atomic
$script:JFTx=([string]$atomic.result.transaction_id).Trim().ToLowerInvariant()
Assert-JF ([bool](Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 $atomic.result).ok) 'signed journaled mutation receipt invalid'
$jr=Read-JF 'candidate-live'
Assert-JF ([int64]$jr.revision -eq 3 -and [string]$jr.entry.entry_sha256 -ceq [string]$atomic.result.journal_entry_sha256) 'real journal atomic head invalid'
$ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $script:JFAllowed -StoreDirectory $script:JFStore -ExpectedTransactionId $script:JFTx
Assert-JF ([bool]$ev.ok -and [string]$ev.evidence_fingerprint -ceq [string]$atomic.result.recovery_evidence_fingerprint) 'immutable backup recovery evidence absent'
$script:JFCases++
# Legacy finalization legitimately rejects a DIFFERENT atomic receipt contract.
# No forged old-schema receipt, dual-ID bridge, or fake execution authorization.
$oldFinal=Invoke-CustomAppProductionTransactionFinalizationV010 -AtomicResult $atomic.result -PreparedResult $p -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify' -LifecycleRow $q.bundle.lifecycle -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-JF (-not[bool]$oldFinal.ok) 'generic finalizer accidentally accepted evidence-bound different schema'
Assert-JF (Test-Path -LiteralPath ([string]$atomic.result.transaction_root) -PathType Container) 'legacy denial deleted recovery root'
$script:JFCases++
$now=$script:PPBAt.AddMilliseconds(650)
$auth=Test-CustomAppProductionPostSwapPermitIntegrityV010 -Permit $script:PPBIssuer.permit -SessionKey $script:DINPIKey -Now $now
Assert-JF ([bool]$auth.ok) ('fresh signed permit denied '+[string]$auth.reason)
$identity=Test-CustomAppProductionPostSwapPermitStageContinuityV010 -Permit $script:PPBIssuer.permit -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify'
Assert-JF ([bool]$identity.ok) 'signed permit stage mismatch'
$consumption=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $script:JFAllowed -StoreDirectory ([string]$cf3.store) -ExpectedConsumptionId ([string]$p.consumption_id) -Permit $script:PPBIssuer.permit -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify'
Assert-JF ([bool]$consumption.ok -and [bool]$consumption.store.reloaded_from_persistent_store) 'third consumption lost'
Assert-JF ([bool](Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $q.bundle.lifecycle -ProvenanceRow $q.bundle.provenance).ok) 'remote provenance denied'
$binding=Test-CustomAppStageBindingRowV010 -BindingRow $q.bundle.binding -ExpectedName 'tagify'
Assert-JF ([bool]$binding.ok) 'remote binding schema invalid'
$stageResult=$script:PPBStageResult.stage_result
Assert-JF ([string]$binding.source -ceq [string]$stageResult.source_identity -and [string]$binding.surface -ceq [string]$stageResult.surface_kind) 'remote binding source/surface drift'
Assert-JF ([int64]$binding.repo_id -eq [int64]$stageResult.github_repo_id) 'remote repo identity drift'
Assert-JF ([string]$binding.remote_tree_sha256 -ceq [string]$stageResult.remote_tree_sha256 -and [string]$binding.commit_sha -ceq [string]$stageResult.remote_commit_sha -and [string]$binding.binding_fingerprint -ceq [string]$stageResult.binding_fingerprint) 'remote signed binding values drift'
$lastSuccess=[DateTimeOffset]::MinValue
Assert-JF ([DateTimeOffset]::TryParse([string]$binding.last_success,[ref]$lastSuccess)) 'remote binding freshness timestamp invalid'
Assert-JF ($now -ge $lastSuccess.AddMinutes(-5) -and $now -le $lastSuccess.AddHours(36)) 'remote binding observation stale/future'
$before=Snapshot-JF $true
$stageArtifact=Test-CustomAppProductionPostApplyStageCleanupArtifactV010 -PreparedResult $p -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify'
$appArtifact=Test-CustomAppProductionPostApplyAppBackupCleanupArtifactV010 -PreparedResult $p
$persistArtifact=Test-CustomAppProductionPostApplyPersistenceCleanupArtifactV010 -PreparedResult $p
foreach($x in @($stageArtifact,$appArtifact,$persistArtifact)){Assert-JF ([bool]$x.ok -and [string]$x.status -ceq 'present-verified') ('backup artifact not exact '+[string]$x.reason)}
$script:JFCases++
$control=Join-Path $env:RUNNER_TEMP ('triple-id-journal-forward-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($control)|Out-Null
$exe=Join-Path $control 'spicetify.exe'
$countPath=Join-Path $control 'count.txt'
$appliedPath=Join-Path $control 'applied-index.txt'
$source=@'
using System;
using System.IO;
public static class IsolatedForwardFake {
 static string E(string x) {return Environment.GetEnvironmentVariable(x) ?? ""; }
 public static int Main(string[] a){
  if(a==null || a.Length!=1 || a[0]!="apply")return 64;
  string live=E("JF_LIVE");string count=E("JF_COUNT");string dest=E("JF_APPLIED");
  if(String.IsNullOrEmpty(live)||String.IsNullOrEmpty(count)||String.IsNullOrEmpty(dest))return 65;
  int n=0;if(File.Exists(count))Int32.TryParse(File.ReadAllText(count),out n);
  File.WriteAllText(count,(n+1).ToString());
  File.WriteAllBytes(dest,File.ReadAllBytes(live));return 0;
 }
}
'@
Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $exe -OutputType ConsoleApplication
$sha=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Isolated $exe 'fake executable'
Assert-JF ($sha -match '^[0-9a-f]{64}$' -and -not(Test-Path -LiteralPath $countPath)) 'fake exe not ready'
$wrongHash=$null
try{$wrongHash=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $exe -ExpectedSha256 ('0'*64)}catch{}
if($null-ne$wrongHash -and $null-ne$wrongHash.stream){$wrongHash.stream.Dispose()}
Assert-JF ($null-eq$wrongHash -and -not(Test-Path -LiteralPath $countPath)) 'wrong executable hash accepted'
$pin=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $exe -ExpectedSha256 $sha
Assert-JF ([string]$pin.sha256 -ceq $sha) 'fake exe pin did not match'
# Preserve the SHA-verified read-only file handle until the process has exited:
# closing it before launch would permit a TOCTOU replacement of the executable.
$script:JFCases++
$finalFp=Hash-JF ((@('journaled-forward-fixture','actual-third-id',$script:JFTx,[string]$atomic.result.result_fingerprint,[string]$p.preparation_fingerprint,[string]$before.runtime.tree_sha256,[string]$before.git.tree_sha256,[string]$before.persistence.fingerprint,'old-live-retained-for-rollback') -join [Environment]::NewLine))
$jr=Append-JF 'candidate-live' 'transaction-finalized' $finalFp
Assert-JF ([string]$jr.entry.finalization_fingerprint -ceq $finalFp) 'finalization evidence mismatch'
$script:JFCases++
$jr=Append-JF 'transaction-finalized' 'apply-starting' $finalFp
Assert-JF (-not(Test-Path -LiteralPath $countPath)) 'fake apply ran before durable barrier'
$script:JFCases++
try {
    $env:JF_LIVE=(Join-Path $script:TIDLive 'index.js')
    $env:JF_COUNT=$countPath
    $env:JF_APPLIED=$appliedPath
    $run=Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 -ExecutablePath $exe -TimeoutSeconds 20
}finally{
    if($null-ne$pin.stream){$pin.stream.Dispose()}
    foreach($n in @('JF_LIVE','JF_COUNT','JF_APPLIED')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
}
Assert-JF ([bool]$run.ok -and [int]$run.exit_code -eq 0 -and -not[bool]$run.timed_out) ('qualified fake exact process denied '+[string]$run.reason)
$jr=Append-JF 'apply-starting' 'apply-returned-success-pending-verification' $finalFp
$after=Snapshot-JF $true
Assert-JF ([IO.File]::ReadAllText($appliedPath) -ceq [IO.File]::ReadAllText((Join-Path $script:TIDLive 'index.js'))) 'fake apply read wrong new live bytes'
Assert-JF ([bool](Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $script:JFAllowed -StoreDirectory ([string]$cf3.store) -ExpectedConsumptionId ([string]$p.consumption_id) -Permit $script:PPBIssuer.permit -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify').ok) 'post-apply durable consumption drift'
Assert-JF ([bool](Test-CustomAppProductionPostSwapPermitIntegrityV010 -Permit $script:PPBIssuer.permit -SessionKey $script:DINPIKey -Now $now).ok) 'post-apply HMAC permit drift'
$applyFp=Hash-JF ((@('journaled-forward-fixture','fake-process-applied-once',$script:JFTx,$finalFp,$sha,[string]$after.runtime.tree_sha256,[string]$after.git.tree_sha256,[string]$after.persistence.fingerprint) -join [Environment]::NewLine))
$jr=Append-JF 'apply-returned-success-pending-verification' 'apply-verified' $finalFp $applyFp
Assert-JF ([string]$jr.entry.apply_result_fingerprint -ceq $applyFp -and [int]([IO.File]::ReadAllText($countPath).Trim()) -eq 1) 'apply-verified receipt incorrect'
$script:JFCases++
$jr=Append-JF 'apply-verified' 'cleanup-starting' $finalFp $applyFp
Assert-JF (Test-Path -LiteralPath $script:JFAtomic.result.transaction_root -PathType Container) 'cleanup root gone before barrier'
$script:JFCases++
# Bounded deletion only AFTER the durable cleanup-starting phase.
$txn=[string]$script:JFAtomic.result.transaction_root
Remove-CustomAppAtomicDirectoryV010 -Path $txn -ExpectedParent ([IO.Path]::GetDirectoryName($txn)) -ExpectedName ([IO.Path]::GetFileName($txn))
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$stageArtifact.path) -ExpectedRoot ([string]$stageArtifact.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'isolated-stage')
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$appArtifact.path) -ExpectedRoot ([string]$appArtifact.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'isolated-app-backup')
[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$persistArtifact.path) -ExpectedRoot ([string]$persistArtifact.root) -ExpectedNamePattern '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$' -Label 'isolated-persistence-backup')
foreach($target in @($txn,$stageArtifact.path,$appArtifact.path,$persistArtifact.path)){Assert-JF (-not(Test-Path -LiteralPath ([string]$target))) 'bounded cleanup artifact remained'}
$committed=Snapshot-JF $false
Assert-JF ([int]([IO.File]::ReadAllText($countPath).Trim()) -eq 1) 'cleanup re-executed fake apply'
$cleanupFp=Hash-JF ((@('journaled-forward-fixture','all-four-artifacts-clean',$script:JFTx,$finalFp,$applyFp,[string]$committed.runtime.tree_sha256,[string]$committed.git.tree_sha256,[string]$committed.persistence.fingerprint) -join [Environment]::NewLine))
$jr=Append-JF 'cleanup-starting' 'committed-clean' $finalFp $applyFp $cleanupFp
Assert-JF ([string]$jr.entry.cleanup_result_fingerprint -ceq $cleanupFp -and [int64]$jr.revision -eq 9 -and [int]$jr.history_count -eq 10) 'committed journal history proof failed'
$script:JFCases++
$class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead (Read-JF 'committed-clean') -ExpectedTransactionId $script:JFTx
Assert-JF ([bool]$class.ok -and [bool]$class.no_action -and [string]$class.classification -ceq 'no-action-new-permit-required-for-future-update') 'committed recovery wrongly requests rollback'
$script:JFCases++
$replayDenied=$false
try{[void](Append-JF 'candidate-live' 'transaction-finalized' $finalFp)}catch{$replayDenied=$true}
Assert-JF ($replayDenied -and [int]([IO.File]::ReadAllText($countPath).Trim()) -eq 1) 'committed transaction replayed or relaunched fake'
Assert-JF ([string](Read-JF 'committed-clean').entry.entry_sha256 -ceq [string]$jr.entry.entry_sha256) 'terminal journal mutated on replay'
$script:JFCases++
Assert-JF ($script:JFCases -eq 13) ('new case count '+$script:JFCases)
Write-Host 'TRIPLE_ID_REAL_ZIP_JOURNALED_FORWARD_COMMIT_PASS cases=13 third_permit=true durable_consumption=true evidence_before_atomic=true same_journal_history=10 normal_finalization_without_receipt_forgery=true fake_apply_once=true rollback_source_retained_until_cleanup=true cleanup_barrier_before_four_deletions=true committed_clean=true git_and_spotify_persistence_unchanged=true terminal_replay_denied=true user_spotify_untouched=true'
