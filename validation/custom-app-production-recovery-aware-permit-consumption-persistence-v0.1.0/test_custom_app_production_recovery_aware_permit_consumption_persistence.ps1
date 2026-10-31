$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-consumption-v0.1.0/test_custom_app_production_recovery_aware_permit_consumption.ps1')
. (Join-Path $root 'validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence.ps1')
. (Join-Path $root 'validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence-contract-v011.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-consumption-persistence.ps1')

function Assert-RAPCPT([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAPCPF([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPCPEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPCP($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPCPStoreV010 {
    param([Parameter(Mandatory=$true)]$F,[Parameter(Mandatory=$true)][string]$Label)
    $allowed=[string]$F.p.r.ready.f.ce.q.f.f.allowed
    $store=Join-Path $allowed ('recovery-aware-consumption-persistence-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $store -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $store 'history') -Force)
    return $store
}

function New-RAPCPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('6'*32))
    $f=New-RAPCFixtureV010 -Label ('rapcp-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $candidate=Invoke-RAPCFixtureV010 -F $f
    if(-not [bool]$candidate.ok){throw ('RAPCP consumption candidate setup failed: '+[string]$candidate.reason)}
    $store=New-RAPCPStoreV010 -F $f -Label $Label
    return [pscustomobject]@{f=$f;candidate=$candidate;store=$store}
}

function Invoke-RAPCPFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[AllowNull()]$Candidate=$null,[AllowNull()]$Bundle=$null,[AllowNull()]$Baseline=$null,
        [AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][string]$Store=$null,
        [DateTimeOffset]$At=[DateTimeOffset]::MinValue,[ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $Q=$F.f.p.r.ready
    if($null -eq $Candidate){$Candidate=$F.candidate}
    if($null -eq $Bundle){$Bundle=$Q.bundle}
    if([string]::IsNullOrWhiteSpace($Store)){$Store=[string]$F.store}
    if($At -eq [DateTimeOffset]::MinValue){$At=$Q.at.AddSeconds(11)}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    if($null -eq $Baseline){$Baseline=$ctx.baseline}
    if($null -eq $ShadowQualification){$ShadowQualification=$ctx.shadow}
    if($null -eq $LiveQualification){$LiveQualification=$ctx.live}
    return Invoke-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -ConsumptionStoreDirectory $Store -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ConsumptionResult $Candidate -Now $At -FailurePoint $FailurePoint
}

function Assert-RAPCPNoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['receipt'] -and $null -ne $Result.receipt){$Result.receipt}else{$Result}
    foreach($f in @('session_key_accepted','session_key_persisted','session_key_exposed','persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){Assert-RAPCPF ([bool]$x.$f) "$Label escaped $f"}
    foreach($f in @('requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){Assert-RAPCPT ([bool]$x.$f) "$Label missing $f"}
}
function Assert-RAPCPPersistedV010($Result,[string]$Label){
    Assert-RAPCPT ([bool]$Result.consumption_persisted) "$Label consumption not persisted"
    Assert-RAPCPT ([bool]$Result.read_after_write_verified) "$Label read-after-write not verified"
    Assert-RAPCPT ([bool]$Result.persisted_consumption_barrier_attested) "$Label persisted barrier not attested"
    Assert-RAPCPT ([bool]$Result.recovery_aware_persistence_revalidated) "$Label recovery-aware persistence not revalidated"
    Assert-RAPCPNoAuthorityV010 $Result $Label
}
function Assert-RAPCPDeniedV010($Result,[string]$Label,[bool]$ExpectPersisted=$false){
    Assert-RAPCPF ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-RAPCPEq ([bool]$Result.consumption_persisted) $ExpectPersisted "$Label persisted flag"
    Assert-RAPCPNoAuthorityV010 $Result $Label
}

$count=0

$valid=New-RAPCPFixtureV010 -Label 'valid' -Nonce ('1'*32)
$r=Invoke-RAPCPFixtureV010 -F $valid
Assert-RAPCPT ([bool]$r.ok) ('valid recovery-aware consumption persistence denied: '+[string]$r.reason)
Assert-RAPCPEq $r.reason 'recovery-aware-consumption-durably-persisted-barrier-attested-zero-authority' 'valid reason'
Assert-RAPCPPersistedV010 $r 'valid'
Assert-RAPCPT ([bool]$r.write_performed) 'valid write not recorded'
Assert-RAPCPF ([bool]$r.recovered_existing_persistence) 'valid incorrectly marked recovered'
Assert-RAPCPEq $r.receipt.persisted_revision 1 'valid persisted revision'
Assert-RAPCPEq $r.persisted_snapshot.revision 1 'valid snapshot revision'
Assert-RAPCPEq $r.persisted_snapshot.state.consumptions[-1].consumption_id $valid.candidate.receipt.consumption_id 'valid persisted consumption id'
$receiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $r.receipt
Assert-RAPCPT ([bool]$receiptCheck.ok) ('valid persistence receipt denied: '+[string]$receiptCheck.reason)
$count++

$reload=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $valid.f.p.r.ready.f.ce.q.f.f.allowed -StoreDirectory $valid.store
Assert-RAPCPT ([bool]$reload.ok) 'valid consumption store reload failed'
Assert-RAPCPEq $reload.revision 1 'reload revision'
Assert-RAPCPEq $reload.state.consumptions[-1].consumption_id $valid.candidate.receipt.consumption_id 'reload consumption id'
$reloadBarrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $reload -ExpectedConsumptionId ([string]$valid.candidate.receipt.consumption_id)
Assert-RAPCPT ([bool]$reloadBarrier.ok) ('reload persisted barrier denied: '+[string]$reloadBarrier.reason)
$count++

$recover=Invoke-RAPCPFixtureV010 -F $valid -At $valid.f.p.r.ready.at.AddSeconds(20)
Assert-RAPCPT ([bool]$recover.ok) ('lost-response exact persistence recovery denied: '+[string]$recover.reason)
Assert-RAPCPPersistedV010 $recover 'lost-response recovery'
Assert-RAPCPT ([bool]$recover.recovered_existing_persistence) 'lost-response recovery flag missing'
Assert-RAPCPF ([bool]$recover.write_performed) 'lost-response recovery rewrote store'
Assert-RAPCPEq $recover.receipt.persistence_envelope_sha256 $r.receipt.persistence_envelope_sha256 'lost-response envelope drift'
$count++

$future=New-RAPCPFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$futureR=Invoke-RAPCPFixtureV010 -F $future
Assert-RAPCPT ([bool]$futureR.ok) ('future app consumption persistence denied: '+[string]$futureR.reason)
Assert-RAPCPEq $futureR.receipt.name 'future-app' 'future app persisted name'
Assert-RAPCPPersistedV010 $futureR 'future app'
$count++

# Historical recovery: rev1 A stays attestable after unrelated B is durably appended as rev2.
$histA=New-RAPCPFixtureV010 -Label 'historical-a' -Nonce ('3'*32)
$aPersist=Invoke-RAPCPFixtureV010 -F $histA
Assert-RAPCPT ([bool]$aPersist.ok) ('historical A persistence failed: '+[string]$aPersist.reason)
$histB=New-RAPCFixtureV010 -Label 'rapcp-historical-b' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('4'*32)
$bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $aPersist.persisted_snapshot.state -ExpectedConsumptionRevision 1
Assert-RAPCPT ([bool]$bCandidate.ok) ('historical B candidate failed: '+[string]$bCandidate.reason)
$bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$histA.store}
$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier
Assert-RAPCPT ([bool]$bPersist.ok) ('historical B persistence failed: '+[string]$bPersist.reason)
Assert-RAPCPEq $bPersist.receipt.persisted_revision 2 'historical B revision'
$aRecover=Invoke-RAPCPFixtureV010 -F $histA -At $histA.f.p.r.ready.at.AddSeconds(20)
Assert-RAPCPT ([bool]$aRecover.ok) ('historical rev1 recovery denied after rev2 append: '+[string]$aRecover.reason)
Assert-RAPCPT ([bool]$aRecover.recovered_existing_persistence) 'historical rev1 recovery flag missing'
Assert-RAPCPF ([bool]$aRecover.write_performed) 'historical rev1 recovery rewrote store'
Assert-RAPCPEq $aRecover.receipt.persisted_revision 1 'historical recovered revision'
Assert-RAPCPEq $aRecover.receipt.current_store_revision_at_attestation 2 'historical current store revision evidence'
Assert-RAPCPEq $aRecover.persisted_snapshot.state.consumptions[-1].consumption_id $histA.candidate.receipt.consumption_id 'historical target snapshot id'
$count++

$stale=New-RAPCPFixtureV010 -Label 'stale' -Nonce ('5'*32)
$stale.store=$valid.store
$staleR=Invoke-RAPCPFixtureV010 -F $stale
Assert-RAPCPDeniedV010 $staleR 'stale different candidate conflict'
Assert-RAPCPT ([string]$staleR.reason -like '*existing-target-conflict*') ('stale candidate reason '+[string]$staleR.reason)
$count++

$tamperedReceipt=Copy-RAPCP $valid.candidate
$tamperedReceipt.receipt.consumption_fingerprint=('0'*64)
$tamperedR=Invoke-RAPCPFixtureV010 -F $valid -Candidate $tamperedReceipt -Store (New-RAPCPStoreV010 -F $valid.f -Label 'tampered-receipt')
Assert-RAPCPDeniedV010 $tamperedR 'fingerprint-tampered consumption candidate'
Assert-RAPCPT ([string]$tamperedR.reason -like '*candidate-invalid:*fingerprint-mismatch*') ('tampered receipt reason '+[string]$tamperedR.reason)
$count++

$tamperedState=Copy-RAPCP $valid.candidate
$tamperedState.next_state.consumptions[-1].consumption_id=('9'*64)
$tamperedStateR=Invoke-RAPCPFixtureV010 -F $valid -Candidate $tamperedState -Store (New-RAPCPStoreV010 -F $valid.f -Label 'tampered-state')
Assert-RAPCPDeniedV010 $tamperedStateR 'tampered candidate next state'
Assert-RAPCPT ([string]$tamperedStateR.reason -like '*candidate-invalid:*') ('tampered state reason '+[string]$tamperedStateR.reason)
$count++

$authorityCandidate=Copy-RAPCP $valid.candidate
$authorityCandidate.receipt.executor_may_start=$true
$authorityCandidate.receipt.consumption_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionReceiptMaterialV010 -Receipt $authorityCandidate.receipt)
$authorityCandidateR=Invoke-RAPCPFixtureV010 -F $valid -Candidate $authorityCandidate -Store (New-RAPCPStoreV010 -F $valid.f -Label 'authority-candidate')
Assert-RAPCPDeniedV010 $authorityCandidateR 'authority-polluted consumption candidate'
Assert-RAPCPT ([string]$authorityCandidateR.reason -like '*candidate-invalid:*authority-or-persistence-escaped-executor_may_start*') ('authority candidate reason '+[string]$authorityCandidateR.reason)
$count++

$removed=New-RAPCPFixtureV010 -Label 'removed' -Nonce ('6'*32)
$removedBundle=Copy-RAPCP $removed.f.p.r.ready.bundle
$removedBundle.lifecycle.user_removed=$true;$removedBundle.lifecycle.present=$false
$removedR=Invoke-RAPCPFixtureV010 -F $removed -Bundle $removedBundle
Assert-RAPCPDeniedV010 $removedR 'user removal before consumption persistence'
Assert-RAPCPT ([string]$removedR.reason -like '*pre-admission-denied:*') ('user removal persistence reason '+[string]$removedR.reason)
$count++

$drift=New-RAPCPFixtureV010 -Label 'baseline-drift' -Nonce ('7'*32)
$driftCtx=New-RAIssueLiveContextV010 -Bundle $drift.f.p.r.ready.bundle
$driftBase=Copy-RAPCP $driftCtx.baseline;$driftBase.tree_sha256=('7'*64)
$driftR=Invoke-RAPCPFixtureV010 -F $drift -Baseline $driftBase
Assert-RAPCPDeniedV010 $driftR 'baseline drift before consumption persistence'
Assert-RAPCPT ([string]$driftR.reason -like '*pre-admission-denied:*') ('baseline persistence reason '+[string]$driftR.reason)
$count++

$remoteFx=New-RAPCPFixtureV010 -Label 'remote-drift' -Nonce ('8'*32)
$remoteBundle=Copy-RAPCP $remoteFx.f.p.r.ready.bundle
$remoteBundle.binding.last_remote_tree_sha256=('b'*64);$remoteBundle.binding.binding.last_verified_remote_tree_sha256=('b'*64);$remoteBundle.binding.last_remote_commit_sha=('c'*40);$remoteBundle.binding.binding.last_verified_commit_sha=('c'*40)
[void](Sync-PromotionBundleFingerprints -Bundle $remoteBundle)
$remoteR=Invoke-RAPCPFixtureV010 -F $remoteFx -Bundle $remoteBundle
Assert-RAPCPDeniedV010 $remoteR 'remote drift before consumption persistence'
Assert-RAPCPT ([string]$remoteR.reason -like '*mismatch*' -or [string]$remoteR.reason -like '*pre-admission-denied:*') ('remote persistence reason '+[string]$remoteR.reason)
$count++

$pathFx=New-RAPCPFixtureV010 -Label 'pathescape' -Nonce ('9'*32)
$pathAllowed=[IO.Path]::GetFullPath([string]$pathFx.f.p.r.ready.f.ce.q.f.f.allowed).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$pathParent=[IO.Directory]::GetParent($pathAllowed);if($null -eq $pathParent){throw 'RAPCP path escape fixture has no parent'}
$escapeStore=Join-Path $pathParent.FullName ('rapcp-path-escape-'+[Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $escapeStore -Force);[void](New-Item -ItemType Directory -Path (Join-Path $escapeStore 'history') -Force)
$pathR=Invoke-RAPCPFixtureV010 -F $pathFx -Store $escapeStore
Assert-RAPCPDeniedV010 $pathR 'consumption persistence path escape'
Assert-RAPCPT ([string]$pathR.reason -like '*store-read-denied:*escaped allowed fixture root*') ('path escape persistence reason '+[string]$pathR.reason)
$count++

$lockFx=New-RAPCPFixtureV010 -Label 'lock' -Nonce ('a'*32)
$lockPaths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $lockFx.f.p.r.ready.f.ce.q.f.f.allowed -StoreDirectory $lockFx.store
$held=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $lockPaths
try{$lockR=Invoke-RAPCPFixtureV010 -F $lockFx}finally{$held.Dispose()}
Assert-RAPCPDeniedV010 $lockR 'consumption persistence lock contention'
Assert-RAPCPT ([string]$lockR.reason -like '*store-read-denied:*consumption-persistence-lock-busy*') ('lock contention persistence reason '+[string]$lockR.reason)
$count++

$crash=New-RAPCPFixtureV010 -Label 'crash' -Nonce ('b'*32)
$crashR=Invoke-RAPCPFixtureV010 -F $crash -FailurePoint 'after-history-before-current'
Assert-RAPCPDeniedV010 $crashR 'simulated crash after history before current'
Assert-RAPCPT ([string]$crashR.reason -like '*save-denied:simulated-crash-after-history-before-current*') ('crash reason '+[string]$crashR.reason)
$crashReadFailed=$false
try{[void](Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $crash.f.p.r.ready.f.ce.q.f.f.allowed -StoreDirectory $crash.store)}catch{$crashReadFailed=$true;Assert-RAPCPT ([string]$_.Exception.Message -like '*current-history-mismatch*') ('crash read wrong failure '+[string]$_.Exception.Message)}
Assert-RAPCPT $crashReadFailed 'simulated crash store unexpectedly read successfully'
$count++

# Force only the post-persistence fresh recovery admission to drift. The write remains durable but authority remains denied.
$postFx=New-RAPCPFixtureV010 -Label 'post-drift' -Nonce ('c'*32)
$Q=$postFx.f.p.r.ready;$bundle=$Q.bundle;$ctx=New-RAIssueLiveContextV010 -Bundle $bundle;$persistAt=$Q.at.AddSeconds(11)
$actualFresh=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $bundle.lifecycle.name -LifecycleRow $bundle.lifecycle -ProvenanceRow $bundle.provenance -BindingRow $bundle.binding -StageResult $bundle.stage -ShadowResult $bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $ctx.baseline -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -Now $persistAt
Assert-RAPCPT ([bool]$actualFresh.ok) 'post-persistence drift setup admission failed'
$script:RAPCPCall=0;$script:RAPCPFirst=$actualFresh;$script:RAPCPSecondReceipt=Copy-RAPCP $actualFresh.receipt
$script:RAPCPSecondReceipt.current_remote_commit_sha=('d'*40)
$script:RAPCPSecondReceipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $script:RAPCPSecondReceipt)
$origResolve=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock
try{
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value {
        param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours)
        $script:RAPCPCall++
        if($script:RAPCPCall -eq 1){return $script:RAPCPFirst}
        return [pscustomobject]@{ok=$true;reason='fixture-post-persistence-drift';receipt=$script:RAPCPSecondReceipt}
    }
    $postDriftR=Invoke-RAPCPFixtureV010 -F $postFx -At $persistAt
} finally {
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value $origResolve
    $script:RAPCPCall=0
}
Assert-RAPCPDeniedV010 $postDriftR 'post-persistence recovery admission drift' $true
Assert-RAPCPT ([string]$postDriftR.reason -like '*post-*remote_commit_sha-mismatch*') ('post persistence drift reason '+[string]$postDriftR.reason)
$postReload=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $postFx.f.p.r.ready.f.ce.q.f.f.allowed -StoreDirectory $postFx.store
Assert-RAPCPT ([bool]$postReload.ok -and [int64]$postReload.revision -eq 1) 'post drift durable write missing'
$postRecover=Invoke-RAPCPFixtureV010 -F $postFx -At $persistAt.AddSeconds(1)
Assert-RAPCPT ([bool]$postRecover.ok) ('post-drift retry recovery denied: '+[string]$postRecover.reason)
Assert-RAPCPT ([bool]$postRecover.recovered_existing_persistence) 'post-drift retry did not recover existing persistence'
Assert-RAPCPF ([bool]$postRecover.write_performed) 'post-drift retry rewrote persistence'
$count++

$badReceipt=Copy-RAPCP $r.receipt
$badReceipt.executor_may_start=$true
$badReceipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 -Receipt $badReceipt)
$badReceiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $badReceipt
Assert-RAPCPF ([bool]$badReceiptCheck.ok) 'rehashed executor-authorized consumption persistence receipt accepted'
Assert-RAPCPT ([string]$badReceiptCheck.reason -like '*authority-escaped-executor_may_start*') ('bad persistence receipt reason '+[string]$badReceiptCheck.reason)
$count++

$fingerprintReceipt=Copy-RAPCP $r.receipt
$fingerprintReceipt.persistence_fingerprint=('0'*64)
$fingerprintCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $fingerprintReceipt
Assert-RAPCPF ([bool]$fingerprintCheck.ok) 'fingerprint-tampered consumption persistence receipt accepted'
Assert-RAPCPEq $fingerprintCheck.reason 'recovery-aware-consumption-persistence-receipt-fingerprint-mismatch' 'persistence fingerprint reason'
$count++

$badFlags=Copy-RAPCP $recover.receipt
$badFlags.write_performed=$true
$badFlags.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 -Receipt $badFlags)
$badFlagsCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $badFlags
Assert-RAPCPF ([bool]$badFlagsCheck.ok) 'persistence receipt with write+recovery both true accepted'
Assert-RAPCPEq $badFlagsCheck.reason 'recovery-aware-consumption-persistence-receipt-write-recovery-flags-invalid' 'write/recovery flags reason'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_CONSUMPTION_PERSISTENCE_MATRIX_PASS total='+$count)
