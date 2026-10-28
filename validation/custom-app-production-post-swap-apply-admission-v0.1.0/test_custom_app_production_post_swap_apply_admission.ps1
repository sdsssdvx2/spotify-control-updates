$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-transaction-finalization-v0.1.0/test_custom_app_production_transaction_finalization.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-post-swap-apply-admission.ps1')

function New-PostSwapApplyAdmissionFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='abababababababababababababababab')
    $f=New-FinalizationFixtureV010 -Label ('apply-admission-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $final=Invoke-FinalizationFixtureV010 $f
    if(-not [bool]$final.ok){throw ('post-swap fixture finalization failed: '+[string]$final.reason)}
    return [pscustomobject]@{f=$f;finalization=$final}
}

function Invoke-PostSwapApplyAdmissionFixtureV010 {
    param(
        $Fixture,[AllowNull()]$Permit=$null,[AllowNull()]$Finalization=$null,[AllowNull()]$Prepared=$null,[AllowNull()]$Stage=$null,[AllowNull()]$Lifecycle=$null,
        [AllowNull()]$Provenance=$null,[AllowNull()]$Binding=$null,[AllowNull()][string]$ConsumptionId=$null,[byte[]]$SessionKey=$key,[DateTimeOffset]$At=$now.AddSeconds(5),[int]$MaxAge=36
    )
    if($null -eq $Permit){$Permit=$Fixture.f.atomic.q.x.permit};if($null -eq $Finalization){$Finalization=$Fixture.finalization};if($null -eq $Prepared){$Prepared=$Fixture.f.atomic.prepared.result};if($null -eq $Stage){$Stage=$Fixture.f.atomic.q.stage.result}
    if($null -eq $Lifecycle){$Lifecycle=$Fixture.f.atomic.q.x.f.lifecycle};if($null -eq $Provenance){$Provenance=$Fixture.f.atomic.q.x.f.provenance};if($null -eq $Binding){$Binding=$Fixture.f.atomic.q.x.f.binding};if([string]::IsNullOrWhiteSpace($ConsumptionId)){$ConsumptionId=[string]$Fixture.f.atomic.q.x.consumption.consumption_id}
    return Resolve-CustomAppProductionPostSwapApplyAdmissionV010 -AllowedRoot $Fixture.f.atomic.q.x.store.root -StoreDirectory $Fixture.f.atomic.q.x.store.store -ExpectedConsumptionId $ConsumptionId -Permit $Permit -FinalizationResult $Finalization -PreparedResult $Prepared -StageExecutorResult $Stage -Name $Fixture.f.atomic.q.x.f.name -LifecycleRow $Lifecycle -ProvenanceRow $Provenance -BindingRow $Binding -SessionKey $SessionKey -LocalAppDataRoot $Fixture.f.atomic.q.persistence.local -AppDataRoot $Fixture.f.atomic.q.persistence.roaming -Now $At -MaxRemoteObservationAgeHours $MaxAge
}

function Assert-PostSwapApplyAdmissionNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.admission_is_authority) "$Label admission authority"
    Assert-False ([bool]$Result.apply_execution_authorized) "$Label apply execution authority"
    Assert-False ([bool]$Result.spicetify_apply_authorized) "$Label spicetify apply authority"
    Assert-False ([bool]$Result.additional_mutation_authorized) "$Label additional mutation authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function Assert-PostSwapApplyAdmissionDeniedV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-False ([bool]$Result.apply_eligible) "$Label unexpectedly eligible"
    Assert-PostSwapApplyAdmissionNoAuthorityV010 $Result $Label
}

$count=0
$valid=New-PostSwapApplyAdmissionFixtureV010 'valid'
$r=Invoke-PostSwapApplyAdmissionFixtureV010 $valid
Assert-True ([bool]$r.ok) ('valid post-swap apply admission denied: '+[string]$r.reason)
Assert-True ([bool]$r.apply_eligible) 'valid apply eligibility missing'
Assert-True ([bool]$r.requires_immediate_rerun_by_apply_executor) 'valid immediate rerun requirement missing'
Assert-True ([bool]$r.requires_exact_spicetify_apply_executor) 'valid exact apply executor requirement missing'
Assert-True ([bool]$r.requires_exact_rollback_on_apply_failure) 'valid exact rollback requirement missing'
Assert-PostSwapApplyAdmissionNoAuthorityV010 $r 'valid'
$check=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 -Decision $r.decision
Assert-True ([bool]$check.ok) ('valid admission decision self-check failed: '+[string]$check.reason)
$authority=Copy-Deep $r.decision;$authority.spicetify_apply_authorized=$true;$authority.admission_fingerprint=Get-CustomAppProductionPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionPostSwapApplyAdmissionMaterialV010 -Decision $authority);$authorityCheck=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 $authority;Assert-False ([bool]$authorityCheck.ok) 'authority-tampered post-swap admission accepted'
$fingerprint=Copy-Deep $r.decision;$fingerprint.admission_fingerprint=('0'*64);$fingerprintCheck=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 $fingerprint;Assert-False ([bool]$fingerprintCheck.ok) 'fingerprint-tampered post-swap admission accepted'
$count++

$future=New-PostSwapApplyAdmissionFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N '9')
$r=Invoke-PostSwapApplyAdmissionFixtureV010 $future;Assert-True ([bool]$r.ok) ('future app post-swap admission denied: '+[string]$r.reason);Assert-PostSwapApplyAdmissionNoAuthorityV010 $r 'future-app';$count++

$finalFp=New-PostSwapApplyAdmissionFixtureV010 'final-fp' -Nonce (N '8');$bad=Copy-Deep $finalFp.finalization;$bad.finalization_fingerprint=('0'*64);$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $finalFp -Finalization $bad;Assert-PostSwapApplyAdmissionDeniedV010 $r 'finalization-fingerprint-tamper';Assert-True ([string]$r.reason -like 'finalization-result-invalid:*fingerprint*') 'finalization fingerprint reason drifted';$count++

$finalAuth=New-PostSwapApplyAdmissionFixtureV010 'final-auth' -Nonce (N '7');$bad=Copy-Deep $finalAuth.finalization;$bad.spicetify_apply_authorized=$true;$bad.finalization_fingerprint=Get-CustomAppProductionTransactionFinalizationSha256V010 (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $bad);$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $finalAuth -Finalization $bad;Assert-PostSwapApplyAdmissionDeniedV010 $r 'finalization-authority-tamper';Assert-True ([string]$r.reason -like 'finalization-result-invalid:*spicetify_apply_authorized-true*') 'finalization authority reason drifted';$count++

$txn=New-PostSwapApplyAdmissionFixtureV010 'txn-reappeared' -Nonce (N '6');[IO.Directory]::CreateDirectory([string]$txn.finalization.transaction_root)|Out-Null;$r=Invoke-PostSwapApplyAdmissionFixtureV010 $txn;Assert-PostSwapApplyAdmissionDeniedV010 $r 'finalized-transaction-workspace-reappeared';Assert-True ([string]$r.reason -ceq 'finalized-transaction-workspace-reappeared') 'transaction reappearance reason drifted';$count++

$keyBad=New-PostSwapApplyAdmissionFixtureV010 'wrong-key' -Nonce (N '5');$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $keyBad -SessionKey ([byte[]](33..64));Assert-PostSwapApplyAdmissionDeniedV010 $r 'wrong-session-key';Assert-True ([string]$r.reason -like 'permit-integrity-denied:permit-hmac-mismatch') 'wrong key reason drifted';$count++

$expired=New-PostSwapApplyAdmissionFixtureV010 'expired' -Nonce (N '4');$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $expired -At $now.AddMinutes(6);Assert-PostSwapApplyAdmissionDeniedV010 $r 'permit-expired';Assert-True ([string]$r.reason -like 'permit-integrity-denied:permit-expired') 'permit expiry reason drifted';$count++

$store=New-PostSwapApplyAdmissionFixtureV010 'store-tamper' -Nonce (N '3');[IO.File]::WriteAllText((Join-Path $store.f.atomic.q.x.store.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $store;Assert-PostSwapApplyAdmissionDeniedV010 $r 'persisted-store-tamper';Assert-True ([string]$r.reason -like 'persisted-consumption-read-denied:*') 'store tamper reason drifted';$count++

$cid=New-PostSwapApplyAdmissionFixtureV010 'wrong-consumption' -Nonce (N '2');$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $cid -ConsumptionId ('0'*64);Assert-PostSwapApplyAdmissionDeniedV010 $r 'wrong-consumption-id';Assert-True ([string]$r.reason -ceq 'consumption-continuity-mismatch') 'wrong consumption reason drifted';$count++

$removed=New-PostSwapApplyAdmissionFixtureV010 'removed' -Nonce (N '1');$life=Copy-Deep $removed.f.atomic.q.x.f.lifecycle;$life.present=$false;$life.user_removed=$true;$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $removed -Lifecycle $life;Assert-PostSwapApplyAdmissionDeniedV010 $r 'user-removed';Assert-True ([string]$r.reason -ceq 'lifecycle-not-safe-current-single-location') 'user removal reason drifted';$count++

$bindingDrift=New-PostSwapApplyAdmissionFixtureV010 'binding-drift' -Nonce '12121212121212121212121212121212';$binding=Copy-Deep $bindingDrift.f.atomic.q.x.f.binding;$binding.last_remote_tree_sha256=('0'*64);$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $bindingDrift -Binding $binding;Assert-PostSwapApplyAdmissionDeniedV010 $r 'binding-drift';Assert-True ([string]$r.reason -like 'binding-denied:*' -or [string]$r.reason -like 'binding-continuity-mismatch-*') 'binding drift reason changed';$count++

$stale=New-PostSwapApplyAdmissionFixtureV010 'stale-binding' -Nonce '23232323232323232323232323232323';$binding=Copy-Deep $stale.f.atomic.q.x.f.binding;$binding.last_success=$now.AddHours(-40).ToString('o');$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $stale -Binding $binding;Assert-PostSwapApplyAdmissionDeniedV010 $r 'stale-binding';Assert-True ([string]$r.reason -ceq 'binding-observation-stale') 'stale binding reason changed';$count++

$live=New-PostSwapApplyAdmissionFixtureV010 'live-drift' -Nonce '34343434343434343434343434343434';[IO.File]::AppendAllText((Join-Path $live.f.atomic.q.x.live 'index.js'),"// post-swap-admission-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $live;Assert-PostSwapApplyAdmissionDeniedV010 $r 'live-runtime-drift';Assert-True ([string]$r.reason -ceq 'post-swap-live-runtime-not-exact-remote-stage') 'live drift reason changed';$count++

$git=New-PostSwapApplyAdmissionFixtureV010 'git-drift' -Nonce '45454545454545454545454545454545';[IO.File]::AppendAllText((Join-Path $git.f.atomic.q.x.live '.git\config'),"# post-swap-admission-git-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $git;Assert-PostSwapApplyAdmissionDeniedV010 $r 'git-drift';Assert-True ([string]$r.reason -ceq 'preserved-git-continuity-mismatch') 'git drift reason changed';$count++

$stage=New-PostSwapApplyAdmissionFixtureV010 'stage-drift' -Nonce '56565656565656565656565656565656';[IO.File]::AppendAllText((Join-Path ([string]$stage.f.atomic.prepared.result.stage_path) 'index.js'),"// retained-stage-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $stage;Assert-PostSwapApplyAdmissionDeniedV010 $r 'retained-stage-drift';Assert-True ([string]$r.reason -ceq 'retained-stage-runtime-drift') 'retained stage drift reason changed';$count++

$appBackup=New-PostSwapApplyAdmissionFixtureV010 'app-backup-drift' -Nonce '67676767676767676767676767676767';[IO.File]::AppendAllText((Join-Path ([string]$appBackup.f.atomic.prepared.result.app_backup_path) 'index.js'),"// app-backup-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $appBackup;Assert-PostSwapApplyAdmissionDeniedV010 $r 'app-backup-drift';Assert-True ([string]$r.reason -ceq 'app-rollback-backup-drift') 'app backup drift reason changed';$count++

$pBackup=New-PostSwapApplyAdmissionFixtureV010 'persistence-backup-drift' -Nonce '78787878787878787878787878787878';[IO.File]::AppendAllText((Join-Path ([string]$pBackup.f.atomic.prepared.result.persistence_backup_path) 'guard-manifest.json'),"x",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $pBackup;Assert-PostSwapApplyAdmissionDeniedV010 $r 'persistence-backup-drift';Assert-True ([string]$r.reason -like 'persistence-backup-invalid:*') 'persistence backup drift reason changed';$count++

$persist=New-PostSwapApplyAdmissionFixtureV010 'persistence-drift' -Nonce '89898989898989898989898989898989';[IO.File]::AppendAllText((Join-Path $persist.f.atomic.q.persistence.roaming 'spicetify\config-xpui.ini'),"# post-swap-admission-persistence-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostSwapApplyAdmissionFixtureV010 $persist;Assert-PostSwapApplyAdmissionDeniedV010 $r 'protected-persistence-drift';Assert-True ([string]$r.reason -ceq 'protected-persistence-drift-before-apply-admission') 'persistence drift reason changed';$count++

$prepared=New-PostSwapApplyAdmissionFixtureV010 'prepared-tamper' -Nonce '90909090909090909090909090909090';$bad=Copy-Deep $prepared.f.atomic.prepared.result;$bad.preparation_fingerprint=('0'*64);$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $prepared -Prepared $bad;Assert-PostSwapApplyAdmissionDeniedV010 $r 'prepared-result-tamper';Assert-True ([string]$r.reason -like 'prepared-result-invalid:*fingerprint*') 'prepared result tamper reason changed';$count++

$stageResult=New-PostSwapApplyAdmissionFixtureV010 'stage-result-tamper' -Nonce 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';$bad=Copy-Deep $stageResult.f.atomic.q.stage.result;$bad.result_fingerprint=('0'*64);$r=Invoke-PostSwapApplyAdmissionFixtureV010 -Fixture $stageResult -Stage $bad;Assert-PostSwapApplyAdmissionDeniedV010 $r 'stage-result-tamper';Assert-True ([string]$r.reason -like 'stage-result-invalid:*fingerprint*') 'stage result tamper reason changed';$count++

Write-Host "CUSTOM_APP_PRODUCTION_POST_SWAP_APPLY_ADMISSION_MATRIX_PASS total=$count"
