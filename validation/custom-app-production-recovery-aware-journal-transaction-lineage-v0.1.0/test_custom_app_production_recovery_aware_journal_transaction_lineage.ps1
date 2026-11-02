$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse the exact validated recovery-aware pre-apply fixture and the exact #191
# separate-process recovery harness. Their matrices intentionally replay here.
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1')
. (Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restore-integration-v0.1.0/test_custom_app_production_evidence_bound_recovery_restore_integration.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-journal-transaction-lineage.ps1')

function Assert-LRTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-LRFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-LREq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-LR($x){return (($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

$script:LRLineageFault='none'
function Invoke-CustomAppProductionRecoveryAwareJournalTransactionLineageValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:LRLineageFault -ceq $Checkpoint){throw ('transaction-lineage-fixture-crash:'+ $Checkpoint)}
}
function Get-LRTrustRootV010 {return (Get-EBTrustRootV010)}
function Get-LRRootsV010($X){return [pscustomobject]@{local=[string]$X.q.f.ce.q.f.f.q.persistence.local;roaming=[string]$X.q.f.ce.q.f.f.q.persistence.roaming}}
function New-LRFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$PermitNonce,[Parameter(Mandatory=$true)][string]$TransactionNonce)
    $x=New-RAPPFixtureV010 -Label ('lineage-'+$Label) -Nonce $PermitNonce
    $prep=Invoke-RAPPFixtureV010 -X $x
    Assert-LRTrue ([bool]$prep.ok) ("$Label recovery-aware pre-apply denied: "+[string]$prep.reason)
    $pc=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $prep.result;Assert-LRTrue ([bool]$pc.ok) ("$Label recovery-aware pre-apply result invalid: "+[string]$pc.reason)
    $generic=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $prep.result
    $gc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $generic;Assert-LRTrue ([bool]$gc.ok) ("$Label generic projection invalid: "+[string]$gc.reason)
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$x.live_path)
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$prep.result.name) -AppPath ([string]$x.live_path)
    Assert-LRTrue ([bool]$runtime.safe -and [bool]$runtime.installable) "$Label live runtime unsafe"
    Assert-LREq ([string]$runtime.tree_sha256).Trim().ToLowerInvariant() ([string]$generic.live_tree_sha256).Trim().ToLowerInvariant() "$Label generic live runtime does not match byte-real live"
    $roots=Get-LRRootsV010 $x
    $persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $roots.local -AppDataRoot $roots.roaming
    Assert-LREq ([string]$persistence.fingerprint).Trim().ToLowerInvariant() ([string]$generic.persistence_fingerprint).Trim().ToLowerInvariant() "$Label persistence drift before lineage"
    $storeRoot=Join-Path (Get-LRTrustRootV010) ('lineage-store-root-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($storeRoot)|Out-Null
    $storeLabel='tx-'+$Label
    $store=Join-Path $storeRoot ('evidence-bound-'+$storeLabel)
    return [pscustomobject]@{x=$x;prep=$prep.result;generic=$generic;full=$full;runtime=$runtime;persistence=$persistence;roots=$roots;store_root=$storeRoot;store_label=$storeLabel;store=$store;transaction_nonce=$TransactionNonce}
}
function Invoke-LRFixtureV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()]$Prepared=$null)
    if($null-eq$Prepared){$Prepared=$F.prep}
    return Invoke-CustomAppProductionRecoveryAwareJournalTransactionLineageAtomicV010 -RecoveryAwarePreparedResult $Prepared -Name ([string]$F.prep.name) -AllowedRoot (Get-LRTrustRootV010) -JournalStoreDirectory ([string]$F.store) -TransactionNonce ([string]$F.transaction_nonce) -LivePath ([string]$F.x.live_path) -ExpectedLiveFullTreeSha256 ([string]$F.full.tree_sha256) -ExpectedLiveFullFileCount ([int]$F.full.file_count) -ExpectedLiveFullTotalBytes ([int64]$F.full.total_bytes) -LocalAppDataRoot ([string]$F.roots.local) -AppDataRoot ([string]$F.roots.roaming)
}
function Assert-LRZeroAuthorityV010($R,[string]$Label){
    $x=if($R.PSObject.Properties['result'] -and $null-ne$R.result){$R.result}else{$R}
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-LRFalse ([bool]$x.$f) "$Label authority escaped $f"}}
}
function Restore-LRSuccessV010($F,$R,[string]$Label){
    $rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$F.x.live_path) -AppBackupPath ([string]$F.generic.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$F.generic.app_backup_tree_sha256) -PersistenceBackupPath ([string]$F.generic.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$F.generic.persistence_fingerprint) -LocalAppDataRoot ([string]$F.roots.local) -AppDataRoot ([string]$F.roots.roaming)
    Assert-LRTrue ([bool]$rb.ok) "$Label exact restore failed"
    $tx=[string]$R.lineage.transaction_root
    if(Test-Path -LiteralPath $tx){Remove-CustomAppAtomicDirectoryV010 -Path $tx -ExpectedParent ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$F.x.live_path))) -ExpectedName ([IO.Path]::GetFileName($tx))}
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$F.x.live_path);Assert-LREq ([string]$full.tree_sha256) ([string]$F.full.tree_sha256) "$Label full live not restored"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$F.roots.local) -AppDataRoot ([string]$F.roots.roaming);Assert-LREq ([string]$persist.fingerprint) ([string]$F.persistence.fingerprint) "$Label persistence not restored"
}
function New-LRRecoveryAdapterV010($F){
    return [pscustomobject]@{
        q=[pscustomobject]@{
            x=[pscustomobject]@{live=[string]$F.x.live_path;store=[pscustomobject]@{root=[string]$F.store_root};f=[pscustomobject]@{name=[string]$F.prep.name}}
            persistence=[pscustomobject]@{local=[string]$F.roots.local;roaming=[string]$F.roots.roaming}
        }
        prepared=[pscustomobject]@{result=$F.generic}
        full_before=$F.full;runtime_before=$F.runtime;persistence_before=$F.persistence
    }
}
function Get-LRInspectionArgsV010($F,[string]$CrashTransactionId){
    return @{
        AllowedRoot=(Get-LRTrustRootV010);JournalStoreDirectory=[string]$F.store;ExpectedTransactionId=$CrashTransactionId;Name=[string]$F.prep.name
        ExpectedLiveFullTreeSha256=[string]$F.full.tree_sha256;ExpectedLiveFullFileCount=[int]$F.full.file_count;ExpectedLiveFullTotalBytes=[int64]$F.full.total_bytes;ExpectedStageRuntimeTreeSha256=[string]$F.generic.stage_tree_sha256
        ExpectedAppBackupTreeSha256=[string]$F.generic.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$F.generic.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$F.generic.app_backup_total_bytes;ExpectedPersistenceFingerprint=[string]$F.generic.persistence_fingerprint;LocalAppDataRoot=[string]$F.roots.local;AppDataRoot=[string]$F.roots.roaming
    }
}

$count=0

$f=New-LRFixtureV010 -Label 'success' -PermitNonce '61616161616161616161616161616161' -TransactionNonce '71717171717171717171717171717171'
$r=Invoke-LRFixtureV010 $f
try{
    Assert-LRTrue ([bool]$r.ok) ('lineage success denied: '+[string]$r.reason);Assert-LRZeroAuthorityV010 $r 'lineage success'
    $rc=Test-CustomAppProductionRecoveryAwareJournalTransactionLineageResultV010 -Result $r.result;Assert-LRTrue ([bool]$rc.ok) ('lineage success result invalid: '+[string]$rc.reason)
    Assert-LRFalse (([string]$r.result.upstream_transaction_id)-ceq([string]$r.result.crash_transaction_id)) 'lineage success unexpectedly reused the upstream transaction id'
    $jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store;Assert-LRTrue ([bool]$jr.ok) 'lineage success journal unreadable';Assert-LREq ([string]$jr.transaction_id) ([string]$r.result.crash_transaction_id) 'lineage success crash id not journal id'
    $lr=Resolve-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store -ExpectedUpstreamTransactionId ([string]$r.result.upstream_transaction_id) -ExpectedCrashTransactionId ([string]$jr.transaction_id) -ExpectedRecoveryAwarePreApplyResultFingerprint ([string]$f.prep.result_fingerprint);Assert-LRTrue ([bool]$lr.ok) ('lineage success resolve denied: '+[string]$lr.reason)
    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store -ExpectedTransactionId ([string]$jr.transaction_id);Assert-LRTrue ([bool]$ev.ok) ('lineage success recovery evidence unreadable: '+[string]$ev.reason)
    $count++
}finally{if($r.ok){Restore-LRSuccessV010 $f $r 'lineage success'}}

$f=New-LRFixtureV010 -Label 'pre-journal-replay' -PermitNonce '62626262626262626262626262626262' -TransactionNonce '72727272727272727272727272727272'
$script:LRLineageFault='after-lineage-binding-before-journal-init';try{$first=Invoke-LRFixtureV010 $f}finally{$script:LRLineageFault='none'}
Assert-LRFalse ([bool]$first.ok) 'pre-journal crash unexpectedly succeeded';Assert-LRTrue ([bool]$first.lineage_persisted) 'pre-journal lineage not persisted';Assert-LRFalse (Test-Path -LiteralPath ([string]$first.lineage.transaction_root)) 'pre-journal crash created transaction workspace'
$pre=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store;Assert-LRFalse ([bool]$pre.ok) 'pre-journal crash initialized journal';Assert-LREq ([string]$pre.reason) 'journal-uninitialized' 'pre-journal state reason'
$r=Invoke-LRFixtureV010 $f
try{Assert-LRTrue ([bool]$r.ok) ('exact lineage replay denied: '+[string]$r.reason);Assert-LREq ([string]$r.lineage.lineage_fingerprint) ([string]$first.lineage.lineage_fingerprint) 'exact lineage replay fingerprint drift';$count++}finally{if($r.ok){Restore-LRSuccessV010 $f $r 'lineage replay'}}

$f=New-LRFixtureV010 -Label 'tamper' -PermitNonce '63636363636363636363636363636363' -TransactionNonce '73737373737373737373737373737373'
$script:LRLineageFault='after-lineage-binding-before-journal-init';try{$first=Invoke-LRFixtureV010 $f}finally{$script:LRLineageFault='none'}
Assert-LRFalse ([bool]$first.ok) 'tamper setup crash unexpectedly succeeded'
$sidecar=Join-Path $f.store 'transaction-lineage-v1.json';$tampered=(Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json);$tampered.upstream_transaction_id=('0'*64);[IO.File]::WriteAllText($sidecar,($tampered|ConvertTo-Json -Depth 40 -Compress),[Text.UTF8Encoding]::new($false))
$r=Invoke-LRFixtureV010 $f
Assert-LRFalse ([bool]$r.ok) 'tampered lineage sidecar accepted';Assert-LRTrue ([string]$r.reason -like '*transaction-lineage*') 'tampered lineage denial reason drift';Assert-LRFalse (Test-Path -LiteralPath ([string]$first.lineage.transaction_root)) 'tampered lineage created transaction workspace'
$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store;Assert-LRFalse ([bool]$jr.ok) 'tampered lineage initialized journal';$full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$f.x.live_path);Assert-LREq ([string]$full.tree_sha256) ([string]$f.full.tree_sha256) 'tampered lineage changed live';$count++

$f=New-LRFixtureV010 -Label 'upstream-tamper' -PermitNonce '64646464646464646464646464646464' -TransactionNonce '74747474747474747474747474747474'
$bad=Copy-LR $f.prep;$bad.transaction_id=('0'*64)
$r=Invoke-LRFixtureV010 -F $f -Prepared $bad
Assert-LRFalse ([bool]$r.ok) 'forged upstream transaction id accepted';Assert-LRTrue ([string]$r.reason -like '*recovery-aware-prepared-invalid*') 'forged upstream transaction denial reason drift';Assert-LRFalse (Test-Path -LiteralPath $f.store) 'forged upstream transaction created lineage store';$count++

$f=New-LRFixtureV010 -Label 'restart-recovery' -PermitNonce '65656565656565656565656565656565' -TransactionNonce '75757575757575757575757575757575'
$script:EvidenceBoundAtomicFaultMode='after-live-move-before-journal';try{$r=Invoke-LRFixtureV010 $f}finally{$script:EvidenceBoundAtomicFaultMode='none'}
Assert-LRFalse ([bool]$r.ok) 'restart-recovery crash unexpectedly succeeded';Assert-LRTrue ([bool]$r.lineage_persisted) 'restart-recovery lineage missing'
$crashTx=[string]$r.lineage.crash_transaction_id;$ia=Get-LRInspectionArgsV010 $f $crashTx
$inspect=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-LRTrue ([bool]$inspect.ok) ('restart-recovery inspection denied: '+[string]$inspect.reason);Assert-LREq ([string]$inspect.receipt.state) 'first-rename-complete-unjournaled' 'restart-recovery inspection state'
$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));Assert-LRTrue ([bool]$repair.ok) ('restart-recovery normalization denied: '+[string]$repair.reason);Assert-LREq ([string]$repair.phase) 'live-moved-to-old' 'restart-recovery normalized phase'
$ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store -ExpectedTransactionId $crashTx;Assert-LRTrue ([bool]$ev.ok) ('restart-recovery evidence missing: '+[string]$ev.reason)
$adapter=New-LRRecoveryAdapterV010 $f
[void](Invoke-IRSeparateProcessRecoveryV010 -Fixture $adapter -StoreLabel ([string]$f.store_label) -TransactionId $crashTx -EvidenceFingerprint ([string]$ev.evidence_fingerprint) -ExpectedInitialPhase 'live-moved-to-old' -ExpectedInitialLiveState 'absent-after-live-move' -Label 'recovery-aware lineage restart recovery')
$lr=Resolve-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store -ExpectedUpstreamTransactionId ([string]$f.prep.transaction_id) -ExpectedCrashTransactionId $crashTx -ExpectedRecoveryAwarePreApplyResultFingerprint ([string]$f.prep.result_fingerprint);Assert-LRTrue ([bool]$lr.ok) ('rollback-complete lineage unreadable: '+[string]$lr.reason)
$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-LRTrustRootV010) -StoreDirectory $f.store;Assert-LREq ([string]$jr.entry.phase) 'rollback-complete' 'restart-recovery final phase';Assert-LREq ([string]$jr.transaction_id) $crashTx 'restart-recovery crash id drift'
$full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$f.x.live_path);Assert-LREq ([string]$full.tree_sha256) ([string]$f.full.tree_sha256) 'restart-recovery live not restored'
$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$f.roots.local) -AppDataRoot ([string]$f.roots.roaming);Assert-LREq ([string]$persist.fingerprint) ([string]$f.persistence.fingerprint) 'restart-recovery persistence not restored'
if(Test-Path -LiteralPath ([string]$r.lineage.transaction_root)){Remove-CustomAppAtomicDirectoryV010 -Path ([string]$r.lineage.transaction_root) -ExpectedParent ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$f.x.live_path))) -ExpectedName ([IO.Path]::GetFileName([string]$r.lineage.transaction_root))}
$count++

if($count-ne5){throw "recovery-aware journal transaction lineage matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_JOURNAL_TRANSACTION_LINEAGE_MATRIX_PASS cases=$count separate_process_recovery=true"
