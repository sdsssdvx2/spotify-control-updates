$ErrorActionPreference='Stop'
$base=Join-Path (Split-Path $PSScriptRoot -Parent) 'custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1'
. $base
. (Join-Path $PSScriptRoot 'release-continuity-v011.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}
function Assert-Denied($Decision,[string]$Message){Assert-False (Test-CustomAppRemoteSourceMutationAuthorityV011 -Decision $Decision) "$Message mutation authority escaped"}

$H1='1'*64;$H2='2'*64;$H3='3'*64;$H4='4'*64;$C1='a'*40;$C2='b'*40

function New-Provenance([string]$Source='example/app'){
    [pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';source_identity=$Source;last_proven_source=$Source;source_status='proven-local-git-origin';source_changed=$false;requires_reenrollment=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-File([string]$Path,[string]$Hash,[int64]$Size){[pscustomobject]@{path=$Path;type='file';size=$Size;sha256=$Hash}}
function New-ReleaseObs {
    param([string]$AssetName='fixture-v1.zip',[int]$ZipCount=1,[string]$Commit=$C1,[object[]]$Files=$null,[string]$Source='example/app',[int64]$RepoId=12345,[string]$Digest=$H4,[string]$ManifestName='Fixture App')
    if($null -eq $Files){$Files=@(New-File 'index.js' $H1 100;New-File 'manifest.json' $H2 200)}
    $o=[pscustomobject]@{schema=1;source_identity=$Source;github_repo_id=$RepoId;transport='github-api-https';commit_sha=$Commit;surface_kind='release-asset';archive_unsafe=$false;has_symlink=$false;has_hardlink=$false;has_submodule=$false;has_device_entry=$false;build_required=$false;app_root_count=1;layout_root='.';manifest_valid=$true;manifest_name=$ManifestName;package_repository_identity=$Source;release_id=777;asset_id=888;asset_name=$AssetName;asset_size=2048;asset_digest_sha256=$Digest;release_zip_asset_count=$ZipCount;files=$Files;tree_sha256=$null}
    $f=Test-CustomAppRemoteRuntimeFileSet -Observation $o
    if($f.safe -and $f.installable){$o.tree_sha256=[string]$f.tree_sha256}
    $o
}
function New-RepoObs {
    $files=@(New-File 'index.js' $H1 100;New-File 'manifest.json' $H2 200)
    $o=[pscustomobject]@{schema=1;source_identity='example/app';github_repo_id=12345;transport='github-api-https';commit_sha=$C1;surface_kind='repo-commit-root';archive_unsafe=$false;has_symlink=$false;has_hardlink=$false;has_submodule=$false;has_device_entry=$false;build_required=$false;app_root_count=1;layout_root='.';manifest_valid=$true;manifest_name='Fixture App';package_repository_identity='example/app';files=$files;tree_sha256=$null}
    $f=Test-CustomAppRemoteRuntimeFileSet -Observation $o;$o.tree_sha256=[string]$f.tree_sha256;$o
}
function Clone-Obj($o){$o|ConvertTo-Json -Depth 20|ConvertFrom-Json}

$prov=New-Provenance
$rel=New-ReleaseObs
$tree=[string]$rel.tree_sha256

# 1. A release surface can enroll only when exactly one ZIP asset exists and content exactly matches local.
$e=Resolve-CustomAppRemoteSourceContractV011 $prov $rel $null $tree 'Fixture App'
Assert-Eq $e.status 'binding-enrollment-candidate' 'Unique ZIP release did not enroll.'
Assert-Eq $e.binding_candidate.release_asset_selector 'unique-zip-asset' 'Unique ZIP selector was not persisted.'
Assert-Eq $e.binding_candidate.initial_asset_name 'fixture-v1.zip' 'Initial asset audit name missing.'
Assert-Denied $e 'Initial unique ZIP enrollment'
$binding=$e.binding_candidate

# 2. Same release/tree remains current.
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $rel $binding $tree 'Fixture App'
Assert-Eq $d.status 'remote-current' 'Bound unique ZIP release was not current.'
Assert-False $d.release_asset_name_changed 'Unchanged asset name was reported changed.'
Assert-Denied $d 'Current unique ZIP'

# 3. Versioned asset-name change is allowed only because the release still contains exactly one ZIP.
$changed=New-ReleaseObs -AssetName 'fixture-v2.zip' -Commit $C2 -Files @(New-File 'index.js' $H1 100;New-File 'manifest.json' $H2 200;New-File 'style.css' $H3 50)
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $changed $binding $tree 'Fixture App'
Assert-Eq $d.status 'remote-change-observed' 'Unique versioned ZIP rename/new tree was not observed.'
Assert-True $d.release_asset_name_changed 'Versioned ZIP name change audit bit missing.'
Assert-Eq $d.previous_asset_name 'fixture-v1.zip' 'Previous asset name audit value drifted.'
Assert-Eq $d.observed_asset_name 'fixture-v2.zip' 'Observed asset name audit value drifted.'
Assert-Denied $d 'Versioned unique ZIP update'

# 4. A renamed but byte-identical unique ZIP stays current and remains denied.
$renamedSame=New-ReleaseObs -AssetName 'fixture-v1-repacked-name.zip'
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $renamedSame $binding $tree 'Fixture App'
Assert-Eq $d.status 'remote-current' 'Byte-identical unique ZIP rename should remain current.'
Assert-True $d.release_asset_name_changed 'Byte-identical rename audit bit missing.'
Assert-Denied $d 'Byte-identical unique ZIP rename'

# 5-6. Zero or multiple ZIP candidates are ambiguous and fail closed.
foreach($n in @(0,2)){
    $o=New-ReleaseObs -ZipCount $n
    $d=Resolve-CustomAppRemoteSourceContractV011 $prov $o $null $tree 'Fixture App'
    Assert-Eq $d.reason 'release-zip-asset-not-unique' "ZIP count $n did not fail closed."
    Assert-Denied $d "ZIP count $n"
}

# 7-8. Existing release bindings require the explicit unique-ZIP selector.
$b=Clone-Obj $binding;$b.PSObject.Properties.Remove('release_asset_selector')
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $rel $b $tree 'Fixture App'
Assert-Eq $d.reason 'release-asset-selector-missing-or-unsupported' 'Missing release selector escaped.';Assert-Denied $d 'Missing selector'
$b=Clone-Obj $binding;$b.release_asset_selector='asset-name-pattern'
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $rel $b $tree 'Fixture App'
Assert-Eq $d.reason 'release-asset-selector-missing-or-unsupported' 'Unsupported release selector escaped.';Assert-Denied $d 'Unsupported selector'

# 9. Numeric repository identity continuity is still enforced after name-flex amendment.
$repoDrift=New-ReleaseObs -RepoId 99999 -AssetName 'fixture-v2.zip'
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $repoDrift $binding $tree 'Fixture App'
Assert-Eq $d.status 'repo-id-drift' 'Repo ID drift escaped release-name amendment.';Assert-Denied $d 'Repo ID drift'

# 10. Local tree continuity is still enforced.
$b=Clone-Obj $binding;$b.last_verified_local_tree_sha256=$H4
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $rel $b $tree 'Fixture App'
Assert-Eq $d.status 'local-tree-drift' 'Local tree drift escaped release-name amendment.';Assert-Denied $d 'Local tree drift'

# 11. Release digest validation remains owned by the base contract.
$badDigest=New-ReleaseObs -Digest ''
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $badDigest $null $tree 'Fixture App'
Assert-Eq $d.reason 'release-asset-identity-invalid' 'Missing release digest escaped amendment.';Assert-Denied $d 'Missing release digest'

# 12. Non-release behavior must remain exactly delegated to the validated v0.1.0 resolver.
$repo=New-RepoObs;$repoTree=[string]$repo.tree_sha256
$old=Resolve-CustomAppRemoteSourceContract $prov $repo $null $repoTree 'Fixture App'
$new=Resolve-CustomAppRemoteSourceContractV011 $prov $repo $null $repoTree 'Fixture App'
Assert-Eq $new.status $old.status 'Non-release status changed.'
Assert-Eq $new.reason $old.reason 'Non-release reason changed.'
Assert-Eq $new.remote_tree_sha256 $old.remote_tree_sha256 'Non-release tree identity changed.'
Assert-Denied $new 'Non-release delegated behavior'

# 13. Provenance/source mismatch remains denied even on unique release assets.
$evil=New-ReleaseObs -Source 'evil/app'
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $evil $null $tree 'Fixture App'
Assert-Eq $d.reason 'remote-source-mismatch' 'Source mismatch escaped unique ZIP amendment.';Assert-Denied $d 'Source mismatch'

# 14. Multiple ZIP ambiguity also blocks an already-bound release, not only enrollment.
$ambiguous=New-ReleaseObs -ZipCount 2 -AssetName 'fixture-v2.zip'
$d=Resolve-CustomAppRemoteSourceContractV011 $prov $ambiguous $binding $tree 'Fixture App'
Assert-Eq $d.reason 'release-zip-asset-not-unique' 'Bound release accepted multiple ZIP candidates.';Assert-Denied $d 'Bound multiple ZIP ambiguity'

Write-Host 'CUSTOM_APP_REMOTE_SOURCE_RELEASE_CONTINUITY_V011_PASS cases=14'
