$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-consumption-v0.1.0/test_custom_app_production_dual_id_new_permit_consumption.ps1')
. (Join-Path $root 'validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence-contract-v011.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-consumption-persistence.ps1')

function Assert-DNCPTrue([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Assert-DNCPFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-DNCPEq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-DNCP($Object){return ($Object|ConvertTo-Json -Depth 100|ConvertFrom-Json)}
function Assert-DNCPDenied($R,[string]$Label){
    Assert-DNCPFalse ([bool]$R.ok) "$Label unexpectedly allowed"
    Assert-DNCPFalse ([bool]$R.executor_may_start) "$Label executor escaped"
    Assert-DNCPFalse ([bool]$R.production_mutation_authorized) "$Label production mutation escaped"
}
function New-DNCPFixtureV010 {
    param([string]$Label)
    $p=$script:DINCPrimaryP;$candidate=Invoke-DINCV010 -P $p
    Assert-DNCPTrue ([bool]$candidate.ok) ('candidate setup denied: '+[string]$candidate.reason)
    $base=[string]$p.q.i.f.q.x.f.trust
    $dir=Join-Path $base ('dual-id-consumption-persistence-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $dir 'history'))
    return [pscustomobject]@{p=$p;candidate=$candidate;store=$dir;at=$p.at.AddMilliseconds(200)}
}
function Invoke-DNCPV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[AllowNull()]$Candidate=$null,[AllowNull()]$Bundle=$null,[AllowNull()]$Issuer=$null,
        [AllowNull()]$ReservationPersistence=$null,[AllowNull()][string]$Store=$null,[AllowNull()][string]$NewId=$null,
        [AllowNull()][string]$JournalId=$null,[AllowNull()][byte[]]$Key=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $p=$F.p;$i=$p.q.i;$x=$i.f;$q=$x.q
    if($null-eq$Candidate){$Candidate=$F.candidate}
    if($null-eq$Bundle){$Bundle=$q.bundle}
    if($null-eq$Issuer){$Issuer=$p.q.issuer}
    if($null-eq$ReservationPersistence){$ReservationPersistence=$script:DINCPrimaryPersist}
    if([string]::IsNullOrWhiteSpace($Store)){$Store=$F.store}
    if([string]::IsNullOrWhiteSpace($NewId)){$NewId=[string]$x.new_id}
    if([string]::IsNullOrWhiteSpace($JournalId)){$JournalId=[string]$q.house.result.journal_transaction_id}
    if($At-eq[DateTimeOffset]::MinValue){$At=$F.at}
    if($null-eq$Key){$Key=$script:DINPIKey}
    return Invoke-DualIdNewConsumptionPersistenceV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -HousekeepingResult $q.house.result -AllowedRoot $q.x.f.trust -RecoveryStoreDirectory $q.x.f.store -ReservationPersistenceStoreDirectory $p.store -ConsumptionStoreDirectory $Store -HistoricalPermitTransactionId ([string]$q.house.result.permit_transaction_id) -HistoricalJournalTransactionId $JournalId -NewPermitTransactionId $NewId -LocalAppDataRoot ([string]$q.x.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$q.x.f.x.fixture.q.persistence.roaming) -CurrentBaseline $x.live.baseline -ShadowProtocolQualification $x.live.shadow -LiveAttestedQualification $x.live.live -PriorReadinessReceipt $x.prior -IssuerResult $Issuer -ReservationPersistenceResult $ReservationPersistence -ConsumptionResult $Candidate -SessionKey $Key -Now $At -FailurePoint $FailurePoint
}

$count=0
$valid=New-DNCPFixtureV010 'valid'
$first=Invoke-DNCPV010 -F $valid
Assert-DNCPTrue ([bool]$first.ok) ('first persistence denied: '+[string]$first.reason)
Assert-DNCPTrue ([bool]$first.consumption_persisted) 'first result not durably persisted'
Assert-DNCPTrue ([bool]$first.write_performed) 'first write did not occur'
Assert-DNCPFalse ([bool]$first.recovered_existing_persistence) 'first write unexpectedly recovered'
$ck=Test-DualIdNewConsumptionPersistenceReceiptV010 -Receipt $first.receipt
Assert-DNCPTrue ([bool]$ck.ok) ('first receipt invalid: '+[string]$ck.reason)
$read=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot ([string]$valid.p.q.i.f.q.x.f.trust) -StoreDirectory $valid.store
Assert-DNCPTrue ([bool]$read.ok) ('first durable read denied: '+[string]$read.reason)
Assert-DNCPEq $read.revision 1 'durable store revision'
Assert-DNCPEq $read.state.consumptions[0].consumption_id $valid.candidate.receipt.consumption_id 'durable consumption row'
$barrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $read -ExpectedConsumptionId ([string]$valid.candidate.receipt.consumption_id)
Assert-DNCPTrue ([bool]$barrier.ok) ('persisted barrier denied: '+[string]$barrier.reason)
Assert-DNCPFalse ([bool]$first.executor_may_start) 'durable barrier granted executor authority'
$count++

$repeat=Invoke-DNCPV010 -F $valid
Assert-DNCPTrue ([bool]$repeat.ok) ('idempotent restart denied: '+[string]$repeat.reason)
Assert-DNCPTrue ([bool]$repeat.recovered_existing_persistence) 'restart not recognized as recovery'
Assert-DNCPFalse ([bool]$repeat.write_performed) 'restart repeated durable append'
Assert-DNCPEq $repeat.receipt.persistence_envelope_sha256 $first.receipt.persistence_envelope_sha256 'restart envelope changed'
$count++

$wrongId=Invoke-DNCPV010 -F $valid -NewId ('f'*64)
Assert-DNCPDenied $wrongId 'new-permit-ID transplant'
Assert-DNCPEq $wrongId.reason 'consumption-new_permit_transaction_id-mismatch' 'new-permit ID reason'
$count++

$conflated=Invoke-DNCPV010 -F $valid -JournalId ([string]$valid.p.q.i.f.q.house.result.permit_transaction_id)
Assert-DNCPDenied $conflated 'historical ID conflation'
Assert-DNCPEq $conflated.reason 'transaction-id-conflation' 'conflation reason'
$count++

$bad=Copy-DNCP $valid.candidate
$bad.receipt.consumption_id=('0'*64)
$bad.receipt.consumption_fingerprint=Get-CustomAppProductionDualIdNewPermitConsumptionSha256V010(Get-CustomAppProductionDualIdNewPermitConsumptionReceiptMaterialV010 -Receipt $bad.receipt)
$r=Invoke-DNCPV010 -F $valid -Candidate $bad
Assert-DNCPDenied $r 'consumption ID transplant'
Assert-DNCPTrue ([string]$r.reason-like'*consumption-row-consumption_id-mismatch') ('consumption transplant reason '+[string]$r.reason)
$count++

$removed=Copy-DNCP $valid.p.q.i.f.q.bundle
$removed.lifecycle.user_removed=$true
$fx=New-DNCPFixtureV010 'removed'
$r=Invoke-DNCPV010 -F $fx -Bundle $removed
Assert-DNCPDenied $r 'user removed before persistence'
Assert-DNCPTrue ([string]$r.reason-like'pre-admission-denied:*') ('removed reason '+[string]$r.reason)
$count++

$lockCase=New-DNCPFixtureV010 'lock'
$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot ([string]$lockCase.p.q.i.f.q.x.f.trust) -StoreDirectory $lockCase.store
$lock=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths
try{$r=Invoke-DNCPV010 -F $lockCase}finally{$lock.Dispose()}
Assert-DNCPDenied $r 'concurrent store lock'
Assert-DNCPTrue ([string]$r.reason-like'*lock-busy*') ('lock reason '+[string]$r.reason)
$count++

$expired=New-DNCPFixtureV010 'expired'
$r=Invoke-DNCPV010 -F $expired -At $expired.at.AddSeconds(15)
Assert-DNCPDenied $r 'expired original readiness'
Assert-DNCPTrue ([string]$r.reason-like'*issuer-invalid:*') ('expired issuer reason '+[string]$r.reason)
$count++

$crash=New-DNCPFixtureV010 'history-crash'
$r=Invoke-DNCPV010 -F $crash -FailurePoint 'after-history-before-current'
Assert-DNCPDenied $r 'history-written-but-current-not-updated'
Assert-DNCPFalse ([bool]$r.consumption_persisted) 'history-only state falsely treated committed'
$count++

$badReceipt=Copy-DNCP $first.receipt
$badReceipt.executor_may_start=$true
$badReceipt.persistence_fingerprint=Get-DualIdNewConsumptionPersistenceShaV010(Get-DualIdNewConsumptionPersistenceMaterialV010 -Receipt $badReceipt)
$ck=Test-DualIdNewConsumptionPersistenceReceiptV010 -Receipt $badReceipt
Assert-DNCPFalse ([bool]$ck.ok) 'rehashed executor authority tamper accepted'
Assert-DNCPTrue ([string]$ck.reason-like'*authority-escaped-executor_may_start') ('tamper reason '+[string]$ck.reason)
$count++

$badFingerprint=Copy-DNCP $first.receipt
$badFingerprint.persistence_fingerprint=('0'*64)
$ck=Test-DualIdNewConsumptionPersistenceReceiptV010 -Receipt $badFingerprint
Assert-DNCPFalse ([bool]$ck.ok) 'fingerprint tamper accepted'
$count++

$wrongKey=New-DNCPFixtureV010 'wrong-session-key'
$r=Invoke-DNCPV010 -F $wrongKey -Key ([byte[]](0..31))
Assert-DNCPDenied $r 'issuer HMAC with wrong ephemeral session key'
Assert-DNCPTrue ([string]$r.reason-like'issuer-invalid:*') ('wrong key reason '+[string]$r.reason)
$count++

if($count-ne12){throw "dual-ID new consumption persistence matrix count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_DUAL_ID_NEW_PERMIT_CONSUMPTION_PERSISTENCE_MATRIX_PASS cases=$count triple_ids_distinct=true durable_cas=true replay_idempotent=true readback_attested=true no_session_key_persisted=true zero_authority=true"
