# Runs only on an ephemeral hosted GitHub Windows runner.
# Source prior independently qualified fixture, then use its ORIGINAL third
# Triple-ID permit, actual ZIP, stage, persisted consumption and pre-permit backups
# for real atomic swap -> transaction finalization -> FAKE Spicetify apply -> cleanup.
# No production code, real Spicetify binary, installed Spotify path, or network calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'TRIPLE_ID_APPLY_E2E_REQUIRES_HOSTED_WINDOWS'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-triple-id-prepared-atomic-e2e-v0.1.0/test_triple_id_prepared_atomic_e2e.ps1')
. (Join-Path $root 'validation/custom-app-production-transaction-finalization-v0.1.0/custom-app-production-transaction-finalization.ps1')
. (Join-Path $root 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1')
. (Join-Path $root 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1')
function Assert-E2E([bool]$Yes,[string]$Why){if(-not$Yes){throw ('TRIPLE_ID_APPLY_CLEANUP_E2E_FAIL: '+$Why)}}
function Check-E2ENoAuthority($Obj,[string]$Label){
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){
        if($null-ne$Obj -and $Obj.PSObject.Properties[$f]){
            Assert-E2E (-not [bool]$Obj.$f) ($Label+' grants '+$f)
        }
    }
}

$script:E2EControl=Join-Path $env:RUNNER_TEMP ('triple-id-apply-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:E2EControl)|Out-Null
Assert-Isolated $script:E2EControl 'fake-executable-root'
$script:E2EFakeExe=Join-Path $script:E2EControl 'spicetify.exe'
$script:E2ECounter=Join-Path $script:E2EControl 'count.txt'
$script:E2EApplied=Join-Path $script:E2EControl 'applied-state.txt'

# Original small fake executable contract: ONLY accepts one argument "apply".
# It stores exactly the current disposable live app's bytes; never accesses Spotify.
$fakeSource=@'
using System;
using System.IO;
public static class IsolatedFakeSpicetify {
    static string Env(string name){return Environment.GetEnvironmentVariable(name) ?? "";}
    public static int Main(string[] args) {
        if(args == null || args.Length != 1 || args[0] != "apply") return 64;
        string live=Env("SC_TRIPLE_LIVE");
        string counter=Env("SC_TRIPLE_COUNT");
        string applied=Env("SC_TRIPLE_APPLIED");
        if(String.IsNullOrEmpty(live) || String.IsNullOrEmpty(counter) || String.IsNullOrEmpty(applied)) return 65;
        int count=0;
        if(File.Exists(counter)) Int32.TryParse(File.ReadAllText(counter).Trim(),out count);
        File.WriteAllText(counter,(count+1).ToString());
        File.WriteAllBytes(applied,File.ReadAllBytes(live));
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $script:E2EFakeExe -OutputType ConsoleApplication
$script:E2EFakeSha=(Get-FileHash -LiteralPath $script:E2EFakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-E2E ($script:E2EFakeSha -cmatch '^[0-9a-f]{64}$') 'fake exe digest missing'
Assert-E2E (-not (Test-Path -LiteralPath $script:E2ECounter)) 'fake executable unexpectedly invoked'
$script:E2ECases=0

# Prior integration returned ORIGINAL live state and exact backup after its
# successful-swap/abort exercise. No new permit or duplicate download here.
Assert-Original 'qualified parent before new full-chain'
$script:E2ECases++

$atomic=Invoke-CustomAppProductionAtomicLiveSwapV010 @TIDArgs
Assert-E2E ([bool]$atomic.ok -and [bool]$atomic.live_code_swap_performed) ('same third Triple-ID permit real swap failed: '+[string]$atomic.reason)
Check-E2ENoAuthority $atomic 'atomic'
$script:E2ECases++

$final=Invoke-CustomAppProductionTransactionFinalizationV010 -AtomicResult $atomic -PreparedResult $script:PPBValid.result -StageExecutorResult $script:PPBStageResult.stage_result -Name 'tagify' -LifecycleRow $q.bundle.lifecycle -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming -Now $script:PPBAt.AddMilliseconds(450)
Assert-E2E ([bool]$final.ok) ('generic transaction finalizer rejected new Triple-ID: '+[string]$final.reason)
$finalCheck=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $final
Assert-E2E ([bool]$finalCheck.ok -and [bool]$final.transaction_workspace_deleted) ('finalization result invalid: '+[string]$finalCheck.reason)
foreach($f in @('stage_workspace_path','app_backup_path','persistence_backup_path')){
    Assert-E2E (Test-Path -LiteralPath ([string]$final.$f) -PathType Container) ('rollback artifact lost before apply: '+$f)
}
Check-E2ENoAuthority $final 'finalization'
$script:E2ECases++

$script:E2ECommon=@{
    AllowedRoot=[string]$script:BRHAllowedRoot
    StoreDirectory=[string]$cf3.store
    ExpectedConsumptionId=[string]$script:PPBStageResult.stage_result.consumption_id
    Permit=$script:PPBIssuer.permit
    FinalizationResult=$final
    PreparedResult=$script:PPBValid.result
    StageExecutorResult=$script:PPBStageResult.stage_result
    Name='tagify'
    LifecycleRow=$q.bundle.lifecycle
    ProvenanceRow=$q.bundle.provenance
    BindingRow=$q.bundle.binding
    SessionKey=$script:DINPIKey
    LocalAppDataRoot=$script:PPBLocal
    AppDataRoot=$script:PPBRoaming
}
$script:E2EAt=$script:PPBAt.AddMilliseconds(650)
$adm=Resolve-CustomAppProductionPostSwapApplyAdmissionV010 @E2ECommon -Now $script:E2EAt
Assert-E2E ([bool]$adm.ok -and [bool]$adm.apply_eligible) ('postswap admission rejected real new Permit: '+[string]$adm.reason)
Check-E2ENoAuthority $adm 'admission'
$script:E2ECases++

# Denials must happen before launching even the FAKE executable. The original
# approved live code must remain byte-for-byte unchanged across denial probes.
$script:E2EExpectedPost=Get-CustomAppUpdateTreeSnapshotV010 -Root $script:TIDLive
$wrongKey=@{};foreach($k in $script:E2ECommon.Keys){$wrongKey[$k]=$script:E2ECommon[$k]}
$wrongKey.SessionKey=[byte[]](33..64)
$badAdmission=Resolve-CustomAppProductionPostSwapApplyAdmissionV010 @wrongKey -Now $script:E2EAt
Assert-E2E (-not[bool]$badAdmission.ok) 'wrong signing key accepted after swap'
Check-E2ENoAuthority $badAdmission 'wrong-key'
$script:E2ECases++

$script:E2EApplyArgs=@{};foreach($k in $script:E2ECommon.Keys){$script:E2EApplyArgs[$k]=$script:E2ECommon[$k]}
$script:E2EApplyArgs.SpicetifyExecutablePath=$script:E2EFakeExe
$script:E2EApplyArgs.ExpectedSpicetifySha256=$script:E2EFakeSha
$script:E2EApplyArgs.Now=$script:E2EAt
$script:E2EApplyArgs.TimeoutSeconds=15
$badHash=@{};foreach($k in $script:E2EApplyArgs.Keys){$badHash[$k]=$script:E2EApplyArgs[$k]}
$badHash.ExpectedSpicetifySha256=('0'*64)
$rejected=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 @badHash
Assert-E2E (-not [bool]$rejected.ok -and -not [bool]$rejected.spicetify_apply_executed) ('tampered executable hash accepted: '+[string]$rejected.reason)
Assert-E2E (-not (Test-Path -LiteralPath $script:E2ECounter)) 'fake executable launched on wrong digest'
Check-E2ENoAuthority $rejected 'wrong-exe-sha'
$afterDenial=Get-CustomAppUpdateTreeSnapshotV010 -Root $script:TIDLive
Assert-E2E ([string]$afterDenial.tree_sha256 -ceq [string]$script:E2EExpectedPost.tree_sha256) 'failed admission changed live app'
$script:E2ECases++

try{
    $env:SC_TRIPLE_LIVE=Join-Path $script:TIDLive 'index.js'
    $env:SC_TRIPLE_COUNT=$script:E2ECounter
    $env:SC_TRIPLE_APPLIED=$script:E2EApplied
    foreach($p in @($env:SC_TRIPLE_LIVE,$env:SC_TRIPLE_COUNT,$env:SC_TRIPLE_APPLIED)){Assert-Isolated $p 'fake-executable-io'}
    $applied=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 @E2EApplyArgs
}finally{
    foreach($n in @('SC_TRIPLE_LIVE','SC_TRIPLE_COUNT','SC_TRIPLE_APPLIED')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
}
Assert-E2E ([bool]$applied.ok -and [bool]$applied.spicetify_apply_executed -and [bool]$applied.requires_post_apply_commit_cleanup) ('fake Spicetify final apply rejected: '+[string]$applied.reason)
Assert-E2E ([int]([IO.File]::ReadAllText($script:E2ECounter).Trim()) -eq 1) 'Spicetify fake process ran more or less than once'
Assert-E2E ([IO.File]::ReadAllText($script:E2EApplied) -ceq [IO.File]::ReadAllText((Join-Path $script:TIDLive 'index.js'))) 'fake apply did not process newly swapped app'
$applyCheck=Test-CustomAppProductionSpicetifyApplyResultV010 -Result $applied.result
Assert-E2E ([bool]$applyCheck.ok) ('apply result integrity failed: '+[string]$applyCheck.reason)
Check-E2ENoAuthority $applied 'apply'
Check-E2ENoAuthority $applied.result 'apply-result'
$script:E2ECases++

$cleanupArgs=@{};foreach($k in $script:E2ECommon.Keys){$cleanupArgs[$k]=$script:E2ECommon[$k]}
$cleanupArgs.ApplyResult=$applied.result
$cleanupArgs.Now=$script:E2EAt.AddMilliseconds(200)
$cleanup=Invoke-CustomAppProductionPostApplyCommitCleanupV010 @cleanupArgs
Assert-E2E ([bool]$cleanup.ok -and [bool]$cleanup.update_commit_complete -and [bool]$cleanup.all_transaction_artifacts_clean) ('committed cleanup failed: '+[string]$cleanup.reason)
$cleanCheck=Test-CustomAppProductionPostApplyCommitCleanupResultV010 -Result $cleanup.result
Assert-E2E ([bool]$cleanCheck.ok) ('cleanup receipt invalid: '+[string]$cleanCheck.reason)
foreach($p in @($script:PPBValid.result.stage_workspace_path,$script:PPBValid.result.app_backup_path,$script:PPBValid.result.persistence_backup_path)){
    Assert-E2E (-not(Test-Path -LiteralPath ([string]$p))) ('committed artifact still present: '+$p)
}
$afterCommit=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
Assert-E2E ([string]$afterCommit.tree_sha256 -ceq [string]$script:PPBStageResult.stage_result.remote_tree_sha256) 'committed live code differs from ZIP'
$git=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $script:TIDLive '.git')
Assert-E2E ([string]$git.tree_sha256 -ceq [string]$script:BeforeGit.tree_sha256) 'committed git drift'
$p=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-E2E ([string]$p.fingerprint -ceq [string]$script:BeforePersist.fingerprint) 'committed Spotify config drift'
Assert-E2E ([int]([IO.File]::ReadAllText($script:E2ECounter).Trim()) -eq 1) 'cleanup unexpectedly reapplied fake Spicetify'
Check-E2ENoAuthority $cleanup 'cleanup'
Check-E2ENoAuthority $cleanup.result 'cleanup-result'
$script:E2ECases++

Assert-E2E ($script:E2ECases -eq 9) ('case count '+$script:E2ECases)
Write-Host "TRIPLE_ID_REAL_ZIP_FAKE_APPLY_CLEANUP_E2E_PASS cases=9 third_permit=true real_isolated_swap=true finalization=true fake_apply_count=1 persisted_consumption=true wrong_key_and_exe_denied=true stage_app_and_persistence_cleanup=true git_and_spotify_persistence_unchanged=true no_actual_spicetify=true production_untouched=true"
