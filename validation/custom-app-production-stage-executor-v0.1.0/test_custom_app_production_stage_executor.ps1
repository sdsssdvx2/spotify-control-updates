$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-stage-acquisition-admission-v0.1.0/test_custom_app_production_stage_acquisition_admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-stage-executor.ps1')

function Assert-ProductionStageNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.result_is_authority) "$Label result authority"
    Assert-False ([bool]$Result.apply_authorized) "$Label apply authority"
    Assert-False ([bool]$Result.live_destination_authorized) "$Label live destination authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_apply) "$Label pre-apply revalidation requirement missing"
}

function Write-ProductionStageRuntimeV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ManifestName,[Parameter(Mandatory=$true)][string]$VersionText)
    [IO.Directory]::CreateDirectory($Path)|Out-Null
    [IO.File]::WriteAllText((Join-Path $Path 'index.js'),("console.log('"+$VersionText+"');`n"),[Text.UTF8Encoding]::new($false))
    $manifest=([ordered]@{name=$ManifestName}|ConvertTo-Json -Compress)
    [IO.File]::WriteAllText((Join-Path $Path 'manifest.json'),($manifest+"`n"),[Text.UTF8Encoding]::new($false))
}

function New-ProductionStageExecutorFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='abababababababababababababababab')
    $base=Join-Path $env:RUNNER_TEMP ('custom-app-production-stage-executor-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    $live=Join-Path $base 'live';$remote=Join-Path $base 'remote-template'
    [IO.Directory]::CreateDirectory($base)|Out-Null
    Write-ProductionStageRuntimeV010 -Path $live -ManifestName $Manifest -VersionText ($Name+'-live-v1')
    Write-ProductionStageRuntimeV010 -Path $remote -ManifestName $Manifest -VersionText ($Name+'-remote-v2')
    $liveBaseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live
    $remoteBaseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $remote
    if(-not $liveBaseline.installable -or -not $remoteBaseline.installable -or [string]$liveBaseline.tree_sha256 -ceq [string]$remoteBaseline.tree_sha256){throw 'stage executor fixture baseline construction failed'}

    $f=New-ReservationFixture -Name $Name -Source $Source -Manifest $Manifest
    $f.lifecycle.locations=@([string]$live)
    $f.baseline=$liveBaseline
    $f.binding.last_local_tree_sha256=[string]$liveBaseline.tree_sha256
    $f.binding.last_local_manifest_name=$Manifest
    $f.binding.last_remote_tree_sha256=[string]$remoteBaseline.tree_sha256
    $f.binding.binding.last_verified_local_tree_sha256=[string]$liveBaseline.tree_sha256
    $f.binding.binding.last_verified_remote_tree_sha256=[string]$remoteBaseline.tree_sha256
    $f.binding.binding.manifest_name=$Manifest

    $permit=New-FixturePermit $f $Nonce $now
    if($null -eq $permit){throw 'stage executor fixture permit creation failed'}
    $reservationState=New-CustomAppProductionPermitReservationStateV010
    $reserved=Reserve-Fixture $permit $f $reservationState 0 $now
    if(-not [bool]$reserved.ok){throw ('stage executor fixture reservation failed: '+[string]$reserved.reason)}
    $store=New-PersistenceStoreFixtureV011 ('stage-executor-'+$Label)
    $consumed=Invoke-CustomAppProductionExecutorConsumptionV010 -Permit $permit -ReservationId ([string]$reserved.reservation_id) -Name $Name -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -CurrentBaseline $f.baseline -ShadowProtocolQualification $f.shadow -LiveAttestedQualification $f.live -SessionKey $key -ReservationState $reserved.next_state -ExpectedReservationRevision 1 -ConsumptionState $store.read.state -ExpectedConsumptionRevision 0 -Now $now
    if(-not [bool]$consumed.ok){throw ('stage executor fixture consumption failed: '+[string]$consumed.reason)}
    $persisted=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $store.root -StoreDirectory $store.store -NextState $consumed.next_state -ExpectedCurrentRevision 0 -Now $now
    if(-not [bool]$persisted.ok){throw ('stage executor fixture persistence failed: '+[string]$persisted.reason)}
    return [pscustomobject]@{base=$base;live=$live;remote=$remote;live_baseline=$liveBaseline;remote_baseline=$remoteBaseline;f=$f;permit=$permit;reservation=$reserved;consumption=$consumed;store=$store;persisted=$persisted}
}

$script:ProductionStageMockMode='valid'
$script:ProductionStageMockInvocationCount=0
$script:ProductionStageMockFixture=$null

function Invoke-CustomAppStageAcquisitionV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$BindingRow)
    $script:ProductionStageMockInvocationCount++
    if($script:ProductionStageMockMode -ceq 'throw'){throw 'fixture-stage-acquisition-throw'}
    if($null -eq $script:ProductionStageMockFixture){throw 'fixture-stage-context-null'}
    $x=$script:ProductionStageMockFixture
    $check=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$check.ok){throw ('fixture-stage-binding-denied:'+[string]$check.reason)}
    $workspace=New-CustomAppStageWorkspaceV010;$stage=Join-Path $workspace 'stage'
    Write-ProductionStageRuntimeV010 -Path $stage -ManifestName ([string]$check.manifest_name) -VersionText ($Name+'-remote-v2')
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage
    $result=[pscustomobject]@{
        schema=$CustomAppStageAcquisitionSchema;managed_by=$CustomAppStageWorkspaceManagedBy;status='staged-verified';name=$Name;source_identity=[string]$check.source
        github_repo_id=[int64]$check.repo_id;surface_kind=[string]$check.surface;commit_sha=[string]$check.commit_sha;remote_tree_sha256=[string]$check.remote_tree_sha256
        binding_fingerprint=[string]$check.binding_fingerprint;binding_last_success=[string]$check.last_success;workspace_path=$workspace;stage_path=$stage
        archive_sha256=(Get-CustomAppProductionStageExecutorSha256V010 ('fixture-archive|'+[string]$check.source+'|'+[string]$check.commit_sha));stage_baseline=$baseline
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    switch($script:ProductionStageMockMode){
        'authority' {$result.mutation_authorized=$true}
        'result-tree-drift' {$result.remote_tree_sha256=('9'*64)}
        'stage-missing' {[IO.Directory]::Delete($stage,$true)}
        'mutate-live' {[IO.File]::AppendAllText((Join-Path $x.live 'index.js'),"// live drift`n",[Text.UTF8Encoding]::new($false))}
        'mutate-binding' {$BindingRow.source_identity='other/repo'}
        'tamper-store' {[IO.File]::WriteAllText((Join-Path $x.store.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false))}
    }
    return $result
}

function Invoke-ProductionStageFixtureV010 {
    param($X,[string]$Mode='valid',[DateTimeOffset]$At=$now,[DateTimeOffset]$PostAt=$now.AddSeconds(1),[byte[]]$SessionKey=$key)
    $script:ProductionStageMockMode=$Mode;$script:ProductionStageMockFixture=$X;$script:ProductionStageMockInvocationCount=0
    return Invoke-CustomAppProductionStageExecutorV010 -AllowedRoot $X.store.root -StoreDirectory $X.store.store -ExpectedConsumptionId ([string]$X.consumption.consumption_id) -Permit $X.permit -Name $X.f.name -LifecycleRow $X.f.lifecycle -ProvenanceRow $X.f.provenance -BindingRow $X.f.binding -CurrentBaseline $X.f.baseline -ShadowProtocolQualification $X.f.shadow -LiveAttestedQualification $X.f.live -SessionKey $SessionKey -Now $At -PostStageNow $PostAt
}

function Assert-ProductionStageDeniedV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-ProductionStageNoAuthorityV010 $Result $Label
    Assert-False ([bool]$Result.post_stage_revalidated) "$Label unexpectedly post-stage revalidated"
}

$count=0
$validFixture=New-ProductionStageExecutorFixtureV010 'valid'
$valid=Invoke-ProductionStageFixtureV010 $validFixture
Assert-True ([bool]$valid.ok) ('valid production stage denied: '+[string]$valid.reason)
Assert-True ([bool]$valid.stage_performed -and [bool]$valid.post_stage_revalidated) 'valid stage/post-stage flags missing'
Assert-True ([bool]$valid.stage_workspace_retained_for_pre_apply -and [bool]$valid.requires_cleanup_if_not_promoted) 'valid stage retention contract missing'
Assert-ProductionStageNoAuthorityV010 $valid 'valid'
Assert-True ($script:ProductionStageMockInvocationCount -eq 1) 'valid staging invoked exact stage function more than once'
Assert-True (Test-Path -LiteralPath ([string]$valid.workspace_path) -PathType Container) 'valid retained workspace missing'
$validCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $valid.result
Assert-True ([bool]$validCheck.ok) ('valid result self-check failed: '+[string]$validCheck.reason)
$freshAfter=Get-CustomAppLocalRuntimeBaseline -Name $validFixture.f.name -AppPath $validFixture.live
Assert-True ([string]$freshAfter.tree_sha256 -ceq [string]$validFixture.live_baseline.tree_sha256) 'valid isolated stage changed live runtime'
$clean=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath ([string]$valid.workspace_path);Assert-True ([bool]$clean.ok) 'valid retained workspace cleanup failed';Assert-False (Test-Path -LiteralPath ([string]$valid.workspace_path)) 'valid retained workspace remained after explicit cleanup'
$count++

$preDenied=New-ProductionStageExecutorFixtureV010 'pre-denied' -Nonce 'bcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc'
$preResult=Invoke-ProductionStageFixtureV010 $preDenied 'valid' $now $now.AddSeconds(1) ([byte[]](33..64))
Assert-ProductionStageDeniedV010 $preResult 'pre-stage-wrong-key';Assert-True ([string]$preResult.reason -like 'pre-stage-admission-denied:*permit-hmac-mismatch*') 'pre-stage wrong key reason drifted';Assert-True ($script:ProductionStageMockInvocationCount -eq 0) 'stage invoked despite pre-stage denial';$count++

$throwFixture=New-ProductionStageExecutorFixtureV010 'throw' -Nonce 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd'
$throwResult=Invoke-ProductionStageFixtureV010 $throwFixture 'throw'
Assert-ProductionStageDeniedV010 $throwResult 'stage-throw';Assert-True ([string]$throwResult.reason -ceq 'stage-acquisition-failed:fixture-stage-acquisition-throw') 'stage throw reason drifted';Assert-True ($script:ProductionStageMockInvocationCount -eq 1) 'stage throw invocation count drifted';$count++

$treeFixture=New-ProductionStageExecutorFixtureV010 'tree-drift' -Nonce 'dededededededededededededededede'
$treeResult=Invoke-ProductionStageFixtureV010 $treeFixture 'result-tree-drift'
Assert-ProductionStageDeniedV010 $treeResult 'stage-result-tree-drift';Assert-True ([string]$treeResult.reason -ceq 'stage-result-denied:stage-result-admission-mismatch-remote_tree_sha256') 'stage result tree drift reason changed';Assert-True ([bool]$treeResult.cleanup_attempted -and [bool]$treeResult.cleanup_ok) 'stage result tree drift was not cleaned';Assert-False (Test-Path -LiteralPath ([string]$treeResult.workspace_path)) 'stage result tree drift workspace remained';$count++

$authorityFixture=New-ProductionStageExecutorFixtureV010 'authority' -Nonce 'efefefefefefefefefefefefefefefef'
$authorityResult=Invoke-ProductionStageFixtureV010 $authorityFixture 'authority'
Assert-ProductionStageDeniedV010 $authorityResult 'stage-result-authority';Assert-True ([string]$authorityResult.reason -ceq 'stage-result-denied:stage-result-authority-drift') 'stage result authority reason drifted';Assert-True ([bool]$authorityResult.cleanup_ok) 'authority-drift stage cleanup failed';$count++

$missingFixture=New-ProductionStageExecutorFixtureV010 'stage-missing' -Nonce '12121212121212121212121212121212'
$missingResult=Invoke-ProductionStageFixtureV010 $missingFixture 'stage-missing'
Assert-ProductionStageDeniedV010 $missingResult 'stage-directory-missing';Assert-True ([string]$missingResult.reason -ceq 'stage-result-denied:stage-result-workspace-or-stage-missing') 'stage missing reason drifted';Assert-True ([bool]$missingResult.cleanup_ok) 'missing stage workspace cleanup failed';$count++

$liveFixture=New-ProductionStageExecutorFixtureV010 'live-drift' -Nonce '23232323232323232323232323232323'
$liveResult=Invoke-ProductionStageFixtureV010 $liveFixture 'mutate-live'
Assert-ProductionStageDeniedV010 $liveResult 'live-drift-during-stage';Assert-True ([string]$liveResult.reason -ceq 'post-stage-live-revalidation-denied:fresh-live-tree-changed-during-staging') 'live drift reason changed';Assert-True ([bool]$liveResult.cleanup_ok) 'live drift stage cleanup failed';Assert-False (Test-Path -LiteralPath ([string]$liveResult.workspace_path)) 'live drift workspace remained';$count++

$bindingFixture=New-ProductionStageExecutorFixtureV010 'binding-drift' -Nonce '34343434343434343434343434343434'
$bindingResult=Invoke-ProductionStageFixtureV010 $bindingFixture 'mutate-binding'
Assert-ProductionStageDeniedV010 $bindingResult 'binding-drift-during-stage';Assert-True ([string]$bindingResult.reason -like 'post-stage-admission-denied:*') 'binding drift did not fail at post-stage admission';Assert-True ([bool]$bindingResult.cleanup_ok) 'binding drift stage cleanup failed';$count++

$storeFixture=New-ProductionStageExecutorFixtureV010 'store-tamper' -Nonce '45454545454545454545454545454545'
$storeResult=Invoke-ProductionStageFixtureV010 $storeFixture 'tamper-store'
Assert-ProductionStageDeniedV010 $storeResult 'store-tamper-during-stage';Assert-True ([string]$storeResult.reason -like 'post-stage-admission-denied:*persisted-consumption-read-denied*') 'store tamper did not fail at post-stage admission';Assert-True ([bool]$storeResult.cleanup_ok) 'store tamper stage cleanup failed';$count++

$expiryFixture=New-ProductionStageExecutorFixtureV010 'post-expiry' -Nonce '56565656565656565656565656565656'
$expiryResult=Invoke-ProductionStageFixtureV010 $expiryFixture 'valid' $now $now.AddMinutes(4)
Assert-ProductionStageDeniedV010 $expiryResult 'permit-expired-after-stage';Assert-True ([string]$expiryResult.reason -like 'post-stage-admission-denied:*permit-expired*') 'post-stage expiry reason drifted';Assert-True ([bool]$expiryResult.cleanup_ok) 'expired post-stage workspace cleanup failed';$count++

$timeFixture=New-ProductionStageExecutorFixtureV010 'time-backwards' -Nonce '67676767676767676767676767676767'
$timeResult=Invoke-ProductionStageFixtureV010 $timeFixture 'valid' $now $now.AddSeconds(-1)
Assert-ProductionStageDeniedV010 $timeResult 'post-stage-time-backwards';Assert-True ([string]$timeResult.reason -ceq 'post-stage-time-before-pre-stage-time') 'post-stage backwards time reason drifted';Assert-True ([bool]$timeResult.cleanup_ok) 'backwards-time stage cleanup failed';$count++

$futureFixture=New-ProductionStageExecutorFixtureV010 'future-app' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce '78787878787878787878787878787878'
$futureResult=Invoke-ProductionStageFixtureV010 $futureFixture
Assert-True ([bool]$futureResult.ok) ('generic future app isolated staging denied: '+[string]$futureResult.reason);Assert-ProductionStageNoAuthorityV010 $futureResult 'future-app';Assert-True ([bool]$futureResult.post_stage_revalidated) 'future app missing post-stage revalidation';[void](Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath ([string]$futureResult.workspace_path));$count++

$resultTamper=Copy-Deep $valid.result;$resultTamper.apply_authorized=$true;$resultTamper.result_fingerprint=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 $resultTamper);$resultTamperCheck=Test-CustomAppProductionStageExecutorResultV010 $resultTamper
Assert-False ([bool]$resultTamperCheck.ok) 'apply authority tamper accepted with recomputed result fingerprint';Assert-True ([string]$resultTamperCheck.reason -ceq 'production-stage-result-apply_authorized-true') 'apply authority tamper reason drifted';$count++

$fingerprintTamper=Copy-Deep $valid.result;$fingerprintTamper.result_fingerprint=('0'*64);$fingerprintCheck=Test-CustomAppProductionStageExecutorResultV010 $fingerprintTamper
Assert-False ([bool]$fingerprintCheck.ok) 'production stage result fingerprint tamper accepted';Assert-True ([string]$fingerprintCheck.reason -ceq 'production-stage-result-fingerprint-mismatch') 'result fingerprint tamper reason drifted';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_STAGE_EXECUTOR_MATRIX_PASS total='+$count)
