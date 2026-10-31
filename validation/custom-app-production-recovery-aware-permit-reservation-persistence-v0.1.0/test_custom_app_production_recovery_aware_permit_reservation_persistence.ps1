$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-reservation-v0.1.0/test_custom_app_production_recovery_aware_permit_reservation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-reservation-persistence.ps1')

function Assert-RAPRPT([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAPRPF([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPRPEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPRP($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPRPPersistenceStoreV010 {
    param([Parameter(Mandatory=$true)]$R,[Parameter(Mandatory=$true)][string]$Label)
    $allowed=[string]$R.ready.f.ce.q.f.f.allowed
    $store=Join-Path $allowed ('recovery-aware-reservation-persistence-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $store -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $store 'history') -Force)
    return $store
}

function New-RAPRPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('4'*32))
    $r=New-RAPRFixtureV010 -Label ('raprp-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $reservation=Invoke-RAPRFixtureV010 -F $r
    if(-not [bool]$reservation.ok){throw ('RAPRP reservation setup failed: '+[string]$reservation.reason)}
    $store=New-RAPRPPersistenceStoreV010 -R $r -Label $Label
    return [pscustomobject]@{r=$r;reservation=$reservation;store=$store}
}

function Invoke-RAPRPFixtureV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()]$Reservation=$null,[AllowNull()]$Bundle=$null,[AllowNull()][string]$PersistenceStore=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    $Q=$F.r.ready
    if($null -eq $Reservation){$Reservation=$F.reservation}
    if($null -eq $Bundle){$Bundle=$Q.bundle}
    if([string]::IsNullOrWhiteSpace($PersistenceStore)){$PersistenceStore=[string]$F.store}
    if($At -eq [DateTimeOffset]::MinValue){$At=$Q.at}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    return Invoke-CustomAppProductionRecoveryAwarePermitReservationPersistenceV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $ctx.baseline -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -PersistenceStoreDirectory $PersistenceStore -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ReservationResult $Reservation -Now $At
}

function Assert-RAPRPNoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['receipt'] -and $null -ne $Result.receipt){$Result.receipt}else{$Result}
    foreach($f in @('session_key_persisted','session_key_exposed','permit_consumed','persistence_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')){Assert-RAPRPF ([bool]$x.$f) "$Label escaped $f"}
}
function Assert-RAPRPPersistedV010($Result,[string]$Label){
    Assert-RAPRPT ([bool]$Result.reservation_persisted) "$Label reservation not persisted"
    Assert-RAPRPT ([bool]$Result.nonce_durably_reserved) "$Label nonce not durably reserved"
    Assert-RAPRPT ([bool]$Result.permit_durably_reserved) "$Label permit not durably reserved"
    Assert-RAPRPNoAuthorityV010 $Result $Label
}

$count=0

$valid=New-RAPRPFixtureV010 -Label 'valid' -Nonce ('1'*32)
$r=Invoke-RAPRPFixtureV010 -F $valid
Assert-RAPRPT ([bool]$r.ok) ('valid persistence denied: '+[string]$r.reason)
Assert-RAPRPEq $r.reason 'recovery-aware-permit-reservation-durably-persisted-zero-authority' 'valid reason'
Assert-RAPRPPersistedV010 $r 'valid'
Assert-RAPRPT ([bool]$r.recovery_aware_persistence_revalidated) 'valid missing recovery-aware persistence revalidation'
Assert-RAPRPT ([bool]$r.receipt.write_performed) 'valid did not record first write'
Assert-RAPRPF ([bool]$r.receipt.recovered_existing_persistence) 'valid incorrectly marked recovered existing'
$rc=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $r.receipt
Assert-RAPRPT ([bool]$rc.ok) ('valid persistence receipt denied: '+[string]$rc.reason)
$count++

$reload=Read-CustomAppProductionRecoveryAwarePermitReservationStoreV010 -AllowedRoot $valid.r.ready.f.ce.q.f.f.allowed -PersistenceStoreDirectory $valid.store
Assert-RAPRPT ([bool]$reload.ok) 'reload failed'
Assert-RAPRPEq $reload.revision 1 'reload revision'
Assert-RAPRPEq @($reload.state.reservations).Count 1 'reload row count'
Assert-RAPRPEq $reload.envelope.reservation_id $valid.reservation.receipt.reservation_id 'reload reservation id'
Assert-RAPRPNoAuthorityV010 $reload 'reload'
$count++

$recover=Invoke-RAPRPFixtureV010 -F $valid -At $valid.r.ready.at.AddSeconds(10)
Assert-RAPRPT ([bool]$recover.ok) ('existing durable persistence recovery denied: '+[string]$recover.reason)
Assert-RAPRPT ([bool]$recover.receipt.recovered_existing_persistence) 'existing durable row not recognized as recovery'
Assert-RAPRPF ([bool]$recover.receipt.write_performed) 'recovery unexpectedly rewrote store'
Assert-RAPRPPersistedV010 $recover 'recovery'
$count++

$future=New-RAPRPFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$rf=Invoke-RAPRPFixtureV010 -F $future
Assert-RAPRPT ([bool]$rf.ok) ('future app persistence denied: '+[string]$rf.reason)
Assert-RAPRPEq $rf.receipt.name 'future-app' 'future name'
Assert-RAPRPPersistedV010 $rf 'future'
$count++

$expired=New-RAPRPFixtureV010 -Label 'expired' -Nonce ('3'*32)
$re=Invoke-RAPRPFixtureV010 -F $expired -At $expired.r.ready.at.AddSeconds(4)
Assert-RAPRPF ([bool]$re.ok) 'expired unpersisted reservation unexpectedly persisted'
Assert-RAPRPEq $re.reason 'reservation-persistence-window-expired-before-durable-write' 'expired reason'
Assert-RAPRPF ([bool]$re.reservation_persisted) 'expired path claimed persistence'
Assert-RAPRPNoAuthorityV010 $re 'expired'
$count++

$tamper=New-RAPRPFixtureV010 -Label 'tamper' -Nonce ('4'*32)
$badReservation=Copy-RAPRP $tamper.reservation
$badReservation.receipt.reservation_fingerprint=('0'*64)
$rt=Invoke-RAPRPFixtureV010 -F $tamper -Reservation $badReservation
Assert-RAPRPF ([bool]$rt.ok) 'fingerprint-tampered reservation receipt persisted'
Assert-RAPRPT ([string]$rt.reason -like '*reservation-receipt-invalid:*fingerprint-mismatch*') ('tamper reason '+[string]$rt.reason)
$count++

$badState=New-RAPRPFixtureV010 -Label 'badstate' -Nonce ('5'*32)
$badStateResult=Copy-RAPRP $badState.reservation
$badStateResult.next_state.production_execution_authorized=$true
$rs=Invoke-RAPRPFixtureV010 -F $badState -Reservation $badStateResult
Assert-RAPRPF ([bool]$rs.ok) 'authority-polluted next state persisted'
Assert-RAPRPT ([string]$rs.reason -like '*next-state-invalid:*') ('bad state reason '+[string]$rs.reason)
Assert-RAPRPNoAuthorityV010 $rs 'badstate'
$count++

$casA=New-RAPRPFixtureV010 -Label 'casa' -Nonce ('6'*32)
$casFirst=Invoke-RAPRPFixtureV010 -F $casA
Assert-RAPRPT ([bool]$casFirst.ok) 'CAS setup persistence failed'
$casB=New-RAPRPFixtureV010 -Label 'casb' -Nonce ('7'*32)
$casB.store=$casA.store
$casConflict=Invoke-RAPRPFixtureV010 -F $casB
Assert-RAPRPF ([bool]$casConflict.ok) 'stale CAS reservation persisted'
Assert-RAPRPEq $casConflict.reason 'reservation-persistence-store-revision-conflict' 'stale CAS reason'
Assert-RAPRPNoAuthorityV010 $casConflict 'stale CAS'
$count++

$appendBase=New-RAPRPFixtureV010 -Label 'appendbase' -Nonce ('8'*32)
$appendFirst=Invoke-RAPRPFixtureV010 -F $appendBase
Assert-RAPRPT ([bool]$appendFirst.ok) 'append first failed'
$appendNext=New-RAPRFixtureV010 -Label 'raprp-appendnext' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('9'*32)
$appendReservation=Invoke-RAPRFixtureV010 -F $appendNext -State $appendFirst.store.state -ExpectedRevision 1
Assert-RAPRPT ([bool]$appendReservation.ok) ('append reservation creation failed: '+[string]$appendReservation.reason)
$appendF=[pscustomobject]@{r=$appendNext;reservation=$appendReservation;store=$appendBase.store}
$appendSecond=Invoke-RAPRPFixtureV010 -F $appendF
Assert-RAPRPT ([bool]$appendSecond.ok) ('append second persistence failed: '+[string]$appendSecond.reason)
Assert-RAPRPEq $appendSecond.store.revision 2 'append revision'
Assert-RAPRPEq @($appendSecond.store.state.reservations).Count 2 'append row count'
Assert-RAPRPEq ((@($appendSecond.store.state.reservations)[0]|ConvertTo-Json -Depth 60 -Compress)) ((@($appendFirst.store.state.reservations)[0]|ConvertTo-Json -Depth 60 -Compress)) 'append rewrote prior row'
$count++

$badReceipt=Copy-RAPRP $r.receipt
$badReceipt.executor_may_start=$true
$badReceipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $badReceipt)
$badReceiptCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $badReceipt
Assert-RAPRPF ([bool]$badReceiptCheck.ok) 'rehashed executor-authorized persistence receipt accepted'
Assert-RAPRPT ([string]$badReceiptCheck.reason -like '*authority-escaped-executor_may_start*') ('bad receipt reason '+[string]$badReceiptCheck.reason)
$count++

$badFlags=Copy-RAPRP $recover.receipt
$badFlags.write_performed=$true
$badFlags.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $badFlags)
$badFlagsCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $badFlags
Assert-RAPRPF ([bool]$badFlagsCheck.ok) 'receipt with write+recovery both true accepted'
Assert-RAPRPEq $badFlagsCheck.reason 'reservation-persistence-receipt-write-recovery-flags-invalid' 'write/recovery flags reason'
$count++

$badEnvelope=Copy-RAPRP $r.store.envelope
$badEnvelope.permit_consumed=$true
$badEnvelope.envelope_sha256=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeMaterialV010 -Envelope $badEnvelope)
$badEnvelopeCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 -Envelope $badEnvelope
Assert-RAPRPF ([bool]$badEnvelopeCheck.ok) 'rehashed consumed persistence envelope accepted'
Assert-RAPRPT ([string]$badEnvelopeCheck.reason -like '*authority-escaped-permit_consumed*') ('bad envelope reason '+[string]$badEnvelopeCheck.reason)
$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_RESERVATION_PERSISTENCE_MATRIX_PASS total=$count"
