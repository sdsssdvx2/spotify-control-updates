$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'custom-app-remote-source-contract.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}
function Assert-Denied($Decision,[string]$Message){Assert-False (Test-CustomAppRemoteSourceMutationAuthority -Decision $Decision) "$Message mutation authority escaped"}

$H1=(('1' * 64) -join '');$H2=(('2' * 64) -join '');$H3=(('3' * 64) -join '');$H4=(('4' * 64) -join '')
$Commit1=(('a' * 40) -join '');$Commit2=(('b' * 40) -join '')

function New-ProvenanceRow {
    param([string]$Source='example/app',[bool]$SourceChanged=$false,[bool]$RequiresReenrollment=$false,[string]$MutationMode='deny',[bool]$AutoUpdate=$false,[bool]$AutoInstall=$false,[string]$LastProvenSource='example/app')
    return [pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';source_identity=$Source;last_proven_source=$LastProvenSource;source_status='proven-local-git-origin';source_changed=$SourceChanged;requires_reenrollment=$RequiresReenrollment;mutation_mode=$MutationMode;auto_update_authorized=$AutoUpdate;auto_install_authorized=$AutoInstall}
}

function New-FileEntry([string]$Path,[string]$Hash=$H1,[int64]$Size=10,[string]$Type='file'){
    return [pscustomobject]@{path=$Path;type=$Type;size=$Size;sha256=$Hash}
}

function New-Observation {
    param(
        [string]$Source='example/app',[int64]$RepoId=12345,[string]$Commit=$Commit1,[string]$Surface='repo-commit-root',
        [object[]]$Files=$null,[string]$ManifestName='Fixture App',[bool]$ManifestValid=$true,[string]$PackageSource='example/app',
        [string]$Transport='github-api-https',[bool]$ArchiveUnsafe=$false,[bool]$Symlink=$false,[bool]$Hardlink=$false,[bool]$Submodule=$false,[bool]$Device=$false,
        [bool]$BuildRequired=$false,[int]$AppRootCount=1,[string]$LayoutRoot='.',[int64]$ReleaseId=777,[int64]$AssetId=888,[string]$AssetName='fixture-app.zip',[int64]$AssetSize=2048,[string]$AssetDigest=$H4
    )
    if($null -eq $Files){$Files=@(New-FileEntry 'index.js' $H1 100;New-FileEntry 'manifest.json' $H2 200)}
    $o=[pscustomobject]@{
        schema=1;source_identity=$Source;github_repo_id=$RepoId;transport=$Transport;commit_sha=$Commit;surface_kind=$Surface
        archive_unsafe=$ArchiveUnsafe;has_symlink=$Symlink;has_hardlink=$Hardlink;has_submodule=$Submodule;has_device_entry=$Device;build_required=$BuildRequired
        app_root_count=$AppRootCount;layout_root=$LayoutRoot;manifest_valid=$ManifestValid;manifest_name=$ManifestName;package_repository_identity=$PackageSource
        release_id=$ReleaseId;asset_id=$AssetId;asset_name=$AssetName;asset_size=$AssetSize;asset_digest_sha256=$AssetDigest;files=$Files;tree_sha256=$null
    }
    $check=Test-CustomAppRemoteRuntimeFileSet -Observation $o
    if([bool]$check.safe -and [bool]$check.installable){$o.tree_sha256=[string]$check.tree_sha256}
    return $o
}

function Clone-Binding($Binding){return ($Binding|ConvertTo-Json -Depth 20|ConvertFrom-Json)}

$prov=New-ProvenanceRow
$repo=New-Observation
$tree=[string]$repo.tree_sha256
Assert-True (Test-CustomAppRemoteSha256 $tree) 'Fixture tree fingerprint is invalid.'

# 1. First exact content match may only produce an observer binding candidate.
$enroll=Resolve-CustomAppRemoteSourceContract -ProvenanceRow $prov -RemoteObservation $repo -Binding $null -CurrentLocalTreeSha256 $tree -CurrentLocalManifestName 'Fixture App'
Assert-Eq $enroll.status 'binding-enrollment-candidate' 'Exact initial content match was not recognized.'
Assert-True $enroll.conclusive 'Initial binding candidate should be conclusive.'
Assert-True $enroll.enrollment_candidate 'Initial binding candidate flag missing.'
Assert-False $enroll.repo_id_verified 'First observation must not claim previously-bound repo ID continuity.'
Assert-Denied $enroll 'Initial enrollment'
$binding=$enroll.binding_candidate
Assert-Eq $binding.managed_by 'custom-app-remote-source-v1' 'Binding owner mismatch.'
Assert-Eq $binding.github_repo_id 12345 'Binding numeric repo ID mismatch.'
Assert-Eq $binding.mutation_mode 'deny' 'Binding mutation mode drift.'

# 2. Same bound source/tree is current.
$current=Resolve-CustomAppRemoteSourceContract $prov $repo $binding $tree 'Fixture App'
Assert-Eq $current.status 'remote-current' 'Bound current tree was not current.'
Assert-True $current.repo_id_verified 'Bound repo ID continuity was not verified.'
Assert-True $current.local_continuity_verified 'Local continuity was not verified.'
Assert-False $current.update_observed 'Current tree incorrectly reported an update.'
Assert-Denied $current 'Current observation'

# 3. Same repo/surface with a new safe tree is observed, still mutation-denied.
$changed=New-Observation -Commit $Commit2 -Files @(New-FileEntry 'index.js' $H1 100;New-FileEntry 'manifest.json' $H2 200;New-FileEntry 'style.css' $H3 300)
$update=Resolve-CustomAppRemoteSourceContract $prov $changed $binding $tree 'Fixture App'
Assert-Eq $update.status 'remote-change-observed' 'New verified tree was not observed.'
Assert-True $update.update_observed 'New verified tree did not set update_observed.'
Assert-Denied $update 'Remote change observation'

# 4. Initial nonmatching remote content cannot bind.
$noMatch=Resolve-CustomAppRemoteSourceContract $prov $changed $null $tree 'Fixture App'
Assert-Eq $noMatch.status 'initial-content-match-required' 'Initial mismatched content did not fail closed.';Assert-Denied $noMatch 'Initial mismatch'

# 5-9. Provenance authority and continuity gates.
$d=Resolve-CustomAppRemoteSourceContract (New-ProvenanceRow -SourceChanged $true) $repo $null $tree 'Fixture App';Assert-Eq $d.reason 'provenance-reenrollment-required' 'Source-changed provenance escaped.';Assert-Denied $d 'Source-changed provenance'
$d=Resolve-CustomAppRemoteSourceContract (New-ProvenanceRow -RequiresReenrollment $true) $repo $null $tree 'Fixture App';Assert-Eq $d.reason 'provenance-reenrollment-required' 'Re-enrollment provenance escaped.';Assert-Denied $d 'Re-enrollment provenance'
$d=Resolve-CustomAppRemoteSourceContract (New-ProvenanceRow -MutationMode 'auto') $repo $null $tree 'Fixture App';Assert-Eq $d.reason 'provenance-authority-drift' 'Provenance authority drift escaped.';Assert-Denied $d 'Provenance authority drift'
$d=Resolve-CustomAppRemoteSourceContract (New-ProvenanceRow -AutoUpdate $true) $repo $null $tree 'Fixture App';Assert-Eq $d.reason 'provenance-authority-drift' 'Provenance auto-update drift escaped.';Assert-Denied $d 'Provenance auto update drift'
$d=Resolve-CustomAppRemoteSourceContract (New-ProvenanceRow -LastProvenSource 'example/other') $repo $null $tree 'Fixture App';Assert-Eq $d.reason 'provenance-history-mismatch' 'Provenance history mismatch escaped.';Assert-Denied $d 'Provenance history mismatch'

# 10-17. Remote identity/transport/archive safety gates.
foreach($case in @(
    @{o=(New-Observation -Source 'evil/app');reason='remote-source-mismatch';label='source mismatch'},
    @{o=(New-Observation -RepoId 0);reason='remote-repo-id-invalid';label='repo id invalid'},
    @{o=(New-Observation -Commit 'main');reason='remote-commit-not-immutable-sha';label='mutable ref'},
    @{o=(New-Observation -Transport 'http');reason='remote-transport-not-pinned-https';label='insecure transport'},
    @{o=(New-Observation -ArchiveUnsafe $true);reason='remote-archive-unsafe-entry';label='archive unsafe'},
    @{o=(New-Observation -Symlink $true);reason='remote-archive-unsafe-entry';label='symlink'},
    @{o=(New-Observation -Hardlink $true);reason='remote-archive-unsafe-entry';label='hardlink'},
    @{o=(New-Observation -Submodule $true);reason='remote-archive-unsafe-entry';label='submodule'},
    @{o=(New-Observation -Device $true);reason='remote-archive-unsafe-entry';label='device entry'}
)){
    $d=Resolve-CustomAppRemoteSourceContract $prov $case.o $null $tree 'Fixture App';Assert-Eq $d.reason $case.reason "Remote $($case.label) did not fail closed.";Assert-Denied $d "Remote $($case.label)"
}

# 18-23. Installable-root and metadata gates.
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -BuildRequired $true) $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-surface-requires-build' 'Build-required source escaped.';Assert-Denied $d 'Build required'
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -AppRootCount 2) $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-app-root-not-unique-root' 'Multiple app roots escaped.';Assert-Denied $d 'Multiple app roots'
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -LayoutRoot 'dist/app') $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-app-root-not-unique-root' 'Nested inferred root escaped.';Assert-Denied $d 'Nested root'
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -ManifestValid $false) $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-manifest-invalid' 'Invalid manifest escaped.';Assert-Denied $d 'Invalid manifest'
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -PackageSource 'evil/app') $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-package-repository-conflict' 'Package source conflict escaped.';Assert-Denied $d 'Package source conflict'
$d=Resolve-CustomAppRemoteSourceContract $prov (New-Observation -ManifestName 'Other App') $null $tree 'Fixture App';Assert-Eq $d.status 'manifest-identity-drift' 'Manifest identity drift escaped.';Assert-Denied $d 'Manifest identity drift'

# 24-31. Archive path/resource/file-set hazards.
$hazards=@(
    @{files=@(New-FileEntry '..\evil.js' $H1 1;New-FileEntry 'index.js' $H1 1;New-FileEntry 'manifest.json' $H2 1);reason='path-backslash-denied';label='backslash'},
    @{files=@(New-FileEntry '../evil.js' $H1 1;New-FileEntry 'index.js' $H1 1;New-FileEntry 'manifest.json' $H2 1);reason='path-dot-or-empty-segment';label='traversal'},
    @{files=@(New-FileEntry 'index.js:evil' $H1 1;New-FileEntry 'manifest.json' $H2 1);reason='path-ads-or-colon';label='ADS'},
    @{files=@(New-FileEntry 'CON' $H1 1;New-FileEntry 'index.js' $H1 1;New-FileEntry 'manifest.json' $H2 1);reason='path-windows-reserved-name';label='reserved'},
    @{files=@(New-FileEntry 'Index.js' $H1 1;New-FileEntry 'index.js' $H2 1;New-FileEntry 'manifest.json' $H3 1);reason='case-insensitive-duplicate-path';label='case collision'},
    @{files=@(New-FileEntry 'index.js' 'bad' 1;New-FileEntry 'manifest.json' $H2 1);reason='file-sha256-invalid';label='bad file hash'},
    @{files=@(New-FileEntry 'index.js' $H1 67108865;New-FileEntry 'manifest.json' $H2 1);reason='individual-file-size-limit';label='large file'},
    @{files=@(New-FileEntry 'manifest.json' $H2 1;New-FileEntry 'style.css' $H3 1);reason='root-index-js-missing';label='missing index'},
    @{files=@(New-FileEntry 'index.js' $H1 1;New-FileEntry 'style.css' $H3 1);reason='root-manifest-json-missing';label='missing manifest'}
)
foreach($case in $hazards){$o=New-Observation -Files $case.files;$d=Resolve-CustomAppRemoteSourceContract $prov $o $null $tree 'Fixture App';Assert-Eq $d.reason $case.reason "Archive $($case.label) did not fail closed.";Assert-Denied $d "Archive $($case.label)"}

$o=New-Observation;$o.tree_sha256=$H4;$d=Resolve-CustomAppRemoteSourceContract $prov $o $null $tree 'Fixture App';Assert-Eq $d.reason 'declared-tree-fingerprint-mismatch' 'Declared tree fingerprint mismatch escaped.';Assert-Denied $d 'Tree fingerprint mismatch'
$o=New-Observation -Surface 'unsupported';$d=Resolve-CustomAppRemoteSourceContract $prov $o $null $tree 'Fixture App';Assert-Eq $d.reason 'remote-surface-kind-unsupported' 'Unsupported surface escaped.';Assert-Denied $d 'Unsupported surface'

# 32-35. Binding continuity hard failures.
$b=Clone-Binding $binding;$b.github_repo_id=99999;$d=Resolve-CustomAppRemoteSourceContract $prov $repo $b $tree 'Fixture App';Assert-Eq $d.status 'repo-id-drift' 'Numeric repo-id drift escaped.';Assert-Denied $d 'Repo-id drift'
$b=Clone-Binding $binding;$b.last_verified_local_tree_sha256=$H4;$d=Resolve-CustomAppRemoteSourceContract $prov $repo $b $tree 'Fixture App';Assert-Eq $d.status 'local-tree-drift' 'Local tree drift escaped.';Assert-Denied $d 'Local tree drift'
$b=Clone-Binding $binding;$b.mutation_mode='auto';$d=Resolve-CustomAppRemoteSourceContract $prov $repo $b $tree 'Fixture App';Assert-Eq $d.reason 'binding-authority-drift' 'Binding authority drift escaped.';Assert-Denied $d 'Binding authority drift'
$b=Clone-Binding $binding;$b.source_identity='evil/app';$d=Resolve-CustomAppRemoteSourceContract $prov $repo $b $tree 'Fixture App';Assert-Eq $d.reason 'binding-source-mismatch' 'Binding source mismatch escaped.';Assert-Denied $d 'Binding source mismatch'

# 36-40. Release asset contract and continuity.
$release=New-Observation -Surface 'release-asset' -AssetName 'fixture-app.zip'
$releaseTree=[string]$release.tree_sha256
$re=Resolve-CustomAppRemoteSourceContract $prov $release $null $releaseTree 'Fixture App'
Assert-Eq $re.status 'binding-enrollment-candidate' 'Valid release asset exact match could not enroll.';Assert-Denied $re 'Release enrollment'
$releaseBinding=$re.binding_candidate
$rc=Resolve-CustomAppRemoteSourceContract $prov $release $releaseBinding $releaseTree 'Fixture App';Assert-Eq $rc.status 'remote-current' 'Bound release asset did not remain current.';Assert-Denied $rc 'Release current'
$releaseChanged=New-Observation -Surface 'release-asset' -Commit $Commit2 -AssetName 'fixture-app.zip' -ReleaseId 778 -AssetId 889 -AssetDigest $H3 -Files @(New-FileEntry 'index.js' $H1 100;New-FileEntry 'manifest.json' $H2 200;New-FileEntry 'style.css' $H3 300)
$ru=Resolve-CustomAppRemoteSourceContract $prov $releaseChanged $releaseBinding $releaseTree 'Fixture App';Assert-Eq $ru.status 'remote-change-observed' 'Release update was not observed.';Assert-Denied $ru 'Release update'
$badRelease=New-Observation -Surface 'release-asset' -AssetDigest '';$d=Resolve-CustomAppRemoteSourceContract $prov $badRelease $null $releaseTree 'Fixture App';Assert-Eq $d.reason 'release-asset-identity-invalid' 'Release missing digest escaped.';Assert-Denied $d 'Release digest missing'
$renamed=New-Observation -Surface 'release-asset' -AssetName 'renamed.zip';$d=Resolve-CustomAppRemoteSourceContract $prov $renamed $releaseBinding $releaseTree 'Fixture App';Assert-Eq $d.status 'release-asset-continuity-drift' 'Release asset rename escaped.';Assert-Denied $d 'Release asset rename'

# 41. Local baseline must be a real SHA-256.
$d=Resolve-CustomAppRemoteSourceContract $prov $repo $null 'bad' 'Fixture App';Assert-Eq $d.status 'local-baseline-invalid' 'Invalid local baseline escaped.';Assert-Denied $d 'Invalid local baseline'

Write-Host 'CUSTOM_APP_REMOTE_SOURCE_CONTRACT_ACCEPTANCE_PASS cases=41'
