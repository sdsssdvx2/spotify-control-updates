$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# The recovery-aware pre-apply harness provides a byte-real permit/preparation chain.
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1')
# The #191 harness replays the exact evidence-bound atomic/recovery matrices and exposes
# a separate-process #156 -> #157 recovery helper. CI materializes this exact directory.
. (Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restore-integration-v0.1.0/test_custom_app_production_evidence_bound_recovery_restore_integration.ps1')
. (Join-Path $root 'validation/custom-app-production-dual-transaction-id-bridge-v0.1.0/custom-app-production-dual-transaction-id-bridge.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-durable-dual-transaction-id-bridge-integration.ps1')

function Assert-DDIBTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-DDIBFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-DDIBEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-DDIB($x){return (($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

$script:DDIBFault='none'
function Invoke-CustomAppProductionDurableDualTransactionIdBridgeIntegrationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:DDIBFault-ceq$Checkpoint){throw ('durable-dual-id-fixture-crash:'+$Checkpoint)}
}
function Get-DDIBTrustRootV010 {return (Get-EBTrustRootV010)}
function New-DDIBFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$PermitNonce,[Parameter(Mandatory=$true)][string]$JournalNonce)
    $x=New-RAPPFixtureV010 -Label ('ddib-'+$Label) -Nonce $PermitNonce
    $prep=Invoke-RAPPFixtureV010 -X $x
    Assert-DDIBTrue ([bool]$prep.ok) ("$Label recovery-aware pre-apply denied: "+[string]$prep.reason)
    $pc=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $prep.result;Assert-DDIBTrue ([bool]$pc.ok) ("$Label recovery-aware prepared invalid: "+[string]$pc.reason)
    $sc=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $x.stage;Assert-DDIBTrue ([bool]$sc.ok) ("$Label recovery-aware stage invalid: "+[string]$sc.reason)
    $generic=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $prep.result;$gc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $generic;Assert-DDIBTrue ([bool]$gc.ok) ("$Label generic prepared invalid: "+[string]$gc.reason)
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$x.live_path)
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$prep.result.name) -AppPath ([string]$x.live_path);Assert-DDIBTrue ([bool]$runtime.safe -and [bool]$runtime.installable) "$Label live runtime unsafe"
    Assert-DDIBEq ([string]$runtime.tree_sha256).Trim().ToLowerInvariant() ([string]$generic.live_tree_sha256).Trim().ToLowerInvariant() "$Label generic live runtime drift"
    $local=[string]$x.q.f.ce.q.f.f.q.persistence.local;$roaming=[string]$x.q.f.ce.q.f.f.q.persistence.roaming
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $roaming;Assert-DDIBEq ([string]$persist.fingerprint).Trim().ToLowerInvariant() ([string]$generic.persistence_fingerprint).Trim().ToLowerInvariant() "$Label persistence drift"
    $storeRoot=Join-Path (Get-DDIBTrustRootV010) ('ddib-store-root-'+$Label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($storeRoot)|Out-Null
    $storeLabel='ddib-'+$Label;$store=Join-Path $storeRoot ('evidence-bound-'+$storeLabel)
    return [pscustomobject]@{x=$x;prepared=$prep.result;stage=$x.stage;generic=$generic;full=$full;runtime=$runtime;persistence=$persist;local=$local;roaming=$roaming;store_root=$storeRoot;store_label=$storeLabel;store=$store;journal_nonce=$JournalNonce}
}
function Invoke-DDIBFixtureV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()]$Prepared=$null,[AllowNull()]$Stage=$null)
    if($null-eq$Prepared){$Prepared=$F.prepared};if($null-eq$Stage){$Stage=$F.stage}
    return Invoke-CustomAppProductionDurableDualTransactionIdBridgeIntegrationV010 -RecoveryAwarePreparedResult $Prepared -RecoveryAwareStageExecutorResult $Stage -Name ([string]$F.prepared.name) -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory ([string]$F.store) -TransactionNonce ([string]$F.journal_nonce) -LivePath ([string]$F.x.live_path) -ExpectedLiveFullTreeSha256 ([string]$F.full.tree_sha256) -ExpectedLiveFullFileCount ([int]$F.full.file_count) -ExpectedLiveFullTotalBytes ([int64]$F.full.total_bytes) -LocalAppDataRoot ([string]$F.local) -AppDataRoot ([string]$F.roaming)
}
function New-DDIBRecoveryAdapterV010($F){
    return [pscustomobject]@{
        q=[pscustomobject]@{x=[pscustomobject]@{live=[string]$F.x.live_path;store=[pscustomobject]@{root=[string]$F.store_root};f=[pscustomobject]@{name=[string]$F.prepared.name}};persistence=[pscustomobject]@{local=[string]$F.local;roaming=[string]$F.roaming}}
        prepared=[pscustomobject]@{result=$F.generic};full_before=$F.full;runtime_before=$F.runtime;persistence_before=$F.persistence
    }
}
function Get-DDIBEvidenceV010($F,[string]$JournalId){return Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot (Get-DDIBTrustRootV010) -StoreDirectory ([string]$F.store) -ExpectedTransactionId $JournalId}
function Invoke-DDIBRecoveryV010 {
    param([Parameter(Mandatory=$true)]$F,[Parameter(Mandatory=$true)][string]$JournalId,[Parameter(Mandatory=$true)][string]$ExpectedPhase,[Parameter(Mandatory=$true)][string]$ExpectedLiveState,[Parameter(Mandatory=$true)][string]$Label)
    $ev=Get-DDIBEvidenceV010 $F $JournalId;Assert-DDIBTrue ([bool]$ev.ok) ("$Label recovery evidence unreadable: "+[string]$ev.reason)
    $adapter=New-DDIBRecoveryAdapterV010 $F
    [void](Invoke-IRSeparateProcessRecoveryV010 -Fixture $adapter -StoreLabel ([string]$F.store_label) -TransactionId $JournalId -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -ExpectedInitialPhase $ExpectedPhase -ExpectedInitialLiveState $ExpectedLiveState -Label $Label)
    return $ev
}
function Get-DDIBInspectionArgsV010($F,[string]$JournalId){
    return @{
        AllowedRoot=(Get-DDIBTrustRootV010);JournalStoreDirectory=[string]$F.store;ExpectedTransactionId=$JournalId;Name=[string]$F.prepared.name
        ExpectedLiveFullTreeSha256=[string]$F.full.tree_sha256;ExpectedLiveFullFileCount=[int]$F.full.file_count;ExpectedLiveFullTotalBytes=[int64]$F.full.total_bytes;ExpectedStageRuntimeTreeSha256=[string]$F.generic.stage_tree_sha256
        ExpectedAppBackupTreeSha256=[string]$F.generic.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$F.generic.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$F.generic.app_backup_total_bytes;ExpectedPersistenceFingerprint=[string]$F.generic.persistence_fingerprint;LocalAppDataRoot=[string]$F.local;AppDataRoot=[string]$F.roaming
    }
}
function Assert-DDIBNoAuthorityV010($R,[string]$Label){
    $x=if($R.PSObject.Properties['result']-and$null-ne$R.result){$R.result}else{$R}
    foreach($f in @('result_is_authority','execution_authorized','finalization_authorized','spicetify_apply_authorized','cleanup_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-DDIBFalse ([bool]$x.$f) "$Label authority escaped $f"}}
}
function Get-DDIBPathsV010($F){$jp=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot (Get-DDIBTrustRootV010) -StoreDirectory ([string]$F.store);return Get-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPathsV010 $jp}
function Assert-DDIBPrecommitSurvivesV010($F,[string]$PermitId,[string]$JournalId,[string]$Label){$p=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory ([string]$F.store);Assert-DDIBTrue ([bool]$p.ok) ("$Label precommit unreadable: "+[string]$p.reason);Assert-DDIBEq ([string]$p.precommit.permit_transaction_id) $PermitId "$Label permit id";Assert-DDIBEq ([string]$p.precommit.expected_journal_transaction_id) $JournalId "$Label journal id";return $p}

$count=0

# 1. Full success: durable precommit first, #190 candidate-live, canonical bridge receipt,
# durable final receipt, then separate-process recovery. Both bridge files must survive.
$f=New-DDIBFixtureV010 -Label 'success' -PermitNonce '81818181818181818181818181818181' -JournalNonce '91919191919191919191919191919191'
$r=Invoke-DDIBFixtureV010 $f
Assert-DDIBTrue ([bool]$r.ok) ('success denied: '+[string]$r.reason);Assert-DDIBNoAuthorityV010 $r 'success'
$rc=Test-CustomAppProductionDurableDualTransactionIdBridgeIntegrationResultV010 -Result $r.result;Assert-DDIBTrue ([bool]$rc.ok) ('success result invalid: '+[string]$rc.reason)
Assert-DDIBFalse (([string]$r.result.permit_transaction_id)-ceq([string]$r.result.journal_transaction_id)) 'success conflated transaction namespaces'
$pre=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBTrue ([bool]$pre.ok) ('success precommit unreadable: '+[string]$pre.reason)
$final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBTrue ([bool]$final.ok) ('success final receipt unreadable: '+[string]$final.reason);Assert-DDIBEq ([string]$final.receipt.bridge_fingerprint) ([string]$r.result.bridge_fingerprint) 'success final bridge fingerprint'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId ([string]$r.result.journal_transaction_id) -ExpectedPhase 'candidate-live' -ExpectedLiveState 'candidate-live-exact' -Label 'durable dual id success recovery')
[void](Assert-DDIBPrecommitSurvivesV010 -F $f -PermitId ([string]$r.result.permit_transaction_id) -JournalId ([string]$r.result.journal_transaction_id) -Label 'success post-rollback')
$final2=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBTrue ([bool]$final2.ok) 'success final receipt did not survive rollback-complete';$count++

# 2. Crash after precommit but before journal init. No transaction workspace or live side
# effect. Exact retry must replay the same precommit and complete the canonical bridge.
$f=New-DDIBFixtureV010 -Label 'precommit-replay' -PermitNonce '82828282828282828282828282828282' -JournalNonce '92929292929292929292929292929292'
$script:DDIBFault='after-precommit-before-journal-init';try{$first=Invoke-DDIBFixtureV010 $f}finally{$script:DDIBFault='none'}
Assert-DDIBFalse ([bool]$first.ok) 'precommit crash unexpectedly succeeded';Assert-DDIBTrue ([bool]$first.precommit_persisted) 'precommit crash did not persist precommit';Assert-DDIBFalse (Test-Path -LiteralPath ([string]$first.precommit.transaction_root)) 'precommit crash created transaction workspace'
$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-DDIBTrustRootV010) -StoreDirectory $f.store;Assert-DDIBFalse ([bool]$jr.ok) 'precommit crash initialized journal';Assert-DDIBEq ([string]$jr.reason) 'journal-uninitialized' 'precommit crash journal state'
$r=Invoke-DDIBFixtureV010 $f;Assert-DDIBTrue ([bool]$r.ok) ('exact precommit replay denied: '+[string]$r.reason);Assert-DDIBEq ([string]$r.precommit.precommit_fingerprint) ([string]$first.precommit.precommit_fingerprint) 'exact precommit replay drift'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId ([string]$r.result.journal_transaction_id) -ExpectedPhase 'candidate-live' -ExpectedLiveState 'candidate-live-exact' -Label 'durable dual id replay recovery');$count++

# 3. Tampering the durable precommit after the same pre-journal crash must fail closed
# before journal init or any live mutation.
$f=New-DDIBFixtureV010 -Label 'precommit-tamper' -PermitNonce '83838383838383838383838383838383' -JournalNonce '93939393939393939393939393939393'
$script:DDIBFault='after-precommit-before-journal-init';try{$first=Invoke-DDIBFixtureV010 $f}finally{$script:DDIBFault='none'}
Assert-DDIBFalse ([bool]$first.ok) 'precommit tamper setup unexpectedly succeeded';$paths=Get-DDIBPathsV010 $f;$e=(Get-Content -LiteralPath ([string]$paths.precommit) -Raw|ConvertFrom-Json);$e.permit_transaction_id=('0'*64);[IO.File]::WriteAllText([string]$paths.precommit,($e|ConvertTo-Json -Depth 50 -Compress),[Text.UTF8Encoding]::new($false))
$r=Invoke-DDIBFixtureV010 $f;Assert-DDIBFalse ([bool]$r.ok) 'tampered precommit accepted';$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-DDIBTrustRootV010) -StoreDirectory $f.store;Assert-DDIBFalse ([bool]$jr.ok) 'tampered precommit initialized journal';$full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$f.x.live_path);Assert-DDIBEq ([string]$full.tree_sha256) ([string]$f.full.tree_sha256) 'tampered precommit changed live';$count++

# 4. Forging the upstream permit transaction id inside the fingerprinted recovery-aware
# prepared result is rejected before the bridge store is created.
$f=New-DDIBFixtureV010 -Label 'permit-tamper' -PermitNonce '84848484848484848484848484848484' -JournalNonce '94949494949494949494949494949494'
$bad=Copy-DDIB $f.prepared;$bad.transaction_id=('0'*64);$r=Invoke-DDIBFixtureV010 -F $f -Prepared $bad;Assert-DDIBFalse ([bool]$r.ok) 'forged permit transaction id accepted';Assert-DDIBFalse (Test-Path -LiteralPath ([string]$f.store)) 'forged permit id created bridge store';$count++

# 5. Crash after live -> old-live but before journal phase persistence. The precommit has
# already bound permit id -> predicted journal id; normalize the rename window and let
# #156/#157 restore in a new process. Final canonical receipt must not be fabricated.
$f=New-DDIBFixtureV010 -Label 'first-rename' -PermitNonce '85858585858585858585858585858585' -JournalNonce '95959595959595959595959595959595'
$script:EvidenceBoundAtomicFaultMode='after-live-move-before-journal';try{$r=Invoke-DDIBFixtureV010 $f}finally{$script:EvidenceBoundAtomicFaultMode='none'}
Assert-DDIBFalse ([bool]$r.ok) 'first-rename crash unexpectedly succeeded';$permitId=[string]$r.precommit.permit_transaction_id;$journalId=[string]$r.precommit.expected_journal_transaction_id
$ia=Get-DDIBInspectionArgsV010 $f $journalId;$inspect=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-DDIBTrue ([bool]$inspect.ok) ('first-rename inspection denied: '+[string]$inspect.reason);Assert-DDIBEq ([string]$inspect.receipt.state) 'first-rename-complete-unjournaled' 'first-rename inspection state'
$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));Assert-DDIBTrue ([bool]$repair.ok) ('first-rename repair denied: '+[string]$repair.reason);Assert-DDIBEq ([string]$repair.phase) 'live-moved-to-old' 'first-rename normalized phase'
$final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBFalse ([bool]$final.ok) 'first-rename crash fabricated final bridge receipt'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId $journalId -ExpectedPhase 'live-moved-to-old' -ExpectedLiveState 'absent-after-live-move' -Label 'durable dual id first-rename recovery');[void](Assert-DDIBPrecommitSurvivesV010 -F $f -PermitId $permitId -JournalId $journalId -Label 'first-rename post-rollback');$count++

# 6. Crash after #190 has durably reached candidate-live but before canonical resolver.
# The precommit is the only cross-generation durable bridge and must be enough to route
# crash recovery by journal id without inventing a final receipt.
$f=New-DDIBFixtureV010 -Label 'post-atomic' -PermitNonce '86868686868686868686868686868686' -JournalNonce '96969696969696969696969696969696'
$script:DDIBFault='after-atomic-before-canonical-bridge';try{$r=Invoke-DDIBFixtureV010 $f}finally{$script:DDIBFault='none'}
Assert-DDIBFalse ([bool]$r.ok) 'post-atomic crash unexpectedly succeeded';Assert-DDIBTrue ($null-ne$r.atomic -and [bool]$r.atomic.ok) 'post-atomic crash missing successful atomic result';$permitId=[string]$r.precommit.permit_transaction_id;$journalId=[string]$r.precommit.expected_journal_transaction_id
$final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBFalse ([bool]$final.ok) 'post-atomic crash fabricated final receipt'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId $journalId -ExpectedPhase 'candidate-live' -ExpectedLiveState 'candidate-live-exact' -Label 'durable dual id post-atomic recovery');[void](Assert-DDIBPrecommitSurvivesV010 -F $f -PermitId $permitId -JournalId $journalId -Label 'post-atomic post-rollback');$count++

# 7. Crash after canonical resolver succeeded in memory but before final receipt CreateNew.
# Durable state is intentionally still precommit-only and recovery must remain exact.
$f=New-DDIBFixtureV010 -Label 'post-canonical' -PermitNonce '87878787878787878787878787878787' -JournalNonce '97979797979797979797979797979797'
$script:DDIBFault='after-canonical-bridge-before-final-receipt';try{$r=Invoke-DDIBFixtureV010 $f}finally{$script:DDIBFault='none'}
Assert-DDIBFalse ([bool]$r.ok) 'post-canonical crash unexpectedly succeeded';Assert-DDIBTrue ($null-ne$r.bridge -and [bool]$r.bridge.ok) 'post-canonical crash missing in-memory canonical bridge';$permitId=[string]$r.precommit.permit_transaction_id;$journalId=[string]$r.precommit.expected_journal_transaction_id
$final=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBFalse ([bool]$final.ok) 'post-canonical crash persisted final receipt despite fault'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId $journalId -ExpectedPhase 'candidate-live' -ExpectedLiveState 'candidate-live-exact' -Label 'durable dual id post-canonical recovery');[void](Assert-DDIBPrecommitSurvivesV010 -F $f -PermitId $permitId -JournalId $journalId -Label 'post-canonical post-rollback');$count++

# 8. A persisted canonical receipt is not trusted after file tamper. Recovery routing is
# independent and still restores by the journal id from the untampered precommit/journal.
$f=New-DDIBFixtureV010 -Label 'final-tamper' -PermitNonce '88888888888888888888888888888888' -JournalNonce '98989898989898989898989898989898'
$r=Invoke-DDIBFixtureV010 $f;Assert-DDIBTrue ([bool]$r.ok) ('final-tamper setup denied: '+[string]$r.reason);$permitId=[string]$r.result.permit_transaction_id;$journalId=[string]$r.result.journal_transaction_id;$paths=Get-DDIBPathsV010 $f;$fr=(Get-Content -LiteralPath ([string]$paths.receipt) -Raw|ConvertFrom-Json);$fr.permit_transaction_id=('0'*64);[IO.File]::WriteAllText([string]$paths.receipt,($fr|ConvertTo-Json -Depth 60 -Compress),[Text.UTF8Encoding]::new($false))
$read=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationReceiptV010 -AllowedRoot (Get-DDIBTrustRootV010) -JournalStoreDirectory $f.store;Assert-DDIBFalse ([bool]$read.ok) 'tampered final receipt accepted'
[void](Invoke-DDIBRecoveryV010 -F $f -JournalId $journalId -ExpectedPhase 'candidate-live' -ExpectedLiveState 'candidate-live-exact' -Label 'durable dual id final-tamper recovery');[void](Assert-DDIBPrecommitSurvivesV010 -F $f -PermitId $permitId -JournalId $journalId -Label 'final-tamper post-rollback');$count++

if($count-ne8){throw "durable dual transaction id bridge integration matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_DURABLE_DUAL_TRANSACTION_ID_BRIDGE_INTEGRATION_PASS cases=$count separate_process_recovery=true"
