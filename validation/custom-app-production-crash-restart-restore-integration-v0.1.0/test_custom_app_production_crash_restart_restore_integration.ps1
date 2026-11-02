param(
    [ValidateSet('Harness','Recover')][string]$Mode='Harness',
    [AllowNull()][string]$StatePath=$null,
    [AllowNull()][string]$ResultPath=$null
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Assert-CRITrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-CRIFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-CRIEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Get-CRIJson([string]$Path){return ([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)|ConvertFrom-Json)}
function Write-CRIJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 80),[Text.UTF8Encoding]::new($false))}

if($Mode -ceq 'Recover'){
    if([string]::IsNullOrWhiteSpace($StatePath) -or [string]::IsNullOrWhiteSpace($ResultPath)){throw 'recover-mode-paths-required'}
    if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){throw 'recover-state-missing'}

    # Reuse the exact validated recovery executor harness so all of #153/#156/#157 and
    # their exact dependency contracts are loaded and independently replayed in this fresh process.
    . (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')
    . (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1')
    . (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1')

    $s=Get-CRIJson $StatePath
    $jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory)
    Assert-CRITrue ([bool]$jr.ok) ('fresh-process initial journal unreadable: '+[string]$jr.reason)
    Assert-CRIEq $jr.transaction_id $s.transaction_id 'fresh-process transaction id drift'
    Assert-CRIEq $jr.entry.phase 'atomic-mutation-starting' 'fresh-process did not observe unjournaled-first-rename crash phase'

    $inspectArgs=@{
        AllowedRoot=[string]$s.allowed_root;JournalStoreDirectory=[string]$s.store_directory;ExpectedTransactionId=[string]$s.transaction_id;Name=[string]$s.name
        ExpectedLiveFullTreeSha256=[string]$s.live_full_tree_sha256;ExpectedLiveFullFileCount=[int]$s.live_full_file_count;ExpectedLiveFullTotalBytes=[int64]$s.live_full_total_bytes
        ExpectedStageRuntimeTreeSha256=[string]$s.stage_tree_sha256;ExpectedAppBackupTreeSha256=[string]$s.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$s.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$s.app_backup_total_bytes
        ExpectedPersistenceFingerprint=[string]$s.persistence_fingerprint;LocalAppDataRoot=[string]$s.local_appdata_root;AppDataRoot=[string]$s.appdata_root
    }
    $inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @inspectArgs
    Assert-CRITrue ([bool]$inspection.ok) ('fresh-process atomic inspection denied: '+[string]$inspection.reason)
    Assert-CRIEq $inspection.receipt.state 'first-rename-complete-unjournaled' 'fresh-process crash state classification drift'

    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @inspectArgs -Now ([DateTimeOffset]::UtcNow)
    Assert-CRITrue ([bool]$repair.ok) ('fresh-process atomic repair denied: '+[string]$repair.reason)
    Assert-CRIEq $repair.phase 'live-moved-to-old' 'fresh-process repair phase drift'
    Assert-CRIEq $repair.transaction_id $s.transaction_id 'fresh-process repaired transaction id drift'

    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id)
    Assert-CRITrue ([bool]$ev.ok) ('fresh-process recovery evidence unreadable after repair: '+[string]$ev.reason)
    Assert-CRIEq $ev.evidence_fingerprint $s.evidence_fingerprint 'fresh-process recovery evidence fingerprint drift'

    # $fakeExe/$fakeSha are produced by the exact #157 harness above. They are SHA pinned,
    # accept only literal "apply", and record how many times recovery apply executes.
    Assert-CRITrue (Test-Path -LiteralPath $fakeExe -PathType Leaf) 'fresh-process fake spicetify executable missing'
    Assert-CRITrue ($fakeSha -match '^[0-9a-f]{64}$') 'fresh-process fake spicetify sha invalid'

    $at=[DateTimeOffset]::UtcNow
    $admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_appdata_root) -AppDataRoot ([string]$s.appdata_root) -SpicetifyAllowedRoot ([string]$s.allowed_root) -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $at
    Assert-CRITrue ([bool]$admission.ok) ('fresh-process restore-resume admission denied: '+[string]$admission.reason)
    Assert-CRIEq $admission.receipt.phase 'live-moved-to-old' 'fresh-process restore admission phase drift'
    Assert-CRIEq $admission.receipt.transaction_id $s.transaction_id 'fresh-process restore admission transaction drift'
    Assert-CRIEq $admission.receipt.evidence_fingerprint $s.evidence_fingerprint 'fresh-process restore admission evidence drift'
    Assert-CRITrue ([bool]$admission.receipt.restore_resume_eligible) 'fresh-process restore admission not eligible'
    Assert-CRITrue ([bool]$admission.receipt.requires_exact_restore) 'fresh-process restore admission lost exact restore requirement'
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-CRIFalse ([bool]$admission.receipt.$f) ('fresh-process admission authority escaped '+$f)}

    $control=Join-Path $env:RUNNER_TEMP ('crash-restart-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    $countPath=Join-Path $control 'count.txt';$appliedPath=Join-Path $control 'applied.txt'
    $env:SC_RX_COUNT=$countPath;$env:SC_RX_LIVE=Join-Path ([string]$s.live_path) 'index.js';$env:SC_RX_APPLIED=$appliedPath;$env:SC_RX_MODE='success'
    try{
        $exec=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_appdata_root) -AppDataRoot ([string]$s.appdata_root) -SpicetifyAllowedRoot ([string]$s.allowed_root) -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $at.AddSeconds(1) -TimeoutSeconds 30
    } finally {
        foreach($n in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
    }
    Assert-CRITrue ([bool]$exec.ok) ('fresh-process recovery restore executor denied: '+[string]$exec.reason)
    $execCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $exec.result
    Assert-CRITrue ([bool]$execCheck.ok) ('fresh-process recovery restore result invalid: '+[string]$execCheck.reason)
    Assert-CRIEq $exec.result.started_phase 'live-moved-to-old' 'fresh-process executor started phase drift'
    Assert-CRITrue ([bool]$exec.result.rollback_required_was_appended) 'fresh-process executor did not append rollback-required'
    Assert-CRITrue ([bool]$exec.result.restore_performed) 'fresh-process executor did not restore'
    Assert-CRITrue ([bool]$exec.result.recovery_apply_executed) 'fresh-process executor did not apply'
    Assert-CRITrue ([bool]$exec.result.rollback_complete_persisted) 'fresh-process executor did not persist rollback-complete'
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-CRIFalse ([bool]$exec.result.$f) ('fresh-process executor authority escaped '+$f)}

    $applyCount=if(Test-Path -LiteralPath $countPath -PathType Leaf){[int]([IO.File]::ReadAllText($countPath).Trim())}else{0}
    Assert-CRITrue ($applyCount -eq 1) "fresh-process recovery apply count drift $applyCount"
    Assert-CRITrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'fresh-process applied-state record missing'

    $finalJournal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory)
    Assert-CRITrue ([bool]$finalJournal.ok) ('fresh-process final journal unreadable: '+[string]$finalJournal.reason)
    Assert-CRIEq $finalJournal.entry.phase 'rollback-complete' 'fresh-process final journal phase drift'
    Assert-CRIEq $finalJournal.transaction_id $s.transaction_id 'fresh-process final transaction id drift'

    $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$s.live_path)
    Assert-CRIEq $app.tree_sha256 $s.app_backup_tree_sha256 'fresh-process restored app tree drift'
    Assert-CRITrue ([int]$app.file_count -eq [int]$s.app_backup_file_count) 'fresh-process restored app file count drift'
    Assert-CRITrue ([int64]$app.total_bytes -eq [int64]$s.app_backup_total_bytes) 'fresh-process restored app byte count drift'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$s.local_appdata_root) -AppDataRoot ([string]$s.appdata_root)
    Assert-CRIEq $persist.fingerprint $s.persistence_fingerprint 'fresh-process restored persistence fingerprint drift'
    $ev2=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id)
    Assert-CRITrue ([bool]$ev2.ok) ('fresh-process final recovery evidence unreadable: '+[string]$ev2.reason)
    Assert-CRIEq $ev2.evidence_fingerprint $s.evidence_fingerprint 'fresh-process final evidence fingerprint drift'

    foreach($p in @([string]$s.transaction_root,[string]$s.stage_workspace_path,[string]$s.app_backup_path,[string]$s.persistence_backup_path)){Assert-CRITrue (Test-Path -LiteralPath $p) ('fresh-process required recovery artifact missing '+$p)}

    $out=[pscustomobject]@{
        ok=$true;transaction_id=[string]$s.transaction_id;initial_phase='atomic-mutation-starting';normalized_phase='live-moved-to-old';final_phase='rollback-complete';inspection_state='first-rename-complete-unjournaled'
        evidence_fingerprint=[string]$s.evidence_fingerprint;admission_fingerprint=[string]$admission.receipt.admission_fingerprint;executor_result_fingerprint=[string]$exec.result.result_fingerprint
        restore_performed=[bool]$exec.result.restore_performed;recovery_apply_executed=[bool]$exec.result.recovery_apply_executed;apply_count=$applyCount;rollback_complete_persisted=[bool]$exec.result.rollback_complete_persisted
        app_tree_sha256=[string]$app.tree_sha256;persistence_fingerprint=[string]$persist.fingerprint;artifacts_retained=$true;fresh_process=$true;authority_escaped=$false
    }
    Write-CRIJson $ResultPath $out
    Write-Output 'CUSTOM_APP_PRODUCTION_CRASH_RESTART_RECOVER_PROCESS_PASS'
    exit 0
}

# Harness process: build a real #190 evidence-bound state, fail after the first live rename and
# before the durable live-moved-to-old append, then end all recovery work here and hand only
# durable filesystem/journal/evidence state to a new powershell.exe process.
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

$fixture=New-AtomicFixtureV010 'crash-restart-first-rename' -Nonce '56565656565656565656565656565656'
$r=Invoke-EBFixtureV010 -Fixture $fixture -Nonce 'abababababababababababababababab' -Label 'crash-restart-first-rename' -Fault 'after-live-move-before-journal'
Assert-CRIFalse ([bool]$r.ok) 'producer unexpectedly completed evidence-bound atomic mutation'
Assert-CRITrue ([bool]$r.live_move_started) 'producer did not perform first live rename'
Assert-CRITrue ([bool]$r.recovery_evidence_persisted) 'producer did not persist recovery evidence before atomic barrier'
Assert-CRIEq $r.journal_phase 'atomic-mutation-starting' 'producer failure phase drift'

$jr=Get-EBJournalV010 $fixture 'crash-restart-first-rename'
Assert-CRITrue ([bool]$jr.ok) ('producer journal unreadable: '+[string]$jr.reason)
Assert-CRIEq $jr.entry.phase 'atomic-mutation-starting' 'producer durable phase drift'
$ev=Get-EBEvidenceV010 $fixture 'crash-restart-first-rename' ([string]$jr.transaction_id)
Assert-CRITrue ([bool]$ev.ok) ('producer recovery evidence unreadable: '+[string]$ev.reason)
$ia=Get-EBInspectionArgsV010 $fixture 'crash-restart-first-rename'
$inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
Assert-CRITrue ([bool]$inspection.ok) ('producer exact crash inspection denied: '+[string]$inspection.reason)
Assert-CRIEq $inspection.receipt.state 'first-rename-complete-unjournaled' 'producer did not create exact first-rename crash state'

$p=$fixture.prepared.result
$state=[pscustomobject]@{
    allowed_root=(Get-EBTrustRootV010);store_directory=(Get-EBStoreV010 $fixture 'crash-restart-first-rename');transaction_id=[string]$jr.transaction_id;name=[string]$fixture.q.x.f.name
    live_path=[string]$fixture.q.x.live;transaction_root=[string]$r.transaction_root;stage_workspace_path=[string]$p.stage_workspace_path;stage_path=[string]$p.stage_path
    local_appdata_root=[string]$fixture.q.persistence.local;appdata_root=[string]$fixture.q.persistence.roaming
    live_full_tree_sha256=[string]$fixture.full_before.tree_sha256;live_full_file_count=[int]$fixture.full_before.file_count;live_full_total_bytes=[int64]$fixture.full_before.total_bytes
    stage_tree_sha256=[string]$p.stage_tree_sha256;app_backup_path=[string]$p.app_backup_path;app_backup_tree_sha256=[string]$p.app_backup_tree_sha256;app_backup_file_count=[int]$p.app_backup_file_count;app_backup_total_bytes=[int64]$p.app_backup_total_bytes
    persistence_backup_path=[string]$p.persistence_backup_path;persistence_fingerprint=[string]$p.persistence_fingerprint;evidence_fingerprint=[string]$ev.evidence_fingerprint
}
$handoff=Join-Path $env:RUNNER_TEMP ('crash-restart-handoff-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($handoff)|Out-Null
$statePath=Join-Path $handoff 'state.json';$resultPath=Join-Path $handoff 'result.json'
Write-CRIJson $statePath $state

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode Recover -StatePath $statePath -ResultPath $resultPath
if($LASTEXITCODE -ne 0){throw "fresh recovery process failed exit=$LASTEXITCODE"}
Assert-CRITrue (Test-Path -LiteralPath $resultPath -PathType Leaf) 'fresh recovery process did not write result'
$out=Get-CRIJson $resultPath
Assert-CRITrue ([bool]$out.ok) 'fresh recovery process result not ok'
Assert-CRITrue ([bool]$out.fresh_process) 'fresh recovery process marker false'
Assert-CRIFalse ([bool]$out.authority_escaped) 'fresh recovery process authority escaped'
Assert-CRIEq $out.transaction_id $jr.transaction_id 'fresh recovery result transaction drift'
Assert-CRIEq $out.initial_phase 'atomic-mutation-starting' 'fresh recovery result initial phase drift'
Assert-CRIEq $out.normalized_phase 'live-moved-to-old' 'fresh recovery result normalized phase drift'
Assert-CRIEq $out.final_phase 'rollback-complete' 'fresh recovery result final phase drift'
Assert-CRIEq $out.inspection_state 'first-rename-complete-unjournaled' 'fresh recovery result inspection state drift'
Assert-CRIEq $out.evidence_fingerprint $ev.evidence_fingerprint 'fresh recovery result evidence drift'
Assert-CRITrue ([bool]$out.restore_performed) 'fresh recovery result restore flag false'
Assert-CRITrue ([bool]$out.recovery_apply_executed) 'fresh recovery result apply flag false'
Assert-CRITrue ([int]$out.apply_count -eq 1) 'fresh recovery result apply count not one'
Assert-CRITrue ([bool]$out.rollback_complete_persisted) 'fresh recovery result rollback-complete flag false'
Assert-CRIEq $out.app_tree_sha256 $p.app_backup_tree_sha256 'fresh recovery result app tree drift'
Assert-CRIEq $out.persistence_fingerprint $p.persistence_fingerprint 'fresh recovery result persistence drift'
Assert-CRITrue ([bool]$out.artifacts_retained) 'fresh recovery result artifact-retention flag false'

$final=Get-EBJournalV010 $fixture 'crash-restart-first-rename'
Assert-CRITrue ([bool]$final.ok) ('harness final journal unreadable: '+[string]$final.reason)
Assert-CRIEq $final.entry.phase 'rollback-complete' 'harness final durable phase drift'
$finalEvidence=Get-EBEvidenceV010 $fixture 'crash-restart-first-rename' ([string]$jr.transaction_id)
Assert-CRITrue ([bool]$finalEvidence.ok) ('harness final recovery evidence unreadable: '+[string]$finalEvidence.reason)
Assert-CRIEq $finalEvidence.evidence_fingerprint $ev.evidence_fingerprint 'harness final evidence drift'
$app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$fixture.q.x.live)
Assert-CRIEq $app.tree_sha256 $p.app_backup_tree_sha256 'harness final restored app tree drift'
$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$fixture.q.persistence.local) -AppDataRoot ([string]$fixture.q.persistence.roaming)
Assert-CRIEq $persist.fingerprint $p.persistence_fingerprint 'harness final restored persistence drift'
foreach($path in @([string]$r.transaction_root,[string]$p.stage_workspace_path,[string]$p.app_backup_path,[string]$p.persistence_backup_path)){Assert-CRITrue (Test-Path -LiteralPath $path) ('harness expected retained artifact missing '+$path)}

Write-Output 'CUSTOM_APP_PRODUCTION_CRASH_RESTART_RESTORE_INTEGRATION_PASS cases=1 fresh_processes=1 apply_count=1 final_phase=rollback-complete'
