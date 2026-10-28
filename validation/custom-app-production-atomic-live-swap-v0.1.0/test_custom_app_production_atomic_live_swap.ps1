$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Loads the exact validated pre-apply chain and its fixture helpers. The workflow
# materializes the pinned persistence/transaction sibling blobs before this runs.
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/test_custom_app_production_pre_apply_preparation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-atomic-live-swap.ps1')

$script:AtomicFaultMode='none'
function Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:AtomicFaultMode){
        'throw-before-live-move' { if($Checkpoint -ceq 'before-live-move'){ throw 'fixture-before-live-move' } }
        'throw-after-live-move' { if($Checkpoint -ceq 'after-live-move'){ throw 'fixture-after-live-move' } }
        'throw-after-candidate-move' { if($Checkpoint -ceq 'after-candidate-move'){ throw 'fixture-after-candidate-move' } }
        'runtime-drift-after-swap' { if($Checkpoint -ceq 'after-candidate-move'){ [IO.File]::AppendAllText((Join-Path ([string]$Context.live_path) 'index.js'),"// fixture-runtime-drift`n",[Text.UTF8Encoding]::new($false)) } }
        'git-drift-after-swap' { if($Checkpoint -ceq 'after-candidate-move'){ [IO.File]::AppendAllText((Join-Path ([string]$Context.live_path) '.git\config'),"# fixture-git-drift`n",[Text.UTF8Encoding]::new($false)) } }
        'persistence-drift-after-swap' { if($Checkpoint -ceq 'before-persistence-postcheck'){ $cfg=Join-Path ([string]$Context.appdata) 'spicetify\config-xpui.ini';[IO.File]::AppendAllText($cfg,"# fixture-persistence-drift`n",[Text.UTF8Encoding]::new($false)) } }
        'throw-after-post-verify' { if($Checkpoint -ceq 'after-post-verify'){ throw 'fixture-after-post-verify' } }
    }
}

function New-AtomicFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='97979797979797979797979797979797')
    $q=New-PreApplyFixtureV010 -Label ('atomic-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $prepared=Invoke-PreApplyFixtureV010 -Q $q
    if(-not [bool]$prepared.ok){throw ('atomic fixture pre-apply failed: '+[string]$prepared.reason)}
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root $q.x.live
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $q.x.live
    $git=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q.x.live '.git')
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $q.persistence.local -AppDataRoot $q.persistence.roaming
    return [pscustomobject]@{q=$q;prepared=$prepared;full_before=$full;runtime_before=$runtime;git_before=$git;persistence_before=$persist}
}

function Invoke-AtomicFixtureV010 {
    param($Fixture,[string]$Fault='none',[AllowNull()]$Prepared=$null,[AllowNull()]$Lifecycle=$null)
    if($null -eq $Prepared){$Prepared=$Fixture.prepared.result};if($null -eq $Lifecycle){$Lifecycle=$Fixture.q.x.f.lifecycle}
    $script:AtomicFaultMode=$Fault
    return Invoke-CustomAppProductionAtomicLiveSwapV010 -PreparedResult $Prepared -Name $Fixture.q.x.f.name -LifecycleRow $Lifecycle -LocalAppDataRoot $Fixture.q.persistence.local -AppDataRoot $Fixture.q.persistence.roaming
}

function Assert-AtomicResultNoFutureAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.result_is_authority) "$Label result authority"
    Assert-False ([bool]$Result.spicetify_apply_authorized) "$Label spicetify apply authority"
    Assert-False ([bool]$Result.additional_mutation_authorized) "$Label additional mutation authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function Assert-AtomicOriginalRestoredV010 {
    param($Fixture,[string]$Label)
    $live=$Fixture.q.x.live
    Assert-True (Test-Path -LiteralPath $live -PathType Container) "$Label live path missing after rollback"
    $full=Get-CustomAppUpdateTreeSnapshotV010 -Root $live
    Assert-True ([string]$full.tree_sha256 -ceq [string]$Fixture.full_before.tree_sha256) "$Label full app tree not restored"
    Assert-True ([int]$full.file_count -eq [int]$Fixture.full_before.file_count) "$Label app file count not restored"
    Assert-True ([int64]$full.total_bytes -eq [int64]$Fixture.full_before.total_bytes) "$Label app bytes not restored"
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name $Fixture.q.x.f.name -AppPath $live
    Assert-True ([string]$runtime.tree_sha256 -ceq [string]$Fixture.runtime_before.tree_sha256) "$Label runtime tree not restored"
    $git=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $live '.git')
    Assert-True ([string]$git.tree_sha256 -ceq [string]$Fixture.git_before.tree_sha256) "$Label git provenance not restored"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Fixture.q.persistence.local -AppDataRoot $Fixture.q.persistence.roaming
    Assert-True ([string]$persist.fingerprint -ceq [string]$Fixture.persistence_before.fingerprint) "$Label persistence not restored"
}

function Assert-AtomicPreMutationDeniedUnchangedV010 {
    param($Fixture,$Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-False ([bool]$Result.rollback_attempted) "$Label unexpectedly attempted rollback before mutation"
    Assert-AtomicResultNoFutureAuthorityV010 $Result $Label
    Assert-AtomicOriginalRestoredV010 $Fixture $Label
}

function Assert-AtomicPostMutationFailureRolledBackV010 {
    param($Fixture,$Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-True ([bool]$Result.rollback_attempted) "$Label did not attempt rollback"
    Assert-True ([bool]$Result.rollback_ok) "$Label rollback did not verify"
    Assert-AtomicResultNoFutureAuthorityV010 $Result $Label
    Assert-AtomicOriginalRestoredV010 $Fixture $Label
}

$count=0

$valid=New-AtomicFixtureV010 'valid'
$success=Invoke-AtomicFixtureV010 $valid
Assert-True ([bool]$success.ok) ('valid atomic swap denied: '+[string]$success.reason)
Assert-True ([bool]$success.live_code_swap_performed) 'valid atomic swap did not report live swap'
Assert-True ([bool]$success.requires_transaction_workspace_cleanup) 'valid atomic swap cleanup requirement missing'
Assert-True ([bool]$success.requires_spicetify_apply_phase) 'valid atomic swap did not keep spicetify apply separate'
Assert-AtomicResultNoFutureAuthorityV010 $success 'valid'
$postRuntime=Get-CustomAppLocalRuntimeBaseline -Name $valid.q.x.f.name -AppPath $valid.q.x.live
Assert-True ([string]$postRuntime.tree_sha256 -ceq [string]$valid.prepared.result.stage_tree_sha256) 'valid live runtime does not equal retained staged runtime'
$postGit=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $valid.q.x.live '.git')
Assert-True ([string]$postGit.tree_sha256 -ceq [string]$valid.git_before.tree_sha256) 'valid swap changed git provenance'
$postPersist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.persistence.local -AppDataRoot $valid.q.persistence.roaming
Assert-True ([string]$postPersist.fingerprint -ceq [string]$valid.persistence_before.fingerprint) 'valid swap changed persistence'
Assert-True (Test-Path -LiteralPath ([string]$success.old_live_path) -PathType Container) 'valid old-live evidence missing'
$oldSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$success.old_live_path)
Assert-True ([string]$oldSnapshot.tree_sha256 -ceq [string]$valid.full_before.tree_sha256) 'valid old-live evidence not exact original tree'
$count++

$future=New-AtomicFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N '8')
$futureSuccess=Invoke-AtomicFixtureV010 $future
Assert-True ([bool]$futureSuccess.ok) ('future app atomic swap denied: '+[string]$futureSuccess.reason)
Assert-AtomicResultNoFutureAuthorityV010 $futureSuccess 'future-app'
$count++

$fp=New-AtomicFixtureV010 'prepared-fingerprint' -Nonce (N '7');$badPrepared=Copy-Deep $fp.prepared.result;$badPrepared.preparation_fingerprint=('0'*64);$r=Invoke-AtomicFixtureV010 -Fixture $fp -Prepared $badPrepared
Assert-AtomicPreMutationDeniedUnchangedV010 $fp $r 'prepared-fingerprint-tamper';Assert-True ([string]$r.reason -like 'atomic-precondition-denied:prepared-result-invalid:*fingerprint-mismatch*') 'prepared fingerprint reason drifted';$count++

$removed=New-AtomicFixtureV010 'removed' -Nonce (N '6');$removedLifecycle=Copy-Deep $removed.q.x.f.lifecycle;$removedLifecycle.present=$false;$removedLifecycle.user_removed=$true;$r=Invoke-AtomicFixtureV010 -Fixture $removed -Lifecycle $removedLifecycle
Assert-AtomicPreMutationDeniedUnchangedV010 $removed $r 'user-removed';Assert-True ([string]$r.reason -like '*lifecycle-not-safe-current-single-location*') 'user removal reason drifted';$count++

$liveDrift=New-AtomicFixtureV010 'live-drift' -Nonce (N '5');[IO.File]::AppendAllText((Join-Path $liveDrift.q.x.live 'index.js'),"// pre-swap-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AtomicFixtureV010 $liveDrift
Assert-False ([bool]$r.ok) 'pre-swap live drift accepted';Assert-False ([bool]$r.rollback_attempted) 'pre-swap live drift attempted rollback';Assert-AtomicResultNoFutureAuthorityV010 $r 'pre-swap-live-drift';$count++

$stageDrift=New-AtomicFixtureV010 'stage-drift' -Nonce (N '4');[IO.File]::AppendAllText((Join-Path ([string]$stageDrift.prepared.result.stage_path) 'index.js'),"// pre-swap-stage-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AtomicFixtureV010 $stageDrift
Assert-False ([bool]$r.ok) 'pre-swap stage drift accepted';Assert-False ([bool]$r.rollback_attempted) 'pre-swap stage drift attempted rollback';Assert-AtomicResultNoFutureAuthorityV010 $r 'pre-swap-stage-drift';$count++

$persistDrift=New-AtomicFixtureV010 'pre-persistence-drift' -Nonce (N '3');[IO.File]::AppendAllText((Join-Path $persistDrift.q.persistence.roaming 'spicetify\config-xpui.ini'),"# pre-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AtomicFixtureV010 $persistDrift
Assert-False ([bool]$r.ok) 'pre-swap persistence drift accepted';Assert-False ([bool]$r.rollback_attempted) 'pre-swap persistence drift attempted rollback';Assert-AtomicResultNoFutureAuthorityV010 $r 'pre-swap-persistence-drift';$count++

$before=New-AtomicFixtureV010 'throw-before' -Nonce (N '2');$r=Invoke-AtomicFixtureV010 -Fixture $before -Fault 'throw-before-live-move'
Assert-AtomicPreMutationDeniedUnchangedV010 $before $r 'throw-before-live-move';Assert-True ([string]$r.reason -like 'candidate-preparation-failed:*fixture-before-live-move*') 'before-live-move reason drifted';$count++

$afterMove=New-AtomicFixtureV010 'after-live-move' -Nonce (N '1');$r=Invoke-AtomicFixtureV010 -Fixture $afterMove -Fault 'throw-after-live-move'
Assert-AtomicPostMutationFailureRolledBackV010 $afterMove $r 'throw-after-live-move';Assert-True ([string]$r.reason -like '*fixture-after-live-move*') 'after-live-move reason drifted';$count++

$afterCandidate=New-AtomicFixtureV010 'after-candidate' -Nonce (N 'a');$r=Invoke-AtomicFixtureV010 -Fixture $afterCandidate -Fault 'throw-after-candidate-move'
Assert-AtomicPostMutationFailureRolledBackV010 $afterCandidate $r 'throw-after-candidate-move';Assert-True ([string]$r.reason -like '*fixture-after-candidate-move*') 'after-candidate reason drifted';$count++

$runtimeFault=New-AtomicFixtureV010 'runtime-fault' -Nonce (N 'b');$r=Invoke-AtomicFixtureV010 -Fixture $runtimeFault -Fault 'runtime-drift-after-swap'
Assert-AtomicPostMutationFailureRolledBackV010 $runtimeFault $r 'runtime-drift-after-swap';Assert-True ([string]$r.reason -like '*post-swap-runtime-mismatch*') 'runtime post-swap drift reason changed';$count++

$gitFault=New-AtomicFixtureV010 'git-fault' -Nonce (N 'c');$r=Invoke-AtomicFixtureV010 -Fixture $gitFault -Fault 'git-drift-after-swap'
Assert-AtomicPostMutationFailureRolledBackV010 $gitFault $r 'git-drift-after-swap';Assert-True ([string]$r.reason -like '*post-swap-git-tree-mismatch*') 'git post-swap drift reason changed';$count++

$persistenceFault=New-AtomicFixtureV010 'persistence-fault' -Nonce (N 'd');$r=Invoke-AtomicFixtureV010 -Fixture $persistenceFault -Fault 'persistence-drift-after-swap'
Assert-AtomicPostMutationFailureRolledBackV010 $persistenceFault $r 'persistence-drift-after-swap';Assert-True ([string]$r.reason -like '*protected-persistence-drift-after-swap*') 'persistence post-swap drift reason changed';$count++

$postVerify=New-AtomicFixtureV010 'post-verify-fault' -Nonce (N 'e');$r=Invoke-AtomicFixtureV010 -Fixture $postVerify -Fault 'throw-after-post-verify'
Assert-AtomicPostMutationFailureRolledBackV010 $postVerify $r 'throw-after-post-verify';Assert-True ([string]$r.reason -like '*fixture-after-post-verify*') 'post-verify failure reason changed';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_ATOMIC_LIVE_SWAP_MATRIX_PASS total='+$count)
