$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'custom-app-remote-observer.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1')

$old=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 416245914
$new=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 418974188

if([int64]$old.github_repo_id -ne 1021838879 -or [int64]$new.github_repo_id -ne 1021838879){throw 'Tagify numeric repository identity drift.'}
if([string]$old.commit_sha -cne '0be36dced09c5b5b7fef14726a69b99148bee432'){throw "Tagify v3.3.1 commit drift: $($old.commit_sha)"}
if([string]$new.commit_sha -cne 'bacd80f76c621a3acc06965bb3160ce1056fad7b'){throw "Tagify v3.3.2 commit drift: $($new.commit_sha)"}
if([int64]$old.asset_id -ne 652536027 -or [int64]$new.asset_id -ne 660754674){throw 'Tagify pinned asset identity drift.'}
if([string]$old.asset_digest_sha256 -cne 'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957'){throw 'Tagify v3.3.1 digest drift.'}
if([string]$new.asset_digest_sha256 -cne '5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b'){throw 'Tagify v3.3.2 digest drift.'}

foreach($o in @($old,$new)){
    if([int]$o.release_zip_asset_count -ne 1 -or [bool]$o.archive_unsafe -or [bool]$o.has_symlink -or [bool]$o.has_device_entry){throw 'Tagify release observation safety drift.'}
    if([bool]$o.build_required -or [int]$o.app_root_count -ne 1 -or [string]$o.layout_root -cne '.'){
        throw "Tagify ZIP is not a ready runtime root: build=$($o.build_required) roots=$($o.app_root_count) layout=$($o.layout_root) wrapper=$($o.wrapper_name)"
    }
    if(-not [bool]$o.manifest_valid -or [string]::IsNullOrWhiteSpace([string]$o.manifest_name)){throw 'Tagify manifest observation failed.'}
    if(-not (Test-CustomAppRemoteSha256 ([string]$o.tree_sha256))){throw 'Tagify runtime tree hash invalid.'}
    if([bool]$o.mutation_authorized -or [bool]$o.auto_update_authorized -or [bool]$o.auto_install_authorized){throw 'Collector escaped observer-only authority.'}
}

if([string]$old.manifest_name -cne [string]$new.manifest_name){throw 'Tagify manifest identity changed across pinned releases.'}

$prov=[pscustomobject]@{
    schema=1;managed_by='custom-app-provenance-v1';source_identity='alexk218/tagify';last_proven_source='alexk218/tagify';source_status='proven-local-git-origin'
    source_changed=$false;requires_reenrollment=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
}
$enroll=Resolve-CustomAppRemoteSourceContractV011 $prov $old $null ([string]$old.tree_sha256) ([string]$old.manifest_name)
if([string]$enroll.status -cne 'binding-enrollment-candidate' -or [string]$enroll.binding_candidate.release_asset_selector -cne 'unique-zip-asset' -or (Test-CustomAppRemoteSourceMutationAuthorityV011 $enroll)){
    throw "Tagify v3.3.1 safe enrollment failed: $($enroll.status)/$($enroll.reason)"
}
$update=Resolve-CustomAppRemoteSourceContractV011 $prov $new $enroll.binding_candidate ([string]$old.tree_sha256) ([string]$old.manifest_name)
if([string]$update.status -cne 'remote-change-observed' -or -not [bool]$update.update_observed -or -not [bool]$update.release_asset_name_changed -or (Test-CustomAppRemoteSourceMutationAuthorityV011 $update)){
    throw "Tagify v3.3.2 safe update observation failed: $($update.status)/$($update.reason)"
}

Write-Host "CUSTOM_APP_REMOTE_OBSERVER_LIVE_TAGIFY_PASS old_tree=$($old.tree_sha256) new_tree=$($new.tree_sha256) manifest=$($old.manifest_name) old_wrapper=$($old.wrapper_name) new_wrapper=$($new.wrapper_name)"
