$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-executor-start-gate-v0.1.0/test_custom_app_production_executor_start_gate.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-stage-acquisition-admission.ps1')

function Assert-StageAdmissionNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.admission_is_authority) "$Label admission authority"
    Assert-False ([bool]$Result.stage_acquisition_authorized) "$Label stage acquisition authority"
    Assert-False ([bool]$Result.live_destination_authorized) "$Label live destination authority"
    Assert-False ([bool]$Result.apply_authorized) "$Label apply authority"
    Assert-False ([bool]$Result.executor_may_apply) "$Label executor apply authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
    Assert-True ([bool]$Result.requires_immediate_gate_rerun_by_stage_executor) "$Label immediate gate rerun requirement missing"
    Assert-True ([bool]$Result.requires_exact_stage_contract) "$Label exact stage contract requirement missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_after_stage) "$Label post-stage revalidation missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_apply) "$Label pre-apply revalidation missing"
}

function Invoke-StageAdmissionFixtureV010 {
    param($X,[DateTimeOffset]$At=$now,[byte[]]$SessionKey=$key,[AllowNull()]$Permit=$null,[AllowNull()][string]$ConsumptionId=$null)
    if($null -eq $Permit){$Permit=$X.consumption.fixture.permit}
    if([string]::IsNullOrWhiteSpace($ConsumptionId)){$ConsumptionId=[string]$X.consumption.result.consumption_id}
    $f=$X.consumption.fixture.f
    return Resolve-CustomAppProductionStageAdmissionV010 -AllowedRoot $X.store.root -StoreDirectory $X.store.store -ExpectedConsumptionId $ConsumptionId -Permit $Permit -Name $f.name -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -CurrentBaseline $f.baseline -ShadowProtocolQualification $f.shadow -LiveAttestedQualification $f.live -SessionKey $SessionKey -Now $At
}

function Assert-StageAdmissionDeniedV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly eligible"
    Assert-False ([bool]$Result.stage_acquisition_eligible) "$Label stage eligibility escaped"
    Assert-StageAdmissionNoAuthorityV010 $Result $Label
}

$count=0
$x=New-ExecutorStartFixtureV010 'stage-admission-valid'
$valid=Invoke-StageAdmissionFixtureV010 $x
Assert-True ([bool]$valid.ok) ('valid stage admission denied: '+[string]$valid.reason)
Assert-True ([bool]$valid.stage_acquisition_eligible) 'valid stage admission did not produce eligibility'
Assert-StageAdmissionNoAuthorityV010 $valid 'valid'
$check=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $valid.decision
Assert-True ([bool]$check.ok) ('valid admission decision self-check failed: '+[string]$check.reason)
Assert-True ([string]$valid.decision.qualified_executor_start_head -ceq $CustomAppProductionStageAdmissionQualifiedStartHead) 'executor-start qualification head drifted'
Assert-True ([string]$valid.decision.qualified_stage_contract_head -ceq $CustomAppProductionStageAdmissionQualifiedStageHead) 'stage-contract qualification head drifted'
$count++

$workspaceExpected=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
$workspaceActual=[IO.Path]::GetFullPath([string]$valid.decision.stage_workspace_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
Assert-True ($workspaceActual.Equals($workspaceExpected,[StringComparison]::OrdinalIgnoreCase)) 'stage admission workspace root escaped exact stage contract root'
$count++

$wrongId=Invoke-StageAdmissionFixtureV010 $x $now $key $null ('f'*64)
Assert-StageAdmissionDeniedV010 $wrongId 'wrong-consumption-id'
Assert-True ([string]$wrongId.reason -ceq 'executor-start-gate-denied:persisted-consumption-id-not-found-or-ambiguous') 'wrong consumption id reason drifted'
$count++

$wrongKey=Invoke-StageAdmissionFixtureV010 $x $now ([byte[]](33..64))
Assert-StageAdmissionDeniedV010 $wrongKey 'wrong-key'
Assert-True ([string]$wrongKey.reason -ceq 'executor-start-gate-denied:executor-start-permit-revalidation-denied:permit-hmac-mismatch') 'wrong key reason drifted'
$count++

$expired=Invoke-StageAdmissionFixtureV010 $x $now.AddMinutes(4)
Assert-StageAdmissionDeniedV010 $expired 'expired'
Assert-True ([string]$expired.reason -ceq 'executor-start-gate-denied:executor-start-permit-revalidation-denied:permit-expired') 'expired reason drifted'
$count++

$removed=New-ExecutorStartFixtureV010 'stage-admission-removed' -Nonce 'ababcdcdababcdcdababcdcdababcdcd';$removed.consumption.fixture.f.lifecycle.user_removed=$true;$removed.consumption.fixture.f.lifecycle.present=$false
$removedResult=Invoke-StageAdmissionFixtureV010 $removed
Assert-StageAdmissionDeniedV010 $removedResult 'user-removed'
Assert-True ([string]$removedResult.reason -like 'executor-start-gate-denied:executor-start-permit-revalidation-denied:permit-current-admission-denied:*') 'user removal did not fail closed'
$count++

$bindingDrift=New-ExecutorStartFixtureV010 'stage-admission-binding-drift' -Nonce 'bcbccdcdbcbccdcdbcbccdcdcdcdcdcd';$bindingDrift.consumption.fixture.f.binding.source_identity='other/repo'
$bindingDriftResult=Invoke-StageAdmissionFixtureV010 $bindingDrift
Assert-StageAdmissionDeniedV010 $bindingDriftResult 'binding-drift'
Assert-True ([string]$bindingDriftResult.reason -like 'executor-start-gate-denied:*') 'binding drift did not fail at fresh start gate'
$count++

$runtimeDrift=New-ExecutorStartFixtureV010 'stage-admission-runtime-drift' -Nonce 'cdcdababcdcdababcdcdababcdcdabab';$runtimeDrift.consumption.fixture.f.baseline.tree_sha256=('8'*64)
$runtimeDriftResult=Invoke-StageAdmissionFixtureV010 $runtimeDrift
Assert-StageAdmissionDeniedV010 $runtimeDriftResult 'runtime-drift'
Assert-True ([string]$runtimeDriftResult.reason -like 'executor-start-gate-denied:*') 'runtime drift did not fail at fresh start gate'
$count++

$future=New-ExecutorStartFixtureV010 'stage-admission-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce 'dedecdcddecdcdcddecdcdcddecdcdcd'
$futureResult=Invoke-StageAdmissionFixtureV010 $future
Assert-True ([bool]$futureResult.ok) ('generic future app stage admission denied: '+[string]$futureResult.reason)
Assert-True ([bool]$futureResult.stage_acquisition_eligible) 'generic future app not stage eligible'
Assert-StageAdmissionNoAuthorityV010 $futureResult 'future-app'
$count++

$detA=Invoke-StageAdmissionFixtureV010 $x
$detB=Invoke-StageAdmissionFixtureV010 $x
Assert-True ([bool]$detA.ok -and [bool]$detB.ok) 'deterministic admission fixtures failed'
Assert-True ([string]$detA.admission_fingerprint -ceq [string]$detB.admission_fingerprint) 'stage admission fingerprint nondeterministic for same snapshot/time'
$count++

$authTamper=Copy-Deep $valid.decision;$authTamper.stage_acquisition_authorized=$true;$authTamper.admission_fingerprint=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 $authTamper)
$authCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $authTamper
Assert-False ([bool]$authCheck.ok) 'stage authority tamper accepted with recomputed fingerprint'
Assert-True ([string]$authCheck.reason -ceq 'stage-admission-stage_acquisition_authorized-true') 'stage authority tamper reason drifted'
$count++

$liveTamper=Copy-Deep $valid.decision;$liveTamper.live_destination_authorized=$true;$liveTamper.admission_fingerprint=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 $liveTamper)
$liveCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $liveTamper
Assert-False ([bool]$liveCheck.ok) 'live destination authority tamper accepted'
Assert-True ([string]$liveCheck.reason -ceq 'stage-admission-live_destination_authorized-true') 'live authority tamper reason drifted'
$count++

$workspaceTamper=Copy-Deep $valid.decision;$workspaceTamper.stage_workspace_root=Join-Path ([IO.Path]::GetTempPath()) 'other-root';$workspaceTamper.admission_fingerprint=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 $workspaceTamper)
$workspaceCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $workspaceTamper
Assert-False ([bool]$workspaceCheck.ok) 'workspace root drift accepted with recomputed fingerprint'
Assert-True ([string]$workspaceCheck.reason -ceq 'stage-admission-workspace-root-drift') 'workspace root drift reason changed'
$count++

$expiryTamper=Copy-Deep $valid.decision;$expiryTamper.stage_eligibility_expires_at=([DateTimeOffset]::Parse([string]$expiryTamper.evaluated_at)).AddMinutes(5).ToString('o');$expiryTamper.admission_fingerprint=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 $expiryTamper)
$expiryCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $expiryTamper
Assert-False ([bool]$expiryCheck.ok) 'overlong stage eligibility accepted'
Assert-True ([string]$expiryCheck.reason -ceq 'stage-admission-time-window-invalid') 'overlong stage eligibility reason drifted'
$count++

$fpTamper=Copy-Deep $valid.decision;$fpTamper.admission_fingerprint=('0'*64)
$fpCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $fpTamper
Assert-False ([bool]$fpCheck.ok) 'stage admission fingerprint tamper accepted'
Assert-True ([string]$fpCheck.reason -ceq 'stage-admission-fingerprint-mismatch') 'stage admission fingerprint reason drifted'
$count++

$missing=Copy-Deep $valid.decision;$missing.PSObject.Properties.Remove('requires_exact_stage_contract')
$missingCheck=Test-CustomAppProductionStageAdmissionDecisionV010 $missing
Assert-False ([bool]$missingCheck.ok) 'missing exact-stage-contract field accepted'
Assert-True ([string]$missingCheck.reason -ceq 'stage-admission-required-field-missing-requires_exact_stage_contract') 'missing field reason drifted'
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_STAGE_ACQUISITION_ADMISSION_MATRIX_PASS total='+$count)
