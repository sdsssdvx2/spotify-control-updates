$ErrorActionPreference='Stop'
$validationRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $validationRoot 'custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $validationRoot 'custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1')
. (Join-Path $PSScriptRoot 'custom-app-remote-binding-state.ps1')

# Standalone minimal state helpers. Integrated candidate uses the production implementations.
if(-not (Get-Command Ensure-ObjectNoteProperty -ErrorAction SilentlyContinue)){
    function Ensure-ObjectNoteProperty {param($Object,[string]$Name,$DefaultValue) if(-not $Object.PSObject.Properties[$Name]){$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue};return $Object.PSObject.Properties[$Name].Value}
}
if(-not (Get-Command Normalize-AddonStateObject -ErrorAction SilentlyContinue)){
    function Normalize-AddonStateObject {param($State) if($null -eq $State){$State=[pscustomobject]@{}};return $State}
}

function New-Prov {
    param([string]$Source='example/app',[bool]$Changed=$false,[bool]$Reenroll=$false)
    [pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';source_identity=$Source;last_proven_source=$Source;source_status='proven-local-git-origin';source_changed=$Changed;requires_reenrollment=$Reenroll;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-Life {
    param([bool]$Present=$true,[bool]$Removed=$false,[bool]$Ambiguous=$false,[string]$Name='future-app')
    [pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name=$Name;present=$Present;user_removed=$Removed;ambiguous=$Ambiguous;safe_local_identity=(-not $Ambiguous);locations=@('C:\fixture\CustomApps\future-app');mutation_mode='deny'}
}
function New-Files {
    param([string]$IndexHash=('a'*64),[string]$ManifestHash=('b'*64))
    @(
        [pscustomobject]@{path='index.js';type='file';size=[int64]10;sha256=$IndexHash},
        [pscustomobject]@{path='manifest.json';type='file';size=[int64]20;sha256=$ManifestHash}
    )
}
function Get-Tree {
    param([object[]]$Files)
    $rows=New-Object System.Collections.Generic.List[string]
    foreach($f in $Files){$rows.Add(('f|'+([string]$f.path).ToLowerInvariant()+'|'+[int64]$f.size+'|'+([string]$f.sha256).ToLowerInvariant()))}
    $a=[string[]]$rows.ToArray();[Array]::Sort($a,[StringComparer]::Ordinal);Get-CustomAppRemoteStringSha256 (($a -join "`n")+"`n")
}
function New-Baseline {
    param([object[]]$Files=(New-Files),[string]$Manifest='Future App')
    [pscustomobject]@{schema=1;safe=$true;installable=$true;tree_sha256=(Get-Tree $Files);manifest_valid=$true;manifest_name=$Manifest;files=$Files;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-ReleaseObs {
    param([object[]]$Files=(New-Files),[string]$Commit=('1'*40),[int64]$RepoId=12345,[string]$Asset='app-v1.zip',[int64]$ReleaseId=1,[int64]$AssetId=11,[string]$Manifest='Future App')
    [pscustomobject]@{schema=1;source_identity='example/app';github_repo_id=$RepoId;transport='github-api-https';commit_sha=$Commit;surface_kind='release-asset';release_id=$ReleaseId;release_tag=('v'+$ReleaseId);release_zip_asset_count=1;asset_id=$AssetId;asset_name=$Asset;asset_size=[int64]1024;asset_digest_sha256=('c'*64);archive_unsafe=$false;has_symlink=$false;has_hardlink=$false;has_submodule=$false;has_device_entry=$false;build_required=$false;app_root_count=1;layout_root='.';manifest_valid=$true;manifest_name=$Manifest;package_repository_identity='example/app';files=$Files;tree_sha256=(Get-Tree $Files);mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-RepoObs {
    param([object[]]$Files=(New-Files),[string]$Commit=('2'*40),[int64]$RepoId=12345,[string]$Manifest='Future App')
    [pscustomobject]@{schema=1;source_identity='example/app';github_repo_id=$RepoId;transport='github-api-https';commit_sha=$Commit;surface_kind='repo-commit-root';archive_unsafe=$false;has_symlink=$false;has_hardlink=$false;has_submodule=$false;has_device_entry=$false;build_required=$false;app_root_count=1;layout_root='.';manifest_valid=$true;manifest_name=$Manifest;package_repository_identity='example/app';files=$Files;tree_sha256=(Get-Tree $Files);mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-Set {param([object[]]$Obs,[object[]]$Errors=@()) [pscustomobject]@{schema=1;source_identity='example/app';observations=@($Obs);errors=@($Errors);mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}}
function Assert-Denied {param($Row,[string]$Label) if(Test-CustomAppRemoteBindingMutationAuthorityV040 $Row){throw "$Label gained mutation authority."}}

$life=New-Life;$prov=New-Prov;$base=New-Baseline
$state=[pscustomobject]@{}
$row=Update-CustomAppRemoteBindingFromObservationSetV040 -State $state -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @((New-ReleaseObs))) -ObservedAt '2026-10-28T00:00:00+00:00'
if(-not $row.active -or [string]$row.last_status -cne 'binding-enrolled' -or [string]$row.binding.managed_by -cne 'custom-app-remote-source-v1' -or [string]$row.binding.release_asset_selector -cne 'unique-zip-asset'){throw 'Exact-match release binding enrollment failed.'};Assert-Denied $row 'enrolled row'
$bindingJsonBefore=$row.binding|ConvertTo-Json -Depth 12 -Compress

# Network/observer failure must preserve the exact prior binding and active state.
$row=Update-CustomAppRemoteBindingFromObservationSetV040 -State $state -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @() @([pscustomobject]@{surface='release-asset';error='fixture-network-failure'})) -ObservedAt '2026-10-28T00:01:00+00:00'
if(-not $row.active -or [string]$row.last_status -cne 'remote-observation-failed' -or ($row.binding|ConvertTo-Json -Depth 12 -Compress) -cne $bindingJsonBefore){throw 'Network failure did not preserve prior active binding byte-for-byte as JSON state.'};Assert-Denied $row 'failure row'

# Same repo/surface with a new tree is observable, not actionable. Versioned ZIP names may change under unique-ZIP selector.
$newFiles=New-Files -IndexHash ('d'*64);$newObs=New-ReleaseObs -Files $newFiles -Commit ('3'*40) -Asset 'app-v2.zip' -ReleaseId 2 -AssetId 12
$row=Update-CustomAppRemoteBindingFromObservationSetV040 -State $state -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @($newObs)) -ObservedAt '2026-10-28T00:02:00+00:00'
if(-not $row.active -or [string]$row.last_status -cne 'remote-change-observed' -or -not $row.update_observed -or [string]$row.binding.asset_name -cne 'app-v2.zip'){throw 'Safe remote change observation or release asset continuity failed.'};Assert-Denied $row 'remote-change row'

# Local tree drift after enrollment fails closed and requires re-enrollment.
$driftBase=New-Baseline -Files $newFiles
$row=Update-CustomAppRemoteBindingFromObservationSetV040 -State $state -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $driftBase -ObservationSet (New-Set @($newObs)) -ObservedAt '2026-10-28T00:03:00+00:00'
if($row.active -or -not $row.requires_reenrollment -or [string]$row.last_status -cne 'local-tree-drift'){throw 'Local tree drift did not deactivate binding and require re-enrollment.'};Assert-Denied $row 'local-drift row'

# Fresh state with two exact safe surfaces is ambiguous: never guess a binding.
$ambState=[pscustomobject]@{};$repoObs=New-RepoObs
$amb=Update-CustomAppRemoteBindingFromObservationSetV040 -State $ambState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @((New-ReleaseObs),$repoObs)) -ObservedAt '2026-10-28T00:04:00+00:00'
if($amb.active -or $null -ne $amb.binding -or [string]$amb.last_status -cne 'binding-ambiguous'){throw 'Multiple exact-match remote surfaces were not denied as ambiguous.'};Assert-Denied $amb 'ambiguous row'

# Tree mismatch / manifest mismatch cannot enroll.
$mismatchState=[pscustomobject]@{};$mismatch=Update-CustomAppRemoteBindingFromObservationSetV040 -State $mismatchState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @($newObs)) -ObservedAt '2026-10-28T00:05:00+00:00'
if($mismatch.active -or $null -ne $mismatch.binding -or [string]$mismatch.last_status -cne 'binding-not-enrolled'){throw 'Initial tree mismatch incorrectly enrolled.'}
$manifestState=[pscustomobject]@{};$manifestObs=New-ReleaseObs -Manifest 'Other App';$manifest=Update-CustomAppRemoteBindingFromObservationSetV040 -State $manifestState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @($manifestObs)) -ObservedAt '2026-10-28T00:06:00+00:00'
if($manifest.active -or $null -ne $manifest.binding){throw 'Manifest mismatch incorrectly enrolled.'}

# User deletion deactivates without erasing historical binding; no network input is needed.
$deleteState=[pscustomobject]@{};$enrolled=Update-CustomAppRemoteBindingFromObservationSetV040 -State $deleteState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @((New-ReleaseObs))) -ObservedAt '2026-10-28T00:07:00+00:00'
$historical=$enrolled.binding|ConvertTo-Json -Depth 12 -Compress
$deleted=Update-CustomAppRemoteBindingEligibilityOnlyV040 -State $deleteState -Name 'future-app' -LifecycleRow (New-Life -Present:$false -Removed:$true) -ProvenanceRow $prov -ObservedAt '2026-10-28T00:08:00+00:00'
if($deleted.active -or -not $deleted.user_removed -or ($deleted.binding|ConvertTo-Json -Depth 12 -Compress) -cne $historical){throw 'User deletion did not deactivate while preserving historical binding.'};Assert-Denied $deleted 'deleted row'

# Source change / re-enrollment requirement deactivates and preserves history.
$swapProv=New-Prov -Source 'other/fork' -Changed:$true -Reenroll:$true
$swapped=Update-CustomAppRemoteBindingEligibilityOnlyV040 -State $deleteState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $swapProv -ObservedAt '2026-10-28T00:09:00+00:00'
if($swapped.active -or -not $swapped.requires_reenrollment -or ($swapped.binding|ConvertTo-Json -Depth 12 -Compress) -cne $historical){throw 'Source change did not fail closed while preserving historical binding.'};Assert-Denied $swapped 'source-change row'

# Same-source explicit reinstall can only reactivate after exact local/remote proof again.
$reinstall=Update-CustomAppRemoteBindingFromObservationSetV040 -State $deleteState -Name 'future-app' -LifecycleRow $life -ProvenanceRow $prov -LocalBaseline $base -ObservationSet (New-Set @((New-ReleaseObs))) -ObservedAt '2026-10-28T00:10:00+00:00'
if(-not $reinstall.active -or [string]$reinstall.last_status -cne 'binding-enrolled' -or $reinstall.requires_reenrollment){throw 'Same-source reinstall did not require and then accept exact re-proof.'};Assert-Denied $reinstall 'reinstall row'

# State-root normalization must preserve the ledger object in-place or by property retention.
$normalized=Normalize-AddonStateObject $deleteState
if(-not $normalized.PSObject.Properties['custom_app_remote_sources'] -or -not $normalized.custom_app_remote_sources.PSObject.Properties['custom-app:future-app']){throw 'Normalize-AddonStateObject dropped the remote binding state root.'}
[void](Assert-CustomAppRemoteBindingStateDeniedV040 $normalized)

# Due policy is conservative and bounded.
if(-not (Test-CustomAppRemoteObservationDueV040 -Row $null -Now ([DateTimeOffset]'2026-10-28T00:00:00+00:00') -MinimumIntervalHours 24)){throw 'New row was not due.'}
$dueRow=[pscustomobject]@{last_attempt='2026-10-28T00:00:00+00:00'}
if(Test-CustomAppRemoteObservationDueV040 -Row $dueRow -Now ([DateTimeOffset]'2026-10-28T12:00:00+00:00') -MinimumIntervalHours 24){throw 'Observation became due too early.'}
if(-not (Test-CustomAppRemoteObservationDueV040 -Row $dueRow -Now ([DateTimeOffset]'2026-10-29T00:00:00+00:00') -MinimumIntervalHours 24)){throw 'Observation was not due at interval boundary.'}

Write-Host 'CUSTOM_APP_REMOTE_BINDING_STATE_V040_PASS enrollment failure-preserve remote-change local-drift ambiguity mismatch delete source-change reinstall normalize due authority-deny'
