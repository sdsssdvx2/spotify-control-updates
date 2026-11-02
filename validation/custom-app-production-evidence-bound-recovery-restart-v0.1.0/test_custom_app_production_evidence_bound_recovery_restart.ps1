$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function Assert-ERTrueV010([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-ERFalseV010([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-EREqV010($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$allowed=Get-EBTrustRootV010
$fakeRoot=Join-Path $allowed ('spotify-control-evidence-bound-recovery-restart-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class EvidenceBoundRecoveryRestartFakeSpicetify {
    static string E(string n){ return Environment.GetEnvironmentVariable(n) ?? ""; }
    static int Next(string p){ int n=0; if(File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(),out n); n++; File.WriteAllText(p,n.ToString()); return n; }
    public static int Main(string[] args){
        if(args==null || args.Length!=1 || args[0]!="apply") return 64;
        string count=E("SC_RX_COUNT"), live=E("SC_RX_LIVE"), applied=E("SC_RX_APPLIED"), mode=E("SC_RX_MODE");
        if(String.IsNullOrEmpty(count)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied)) return 65;
        Next(count);
        File.WriteAllText(applied,File.Exists(live)?File.ReadAllText(live):"");
        if(mode=="fail") return 7;
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-ERTrueV010 ($fakeSha -match '^[0-9a-f]{64}$') 'fake spicetify sha invalid'
$worker=Join-Path $PSScriptRoot 'invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
Assert-ERTrueV010 (Test-Path -LiteralPath $worker -PathType Leaf) 'recovery restart worker missing'

function Invoke-ERCrossProcessRestartV010 {
    param(
        [Parameter(Mandatory=$true)]$Fixture,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)][string]$EvidenceFingerprint,
        [Parameter(Mandatory=$true)][string]$ExpectedStartPhase
    )
    $control=Join-Path $allowed ('spotify-control-evidence-bound-recovery-restart-control-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    $statePath=Join-Path $control 'state.json'
    $resultPath=Join-Path $control 'result.json'
    $countPath=Join-Path $control 'apply-count.txt'
    $appliedPath=Join-Path $control 'applied-live-index.txt'
    $state=[ordered]@{
        schema=1
        managed_by='custom-app-production-evidence-bound-recovery-restart-test-v1'
        allowed_root=$allowed
        store_directory=(Get-EBStoreV010 $Fixture $Label)
        transaction_id=$TransactionId
        evidence_fingerprint=$EvidenceFingerprint
        expected_start_phase=$ExpectedStartPhase
        local_app_data_root=[string]$Fixture.q.persistence.local
        app_data_root=[string]$Fixture.q.persistence.roaming
        spicetify_allowed_root=$allowed
        spicetify_path=$fakeExe
        spicetify_sha256=$fakeSha
        apply_count_path=$countPath
        applied_probe_path=$appliedPath
        live_probe_path=(Join-Path ([string]$Fixture.q.x.live) 'index.js')
        parent_process_id=$PID
    }
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $childOutput=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath -ResultPath $resultPath 2>&1
    $childExit=$LASTEXITCODE
    foreach($line in @($childOutput)){Write-Host $line}
    Assert-ERTrueV010 (Test-Path -LiteralPath $resultPath -PathType Leaf) "$Label worker result missing"
    $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if($childExit -ne 0){throw "$Label cross-process worker failed exit=$childExit error=$([string]$result.error)"}
    Assert-ERTrueV010 ([bool]$result.success) "$Label worker success flag false: $([string]$result.error)"
    Assert-ERTrueV010 ([int]$result.process_id -ne $PID) "$Label did not execute in a distinct process"
    Assert-ERTrueV010 ([bool]$result.bootstrap_dependencies_verified) "$Label bootstrap dependency inventory was not verified"
    Assert-ERTrueV010 ([int]$result.bootstrap_dependency_count -eq 22) "$Label bootstrap dependency count"
    Assert-EREqV010 $result.transaction_id $TransactionId "$Label transaction id"
    Assert-ERTrueV010 ([bool]$result.admission_ok) "$Label admission failed"
    Assert-EREqV010 $result.admission_phase $ExpectedStartPhase "$Label admission phase"
    Assert-ERTrueV010 ([bool]$result.executor_ok) "$Label executor failed"
    Assert-EREqV010 $result.executor_started_phase $ExpectedStartPhase "$Label executor started phase"
    Assert-ERTrueV010 ([bool]$result.rollback_required_was_appended) "$Label rollback-required barrier was not appended"
    Assert-ERTrueV010 ([bool]$result.restore_performed) "$Label restore missing"
    Assert-ERTrueV010 ([bool]$result.recovery_apply_executed) "$Label recovery apply missing"
    Assert-ERTrueV010 ([bool]$result.rollback_complete_persisted) "$Label rollback-complete missing"
    Assert-EREqV010 $result.final_phase 'rollback-complete' "$Label final phase"
    Assert-EREqV010 $result.evidence_fingerprint_after $EvidenceFingerprint "$Label evidence fingerprint after recovery"
    Assert-ERTrueV010 ([int]$result.apply_count -eq 1) "$Label recovery apply count"
    return [pscustomobject]@{result=$result;control=$control;count_path=$countPath;applied_path=$appliedPath}
}

function Assert-ERRecoveredOldStateV010 {
    param([Parameter(Mandatory=$true)]$Fixture,[Parameter(Mandatory=$true)]$Cross,[Parameter(Mandatory=$true)][string]$TransactionRoot,[Parameter(Mandatory=$true)][string]$Label)
    $p=$Fixture.prepared.result
    $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Fixture.q.x.live)
    Assert-EREqV010 $live.tree_sha256 $p.app_backup_tree_sha256 "$Label restored app tree"
    Assert-ERTrueV010 ([int]$live.file_count -eq [int]$p.app_backup_file_count) "$Label restored app file count"
    Assert-ERTrueV010 ([int64]$live.total_bytes -eq [int64]$p.app_backup_total_bytes) "$Label restored app bytes"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$Fixture.q.persistence.local) -AppDataRoot ([string]$Fixture.q.persistence.roaming)
    Assert-EREqV010 $persist.fingerprint $p.persistence_fingerprint "$Label restored persistence"
    Assert-ERTrueV010 (Test-Path -LiteralPath ([string]$p.stage_workspace_path) -PathType Container) "$Label stage workspace was retired early"
    Assert-ERTrueV010 (Test-Path -LiteralPath ([string]$p.app_backup_path) -PathType Container) "$Label app backup was retired early"
    Assert-ERTrueV010 (Test-Path -LiteralPath ([string]$p.persistence_backup_path) -PathType Container) "$Label persistence backup was retired early"
    Assert-ERTrueV010 (Test-Path -LiteralPath $TransactionRoot -PathType Container) "$Label transaction root was retired early"
    Assert-ERTrueV010 (Test-Path -LiteralPath ([string]$Cross.applied_path) -PathType Leaf) "$Label applied probe missing"
    $expectedIndex=[IO.File]::ReadAllText((Join-Path ([string]$p.app_backup_path) 'index.js'))
    $appliedIndex=[IO.File]::ReadAllText([string]$Cross.applied_path)
    Assert-ERTrueV010 ($appliedIndex -ceq $expectedIndex) "$Label recovery apply did not observe restored old live state"
}

$integrationCount=0

# Case 1: process dies after live -> old-live rename but before the live-moved-to-old journal append.
# #189 repair must first normalize the exact filesystem state, then a brand-new PowerShell process must
# consume #190 durable evidence through #156 and #157 and finish rollback-complete.
$first=New-AtomicFixtureV010 'evidence-bound-recovery-restart-first-rename' -Nonce '51515151515151515151515151515151'
$firstMutation=Invoke-EBFixtureV010 -Fixture $first -Nonce 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1' -Label 'first-rename-restart' -Fault 'after-live-move-before-journal'
$firstTxn=Get-EBTransactionRootV010 $firstMutation
try {
    Assert-ERFalseV010 ([bool]$firstMutation.ok) 'first-rename crash unexpectedly succeeded'
    Assert-ERTrueV010 ([bool]$firstMutation.recovery_evidence_persisted) 'first-rename crash lost recovery evidence'
    $ia=Get-EBInspectionArgsV010 $first 'first-rename-restart'
    $inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
    Assert-ERTrueV010 ([bool]$inspection.ok) ('first-rename inspection denied: '+[string]$inspection.reason)
    Assert-EREqV010 $inspection.receipt.state 'first-rename-complete-unjournaled' 'first-rename inspection state'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1))
    Assert-ERTrueV010 ([bool]$repair.ok) ('first-rename repair denied: '+[string]$repair.reason)
    Assert-EREqV010 $repair.phase 'live-moved-to-old' 'first-rename normalized phase'
    $evidence=Get-EBEvidenceV010 $first 'first-rename-restart' ([string]$repair.transaction_id)
    Assert-ERTrueV010 ([bool]$evidence.ok) ('first-rename evidence unreadable before restart: '+[string]$evidence.reason)
    $cross=Invoke-ERCrossProcessRestartV010 -Fixture $first -Label 'first-rename-restart' -TransactionId ([string]$repair.transaction_id) -EvidenceFingerprint ([string]$evidence.evidence_fingerprint) -ExpectedStartPhase 'live-moved-to-old'
    Assert-ERRecoveredOldStateV010 -Fixture $first -Cross $cross -TransactionRoot $firstTxn -Label 'first-rename-restart'
    $final=Get-EBJournalV010 $first 'first-rename-restart'
    Assert-EREqV010 $final.entry.phase 'rollback-complete' 'first-rename final durable phase'
    $integrationCount++
} finally {
    Restore-EBFixtureV010 $first $firstTxn
}

# Case 2: both directory renames and candidate-live journal append completed, then the process disappears
# before transaction finalization/apply. A brand-new process must restore the exact old state and apply once.
$candidate=New-AtomicFixtureV010 'evidence-bound-recovery-restart-candidate-live' -Nonce '52525252525252525252525252525252'
$candidateMutation=Invoke-EBFixtureV010 -Fixture $candidate -Nonce 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2' -Label 'candidate-live-restart'
$candidateTxn=Get-EBTransactionRootV010 $candidateMutation
try {
    Assert-ERTrueV010 ([bool]$candidateMutation.ok) ('candidate-live mutation denied: '+[string]$candidateMutation.reason)
    $candidateResultCheck=Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 -Result $candidateMutation.result
    Assert-ERTrueV010 ([bool]$candidateResultCheck.ok) ('candidate-live mutation result invalid: '+[string]$candidateResultCheck.reason)
    $journal=Get-EBJournalV010 $candidate 'candidate-live-restart'
    Assert-EREqV010 $journal.entry.phase 'candidate-live' 'candidate-live durable phase before restart'
    $evidence=Get-EBEvidenceV010 $candidate 'candidate-live-restart' ([string]$journal.transaction_id)
    Assert-ERTrueV010 ([bool]$evidence.ok) ('candidate-live evidence unreadable before restart: '+[string]$evidence.reason)
    Assert-EREqV010 $evidence.evidence_fingerprint $candidateMutation.result.recovery_evidence_fingerprint 'candidate-live evidence fingerprint'
    $cross=Invoke-ERCrossProcessRestartV010 -Fixture $candidate -Label 'candidate-live-restart' -TransactionId ([string]$journal.transaction_id) -EvidenceFingerprint ([string]$evidence.evidence_fingerprint) -ExpectedStartPhase 'candidate-live'
    Assert-ERRecoveredOldStateV010 -Fixture $candidate -Cross $cross -TransactionRoot $candidateTxn -Label 'candidate-live-restart'
    $final=Get-EBJournalV010 $candidate 'candidate-live-restart'
    Assert-EREqV010 $final.entry.phase 'rollback-complete' 'candidate-live final durable phase'
    $integrationCount++
} finally {
    Restore-EBFixtureV010 $candidate $candidateTxn
}

try{if(Test-Path -LiteralPath $fakeRoot){[IO.Directory]::Delete($fakeRoot,$true)}}catch{}
if($integrationCount -ne 2){throw "evidence-bound recovery restart integration count mismatch $integrationCount"}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTART_MATRIX_PASS cases=$integrationCount cross_process=true"