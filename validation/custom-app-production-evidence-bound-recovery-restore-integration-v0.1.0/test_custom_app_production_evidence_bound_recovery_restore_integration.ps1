$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse the exact #190 fixture and crash/repair harness. Dot-sourcing it also replays
# the already-validated evidence-bound atomic matrix in this mixed-lineage worktree.
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function Assert-IRTrue([bool]$v,[string]$m){if(-not $v){throw $m}}
function Assert-IRFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-IREq($a,$b,[string]$m){if([string]$a -cne [string]$b){throw "$m actual=<$a> expected=<$b>"}}

$worker=Join-Path $PSScriptRoot 'recovery_worker.ps1'
if(-not (Test-Path -LiteralPath $worker -PathType Leaf)){throw 'integration recovery worker missing'}

$fakeRoot=Join-Path (Get-EBTrustRootV010) ('evidence-bound-recovery-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class EvidenceBoundRecoveryFakeSpicetify {
    static string E(string n){ return Environment.GetEnvironmentVariable(n) ?? ""; }
    public static int Main(string[] args){
        if(args==null || args.Length!=1 || args[0]!="apply") return 64;
        string count=E("SC_EBRI_COUNT"), live=E("SC_EBRI_LIVE"), applied=E("SC_EBRI_APPLIED");
        if(String.IsNullOrEmpty(count)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied)) return 65;
        int n=0; if(File.Exists(count)) Int32.TryParse(File.ReadAllText(count).Trim(),out n); File.WriteAllText(count,(n+1).ToString());
        File.WriteAllText(applied,File.Exists(live)?File.ReadAllText(live):"");
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
if($fakeSha -notmatch '^[0-9a-f]{64}$'){throw 'integration fake spicetify hash invalid'}

function Clear-IREnvironmentV010 {
    foreach($n in @('SC_EBRI_COUNT','SC_EBRI_LIVE','SC_EBRI_APPLIED')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
}
function Get-IRApplyCountV010([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 0};return [int]([IO.File]::ReadAllText($Path).Trim())}
function Assert-IRRestoredStateV010 {
    param($Fixture,[string]$Label)
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Fixture.q.x.live)
    Assert-IREq ([string]$full.tree_sha256) ([string]$Fixture.full_before.tree_sha256) "$Label restored full tree"
    Assert-IRTrue ([int]$full.file_count -eq [int]$Fixture.full_before.file_count "$Label restored file count")
    Assert-IRTrue ([int64]$full.total_bytes -eq [int64]$Fixture.full_before.total_bytes "$Label restored total bytes")
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Fixture.q.x.f.name) -AppPath ([string]$Fixture.q.x.live)
    Assert-IREq ([string]$runtime.tree_sha256) ([string]$Fixture.runtime_before.tree_sha256) "$Label restored runtime tree"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$Fixture.q.persistence.local) -AppDataRoot ([string]$Fixture.q.persistence.roaming)
    Assert-IREq ([string]$persist.fingerprint) ([string]$Fixture.persistence_before.fingerprint) "$Label restored persistence"
}
function Invoke-IRSeparateProcessRecoveryV010 {
    param(
        $Fixture,
        [Parameter(Mandatory=$true)][string]$StoreLabel,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)][string]$EvidenceFingerprint,
        [Parameter(Mandatory=$true)][string]$ExpectedInitialPhase,
        [Parameter(Mandatory=$true)][string]$ExpectedInitialLiveState,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $control=Join-Path (Get-EBTrustRootV010) ('evidence-bound-recovery-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    $statePath=Join-Path $control 'state.json';$resultPath=Join-Path $control 'worker-result.json';$countPath=Join-Path $control 'apply-count.txt';$appliedPath=Join-Path $control 'applied.txt'
    $txnRoot=$null
    $jr=Get-EBJournalV010 $Fixture $StoreLabel
    if($null -eq $jr -or -not[bool]$jr.ok){throw "$Label pre-worker journal unreadable"}
    $txnRoot=[string]$jr.entry.transaction_root
    $state=[pscustomobject]@{
        allowed_root=(Get-EBTrustRootV010)
        store_directory=(Get-EBStoreV010 $Fixture $StoreLabel)
        transaction_id=$TransactionId.Trim().ToLowerInvariant()
        evidence_fingerprint=$EvidenceFingerprint.Trim().ToLowerInvariant()
        preparation_fingerprint=([string]$Fixture.prepared.result.preparation_fingerprint).Trim().ToLowerInvariant()
        local_appdata_root=[string]$Fixture.q.persistence.local
        appdata_root=[string]$Fixture.q.persistence.roaming
        spicetify_allowed_root=(Get-EBTrustRootV010)
        spicetify_path=$fakeExe
        spicetify_sha256=$fakeSha
        worker_result_path=$resultPath
    }
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $env:SC_EBRI_COUNT=$countPath
    $env:SC_EBRI_LIVE=Join-Path ([string]$Fixture.q.x.live) 'index.js'
    $env:SC_EBRI_APPLIED=$appliedPath
    try{
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath
        if($LASTEXITCODE -ne 0){throw "$Label recovery worker exited $LASTEXITCODE"}
    } finally {Clear-IREnvironmentV010}
    Assert-IRTrue (Test-Path -LiteralPath $resultPath -PathType Leaf) "$Label worker result missing"
    $wr=(Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json)
    Assert-IRTrue ([bool]$wr.ok) "$Label worker result not ok"
    Assert-IRTrue ([int]$wr.worker_pid -ne $PID) "$Label recovery did not run in a separate process"
    Assert-IREq ([string]$wr.initial_phase) $ExpectedInitialPhase "$Label initial phase"
    Assert-IREq ([string]$wr.initial_live_state) $ExpectedInitialLiveState "$Label initial live state"
    Assert-IREq ([string]$wr.executor_started_phase) $ExpectedInitialPhase "$Label executor started phase"
    Assert-IREq ([string]$wr.transaction_id) $TransactionId.Trim().ToLowerInvariant() "$Label transaction continuity"
    Assert-IREq ([string]$wr.evidence_fingerprint) $EvidenceFingerprint.Trim().ToLowerInvariant() "$Label evidence continuity"
    Assert-IREq ([string]$wr.preparation_fingerprint) ([string]$Fixture.prepared.result.preparation_fingerprint).Trim().ToLowerInvariant() "$Label preparation continuity"
    Assert-IRTrue ([bool]$wr.rollback_required_was_appended) "$Label rollback-required barrier was not appended"
    Assert-IRTrue ([bool]$wr.restore_performed) "$Label restore not performed"
    Assert-IRTrue ([bool]$wr.recovery_apply_executed) "$Label recovery apply not executed"
    Assert-IRTrue ([bool]$wr.rollback_complete_persisted) "$Label rollback-complete not persisted"
    Assert-IREq ([string]$wr.final_phase) 'rollback-complete' "$Label final phase"
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-IRFalse ([bool]$wr.$f) "$Label authority escaped $f"}
    Assert-IRTrue ((Get-IRApplyCountV010 $countPath)-eq 1) "$Label recovery apply count was not exactly one"
    Assert-IRTrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) "$Label applied-state capture missing"
    $oldIndex=[IO.File]::ReadAllText((Join-Path ([string]$Fixture.prepared.result.app_backup_path) 'index.js'))
    Assert-IREq ([IO.File]::ReadAllText($appliedPath)) $oldIndex "$Label recovery apply did not target restored old live"
    Assert-IRRestoredStateV010 $Fixture $Label
    $final=Get-EBJournalV010 $Fixture $StoreLabel;Assert-IREq ([string]$final.entry.phase) 'rollback-complete' "$Label final durable journal"
    $ev=Get-EBEvidenceV010 $Fixture $StoreLabel $TransactionId;Assert-IRTrue ([bool]$ev.ok) "$Label durable evidence unreadable after rollback-complete";Assert-IREq ([string]$ev.evidence_fingerprint) $EvidenceFingerprint.Trim().ToLowerInvariant() "$Label durable evidence changed"
    Assert-IRTrue (Test-Path -LiteralPath ([string]$Fixture.prepared.result.stage_workspace_path) -PathType Container) "$Label stage artifact retired unexpectedly"
    Assert-IRTrue (Test-Path -LiteralPath ([string]$Fixture.prepared.result.app_backup_path) -PathType Container) "$Label app backup retired unexpectedly"
    Assert-IRTrue (Test-Path -LiteralPath ([string]$Fixture.prepared.result.persistence_backup_path) -PathType Container) "$Label persistence backup retired unexpectedly"
    Assert-IRTrue (Test-Path -LiteralPath $txnRoot -PathType Container) "$Label transaction artifact retired unexpectedly"
    return $wr
}

$count=0

# Crash exactly after live -> old-live rename but before the journal can record it.
$first=New-AtomicFixtureV010 'evidence-recovery-first-rename' -Nonce '51515151515151515151515151515151'
$r=Invoke-EBFixtureV010 -Fixture $first -Nonce 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1' -Label 'restore-first-rename' -Fault 'after-live-move-before-journal'
Assert-IRFalse ([bool]$r.ok) 'first-rename crash unexpectedly succeeded'
$ia=Get-EBInspectionArgsV010 $first 'restore-first-rename'
$inspect=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
Assert-IRTrue ([bool]$inspect.ok) ('first-rename inspection denied: '+[string]$inspect.reason)
Assert-IREq ([string]$inspect.receipt.state) 'first-rename-complete-unjournaled' 'first-rename inspection state'
$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1))
Assert-IRTrue ([bool]$repair.ok) ('first-rename normalization denied: '+[string]$repair.reason)
Assert-IREq ([string]$repair.phase) 'live-moved-to-old' 'first-rename normalized phase'
$ev=Get-EBEvidenceV010 $first 'restore-first-rename' ([string]$repair.transaction_id)
Assert-IRTrue ([bool]$ev.ok) ('first-rename evidence missing before restart: '+[string]$ev.reason)
[void](Invoke-IRSeparateProcessRecoveryV010 -Fixture $first -StoreLabel 'restore-first-rename' -TransactionId ([string]$repair.transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -ExpectedInitialPhase 'live-moved-to-old' -ExpectedInitialLiveState 'absent-after-live-move' -Label 'first-rename restart recovery')
$count++

# Complete the two renames and candidate-live journal barrier, then simulate process death
# before transaction finalization/apply. Recovery must still restore the exact old state.
$candidate=New-AtomicFixtureV010 'evidence-recovery-candidate-live' -Nonce '52525252525252525252525252525252'
$r=Invoke-EBFixtureV010 -Fixture $candidate -Nonce 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2' -Label 'restore-candidate-live'
Assert-IRTrue ([bool]$r.ok) ('candidate-live setup denied: '+[string]$r.reason)
$jr=Get-EBJournalV010 $candidate 'restore-candidate-live';Assert-IREq ([string]$jr.entry.phase) 'candidate-live' 'candidate-live durable phase'
$ev=Get-EBEvidenceV010 $candidate 'restore-candidate-live' ([string]$jr.transaction_id);Assert-IRTrue ([bool]$ev.ok) ('candidate-live evidence missing before restart: '+[string]$ev.reason)
[void](Invoke-IRSeparateProcessRecoveryV010 -Fixture $candidate -StoreLabel 'restore-candidate-live' -TransactionId ([string]$jr.transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -ExpectedInitialPhase 'candidate-live' -ExpectedInitialLiveState 'candidate-live-exact' -Label 'candidate-live restart recovery')
$count++

if($count -ne 2){throw "evidence-bound recovery restore integration count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTORE_INTEGRATION_PASS cases=$count separate_process=true"
