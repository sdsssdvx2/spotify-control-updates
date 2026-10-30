$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/test_custom_app_production_spicetify_apply_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-post-apply-commit-cleanup.ps1')

$script:PostApplyCleanupFaultMode='none'
function Invoke-CustomAppProductionPostApplyCommitCleanupValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:PostApplyCleanupFaultMode){
        'after-stage' {if($Checkpoint -ceq 'after-stage-cleanup'){throw 'fixture-fault-after-stage-cleanup'}}
        'after-app' {if($Checkpoint -ceq 'after-app-backup-cleanup'){throw 'fixture-fault-after-app-backup-cleanup'}}
        'after-persistence' {if($Checkpoint -ceq 'after-persistence-backup-cleanup'){throw 'fixture-fault-after-persistence-backup-cleanup'}}
    }
}

function New-PostApplyCleanupFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='91919191919191919191919191919191')
    $x=New-ApplyExecutorFixtureV010 -Label ('cleanup-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $applied=Invoke-ApplyExecutorFixtureV010 $x
    if(-not [bool]$applied.ok){throw ('cleanup fixture apply failed: '+[string]$applied.reason)}
    $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$x.q.f.atomic.q.x.live)
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $x.q.f.atomic.q.persistence.local -AppDataRoot $x.q.f.atomic.q.persistence.roaming
    [pscustomobject]@{x=$x;apply=$applied.result;live_before=$live;persistence_before=$persist;initial_apply_count=(Get-ApplyExecutorFakeCountV010 $x)}
}

function Get-PostApplyCleanupArtifactPathsV010 {
    param($Fixture)
    $p=$Fixture.x.q.f.atomic.prepared.result
    [pscustomobject]@{stage=[string]$p.stage_workspace_path;app_container=[IO.Path]::GetDirectoryName([string]$p.app_backup_path);persistence=[string]$p.persistence_backup_path}
}

function Invoke-PostApplyCleanupFixtureV010 {
    param($Fixture,[string]$Fault='none',[byte[]]$SessionKey=$key,[AllowNull()]$ApplyResult=$null,[AllowNull()]$Lifecycle=$null,[AllowNull()]$Binding=$null,[DateTimeOffset]$At=$now.AddMinutes(10))
    if($null -eq $ApplyResult){$ApplyResult=$Fixture.apply};if($null -eq $Lifecycle){$Lifecycle=$Fixture.x.q.f.atomic.q.x.f.lifecycle};if($null -eq $Binding){$Binding=$Fixture.x.q.f.atomic.q.x.f.binding}
    $script:PostApplyCleanupFaultMode=$Fault
    try{
        Invoke-CustomAppProductionPostApplyCommitCleanupV010 -AllowedRoot $Fixture.x.q.f.atomic.q.x.store.root -StoreDirectory $Fixture.x.q.f.atomic.q.x.store.store -ExpectedConsumptionId ([string]$Fixture.x.q.f.atomic.q.x.consumption.consumption_id) -Permit $Fixture.x.q.f.atomic.q.x.permit -ApplyResult $ApplyResult -FinalizationResult $Fixture.x.q.finalization -PreparedResult $Fixture.x.q.f.atomic.prepared.result -StageExecutorResult $Fixture.x.q.f.atomic.q.stage.result -Name $Fixture.x.q.f.atomic.q.x.f.name -LifecycleRow $Lifecycle -ProvenanceRow $Fixture.x.q.f.atomic.q.x.f.provenance -BindingRow $Binding -SessionKey $SessionKey -LocalAppDataRoot $Fixture.x.q.f.atomic.q.persistence.local -AppDataRoot $Fixture.x.q.f.atomic.q.persistence.roaming -Now $At
    }finally{$script:PostApplyCleanupFaultMode='none'}
}

function Assert-PostApplyCleanupNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.result_is_authority) "$Label result authority"
    Assert-False ([bool]$Result.spicetify_apply_authorized) "$Label spicetify authority"
    Assert-False ([bool]$Result.additional_mutation_authorized) "$Label additional mutation authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
    Assert-False ([bool]$Result.rollback_attempted) "$Label unexpectedly attempted rollback"
    Assert-False ([bool]$Result.spicetify_apply_executed) "$Label unexpectedly executed spicetify apply"
}

function Assert-PostApplyCleanupAppliedStateUnchangedV010 {
    param($Fixture,[string]$Label)
    $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Fixture.x.q.f.atomic.q.x.live)
    Assert-True ([string]$live.tree_sha256 -ceq [string]$Fixture.live_before.tree_sha256) "$Label applied live tree changed"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Fixture.x.q.f.atomic.q.persistence.local -AppDataRoot $Fixture.x.q.f.atomic.q.persistence.roaming
    Assert-True ([string]$persist.fingerprint -ceq [string]$Fixture.persistence_before.fingerprint) "$Label protected persistence changed"
    Assert-True ((Get-ApplyExecutorFakeCountV010 $Fixture.x) -eq [int]$Fixture.initial_apply_count) "$Label cleanup launched another apply process"
}

function Assert-PostApplyCleanupAllArtifactsAbsentV010 {
    param($Fixture,[string]$Label)
    $paths=Get-PostApplyCleanupArtifactPathsV010 $Fixture
    Assert-False (Test-Path -LiteralPath $paths.stage) "$Label stage workspace remains"
    Assert-False (Test-Path -LiteralPath $paths.app_container) "$Label app backup container remains"
    Assert-False (Test-Path -LiteralPath $paths.persistence) "$Label persistence backup remains"
}

function Assert-PostApplyCleanupAllArtifactsPresentV010 {
    param($Fixture,[string]$Label)
    $paths=Get-PostApplyCleanupArtifactPathsV010 $Fixture
    Assert-True (Test-Path -LiteralPath $paths.stage -PathType Container) "$Label stage workspace missing"
    Assert-True (Test-Path -LiteralPath $paths.app_container -PathType Container) "$Label app backup container missing"
    Assert-True (Test-Path -LiteralPath $paths.persistence -PathType Container) "$Label persistence backup missing"
}

function Assert-PostApplyCleanupDeniedBeforeDeletionV010 {
    param($Fixture,$Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-False ([bool]$Result.cleanup_attempted) "$Label unexpectedly attempted cleanup"
    Assert-PostApplyCleanupNoAuthorityV010 $Result $Label
    Assert-PostApplyCleanupAllArtifactsPresentV010 $Fixture $Label
    Assert-PostApplyCleanupAppliedStateUnchangedV010 $Fixture $Label
}

$count=0
$valid=New-PostApplyCleanupFixtureV010 'valid'
$r=Invoke-PostApplyCleanupFixtureV010 $valid
Assert-True ([bool]$r.ok) ('valid cleanup denied: '+[string]$r.reason);Assert-True ([bool]$r.update_commit_complete -and [bool]$r.all_transaction_artifacts_clean) 'valid cleanup completion flags missing';Assert-PostApplyCleanupNoAuthorityV010 $r 'valid';Assert-PostApplyCleanupAllArtifactsAbsentV010 $valid 'valid';Assert-PostApplyCleanupAppliedStateUnchangedV010 $valid 'valid'
$check=Test-CustomAppProductionPostApplyCommitCleanupResultV010 $r.result;Assert-True ([bool]$check.ok) ('valid cleanup receipt invalid: '+[string]$check.reason)
$authority=Copy-Deep $r.result;$authority.production_mutation_authorized=$true;$authority.cleanup_fingerprint=Get-CustomAppProductionPostApplyCommitCleanupSha256V010 (Get-CustomAppProductionPostApplyCommitCleanupResultMaterialV010 $authority);$authorityCheck=Test-CustomAppProductionPostApplyCommitCleanupResultV010 $authority;Assert-False ([bool]$authorityCheck.ok) 'authority-tampered cleanup receipt accepted'
$fingerprint=Copy-Deep $r.result;$fingerprint.cleanup_fingerprint=('0'*64);$fingerprintCheck=Test-CustomAppProductionPostApplyCommitCleanupResultV010 $fingerprint;Assert-False ([bool]$fingerprintCheck.ok) 'fingerprint-tampered cleanup receipt accepted';$count++

$future=New-PostApplyCleanupFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N '8');$r=Invoke-PostApplyCleanupFixtureV010 $future;Assert-True ([bool]$r.ok) ('future app cleanup denied: '+[string]$r.reason);Assert-PostApplyCleanupAllArtifactsAbsentV010 $future 'future-app';Assert-PostApplyCleanupAppliedStateUnchangedV010 $future 'future-app';$count++

$expired=New-PostApplyCleanupFixtureV010 'expired-permit' -Nonce (N '7');$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $expired -At $now.AddHours(2);Assert-True ([bool]$r.ok) ('expired original permit blocked non-authoritative cleanup: '+[string]$r.reason);Assert-PostApplyCleanupAllArtifactsAbsentV010 $expired 'expired-permit';$count++

$wrongKey=New-PostApplyCleanupFixtureV010 'wrong-key' -Nonce (N '6');$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $wrongKey -SessionKey ([byte[]](33..64));Assert-PostApplyCleanupDeniedBeforeDeletionV010 $wrongKey $r 'wrong-session-key';Assert-True ([string]$r.reason -like '*permit-hmac-mismatch*') 'wrong key reason drifted';$count++

$applyTamper=New-PostApplyCleanupFixtureV010 'apply-tamper' -Nonce (N '5');$badApply=Copy-Deep $applyTamper.apply;$badApply.result_is_authority=$true;$badApply.result_fingerprint=Get-CustomAppProductionSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionSpicetifyApplyResultMaterialV010 $badApply);$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $applyTamper -ApplyResult $badApply;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $applyTamper $r 'apply-result-authority-tamper';Assert-True ([string]$r.reason -like '*apply-result-result_is_authority-true*') 'apply receipt authority reason drifted';$count++

$store=New-PostApplyCleanupFixtureV010 'store-corrupt' -Nonce (N '4');[IO.File]::WriteAllText((Join-Path $store.x.q.f.atomic.q.x.store.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $store;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $store $r 'store-corrupt';Assert-True ([string]$r.reason -like '*persisted-consumption-read-denied*') 'store corrupt reason drifted';$count++

$removed=New-PostApplyCleanupFixtureV010 'user-removed' -Nonce (N '3');$life=Copy-Deep $removed.x.q.f.atomic.q.x.f.lifecycle;$life.present=$false;$life.user_removed=$true;$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $removed -Lifecycle $life;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $removed $r 'user-removed';Assert-True ([string]$r.reason -like '*lifecycle-not-safe-current-single-location*') 'user removed reason drifted';$count++

$bindingDrift=New-PostApplyCleanupFixtureV010 'binding-drift' -Nonce (N '2');$binding=Copy-Deep $bindingDrift.x.q.f.atomic.q.x.f.binding;$binding.source_identity='other/repo';$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $bindingDrift -Binding $binding;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $bindingDrift $r 'binding-drift';Assert-True ([string]$r.reason -like '*binding-denied:*') 'binding drift reason changed';$count++

$liveDrift=New-PostApplyCleanupFixtureV010 'live-drift' -Nonce (N '1');[IO.File]::AppendAllText((Join-Path $liveDrift.x.q.f.atomic.q.x.live 'index.js'),"// cleanup-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $liveDrift;Assert-False ([bool]$r.ok) 'live drift cleanup succeeded';Assert-False ([bool]$r.cleanup_attempted) 'live drift attempted cleanup';Assert-PostApplyCleanupAllArtifactsPresentV010 $liveDrift 'live-drift';Assert-True ([string]$r.reason -like '*post-apply-live-runtime-drift*') 'live drift reason changed';$count++

$gitDrift=New-PostApplyCleanupFixtureV010 'git-drift' -Nonce '11111111111111111111111111111111';[IO.File]::AppendAllText((Join-Path $gitDrift.x.q.f.atomic.q.x.live '.git\config'),"# cleanup-git-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $gitDrift;Assert-False ([bool]$r.ok) 'git drift cleanup succeeded';Assert-False ([bool]$r.cleanup_attempted) 'git drift attempted cleanup';Assert-PostApplyCleanupAllArtifactsPresentV010 $gitDrift 'git-drift';Assert-True ([string]$r.reason -like '*post-apply-git-drift*') 'git drift reason changed';$count++

$persistDrift=New-PostApplyCleanupFixtureV010 'persistence-drift' -Nonce '22222222222222222222222222222222';[IO.File]::AppendAllText((Join-Path $persistDrift.x.q.f.atomic.q.persistence.roaming 'spicetify\config-xpui.ini'),"# cleanup-persistence-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $persistDrift;Assert-False ([bool]$r.ok) 'persistence drift cleanup succeeded';Assert-False ([bool]$r.cleanup_attempted) 'persistence drift attempted cleanup';Assert-PostApplyCleanupAllArtifactsPresentV010 $persistDrift 'persistence-drift';Assert-True ([string]$r.reason -like '*post-apply-protected-persistence-drift*') 'persistence drift reason changed';$count++

$stageExtra=New-PostApplyCleanupFixtureV010 'stage-extra' -Nonce '33333333333333333333333333333333';[IO.File]::WriteAllText((Join-Path $stageExtra.x.q.f.atomic.prepared.result.stage_workspace_path 'unexpected.txt'),'do-not-delete',[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $stageExtra;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $stageExtra $r 'stage-extra-entry';Assert-True ([string]$r.reason -like '*stage-workspace-unexpected-entry*') 'stage extra reason changed';$count++

$appExtra=New-PostApplyCleanupFixtureV010 'app-extra' -Nonce '44444444444444444444444444444444';$appContainer=[IO.Path]::GetDirectoryName([string]$appExtra.x.q.f.atomic.prepared.result.app_backup_path);[IO.File]::WriteAllText((Join-Path $appContainer 'unexpected.txt'),'do-not-delete',[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $appExtra;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $appExtra $r 'app-extra-entry';Assert-True ([string]$r.reason -like '*app-backup-container-contents-not-exact-app-code-only*') 'app extra reason changed';$count++

$persistenceExtra=New-PostApplyCleanupFixtureV010 'persistence-extra' -Nonce '55555555555555555555555555555555';[IO.File]::WriteAllText((Join-Path $persistenceExtra.x.q.f.atomic.prepared.result.persistence_backup_path 'unexpected.txt'),'do-not-delete',[Text.UTF8Encoding]::new($false));$r=Invoke-PostApplyCleanupFixtureV010 $persistenceExtra;Assert-PostApplyCleanupDeniedBeforeDeletionV010 $persistenceExtra $r 'persistence-extra-entry';Assert-True ([string]$r.reason -like '*persistence-backup-top-level-contents-unexpected*') 'persistence extra reason changed';$count++

$stageFault=New-PostApplyCleanupFixtureV010 'fault-after-stage' -Nonce '66666666666666666666666666666666';$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $stageFault -Fault 'after-stage';Assert-False ([bool]$r.ok) 'after-stage fault unexpectedly succeeded';Assert-True ([bool]$r.cleanup_attempted) 'after-stage fault did not attempt cleanup';Assert-PostApplyCleanupNoAuthorityV010 $r 'after-stage-fault';$paths=Get-PostApplyCleanupArtifactPathsV010 $stageFault;Assert-False (Test-Path -LiteralPath $paths.stage) 'after-stage fault stage remained';Assert-True (Test-Path -LiteralPath $paths.app_container) 'after-stage fault app backup missing';Assert-True (Test-Path -LiteralPath $paths.persistence) 'after-stage fault persistence backup missing';Assert-PostApplyCleanupAppliedStateUnchangedV010 $stageFault 'after-stage-fault';$retry=Invoke-PostApplyCleanupFixtureV010 $stageFault;Assert-True ([bool]$retry.ok) ('after-stage retry failed: '+[string]$retry.reason);Assert-True ([string]$retry.result.stage_cleanup_status -ceq 'already-absent') 'after-stage retry did not recognize prior deletion';Assert-PostApplyCleanupAllArtifactsAbsentV010 $stageFault 'after-stage-retry';$count++

$appFault=New-PostApplyCleanupFixtureV010 'fault-after-app' -Nonce '77777777777777777777777777777777';$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $appFault -Fault 'after-app';Assert-False ([bool]$r.ok) 'after-app fault unexpectedly succeeded';Assert-True ([bool]$r.cleanup_attempted) 'after-app fault did not attempt cleanup';$paths=Get-PostApplyCleanupArtifactPathsV010 $appFault;Assert-False (Test-Path -LiteralPath $paths.stage) 'after-app fault stage remained';Assert-False (Test-Path -LiteralPath $paths.app_container) 'after-app fault app backup remained';Assert-True (Test-Path -LiteralPath $paths.persistence) 'after-app fault persistence backup missing';Assert-PostApplyCleanupAppliedStateUnchangedV010 $appFault 'after-app-fault';$retry=Invoke-PostApplyCleanupFixtureV010 $appFault;Assert-True ([bool]$retry.ok) ('after-app retry failed: '+[string]$retry.reason);Assert-True ([string]$retry.result.stage_cleanup_status -ceq 'already-absent' -and [string]$retry.result.app_backup_cleanup_status -ceq 'already-absent') 'after-app retry did not recognize prior deletions';Assert-PostApplyCleanupAllArtifactsAbsentV010 $appFault 'after-app-retry';$count++

$persistenceFault=New-PostApplyCleanupFixtureV010 'fault-after-persistence' -Nonce '88888888888888888888888888888888';$r=Invoke-PostApplyCleanupFixtureV010 -Fixture $persistenceFault -Fault 'after-persistence';Assert-False ([bool]$r.ok) 'after-persistence fault unexpectedly succeeded';Assert-True ([bool]$r.cleanup_attempted) 'after-persistence fault did not attempt cleanup';Assert-PostApplyCleanupAllArtifactsAbsentV010 $persistenceFault 'after-persistence-fault';Assert-PostApplyCleanupAppliedStateUnchangedV010 $persistenceFault 'after-persistence-fault';$retry=Invoke-PostApplyCleanupFixtureV010 $persistenceFault;Assert-True ([bool]$retry.ok) ('after-persistence retry failed: '+[string]$retry.reason);Assert-True ([string]$retry.result.stage_cleanup_status -ceq 'already-absent' -and [string]$retry.result.app_backup_cleanup_status -ceq 'already-absent' -and [string]$retry.result.persistence_backup_cleanup_status -ceq 'already-absent') 'after-persistence retry did not recognize all prior deletions';$count++

Write-Host "CUSTOM_APP_PRODUCTION_POST_APPLY_COMMIT_CLEANUP_MATRIX_PASS total=$count"
