$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-executor-start-gate-v0.1.0/test_custom_app_production_recovery_aware_permit_executor_start_gate.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-stage-acquisition-admission.ps1')

function Assert-RASA-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RASA-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RASA-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RASA($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function Invoke-RASA-FixtureV010 {
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
    return Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -ConsumptionStoreDirectory $ConsumptionStore -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $PersistenceResult -Permit $Permit -SessionKey $Key -Now $At
}

function Assert-RASA-NoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['receipt'] -and $null -ne $Result.receipt){$Result.receipt}else{$Result}
    foreach($f in @('session_key_persisted','session_key_exposed','admission_is_authority','stage_acquisition_authorized','live_destination_authorized','apply_authorized','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){Assert-RASA-False ([bool]$x.$f) "$Label escaped $f"}
    foreach($f in @('requires_immediate_gate_rerun_by_stage_executor','requires_exact_stage_contract','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){Assert-RASA-True ([bool]$x.$f) "$Label missing $f"}
}
function Assert-RASA-DeniedV010($Result,[string]$Label){Assert-RASA-False ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RASA-False ([bool]$Result.stage_acquisition_eligible) "$Label leaked stage eligibility";Assert-RASA-NoAuthorityV010 $Result $Label}

$count=0

$valid=New-RAESFixtureV010 -Label 'rasa-valid' -Nonce ('1'*32)
$at=$valid.p.f.p.r.ready.at.AddSeconds(12)
$r=Invoke-RASA-FixtureV010 -F $valid -At $at
Assert-RASA-True ([bool]$r.ok) ('valid recovery-aware stage admission denied: '+[string]$r.reason)
Assert-RASA-Eq $r.reason 'recovery-aware-persisted-consumption-stage-acquisition-eligible-zero-authority' 'valid reason'
Assert-RASA-True ([bool]$r.stage_acquisition_eligible) 'valid stage eligibility missing'
Assert-RASA-True ([bool]$r.recovery_aware_executor_start_revalidated -and [bool]$r.stage_binding_attested -and [bool]$r.stage_workspace_bound) 'valid attestation flags missing'
Assert-RASA-NoAuthorityV010 $r 'valid'
$rc=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $r.receipt -Now $at.AddMilliseconds(1)
Assert-RASA-True ([bool]$rc.ok) ('valid stage receipt denied: '+[string]$rc.reason)
Assert-RASA-False ([bool]$r.receipt.PSObject.Properties['session_key']) 'raw session key leaked into stage admission receipt'
Assert-RASA-Eq $r.receipt.qualified_recovery_aware_executor_start_head $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStartHead 'start lineage'
Assert-RASA-Eq $r.receipt.qualified_stage_contract_head $CustomAppProductionRecoveryAwarePermitStageAdmissionQualifiedStageHead 'stage lineage'
$count++

$workspaceExpected=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$workspaceActual=[IO.Path]::GetFullPath([string]$r.receipt.stage_workspace_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
Assert-RASA-True ($workspaceActual.Equals($workspaceExpected,[StringComparison]::OrdinalIgnoreCase)) 'stage workspace root escaped exact stage contract root'
$count++

$future=New-RAESFixtureV010 -Label 'rasa-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$futureR=Invoke-RASA-FixtureV010 -F $future
Assert-RASA-True ([bool]$futureR.ok) ('generic future app stage admission denied: '+[string]$futureR.reason)
Assert-RASA-Eq $futureR.receipt.name 'future-app' 'future app stage name'
Assert-RASA-NoAuthorityV010 $futureR 'future app'
$count++

# Durable historical consumption revision 1 must remain stage-admission eligible after unrelated revision 2 is appended.
$histA=New-RAESFixtureV010 -Label 'rasa-historical-a' -Nonce ('3'*32)
$histB=New-RAPCFixtureV010 -Label 'rasa-historical-b' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('4'*32)
$bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $histA.persisted.persisted_snapshot.state -ExpectedConsumptionRevision 1 -At $histA.p.f.p.r.ready.at.AddSeconds(13)
Assert-RASA-True ([bool]$bCandidate.ok) ('historical B candidate failed: '+[string]$bCandidate.reason)
$bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$histA.p.store}
$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier -At $histA.p.f.p.r.ready.at.AddSeconds(14)
Assert-RASA-True ([bool]$bPersist.ok) ('historical B persistence failed: '+[string]$bPersist.reason)
Assert-RASA-Eq $bPersist.receipt.persisted_revision 2 'historical B persisted revision'
$histR=Invoke-RASA-FixtureV010 -F $histA -At $histA.p.f.p.r.ready.at.AddSeconds(15)
Assert-RASA-True ([bool]$histR.ok) ('historical rev1 stage admission denied after rev2 append: '+[string]$histR.reason)
Assert-RASA-Eq $histR.receipt.historical_consumption_envelope_sha256 $histA.persisted.receipt.persistence_envelope_sha256 'historical envelope continuity'
Assert-RASA-NoAuthorityV010 $histR 'historical rev1'
$count++

$wrongKey=Invoke-RASA-FixtureV010 -F $valid -Key ([byte[]](33..64))
Assert-RASA-DeniedV010 $wrongKey 'wrong key'
Assert-RASA-True ([string]$wrongKey.reason -like '*pre-start-denied:*permit-hmac-mismatch*') ('wrong key reason '+[string]$wrongKey.reason)
$count++

$expired=Invoke-RASA-FixtureV010 -F $valid -At $valid.p.f.p.r.ready.at.AddMinutes(2)
Assert-RASA-DeniedV010 $expired 'expired permit'
Assert-RASA-True ([string]$expired.reason -like '*pre-start-denied:*permit-expired*') ('expired reason '+[string]$expired.reason)
$count++

$removed=New-RAESFixtureV010 -Label 'rasa-removed' -Nonce ('5'*32)
$removedBundle=Copy-RASA $removed.p.f.p.r.ready.bundle
$removedBundle.lifecycle.user_removed=$true;$removedBundle.lifecycle.present=$false
$removedR=Invoke-RASA-FixtureV010 -F $removed -Bundle $removedBundle
Assert-RASA-DeniedV010 $removedR 'user removal before stage acquisition'
Assert-RASA-True ([string]$removedR.reason -like '*pre-start-denied:*') ('user removal reason '+[string]$removedR.reason)
$count++

$baselineFx=New-RAESFixtureV010 -Label 'rasa-baseline-drift' -Nonce ('6'*32)
$baseCtx=New-RAIssueLiveContextV010 -Bundle $baselineFx.p.f.p.r.ready.bundle
$badBaseline=Copy-RASA $baseCtx.baseline;$badBaseline.tree_sha256=('8'*64)
$baselineR=Invoke-RASA-FixtureV010 -F $baselineFx -Baseline $badBaseline
Assert-RASA-DeniedV010 $baselineR 'baseline drift before stage acquisition'
Assert-RASA-True ([string]$baselineR.reason -like '*pre-start-denied:*') ('baseline drift reason '+[string]$baselineR.reason)
$count++

$bindingFx=New-RAESFixtureV010 -Label 'rasa-binding-drift' -Nonce ('7'*32)
$bindingBundle=Copy-RASA $bindingFx.p.f.p.r.ready.bundle
$bindingBundle.binding.source_identity='other/repo'
$bindingR=Invoke-RASA-FixtureV010 -F $bindingFx -Bundle $bindingBundle
Assert-RASA-DeniedV010 $bindingR 'stage binding drift'
$count++

$authTamper=Copy-RASA $r.receipt
$authTamper.stage_acquisition_authorized=$true
$authTamper.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $authTamper)
$authCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $authTamper -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$authCheck.ok) 'rehashed stage-authorized admission receipt accepted'
Assert-RASA-True ([string]$authCheck.reason -like '*authority-escaped-stage_acquisition_authorized*') ('stage authority tamper reason '+[string]$authCheck.reason)
$count++

$liveTamper=Copy-RASA $r.receipt
$liveTamper.live_destination_authorized=$true
$liveTamper.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $liveTamper)
$liveCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $liveTamper -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$liveCheck.ok) 'rehashed live-destination-authorized admission receipt accepted'
$count++

$workspaceTamper=Copy-RASA $r.receipt
$workspaceTamper.stage_workspace_root=Join-Path ([IO.Path]::GetTempPath()) 'other-stage-root'
$workspaceTamper.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $workspaceTamper)
$workspaceCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $workspaceTamper -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$workspaceCheck.ok) 'workspace root drift accepted with recomputed fingerprint'
Assert-RASA-Eq $workspaceCheck.reason 'recovery-aware-stage-admission-workspace-root-drift' 'workspace drift reason'
$count++

$expiryTamper=Copy-RASA $r.receipt
$expiryTamper.stage_eligibility_expires_at=([DateTimeOffset]::Parse([string]$expiryTamper.evaluated_at)).AddMinutes(1).ToString('o')
$expiryTamper.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptMaterialV010 -Receipt $expiryTamper)
$expiryCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $expiryTamper -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$expiryCheck.ok) 'overlong stage eligibility accepted'
Assert-RASA-Eq $expiryCheck.reason 'recovery-aware-stage-admission-window-invalid' 'overlong stage eligibility reason'
$count++

$fpTamper=Copy-RASA $r.receipt;$fpTamper.admission_fingerprint=('0'*64)
$fpCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $fpTamper -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$fpCheck.ok) 'stage admission fingerprint tamper accepted'
Assert-RASA-Eq $fpCheck.reason 'recovery-aware-stage-admission-fingerprint-mismatch' 'fingerprint tamper reason'
$count++

$missing=Copy-RASA $r.receipt;$missing.PSObject.Properties.Remove('requires_exact_stage_contract')
$missingCheck=Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 -Receipt $missing -Now $at.AddMilliseconds(1)
Assert-RASA-False ([bool]$missingCheck.ok) 'missing exact-stage-contract field accepted'
Assert-RASA-Eq $missingCheck.reason 'recovery-aware-stage-admission-receipt-field-missing-requires_exact_stage_contract' 'missing exact stage contract reason'
$count++

$detA=Invoke-RASA-FixtureV010 -F $valid -At $at
$detB=Invoke-RASA-FixtureV010 -F $valid -At $at
Assert-RASA-True ([bool]$detA.ok -and [bool]$detB.ok) 'deterministic stage admission fixtures failed'
Assert-RASA-Eq $detA.receipt.admission_fingerprint $detB.receipt.admission_fingerprint 'stage admission fingerprint nondeterministic for same snapshot/time'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_STAGE_ACQUISITION_ADMISSION_MATRIX_PASS total='+$count)
