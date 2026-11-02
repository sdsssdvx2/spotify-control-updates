$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Load the exact validated recovery-aware pre-apply fixture graph, then the exact
# journal/evidence-bound atomic cores. The parent harness also replays its own matrix.
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1')
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/custom-app-production-atomic-live-swap-mutation.ps1')
. (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1')
. (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1')
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/custom-app-production-evidence-bound-journal-atomic.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-evidence-bound-journal-atomic.ps1')

function Assert-RAEBTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAEBFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAEBEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$script:RAEBFault='none'
function Invoke-CustomAppProductionEvidenceBoundJournalAtomicValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:RAEBFault -ceq $Checkpoint){throw ('recovery-aware-evidence-bound-fixture-crash:'+$Checkpoint)}
}
function Get-RAEBCurrentStoreV010 {param($X,[string]$Label);return (Join-Path ([string]$X.q.f.ce.q.f.f.allowed) ('recovery-aware-current-journal-'+$Label))}
function Get-RAEBGenericPreparedV010 {param($Prepared);return (ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $Prepared.result)}
function Invoke-RAEBBridgeV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)]$Prepared,[Parameter(Mandatory=$true)][string]$CurrentStore,[Parameter(Mandatory=$true)][string]$Nonce,[string]$Fault='none')
    $ctx=New-RAIssueLiveContextV010 -Bundle $X.bundle;$priorOverride=$script:RAPPFreshLiveOverride;$priorFault=$script:RAEBFault
    $script:RAPPFreshLiveOverride=[pscustomobject]@{stable_tree_sha256=[string]$X.stable_tree;actual_tree_sha256=[string]$X.actual_live_tree;live_path=[string]$X.live_path;manifest_name=[string]$X.manifest_name};$script:RAEBFault=$Fault
    $when=[DateTimeOffset]::Parse([string]$Prepared.result.post_backup_revalidated_at).AddSeconds(1)
    try {
        return Invoke-CustomAppProductionRecoveryAwareEvidenceBoundJournalAtomicV010 -RecoveryAwareStageExecutorResult $X.stage -RecoveryAwarePreparedResult $Prepared.result -Name ([string]$X.bundle.lifecycle.name) -LifecycleRow $X.bundle.lifecycle -ProvenanceRow $X.bundle.provenance -BindingRow $X.bundle.binding -LifecycleStageResult $X.bundle.stage -ShadowResult $X.bundle.shadow -RetirementResumeResult $X.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot ([string]$X.q.f.ce.q.f.f.allowed) -PriorRecoveryStoreDirectory ([string]$X.q.f.ce.q.f.f.store) -ConsumptionStoreDirectory ([string]$X.f.p.store) -CurrentJournalStoreDirectory $CurrentStore -ExpectedPermitLineageTransactionId ([string]$X.q.f.ce.q.f.f.identity.transaction_id) -TransactionNonce $Nonce -LocalAppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.local) -AppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.roaming) -ConsumptionPersistenceResult $X.f.persisted -Permit $X.f.p.f.p.r.issuer.permit -SessionKey $script:RAIssuerKey -Now $when
    } finally {$script:RAPPFreshLiveOverride=$priorOverride;$script:RAEBFault=$priorFault}
}
function Get-RAEBJournalV010 {param($X,[string]$Store);return (Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$X.q.f.ce.q.f.f.allowed) -StoreDirectory $Store)}
function Get-RAEBEvidenceV010 {param($X,[string]$Store,[string]$TransactionId);return (Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$X.q.f.ce.q.f.f.allowed) -StoreDirectory $Store -ExpectedTransactionId $TransactionId)}
function Get-RAEBInspectionArgsV010 {
    param($X,$Prepared,[string]$Store,[string]$TransactionId)
    $g=Get-RAEBGenericPreparedV010 $Prepared
    return @{AllowedRoot=[string]$X.q.f.ce.q.f.f.allowed;JournalStoreDirectory=$Store;ExpectedTransactionId=$TransactionId;Name=[string]$X.bundle.lifecycle.name;ExpectedLiveFullTreeSha256=[string]$g.app_backup_tree_sha256;ExpectedLiveFullFileCount=[int]$g.app_backup_file_count;ExpectedLiveFullTotalBytes=[int64]$g.app_backup_total_bytes;ExpectedStageRuntimeTreeSha256=[string]$g.stage_tree_sha256;ExpectedAppBackupTreeSha256=[string]$g.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$g.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$g.app_backup_total_bytes;ExpectedPersistenceFingerprint=[string]$g.persistence_fingerprint;LocalAppDataRoot=[string]$X.q.f.ce.q.f.f.q.persistence.local;AppDataRoot=[string]$X.q.f.ce.q.f.f.q.persistence.roaming}
}
function Restore-RAEBFixtureV010 {param($X,$Prepared,[AllowNull()][string]$TransactionRoot)
    $rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$X.live_path) -AppBackupPath ([string]$Prepared.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$Prepared.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$Prepared.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$Prepared.result.persistence_fingerprint) -LocalAppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.local) -AppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.roaming)
    Assert-RAEBTrue ([bool]$rb.ok) ('fixture cleanup restore failed: '+[string]$rb.reason)
    if(-not [string]::IsNullOrWhiteSpace($TransactionRoot) -and (Test-Path -LiteralPath $TransactionRoot)){$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$X.live_path));Remove-CustomAppAtomicDirectoryV010 -Path $TransactionRoot -ExpectedParent $parent -ExpectedName ([IO.Path]::GetFileName($TransactionRoot))}
}

$worker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restore-integration-v0.1.0/recovery_worker.ps1'
if(-not(Test-Path -LiteralPath $worker -PathType Leaf)){throw 'recovery worker missing'}
$fakeRoot=Join-Path ([IO.Path]::GetFullPath($env:RUNNER_TEMP)) ('raeb-fake-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class RecoveryAwareEvidenceBoundFakeSpicetify {
    static string E(string n){return Environment.GetEnvironmentVariable(n)??"";}
    public static int Main(string[] args){if(args==null||args.Length!=1||args[0]!="apply")return 64;string c=E("SC_EBRI_COUNT"),l=E("SC_EBRI_LIVE"),a=E("SC_EBRI_APPLIED");if(String.IsNullOrEmpty(c)||String.IsNullOrEmpty(l)||String.IsNullOrEmpty(a))return 65;int n=0;if(File.Exists(c))Int32.TryParse(File.ReadAllText(c).Trim(),out n);File.WriteAllText(c,(n+1).ToString());File.WriteAllText(a,File.Exists(l)?File.ReadAllText(l):"");return 0;}
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
function Clear-RAEBEnvV010 {foreach($n in @('SC_EBRI_COUNT','SC_EBRI_LIVE','SC_EBRI_APPLIED')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}}
function Invoke-RAEBSeparateRecoveryV010 {
    param($X,$Prepared,[string]$Store,[string]$JournalTransactionId,[string]$EvidenceFingerprint,[string]$Label)
    $control=Join-Path ([IO.Path]::GetFullPath($env:RUNNER_TEMP)) ('raeb-control-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($control)|Out-Null
    $statePath=Join-Path $control 'state.json';$resultPath=Join-Path $control 'result.json';$countPath=Join-Path $control 'count.txt';$appliedPath=Join-Path $control 'applied.txt';$g=Get-RAEBGenericPreparedV010 $Prepared
    $state=[pscustomobject]@{allowed_root=[string]$X.q.f.ce.q.f.f.allowed;store_directory=$Store;transaction_id=$JournalTransactionId;evidence_fingerprint=$EvidenceFingerprint;preparation_fingerprint=[string]$g.preparation_fingerprint;local_appdata_root=[string]$X.q.f.ce.q.f.f.q.persistence.local;appdata_root=[string]$X.q.f.ce.q.f.f.q.persistence.roaming;spicetify_allowed_root=[IO.Path]::GetFullPath($env:RUNNER_TEMP);spicetify_path=$fakeExe;spicetify_sha256=$fakeSha;worker_result_path=$resultPath}
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false));$env:SC_EBRI_COUNT=$countPath;$env:SC_EBRI_LIVE=Join-Path ([string]$X.live_path) 'index.js';$env:SC_EBRI_APPLIED=$appliedPath
    try{& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath;if($LASTEXITCODE){throw "$Label worker exit $LASTEXITCODE"}}finally{Clear-RAEBEnvV010}
    $wr=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json;Assert-RAEBTrue ([bool]$wr.ok) "$Label worker not ok";Assert-RAEBTrue ([int]$wr.worker_pid -ne $PID) "$Label worker was not separate process";Assert-RAEBEq ([string]$wr.initial_phase) 'candidate-live' "$Label initial phase";Assert-RAEBEq ([string]$wr.transaction_id) $JournalTransactionId "$Label journal transaction continuity";Assert-RAEBEq ([string]$wr.evidence_fingerprint) $EvidenceFingerprint "$Label evidence continuity";Assert-RAEBTrue ([bool]$wr.restore_performed -and [bool]$wr.recovery_apply_executed -and [bool]$wr.rollback_complete_persisted) "$Label recovery contract incomplete";Assert-RAEBEq ([string]$wr.final_phase) 'rollback-complete' "$Label final phase"
    $count=$(if(Test-Path -LiteralPath $countPath){[int]([IO.File]::ReadAllText($countPath).Trim())}else{0});Assert-RAEBTrue ($count -eq 1) "$Label apply count $count"
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$X.live_path);Assert-RAEBEq ([string]$full.tree_sha256) ([string]$Prepared.result.app_backup_tree_sha256) "$Label restored full tree";$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.local) -AppDataRoot ([string]$X.q.f.ce.q.f.f.q.persistence.roaming);Assert-RAEBEq ([string]$persist.fingerprint) ([string]$Prepared.result.persistence_fingerprint) "$Label restored persistence"
    return $wr
}

$count=0
$valid=New-RAPPFixtureV010 -Label 'raeb-dual-id-success' -Nonce ('6'*32)
try {
    $prep=Invoke-RAPPFixtureV010 -X $valid;Assert-RAEBTrue ([bool]$prep.ok) ('success pre-apply denied: '+[string]$prep.reason);$store=Get-RAEBCurrentStoreV010 $valid 'success'
    $r=Invoke-RAEBBridgeV010 -X $valid -Prepared $prep -CurrentStore $store -Nonce '61616161616161616161616161616161';Assert-RAEBTrue ([bool]$r.ok) ('bridge success denied: '+[string]$r.reason)
    $rc=Test-CustomAppProductionRecoveryAwareEvidenceBoundJournalAtomicResultV010 -Result $r.result;Assert-RAEBTrue ([bool]$rc.ok) ('bridge result invalid: '+[string]$rc.reason)
    $permitTx=([string]$valid.q.f.ce.q.f.f.identity.transaction_id).Trim().ToLowerInvariant();Assert-RAEBEq ([string]$r.result.permit_lineage_transaction_id) $permitTx 'permit lineage transaction drift';Assert-RAEBFalse (([string]$r.result.journal_transaction_id) -ceq $permitTx) 'fixture unexpectedly collapsed permit lineage and journal transaction ids'
    $jr=Get-RAEBJournalV010 $valid $store;Assert-RAEBEq ([string]$jr.entry.phase) 'candidate-live' 'success journal phase';Assert-RAEBEq ([string]$jr.transaction_id) ([string]$r.result.journal_transaction_id) 'success journal transaction drift';$ev=Get-RAEBEvidenceV010 $valid $store ([string]$jr.transaction_id);Assert-RAEBTrue ([bool]$ev.ok) ('success evidence unreadable: '+[string]$ev.reason)
    [void](Invoke-RAEBSeparateRecoveryV010 -X $valid -Prepared $prep -Store $store -JournalTransactionId ([string]$jr.transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -Label 'dual-id candidate-live restart');$count++
} finally {Remove-RAPPFixtureV010 $valid}

$crash=New-RAPPFixtureV010 -Label 'raeb-first-rename-crash' -Nonce ('7'*32)
try {
    $prep=Invoke-RAPPFixtureV010 -X $crash;Assert-RAEBTrue ([bool]$prep.ok) ('crash pre-apply denied: '+[string]$prep.reason);$store=Get-RAEBCurrentStoreV010 $crash 'first-rename'
    $r=Invoke-RAEBBridgeV010 -X $crash -Prepared $prep -CurrentStore $store -Nonce '71717171717171717171717171717171' -Fault 'after-live-move-before-journal';Assert-RAEBFalse ([bool]$r.ok) 'first-rename crash unexpectedly succeeded';Assert-RAEBTrue ([bool]$r.requires_recovery -and [bool]$r.recovery_evidence_persisted) ('first-rename crash did not require durable recovery: '+[string]$r.reason)
    $jr=Get-RAEBJournalV010 $crash $store;$permitTx=([string]$crash.q.f.ce.q.f.f.identity.transaction_id).Trim().ToLowerInvariant();Assert-RAEBFalse (([string]$jr.transaction_id) -ceq $permitTx) 'first-rename fixture collapsed dual transaction ids';$ia=Get-RAEBInspectionArgsV010 -X $crash -Prepared $prep -Store $store -TransactionId ([string]$jr.transaction_id);$inspect=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-RAEBTrue ([bool]$inspect.ok) ('first-rename inspection denied: '+[string]$inspect.reason);Assert-RAEBEq ([string]$inspect.receipt.state) 'first-rename-complete-unjournaled' 'first-rename exact state';$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));Assert-RAEBTrue ([bool]$repair.ok) ('first-rename repair denied: '+[string]$repair.reason);Assert-RAEBEq ([string]$repair.phase) 'live-moved-to-old' 'first-rename repaired phase';$ev=Get-RAEBEvidenceV010 $crash $store ([string]$repair.transaction_id);Assert-RAEBTrue ([bool]$ev.ok) ('first-rename evidence unreadable: '+[string]$ev.reason);$count++
} finally {try{$jr=Get-RAEBJournalV010 $crash (Get-RAEBCurrentStoreV010 $crash 'first-rename');$txn=$(if($null-ne$jr-and[bool]$jr.ok){[string]$jr.entry.transaction_root}else{$null});Restore-RAEBFixtureV010 -X $crash -Prepared $prep -TransactionRoot $txn}catch{};Remove-RAPPFixtureV010 $crash}

$same=New-RAPPFixtureV010 -Label 'raeb-store-separation' -Nonce ('8'*32)
try {
    $prep=Invoke-RAPPFixtureV010 -X $same;Assert-RAEBTrue ([bool]$prep.ok) ('same-store pre-apply denied: '+[string]$prep.reason);$prior=[string]$same.q.f.ce.q.f.f.store;$before=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$same.q.f.ce.q.f.f.allowed) -StoreDirectory $prior
    $r=Invoke-RAEBBridgeV010 -X $same -Prepared $prep -CurrentStore $prior -Nonce '81818181818181818181818181818181';Assert-RAEBFalse ([bool]$r.ok) 'same prior/current store accepted';Assert-RAEBEq ([string]$r.reason) 'recovery-aware-evidence-bound-prior-recovery-store-must-differ-from-current-journal-store' 'same-store denial reason';$after=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$same.q.f.ce.q.f.f.allowed) -StoreDirectory $prior;Assert-RAEBEq ([string]$after.entry.entry_sha256) ([string]$before.entry.entry_sha256) 'same-store denial mutated prior journal';Assert-RAEBTrue ([int64]$after.revision -eq [int64]$before.revision) 'same-store denial changed prior journal revision';$count++
} finally {Remove-RAPPFixtureV010 $same}

if($count -ne 3){throw "recovery-aware evidence-bound journal atomic matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_EVIDENCE_BOUND_JOURNAL_ATOMIC_PASS cases=$count dual_id=true separate_process_recovery=true prior_current_store_separation=true"