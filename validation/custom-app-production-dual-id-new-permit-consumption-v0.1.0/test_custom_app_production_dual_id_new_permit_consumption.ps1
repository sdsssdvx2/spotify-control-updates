$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-reservation-persistence-v0.1.0/test_custom_app_production_dual_id_new_permit_reservation_persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-executor-consumption-v0.1.0/custom-app-production-executor-consumption.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-consumption.ps1')

function Assert-DINCTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-DINCFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-DINCEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b"}}
function Copy-DINC($x){return (($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}
function Assert-DINCDenied($r,[string]$m){Assert-DINCFalse ([bool]$r.ok) "$m accepted";Assert-DINCFalse ([bool]$r.consumption_created) "$m created consumption";Assert-DINCFalse ([bool]$r.consumption_persisted) "$m persisted consumption";Assert-DINCFalse ([bool]$r.executor_may_start) "$m granted executor";Assert-DINCFalse ([bool]$r.production_mutation_authorized) "$m granted mutation"}
function Invoke-DINCV010 {
    param([Parameter(Mandatory=$true)]$P,[AllowNull()]$Persist=$null,[AllowNull()]$Issuer=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()]$State=$null,[AllowNull()]$Bundle=$null,[AllowNull()]$Baseline=$null,[AllowNull()][string]$Store=$null,[AllowNull()][string]$NewId=$null,[AllowNull()][string]$JournalId=$null,[int64]$ExpectedRevision=-1,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    $Q=$P.q;$I=$Q.i;$F=$I.f
    if($null-eq$Persist){$Persist=$script:DINCPrimaryPersist}
    if($null-eq$Issuer){$Issuer=$Q.issuer}
    if($null-eq$Permit){$Permit=$Issuer.permit}
    if($null-eq$Key){$Key=$script:DINPIKey}
    if($null-eq$State){$State=New-CustomAppProductionExecutorConsumptionStateV010}
    if($null-eq$Bundle){$Bundle=$F.q.bundle}
    if($null-eq$Baseline){$Baseline=$F.live.baseline}
    if([string]::IsNullOrWhiteSpace($Store)){$Store=$P.store}
    if([string]::IsNullOrWhiteSpace($NewId)){$NewId=[string]$F.new_id}
    if([string]::IsNullOrWhiteSpace($JournalId)){$JournalId=[string]$F.q.house.result.journal_transaction_id}
    if($ExpectedRevision-lt0){$ExpectedRevision=[int64]$State.revision}
    if($At-eq[DateTimeOffset]::MinValue){$At=$P.at.AddMilliseconds(100)}
    return Invoke-CustomAppProductionDualIdNewPermitConsumptionV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -HousekeepingResult $F.q.house.result -AllowedRoot $F.q.x.f.trust -RecoveryStoreDirectory $F.q.x.f.store -ReservationPersistenceStoreDirectory $Store -HistoricalPermitTransactionId ([string]$F.q.house.result.permit_transaction_id) -HistoricalJournalTransactionId $JournalId -NewPermitTransactionId $NewId -LocalAppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.roaming) -CurrentBaseline $Baseline -ShadowProtocolQualification $F.live.shadow -LiveAttestedQualification $F.live.live -PriorReadinessReceipt $F.prior -IssuerResult $Issuer -ReservationPersistenceResult $Persist -Permit $Permit -SessionKey $Key -ConsumptionState $State -ExpectedConsumptionRevision $ExpectedRevision -Now $At
}

if($null-eq$valid-or$null-eq$validResult){throw 'validated durable reservation parent fixture missing'}
$script:DINCPrimaryPersist=$validResult
$script:DINCPrimaryP=$valid
$count=0

$good=Invoke-DINCV010 -P $script:DINCPrimaryP
Assert-DINCTrue ([bool]$good.ok) ('valid consumption denied: '+[string]$good.reason)
Assert-DINCEq $good.reason 'dual-id-new-single-use-consumption-created-requires-durable-persistence' 'valid reason'
Assert-DINCTrue ([bool]$good.consumption_created) 'valid consumption missing'
Assert-DINCFalse ([bool]$good.consumption_persisted) 'valid consumption durably persisted unexpectedly'
Assert-DINCEq $good.receipt.new_permit_transaction_id $valid.q.i.f.new_id 'new permit ID continuity'
Assert-DINCEq $good.receipt.historical_permit_transaction_id $valid.q.i.f.q.house.result.permit_transaction_id 'historical permit ID continuity'
Assert-DINCEq $good.receipt.historical_journal_transaction_id $valid.q.i.f.q.house.result.journal_transaction_id 'historical journal ID continuity'
Assert-DINCEq $good.receipt.consumption_id $good.next_state.consumptions[0].consumption_id 'generic consumption id'
Assert-DINCEq $good.next_state.revision 1 'generic consumption revision'
$rc=Test-CustomAppProductionDualIdNewPermitConsumptionReceiptV010 -Receipt $good.receipt
Assert-DINCTrue ([bool]$rc.ok) ('valid receipt denied: '+[string]$rc.reason)
$sr=Read-CustomAppProductionDualIdNewPermitReservationStoreV010 -AllowedRoot $valid.q.i.f.q.x.f.trust -PersistenceStoreDirectory $valid.store
Assert-DINCEq $sr.revision $validResult.receipt.persisted_revision 'consumption mutated durable reservation'
$count++

$replay=Invoke-DINCV010 -P $valid -State $good.next_state -ExpectedRevision 1
Assert-DINCDenied $replay 'replay consumed reservation'
Assert-DINCTrue ([string]$replay.reason-like'*already-consumed') ('replay reason '+[string]$replay.reason)
Assert-DINCEq $replay.next_state.revision 1 'replay mutated prior state'
$count++

$wrongKey=Invoke-DINCV010 -P $valid -Key $script:DINPIWrongKey
Assert-DINCDenied $wrongKey 'wrong session key'
Assert-DINCTrue ([string]$wrongKey.reason-like'*issuer-hmac-invalid:*') ('wrong-key reason '+[string]$wrongKey.reason)
$count++

$wrongNew=Invoke-DINCV010 -P $valid -NewId (Get-DINPIANewTransactionId 'consumption-transplant')
Assert-DINCDenied $wrongNew 'new transaction ID transplant'
Assert-DINCTrue ([string]$wrongNew.reason-like'*persistence-id-mismatch-new_permit_transaction_id') ('new transaction reason '+[string]$wrongNew.reason)
$count++

$conflated=Invoke-DINCV010 -P $valid -JournalId ([string]$valid.q.i.f.q.house.result.permit_transaction_id)
Assert-DINCDenied $conflated 'three ID conflation'
Assert-DINCEq $conflated.reason 'dual-id-new-consumption-three-id-conflation' 'conflation reason'
$count++

$badPermit=Copy-DINC $valid.q.issuer.permit;$badPermit.token_id=('f'*64)
$r=Invoke-DINCV010 -P $valid -Permit $badPermit
Assert-DINCDenied $r 'permit token transplant'
Assert-DINCEq $r.reason 'dual-id-new-consumption-permit-issuer-token-mismatch' 'permit transplant reason'
$count++

$wrongRev=Invoke-DINCV010 -P $valid -ExpectedRevision 1
Assert-DINCDenied $wrongRev 'consumption compare-and-swap loser'
Assert-DINCTrue ([string]$wrongRev.reason-like'*consumption-state-revision-conflict') ('consumption revision reason '+[string]$wrongRev.reason)
$count++

$badPersistence=Copy-DINC $validResult;$badPersistence.receipt.permit_consumed=$true
$badPersistence.receipt.persistence_fingerprint=Get-CustomAppProductionDualIdNewPermitReservationPersistenceSha256V010(Get-CustomAppProductionDualIdNewPermitReservationPersistenceReceiptMaterialV010 -Receipt $badPersistence.receipt)
$r=Invoke-DINCV010 -P $valid -Persist $badPersistence
Assert-DINCDenied $r 'premature durable consumption declaration'
Assert-DINCTrue ([string]$r.reason-like'*persistence-receipt-invalid:*authority-escaped-permit_consumed') ('premature consumption reason '+[string]$r.reason)
$count++

$badPath=Join-Path $valid.q.i.f.q.x.f.trust ('missing-consumption-store-'+[Guid]::NewGuid().ToString('N'))
$r=Invoke-DINCV010 -P $valid -Store $badPath
Assert-DINCDenied $r 'missing durable store'
Assert-DINCTrue ([string]$r.reason-like'*durable-store-denied:*') ('missing store reason '+[string]$r.reason)
$count++

$lp=Get-CustomAppProductionDualIdNewPermitReservationPersistencePathsV010 -AllowedRoot $valid.q.i.f.q.x.f.trust -PersistenceStoreDirectory $valid.store
$held=Open-CustomAppProductionDualIdNewPermitReservationPersistenceLockV010 -Paths $lp
try {$r=Invoke-DINCV010 -P $valid}finally {$held.Dispose()}
Assert-DINCDenied $r 'durable lock busy'
Assert-DINCTrue ([string]$r.reason-like'*lock-busy*') ('lock reason '+[string]$r.reason)
$count++

$b=Copy-DINC $valid.q.i.f.q.bundle;$b.lifecycle.user_removed=$true
$r=Invoke-DINCV010 -P $valid -Bundle $b
Assert-DINCDenied $r 'user removed before consumption'
Assert-DINCTrue ([string]$r.reason-like'*pre-admission-denied:*') ('user removed reason '+[string]$r.reason)
$count++

$receiptTamper=Copy-DINC $good.receipt;$receiptTamper.consumption_persisted=$true
$receiptTamper.consumption_fingerprint=Get-CustomAppProductionDualIdNewPermitConsumptionSha256V010(Get-CustomAppProductionDualIdNewPermitConsumptionReceiptMaterialV010 -Receipt $receiptTamper)
$ck=Test-CustomAppProductionDualIdNewPermitConsumptionReceiptV010 -Receipt $receiptTamper
Assert-DINCFalse ([bool]$ck.ok) 'consumption persisted-authority tamper accepted'
Assert-DINCTrue ([string]$ck.reason-like'*authority-escaped-consumption_persisted') ('receipt tamper reason '+[string]$ck.reason)
$count++

if($count-ne12){throw "dual-ID new consumption matrix count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_DUAL_ID_NEW_PERMIT_CONSUMPTION_MATRIX_PASS cases=$count durable_reservation_attested=true triple_ids_pairwise_distinct=true transaction_hmac_revalidated=true generic_consumption_wire_unchanged=true single_use=true consumed_persisted=false session_key_persisted=false zero_authority=true"
