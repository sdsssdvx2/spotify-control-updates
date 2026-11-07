# V028: real GitHub SOURCE ACQUISITION only for an already installed and
# authorized Addon Manager custom app. No operating mutation or HMAC permit.
# Reuses V026 approved source owner policy, existing observer bounded HTTPS
# download, safe ZIP extraction and full SHA-256 runtime baseline.
function Get-ApprovedLiveSourcePolicyV028 {
    param([Parameter(Mandatory=$true)]$Item)
    $q=Resolve-ApprovedCustomAppScopedNativeV026 -Item $Item
    if(-not[bool]$q.ok -or [bool]$q.production_mutation_authorized){
        throw ('V028_INSTALLED_ONLY_SOURCE_POLICY_DENIED:'+ [string]$q.reason)
    }
    $branch=$null;$manifest=$null;$repoId=[int64]605674911;$type='pithaya-branch'
    switch -CaseSensitive ([string]$q.name){
      'better-local-files' {$branch='dist/better-local-files';$manifest='Local Files'}
      'eternal-jukebox' {$branch='dist/eternal-jukebox';$manifest='Eternal Jukebox'}
      'playlist-maker' {$branch='dist/playlist-maker';$manifest='Playlist maker'}
      'ivLyrics' {$type='ivlyrics-release';$manifest='ivLyrics';$repoId=[int64]1061316081}
      default {throw 'V028_NO_EXPLICIT_SOURCE_ADAPTER'}
    }
    return [pscustomobject]@{
      name=[string]$q.name;source=[string]$q.source;type=$type
      branch=$branch;manifest_name=$manifest;repository_id=$repoId
      handler=[string]$q.handler;registry_sha256=[string]$q.registry_sha256
      production_mutation_authorized=$false
    }
}
function Get-ApprovedLiveRemoteSnapshotV028 {
    param([Parameter(Mandatory=$true)]$Policy)
    $n=[string]$Policy.name;$type=[string]$Policy.type
    $expectedSource=if($type -ceq 'ivlyrics-release'){'ivLis-Studio/ivLyrics'}else{'Pithaya/spicetify-apps-dist'}
    $expectedId=if($type -ceq 'ivlyrics-release'){[int64]1061316081}else{[int64]605674911}
    $expectedBranch=if($type -ceq 'pithaya-branch'){'dist/'+$n}else{$null}
    $expectedManifest=switch -CaseSensitive ($n){
      'better-local-files' {'Local Files'}
      'eternal-jukebox' {'Eternal Jukebox'}
      'playlist-maker' {'Playlist maker'}
      'ivLyrics' {'ivLyrics'}
      default {throw 'V028_UNKNOWN_APPROVED_APP'}
    }
    if([string]$Policy.source -cne $expectedSource -or
       [int64]$Policy.repository_id -ne $expectedId -or
       [string]$Policy.branch -cne [string]$expectedBranch -or
       [string]$Policy.manifest_name -cne $expectedManifest -or
       [string]$Policy.registry_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
       [bool]$Policy.production_mutation_authorized){
       throw 'V028_SOURCE_ID_BRANCH_OR_DISPLAY_MANIFEST_DRIFT'
    }
    $api=Get-CustomAppObserverRepoApiBase -Source ([string]$Policy.source)
    $repo=Invoke-CustomAppObserverApiJson -Uri $api
    if([int64]$repo.id -ne $expectedId -or
       ([string]$repo.full_name).ToLowerInvariant() -cne $expectedSource.ToLowerInvariant() -or
       [bool]$repo.private -or [bool]$repo.archived){
       throw 'V028_GITHUB_REPO_ID_OR_STATE_CHANGED'
    }
    $commit=$null;$tag=$null;$releaseId=[int64]0;$assetId=[int64]0
    $digest=$null;$assetBytes=[int64]0;$url=$null
    if($type -ceq 'pithaya-branch'){
        $ref='refs/heads/'+$expectedBranch
        $remote=Invoke-CustomAppObserverApiJson -Uri ($api+'/git/ref/heads/'+$expectedBranch)
        if([string]$remote.ref -cne $ref -or
           [string]$remote.object.type -cne 'commit' -or
           ([string]$remote.object.sha) -cnotmatch '^[a-f0-9]{40}$'){
            throw 'V028_PINNED_PITHAYA_BRANCH_NOT_COMMIT'
        }
        $commit=[string]$remote.object.sha
        $url='https://codeload.github.com/Pithaya/spicetify-apps-dist/zip/'+$commit
    }else{
        $release=Invoke-CustomAppObserverApiJson -Uri ($api+'/releases/latest')
        $tag=[string]$release.tag_name
        if([bool]$release.draft -or [bool]$release.prerelease -or
           [int64]$release.id -le 0 -or $tag -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+$'){
           throw 'V028_NO_QUALIFIED_IVLYRICS_STABLE_RELEASE'
        }
        $assets=@($release.assets|Where-Object{[string]$_.name -ceq 'ivLyrics.zip'})
        if($assets.Count -ne 1){throw 'V028_IVLYRICS_RELEASE_ZIP_NOT_UNIQUE'}
        $asset=$assets[0];$digest=[string]$asset.digest
        $releaseId=[int64]$release.id;$assetId=[int64]$asset.id
        $assetBytes=[int64]$asset.size
        $url='https://github.com/ivLis-Studio/ivLyrics/releases/download/'+$tag+'/ivLyrics.zip'
        if($digest -cnotmatch '^sha256:[0-9a-f]{64}$' -or
           $assetId -le 0 -or $assetBytes -le 0 -or $assetBytes -gt 67108864 -or
           ([string]$asset.browser_download_url) -cne $url){
            throw 'V028_RELEASE_ASSET_DIGEST_SIZE_OR_URL_DRIFT'
        }
        $ref=Invoke-CustomAppObserverApiJson -Uri ($api+'/git/ref/tags/'+$tag)
        if([string]$ref.ref -cne ('refs/tags/'+$tag) -or
           [string]$ref.object.type -cne 'commit' -or
           ([string]$ref.object.sha) -cnotmatch '^[a-f0-9]{40}$'){
            throw 'V028_RELEASE_TAG_NO_EXACT_COMMIT'
        }
        $commit=[string]$ref.object.sha
    }
    return [pscustomobject]@{
      name=$n;source=[string]$Policy.source;type=$type;branch=$expectedBranch
      manifest_name=$expectedManifest;repository_id=$expectedId
      registry_sha256=[string]$Policy.registry_sha256;commit_sha=$commit
      release_tag=$tag;release_id=$releaseId;asset_id=$assetId
      asset_digest=$digest;asset_bytes=$assetBytes;archive_uri=$url
      production_mutation_authorized=$false
    }
}
function Get-ApprovedLiveRemoteSnapshotMaterialV028 {
    param([Parameter(Mandatory=$true)]$Snapshot)
    $fields=@('name','source','type','branch','manifest_name','repository_id',
       'registry_sha256','commit_sha','release_tag','release_id',
       'asset_id','asset_digest','asset_bytes','archive_uri')
    return ($fields|ForEach-Object{[string]$Snapshot.$_}) -join [Environment]::NewLine
}
function Invoke-ApprovedLiveSourceAcquireV028 {
    param([Parameter(Mandatory=$true)]$Item)
    $policy=Get-ApprovedLiveSourcePolicyV028 -Item $Item
    $before=Get-ApprovedLiveRemoteSnapshotV028 -Policy $policy
    $workspace=$null;$success=$false
    try{
        $workspace=New-CustomAppStageWorkspaceV010
        $zip=Join-Path $workspace 'pinned-upstream.zip'
        $dl=Invoke-CustomAppObserverBoundedDownload -Uri ([string]$before.archive_uri) -Destination $zip -MaxBytes 67108864
        $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]$before.type -ceq 'ivlyrics-release'){
            if($zipHash -cne ([string]$before.asset_digest).Substring(7) -or
                [int64]$dl.bytes -ne [int64]$before.asset_bytes){
                throw 'V028_RELEASE_ARCHIVE_BYTE_DIGEST_MISMATCH'
            }
        }
        $ev=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode auto
        if([bool]$ev.build_required -or -not[bool]$ev.manifest_valid -or
           [int]$ev.app_root_count -ne 1 -or [string]$ev.layout_root -cne '.' -or
           [string]$ev.manifest_name -cne [string]$policy.manifest_name){
            throw 'V028_CURRENT_ARCHIVE_NOT_EXPECTED_SINGLE_APP'
        }
        $stage=Join-Path $workspace ('prepared-'+[string]$policy.name)
        $extract=Expand-CustomAppStageArchiveV010 -ZipPath $zip -Destination $stage -ValidationRoot $workspace -WrapperMode auto -Name ([string]$policy.name) -ExpectedTreeSha256 ([string]$ev.tree_sha256) -ExpectedManifestName ([string]$policy.manifest_name)
        if(-not[bool]$extract.baseline.installable -or
           [string]$extract.tree_sha256 -cne [string]$ev.tree_sha256 -or
           [int]$extract.file_count -ne [int]$ev.file_count){
            throw 'V028_EXTRACTED_FULL_TREE_MISMATCH'
        }
        $after=Get-ApprovedLiveRemoteSnapshotV028 -Policy $policy
        if((Get-ApprovedLiveRemoteSnapshotMaterialV028 $before) -cne
           (Get-ApprovedLiveRemoteSnapshotMaterialV028 $after)){
            throw 'V028_REMOTE_REF_CHANGED_DURING_STAGE_DOWNLOAD'
        }
        $currentPolicy=Get-ApprovedLiveSourcePolicyV028 -Item $Item
        if([string]$currentPolicy.registry_sha256 -cne [string]$policy.registry_sha256 -or
           [string]$currentPolicy.name -cne [string]$policy.name){
            throw 'V028_LOCAL_INSTALLED_OWNER_POLICY_DRIFT'
        }
        $tree=Get-CustomAppLocalRuntimeBaseline -Name ([string]$policy.name) -AppPath $stage
        if(-not[bool]$tree.safe -or -not[bool]$tree.installable -or
           [string]$tree.tree_sha256 -cne [string]$ev.tree_sha256){
            throw 'V028_FINAL_STAGE_SHA_CHANGED'
        }
        $material=@('approved-real-remote-v028',(Get-ApprovedLiveRemoteSnapshotMaterialV028 $before),
            $zipHash,[string]$ev.tree_sha256,[string]$ev.file_count,[string]$ev.expanded_bytes) -join [Environment]::NewLine
        $fingerprint=Get-CustomAppObserverStringSha256 $material
        $success=$true
        return [pscustomobject]@{
          ok=$true;schema=1;managed_by='approved-live-source-acquisition-v028'
          name=[string]$policy.name;source=[string]$policy.source
          source_snapshot=$before;source_provenance_sha256=$fingerprint
          workspace_path=$workspace;archive_path=$zip;archive_sha256=$zipHash
          stage_path=$stage;runtime_tree_sha256=[string]$tree.tree_sha256
          manifest_name=[string]$tree.manifest_name
          file_count=[int]$tree.file_count;total_bytes=[int64]$tree.total_bytes
          ready_for_separate_cryptographic_permit=$true
          authenticated_hmac_permit=$false;installed_spotify_touched=$false
          spicetify_executed=$false;production_execution_authorized=$false
          production_mutation_authorized=$false
        }
    }finally{
        if(-not$success -and $null-ne$workspace){
           Remove-CustomAppStageWorkspaceV010 -Path $workspace
        }
    }
}
