$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-consumption-persistence-v0.1.0/test_custom_app_production_consumption_persistence_v011.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-executor-start-gate.ps1')

function Assert-StartNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.eligibility_is_authority) "$Label eligibility authority"
    Assert-False ([bool]$Result.stage_acquisition_authorized) "$Label stage acquisition authority"
    Assert-False ([bool]$Result.executor_may_stage) "$Label executor stage authority"
    Assert-False ([bool]$Result.executor_may_apply) "$Label executor apply authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_stage_acquisition) "$Label pre-stage revalidation missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_after_stage) "$Label post-stage revalidation missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_apply) "$Label pre-apply revalidation missing"
}

function New-ExecutorStartFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='abababababababababababababababab')
    $s=New-PersistenceStoreFixtureV011 $Label
    $c=New-PersistableConsumptionV011 $s.read.state $Nonce $Name $Source $Manifest
    $p=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c.next_state -ExpectedCurrentRevision 0 -Now $now
    if(-not [bool]$p.ok){throw ('executor start fixture persistence failed: '+[string]$p.reason)}
    return [pscustomobject]@{store=$s;consumption=$c;persist=$p}
}

function Invoke-StartFixtureV010 {
    param($X,[DateTimeOffset]$At=$now,[byte[]]$SessionKey=$key,[AllowNull()]$Permit=$null,[AllowNull()][string]$ConsumptionId=$null)
    if($null -eq $Permit){$Permit=$X.consumption.fixture.permit}
    if([string]::IsNullOrWhiteSpace($ConsumptionId)){$ConsumptionId=[string]$X.consumption.result.consumption_id}
    $f=$X.consumption.fixture.f
    return Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $X.store.root -StoreDirectory $X.store.store -ExpectedConsumptionId $ConsumptionId -Permit $Permit -Name $f.name -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -CurrentBaseline $f.baseline -ShadowProtocolQualification $f.shadow -LiveAttestedQualification $f.live -SessionKey $SessionKey -Now $At
}

function Assert-StartDeniedV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly start-eligible"
    Assert-False ([bool]$Result.staging_eligible) "$Label staging eligibility escaped"
    Assert-StartNoAuthorityV010 $Result $Label
}

$count=0
$x=New-ExecutorStartFixtureV010 'valid'
$valid=Invoke-StartFixtureV010 $x
Assert-True ([bool]$valid.ok) ('valid persisted executor start denied: '+[string]$valid.reason)
Assert-True ([bool]$valid.staging_eligible) 'valid executor start did not produce staging eligibility'
Assert-True (Test-CustomAppProductionExecutorStartGateSha256V010 ([string]$valid.eligibility_fingerprint)) 'valid eligibility fingerprint invalid'
Assert-StartNoAuthorityV010 $valid 'valid'
$decisionCheck=Test-CustomAppProductionExecutorStartEligibilityV010 $valid.decision
Assert-True ([bool]$decisionCheck.ok) ('valid eligibility self-check failed: '+[string]$decisionCheck.reason)
$count++

$wrongId=Invoke-StartFixtureV010 $x $now $key $null ('f'*64)
Assert-StartDeniedV010 $wrongId 'wrong-consumption-id';Assert-True ([string]$wrongId.reason -ceq 'persisted-consumption-id-not-found-or-ambiguous') 'wrong consumption id reason drifted';$count++

$empty=New-PersistenceStoreFixtureV011 'empty-start'
$emptyResult=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $empty.root -StoreDirectory $empty.store -ExpectedConsumptionId ([string]$x.consumption.result.consumption_id) -Permit $x.consumption.fixture.permit -Name $x.consumption.fixture.f.name -LifecycleRow $x.consumption.fixture.f.lifecycle -ProvenanceRow $x.consumption.fixture.f.provenance -BindingRow $x.consumption.fixture.f.binding -CurrentBaseline $x.consumption.fixture.f.baseline -ShadowProtocolQualification $x.consumption.fixture.f.shadow -LiveAttestedQualification $x.consumption.fixture.f.live -SessionKey $key -Now $now
Assert-StartDeniedV010 $emptyResult 'empty-store';Assert-True ([string]$emptyResult.reason -ceq 'persisted-consumption-id-not-found-or-ambiguous') 'empty store reason drifted';$count++

$wrongKey=Invoke-StartFixtureV010 $x $now ([byte[]](33..64))
Assert-StartDeniedV010 $wrongKey 'wrong-key';Assert-True ([string]$wrongKey.reason -ceq 'executor-start-permit-revalidation-denied:permit-hmac-mismatch') 'wrong key reason drifted';$count++

$expired=Invoke-StartFixtureV010 $x $now.AddMinutes(4)
Assert-StartDeniedV010 $expired 'expired-permit';Assert-True ([string]$expired.reason -ceq 'executor-start-permit-revalidation-denied:permit-expired') 'expired permit reason drifted';$count++

$removed=New-ExecutorStartFixtureV010 'removed' -Nonce 'bcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc';$removed.consumption.fixture.f.lifecycle.user_removed=$true;$removed.consumption.fixture.f.lifecycle.present=$false
$removedResult=Invoke-StartFixtureV010 $removed
Assert-StartDeniedV010 $removedResult 'user-removed';Assert-True ([string]$removedResult.reason -like 'executor-start-permit-revalidation-denied:permit-current-admission-denied:*') 'user removal not revalidated';$count++

$runtime=New-ExecutorStartFixtureV010 'runtime-drift' -Nonce 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';$runtime.consumption.fixture.f.baseline.tree_sha256=('8'*64)
$runtimeResult=Invoke-StartFixtureV010 $runtime
Assert-StartDeniedV010 $runtimeResult 'runtime-drift';Assert-True ([string]$runtimeResult.reason -like 'executor-start-permit-revalidation-denied:*') 'runtime drift not denied';$count++

$source=New-ExecutorStartFixtureV010 'source-drift' -Nonce 'dedededededededededededededededede';$source.consumption.fixture.f.provenance.source_identity='other/repo';$source.consumption.fixture.f.provenance.source_changed=$true;$source.consumption.fixture.f.provenance.requires_reenrollment=$true
$sourceResult=Invoke-StartFixtureV010 $source
Assert-StartDeniedV010 $sourceResult 'source-drift';Assert-True ([string]$sourceResult.reason -like 'executor-start-permit-revalidation-denied:*') 'source drift not denied';$count++

$binding=New-ExecutorStartFixtureV010 'binding-drift' -Nonce 'efefefefefefefefefefefefefefefef';$binding.consumption.fixture.f.binding.source_identity='other/repo'
$bindingResult=Invoke-StartFixtureV010 $binding
Assert-StartDeniedV010 $bindingResult 'binding-drift';Assert-True ([string]$bindingResult.reason -like 'executor-start-permit-revalidation-denied:*') 'binding drift not denied';$count++

$hmac=Copy-Deep $x.consumption.fixture.permit;$hmac.hmac_sha256=('1'*64)
$hmacResult=Invoke-StartFixtureV010 $x $now $key $hmac
Assert-StartDeniedV010 $hmacResult 'tampered-hmac';Assert-True ([string]$hmacResult.reason -ceq 'executor-start-permit-revalidation-denied:permit-hmac-mismatch') 'tampered HMAC reason drifted';$count++

$otherPermit=New-FixturePermit $x.consumption.fixture.f '12121212121212121212121212121212' $now
$continuity=Invoke-StartFixtureV010 $x $now $key $otherPermit
Assert-StartDeniedV010 $continuity 'consumption-permit-continuity';Assert-True ([string]$continuity.reason -like 'consumption-permit-mismatch-*') 'consumption/permit continuity reason drifted';$count++

$lock=New-ExecutorStartFixtureV010 'lock-start' -Nonce '23232323232323232323232323232323';$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $lock.store.root -StoreDirectory $lock.store.store;$held=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths
try{$lockResult=Invoke-StartFixtureV010 $lock;Assert-StartDeniedV010 $lockResult 'store-lock-contention';Assert-True ([string]$lockResult.reason -like 'persisted-consumption-read-denied:*lock-busy*') 'store lock reason drifted'}finally{$held.Dispose()};$count++

$tamper=New-ExecutorStartFixtureV010 'store-tamper' -Nonce '34343434343434343434343434343434';[IO.File]::WriteAllText((Join-Path $tamper.store.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false));$tamperResult=Invoke-StartFixtureV010 $tamper
Assert-StartDeniedV010 $tamperResult 'store-tamper';Assert-True ([string]$tamperResult.reason -like 'persisted-consumption-read-denied:*JSON invalid*') 'store tamper reason drifted';$count++

$futureTimeStore=New-PersistenceStoreFixtureV011 'future-consumed-time';$futureFx=New-ConsumptionFixture -Nonce '45454545454545454545454545454545';$futureConsumption=Consume-Fixture $futureFx $futureTimeStore.read.state 0 1 $now.AddMinutes(1);Assert-True ([bool]$futureConsumption.ok) 'future-time consumption fixture failed';$futurePersist=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $futureTimeStore.root -StoreDirectory $futureTimeStore.store -NextState $futureConsumption.next_state -ExpectedCurrentRevision 0 -Now $now;Assert-True ([bool]$futurePersist.ok) 'future-time consumption persistence failed';$f=$futureFx.f;$futureTimeResult=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $futureTimeStore.root -StoreDirectory $futureTimeStore.store -ExpectedConsumptionId ([string]$futureConsumption.consumption_id) -Permit $futureFx.permit -Name $f.name -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -CurrentBaseline $f.baseline -ShadowProtocolQualification $f.shadow -LiveAttestedQualification $f.live -SessionKey $key -Now $now
Assert-StartDeniedV010 $futureTimeResult 'future-consumption-time';Assert-True ([string]$futureTimeResult.reason -ceq 'executor-start-before-persisted-consumption-time') 'future consumed time reason drifted';$count++

$multi=New-PersistenceStoreFixtureV011 'multi-different';$first=New-PersistableConsumptionV011 $multi.read.state '56565656565656565656565656565656' 'tagify' 'alexk218/tagify' 'Tagify';$firstP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $multi.root -StoreDirectory $multi.store -NextState $first.next_state -ExpectedCurrentRevision 0 -Now $now;Assert-True ([bool]$firstP.ok) 'multi first persist failed';$read1=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $multi.root -StoreDirectory $multi.store;$second=New-PersistableConsumptionV011 $read1.state '67676767676767676767676767676767' 'future-app' 'owner/future-app' 'Future App';$secondP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $multi.root -StoreDirectory $multi.store -NextState $second.next_state -ExpectedCurrentRevision 1 -Now $now;Assert-True ([bool]$secondP.ok) 'multi second persist failed';$ff=$first.fixture.f;$multiFirst=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $multi.root -StoreDirectory $multi.store -ExpectedConsumptionId ([string]$first.result.consumption_id) -Permit $first.fixture.permit -Name $ff.name -LifecycleRow $ff.lifecycle -ProvenanceRow $ff.provenance -BindingRow $ff.binding -CurrentBaseline $ff.baseline -ShadowProtocolQualification $ff.shadow -LiveAttestedQualification $ff.live -SessionKey $key -Now $now
Assert-True ([bool]$multiFirst.ok) ('older different-app consumption incorrectly blocked: '+[string]$multiFirst.reason);Assert-StartNoAuthorityV010 $multiFirst 'multi-different-first';$count++

$same=New-PersistenceStoreFixtureV011 'multi-same';$old=New-PersistableConsumptionV011 $same.read.state '78787878787878787878787878787878';$oldP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $same.root -StoreDirectory $same.store -NextState $old.next_state -ExpectedCurrentRevision 0 -Now $now;Assert-True ([bool]$oldP.ok) 'same-app old persist failed';$sameRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $same.root -StoreDirectory $same.store;$new=New-PersistableConsumptionV011 $sameRead.state '89898989898989898989898989898989';$newP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $same.root -StoreDirectory $same.store -NextState $new.next_state -ExpectedCurrentRevision 1 -Now $now;Assert-True ([bool]$newP.ok) 'same-app new persist failed';$of=$old.fixture.f;$oldResult=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $same.root -StoreDirectory $same.store -ExpectedConsumptionId ([string]$old.result.consumption_id) -Permit $old.fixture.permit -Name $of.name -LifecycleRow $of.lifecycle -ProvenanceRow $of.provenance -BindingRow $of.binding -CurrentBaseline $of.baseline -ShadowProtocolQualification $of.shadow -LiveAttestedQualification $of.live -SessionKey $key -Now $now
Assert-StartDeniedV010 $oldResult 'superseded-same-app';Assert-True ([string]$oldResult.reason -ceq 'persisted-consumption-superseded-by-newer-same-app') 'same-app supersession reason drifted';$count++

$future=New-ExecutorStartFixtureV010 'future-app' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce '90909090909090909090909090909090';$futureResult=Invoke-StartFixtureV010 $future
Assert-True ([bool]$futureResult.ok) ('generic future app start eligibility denied: '+[string]$futureResult.reason);Assert-True ([bool]$futureResult.staging_eligible) 'generic future app not staging eligible';Assert-StartNoAuthorityV010 $futureResult 'future-app';$count++

$decisionTamper=Copy-Deep $valid.decision;$decisionTamper.stage_acquisition_authorized=$true;$decisionTamper.eligibility_fingerprint=Get-CustomAppProductionExecutorStartGateSha256V010 (Get-CustomAppProductionExecutorStartEligibilityMaterialV010 $decisionTamper);$decisionTamperCheck=Test-CustomAppProductionExecutorStartEligibilityV010 $decisionTamper
Assert-False ([bool]$decisionTamperCheck.ok) 'authority-tampered eligibility accepted even with recomputed fingerprint';Assert-True ([string]$decisionTamperCheck.reason -ceq 'start-eligibility-stage_acquisition_authorized-true') 'authority tamper reason drifted';$count++

$fingerprintTamper=Copy-Deep $valid.decision;$fingerprintTamper.eligibility_fingerprint=('0'*64);$fpCheck=Test-CustomAppProductionExecutorStartEligibilityV010 $fingerprintTamper
Assert-False ([bool]$fpCheck.ok) 'eligibility fingerprint tamper accepted';Assert-True ([string]$fpCheck.reason -ceq 'start-eligibility-fingerprint-mismatch') 'fingerprint tamper reason drifted';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_EXECUTOR_START_GATE_MATRIX_PASS total='+$count)
