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

# Repository archive endpoints are REST endpoints, not release-asset URLs.
# GitHub documents application/vnd.github+json for /zipball/{ref}; using the
# release-asset application/octet-stream media type can be rejected with 415.
function Invoke-CustomAppObserverBoundedArchiveDownloadV011 {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int64]$MaxBytes=134217728
    )
    if($MaxBytes -lt 1){throw 'Remote observer archive download limit is invalid.'}
    $initial=[Uri]$Uri
    if($initial.Scheme -cne 'https' -or $initial.Host -cne 'api.github.com'){throw 'Remote observer repository archive must start at api.github.com HTTPS.'}
    if(-not (Test-CustomAppObserverDownloadHost $initial)){throw 'Remote observer repository archive URI is not an allowed GitHub host.'}
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler=New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect=$true;$handler.MaxAutomaticRedirections=5
    $client=New-Object System.Net.Http.HttpClient($handler)
    $response=$null;$input=$null;$output=$null
    try{
        $client.Timeout=[TimeSpan]::FromSeconds(90)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd($CustomAppRemoteObserverUserAgent)
        $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('X-GitHub-Api-Version','2022-11-28')
        $response=$client.GetAsync($Uri,[System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if(-not $response.IsSuccessStatusCode){throw "Remote observer repository archive download failed HTTP $([int]$response.StatusCode)."}
        $final=$response.RequestMessage.RequestUri
        if(-not (Test-CustomAppObserverDownloadHost $final)){throw "Remote observer repository archive redirect escaped allowed GitHub hosts: $final"}
        if($null -ne $response.Content.Headers.ContentLength -and [int64]$response.Content.Headers.ContentLength -gt $MaxBytes){throw 'Remote observer repository archive compressed size exceeds the safety limit.'}
        $parent=Split-Path -Parent $Destination
        if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw 'Remote observer repository archive destination parent does not exist.'}
        $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536
        [int64]$total=0
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $total += $read
            if($total -gt $MaxBytes){throw 'Remote observer repository archive compressed download exceeded the safety limit while streaming.'}
            $output.Write($buffer,0,$read)
        }
        $output.Flush()
        return [pscustomobject]@{path=$Destination;bytes=$total;final_uri=[string]$final;media_type='application/vnd.github+json'}
    } finally {
        if($null -ne $output){$output.Dispose()}
        if($null -ne $input){$input.Dispose()}
        if($null -ne $response){$response.Dispose()}
        $client.Dispose();$handler.Dispose()
    }
}

function Get-CustomAppObserverRepoCommitObservation {
    param([Parameter(Mandatory=$true)][string]$Source,[AllowNull()][string]$CommitSha=$null)
    $repo=Get-CustomAppObserverRepositoryMetadata $Source;$base=[string]$repo.api_base
    $selector=$(if([string]::IsNullOrWhiteSpace($CommitSha)){[Uri]::EscapeDataString([string]$repo.default_branch)}else{$CommitSha.ToLowerInvariant()})
    if(-not [string]::IsNullOrWhiteSpace($CommitSha) -and -not (Test-CustomAppObserverCommitSha $selector)){throw 'Requested remote observer commit SHA is invalid.'}
    $commitObj=Invoke-CustomAppObserverApiJson ($base+'/commits/'+$selector)
    $commit=([string]$commitObj.sha).ToLowerInvariant()
    if(-not (Test-CustomAppObserverCommitSha $commit)){throw 'GitHub repository commit resolution returned an invalid SHA.'}
    if(-not [string]::IsNullOrWhiteSpace($CommitSha) -and $commit -cne $CommitSha.ToLowerInvariant()){throw 'GitHub repository commit resolution changed the requested immutable SHA.'}
    $hasSubmodule=Test-CustomAppObserverRepoHasSubmodule -Source ([string]$repo.source_identity) -CommitSha $commit
    $temp=New-CustomAppObserverTempDirectory
    try{
        $zip=Join-Path $temp 'repo.zip'
        [void](Invoke-CustomAppObserverBoundedArchiveDownloadV011 -Uri ($base+'/zipball/'+$commit) -Destination $zip -MaxBytes 134217728)
        $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode required
        return New-CustomAppObserverObservation -Repo $repo -CommitSha $commit -SurfaceKind 'repo-commit-root' -ZipEvidence $evidence -Release $null -Asset $null -ReleaseZipAssetCount 0 -HasSubmodule $hasSubmodule
    } finally {Remove-CustomAppObserverTempDirectory $temp}
}
