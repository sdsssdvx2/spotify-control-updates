$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot=Split-Path -Parent (Split-Path -Parent $here)
$depRoot=Join-Path $env:TEMP ('custom-app-shadow-live-deps-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $depRoot|Out-Null

function Get-PinnedLiveDependencyFile {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$RepoPath,[Parameter(Mandatory=$true)][string]$Name)
    $lines=@(& git -C $repoRoot show "$Commit`:$RepoPath")
    if($LASTEXITCODE -ne 0){throw "Could not materialize pinned live dependency: $Commit`:$RepoPath"}
    $out=Join-Path $depRoot $Name
    [IO.File]::WriteAllText($out,(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
    return $out
}

. (Get-PinnedLiveDependencyFile '57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b' 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1' 'lifecycle-settings-core.ps1')
. (Get-PinnedLiveDependencyFile 'b339f2b79a267c13cf3c5974aea2fff3786d3093' 'validation/custom-app-provenance-enrollment-v0.1.0/custom-app-provenance.ps1' 'custom-app-provenance.ps1')
. (Get-PinnedLiveDependencyFile '7d22b55c58c6e85a8a3ec9396800e65d81b0e7d2' 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1' 'custom-app-remote-observer.ps1')
. (Get-PinnedLiveDependencyFile '7d22b55c58c6e85a8a3ec9396800e65d81b0e7d2' 'validation/custom-app-remote-observation-collector-v0.1.1/release-id-fix-v011.ps1' 'release-id-fix-v011.ps1')
. (Get-PinnedLiveDependencyFile '19109205bd2e61e862c3b9acd61946568397ecb5' 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1' 'custom-app-remote-source-contract.ps1')
. (Get-PinnedLiveDependencyFile '19109205bd2e61e862c3b9acd61946568397ecb5' 'validation/custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1' 'release-continuity-v011.ps1')
. (Get-PinnedLiveDependencyFile '7402ea5c77e58cd072f0166411d40e7726093f3c' 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1' 'custom-app-local-runtime-baseline.ps1')
. (Get-PinnedLiveDependencyFile 'c420a1df6f306c7ba74772b91241cb14abd04738' 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1' 'custom-app-stage-acquisition.ps1')
. (Get-PinnedLiveDependencyFile '1a2461a6929e9cabd50d27f95e0744f83443b9e8' 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1' 'custom-app-update-transaction.ps1')
. (Join-Path $here 'custom-app-shadow-executor.ps1')
. (Join-Path $here 'shadow-executor-safety-overlay.ps1')

# Standalone equivalents of the stable Addon Manager base helpers required by the
# pinned lifecycle/settings insertion core. They are deliberately conservative and
# the core independently re-fingerprints every persistence backup/restore.
function Test-PathSafe {
    param([AllowNull()][string]$Path,[ValidateSet('Leaf','Container')][string]$Kind)
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    try{return [bool](Test-Path -LiteralPath $Path -PathType $Kind -ErrorAction Stop)}catch{return $false}
}
function Copy-TreeSafe {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    if(-not(Test-PathSafe $Source 'Container')){throw 'Copy-TreeSafe source is missing.'}
    $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $root=Get-Item -LiteralPath $src -Force -ErrorAction Stop
    if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Copy-TreeSafe source root is a reparse point.'}
    if(Test-Path -LiteralPath $Destination){throw 'Copy-TreeSafe destination already exists.'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($Destination))|Out-Null
    foreach($entry in @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction Stop)){
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Copy-TreeSafe source contains reparse point: $($entry.FullName)"}
        $rel=$entry.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $target=Join-Path $Destination $rel
        if($entry.PSIsContainer){[IO.Directory]::CreateDirectory($target)|Out-Null}
        else{$parent=Split-Path -Parent $target;if(-not(Test-Path $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($entry.FullName,$target,$false)}
    }
    return [IO.Path]::GetFullPath($Destination)
}

function New-TagifyReleaseBindingRow {
    param(
        [Parameter(Mandatory=$true)]$Observation,
        [Parameter(Mandatory=$true)][string]$LocalTreeSha256,
        [Parameter(Mandatory=$true)][string]$LocalManifestName
    )
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity='alexk218/tagify';github_repo_id=[int64]$Observation.github_repo_id
        surface_kind='release-asset';layout_root='.';manifest_name=[string]$Observation.manifest_name
        last_verified_local_tree_sha256=$LocalTreeSha256;last_verified_remote_tree_sha256=[string]$Observation.tree_sha256;last_verified_commit_sha=[string]$Observation.commit_sha
        release_asset_selector='unique-zip-asset';asset_name=[string]$Observation.asset_name;last_observed_asset_id=[int64]$Observation.asset_id;last_observed_asset_digest_sha256=[string]$Observation.asset_digest_sha256
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name='tagify';active=$true;source_identity='alexk218/tagify';binding=$binding
        last_success='2026-10-28T12:00:00+00:00';last_status='remote-change-observed'
        last_local_tree_sha256=$LocalTreeSha256;last_local_manifest_name=$LocalManifestName
        last_remote_tree_sha256=[string]$Observation.tree_sha256;last_remote_commit_sha=[string]$Observation.commit_sha
        update_observed=$true;requires_reenrollment=$false;user_removed=$false
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
}

$old=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 416245914
$new=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 418974188
if([int64]$old.github_repo_id -ne 1021838879 -or [string]$old.commit_sha -cne '0be36dced09c5b5b7fef14726a69b99148bee432' -or [int64]$old.asset_id -ne 652536027 -or [string]$old.asset_digest_sha256 -cne 'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957'){throw 'Pinned Tagify v3.3.1 identity drift.'}
if([int64]$new.github_repo_id -ne 1021838879 -or [string]$new.commit_sha -cne 'bacd80f76c621a3acc06965bb3160ce1056fad7b' -or [int64]$new.asset_id -ne 660754674 -or [string]$new.asset_digest_sha256 -cne '5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b'){throw 'Pinned Tagify v3.3.2 identity drift.'}

$stageRoot=Get-CustomAppStageWorkspaceRootV010
if(-not(Test-Path -LiteralPath $stageRoot)){New-Item -ItemType Directory -Force -Path $stageRoot|Out-Null}
$fixture=Join-Path $stageRoot ('tagify-shadow-live-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixture|Out-Null
$oldStage=$null
try {
    $oldBinding=New-TagifyReleaseBindingRow -Observation $old -LocalTreeSha256 ([string]$old.tree_sha256) -LocalManifestName ([string]$old.manifest_name)
    $oldStage=Invoke-CustomAppStageAcquisitionV010 -Name 'tagify' -BindingRow $oldBinding
    if([string]$oldStage.status -cne 'staged-verified' -or [string]$oldStage.stage_baseline.tree_sha256 -cne [string]$old.tree_sha256){throw 'Pinned Tagify v3.3.1 stage acquisition drift.'}

    $live=Join-Path $fixture 'live'
    [void](Copy-CustomAppUpdateTreeFixtureV010 -Source ([string]$oldStage.stage_path) -Destination $live -ValidationRoot $stageRoot)
    Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path);$oldStage=$null

    $gitDir=Join-Path $live '.git';New-Item -ItemType Directory -Force -Path $gitDir|Out-Null
    $gitConfig=((@('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/alexk218/tagify.git') -join "`n")+"`n")
    [IO.File]::WriteAllText((Join-Path $gitDir 'config'),$gitConfig,[Text.UTF8Encoding]::new($false))
    $current=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $live
    if(-not [bool]$current.safe -or -not [bool]$current.installable -or [string]$current.tree_sha256 -cne [string]$old.tree_sha256){throw 'Pinned Tagify v3.3.1 live fixture baseline drift.'}

    $lifecycle=[pscustomobject]@{
        managed_by='dynamic-spicetify-v1';kind='custom-app';name='tagify';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true
        locations=@($live);mutation_mode='deny'
    }
    $lifeRoot=[pscustomobject]@{};$lifeRoot|Add-Member -NotePropertyName 'custom-app:tagify' -NotePropertyValue $lifecycle
    $state=[pscustomobject]@{lifecycle=$lifeRoot}
    $provEvidence=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath $live
    $provenance=Update-CustomAppProvenanceEnrollment -State $state -Evidence $provEvidence -ObservedAt '2026-10-28T12:01:00+00:00'
    if([string]$provenance.source_identity -cne 'alexk218/tagify' -or [string]$provenance.mutation_mode -cne 'deny' -or [bool]$provenance.auto_update_authorized -or [bool]$provenance.auto_install_authorized){throw "Live Tagify provenance enrollment failed: $($provenance.source_status)"}

    $newBinding=New-TagifyReleaseBindingRow -Observation $new -LocalTreeSha256 ([string]$current.tree_sha256) -LocalManifestName ([string]$current.manifest_name)
    $bindingCheck=Test-CustomAppStageBindingRowV010 -BindingRow $newBinding -ExpectedName 'tagify'
    if(-not [bool]$bindingCheck.ok){throw "Live Tagify v3.3.2 binding row denied: $($bindingCheck.reason)"}

    $localRoot=Join-Path $fixture 'persistence\Local'
    $appRoot=Join-Path $fixture 'persistence\Roaming'
    $backupRoot=Join-Path $fixture 'persistence\Backups'
    $ldb=Join-Path $localRoot 'Spotify\Browser\Local Storage\leveldb\000001.ldb'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ldb)|Out-Null
    [IO.File]::WriteAllText($ldb,'tagify-persistence-fixture',[Text.UTF8Encoding]::new($false))
    $spicetifyConfig=Join-Path $appRoot 'spicetify\config-xpui.ini'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $spicetifyConfig)|Out-Null
    [IO.File]::WriteAllText($spicetifyConfig,"[AdditionalOptions]`ncustom_apps = tagify`n",[Text.UTF8Encoding]::new($false))
    $persistenceBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot

    $result=Invoke-CustomAppShadowExecutorV010 -Name 'tagify' -LifecycleRow $lifecycle -ProvenanceRow $provenance -BindingRow $newBinding -LocalAppDataRoot $localRoot -AppDataRoot $appRoot -PersistenceBackupRoot $backupRoot
    if([string]$result.status -cne 'committed-shadow-fixture' -or -not [bool]$result.committed -or [bool]$result.production_mutation_authorized){throw "Live Tagify shadow execution failed: $($result.status) / $($result.reason)"}

    $after=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $live
    if([string]$after.tree_sha256 -cne [string]$new.tree_sha256 -or [string]$after.manifest_name -cne [string]$new.manifest_name){throw 'Live Tagify shadow update did not install exact v3.3.2 runtime tree.'}
    $persistenceAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
    if([string]$persistenceAfter.fingerprint -cne [string]$persistenceBefore.fingerprint){throw 'Live Tagify shadow update changed Spotify/Spicetify persistence.'}
    $postProv=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath $live
    if(-not [bool]$postProv.source_proven -or ([string]$postProv.source_candidate).Trim().ToLowerInvariant() -cne 'alexk218/tagify' -or $null -eq $postProv.git -or -not [bool]$postProv.git.safe){throw 'Live Tagify post-update provenance was not strongly re-proven.'}
    if([string]$postProv.git.file_sha256 -cne [string]$provEvidence.git.file_sha256){throw 'Live Tagify .git/config provenance bytes changed across shadow update.'}

    Write-Host "CUSTOM_APP_SHADOW_LIVE_TAGIFY_PASS old=$($old.tree_sha256) new=$($new.tree_sha256) tx=$($result.transaction_id) persistence=$($persistenceAfter.fingerprint)"
} finally {
    if($null -ne $oldStage -and $oldStage.PSObject.Properties['workspace_path']){try{Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path)}catch{}}
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $depRoot){Remove-Item -LiteralPath $depRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
