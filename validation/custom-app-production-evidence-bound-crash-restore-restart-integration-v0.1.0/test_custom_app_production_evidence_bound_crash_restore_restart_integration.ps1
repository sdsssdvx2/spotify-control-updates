$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse the exact #190 fixture path and matrix. This validates the producer before
# exercising a fresh-process consumer handoff.
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function Assert-EBCRTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-EBCRFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-EBCREq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$child=Join-Path $PSScriptRoot 'recover_in_fresh_process.ps1'
if(-not (Test-Path -LiteralPath $child -PathType Leaf)){throw 'fresh-process child harness missing'}

$trust=Get-EBTrustRootV010
$fakeRoot=Join-Path $trust ('evidence-bound-crash-restore-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class EvidenceBoundRecoveryFakeSpicetify {
    static string E(string n){return Environment.GetEnvironmentVariable(n) ?? "";}
    static int Next(string p){int n=0;if(File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(),out n);n++;File.WriteAllText(p,n.ToString());return n;}
    public static int Main(string[] args){
        if(args==null || args.Length!=1 || args[0]!="apply") return 64;
        string count=E("SC_EBCR_COUNT"), live=E("SC_EBCR_LIVE"), applied=E("SC_EBCR_APPLIED");
        if(String.IsNullOrEmpty(count)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied)) return 65;
        Next(count);
        File.WriteAllText(applied,File.Exists(live)?File.ReadAllText(live):"");
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
if($fakeSha -notmatch '^[0-9a-f]{64}$'){throw 'fresh-process fake spicetify hash invalid'}

function Get-EBCRCountV010([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 0};return [int]([IO.File]::ReadAllText($Path).Trim())}
function Clear-EBCREnvV010 {foreach($n in @('SC_EBCR_COUNT','SC_EBCR_LIVE','SC_EBCR_APPLIED')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}}
function Invoke-EBCRChildV010 {
    param([string]$StatePath,[switch]$Replay)
    $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$child,'-StatePath',$StatePath)
    if($Replay){$args+='-ExpectReplayDeny'}
    $out=& powershell.exe @args 2>&1
    $code=$LASTEXITCODE
    $out|ForEach-Object{Write-Host $_}
    if($code -ne 0){throw "fresh-process recovery child failed exit=$code"}
}

function Invoke-EBCRCaseV010 {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('post-first-rename','candidate-live')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$Nonce,
        [Parameter(Mandatory=$true)][string]$TransactionNonce
    )
    $label=('handoff-'+$Mode)
    $fixture=New-AtomicFixtureV010 $label -Nonce $Nonce
    $store=Get-EBStoreV010 $fixture $label
    $atomic=$null
    if($Mode -ceq 'post-first-rename'){
        $atomic=Invoke-EBFixtureV010 -Fixture $fixture -Nonce $TransactionNonce -Label $label -Fault 'after-live-move-before-journal'
        Assert-EBCRFalse ([bool]$atomic.ok) 'post-first crash unexpectedly succeeded'
        Assert-EBCRTrue ([bool]$atomic.recovery_evidence_persisted) 'post-first crash lost recovery evidence'
        $ia=Get-EBInspectionArgsV010 $fixture $label
        $inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
        Assert-EBCRTrue ([bool]$inspection.ok) ('post-first inspection denied: '+[string]$inspection.reason)
        Assert-EBCREq $inspection.receipt.state 'first-rename-complete-unjournaled' 'post-first inspection state'
        $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia
        Assert-EBCRTrue ([bool]$repair.ok) ('post-first repair denied: '+[string]$repair.reason)
        Assert-EBCREq $repair.phase 'live-moved-to-old' 'post-first normalized phase'
    } else {
        $atomic=Invoke-EBFixtureV010 -Fixture $fixture -Nonce $TransactionNonce -Label $label
        Assert-EBCRTrue ([bool]$atomic.ok) ('candidate-live producer denied: '+[string]$atomic.reason)
        Assert-EBCRTrue ([bool]$atomic.result.recovery_evidence_persisted) 'candidate-live producer lost recovery evidence'
        Assert-EBCREq $atomic.result.journal_phase 'candidate-live' 'candidate-live producer phase'
    }

    $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $trust -StoreDirectory $store
    Assert-EBCRTrue ([bool]$journal.ok) ('handoff journal invalid: '+[string]$journal.reason)
    $expectedPhase=if($Mode -ceq 'post-first-rename'){'live-moved-to-old'}else{'candidate-live'}
    Assert-EBCREq $journal.entry.phase $expectedPhase 'handoff durable phase'
    $tx=([string]$journal.transaction_id).Trim().ToLowerInvariant()
    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $trust -StoreDirectory $store -ExpectedTransactionId $tx
    Assert-EBCRTrue ([bool]$evidence.ok) ('handoff evidence unreadable: '+[string]$evidence.reason)

    $control=Join-Path $trust ('evidence-bound-crash-restore-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    $countPath=Join-Path $control 'count.txt'
    $appliedPath=Join-Path $control 'applied.txt'
    $statePath=Join-Path $control 'state.json'
    $resultPath=Join-Path $control 'result.json'
    $env:SC_EBCR_COUNT=$countPath
    $env:SC_EBCR_LIVE=Join-Path ([string]$evidence.envelope.live_path) 'index.js'
    $env:SC_EBCR_APPLIED=$appliedPath

    $state=[pscustomobject]@{
        allowed_root=$trust;store_directory=$store;transaction_id=$tx
        local_app_data_root=[string]$fixture.q.persistence.local;app_data_root=[string]$fixture.q.persistence.roaming
        spicetify_allowed_root=$trust;spicetify_path=$fakeExe;spicetify_sha256=$fakeSha
        expected_app_tree_sha256=[string]$evidence.envelope.app_backup_tree_sha256;expected_app_file_count=[int]$evidence.envelope.app_backup_file_count;expected_app_total_bytes=[int64]$evidence.envelope.app_backup_total_bytes
        expected_persistence_fingerprint=[string]$evidence.envelope.persistence_fingerprint
        stage_workspace_path=[string]$evidence.envelope.stage_workspace_path;app_backup_path=[string]$evidence.envelope.app_backup_path;persistence_backup_path=[string]$evidence.envelope.persistence_backup_path;transaction_root=[string]$evidence.envelope.transaction_root
        result_path=$resultPath
    }
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))

    try{
        Invoke-EBCRChildV010 -StatePath $statePath
        Assert-EBCRTrue (Test-Path -LiteralPath $resultPath -PathType Leaf) 'fresh-process recovery result missing'
        $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
        Assert-EBCRTrue ([bool]$result.ok) 'fresh-process recovery result not ok'
        Assert-EBCREq $result.mode 'recovered' 'fresh-process recovery mode'
        Assert-EBCREq $result.started_phase $expectedPhase 'fresh-process starting phase'
        Assert-EBCREq $result.final_phase 'rollback-complete' 'fresh-process final phase'
        Assert-EBCRTrue ([bool]$result.restore_performed) 'fresh-process restore flag missing'
        Assert-EBCRTrue ([bool]$result.recovery_apply_executed) 'fresh-process apply flag missing'
        Assert-EBCRTrue ([bool]$result.artifacts_retained) 'fresh-process artifact retention flag missing'
        foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-EBCRFalse ([bool]$result.$f) ('fresh-process authority escaped '+$f)}
        Assert-EBCRTrue ((Get-EBCRCountV010 $countPath)-eq 1) 'fresh-process recovery apply count was not exactly one'
        Assert-EBCRTrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'fresh-process fake apply evidence missing'
        Assert-EBCREq ([IO.File]::ReadAllText($appliedPath)) ([IO.File]::ReadAllText((Join-Path ([string]$evidence.envelope.live_path) 'index.js'))) 'fresh-process apply did not observe restored old live state'

        Invoke-EBCRChildV010 -StatePath $statePath -Replay
        $replay=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
        Assert-EBCRTrue ([bool]$replay.ok) 'fresh-process replay result not ok'
        Assert-EBCREq $replay.mode 'replay-denied' 'fresh-process replay mode'
        Assert-EBCRTrue ((Get-EBCRCountV010 $countPath)-eq 1) 'rollback-complete replay launched a second recovery apply'

        $final=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $trust -StoreDirectory $store
        Assert-EBCRTrue ([bool]$final.ok) ('final handoff journal invalid: '+[string]$final.reason)
        Assert-EBCREq $final.entry.phase 'rollback-complete' 'final handoff phase'
        $evAfter=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $trust -StoreDirectory $store -ExpectedTransactionId $tx
        Assert-EBCRTrue ([bool]$evAfter.ok) ('evidence unreadable after recovery completion: '+[string]$evAfter.reason)
        Assert-EBCREq $evAfter.envelope.evidence_fingerprint $evidence.envelope.evidence_fingerprint 'evidence fingerprint drift after recovery'
        $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$evidence.envelope.live_path)
        Assert-EBCREq $app.tree_sha256 $evidence.envelope.app_backup_tree_sha256 'final restored app tree'
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$fixture.q.persistence.local) -AppDataRoot ([string]$fixture.q.persistence.roaming)
        Assert-EBCREq $persist.fingerprint $evidence.envelope.persistence_fingerprint 'final restored persistence'
        foreach($p in @([string]$evidence.envelope.transaction_root,[string]$evidence.envelope.stage_workspace_path,[string]$evidence.envelope.app_backup_path,[string]$evidence.envelope.persistence_backup_path)){Assert-EBCRTrue (Test-Path -LiteralPath $p) ('recovery artifact missing after completion: '+$p)}
    } finally {
        Clear-EBCREnvV010
    }
    return [pscustomobject]@{mode=$Mode;started_phase=$expectedPhase;transaction_id=$tx;recovery_apply_count=1;replay_apply_count=0;final_phase='rollback-complete'}
}

$results=@()
$results+=Invoke-EBCRCaseV010 -Mode 'post-first-rename' -Nonce '51515151515151515151515151515151' -TransactionNonce 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1'
$results+=Invoke-EBCRCaseV010 -Mode 'candidate-live' -Nonce '52525252525252525252525252525252' -TransactionNonce 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2'
if($results.Count -ne 2){throw 'fresh-process integration case count mismatch'}
if(@($results|Where-Object{$_.final_phase -cne 'rollback-complete'}).Count){throw 'fresh-process integration final phase mismatch'}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_CRASH_RESTORE_RESTART_INTEGRATION_PASS cases=$($results.Count) fresh_process_recoveries=2 replay_denials=2"
