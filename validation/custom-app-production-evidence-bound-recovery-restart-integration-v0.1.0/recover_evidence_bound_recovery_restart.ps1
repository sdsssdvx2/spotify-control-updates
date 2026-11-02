param([Parameter(Mandatory=$true)][string]$StatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')

function Assert-RecoverTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RecoverFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RecoverEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){throw 'restart state file missing'}
$state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
Assert-RecoverTrue ([int]$state.schema -eq 1) 'restart state schema invalid'
Assert-RecoverEq $state.managed_by 'custom-app-production-evidence-bound-recovery-restart-seed-v1' 'restart state owner invalid'
$tx=([string]$state.transaction_id).Trim().ToLowerInvariant()
Assert-RecoverTrue ($tx -cmatch '^[0-9a-f]{64}$') 'restart transaction id invalid'

$beforeJournal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
Assert-RecoverTrue ([bool]$beforeJournal.ok) 'restart journal unreadable before admission'
Assert-RecoverEq $beforeJournal.transaction_id $tx 'restart journal transaction mismatch'
Assert-RecoverEq $beforeJournal.entry.phase 'live-moved-to-old' 'restart journal phase before admission'
$beforeEvidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $tx
Assert-RecoverTrue ([bool]$beforeEvidence.ok) ('restart evidence unreadable before admission: '+[string]$beforeEvidence.reason)
Assert-RecoverEq $beforeEvidence.evidence_fingerprint $state.recovery_evidence_fingerprint 'restart evidence fingerprint before admission'

$fakeRoot=Join-Path $env:RUNNER_TEMP ('spotify-control-evidence-bound-restart-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class EvidenceBoundRestartFakeSpicetify {
    static string E(string n){ return Environment.GetEnvironmentVariable(n) ?? ""; }
    static int Next(string p){ int n=0; if(File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(),out n); n++; File.WriteAllText(p,n.ToString()); return n; }
    public static int Main(string[] args){
        if(args==null || args.Length!=1 || args[0]!="apply") return 64;
        string count=E("SC_EBR_COUNT"), live=E("SC_EBR_LIVE"), applied=E("SC_EBR_APPLIED");
        if(String.IsNullOrEmpty(count)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied)) return 65;
        Next(count);
        File.WriteAllText(applied,File.Exists(live)?File.ReadAllText(live):"");
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-RecoverTrue ($fakeSha -cmatch '^[0-9a-f]{64}$') 'restart fake spicetify hash invalid'
$countPath=Join-Path $fakeRoot 'apply-count.txt'
$appliedPath=Join-Path $fakeRoot 'applied-index.txt'
$env:SC_EBR_COUNT=$countPath
$env:SC_EBR_LIVE=Join-Path ([string]$state.live_path) 'index.js'
$env:SC_EBR_APPLIED=$appliedPath

try {
    $now=[DateTimeOffset]::UtcNow
    $admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $tx -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot $fakeRoot -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now
    Assert-RecoverTrue ([bool]$admission.ok) ('restart restore-resume admission denied: '+[string]$admission.reason)
    Assert-RecoverEq $admission.receipt.transaction_id $tx 'restart admission transaction'
    Assert-RecoverEq $admission.receipt.phase 'live-moved-to-old' 'restart admission phase'
    Assert-RecoverEq $admission.receipt.evidence_fingerprint $state.recovery_evidence_fingerprint 'restart admission evidence continuity'
    Assert-RecoverEq $admission.receipt.transaction_root $state.transaction_root 'restart admission transaction root continuity'
    Assert-RecoverTrue ([bool]$admission.receipt.restore_resume_eligible) 'restart admission not eligible'
    Assert-RecoverTrue ([bool]$admission.receipt.requires_exact_restore) 'restart admission did not require exact restore'
    Assert-RecoverFalse ([bool]$admission.receipt.admission_is_authority) 'restart admission authority escaped'
    $admissionCheck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $admission.receipt -Now $now
    Assert-RecoverTrue ([bool]$admissionCheck.ok) ('restart admission receipt invalid: '+[string]$admissionCheck.reason)

    $result=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $tx -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot $fakeRoot -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now.AddMilliseconds(10) -TimeoutSeconds 20
    Assert-RecoverTrue ([bool]$result.ok) ('restart executor denied: '+[string]$result.reason)
    Assert-RecoverTrue ([bool]$result.result.restore_performed) 'restart executor did not restore'
    Assert-RecoverTrue ([bool]$result.result.recovery_apply_executed) 'restart executor did not run recovery apply'
    Assert-RecoverTrue ([bool]$result.result.rollback_complete_persisted) 'restart executor did not persist rollback-complete'
    foreach($field in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RecoverFalse ([bool]$result.result.$field) ('restart executor authority escaped '+$field)}
    $resultCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $result.result
    Assert-RecoverTrue ([bool]$resultCheck.ok) ('restart executor result invalid: '+[string]$resultCheck.reason)

    $afterJournal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
    Assert-RecoverTrue ([bool]$afterJournal.ok) 'restart journal unreadable after executor'
    Assert-RecoverEq $afterJournal.transaction_id $tx 'restart journal transaction after executor'
    Assert-RecoverEq $afterJournal.entry.phase 'rollback-complete' 'restart journal final phase'

    $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$state.live_path)
    Assert-RecoverEq $app.tree_sha256 $state.app_backup_tree_sha256 'restart restored app tree'
    Assert-RecoverTrue ([int]$app.file_count -eq [int]$state.app_backup_file_count) 'restart restored app file count'
    Assert-RecoverTrue ([int64]$app.total_bytes -eq [int64]$state.app_backup_total_bytes) 'restart restored app total bytes'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root)
    Assert-RecoverEq $persist.fingerprint $state.persistence_fingerprint 'restart restored persistence fingerprint'

    Assert-RecoverTrue (Test-Path -LiteralPath ([string]$state.stage_workspace_path) -PathType Container) 'restart stage artifact unexpectedly retired'
    Assert-RecoverTrue (Test-Path -LiteralPath ([string]$state.app_backup_path) -PathType Container) 'restart app backup unexpectedly retired'
    Assert-RecoverTrue (Test-Path -LiteralPath ([string]$state.persistence_backup_path) -PathType Container) 'restart persistence backup unexpectedly retired'
    Assert-RecoverTrue (Test-Path -LiteralPath ([string]$state.transaction_root) -PathType Container) 'restart transaction artifact unexpectedly retired'

    Assert-RecoverTrue (Test-Path -LiteralPath $countPath -PathType Leaf) 'restart apply count missing'
    Assert-RecoverTrue ([int]([IO.File]::ReadAllText($countPath).Trim()) -eq 1) 'restart recovery apply count was not exactly one'
    Assert-RecoverTrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'restart applied state proof missing'
    $restoredIndex=[IO.File]::ReadAllText((Join-Path ([string]$state.live_path) 'index.js'))
    Assert-RecoverEq ([IO.File]::ReadAllText($appliedPath)) $restoredIndex 'restart apply did not observe restored old live state'

    $afterEvidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $tx
    Assert-RecoverTrue ([bool]$afterEvidence.ok) ('restart evidence unreadable after rollback-complete: '+[string]$afterEvidence.reason)
    Assert-RecoverEq $afterEvidence.evidence_fingerprint $state.recovery_evidence_fingerprint 'restart evidence fingerprint after rollback-complete'

    $replay=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId $tx -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot $fakeRoot -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now.AddSeconds(1) -TimeoutSeconds 20
    Assert-RecoverFalse ([bool]$replay.ok) 'rollback-complete replay unexpectedly accepted'
    Assert-RecoverTrue ([string]$replay.reason -like 'recovery-restore-executor-initial-admission-denied:*') 'rollback-complete replay denial reason drift'
    Assert-RecoverTrue ([int]([IO.File]::ReadAllText($countPath).Trim()) -eq 1) 'rollback-complete replay launched a second apply'

    Write-Output ('CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTART_PASS tx='+$tx+' apply_count=1 phase=rollback-complete')
}
finally {
    foreach($name in @('SC_EBR_COUNT','SC_EBR_LIVE','SC_EBR_APPLIED')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    if(Test-Path -LiteralPath $fakeRoot){Remove-Item -LiteralPath $fakeRoot -Recurse -Force}
}
