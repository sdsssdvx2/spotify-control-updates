$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse the exact #190 byte-real generic prepared/atomic fixture. This does replay the
# compact five-case #190 matrix, but deliberately avoids the much deeper #180 permit
# harness whose nested matrices can age recovery evidence before this integration starts.
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')
. (Join-Path $root 'validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/custom-app-production-dual-transaction-id-bridge.ps1')
. (Join-Path $root 'validation/custom-app-production-durable-dual-transaction-id-bridge-integration-v0.1.0/custom-app-production-durable-dual-transaction-id-bridge-integration.ps1')

function Assert-LDTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-LDFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-LDEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

# This carrier is intentionally NOT a replacement qualification for #180. It only
# projects an already byte-real, self-validating generic prepared result into the exact
# fields the durable dual-ID bridge consumes, so this test can isolate ID namespace,
# precommit ordering, real #190 mutation, and restart recovery without replaying all
# upstream permit matrices. The validators below fail closed to this explicit carrier.
function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result -or -not $Result.PSObject.Properties['lightweight_dual_id_carrier'] -or -not[bool]$Result.lightweight_dual_id_carrier){return [pscustomobject]@{ok=$false;reason='lightweight-dual-id-carrier-required'}}
    if(-not $Result.PSObject.Properties['generic_prepared'] -or $null-eq$Result.generic_prepared){return [pscustomobject]@{ok=$false;reason='lightweight-dual-id-generic-prepared-missing'}}
    $gc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $Result.generic_prepared
    if($null-eq$gc -or -not[bool]$gc.ok){return [pscustomobject]@{ok=$false;reason=('lightweight-dual-id-generic-prepared-invalid:'+[string]$gc.reason)}}
    foreach($p in @(
        @('name',[string]$Result.name,[string]$Result.generic_prepared.name),
        @('source_identity',[string]$Result.source_identity,[string]$Result.generic_prepared.source_identity),
        @('remote_commit_sha',[string]$Result.remote_commit_sha,[string]$Result.generic_prepared.remote_commit_sha),
        @('consumption_id',[string]$Result.consumption_id,[string]$Result.generic_prepared.consumption_id),
        @('generic_stage_result_fingerprint',[string]$Result.generic_stage_result_fingerprint,[string]$Result.generic_prepared.stage_result_fingerprint),
        @('generic_preparation_fingerprint',[string]$Result.generic_preparation_fingerprint,[string]$Result.generic_prepared.preparation_fingerprint),
        @('live_tree_sha256',[string]$Result.live_tree_sha256,[string]$Result.generic_prepared.live_tree_sha256),
        @('stage_tree_sha256',[string]$Result.stage_tree_sha256,[string]$Result.generic_prepared.stage_tree_sha256),
        @('app_backup_tree_sha256',[string]$Result.app_backup_tree_sha256,[string]$Result.generic_prepared.app_backup_tree_sha256),
        @('persistence_fingerprint',[string]$Result.persistence_fingerprint,[string]$Result.generic_prepared.persistence_fingerprint)
    )){if(([string]$p[1]).Trim().ToLowerInvariant()-cne([string]$p[2]).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('lightweight-dual-id-carrier-drift-'+[string]$p[0])}}}
    if(([string]$Result.transaction_id).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{64}$' -or ([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{64}$'){return [pscustomobject]@{ok=$false;reason='lightweight-dual-id-carrier-id-invalid'}}
    return [pscustomobject]@{ok=$true;reason='lightweight-dual-id-carrier-valid-for-isolated-bridge-validation'}
}
function Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result -or -not $Result.PSObject.Properties['lightweight_dual_id_stage'] -or -not[bool]$Result.lightweight_dual_id_stage){return [pscustomobject]@{ok=$false;reason='lightweight-dual-id-stage-required'}}
    if(([string]$Result.transaction_id).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{64}$' -or ([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{64}$'){return [pscustomobject]@{ok=$false;reason='lightweight-dual-id-stage-invalid'}}
    return [pscustomobject]@{ok=$true;reason='lightweight-dual-id-stage-valid-for-isolated-bridge-validation'}
}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {
    param([AllowNull()]$Result)
    $c=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $Result
    if(-not[bool]$c.ok){throw ('lightweight-dual-id-conversion-denied:'+[string]$c.reason)}
    return $Result.generic_prepared
}

$script:LDDurableFault='none'
function Invoke-CustomAppProductionDurableDualTransactionIdBridgeIntegrationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:LDDurableFault-ceq$Checkpoint){throw ('lightweight-dual-id-fixture-crash:'+$Checkpoint)}
}

function New-LDCarrierV010 {
    param([Parameter(Mandatory=$true)]$Generic,[Parameter(Mandatory=$true)][string]$PermitId,[Parameter(Mandatory=$true)][string]$StageFingerprint)
    $preparedAt=[DateTimeOffset]::Parse([string]$Generic.prepared_at)
    $material=([string]$PermitId+'|'+[string]$Generic.preparation_fingerprint+'|'+[string]$StageFingerprint)
    $fp=Get-CustomAppProductionDurableDualTransactionIdBridgeIntegrationSha256V010 $material
    return [pscustomobject]@{
        lightweight_dual_id_carrier=$true;generic_prepared=$Generic
        name=[string]$Generic.name;source_identity=[string]$Generic.source_identity;github_repo_id=[int64]$Generic.github_repo_id;surface_kind=[string]$Generic.surface_kind;remote_commit_sha=[string]$Generic.remote_commit_sha;binding_fingerprint=[string]$Generic.binding_fingerprint;consumption_id=[string]$Generic.consumption_id
        transaction_id=$PermitId;recovery_stage_result_fingerprint=$StageFingerprint;generic_stage_result_fingerprint=[string]$Generic.stage_result_fingerprint;generic_preparation_fingerprint=[string]$Generic.preparation_fingerprint
        live_tree_sha256=[string]$Generic.live_tree_sha256;stage_tree_sha256=[string]$Generic.stage_tree_sha256;stage_workspace_path=[string]$Generic.stage_workspace_path;stage_path=[string]$Generic.stage_path
        app_backup_path=[string]$Generic.app_backup_path;app_backup_tree_sha256=[string]$Generic.app_backup_tree_sha256;app_backup_file_count=[int]$Generic.app_backup_file_count;app_backup_total_bytes=[int64]$Generic.app_backup_total_bytes
        persistence_backup_path=[string]$Generic.persistence_backup_path;persistence_fingerprint=[string]$Generic.persistence_fingerprint
        prepared_at=$preparedAt.ToString('o');post_backup_revalidated_at=$preparedAt.AddSeconds(1).ToString('o');result_fingerprint=$fp
    }
}
function New-LDStageV010 {
    param([Parameter(Mandatory=$true)][string]$PermitId,[Parameter(Mandatory=$true)][string]$StageFingerprint)
    return [pscustomobject]@{lightweight_dual_id_stage=$true;transaction_id=$PermitId;result_fingerprint=$StageFingerprint}
}
function New-LDFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$FixtureNonce,[Parameter(Mandatory=$true)][string]$PermitSeed)
    $f=New-AtomicFixtureV010 ('lightweight-dual-id-'+$Label) -Nonce $FixtureNonce
    $g=$f.prepared.result
    $permit=Get-CustomAppProductionDurableDualTransactionIdBridgeIntegrationSha256V010 ('permit|'+$PermitSeed+'|'+[string]$g.preparation_fingerprint)
    $stageFp=Get-CustomAppProductionDurableDualTransactionIdBridgeIntegrationSha256V010 ('stage|'+$PermitSeed+'|'+[string]$g.stage_result_fingerprint)
    return [pscustomobject]@{fixture=$f;generic=$g;permit_id=$permit;stage_fingerprint=$stageFp;carrier=(New-LDCarrierV010 -Generic $g -PermitId $permit -StageFingerprint $stageFp);stage=(New-LDStageV010 -PermitId $permit -StageFingerprint $stageFp)}
}
function Invoke-LDIntegrationV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$TransactionNonce)
    $f=$X.fixture
    return Invoke-CustomAppProductionDurableDualTransactionIdBridgeIntegrationV010 -RecoveryAwarePreparedResult $X.carrier -RecoveryAwareStageExecutorResult $X.stage -Name ([string]$f.q.x.f.name) -AllowedRoot (Get-EBTrustRootV010) -JournalStoreDirectory (Get-EBStoreV010 $f $Label) -TransactionNonce $TransactionNonce -LivePath ([string]$f.q.x.live) -ExpectedLiveFullTreeSha256 ([string]$f.full_before.tree_sha256) -ExpectedLiveFullFileCount ([int]$f.full_before.file_count) -ExpectedLiveFullTotalBytes ([int64]$f.full_before.total_bytes) -LocalAppDataRoot ([string]$f.q.persistence.local) -AppDataRoot ([string]$f.q.persistence.roaming) -Now ([DateTimeOffset]::UtcNow)
}
function Assert-LDOldStateV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)][string]$Label)
    $f=$X.fixture
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$f.q.x.live)
    Assert-LDEq ([string]$full.tree_sha256) ([string]$f.full_before.tree_sha256) "$Label full live tree"
    Assert-LDTrue ([int]$full.file_count -eq [int]$f.full_before.file_count) "$Label full live count"
    Assert-LDTrue ([int64]$full.total_bytes -eq [int64]$f.full_before.total_bytes) "$Label full live bytes"
    $p=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$f.q.persistence.local) -AppDataRoot ([string]$f.q.persistence.roaming)
    Assert-LDEq ([string]$p.fingerprint) ([string]$f.persistence_before.fingerprint) "$Label persistence"
}

$allowed=Get-EBTrustRootV010
$fakeRoot=Join-Path $allowed ('spotify-control-lightweight-dual-id-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
public static class LightweightDualIdFakeSpicetify {
  static string E(string n){ return Environment.GetEnvironmentVariable(n) ?? ""; }
  static int Next(string p){ int n=0; if(File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(),out n); n++; File.WriteAllText(p,n.ToString()); return n; }
  public static int Main(string[] args){ if(args==null||args.Length!=1||args[0]!="apply") return 64; string c=E("SC_RX_COUNT"),l=E("SC_RX_LIVE"),a=E("SC_RX_APPLIED"); if(String.IsNullOrEmpty(c)||String.IsNullOrEmpty(l)||String.IsNullOrEmpty(a)) return 65; Next(c); File.WriteAllText(a,File.Exists(l)?File.ReadAllText(l):""); return 0; }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
$worker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
Assert-LDTrue (Test-Path -LiteralPath $worker -PathType Leaf) 'restart worker missing'

function Invoke-LDRestartV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$JournalId,[Parameter(Mandatory=$true)][string]$EvidenceFingerprint,[Parameter(Mandatory=$true)][string]$Phase)
    $f=$X.fixture;$control=Join-Path $allowed ('lightweight-dual-id-restart-'+$Label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($control)|Out-Null
    $statePath=Join-Path $control 'state.json';$resultPath=Join-Path $control 'result.json';$countPath=Join-Path $control 'apply-count.txt';$appliedPath=Join-Path $control 'applied.txt'
    $state=[ordered]@{schema=1;allowed_root=$allowed;store_directory=(Get-EBStoreV010 $f $Label);transaction_id=$JournalId;evidence_fingerprint=$EvidenceFingerprint;expected_start_phase=$Phase;local_app_data_root=[string]$f.q.persistence.local;app_data_root=[string]$f.q.persistence.roaming;spicetify_allowed_root=$allowed;spicetify_path=$fakeExe;spicetify_sha256=$fakeSha;apply_count_path=$countPath;applied_probe_path=$appliedPath;live_probe_path=(Join-Path ([string]$f.q.x.live) 'index.js');parent_process_id=$PID}
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    $child=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath -ResultPath $resultPath 2>&1;$exit=$LASTEXITCODE
    foreach($line in @($child)){Write-Host $line}
    Assert-LDTrue (Test-Path -LiteralPath $resultPath -PathType Leaf) "$Label restart result missing"
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
    if($exit-ne0){Write-Host ('LD_RESTART_DIAGNOSTIC '+($result|ConvertTo-Json -Depth 20 -Compress));throw "$Label restart worker failed exit=$exit error=$([string]$result.error)"}
    Assert-LDTrue ([bool]$result.success) "$Label restart success false"
    Assert-LDTrue ([int]$result.process_id-ne$PID) "$Label did not use a distinct process"
    Assert-LDEq ([string]$result.transaction_id) $JournalId "$Label journal transaction id"
    Assert-LDEq ([string]$result.admission_phase) $Phase "$Label admission phase"
    Assert-LDEq ([string]$result.final_phase) 'rollback-complete' "$Label final phase"
    Assert-LDTrue ([int]$result.apply_count-eq1) "$Label recovery apply count"
    Assert-LDEq ([string]$result.evidence_fingerprint_after) $EvidenceFingerprint "$Label evidence fingerprint"
    Assert-LDOldStateV010 -X $X -Label $Label
    return $result
}

$count=0

# Case 1: exact durable precommit -> real #190 candidate-live -> canonical bridge receipt ->
# separate-process #156/#157 rollback. Both ID namespaces and both bridge files survive.
$x=New-LDFixtureV010 -Label 'success' -FixtureNonce '61616161616161616161616161616161' -PermitSeed 'success'
$label='ld-success';$nonce='71717171717171717171717171717171';$r=Invoke-LDIntegrationV010 -X $x -Label $label -TransactionNonce $nonce;$txn=$null
try{
    Assert-LDTrue ([bool]$r.ok) ('success integration denied: '+[string]$r.reason);$txn=[string]$r.atomic.result.transaction_root
    $rc=Test-CustomAppProductionDurableDualTransactionIdBridgeIntegrationResultV010 -Result $r.result;Assert-LDTrue ([bool]$rc.ok) ('success result invalid: '+[string]$rc.reason)
    Assert-LDFalse (([string]$r.result.permit_transaction_id)-ceq([string]$r.result.journal_transaction_id)) 'success transaction namespaces conflated'
    Assert-LDEq ([string]$r.result.permit_transaction_id) ([string]$x.permit_id) 'success permit id'
    $pre=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDTrue ([bool]$pre.ok) ('success precommit unreadable: '+[string]$pre.reason)
    $final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDTrue ([bool]$final.ok) ('success final receipt unreadable: '+[string]$final.reason)
    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $allowed -StoreDirectory (Get-EBStoreV010 $x.fixture $label) -ExpectedTransactionId ([string]$r.result.journal_transaction_id);Assert-LDTrue ([bool]$ev.ok) ('success evidence unreadable: '+[string]$ev.reason)
    [void](Invoke-LDRestartV010 -X $x -Label $label -JournalId ([string]$r.result.journal_transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -Phase 'candidate-live')
    $pre2=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDTrue ([bool]$pre2.ok) 'success precommit did not survive rollback-complete';Assert-LDEq ([string]$pre2.precommit_fingerprint) ([string]$pre.precommit_fingerprint) 'success precommit fingerprint drift'
    $final2=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDTrue ([bool]$final2.ok) 'success final receipt did not survive rollback-complete';Assert-LDEq ([string]$final2.bridge_fingerprint) ([string]$final.bridge_fingerprint) 'success final receipt drift';$count++
}finally{Restore-EBFixtureV010 $x.fixture $txn}

# Case 2: crash immediately after durable precommit but before journal initialization.
# Exact retry must replay the same CreateNew binding, then complete and remain recoverable.
$x=New-LDFixtureV010 -Label 'precommit-replay' -FixtureNonce '62626262626262626262626262626262' -PermitSeed 'precommit-replay'
$label='ld-precommit-replay';$nonce='72727272727272727272727272727272';$script:LDDurableFault='after-precommit-before-journal-init';try{$first=Invoke-LDIntegrationV010 -X $x -Label $label -TransactionNonce $nonce}finally{$script:LDDurableFault='none'}
Assert-LDFalse ([bool]$first.ok) 'precommit crash unexpectedly succeeded';Assert-LDTrue ([bool]$first.precommit_persisted) 'precommit crash did not persist binding';Assert-LDFalse (Test-Path -LiteralPath ([string]$first.precommit.transaction_root)) 'precommit crash created transaction workspace'
$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDFalse ([bool]$jr.ok) 'precommit crash initialized journal';Assert-LDEq ([string]$jr.reason) 'journal-uninitialized' 'precommit crash journal reason'
$r=Invoke-LDIntegrationV010 -X $x -Label $label -TransactionNonce $nonce;$txn=$null
try{
    Assert-LDTrue ([bool]$r.ok) ('precommit exact replay denied: '+[string]$r.reason);$txn=[string]$r.atomic.result.transaction_root
    Assert-LDEq ([string]$r.precommit.precommit_fingerprint) ([string]$first.precommit.precommit_fingerprint) 'precommit replay fingerprint drift'
    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $allowed -StoreDirectory (Get-EBStoreV010 $x.fixture $label) -ExpectedTransactionId ([string]$r.result.journal_transaction_id);Assert-LDTrue ([bool]$ev.ok) ('precommit replay evidence unreadable: '+[string]$ev.reason)
    [void](Invoke-LDRestartV010 -X $x -Label $label -JournalId ([string]$r.result.journal_transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -Phase 'candidate-live');$count++
}finally{Restore-EBFixtureV010 $x.fixture $txn}

# Case 3: live -> old-live happened but its journal phase did not. The precommit already
# durably binds permit ID to the predicted journal ID. #189 normalizes the crash window,
# then a new process recovers by journal ID. A canonical final bridge receipt must NOT
# be fabricated because the process died before canonical bridge resolution.
$x=New-LDFixtureV010 -Label 'first-rename' -FixtureNonce '63636363636363636363636363636363' -PermitSeed 'first-rename'
$label='ld-first-rename';$nonce='73737373737373737373737373737373';$script:EvidenceBoundAtomicFaultMode='after-live-move-before-journal';try{$r=Invoke-LDIntegrationV010 -X $x -Label $label -TransactionNonce $nonce}finally{$script:EvidenceBoundAtomicFaultMode='none'}
$txn=$null
try{
    Assert-LDFalse ([bool]$r.ok) 'first-rename crash unexpectedly succeeded';Assert-LDTrue ([bool]$r.precommit_persisted) 'first-rename precommit missing';Assert-LDTrue ($null-ne$r.atomic) 'first-rename atomic result missing';$txn=Get-EBTransactionRootV010 $r.atomic
    Assert-LDEq ([string]$r.precommit.permit_transaction_id) ([string]$x.permit_id) 'first-rename permit id'
    Assert-LDFalse (([string]$r.precommit.permit_transaction_id)-ceq([string]$r.precommit.expected_journal_transaction_id)) 'first-rename transaction namespaces conflated'
    $ia=Get-EBInspectionArgsV010 $x.fixture $label;$inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-LDTrue ([bool]$inspection.ok) ('first-rename inspection denied: '+[string]$inspection.reason);Assert-LDEq ([string]$inspection.receipt.state) 'first-rename-complete-unjournaled' 'first-rename inspection state'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));Assert-LDTrue ([bool]$repair.ok) ('first-rename normalization denied: '+[string]$repair.reason);Assert-LDEq ([string]$repair.transaction_id) ([string]$r.precommit.expected_journal_transaction_id) 'first-rename normalized journal id';Assert-LDEq ([string]$repair.phase) 'live-moved-to-old' 'first-rename normalized phase'
    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $allowed -StoreDirectory (Get-EBStoreV010 $x.fixture $label) -ExpectedTransactionId ([string]$repair.transaction_id);Assert-LDTrue ([bool]$ev.ok) ('first-rename evidence unreadable: '+[string]$ev.reason)
    [void](Invoke-LDRestartV010 -X $x -Label $label -JournalId ([string]$repair.transaction_id) -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -Phase 'live-moved-to-old')
    $pre=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDTrue ([bool]$pre.ok) 'first-rename precommit did not survive rollback-complete'
    $final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot $allowed -JournalStoreDirectory (Get-EBStoreV010 $x.fixture $label);Assert-LDFalse ([bool]$final.ok) 'first-rename fabricated canonical final receipt after crash';$count++
}finally{Restore-EBFixtureV010 $x.fixture $txn}

try{if(Test-Path -LiteralPath $fakeRoot){[IO.Directory]::Delete($fakeRoot,$true)}}catch{}
if($count-ne3){throw "lightweight dual-id restart bridge matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_LIGHTWEIGHT_DUAL_ID_RESTART_BRIDGE_PASS cases=$count byte_real_generic=true cross_process_recovery=true upstream_permit_chain_stubbed=true"