$CustomAppRemoteObserverReleaseIdFixSchema = 1

function ConvertTo-CustomAppObserverReleaseIdV011 {
    param([AllowNull()]$ReleaseId)
    if($null -eq $ReleaseId){return $null}
    try{$value=[Convert]::ToInt64($ReleaseId,[Globalization.CultureInfo]::InvariantCulture)}
    catch{throw 'Remote observer release ID is not a valid Int64.'}
    if($value -le 0){throw 'Remote observer release ID must be a positive Int64 when explicitly supplied.'}
    return $value
}

# v0.1.1 amendment: PowerShell may expose a Nullable[Int64] parameter as its
# unboxed Int64 value, so reading `$ReleaseId.Value` can silently yield $null.
# Normalize the supplied scalar directly and use null alone to mean "latest".
function Get-CustomAppObserverReleaseObservation {
    param([Parameter(Mandatory=$true)][string]$Source,[Nullable[Int64]]$ReleaseId=$null)
    $repo=Get-CustomAppObserverRepositoryMetadata $Source;$base=[string]$repo.api_base
    $releaseIdValue=ConvertTo-CustomAppObserverReleaseIdV011 $ReleaseId
    $releaseUri=$(if($null -ne $releaseIdValue){$base+'/releases/'+$releaseIdValue}else{$base+'/releases/latest'})
    $release=Invoke-CustomAppObserverApiJson $releaseUri
    if([bool]$release.draft -or [bool]$release.prerelease){throw 'Remote observer release is draft or prerelease.'}
    if([int64]$release.id -le 0 -or [string]::IsNullOrWhiteSpace([string]$release.tag_name)){throw 'Remote observer release identity is incomplete.'}
    if($null -ne $releaseIdValue -and [int64]$release.id -ne $releaseIdValue){throw 'Remote observer release endpoint returned a different release ID than requested.'}
    $assets=Invoke-CustomAppObserverApiJson ([string]$release.assets_url+'?per_page=100')
    $all=@($assets)
    if($all.Count -ge 100){throw 'Remote observer release asset list is too large to prove complete unique-ZIP selection.'}
    $zips=@($all|Where-Object{([string]$_.name).EndsWith('.zip',[StringComparison]::OrdinalIgnoreCase)})
    $commit=Resolve-CustomAppObserverReleaseTagCommit -Source ([string]$repo.source_identity) -TagName ([string]$release.tag_name)
    if($zips.Count -ne 1){
        return [pscustomobject]@{schema=$CustomAppRemoteObserverSchema;source_identity=[string]$repo.source_identity;github_repo_id=[int64]$repo.github_repo_id;transport='github-api-https';commit_sha=$commit;surface_kind='release-asset';release_id=[int64]$release.id;release_tag=[string]$release.tag_name;release_zip_asset_count=$zips.Count;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
    }
    $asset=$zips[0]
    $digest=([string]$asset.digest).ToLowerInvariant()
    if($digest -notmatch '^sha256:[0-9a-f]{64}$'){throw 'Remote observer release ZIP does not expose a GitHub SHA-256 asset digest.'}
    if([int64]$asset.id -le 0 -or [int64]$asset.size -le 0 -or [int64]$asset.size -gt 134217728){throw 'Remote observer release ZIP identity/size is unsafe.'}
    if([string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)){throw 'Remote observer release ZIP download URL is missing.'}
    $temp=New-CustomAppObserverTempDirectory
    try{
        $zip=Join-Path $temp 'release.zip'
        $download=Invoke-CustomAppObserverBoundedDownload -Uri ([string]$asset.browser_download_url) -Destination $zip -MaxBytes 134217728
        if([int64]$download.bytes -ne [int64]$asset.size){throw 'Remote observer release ZIP downloaded byte count does not match GitHub asset size.'}
        $actual=Get-CustomAppObserverFileSha256 $zip;$expected=$digest.Substring(7)
        if($actual -cne $expected){throw 'Remote observer release ZIP SHA-256 does not match GitHub asset digest.'}
        $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode auto
        return New-CustomAppObserverObservation -Repo $repo -CommitSha $commit -SurfaceKind 'release-asset' -ZipEvidence $evidence -Release $release -Asset $asset -ReleaseZipAssetCount $zips.Count -HasSubmodule $false
    } finally {Remove-CustomAppObserverTempDirectory $temp}
}
