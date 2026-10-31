$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-reservation-persistence-v0.1.0/test_custom_app_production_recovery_aware_permit_reservation_persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-executor-consumption-v0.1.0/custom-app-production-executor-consumption.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-consumption.ps1')

function Assert-RAPCT([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAPCF([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPCEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPC($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPCFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('5'*32))
    $p=New-RAPRPFixtureV010 -Label ('rapc-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $persisted=Invoke-RAPRPFixtureV010 -F $p
    if(-not [bool]$persisted.ok){throw ('RAPC durable reservation setup failed: '+[string]$persisted.reason)}
    return [pscustomobject]@{p=$p;persisted=$persisted}
}

function Invoke-RAPCFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[AllowNull()]$Bundle=$null,[AllowNull()]$PersistenceResult=$null,[AllowNull()]$Permit=$null,
        [AllowNull()]$ConsumptionState=$null,[AllowNull()]$ExpectedConsumptionRevision=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,
        [AllowNull()][string]$ReservationStore=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue
    )
    $Q=$F.p.r.ready
    if($null -eq $Bundle){$Bundle=$Q.bundle}
    if($null -eq $PersistenceResult){$PersistenceResult=$F.persisted}
    if($null -eq $Permit){$Permit=$F.p.r.issuer.permit}
    if($null -eq $ConsumptionState){$ConsumptionState=New-CustomAppProductionExecutorConsumptionStateV010}
    if($null -eq $ExpectedConsumptionRevision){$ExpectedConsumptionRevision=[int64]$ConsumptionState.revision}
    if($null -eq $Key){$Key=$script:RAIssuerKey}
    if([string]::IsNullOrWhiteSpace($ReservationStore)){$ReservationStore=[string]$F.p.store}
    if($At -eq [DateTimeOffset]::MinValue){$At=$Q.at.AddSeconds(10)}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    if($null -eq $Baseline){$Baseline=$ctx.baseline}
    if($null -eq $ShadowQualification){$ShadowQualification=$ctx.shadow}
    if($null -eq $LiveQualification){$LiveQualification=$ctx.live}
    return Invoke-CustomAppProductionRecoveryAwarePermitConsumptionV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -ReservationPersistenceStoreDirectory $ReservationStore -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ReservationPersistenceResult $PersistenceResult -Permit $Permit -SessionKey $Key -ConsumptionState $ConsumptionState -ExpectedConsumptionRevision ([int64]$ExpectedConsumptionRevision) -Now $At
}

function Assert-RAPCNoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['receipt'] -and $null -ne $Result.receipt){$Result.receipt}else{$Result}
    foreach($f in @('consumption_persisted','session_key_persisted','session_key_exposed','consumption_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){Assert-RAPCF ([bool]$x.$f) "$Label escaped $f"}
    foreach($f in @('requires_atomic_compare_and_swap_persistence','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){Assert-RAPCT ([bool]$x.$f) "$Label missing $f"}
}
function Assert-RAPCDeniedV010($Result,[string]$Label){Assert-RAPCF ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RAPCF ([bool]$Result.consumption_created) "$Label created consumption";Assert-RAPCF ([bool]$Result.single_use_consumption_candidate_created) "$Label created consumption candidate";Assert-RAPCNoAuthorityV010 $Result $Label}

$count=0

$valid=New-RAPCFixtureV010 -Label 'valid' -Nonce ('1'*32)
$r=Invoke-RAPCFixtureV010 -F $valid
Assert-RAPCT ([bool]$r.ok) ('valid recovery-aware consumption denied: '+[string]$r.reason)
Assert-RAPCEq $r.reason 'recovery-aware-single-use-consumption-created-requires-atomic-persistence-before-executor' 'valid reason'
Assert-RAPCT ([bool]$r.reservation_persistence_attested) 'valid reservation persistence not attested'
Assert-RAPCT ([bool]$r.historical_reservation_envelope_attested) 'valid historical envelope not attested'
Assert-RAPCT ([bool]$r.fresh_recovery_admission_revalidated) 'valid fresh recovery admission missing'
Assert-RAPCT ([bool]$r.consumption_created -and [bool]$r.single_use_consumption_candidate_created) 'valid consumption candidate missing'
Assert-RAPCF ([bool]$r.consumption_persisted) 'valid consumption unexpectedly persisted'
Assert-RAPCEq $r.next_state.revision 1 'valid next consumption revision'
Assert-RAPCNoAuthorityV010 $r 'valid'
$receiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 -Receipt $r.receipt
Assert-RAPCT ([bool]$receiptCheck.ok) ('valid consumption receipt denied: '+[string]$receiptCheck.reason)
Assert-RAPCF ([bool]$r.receipt.PSObject.Properties['session_key']) 'raw session key leaked into receipt'
$count++

$future=New-RAPCFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$futureR=Invoke-RAPCFixtureV010 -F $future
Assert-RAPCT ([bool]$futureR.ok) ('future app recovery-aware consumption denied: '+[string]$futureR.reason)
Assert-RAPCEq $futureR.receipt.name 'future-app' 'future app name'
Assert-RAPCNoAuthorityV010 $futureR 'future app'
$count++

# A later durable reservation for another app must not invalidate an earlier durable reservation.
# The consumer must attest the exact historical envelope named by persisted_revision, not only current.json.
$hist=New-RAPCFixtureV010 -Label 'historical-first' -Nonce ('3'*32)
$appendNext=New-RAPRFixtureV010 -Label 'rapc-historical-second' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('4'*32)
$appendReservation=Invoke-RAPRFixtureV010 -F $appendNext -State $hist.persisted.store.state -ExpectedRevision 1
Assert-RAPCT ([bool]$appendReservation.ok) ('historical append reservation failed: '+[string]$appendReservation.reason)
$appendCarrier=[pscustomobject]@{r=$appendNext;reservation=$appendReservation;store=$hist.p.store}
$appendPersist=Invoke-RAPRPFixtureV010 -F $appendCarrier
Assert-RAPCT ([bool]$appendPersist.ok) ('historical append persistence failed: '+[string]$appendPersist.reason)
Assert-RAPCEq $appendPersist.store.revision 2 'historical append store revision'
$histR=Invoke-RAPCFixtureV010 -F $hist
Assert-RAPCT ([bool]$histR.ok) ('historical durable reservation denied after later append: '+[string]$histR.reason)
Assert-RAPCEq $histR.receipt.persisted_reservation_revision 1 'historical persisted revision'
Assert-RAPCEq $histR.receipt.current_reservation_store_revision 2 'historical current revision'
Assert-RAPCT ([bool]$histR.receipt.historical_reservation_envelope_attested) 'historical envelope attestation missing'
$count++

$replay=Invoke-RAPCFixtureV010 -F $valid -ConsumptionState $r.next_state -ExpectedConsumptionRevision 1
Assert-RAPCDeniedV010 $replay 'same reservation replay'
Assert-RAPCT ([string]$replay.reason -like '*reservation-already-consumed*') ('replay reason '+[string]$replay.reason)
$count++

$stale=Invoke-RAPCFixtureV010 -F $valid -ConsumptionState $r.next_state -ExpectedConsumptionRevision 0
Assert-RAPCDeniedV010 $stale 'stale consumption revision'
Assert-RAPCT ([string]$stale.reason -like '*consumption-state-revision-conflict*') ('stale reason '+[string]$stale.reason)
$count++

$wrongKey=Invoke-RAPCFixtureV010 -F $valid -Key $script:RAIssuerWrongKey
Assert-RAPCDeniedV010 $wrongKey 'wrong session key'
Assert-RAPCT ([string]$wrongKey.reason -like '*permit-invalid:*hmac-mismatch*') ('wrong key reason '+[string]$wrongKey.reason)
$count++

$removed=Copy-RAPC $valid.p.r.ready.bundle
$removed.lifecycle.user_removed=$true;$removed.lifecycle.present=$false
$removedR=Invoke-RAPCFixtureV010 -F $valid -Bundle $removed
Assert-RAPCDeniedV010 $removedR 'user removal after durable reservation'
Assert-RAPCT ([string]$removedR.reason -like '*pre-admission-denied:*') ('user removal reason '+[string]$removedR.reason)
$count++

$validCtx=New-RAIssueLiveContextV010 -Bundle $valid.p.r.ready.bundle
$driftBase=Copy-RAPC $validCtx.baseline;$driftBase.tree_sha256=('7'*64)
$driftR=Invoke-RAPCFixtureV010 -F $valid -Baseline $driftBase
Assert-RAPCDeniedV010 $driftR 'baseline drift after durable reservation'
Assert-RAPCT ([string]$driftR.reason -like '*pre-admission-denied:*') ('baseline drift reason '+[string]$driftR.reason)
$count++

$remote=Copy-RAPC $valid.p.r.ready.bundle
$remote.binding.last_remote_tree_sha256=('b'*64);$remote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$remote.binding.last_remote_commit_sha=('c'*40);$remote.binding.binding.last_verified_commit_sha=('c'*40)
[void](Sync-PromotionBundleFingerprints -Bundle $remote)
$remoteR=Invoke-RAPCFixtureV010 -F $valid -Bundle $remote
Assert-RAPCDeniedV010 $remoteR 'remote drift after durable reservation'
Assert-RAPCT ([string]$remoteR.reason -like '*mismatch*' -or [string]$remoteR.reason -like '*pre-admission-denied:*') ('remote drift reason '+[string]$remoteR.reason)
$count++

$expiredR=Invoke-RAPCFixtureV010 -F $valid -At $valid.p.r.ready.at.AddMinutes(2)
Assert-RAPCDeniedV010 $expiredR 'expired permit after durable reservation'
Assert-RAPCT ([string]$expiredR.reason -like '*permit-expired*') ('expired permit reason '+[string]$expiredR.reason)
$count++

$badEnvelopeResult=Copy-RAPC $valid.persisted
$badEnvelopeResult.receipt.persistence_envelope_sha256=('0'*64)
$badEnvelopeResult.receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $badEnvelopeResult.receipt)
$badEnvelopeR=Invoke-RAPCFixtureV010 -F $valid -PersistenceResult $badEnvelopeResult
Assert-RAPCDeniedV010 $badEnvelopeR 'tampered durable envelope identity'
Assert-RAPCT ([string]$badEnvelopeR.reason -like '*persistence-persistence_envelope_sha256-mismatch*') ('bad envelope reason '+[string]$badEnvelopeR.reason)
$count++

$badRevisionResult=Copy-RAPC $valid.persisted
$badRevisionResult.receipt.persisted_revision=[int64]99
$badRevisionResult.receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $badRevisionResult.receipt)
$badRevisionR=Invoke-RAPCFixtureV010 -F $valid -PersistenceResult $badRevisionResult
Assert-RAPCDeniedV010 $badRevisionR 'missing historical reservation revision'
Assert-RAPCT ([string]$badRevisionR.reason -like '*persisted-revision-not-present*') ('bad historical revision reason '+[string]$badRevisionR.reason)
$count++

$authorityPersistence=Copy-RAPC $valid.persisted
$authorityPersistence.receipt.executor_may_start=$true
$authorityPersistence.receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $authorityPersistence.receipt)
$authorityR=Invoke-RAPCFixtureV010 -F $valid -PersistenceResult $authorityPersistence
Assert-RAPCDeniedV010 $authorityR 'authority-polluted reservation persistence receipt'
Assert-RAPCT ([string]$authorityR.reason -like '*persistence-receipt-invalid:*authority-escaped-executor_may_start*') ('authority persistence reason '+[string]$authorityR.reason)
$count++

$pathAllowed=[IO.Path]::GetFullPath([string]$valid.p.r.ready.f.ce.q.f.f.allowed).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$pathParent=[IO.Directory]::GetParent($pathAllowed);if($null -eq $pathParent){throw 'RAPC path escape fixture has no parent'}
$escapeStore=Join-Path $pathParent.FullName ('rapc-consume-escape-'+[Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $escapeStore);[void](New-Item -ItemType Directory -Force -Path (Join-Path $escapeStore 'history'))
$pathR=Invoke-RAPCFixtureV010 -F $valid -ReservationStore $escapeStore
Assert-RAPCDeniedV010 $pathR 'reservation store path escape'
Assert-RAPCT ([string]$pathR.reason -like '*durable-reservation-denied:*escaped allowed root*') ('path escape reason '+[string]$pathR.reason)
$count++

$lockPaths=Get-CustomAppProductionRecoveryAwarePermitReservationPersistencePathsV010 -AllowedRoot $valid.p.r.ready.f.ce.q.f.f.allowed -PersistenceStoreDirectory $valid.p.store
$held=Open-CustomAppProductionRecoveryAwarePermitReservationPersistenceLockV010 -Paths $lockPaths
try{$lockR=Invoke-RAPCFixtureV010 -F $valid}finally{$held.Dispose()}
Assert-RAPCDeniedV010 $lockR 'reservation store lock contention'
Assert-RAPCT ([string]$lockR.reason -like '*reservation-store-lock-busy*') ('lock contention reason '+[string]$lockR.reason)
$count++

$badConsumptionState=New-CustomAppProductionExecutorConsumptionStateV010;$badConsumptionState.production_execution_authorized=$true
$badConsumptionR=Invoke-RAPCFixtureV010 -F $valid -ConsumptionState $badConsumptionState
Assert-RAPCDeniedV010 $badConsumptionR 'authority-polluted consumption state'
Assert-RAPCT ([string]$badConsumptionR.reason -like '*production_execution_authorized-true*') ('bad consumption state reason '+[string]$badConsumptionR.reason)
$count++

# Force only the post-consumption recovery-aware admission to drift.
$Q=$valid.p.r.ready;$bundle=$Q.bundle;$ctx=New-RAIssueLiveContextV010 -Bundle $bundle;$consumeAt=$Q.at.AddSeconds(10)
$actualFresh=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $bundle.lifecycle.name -LifecycleRow $bundle.lifecycle -ProvenanceRow $bundle.provenance -BindingRow $bundle.binding -StageResult $bundle.stage -ShadowResult $bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $ctx.baseline -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -Now $consumeAt
Assert-RAPCT ([bool]$actualFresh.ok) 'post-consumption drift setup admission failed'
$script:RAPCCall=0;$script:RAPCFirst=$actualFresh;$script:RAPCSecondReceipt=Copy-RAPC $actualFresh.receipt
$script:RAPCSecondReceipt.current_remote_commit_sha=('d'*40)
$script:RAPCSecondReceipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $script:RAPCSecondReceipt)
$origResolve=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock
try{
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value {
        param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours)
        $script:RAPCCall++
        if($script:RAPCCall -eq 1){return $script:RAPCFirst}
        return [pscustomobject]@{ok=$true;reason='fixture-post-consumption-drift';receipt=$script:RAPCSecondReceipt}
    }
    $postDriftR=Invoke-RAPCFixtureV010 -F $valid -At $consumeAt
} finally {
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value $origResolve
    $script:RAPCCall=0
}
Assert-RAPCDeniedV010 $postDriftR 'post-consumption recovery admission drift'
Assert-RAPCT ([string]$postDriftR.reason -like '*post-*remote_commit_sha-mismatch*') ('post drift reason '+[string]$postDriftR.reason)
Assert-RAPCEq $postDriftR.next_state.revision 0 'post drift leaked consumption candidate state'
$count++

$authorityReceipt=Copy-RAPC $r.receipt;$authorityReceipt.executor_may_start=$true
$authorityReceipt.consumption_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionReceiptMaterialV010 -Receipt $authorityReceipt)
$authorityReceiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 -Receipt $authorityReceipt
Assert-RAPCF ([bool]$authorityReceiptCheck.ok) 'rehashed executor-authorized consumption receipt accepted'
Assert-RAPCT ([string]$authorityReceiptCheck.reason -like '*authority-or-persistence-escaped-executor_may_start*') ('authority receipt reason '+[string]$authorityReceiptCheck.reason)
$count++

$fingerprintReceipt=Copy-RAPC $r.receipt;$fingerprintReceipt.consumption_fingerprint=('0'*64)
$fingerprintCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 -Receipt $fingerprintReceipt
Assert-RAPCF ([bool]$fingerprintCheck.ok) 'fingerprint-tampered recovery-aware consumption receipt accepted'
Assert-RAPCEq $fingerprintCheck.reason 'recovery-aware-consumption-receipt-fingerprint-mismatch' 'fingerprint tamper reason'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_CONSUMPTION_MATRIX_PASS total='+$count)
