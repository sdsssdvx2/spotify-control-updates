$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-consumption-persistence-v0.1.0/test_custom_app_production_dual_id_new_permit_consumption_persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-consumption-persistence-v0.1.0/custom-app-production-recovery-aware-permit-consumption-persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-executor-start-gate-v0.1.0/custom-app-production-executor-start-gate.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-executor-start-gate.ps1')

function Assert-TDS([bool]$Yes,[string]$Why){if(-not$Yes){throw $Why}}
function Assert-TDSNot([bool]$Yes,[string]$Why){if($Yes){throw $Why}}
function Assert-TDSEq($Actual,$Expected,[string]$Why){if([string]$Actual-cne[string]$Expected){throw "$Why actual=<$Actual> expected=<$Expected>"}}
function Copy-TDS($Object){return ($Object|ConvertTo-Json -Depth 100|ConvertFrom-Json)}
function Assert-TDSDenied($Result,[string]$Why){
    Assert-TDSNot ([bool]$Result.ok) "$Why unexpectedly allowed"
    Assert-TDSNot ([bool]$Result.staging_eligible) "$Why staging eligibility escaped"
    Assert-TDSNot ([bool]$Result.executor_may_start) "$Why executor start escaped"
    Assert-TDSNot ([bool]$Result.production_mutation_authorized) "$Why mutation escaped"
}
function Invoke-TDSV010 {
    param(
        [AllowNull()]$F=$null,[AllowNull()]$Persistence=$null,[AllowNull()]$Issuer=$null,
        [AllowNull()]$Permit=$null,[AllowNull()]$Bundle=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()][string]$OldId=$null,[AllowNull()][string]$JournalId=$null,[AllowNull()][string]$NewId=$null,
        [AllowNull()][string]$Store=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue
    )
    if($null-eq$F){$F=$script:TDSValidFixture}
    if($null-eq$Persistence){$Persistence=$script:TDSPersisted}
    $p=$F.p;$i=$p.q.i;$x=$i.f;$q=$x.q
    if($null-eq$Issuer){$Issuer=$p.q.issuer}
    if($null-eq$Permit){$Permit=$Issuer.permit}
    if($null-eq$Bundle){$Bundle=$q.bundle}
    if($null-eq$Key){$Key=$script:DINPIKey}
    if([string]::IsNullOrWhiteSpace($OldId)){$OldId=[string]$q.house.result.permit_transaction_id}
    if([string]::IsNullOrWhiteSpace($JournalId)){$JournalId=[string]$q.house.result.journal_transaction_id}
    if([string]::IsNullOrWhiteSpace($NewId)){$NewId=[string]$x.new_id}
    if([string]::IsNullOrWhiteSpace($Store)){$Store=$F.store}
    if($At-eq[DateTimeOffset]::MinValue){$At=$F.at.AddMilliseconds(100)}
    $args=@{
        Name=[string]$Bundle.lifecycle.name;LifecycleRow=$Bundle.lifecycle;ProvenanceRow=$Bundle.provenance;BindingRow=$Bundle.binding
        StageResult=$Bundle.stage;ShadowResult=$Bundle.shadow;HousekeepingResult=$q.house.result
        AllowedRoot=$q.x.f.trust;RecoveryStoreDirectory=$q.x.f.store;ConsumptionStoreDirectory=$Store
        HistoricalPermitTransactionId=$OldId;HistoricalJournalTransactionId=$JournalId;NewPermitTransactionId=$NewId
        LocalAppDataRoot=[string]$q.x.f.x.fixture.q.persistence.local;AppDataRoot=[string]$q.x.f.x.fixture.q.persistence.roaming
        CurrentBaseline=$x.live.baseline;ShadowProtocolQualification=$x.live.shadow;LiveAttestedQualification=$x.live.live
        PriorReadinessReceipt=$x.prior;IssuerResult=$Issuer;ConsumptionPersistenceResult=$Persistence
        Permit=$Permit;SessionKey=$Key;Now=$At
    }
    return Resolve-DualIdNewExecutorStartGateV010 @args
}

# Inherit the exact byte-real qualified persisted-consumption fixture from #206.
# The start gate creates no new permit, transaction, reservation, stage or execution.
if($null-eq$valid-or$null-eq$first-or-not[bool]$first.ok){throw 'qualified consumption persistence fixture unavailable'}
$script:TDSValidFixture=$valid
$script:TDSPersisted=$first
$count=0

$good=Invoke-TDSV010
Assert-TDS ([bool]$good.ok) ('valid triple-ID executor start denied: '+[string]$good.reason)
Assert-TDS ([bool]$good.staging_eligible) 'staging eligibility not issued'
Assert-TDS ([bool]$good.historical_persistence_attested) 'durable history not attested'
Assert-TDS ([bool]$good.current_consumption_reloaded) 'current store not freshly reloaded'
Assert-TDS ([bool]$good.fresh_issuance_admission_revalidated) 'fresh admission not checked'
Assert-TDSNot ([bool]$good.executor_may_start) 'start gate granted start authority'
Assert-TDSNot ([bool]$good.executor_may_stage) 'start gate granted stage authority'
Assert-TDSNot ([bool]$good.production_mutation_authorized) 'start gate granted mutation authority'
$ck=Test-DualIdNewExecutorStartReceiptV010 -Receipt $good.receipt -Now $script:TDSValidFixture.at.AddMilliseconds(100)
Assert-TDS ([bool]$ck.ok) ('valid receipt denied: '+[string]$ck.reason)
Assert-TDSEq $good.receipt.consumption_id $script:TDSPersisted.receipt.consumption_id 'consumption ID'
Assert-TDSEq $good.receipt.new_permit_transaction_id $script:TDSValidFixture.p.q.i.f.new_id 'new permit ID'
Assert-TDSEq $good.receipt.pre_start_issuance_admission_fingerprint $good.receipt.post_start_issuance_admission_fingerprint 'start pre/post admission drift'
Assert-TDS ([string]$good.receipt.pre_start_issuance_admission_fingerprint-cne[string]$script:TDSPersisted.receipt.pre_persistence_admission_fingerprint) 'historical timestamped admission unexpectedly identical to fresh admission'
$count++

$again=Invoke-TDSV010
Assert-TDS ([bool]$again.ok) ('read-only repeat denied: '+[string]$again.reason)
Assert-TDSEq $again.receipt.start_fingerprint $good.receipt.start_fingerprint 'deterministic receipt'
Assert-TDSEq $again.receipt.current_consumption_store_revision $good.receipt.current_consumption_store_revision 'repeat rewrote store'
$count++

$r=Invoke-TDSV010 -NewId ('f'*64)
Assert-TDSDenied $r 'new permit transaction ID transplant'
Assert-TDSEq $r.reason 'triple-id-start-new_permit_transaction_id-mismatch' 'new ID reason'
$count++

$r=Invoke-TDSV010 -JournalId ([string]$script:TDSValidFixture.p.q.i.f.q.house.result.permit_transaction_id)
Assert-TDSDenied $r 'journal and historical permit conflated'
Assert-TDSEq $r.reason 'triple-id-start-id-conflation' 'journal conflation reason'
$count++

$r=Invoke-TDSV010 -OldId ('a'*64)
Assert-TDSDenied $r 'historical permit ID transplant'
$count++

$r=Invoke-TDSV010 -Key ([byte[]](0..31))
Assert-TDSDenied $r 'wrong ephemeral HMAC key'
Assert-TDS ([string]$r.reason-like'triple-id-start-issuer-hmac-invalid:*') ('wrong HMAC reason '+[string]$r.reason)
$count++

$badIssuer=Copy-TDS $script:TDSValidFixture.p.q.issuer
$badIssuer.receipt.transaction_binding_hmac_sha256=('0'*64)
$r=Invoke-TDSV010 -Issuer $badIssuer
Assert-TDSDenied $r 'tampered issuer HMAC receipt'
$count++

$badPermit=Copy-TDS $script:TDSValidFixture.p.q.issuer.permit
$badPermit.token_id=('0'*64)
$r=Invoke-TDSV010 -Permit $badPermit
Assert-TDSDenied $r 'transplanted permit token'
$count++

$badPersistence=Copy-TDS $script:TDSPersisted
$badPersistence.receipt.persistence_fingerprint=('0'*64)
$r=Invoke-TDSV010 -Persistence $badPersistence
Assert-TDSDenied $r 'tampered persisted receipt fingerprint'
$count++

$badSnapshot=Copy-TDS $script:TDSPersisted
$badSnapshot.persisted_snapshot.state.consumptions[0].consumption_id=('0'*64)
$r=Invoke-TDSV010 -Persistence $badSnapshot
Assert-TDSDenied $r 'tampered in-memory snapshot does not match disk'
$count++

$notThere=Join-Path ([string]$script:TDSValidFixture.p.q.i.f.q.x.f.trust) ('missing-start-store-'+[Guid]::NewGuid().ToString('N'))
$r=Invoke-TDSV010 -Store $notThere
Assert-TDSDenied $r 'missing durable historical target'
$count++

$removed=Copy-TDS $script:TDSValidFixture.p.q.i.f.q.bundle
$removed.lifecycle.user_removed=$true
$r=Invoke-TDSV010 -Bundle $removed
Assert-TDSDenied $r 'user removed before executor start'
$count++

$r=Invoke-TDSV010 -At $script:TDSValidFixture.at.AddSeconds(30)
Assert-TDSDenied $r 'expired readiness and permit'
$count++

$rehashed=Copy-TDS $good.receipt
$rehashed.executor_may_start=$true
$rehashed.start_fingerprint=Get-DualIdNewExecutorStartShaV010 (Get-DualIdNewExecutorStartMaterialV010 -Receipt $rehashed)
$c=Test-DualIdNewExecutorStartReceiptV010 -Receipt $rehashed -Now $script:TDSValidFixture.at.AddMilliseconds(100)
Assert-TDSNot ([bool]$c.ok) 'rehashed executor authority escalation accepted'
$count++

$c=Test-DualIdNewExecutorStartReceiptV010 -Receipt $good.receipt -Now $script:TDSValidFixture.at.AddSeconds(6)
Assert-TDSNot ([bool]$c.ok) 'stale start eligibility receipt accepted'
$count++

if($count-ne15){throw "triple-ID new permit executor start matrix count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_TRIPLE_ID_NEW_PERMIT_EXECUTOR_START_GATE_PASS cases=$count historical_reloaded=true generic_start_revalidated=true triple_ids_distinct=true ephemeral_hmac=true stale_and_tamper_denied=true zero_authority=true"
