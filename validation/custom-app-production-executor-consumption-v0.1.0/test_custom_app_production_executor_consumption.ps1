$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-permit-reservation-v0.1.0/test_custom_app_production_permit_reservation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-executor-consumption.ps1')

function Assert-NoProductionExecutorAuthority {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
    Assert-False ([bool]$Result.executor_may_stage) "$Label stage authority"
    Assert-False ([bool]$Result.executor_may_apply) "$Label apply authority"
    Assert-True ([bool]$Result.requires_atomic_compare_and_swap_persistence) "$Label CAS persistence requirement missing"
    Assert-True ([bool]$Result.requires_persisted_consumption_before_executor) "$Label persisted-consumption barrier missing"
    Assert-True ([bool]$Result.requires_fresh_permit_revalidation_at_executor_start) "$Label executor-start revalidation missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_after_stage) "$Label post-stage revalidation missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_apply) "$Label pre-apply revalidation missing"
}

function New-ConsumptionFixture {
    param([string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='66666666666666666666666666666666',[DateTimeOffset]$IssuedAt=$now)
    $f=New-ReservationFixture -Name $Name -Source $Source -Manifest $Manifest
    $permit=New-FixturePermit $f $Nonce $IssuedAt
    $reservationState=New-CustomAppProductionPermitReservationStateV010
    $reserved=Reserve-Fixture $permit $f $reservationState 0 $now
    if(-not [bool]$reserved.ok){throw ('fixture reservation failed: '+[string]$reserved.reason)}
    return [pscustomobject]@{f=$f;permit=$permit;reservation_state=$reserved.next_state;reservation_id=[string]$reserved.reservation_id}
}

function Consume-Fixture {
    param($Fixture,$ConsumptionState,[int64]$ExpectedConsumptionRevision=0,[int64]$ExpectedReservationRevision=1,[DateTimeOffset]$At=$now,[byte[]]$SessionKey=$key,[AllowNull()]$Permit=$null,[AllowNull()][string]$ReservationId=$null)
    if($null -eq $Permit){$Permit=$Fixture.permit}
    if([string]::IsNullOrWhiteSpace($ReservationId)){$ReservationId=[string]$Fixture.reservation_id}
    return Invoke-CustomAppProductionExecutorConsumptionV010 -Permit $Permit -ReservationId $ReservationId -Name $Fixture.f.name -LifecycleRow $Fixture.f.lifecycle -ProvenanceRow $Fixture.f.provenance -BindingRow $Fixture.f.binding -CurrentBaseline $Fixture.f.baseline -ShadowProtocolQualification $Fixture.f.shadow -LiveAttestedQualification $Fixture.f.live -SessionKey $SessionKey -ReservationState $Fixture.reservation_state -ExpectedReservationRevision $ExpectedReservationRevision -ConsumptionState $ConsumptionState -ExpectedConsumptionRevision $ExpectedConsumptionRevision -Now $At
}

function Assert-ConsumptionDenied {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly consumed"
    Assert-False ([bool]$Result.consumption_created) "$Label created consumption"
    Assert-False ([bool]$Result.executor_handoff_recorded) "$Label recorded executor handoff"
    Assert-NoProductionExecutorAuthority $Result $Label
}

$count=0
$fresh=New-CustomAppProductionExecutorConsumptionStateV010
$check=Test-CustomAppProductionExecutorConsumptionStateV010 $fresh
Assert-True ([bool]$check.ok) ('fresh consumption state invalid: '+[string]$check.reason)
Assert-True ([int64]$fresh.revision -eq 0 -and @($fresh.consumptions).Count -eq 0) 'fresh consumption state shape drifted'
$count++

$x=New-ConsumptionFixture
$state=New-CustomAppProductionExecutorConsumptionStateV010
$r=Consume-Fixture $x $state
Assert-True ([bool]$r.ok) ('valid consumption denied: '+[string]$r.reason)
Assert-True ([string]$r.reason -ceq 'production-reservation-consumption-recorded-persist-before-executor') 'valid consumption reason drifted'
Assert-True ([bool]$r.consumption_created -and [bool]$r.executor_handoff_recorded) 'valid consumption flags missing'
Assert-True (Test-CustomAppProductionExecutorConsumptionSha256V010 ([string]$r.consumption_id)) 'consumption id invalid'
Assert-True ([int64]$state.revision -eq 0) 'input consumption state mutated in place'
Assert-NoProductionExecutorAuthority $r 'valid-consumption'
$saved=$r.next_state
Assert-True ([bool](Test-CustomAppProductionExecutorConsumptionStateV010 $saved).ok) 'saved consumption state invalid'
$count++

$replay=Consume-Fixture $x $saved 1
Assert-ConsumptionDenied $replay 'same-reservation-replay'
Assert-True ([string]$replay.reason -ceq 'reservation-already-consumed') 'reservation replay reason drifted'
$count++

$staleConsumption=Consume-Fixture $x $saved 0
Assert-ConsumptionDenied $staleConsumption 'stale-consumption-revision'
Assert-True ([string]$staleConsumption.reason -ceq 'consumption-state-revision-conflict') 'stale consumption revision reason drifted'
$count++

$staleReservation=Consume-Fixture $x (New-CustomAppProductionExecutorConsumptionStateV010) 0 0
Assert-ConsumptionDenied $staleReservation 'stale-reservation-revision'
Assert-True ([string]$staleReservation.reason -ceq 'reservation-state-revision-conflict') 'stale reservation revision reason drifted'
$count++

$badId=Consume-Fixture $x (New-CustomAppProductionExecutorConsumptionStateV010) 0 1 $now $key $null ('f'*64)
Assert-ConsumptionDenied $badId 'unknown-reservation-id'
Assert-True ([string]$badId.reason -ceq 'reservation-not-found-or-ambiguous') 'unknown reservation reason drifted'
$count++

$otherPermit=New-FixturePermit $x.f '77777777777777777777777777777777' $now
$mismatch=Consume-Fixture $x (New-CustomAppProductionExecutorConsumptionStateV010) 0 1 $now $key $otherPermit
Assert-ConsumptionDenied $mismatch 'reservation-permit-mismatch'
Assert-True ([string]$mismatch.reason -like 'reservation-permit-mismatch-*') 'reservation/permit mismatch reason drifted'
$count++

$wrongKey=Consume-Fixture $x (New-CustomAppProductionExecutorConsumptionStateV010) 0 1 $now ([byte[]](33..64))
Assert-ConsumptionDenied $wrongKey 'wrong-key'
Assert-True ([string]$wrongKey.reason -ceq 'permit-revalidation-denied:permit-hmac-mismatch') 'wrong key reason drifted'
$count++

$removed=New-ConsumptionFixture -Nonce '88888888888888888888888888888888'
$removed.f.lifecycle.user_removed=$true;$removed.f.lifecycle.present=$false
$denyRemoved=Consume-Fixture $removed (New-CustomAppProductionExecutorConsumptionStateV010)
Assert-ConsumptionDenied $denyRemoved 'user-removed-after-reservation'
Assert-True ([string]$denyRemoved.reason -like 'permit-revalidation-denied:permit-current-admission-denied:*') 'user removal did not revalidate permit'
$count++

$drift=New-ConsumptionFixture -Nonce '99999999999999999999999999999999'
$drift.f.baseline.tree_sha256=('8'*64)
$denyDrift=Consume-Fixture $drift (New-CustomAppProductionExecutorConsumptionStateV010)
Assert-ConsumptionDenied $denyDrift 'runtime-drift-after-reservation'
Assert-True ([string]$denyDrift.reason -like 'permit-revalidation-denied:*') 'runtime drift did not revalidate permit'
$count++

$sourceDrift=New-ConsumptionFixture -Nonce 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$sourceDrift.f.provenance.source_identity='other/repo';$sourceDrift.f.provenance.source_changed=$true;$sourceDrift.f.provenance.requires_reenrollment=$true
$denySource=Consume-Fixture $sourceDrift (New-CustomAppProductionExecutorConsumptionStateV010)
Assert-ConsumptionDenied $denySource 'source-drift-after-reservation'
Assert-True ([string]$denySource.reason -like 'permit-revalidation-denied:*') 'source drift did not revalidate permit'
$count++

$exp=New-ConsumptionFixture -Nonce 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -IssuedAt $now.AddMinutes(-2)
$denyExpired=Consume-Fixture $exp (New-CustomAppProductionExecutorConsumptionStateV010) 0 1 $now.AddMinutes(2)
Assert-ConsumptionDenied $denyExpired 'expired-after-reservation'
Assert-True ([string]$denyExpired.reason -ceq 'permit-revalidation-denied:permit-expired') 'expired consumption reason drifted'
$count++

$future=New-ConsumptionFixture -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce 'cccccccccccccccccccccccccccccccc'
$futureR=Consume-Fixture $future (New-CustomAppProductionExecutorConsumptionStateV010)
Assert-True ([bool]$futureR.ok) ('generic future app consumption denied: '+[string]$futureR.reason)
Assert-NoProductionExecutorAuthority $futureR 'future-app'
$count++

$badOwner=New-CustomAppProductionExecutorConsumptionStateV010;$badOwner.managed_by='other'
$denyOwner=Consume-Fixture $x $badOwner
Assert-ConsumptionDenied $denyOwner 'bad-consumption-state-owner'
Assert-True ([string]$denyOwner.reason -ceq 'consumption-state-owner-or-schema-mismatch') 'bad consumption owner reason drifted'
$count++

$badAuthority=New-CustomAppProductionExecutorConsumptionStateV010;$badAuthority.production_execution_authorized=$true
$denyAuthority=Consume-Fixture $x $badAuthority
Assert-ConsumptionDenied $denyAuthority 'bad-consumption-state-authority'
Assert-True ([string]$denyAuthority.reason -ceq 'consumption-state-production_execution_authorized-true') 'bad consumption authority reason drifted'
$count++

$tampered=Copy-Deep $saved;$tampered.consumptions[0].consumption_id=('9'*64)
$stateTampered=Test-CustomAppProductionExecutorConsumptionStateV010 $tampered
Assert-False ([bool]$stateTampered.ok) 'tampered consumption id accepted'
Assert-True ([string]$stateTampered.reason -ceq 'consumption-row-id-mismatch') 'tampered consumption id reason drifted'
$count++

$duplicate=Copy-Deep $saved;$row2=Copy-Deep $duplicate.consumptions[0];$row2.state_revision_before=[int64]1;$row2.state_revision_after=[int64]2;$row2.consumption_id=$null;$row2.consumption_id=Get-CustomAppProductionExecutorConsumptionSha256V010 (Get-CustomAppProductionExecutorConsumptionMaterialV010 $row2);$duplicate.consumptions=@($duplicate.consumptions[0],$row2);$duplicate.revision=[int64]2
$stateDup=Test-CustomAppProductionExecutorConsumptionStateV010 $duplicate
Assert-False ([bool]$stateDup.ok) 'duplicate reservation consumption accepted'
Assert-True ([string]$stateDup.reason -ceq 'consumption-state-duplicate-reservation') 'duplicate reservation reason drifted'
$count++

$det=New-ConsumptionFixture -Nonce 'dddddddddddddddddddddddddddddddd'
$a=Consume-Fixture $det (New-CustomAppProductionExecutorConsumptionStateV010)
$b=Consume-Fixture $det (New-CustomAppProductionExecutorConsumptionStateV010)
Assert-True ([bool]$a.ok -and [bool]$b.ok) 'determinism fixtures failed'
Assert-True ([string]$a.consumption_id -ceq [string]$b.consumption_id) 'consumption id nondeterministic for same snapshot/time'
$count++

$race=New-ConsumptionFixture -Nonce 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
$raceSnapshot=New-CustomAppProductionExecutorConsumptionStateV010
$candidate1=Consume-Fixture $race $raceSnapshot
$candidate2=Consume-Fixture $race $raceSnapshot
Assert-True ([bool]$candidate1.ok -and [bool]$candidate2.ok) 'independent consumption candidates should both be locally valid'
Assert-True ([bool]$candidate1.requires_atomic_compare_and_swap_persistence -and [bool]$candidate2.requires_atomic_compare_and_swap_persistence) 'consumption race candidates did not require CAS persistence'
$loser=Consume-Fixture $race $candidate1.next_state 0
Assert-ConsumptionDenied $loser 'consumption-cas-race-loser'
Assert-True ([string]$loser.reason -ceq 'consumption-state-revision-conflict') 'consumption CAS race loser reason drifted'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_EXECUTOR_CONSUMPTION_MATRIX_PASS total='+$count)
