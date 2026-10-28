$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/test_custom_app_production_atomic_live_swap.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-transaction-finalization.ps1')

$script:FinalizationFaultMode='none'
function Invoke-CustomAppProductionTransactionFinalizationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:FinalizationFaultMode){
        'throw-before-cleanup' { if($Checkpoint -ceq 'before-cleanup'){ throw 'fixture-before-cleanup' } }
        'throw-after-cleanup' { if($Checkpoint -ceq 'after-cleanup'){ throw 'fixture-after-cleanup' } }
        'live-drift-after-cleanup' { if($Checkpoint -ceq 'after-cleanup'){ [IO.File]::AppendAllText((Join-Path ([string]$Context.live_path) 'index.js'),"// finalizer-post-cleanup-live-drift`n",[Text.UTF8Encoding]::new($false)) } }
        'git-drift-after-cleanup' { if($Checkpoint -ceq 'after-cleanup'){ [IO.File]::AppendAllText((Join-Path ([string]$Context.live_path) '.git\config'),"# finalizer-post-cleanup-git-drift`n",[Text.UTF8Encoding]::new($false)) } }
        'persistence-drift-after-cleanup' { if($Checkpoint -ceq 'after-cleanup'){ $cfg=Join-Path ([string]$Context.appdata) 'spicetify\config-xpui.ini';[IO.File]::AppendAllText($cfg,"# finalizer-post-cleanup-persistence-drift`n",[Text.UTF8Encoding]::new($false)) } }
    }
}

function New-FinalizationFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='89898989898989898989898989898989')
    $atomic=New-AtomicFixtureV010 -Label ('finalize-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $swap=Invoke-AtomicFixtureV010 $atomic
    if(-not [bool]$swap.ok){ throw ('finalization fixture atomic swap failed: '+[string]$swap.reason) }
    $liveRuntime=Get-CustomAppLocalRuntimeBaseline -Name $atomic.q.x.f.name -AppPath $atomic.q.x.live
    $liveGit=Get-CustomAppAtomicGitSnapshotV010 -LivePath $atomic.q.x.live
    $persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $atomic.q.persistence.local -AppDataRoot $atomic.q.persistence.roaming
    return [pscustomobject]@{atomic=$atomic;swap=$swap;live_runtime=$liveRuntime;live_git=$liveGit;persistence=$persistence}
}

function Invoke-FinalizationFixtureV010 {
    param($Fixture,[string]$Fault='none',[AllowNull()]$AtomicResult=$null,[AllowNull()]$PreparedResult=$null,[AllowNull()]$StageResult=$null,[AllowNull()]$Lifecycle=$null,[DateTimeOffset]$At=$now.AddSeconds(4))
    if($null -eq $AtomicResult){$AtomicResult=$Fixture.swap};if($null -eq $PreparedResult){$PreparedResult=$Fixture.atomic.prepared.result};if($null -eq $StageResult){$StageResult=$Fixture.atomic.q.stage.result};if($null -eq $Lifecycle){$Lifecycle=$Fixture.atomic.q.x.f.lifecycle}
    $script:FinalizationFaultMode=$Fault
    return Invoke-CustomAppProductionTransactionFinalizationV010 -AtomicResult $AtomicResult -PreparedResult $PreparedResult -StageExecutorResult $StageResult -Name $Fixture.atomic.q.x.f.name -LifecycleRow $Lifecycle -LocalAppDataRoot $Fixture.atomic.q.persistence.local -AppDataRoot $Fixture.atomic.q.persistence.roaming -Now $At
}

function Assert-FinalizationNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.result_is_authority) "$Label result authority"
    Assert-False ([bool]$Result.spicetify_apply_authorized) "$Label spicetify apply authority"
    Assert-False ([bool]$Result.additional_mutation_authorized) "$Label additional mutation authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function Assert-FinalizationEvidencePreservedV010 {
    param($Fixture,[string]$Label)
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.atomic.prepared.result.stage_workspace_path) -PathType Container) "$Label stage workspace lost"
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.atomic.prepared.result.app_backup_path) -PathType Container) "$Label app backup lost"
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.atomic.prepared.result.persistence_backup_path) -PathType Container) "$Label persistence backup lost"
}

function Assert-FinalizationLiveUnchangedV010 {
    param($Fixture,[string]$Label)
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name $Fixture.atomic.q.x.f.name -AppPath $Fixture.atomic.q.x.live
    Assert-True ([string]$runtime.tree_sha256 -ceq [string]$Fixture.live_runtime.tree_sha256) "$Label live runtime drifted"
    $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $Fixture.atomic.q.x.live
    Assert-True ([bool]$git.present -eq [bool]$Fixture.live_git.present) "$Label git presence drifted"
    if([bool]$git.present){ Assert-True ([string]$git.tree_sha256 -ceq [string]$Fixture.live_git.tree_sha256) "$Label git tree drifted" }
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Fixture.atomic.q.persistence.local -AppDataRoot $Fixture.atomic.q.persistence.roaming
    Assert-True ([string]$persist.fingerprint -ceq [string]$Fixture.persistence.fingerprint) "$Label persistence drifted"
}

function Assert-FinalizationDeniedV010 {
    param($Fixture,$Result,[string]$Label,[bool]$ExpectTransaction=$true)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-FinalizationNoAuthorityV010 $Result $Label
    if($ExpectTransaction){ Assert-True (Test-Path -LiteralPath ([string]$Fixture.swap.transaction_root) -PathType Container) "$Label unexpectedly deleted transaction workspace" }
    Assert-FinalizationEvidencePreservedV010 $Fixture $Label
}

$count=0
$valid=New-FinalizationFixtureV010 'valid'
$parent=[IO.Path]::GetDirectoryName([string]$valid.swap.live_path);$sentinel=Join-Path $parent ('.spotify-control-sentinel-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($sentinel)|Out-Null
$success=Invoke-FinalizationFixtureV010 $valid
Assert-True ([bool]$success.ok) ('valid finalization denied: '+[string]$success.reason)
Assert-True ([bool]$success.transaction_workspace_deleted) 'valid transaction workspace delete flag missing'
Assert-False (Test-Path -LiteralPath ([string]$valid.swap.transaction_root)) 'valid transaction workspace remained'
Assert-True (Test-Path -LiteralPath $sentinel -PathType Container) 'finalizer deleted unrelated sibling'
Assert-True ([bool]$success.requires_spicetify_apply_phase) 'valid finalization lost apply separation'
Assert-FinalizationNoAuthorityV010 $success 'valid'
Assert-FinalizationEvidencePreservedV010 $valid 'valid'
Assert-FinalizationLiveUnchangedV010 $valid 'valid'
$successCheck=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $success
Assert-True ([bool]$successCheck.ok) ('valid finalization result self-check failed: '+[string]$successCheck.reason)
$authorityTamper=Copy-Deep $success;$authorityTamper.spicetify_apply_authorized=$true;$authorityTamper.finalization_fingerprint=Get-CustomAppProductionTransactionFinalizationSha256V010 -Text (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $authorityTamper);$authorityCheck=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $authorityTamper;Assert-False ([bool]$authorityCheck.ok) 'authority-tampered finalization receipt accepted'
$fingerprintTamper=Copy-Deep $success;$fingerprintTamper.finalization_fingerprint=('0'*64);$fingerprintCheck=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $fingerprintTamper;Assert-False ([bool]$fingerprintCheck.ok) 'fingerprint-tampered finalization receipt accepted'
$count++

$future=New-FinalizationFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N '9')
$futureResult=Invoke-FinalizationFixtureV010 $future;Assert-True ([bool]$futureResult.ok) ('future app finalization denied: '+[string]$futureResult.reason);Assert-FinalizationNoAuthorityV010 $futureResult 'future-app';Assert-FinalizationEvidencePreservedV010 $future 'future-app';$count++

$atomicBad=New-FinalizationFixtureV010 'atomic-bad' -Nonce (N '8');$badAtomic=Copy-Deep $atomicBad.swap;$badAtomic.ok=$false;$r=Invoke-FinalizationFixtureV010 -Fixture $atomicBad -AtomicResult $badAtomic;Assert-FinalizationDeniedV010 $atomicBad $r 'atomic-result-not-success';Assert-True ([string]$r.reason -like '*atomic-result-invalid*') 'atomic bad reason drifted';$count++

$atomicAuthority=New-FinalizationFixtureV010 'atomic-authority' -Nonce (N '7');$badAtomic=Copy-Deep $atomicAuthority.swap;$badAtomic.production_mutation_authorized=$true;$r=Invoke-FinalizationFixtureV010 -Fixture $atomicAuthority -AtomicResult $badAtomic;Assert-FinalizationDeniedV010 $atomicAuthority $r 'atomic-authority';Assert-True ([string]$r.reason -like '*production_mutation_authorized-true*') 'atomic authority reason drifted';$count++

$pathFixture=New-FinalizationFixtureV010 'path' -Nonce (N '6');$badAtomic=Copy-Deep $pathFixture.swap;$badAtomic.transaction_root=[IO.Path]::GetDirectoryName([string]$pathFixture.swap.transaction_root);$r=Invoke-FinalizationFixtureV010 -Fixture $pathFixture -AtomicResult $badAtomic;Assert-FinalizationDeniedV010 $pathFixture $r 'transaction-path-shape';Assert-True ([string]$r.reason -like '*transaction-root-shape-invalid*' -or [string]$r.reason -like '*transaction-path-validation-failed*') 'transaction path reason drifted';$count++

$extra=New-FinalizationFixtureV010 'extra-entry' -Nonce (N '5');[IO.File]::WriteAllText((Join-Path ([string]$extra.swap.transaction_root) 'unexpected.txt'),'x',[Text.UTF8Encoding]::new($false));$r=Invoke-FinalizationFixtureV010 $extra;Assert-FinalizationDeniedV010 $extra $r 'extra-transaction-entry';Assert-True ([string]$r.reason -like '*transaction-root-contents-not-exact-old-live-only*') 'extra entry reason drifted';$count++

$oldDrift=New-FinalizationFixtureV010 'old-live-drift' -Nonce (N '4');[IO.File]::AppendAllText((Join-Path ([string]$oldDrift.swap.old_live_path) 'index.js'),"// old-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-FinalizationFixtureV010 $oldDrift;Assert-FinalizationDeniedV010 $oldDrift $r 'old-live-drift';Assert-True ([string]$r.reason -like '*old-live-not-exact-pre-swap-tree*') 'old-live drift reason changed';$count++

$liveDrift=New-FinalizationFixtureV010 'live-drift' -Nonce (N '3');[IO.File]::AppendAllText((Join-Path $liveDrift.atomic.q.x.live 'index.js'),"// live-drift-before-finalization`n",[Text.UTF8Encoding]::new($false));$r=Invoke-FinalizationFixtureV010 $liveDrift;Assert-FinalizationDeniedV010 $liveDrift $r 'live-runtime-drift';Assert-True ([string]$r.reason -like '*live-runtime-no-longer-exact-staged-tree*') 'live drift reason changed';$count++

$gitDrift=New-FinalizationFixtureV010 'git-drift' -Nonce (N '2');[IO.File]::AppendAllText((Join-Path $gitDrift.atomic.q.x.live '.git\config'),"# git-drift-before-finalization`n",[Text.UTF8Encoding]::new($false));$r=Invoke-FinalizationFixtureV010 $gitDrift;Assert-FinalizationDeniedV010 $gitDrift $r 'git-drift';Assert-True ([string]$r.reason -like '*git-tree-drift*') 'git drift reason changed';$count++

$persistDrift=New-FinalizationFixtureV010 'persistence-drift' -Nonce (N '1');[IO.File]::AppendAllText((Join-Path $persistDrift.atomic.q.persistence.roaming 'spicetify\config-xpui.ini'),"# persistence-drift-before-finalization`n",[Text.UTF8Encoding]::new($false));$r=Invoke-FinalizationFixtureV010 $persistDrift;Assert-FinalizationDeniedV010 $persistDrift $r 'persistence-drift';Assert-True ([string]$r.reason -like '*protected-persistence-drift-before-finalization*') 'persistence drift reason changed';$count++

$preparedTamper=New-FinalizationFixtureV010 'prepared-tamper' -Nonce '12121212121212121212121212121212';$badPrepared=Copy-Deep $preparedTamper.atomic.prepared.result;$badPrepared.preparation_fingerprint=('0'*64);$r=Invoke-FinalizationFixtureV010 -Fixture $preparedTamper -PreparedResult $badPrepared;Assert-FinalizationDeniedV010 $preparedTamper $r 'prepared-result-tamper';Assert-True ([string]$r.reason -like '*prepared-result-invalid:*fingerprint-mismatch*') 'prepared tamper reason changed';$count++

$stageTamper=New-FinalizationFixtureV010 'stage-tamper' -Nonce '23232323232323232323232323232323';$badStage=Copy-Deep $stageTamper.atomic.q.stage.result;$badStage.result_fingerprint=('0'*64);$r=Invoke-FinalizationFixtureV010 -Fixture $stageTamper -StageResult $badStage;Assert-FinalizationDeniedV010 $stageTamper $r 'stage-result-tamper';Assert-True ([string]$r.reason -like '*stage-result-invalid:*fingerprint*') 'stage tamper reason changed';$count++

$removed=New-FinalizationFixtureV010 'removed' -Nonce '34343434343434343434343434343434';$badLifecycle=Copy-Deep $removed.atomic.q.x.f.lifecycle;$badLifecycle.present=$false;$badLifecycle.user_removed=$true;$r=Invoke-FinalizationFixtureV010 -Fixture $removed -Lifecycle $badLifecycle;Assert-FinalizationDeniedV010 $removed $r 'user-removed';Assert-True ([string]$r.reason -like '*lifecycle-not-safe-current-single-location*') 'user removal reason changed';$count++

$beforeFault=New-FinalizationFixtureV010 'before-fault' -Nonce '45454545454545454545454545454545';$r=Invoke-FinalizationFixtureV010 -Fixture $beforeFault -Fault 'throw-before-cleanup';Assert-FinalizationDeniedV010 $beforeFault $r 'throw-before-cleanup';Assert-True ([bool]$r.cleanup_attempted) 'before-cleanup fault did not report cleanup attempt';Assert-True ([string]$r.reason -like '*fixture-before-cleanup*') 'before cleanup fault reason drifted';Assert-FinalizationLiveUnchangedV010 $beforeFault 'throw-before-cleanup';$count++

$afterFault=New-FinalizationFixtureV010 'after-fault' -Nonce '56565656565656565656565656565656';$r=Invoke-FinalizationFixtureV010 -Fixture $afterFault -Fault 'throw-after-cleanup';Assert-FinalizationDeniedV010 $afterFault $r 'throw-after-cleanup' $false;Assert-True ([bool]$r.cleanup_attempted -and [bool]$r.transaction_workspace_deleted) 'after-cleanup fault did not report deleted transaction';Assert-False (Test-Path -LiteralPath ([string]$afterFault.swap.transaction_root)) 'after-cleanup fault transaction root remained';Assert-FinalizationEvidencePreservedV010 $afterFault 'throw-after-cleanup';Assert-FinalizationLiveUnchangedV010 $afterFault 'throw-after-cleanup';$count++

$postLive=New-FinalizationFixtureV010 'post-live-drift' -Nonce '67676767676767676767676767676767';$r=Invoke-FinalizationFixtureV010 -Fixture $postLive -Fault 'live-drift-after-cleanup';Assert-FinalizationDeniedV010 $postLive $r 'post-cleanup-live-drift' $false;Assert-True ([string]$r.reason -ceq 'post-cleanup-live-runtime-drift') 'post-cleanup live drift reason changed';Assert-FinalizationEvidencePreservedV010 $postLive 'post-cleanup-live-drift';$count++

$postGit=New-FinalizationFixtureV010 'post-git-drift' -Nonce '78787878787878787878787878787878';$r=Invoke-FinalizationFixtureV010 -Fixture $postGit -Fault 'git-drift-after-cleanup';Assert-FinalizationDeniedV010 $postGit $r 'post-cleanup-git-drift' $false;Assert-True ([string]$r.reason -ceq 'post-cleanup-git-drift') 'post-cleanup git drift reason changed';Assert-FinalizationEvidencePreservedV010 $postGit 'post-cleanup-git-drift';$count++

$postPersist=New-FinalizationFixtureV010 'post-persistence-drift' -Nonce '89898989898989898989898989898989';$r=Invoke-FinalizationFixtureV010 -Fixture $postPersist -Fault 'persistence-drift-after-cleanup';Assert-FinalizationDeniedV010 $postPersist $r 'post-cleanup-persistence-drift' $false;Assert-True ([string]$r.reason -ceq 'post-cleanup-protected-persistence-drift') 'post-cleanup persistence drift reason changed';Assert-FinalizationEvidencePreservedV010 $postPersist 'post-cleanup-persistence-drift';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_TRANSACTION_FINALIZATION_MATRIX_PASS total='+$count)
