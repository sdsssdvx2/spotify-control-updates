# Validation-only hosted Windows integration:
#   byte-real ZIP + freshly issued THIRD Triple-ID permit and pre-permit backups
#   -> generic cryptographic/durable-consumption admission recheck
#   -> existing recovery-evidence-bound atomic mutation (durable pre-mutation journal)
#   -> simulated process death -> independently bootstrapped fresh PowerShell
#   -> existing restore-resume admission -> exact app/config restore and fake old-code apply
#   -> persisted rollback-complete; stale replay denied.
# DO NOT connect this fixture to production or installed Spotify.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'TRIPLE_ID_JOURNALED_RESTART_E2E_WINDOWS_ACTIONS_ONLY'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')
. (Join-Path $root 'validation/custom-app-production-triple-id-prepared-atomic-e2e-v0.1.0/test_triple_id_prepared_atomic_e2e.ps1')

function Assert-TJR([bool]$Yes,[string]$Why){if(-not $Yes){throw ('TRIPLE_ID_JOURNALED_RESTART_E2E_FAIL: '+$Why)}}
function Assert-TJRNoAuthority($Object,[string]$Label){
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized','restore_authorized','apply_authorized','execution_authorized')){
        if($null -ne $Object -and $Object.PSObject.Properties[$f]){
            Assert-TJR (-not[bool]$Object.$f) ($Label+' unexpected authority '+$f)
        }
    }
}
$script:TJRRoot=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
Assert-Isolated $script:TIDLive 'live app'
Assert-Isolated ([string]$script:PPBValid.result.app_backup_path) 'immutable app rollback backup'
Assert-Isolated ([string]$script:PPBValid.result.persistence_backup_path) 'immutable settings backup'
Assert-Isolated ([string]$script:PPBValid.result.stage_workspace_path) 'pre-acquired ZIP stage'
Assert-Original 'fresh third Triple-ID after prior isolated rollback'
$script:TJRCases=0

# Revalidation is mandatory before invoking the recovery-aware atomic core.
# The generic atomic precondition checker verifies persisted single-use consumption,
# current permit HMAC, stage SHA, live baseline, .git and protected Spotify surfaces.
$pre=Test-CustomAppProductionAtomicPreconditionsV010 @TIDArgs
Assert-TJR ([bool]$pre.ok -and [bool]$pre.fresh_admission) ('third-permit admission failed: '+[string]$pre.reason)
Assert-TJR ([string]$pre.fresh_admission.consumption_id -ceq [string]$script:PPBStageResult.stage_result.consumption_id) 'admission did not retain third consumption'
Assert-TJR ([string]$pre.fresh_admission.admission_fingerprint -cmatch '^[0-9a-f]{64}$') 'fresh admission fingerprint absent'
Assert-TJRNoAuthority $pre.fresh_admission 'fresh-third-permit-admission'
$script:TJRCases++

$bad=@{};foreach($k in $TIDArgs.Keys){$bad[$k]=$TIDArgs[$k]}
$bad.SessionKey=[byte[]](33..64)
$deny=Test-CustomAppProductionAtomicPreconditionsV010 @bad
Assert-TJR (-not[bool]$deny.ok) 'wrong ephemeral session key passed post-consumption gate'
Assert-Original 'wrong-key-before-journal'
$script:TJRCases++

$script:TJRLabel='third-triple-id-restart'
$script:TJRStore=Join-Path $script:TJRRoot ('evidence-bound-'+$script:TJRLabel+'-'+[Guid]::NewGuid().ToString('N'))
$script:TJRTxnNonce=[Guid]::NewGuid().ToString('N')
Assert-Isolated $script:TJRStore 'journal'
$p=$script:PPBValid.result
$script:TJRMutation=@{
    GenericPreparedResult=$p
    Name='tagify'
    CallerAdmissionManagedBy=[string]$pre.fresh_admission.managed_by
    CallerAdmissionFingerprint=[string]$pre.fresh_admission.admission_fingerprint
    AllowedRoot=$script:TJRRoot
    JournalStoreDirectory=$script:TJRStore
    TransactionNonce=$script:TJRTxnNonce
    ConsumptionId=[string]$p.consumption_id
    SourceIdentity=[string]$p.source_identity
    RemoteCommitSha=[string]$p.remote_commit_sha
    StageResultFingerprint=[string]$p.stage_result_fingerprint
    PreparationFingerprint=[string]$p.preparation_fingerprint
    StageWorkspacePath=[string]$p.stage_workspace_path
    LivePath=[string]$script:TIDLive
    StagePath=[string]$p.stage_path
    ExpectedLiveRuntimeTreeSha256=[string]$pre.live_runtime.tree_sha256
    ExpectedLiveFullTreeSha256=[string]$pre.full_live.tree_sha256
    ExpectedLiveFullFileCount=[int]$pre.full_live.file_count
    ExpectedLiveFullTotalBytes=[int64]$pre.full_live.total_bytes
    ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256
    AppBackupPath=[string]$p.app_backup_path
    ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256
    ExpectedAppBackupFileCount=[int]$p.app_backup_file_count
    ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes
    PersistenceBackupPath=[string]$p.persistence_backup_path
    ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint
    LocalAppDataRoot=$script:PPBLocal
    AppDataRoot=$script:PPBRoaming
    Now=[DateTimeOffset]::UtcNow
}
# Unlike the non-journaled mutation, this core must durably record recoverable
# evidence and the start barrier BEFORE its first file-system rename.
$mutation=Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 @TJRMutation
Assert-TJR ([bool]$mutation.ok -and [bool]$mutation.live_code_swap_performed) ('third-permit journaled atomic failed: '+[string]$mutation.reason)
Assert-TJR ([bool]$mutation.recovery_evidence_bound_before_atomic_barrier) 'recovery evidence created after first rename'
Assert-TJRNoAuthority $mutation 'journal-atomic'
Assert-TJRNoAuthority $mutation.result 'journal-atomic-result'
$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore
Assert-TJR ([bool]$journal.ok -and [bool]$journal.reloaded_from_persistent_store -and [string]$journal.entry.phase -ceq 'candidate-live') 'durable journal did not reach candidate-live'
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore -ExpectedTransactionId ([string]$journal.transaction_id)
Assert-TJR ([bool]$evidence.ok -and [string]$evidence.evidence_fingerprint -ceq [string]$mutation.result.recovery_evidence_fingerprint) 'durable evidence not tied to atomic result'
Assert-TJR ([string]$journal.entry.consumption_id -ceq [string]$script:PPBStageResult.stage_result.consumption_id) 'journal consumption differs from third permit'
$liveAfter=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
Assert-TJR ([string]$liveAfter.tree_sha256 -ceq [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'new ZIP not installed in isolated live app'
$gitAfter=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $script:TIDLive '.git')
Assert-TJR ([string]$gitAfter.tree_sha256 -ceq [string]$script:BeforeGit.tree_sha256) '.git changed during journaled swap'
$persistAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-TJR ([string]$persistAfter.fingerprint -ceq [string]$script:BeforePersist.fingerprint) 'Spotify persistence mutated during journaled swap'
$script:TJRCases++

# Child process uses the preexisting independently qualified 22-contract
# restart worker, loading its own functions and reading only durable journal
# and evidence. The ephemeral HMAC key is NOT sent to it or stored in state.
$control=Join-Path $script:TJRRoot ('triple-id-crash-worker-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($control)|Out-Null
$fakeExe=Join-Path $control 'spicetify.exe'
$fakeSrc=@'
using System;
using System.IO;
public static class TripleIdCrashRecoveryFake {
    static string E(string n){return Environment.GetEnvironmentVariable(n) ?? "";}
    public static int Main(string[] a) {
        if(a==null || a.Length!=1 || a[0]!="apply")return 64;
        string counter=E("SC_RX_COUNT");
        string live=E("SC_RX_LIVE");
        string applied=E("SC_RX_APPLIED");
        if(String.IsNullOrEmpty(counter)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied))return 65;
        int k=0;if(File.Exists(counter))Int32.TryParse(File.ReadAllText(counter).Trim(),out k);
        File.WriteAllText(counter,(k+1).ToString());
        File.WriteAllBytes(applied,File.ReadAllBytes(live));
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSrc -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeHash=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
$worker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
Assert-TJR (Test-Path -LiteralPath $worker -PathType Leaf) 'qualified cross-process worker missing'
$statePath=Join-Path $control 'state.json'
$badStatePath=Join-Path $control 'bad-state.json'
$resultPath=Join-Path $control 'result.json'
$badResultPath=Join-Path $control 'bad-result.json'
$counter=Join-Path $control 'apply-count.txt'
$appliedProbe=Join-Path $control 'applied-old-index.txt'
$state=[ordered]@{
    schema=1;managed_by='triple-id-journaled-restart-validation-only'
    allowed_root=$script:TJRRoot;store_directory=$script:TJRStore
    transaction_id=[string]$journal.transaction_id
    evidence_fingerprint=[string]$evidence.evidence_fingerprint
    expected_start_phase='candidate-live'
    local_app_data_root=$script:PPBLocal;app_data_root=$script:PPBRoaming
    spicetify_allowed_root=$script:TJRRoot;spicetify_path=$fakeExe
    spicetify_sha256=$fakeHash;apply_count_path=$counter
    applied_probe_path=$appliedProbe;live_probe_path=(Join-Path $script:TIDLive 'index.js')
    parent_process_id=$PID
}
$stateJson=$state|ConvertTo-Json -Depth 20
Assert-TJR ($stateJson -notmatch '(?i)session_key|token_secret|hmac_key|DINPIKey') 'ephemeral signing key leaked into restart state'
[IO.File]::WriteAllText($statePath,$stateJson,[Text.UTF8Encoding]::new($false))
$badState=($stateJson|ConvertFrom-Json)
$badState.transaction_id=('0'*64)
[IO.File]::WriteAllText($badStatePath,($badState|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
$previousEAP=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $badOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $badStatePath -ResultPath $badResultPath 2>&1)
    $badExit=$LASTEXITCODE
}finally{$ErrorActionPreference=$previousEAP}
Assert-TJR ($badExit -ne 0) 'wrong durable transaction ID was accepted across restart'
Assert-TJR (Test-Path -LiteralPath $badResultPath -PathType Leaf) 'wrong-ID worker denial evidence absent'
$badWorker=Get-Content -LiteralPath $badResultPath -Raw|ConvertFrom-Json
Assert-TJR (-not[bool]$badWorker.admission_ok -and -not[bool]$badWorker.executor_ok) 'wrong-ID worker progressed past preflight'
Assert-TJR (-not(Test-Path -LiteralPath $counter)) 'fake Spicetify executed on incorrect journal identity'
$still=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore
Assert-TJR ([string]$still.entry.phase -ceq 'candidate-live') 'wrong-ID child mutated the journal'
$stillLive=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
Assert-TJR ([string]$stillLive.tree_sha256 -ceq [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'wrong-ID child modified live code'
$script:TJRCases++

$childOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath -ResultPath $resultPath 2>&1)
$childExit=$LASTEXITCODE
foreach($line in $childOutput){Write-Host $line}
Assert-TJR (Test-Path -LiteralPath $resultPath -PathType Leaf) 'cross-process restore result missing'
$restored=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
if($childExit -ne 0){throw ('third Triple-ID independent restart denied: '+[string]$restored.error)}
Assert-TJR ([bool]$restored.success -and [bool]$restored.executor_ok) ('existing restart executor failed: '+[string]$restored.error)
Assert-TJR ([int]$restored.process_id -ne [int]$PID) 'restart did not use separate PowerShell process'
Assert-TJR ([bool]$restored.bootstrap_dependencies_verified -and [int]$restored.bootstrap_dependency_count -eq 22) 'independent worker dependency bootstrap changed'
Assert-TJR ([string]$restored.executor_started_phase -ceq 'candidate-live' -and [string]$restored.final_phase -ceq 'rollback-complete') 'durable recovery phase ordering invalid'
Assert-TJR ([bool]$restored.rollback_required_was_appended -and [bool]$restored.restore_performed -and [bool]$restored.recovery_apply_executed -and [bool]$restored.rollback_complete_persisted) 'durable barrier/restore/rollback proof incomplete'
Assert-TJR ([int]$restored.apply_count -eq 1) 'fake old-code recovery apply did not run exactly once'
Assert-TJR ([IO.File]::ReadAllText($appliedProbe) -ceq [IO.File]::ReadAllText((Join-Path $script:TIDLive 'index.js'))) 'fake recovery did not observe restored old code'
Assert-TJR ([string]$restored.evidence_fingerprint_after -ceq [string]$evidence.evidence_fingerprint) 'recovery evidence drifted across restart'
Assert-Original 'cross-process journaled third-ID recovery'
foreach($recoveryArtifact in @($p.stage_workspace_path,$p.app_backup_path,$p.persistence_backup_path,$mutation.result.transaction_root)){
    Assert-TJR (Test-Path -LiteralPath ([string]$recoveryArtifact) -PathType Container) 'recovery rollback artifact prematurely deleted'
}
$script:TJRCases++

# Replaying a fully completed rollback is not another apply authorization.
$secondPath=Join-Path $control 'replay-result.json'
try{
    $ErrorActionPreference='Continue'
    $replayOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath -ResultPath $secondPath 2>&1)
    $replayExit=$LASTEXITCODE
}finally{$ErrorActionPreference=$previousEAP}
Assert-TJR ($replayExit -ne 0) 'finished rollback unexpectedly admitted replay'
Assert-TJR (Test-Path -LiteralPath $secondPath -PathType Leaf) 'replay denial output absent'
$replay=Get-Content -LiteralPath $secondPath -Raw|ConvertFrom-Json
Assert-TJR (-not[bool]$replay.executor_ok) 'duplicate recovery executor invoked'
Assert-TJR ([int]([IO.File]::ReadAllText($counter).Trim()) -eq 1) 'replay launched second fake Spicetify apply'
Assert-Original 'idempotent recovery replay denial'
$last=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore
Assert-TJR ([string]$last.entry.phase -ceq 'rollback-complete') 'replay mutated terminal recovery phase'
$script:TJRCases++

# The Third-ID consumption record remains durable; recovery does not reissue
# a permit or silently authorize further production mutation.
$read=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot ([string]$script:TIDArgs.AllowedRoot) -StoreDirectory ([string]$cf3.store)
Assert-TJR ([bool]$read.ok -and [bool]$read.reloaded_from_persistent_store) 'third-ID consumption ledger lost after fresh process'
$matches=@($read.state.consumptions|Where-Object{([string]$_.consumption_id).Trim().ToLowerInvariant() -ceq ([string]$p.consumption_id).Trim().ToLowerInvariant()})
Assert-TJR ($matches.Count -eq 1) 'third-ID consumption ledger lost or duplicated'
$script:TJRCases++

Assert-TJR ($script:TJRCases -eq 7) ('case count mismatch '+$script:TJRCases)
Write-Host 'TRIPLE_ID_JOURNALED_RESTART_E2E_PASS cases=7 real_zip=true third_permit_revalidated=true durable_single_use_consumption=true recovery_evidence_before_first_mutation=true journal_candidate_live=true separate_process=true resume_admission=true rollback_required_and_complete_durable=true exact_app_git_spotify_settings_restored=true fake_old_apply_count=1 wrong_identity_and_replay_denied=true no_session_key_persisted=true installed_spotify_untouched=true'
