$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-consumption-persistence-v0.1.0/test_custom_app_production_recovery_aware_permit_consumption_persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-executor-start-gate-v0.1.0/custom-app-production-executor-start-gate.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-executor-start-gate.ps1')

function Assert-RAEST([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAESF([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAESEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAES($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAESFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('7'*32))
    $p=New-RAPCPFixtureV010 -Label ('raes-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $persisted=Invoke-RAPCPFixtureV010 -F $p
    if(-not [bool]$persisted.ok){throw ('RAES consumption persistence setup failed: '+[string]$persisted.reason)}
    return [pscustomobject]@{p=$p;persisted=$persisted}
}

function Invoke-RAESFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[AllowNull()]$PersistenceResult=$null,[AllowNull()]$Bundle=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][string]$ConsumptionStore=$null,
        [DateTimeOffset]$At=[DateTimeOffset]::MinValue
    )
    $Q=$F.p.f.p.r.ready
    if($null -eq $PersistenceResult){$PersistenceResult=$F.persisted}
    if($null -eq $Bundle){$Bundle=$Q.bundle}
    if($null -eq $Permit){$Permit=$F.p.f.p.r.issuer.permit}
    if($null -eq $Key){$Key=$script:RAIssuerKey}
    if([string]::IsNullOrWhiteSpace($ConsumptionStore)){$ConsumptionStore=[string]$F.p.store}
    if($At -eq [DateTimeOffset]::MinValue){$At=$Q.at.AddSeconds(12)}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    if($null -eq $Baseline){$Baseline=$ctx.baseline}
    if($null -eq $ShadowQualification){$ShadowQualification=$ctx.shadow}
    if($null -eq $LiveQualification){$LiveQualification=$ctx.live}
    return Resolve-CustomAppProductionRecoveryAwarePermitExecutorStartGateV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -ConsumptionStoreDirectory $ConsumptionStore -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $PersistenceResult -Permit $Permit -SessionKey $Key -Now $At
}

function Assert-RAESNoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['receipt'] -and $null -ne $Result.receipt){$Result.receipt}else{$Result}
    foreach($f in @('session_key_persisted','session_key_exposed','eligibility_is_authority','stage_acquisition_authorized','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){Assert-RAESF ([bool]$x.$f) "$Label escaped $f"}
    foreach($f in @('requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){Assert-RAEST ([bool]$x.$f) "$Label missing $f"}
}
function Assert-RAESDeniedV010($Result,[string]$Label){Assert-RAESF ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RAESF ([bool]$Result.staging_eligible) "$Label leaked staging eligibility";Assert-RAESNoAuthorityV010 $Result $Label}

$count=0

$valid=New-RAESFixtureV010 -Label 'valid' -Nonce ('1'*32)
$at=$valid.p.f.p.r.ready.at.AddSeconds(12)
$r=Invoke-RAESFixtureV010 -F $valid -At $at
Assert-RAEST ([bool]$r.ok) ('valid recovery-aware executor start denied: '+[string]$r.reason)
Assert-RAESEq $r.reason 'recovery-aware-persisted-consumption-freshly-revalidated-staging-eligible-zero-authority' 'valid reason'
Assert-RAEST ([bool]$r.staging_eligible) 'valid staging eligibility missing'
Assert-RAEST ([bool]$r.persisted_consumption_attested -and [bool]$r.historical_consumption_envelope_attested -and [bool]$r.fresh_recovery_admission_revalidated) 'valid attestation flags missing'
Assert-RAEST ([bool]$r.receipt.session_key_accepted) 'valid session key acceptance not recorded'
Assert-RAESNoAuthorityV010 $r 'valid'
$rc=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $r.receipt -Now $at.AddMilliseconds(1)
Assert-RAEST ([bool]$rc.ok) ('valid start receipt denied: '+[string]$rc.reason)
Assert-RAESF ([bool]$r.receipt.PSObject.Properties['session_key']) 'raw session key leaked into start receipt'
$count++

$future=New-RAESFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$futureR=Invoke-RAESFixtureV010 -F $future
Assert-RAEST ([bool]$futureR.ok) ('future app recovery-aware executor start denied: '+[string]$futureR.reason)
Assert-RAESEq $futureR.receipt.name 'future-app' 'future app start name'
Assert-RAESNoAuthorityV010 $futureR 'future app'
$count++

# A lost persistence response recovered from disk must remain a valid executor-start input.
$lost=New-RAESFixtureV010 -Label 'lost-response' -Nonce ('3'*32)
$lostRecovered=Invoke-RAPCPFixtureV010 -F $lost.p -At $lost.p.f.p.r.ready.at.AddSeconds(20)
Assert-RAEST ([bool]$lostRecovered.ok -and [bool]$lostRecovered.recovered_existing_persistence -and -not [bool]$lostRecovered.write_performed) 'lost-response persistence recovery setup failed'
$lostR=Invoke-RAESFixtureV010 -F $lost -PersistenceResult $lostRecovered -At $lost.p.f.p.r.ready.at.AddSeconds(21)
Assert-RAEST ([bool]$lostR.ok) ('lost-response persistence start denied: '+[string]$lostR.reason)
Assert-RAESNoAuthorityV010 $lostR 'lost response'
$count++

# Historical consumption rev1 stays start-eligible after an unrelated app appends rev2.
$histA=New-RAESFixtureV010 -Label 'historical-a' -Nonce ('4'*32)
$histB=New-RAPCFixtureV010 -Label 'raes-historical-b' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('5'*32)
$bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $histA.persisted.persisted_snapshot.state -ExpectedConsumptionRevision 1 -At $histA.p.f.p.r.ready.at.AddSeconds(13)
Assert-RAEST ([bool]$bCandidate.ok) ('historical B candidate failed: '+[string]$bCandidate.reason)
$bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$histA.p.store}
$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier -At $histA.p.f.p.r.ready.at.AddSeconds(14)
Assert-RAEST ([bool]$bPersist.ok) ('historical B persistence failed: '+[string]$bPersist.reason)
Assert-RAESEq $bPersist.receipt.persisted_revision 2 'historical B persisted revision'
$histR=Invoke-RAESFixtureV010 -F $histA -At $histA.p.f.p.r.ready.at.AddSeconds(15)
Assert-RAEST ([bool]$histR.ok) ('historical rev1 executor start denied after rev2 append: '+[string]$histR.reason)
Assert-RAESEq $histR.receipt.persisted_consumption_revision 1 'historical rev1 persisted revision'
Assert-RAESEq $histR.receipt.current_consumption_store_revision 2 'historical rev1 current store revision evidence'
Assert-RAEST ([bool]$histR.receipt.historical_consumption_envelope_attested) 'historical consumption envelope attestation missing'
Assert-RAESNoAuthorityV010 $histR 'historical rev1'
$count++

$wrongKey=Invoke-RAESFixtureV010 -F $valid -Key ([byte[]](33..64))
Assert-RAESDeniedV010 $wrongKey 'wrong key'
Assert-RAEST ([string]$wrongKey.reason -like '*core-denied:*permit-hmac-mismatch*') ('wrong key reason '+[string]$wrongKey.reason)
$count++

$expired=Invoke-RAESFixtureV010 -F $valid -At $valid.p.f.p.r.ready.at.AddMinutes(2)
Assert-RAESDeniedV010 $expired 'expired permit'
Assert-RAEST ([string]$expired.reason -like '*core-denied:*permit-expired*') ('expired permit reason '+[string]$expired.reason)
$count++

$removed=New-RAESFixtureV010 -Label 'removed' -Nonce ('6'*32)
$removedBundle=Copy-RAES $removed.p.f.p.r.ready.bundle
$removedBundle.lifecycle.user_removed=$true;$removedBundle.lifecycle.present=$false
$removedR=Invoke-RAESFixtureV010 -F $removed -Bundle $removedBundle
Assert-RAESDeniedV010 $removedR 'user removal before executor start'
Assert-RAEST ([string]$removedR.reason -like '*pre-admission-denied:*') ('user removal reason '+[string]$removedR.reason)
$count++

$baselineFx=New-RAESFixtureV010 -Label 'baseline-drift' -Nonce ('7'*32)
$baseCtx=New-RAIssueLiveContextV010 -Bundle $baselineFx.p.f.p.r.ready.bundle
$badBaseline=Copy-RAES $baseCtx.baseline;$badBaseline.tree_sha256=('8'*64)
$baselineR=Invoke-RAESFixtureV010 -F $baselineFx -Baseline $badBaseline
Assert-RAESDeniedV010 $baselineR 'baseline drift before executor start'
Assert-RAEST ([string]$baselineR.reason -like '*pre-admission-denied:*') ('baseline drift reason '+[string]$baselineR.reason)
$count++

$remoteFx=New-RAESFixtureV010 -Label 'remote-drift' -Nonce ('8'*32)
$remoteBundle=Copy-RAES $remoteFx.p.f.p.r.ready.bundle
$remoteBundle.binding.last_remote_tree_sha256=('b'*64);$remoteBundle.binding.binding.last_verified_remote_tree_sha256=('b'*64);$remoteBundle.binding.last_remote_commit_sha=('c'*40);$remoteBundle.binding.binding.last_verified_commit_sha=('c'*40)
[void](Sync-PromotionBundleFingerprints -Bundle $remoteBundle)
$remoteR=Invoke-RAESFixtureV010 -F $remoteFx -Bundle $remoteBundle
Assert-RAESDeniedV010 $remoteR 'remote drift before executor start'
Assert-RAEST ([string]$remoteR.reason -like '*pre-admission-denied:*' -or [string]$remoteR.reason -like '*mismatch*') ('remote drift reason '+[string]$remoteR.reason)
$count++

# A persistence receipt cannot gain executor authority even with a recomputed fingerprint.
$badPersistence=Copy-RAES $valid.persisted
$badPersistence.receipt.executor_may_start=$true
$badPersistence.receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 -Receipt $badPersistence.receipt)
$badPersistenceR=Invoke-RAESFixtureV010 -F $valid -PersistenceResult $badPersistence
Assert-RAESDeniedV010 $badPersistenceR 'rehashed authority-polluted persistence receipt'
Assert-RAEST ([string]$badPersistenceR.reason -like '*persistence-receipt-invalid:*authority-escaped-executor_may_start*') ('authority persistence reason '+[string]$badPersistenceR.reason)
$count++

$badFingerprint=Copy-RAES $valid.persisted
$badFingerprint.receipt.persistence_fingerprint=('0'*64)
$badFingerprintR=Invoke-RAESFixtureV010 -F $valid -PersistenceResult $badFingerprint
Assert-RAESDeniedV010 $badFingerprintR 'fingerprint-tampered persistence receipt'
Assert-RAEST ([string]$badFingerprintR.reason -like '*persistence-receipt-invalid:*fingerprint-mismatch*') ('persistence fingerprint reason '+[string]$badFingerprintR.reason)
$count++

# The in-memory persisted snapshot is not trusted without exact durable historical target equality.
$badSnapshot=Copy-RAES $valid.persisted
$badSnapshot.persisted_snapshot.state.consumptions[-1].consumption_id=('9'*64)
$badSnapshot.persisted_snapshot.envelope.state=$badSnapshot.persisted_snapshot.state
$badSnapshotR=Invoke-RAESFixtureV010 -F $valid -PersistenceResult $badSnapshot
Assert-RAESDeniedV010 $badSnapshotR 'tampered persisted snapshot'
Assert-RAEST ([string]$badSnapshotR.reason -like '*snapshot-barrier-denied:*' -or [string]$badSnapshotR.reason -like '*durable-target-denied:*') ('snapshot tamper reason '+[string]$badSnapshotR.reason)
$count++

# Exclusive consumption-store lock must fail closed during durable target re-attestation.
$lockFx=New-RAESFixtureV010 -Label 'lock' -Nonce ('9'*32)
$lockPaths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $lockFx.p.f.p.r.ready.f.ce.q.f.f.allowed -StoreDirectory $lockFx.p.store
$held=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $lockPaths
try{$lockR=Invoke-RAESFixtureV010 -F $lockFx}finally{$held.Dispose()}
Assert-RAESDeniedV010 $lockR 'executor-start consumption persistence lock contention'
Assert-RAEST ([string]$lockR.reason -like '*durable-target-denied:*lock-busy*') ('lock contention reason '+[string]$lockR.reason)
$count++

# Force only the post-start recovery admission fingerprint to drift while continuity fields remain exact.
$driftFx=New-RAESFixtureV010 -Label 'post-admission-drift' -Nonce ('a'*32)
$driftQ=$driftFx.p.f.p.r.ready
$driftAt=$driftQ.at.AddSeconds(12)
$driftCtx=New-RAIssueLiveContextV010 -Bundle $driftQ.bundle
$actualFresh=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $driftQ.bundle.lifecycle.name -LifecycleRow $driftQ.bundle.lifecycle -ProvenanceRow $driftQ.bundle.provenance -BindingRow $driftQ.bundle.binding -StageResult $driftQ.bundle.stage -ShadowResult $driftQ.bundle.shadow -RetirementResumeResult $driftQ.resume.result -CurrentBaseline $driftCtx.baseline -ShadowProtocolQualification $driftCtx.shadow -LiveAttestedQualification $driftCtx.live -AllowedRoot $driftQ.f.ce.q.f.f.allowed -StoreDirectory $driftQ.f.ce.q.f.f.store -ExpectedTransactionId ([string]$driftQ.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $driftQ.f.ce.q.f.f.q.persistence.local -AppDataRoot $driftQ.f.ce.q.f.f.q.persistence.roaming -Now $driftAt
Assert-RAEST ([bool]$actualFresh.ok) 'post-start drift fresh setup failed'
$script:RAESAdmissionCall=0
$script:RAESFirstAdmission=$actualFresh
$script:RAESSecondReceipt=Copy-RAES $actualFresh.receipt
$script:RAESSecondReceipt.readiness_fingerprint=('e'*64)
$script:RAESSecondReceipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $script:RAESSecondReceipt)
$origAdmission=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock
try {
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value {
        param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours)
        $script:RAESAdmissionCall++
        if($script:RAESAdmissionCall -eq 1){return $script:RAESFirstAdmission}
        return [pscustomobject]@{ok=$true;reason='fixture-post-start-admission-drift';receipt=$script:RAESSecondReceipt}
    }
    $postDriftR=Invoke-RAESFixtureV010 -F $driftFx -At $driftAt
} finally {
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value $origAdmission
    $script:RAESAdmissionCall=0
}
Assert-RAESDeniedV010 $postDriftR 'post-start recovery admission drift'
Assert-RAESEq $postDriftR.reason 'recovery-aware-executor-start-admission-drift-during-start-gate' 'post-start admission drift reason'
$count++

# Wrapper receipt itself remains zero-authority even if an attacker recomputes the fingerprint.
$authorityReceipt=Copy-RAES $r.receipt
$authorityReceipt.stage_acquisition_authorized=$true
$authorityReceipt.start_fingerprint=Get-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 (Get-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptMaterialV010 -Receipt $authorityReceipt)
$authorityCheck=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $authorityReceipt -Now $at.AddMilliseconds(1)
Assert-RAESF ([bool]$authorityCheck.ok) 'rehashed stage-authorized start receipt accepted'
Assert-RAESEq $authorityCheck.reason 'recovery-aware-executor-start-receipt-authority-escaped-stage_acquisition_authorized' 'start authority tamper reason'
$count++

$fingerprintReceipt=Copy-RAES $r.receipt
$fingerprintReceipt.start_fingerprint=('0'*64)
$fingerprintCheck=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $fingerprintReceipt -Now $at.AddMilliseconds(1)
Assert-RAESF ([bool]$fingerprintCheck.ok) 'fingerprint-tampered executor-start receipt accepted'
Assert-RAESEq $fingerprintCheck.reason 'recovery-aware-executor-start-receipt-fingerprint-mismatch' 'start fingerprint tamper reason'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_EXECUTOR_START_MATRIX_PASS total='+$count)
