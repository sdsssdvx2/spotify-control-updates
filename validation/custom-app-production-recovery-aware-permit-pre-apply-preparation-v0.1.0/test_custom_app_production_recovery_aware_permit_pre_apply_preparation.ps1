$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-stage-executor-v0.1.0/test_custom_app_production_recovery_aware_permit_stage_executor.ps1')
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-pre-apply-preparation.ps1')

function Assert-RAPPTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAPPFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPPEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPP($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

# Recovery-aware permit fixtures intentionally bind the stable local tree to durable
# recovery evidence, while generic pre-apply must back up an actual byte-real live path.
# Preserve both truths: validate the real live bytes independently, then expose the
# recovery-stable tree only inside the already-qualified fresh-live validator calls.
$script:RAPPParentFreshLiveValidator=(Get-Command Test-CustomAppProductionStageExecutorLiveBaselineV010 -CommandType Function).ScriptBlock
$script:RAPPFreshLiveOverride=$null
function Test-CustomAppProductionStageExecutorLiveBaselineV010 {
    param([AllowNull()]$LifecycleRow,[AllowNull()]$Permit,[AllowNull()]$BindingRow,[Parameter(Mandatory=$true)][string]$Name)
    if($null -eq $script:RAPPFreshLiveOverride){return & $script:RAPPParentFreshLiveValidator -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name}
    $o=$script:RAPPFreshLiveOverride
    $locations=@($LifecycleRow.locations)
    if($locations.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$locations[0])){return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-location-not-single'}}
    try{
        $actualPath=[IO.Path]::GetFullPath([string]$locations[0]).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $expectedPath=[IO.Path]::GetFullPath([string]$o.live_path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    }catch{return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-location-invalid'}}
    if(-not $actualPath.Equals($expectedPath,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-location-drift'}}
    try{$actual=& $script:RASEOriginalLocalBaseline -Name $Name -AppPath $actualPath}catch{return [pscustomobject]@{ok=$false;reason=('fresh-live-byte-real-baseline-failed:'+[string]$_.Exception.Message)}}
    if(-not [bool]$actual.safe -or -not [bool]$actual.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $actual)){return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-baseline-not-safe'}}
    if(([string]$actual.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$o.actual_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-tree-changed'}}
    if([string]$actual.manifest_name -cne [string]$o.manifest_name){return [pscustomobject]@{ok=$false;reason='fresh-live-byte-real-manifest-changed'}}

    $oldOverride=$script:RASEPostStageBaselineOverride;$oldArmed=$script:RASEFreshLiveCallArmed;$oldInside=$script:RASEInsideFreshLiveObserver
    try{
        $script:RASEPostStageBaselineOverride=[pscustomobject]@{tree_sha256=([string]$o.stable_tree_sha256).Trim().ToLowerInvariant();manifest_name=[string]$o.manifest_name}
        $script:RASEFreshLiveCallArmed=$true;$script:RASEInsideFreshLiveObserver=$false
        return & $script:RAPPParentFreshLiveValidator -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    } finally {
        $script:RASEPostStageBaselineOverride=$oldOverride;$script:RASEFreshLiveCallArmed=$oldArmed;$script:RASEInsideFreshLiveObserver=$oldInside
    }
}

function New-RAPPByteRealCarrierV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('7'*32))
    $ready=New-RAReadyFixtureV010 -Label ('rapp-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $actualLive=[string]$ready.f.ce.q.f.f.q.x.live
    $liveBaseline=& $script:RASEOriginalLocalBaseline -Name $Name -AppPath $actualLive
    if(-not [bool]$liveBaseline.safe -or -not [bool]$liveBaseline.installable){throw 'RAPP byte-real live baseline unsafe'}
    $stableTree=([string]$ready.resume.result.live_tree_sha256).Trim().ToLowerInvariant()
    if($stableTree -notmatch '^[0-9a-f]{64}$'){throw 'RAPP stable recovery tree invalid'}

    # Make only the *new remote* tree byte-real before permit creation. The stable local
    # tree remains the exact durable recovery tree; changing it would weaken continuity.
    $probe=Join-Path $env:TEMP ('rapp-remote-probe-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    try{
        Write-ProductionStageRuntimeV010 $probe ([string]$liveBaseline.manifest_name) ($Name+'-remote-v2')
        $remoteBaseline=& $script:RASEOriginalLocalBaseline -Name $Name -AppPath $probe
        if(-not [bool]$remoteBaseline.safe -or -not [bool]$remoteBaseline.installable){throw 'RAPP byte-real remote baseline unsafe'}
        $remoteTree=([string]$remoteBaseline.tree_sha256).Trim().ToLowerInvariant()
    } finally {if(Test-Path -LiteralPath $probe){Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue}}

    $bundle=New-RAReadyPromotionBundleV010 -RecoveryResult $ready.resume.result -At $ready.at -RemoteTree $remoteTree -RemoteCommit ('e'*40)
    $bundle.lifecycle.locations=@($actualLive)
    $bundle.binding.last_local_manifest_name=[string]$liveBaseline.manifest_name
    $bundle.binding.binding.manifest_name=[string]$liveBaseline.manifest_name
    [void](Sync-PromotionBundleFingerprints -Bundle $bundle)
    Assert-RAPPEq ([string]$bundle.binding.last_local_tree_sha256).Trim().ToLowerInvariant() $stableTree 'pre-permit stable recovery tree'
    $ready.bundle=$bundle

    $prior=New-RAIssuerPriorV010 $ready
    $issuer=Invoke-RAIssuerV010 -Q $ready -Prior $prior -Nonce $Nonce
    if(-not [bool]$issuer.ok){throw ('RAPP byte-real issuer setup failed: '+[string]$issuer.reason)}
    $rapr=[pscustomobject]@{ready=$ready;prior=$prior;issuer=$issuer;state=(New-CustomAppProductionPermitReservationStateV010);nonce=$Nonce}
    $reservation=Invoke-RAPRFixtureV010 -F $rapr;if(-not [bool]$reservation.ok){throw ('RAPP byte-real reservation setup failed: '+[string]$reservation.reason)}
    $reservationStore=New-RAPRPPersistenceStoreV010 -R $rapr -Label ('rapp-'+$Label)
    $raprp=[pscustomobject]@{r=$rapr;reservation=$reservation;store=$reservationStore}
    $reservationPersisted=Invoke-RAPRPFixtureV010 -F $raprp;if(-not [bool]$reservationPersisted.ok){throw ('RAPP byte-real reservation persistence failed: '+[string]$reservationPersisted.reason)}
    $rapc=[pscustomobject]@{p=$raprp;persisted=$reservationPersisted}
    $candidate=Invoke-RAPCFixtureV010 -F $rapc;if(-not [bool]$candidate.ok){throw ('RAPP byte-real consumption candidate failed: '+[string]$candidate.reason)}
    $consumptionStore=New-RAPCPStoreV010 -F $rapc -Label ('rapp-'+$Label)
    $rapcp=[pscustomobject]@{f=$rapc;candidate=$candidate;store=$consumptionStore}
    $consumptionPersisted=Invoke-RAPCPFixtureV010 -F $rapcp;if(-not [bool]$consumptionPersisted.ok){throw ('RAPP byte-real consumption persistence failed: '+[string]$consumptionPersisted.reason)}
    return [pscustomobject]@{ready=$ready;bundle=$bundle;carrier=[pscustomobject]@{p=$rapcp;persisted=$consumptionPersisted};remote_tree=$remoteTree;stable_tree=$stableTree;actual_live_tree=([string]$liveBaseline.tree_sha256).Trim().ToLowerInvariant();live_path=$actualLive;manifest_name=[string]$liveBaseline.manifest_name}
}

function New-RAPPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$Nonce,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $built=New-RAPPByteRealCarrierV010 -Label $Label -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $f=$built.carrier;$q=$built.ready;$at=$q.at.AddSeconds(12)
    $stage=Invoke-RASEFixtureV010 -F $f -At $at -PostAt $at.AddSeconds(1)
    if(-not [bool]$stage.ok){throw ('fixture recovery-aware stage failed: '+[string]$stage.reason)}
    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $built.bundle.binding -ExpectedName ([string]$built.bundle.lifecycle.name)
    if(-not [bool]$binding.ok){throw ('fixture binding denied: '+[string]$binding.reason)}
    Assert-RAPPEq ([string]$stage.result.local_tree_sha256).Trim().ToLowerInvariant() ([string]$built.stable_tree).Trim().ToLowerInvariant() 'fixture stable recovery stage-local tree'

    # Stage bytes are genuinely materialized and must hash to the remote tree that was
    # bound before permit creation.
    Write-ProductionStageRuntimeV010 ([string]$stage.result.stage_path) ([string]$binding.manifest_name) (([string]$built.bundle.lifecycle.name)+'-remote-v2')
    $stageBaseline=& $script:RASEOriginalLocalBaseline -Name ([string]$built.bundle.lifecycle.name) -AppPath ([string]$stage.result.stage_path)
    Assert-RAPPEq ([string]$stageBaseline.tree_sha256).Trim().ToLowerInvariant() ([string]$stage.result.remote_tree_sha256).Trim().ToLowerInvariant() 'fixture byte-real stage tree'
    Assert-RAPPEq ([string]$stageBaseline.tree_sha256).Trim().ToLowerInvariant() ([string]$built.remote_tree).Trim().ToLowerInvariant() 'fixture stage pre-permit probe'

    # Root VCS metadata is deliberately invisible to the runtime baseline but must be
    # copied byte-for-byte into the rollback backup.
    $git=Join-Path ([string]$built.live_path) '.git';[IO.Directory]::CreateDirectory($git)|Out-Null
    [IO.File]::WriteAllText((Join-Path $git 'config'),("[remote `"origin`"]`nurl = https://github.com/$Source.git`n"),[Text.UTF8Encoding]::new($false))
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
    $runtimeAfterGit=& $script:RASEOriginalLocalBaseline -Name ([string]$built.bundle.lifecycle.name) -AppPath ([string]$built.live_path)
    Assert-RAPPEq ([string]$runtimeAfterGit.tree_sha256).Trim().ToLowerInvariant() ([string]$built.actual_live_tree).Trim().ToLowerInvariant() 'root git metadata changed runtime baseline'

    $base=Join-Path $env:TEMP ('rapp-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    return [pscustomobject]@{f=$f;q=$q;bundle=$built.bundle;stage=$stage.result;at=([DateTimeOffset]::Parse([string]$stage.result.post_stage_revalidated_at).AddSeconds(1));rollback=(Join-Path $base 'rollback');persistence=(Join-Path $base 'persistence');base=$base;live_path=[string]$built.live_path;remote_tree=[string]$built.remote_tree;stable_tree=[string]$built.stable_tree;actual_live_tree=[string]$built.actual_live_tree;manifest_name=[string]$built.manifest_name;raw_live_snapshot=$rawLive}
}

function Invoke-RAPPFixtureV010 {
    param([Parameter(Mandatory=$true)]$X,[AllowNull()]$Stage=$null,[AllowNull()]$Lifecycle=$null,[AllowNull()]$Binding=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()][string]$ExpectedTransactionId=$null,[AllowNull()][string]$RollbackRoot=$null,[AllowNull()][string]$PersistenceRoot=$null,[Nullable[DateTimeOffset]]$At=$null,[Nullable[DateTimeOffset]]$PostAt=$null)
    if($null -eq $Stage){$Stage=$X.stage};if($null -eq $Lifecycle){$Lifecycle=$X.bundle.lifecycle};if($null -eq $Binding){$Binding=$X.bundle.binding};if($null -eq $Permit){$Permit=$X.f.p.f.p.r.issuer.permit};if($null -eq $Key){$Key=$script:RAIssuerKey}
    if([string]::IsNullOrWhiteSpace($ExpectedTransactionId)){$ExpectedTransactionId=[string]$X.q.f.ce.q.f.f.identity.transaction_id};if([string]::IsNullOrWhiteSpace($RollbackRoot)){$RollbackRoot=[string]$X.rollback};if([string]::IsNullOrWhiteSpace($PersistenceRoot)){$PersistenceRoot=[string]$X.persistence}
    $when=$(if($null -ne $At){[DateTimeOffset]$At}else{[DateTimeOffset]$X.at});$post=$(if($null -ne $PostAt){[DateTimeOffset]$PostAt}else{$when.AddSeconds(1)});$ctx=New-RAIssueLiveContextV010 -Bundle $X.bundle
    $priorOverride=$script:RAPPFreshLiveOverride
    $script:RAPPFreshLiveOverride=[pscustomobject]@{stable_tree_sha256=[string]$X.stable_tree;actual_tree_sha256=[string]$X.actual_live_tree;live_path=[string]$X.live_path;manifest_name=[string]$X.manifest_name}
    try{
        return Invoke-CustomAppProductionRecoveryAwarePermitPreApplyPreparationV010 -RecoveryAwareStageExecutorResult $Stage -Name ([string]$X.bundle.lifecycle.name) -LifecycleRow $Lifecycle -ProvenanceRow $X.bundle.provenance -BindingRow $Binding -LifecycleStageResult $X.bundle.stage -ShadowResult $X.bundle.shadow -RetirementResumeResult $X.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $X.q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $X.q.f.ce.q.f.f.store -ConsumptionStoreDirectory $X.f.p.store -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $X.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $X.q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $X.f.persisted -Permit $Permit -SessionKey $Key -RollbackBackupRoot $RollbackRoot -PersistenceBackupRoot $PersistenceRoot -Now $when -PostBackupNow $post
    } finally {$script:RAPPFreshLiveOverride=$priorOverride}
}

function Assert-RAPPNoAuthorityV010($Result,[string]$Label){$x=if($Result.PSObject.Properties['result'] -and $null -ne $Result.result){$Result.result}else{$Result};foreach($f in @('session_key_persisted','session_key_exposed','preparation_is_authority','backups_are_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAPPFalse ([bool]$x.$f) "$Label escaped $f"};Assert-RAPPTrue ([bool]$x.requires_atomic_apply_rollback_executor) "$Label missing atomic apply requirement";Assert-RAPPTrue ([bool]$x.requires_fresh_revalidation_before_apply) "$Label missing fresh apply revalidation"}
function Assert-RAPPDeniedV010($Result,[string]$Label){Assert-RAPPFalse ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RAPPNoAuthorityV010 $Result $Label}
function Remove-RAPPFixtureV010($X){try{Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorCleanupV010 -WorkspacePath ([string]$X.stage.workspace_path)|Out-Null}catch{};try{if(Test-Path -LiteralPath $X.base){Remove-Item -LiteralPath $X.base -Recurse -Force -ErrorAction SilentlyContinue}}catch{}}

$count=0
$valid=New-RAPPFixtureV010 -Label 'valid' -Nonce ('1'*32)
try{
    $r=Invoke-RAPPFixtureV010 -X $valid
    Assert-RAPPTrue ([bool]$r.ok) ('valid recovery-aware pre-apply denied: '+[string]$r.reason);Assert-RAPPEq $r.reason 'recovery-aware-pre-apply-backups-prepared-verified-zero-apply-authority' 'valid reason';Assert-RAPPTrue ([bool]$r.backups_prepared -and [bool]$r.recovery_revalidated_before_backups -and [bool]$r.recovery_revalidated_after_backups) 'valid backup/revalidation flags missing';Assert-RAPPNoAuthorityV010 $r 'valid'
    $check=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $r.result;Assert-RAPPTrue ([bool]$check.ok) ('valid prepared result denied: '+[string]$check.reason)
    Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.app_backup_path) -PathType Container) 'valid app rollback backup missing';Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.persistence_backup_path) -PathType Container) 'valid persistence backup missing';Assert-RAPPTrue (Test-Path -LiteralPath (Join-Path ([string]$r.result.app_backup_path) '.git\config') -PathType Leaf) 'valid rollback backup omitted root git provenance'
    Assert-RAPPEq $r.result.app_backup_tree_sha256 $valid.raw_live_snapshot.tree_sha256 'valid rollback backup raw tree';Assert-RAPPTrue ([int]$r.result.app_backup_file_count -eq [int]$valid.raw_live_snapshot.file_count) 'valid rollback backup raw file count';Assert-RAPPTrue ([int64]$r.result.app_backup_total_bytes -eq [int64]$valid.raw_live_snapshot.total_bytes) 'valid rollback backup raw byte count'
    $liveAfter=Get-CustomAppUpdateTreeSnapshotV010 -Root $valid.live_path;Assert-RAPPEq $liveAfter.tree_sha256 $valid.raw_live_snapshot.tree_sha256 'pre-apply backup mutated byte-real live source'
    Assert-RAPPFalse ([bool]$r.result.PSObject.Properties['session_key']) 'raw session key leaked into result';$count++
    $auth=Copy-RAPP $r.result;$auth.apply_authorized=$true;$auth.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 (Get-CustomAppProductionRecoveryAwarePermitPreApplyResultMaterialV010 -Result $auth);$authCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $auth;Assert-RAPPFalse ([bool]$authCheck.ok) 'rehashed apply-authorized prepared result accepted';Assert-RAPPTrue ([string]$authCheck.reason -like '*authority-escaped-apply_authorized*') ('authority tamper reason '+[string]$authCheck.reason);$count++
    $finger=Copy-RAPP $r.result;$finger.result_fingerprint=('0'*64);$fingerCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $finger;Assert-RAPPFalse ([bool]$fingerCheck.ok) 'prepared result fingerprint tamper accepted';$count++
} finally {Remove-RAPPFixtureV010 $valid}

$stageTamper=New-RAPPFixtureV010 -Label 'stage-result-tamper' -Nonce ('2'*32)
try{
    $s=Copy-RAPP $stageTamper.stage;$s.result_fingerprint=('0'*64);$r=Invoke-RAPPFixtureV010 -X $stageTamper -Stage $s;Assert-RAPPDeniedV010 $r 'stage result fingerprint tamper';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-stage-result-invalid:*') ('stage tamper reason '+[string]$r.reason);$count++
    $s=Copy-RAPP $stageTamper.stage;$s.apply_authorized=$true;$s.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageExecutorResultMaterialV010 -Result $s);$r=Invoke-RAPPFixtureV010 -X $stageTamper -Stage $s;Assert-RAPPDeniedV010 $r 'rehashed stage apply authority';Assert-RAPPTrue ([string]$r.reason -like '*authority-escaped-apply_authorized*') ('stage authority reason '+[string]$r.reason);$count++
    $r=Invoke-RAPPFixtureV010 -X $stageTamper -ExpectedTransactionId ('f'*64);Assert-RAPPDeniedV010 $r 'transaction mismatch';Assert-RAPPEq $r.reason 'recovery-aware-pre-apply-transaction-mismatch' 'transaction mismatch reason';$count++
    $badKey=New-Object byte[] 32;[Array]::Copy($script:RAIssuerKey,$badKey,32);$badKey[0]=$badKey[0] -bxor 0x5a;$r=Invoke-RAPPFixtureV010 -X $stageTamper -Key $badKey;Assert-RAPPDeniedV010 $r 'wrong key';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-pre-backup-admission-denied:*') ('wrong key reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $stageTamper}

$userRemoved=New-RAPPFixtureV010 -Label 'user-removed' -Nonce ('3'*32)
try{$life=Copy-RAPP $userRemoved.bundle.lifecycle;$life.present=$false;$life.user_removed=$true;$r=Invoke-RAPPFixtureV010 -X $userRemoved -Lifecycle $life;Assert-RAPPDeniedV010 $r 'user removal';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-live-revalidation-denied:*') ('user removal reason '+[string]$r.reason);$count++}finally{Remove-RAPPFixtureV010 $userRemoved}

$liveDrift=New-RAPPFixtureV010 -Label 'live-drift' -Nonce ('4'*32)
try{[IO.File]::WriteAllText((Join-Path $liveDrift.live_path 'rapp-live-drift.txt'),'drift',[Text.UTF8Encoding]::new($false));$r=Invoke-RAPPFixtureV010 -X $liveDrift;Assert-RAPPDeniedV010 $r 'live tree drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-live-revalidation-denied:*fresh-live-byte-real-tree-changed*') ('live drift reason '+[string]$r.reason);$count++}finally{Remove-RAPPFixtureV010 $liveDrift}

$stageDrift=New-RAPPFixtureV010 -Label 'stage-drift' -Nonce ('5'*32)
try{[IO.File]::WriteAllText((Join-Path ([string]$stageDrift.stage.stage_path) 'rapp-stage-drift.txt'),'drift',[Text.UTF8Encoding]::new($false));$r=Invoke-RAPPFixtureV010 -X $stageDrift;Assert-RAPPDeniedV010 $r 'stage tree drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-generic-preparation-denied:*') ('stage drift reason '+[string]$r.reason);Assert-RAPPTrue ([bool]$r.requires_cleanup_if_not_applied) 'stage drift after generic entry lost cleanup requirement';$count++}finally{Remove-RAPPFixtureV010 $stageDrift}

$bindingDrift=New-RAPPFixtureV010 -Label 'binding-drift' -Nonce ('6'*32)
try{$binding=Copy-RAPP $bindingDrift.bundle.binding;$binding.source_identity='other/repository';$r=Invoke-RAPPFixtureV010 -X $bindingDrift -Binding $binding;Assert-RAPPDeniedV010 $r 'binding drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-binding-denied:*' -or [string]$r.reason -like 'recovery-aware-pre-apply-stage-binding-mismatch-*') ('binding drift reason '+[string]$r.reason);$count++}finally{Remove-RAPPFixtureV010 $bindingDrift}

$rootOverlap=New-RAPPFixtureV010 -Label 'root-overlap' -Nonce ('7'*32)
try{$same=Join-Path $rootOverlap.base 'same-root';$r=Invoke-RAPPFixtureV010 -X $rootOverlap -RollbackRoot $same -PersistenceRoot $same;Assert-RAPPDeniedV010 $r 'backup roots overlap';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-generic-preparation-denied:*') ('backup overlap reason '+[string]$r.reason);Assert-RAPPFalse ([bool]$r.backups_prepared) 'backup-root overlap incorrectly claimed complete backups';Assert-RAPPTrue ([bool]$r.requires_cleanup_if_not_applied) 'generic-entry failure lost conservative cleanup requirement';$count++}finally{Remove-RAPPFixtureV010 $rootOverlap}

$historical=New-RAPPFixtureV010 -Label 'historical-rev1' -Nonce ('8'*32)
try{
    $histB=New-RAPCFixtureV010 -Label 'rapp-historical-rev2' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('9'*32);$bAt=$historical.q.at.AddSeconds(16)
    $bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $historical.f.persisted.persisted_snapshot.state -ExpectedConsumptionRevision 1 -At $bAt;Assert-RAPPTrue ([bool]$bCandidate.ok) ('historical rev2 candidate failed: '+[string]$bCandidate.reason)
    $bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$historical.f.p.store};$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier -At $bAt.AddSeconds(1);Assert-RAPPTrue ([bool]$bPersist.ok) ('historical rev2 persistence failed: '+[string]$bPersist.reason);Assert-RAPPEq $bPersist.receipt.persisted_revision 2 'historical current consumption revision'
    $preAt=$bAt.AddSeconds(2);$r=Invoke-RAPPFixtureV010 -X $historical -At $preAt -PostAt $preAt.AddSeconds(1);Assert-RAPPTrue ([bool]$r.ok) ('historical rev1 pre-apply denied after rev2 append: '+[string]$r.reason);Assert-RAPPEq $r.result.historical_consumption_envelope_sha256 $historical.f.persisted.receipt.persistence_envelope_sha256 'historical consumption envelope continuity';Assert-RAPPNoAuthorityV010 $r 'historical rev1';$count++
} finally {Remove-RAPPFixtureV010 $historical}

$postExpiry=New-RAPPFixtureV010 -Label 'post-backup-expiry' -Nonce ('a'*32)
try{$expiredPost=$postExpiry.q.at.AddMinutes(1).AddSeconds(2);$r=Invoke-RAPPFixtureV010 -X $postExpiry -At $postExpiry.at -PostAt $expiredPost;Assert-RAPPDeniedV010 $r 'post-backup permit expiry';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-post-backup-admission-denied:*permit-expired*') ('post-backup expiry reason '+[string]$r.reason);Assert-RAPPTrue ([bool]$r.backups_prepared) 'post-backup expiry lost completed-backup evidence';Assert-RAPPTrue ([bool]$r.requires_cleanup_if_not_applied) 'post-backup expiry lost cleanup requirement';$count++}finally{Remove-RAPPFixtureV010 $postExpiry}

$future=New-RAPPFixtureV010 -Label 'future-app' -Nonce ('b'*32) -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App'
try{$r=Invoke-RAPPFixtureV010 -X $future;Assert-RAPPTrue ([bool]$r.ok) ('future app pre-apply denied: '+[string]$r.reason);Assert-RAPPEq $r.result.name 'future-app' 'future app identity';Assert-RAPPNoAuthorityV010 $r 'future app';$count++}finally{Remove-RAPPFixtureV010 $future}

Write-Host ("CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_PRE_APPLY_PREPARATION_MATRIX_PASS total={0}" -f $count)
