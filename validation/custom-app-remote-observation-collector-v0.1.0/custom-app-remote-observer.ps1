$CustomAppRemoteObserverSchema = 1
$CustomAppRemoteObserverUserAgent = 'Spotify-Control-Remote-Observer/0.1'

function Test-CustomAppObserverSha256 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppObserverCommitSha {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function ConvertTo-CustomAppObserverSourceIdentity {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return $null}
    $v=$Value.Trim()
    if($v -match '^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$'){
        return ($Matches[1]+'/'+$Matches[2]).ToLowerInvariant()
    }
    $patterns=@(
        '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$',
        '^git\+https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$',
        '^ssh://git@github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$',
        '^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?$'
    )
    foreach($pattern in $patterns){
        if($v -match $pattern){return ($Matches[1]+'/'+$Matches[2]).ToLowerInvariant()}
    }
    return $null
}

function Get-CustomAppObserverRepoApiBase {
    param([Parameter(Mandatory=$true)][string]$Source)
    $normalized=ConvertTo-CustomAppObserverSourceIdentity $Source
    if($null -eq $normalized -or $normalized -cne $Source.ToLowerInvariant()){throw 'Custom App remote observer source identity is not canonical owner/repo.'}
    $parts=$normalized.Split('/')
    return 'https://api.github.com/repos/'+[Uri]::EscapeDataString($parts[0])+'/'+[Uri]::EscapeDataString($parts[1])
}

function Get-CustomAppObserverApiHeaders {
    $headers=@{
        'User-Agent'=$CustomAppRemoteObserverUserAgent
        'Accept'='application/vnd.github+json'
        'X-GitHub-Api-Version'='2022-11-28'
    }
    return $headers
}

function Invoke-CustomAppObserverApiJson {
    param([Parameter(Mandatory=$true)][string]$Uri)
    $u=[Uri]$Uri
    if($u.Scheme -cne 'https' -or $u.Host -cne 'api.github.com'){throw 'Custom App remote observer API URI escaped api.github.com HTTPS.'}
    return Invoke-RestMethod -UseBasicParsing -Headers (Get-CustomAppObserverApiHeaders) -Uri $Uri -Method Get -TimeoutSec 30
}

function New-CustomAppObserverTempDirectory {
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $root=Join-Path $temp 'spotify-control-remote-observer'
    $dir=Join-Path $root ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}

function Remove-CustomAppObserverTempDirectory {
    param([AllowNull()][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $root=[IO.Path]::GetFullPath((Join-Path $temp 'spotify-control-remote-observer'))
    $full=[IO.Path]::GetFullPath($Path)
    $prefix=$root.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing to clean a path outside the dedicated remote-observer temp root.'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}

function Test-CustomAppObserverDownloadHost {
    param([Parameter(Mandatory=$true)][Uri]$Uri)
    if($Uri.Scheme -cne 'https'){return $false}
    return $Uri.Host.ToLowerInvariant() -in @(
        'api.github.com','github.com','codeload.github.com','objects.githubusercontent.com',
        'release-assets.githubusercontent.com','github-releases.githubusercontent.com','objects-origin.githubusercontent.com'
    )
}

function Invoke-CustomAppObserverBoundedDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int64]$MaxBytes=134217728
    )
    if($MaxBytes -lt 1){throw 'Remote observer download limit is invalid.'}
    $initial=[Uri]$Uri
    if(-not (Test-CustomAppObserverDownloadHost $initial)){throw "Remote observer download URI is not an allowed GitHub HTTPS host: $Uri"}
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler=New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect=$true;$handler.MaxAutomaticRedirections=5
    $client=New-Object System.Net.Http.HttpClient($handler)
    $response=$null;$input=$null;$output=$null
    try{
        $client.Timeout=[TimeSpan]::FromSeconds(90)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd($CustomAppRemoteObserverUserAgent)
        $client.DefaultRequestHeaders.Accept.ParseAdd('application/octet-stream')
        $response=$client.GetAsync($Uri,[System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if(-not $response.IsSuccessStatusCode){throw "Remote observer download failed HTTP $([int]$response.StatusCode)."}
        $final=$response.RequestMessage.RequestUri
        if(-not (Test-CustomAppObserverDownloadHost $final)){throw "Remote observer redirect escaped allowed GitHub hosts: $final"}
        if($null -ne $response.Content.Headers.ContentLength -and [int64]$response.Content.Headers.ContentLength -gt $MaxBytes){throw 'Remote observer compressed download exceeds the safety limit.'}
        $parent=Split-Path -Parent $Destination
        if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw 'Remote observer destination parent does not exist.'}
        $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536
        [int64]$total=0
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $total += $read
            if($total -gt $MaxBytes){throw 'Remote observer compressed download exceeded the safety limit while streaming.'}
            $output.Write($buffer,0,$read)
        }
        $output.Flush()
        return [pscustomobject]@{path=$Destination;bytes=$total;final_uri=[string]$final}
    } finally {
        if($null -ne $output){$output.Dispose()}
        if($null -ne $input){$input.Dispose()}
        if($null -ne $response){$response.Dispose()}
        $client.Dispose();$handler.Dispose()
    }
}

function Get-CustomAppObserverFileSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-CustomAppObserverWindowsReservedSegment {
    param([Parameter(Mandatory=$true)][string]$Segment)
    $base=($Segment.Split('.')[0]).ToUpperInvariant()
    if($base -in @('CON','PRN','AUX','NUL')){return $true}
    return ($base -match '^(COM|LPT)[1-9]$')
}

function Test-CustomAppObserverArchivePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return [pscustomobject]@{safe=$false;reason='path-empty'}}
    if($Path.IndexOf([char]0) -ge 0){return [pscustomobject]@{safe=$false;reason='path-nul'}}
    if($Path -match '[\x00-\x1f]'){return [pscustomobject]@{safe=$false;reason='path-control-character'}}
    if($Path.Contains('\')){return [pscustomobject]@{safe=$false;reason='path-backslash-denied'}}
    if($Path.StartsWith('/') -or $Path.StartsWith('//') -or $Path -match '^[A-Za-z]:'){return [pscustomobject]@{safe=$false;reason='path-absolute'}}
    $p=$Path.TrimEnd('/')
    if([string]::IsNullOrWhiteSpace($p)){return [pscustomobject]@{safe=$false;reason='path-empty'}}
    if($p.Contains('//')){return [pscustomobject]@{safe=$false;reason='path-empty-segment'}}
    foreach($segment in @($p.Split('/'))){
        if([string]::IsNullOrWhiteSpace($segment) -or $segment -ceq '.' -or $segment -ceq '..'){return [pscustomobject]@{safe=$false;reason='path-dot-or-empty-segment'}}
        if($segment.Contains(':')){return [pscustomobject]@{safe=$false;reason='path-ads-or-colon'}}
        if($segment.EndsWith(' ') -or $segment.EndsWith('.')){return [pscustomobject]@{safe=$false;reason='path-windows-trailing-space-or-dot'}}
        if(Test-CustomAppObserverWindowsReservedSegment $segment){return [pscustomobject]@{safe=$false;reason='path-windows-reserved-name'}}
    }
    if($p.Length -gt 1024){return [pscustomobject]@{safe=$false;reason='path-too-long'}}
    return [pscustomobject]@{safe=$true;reason='safe-relative-path';canonical=$p}
}

function Get-CustomAppObserverCommonWrapper {
    param([Parameter(Mandatory=$true)][string[]]$Paths)
    if($Paths.Count -eq 0){return $null}
    $first=$null
    foreach($raw in $Paths){
        $p=$raw.TrimEnd('/')
        $slash=$p.IndexOf('/')
        if($slash -lt 1){return $null}
        $segment=$p.Substring(0,$slash)
        if($null -eq $first){$first=$segment}
        elseif($segment -cne $first){return $null}
    }
    return $first
}

function Get-CustomAppObserverDirectoryName {
    param([Parameter(Mandatory=$true)][string]$Path)
    $i=$Path.LastIndexOf('/')
    if($i -lt 0){return '.'}
    if($i -eq 0){return '.'}
    return $Path.Substring(0,$i)
}

function Get-CustomAppObserverStringSha256 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Read-CustomAppObserverZipEntryText {
    param([Parameter(Mandatory=$true)]$Entry,[int64]$MaxBytes=1048576)
    if([int64]$Entry.Length -gt $MaxBytes){throw 'Remote observer JSON metadata entry exceeds the safety limit.'}
    $stream=$Entry.Open();$reader=$null
    try{
        $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096,$true)
        return $reader.ReadToEnd()
    } finally {
        if($null -ne $reader){$reader.Dispose()}
        $stream.Dispose()
    }
}

function Get-CustomAppObserverPackageRepositoryIdentity {
    param([AllowNull()]$PackageObject)
    if($null -eq $PackageObject -or -not $PackageObject.PSObject.Properties['repository']){return $null}
    $r=$PackageObject.repository
    $raw=$null
    if($r -is [string]){$raw=[string]$r}
    elseif($null -ne $r -and $r.PSObject.Properties['url']){$raw=[string]$r.url}
    if([string]::IsNullOrWhiteSpace($raw)){return $null}
    $normalized=ConvertTo-CustomAppObserverSourceIdentity $raw
    if($null -ne $normalized){return $normalized}
    return 'invalid-package-repository'
}

function Get-CustomAppObserverZipEvidence {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [ValidateSet('none','required','auto')][string]$WrapperMode='none',
        [int]$MaxEntries=20000,
        [int64]$MaxEntryBytes=67108864,
        [int64]$MaxExpandedBytes=268435456
    )
    if(-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)){throw 'Remote observer ZIP is missing.'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive=[IO.Compression.ZipFile]::OpenRead($ZipPath)
    try{
        if($archive.Entries.Count -lt 1){throw 'Remote observer ZIP is empty.'}
        if($archive.Entries.Count -gt $MaxEntries){throw 'Remote observer ZIP entry count exceeds the safety limit.'}
        $rawPaths=New-Object System.Collections.Generic.List[string]
        foreach($entry in @($archive.Entries)){
            $raw=[string]$entry.FullName
            $check=Test-CustomAppObserverArchivePath $raw
            if(-not [bool]$check.safe){throw "Remote observer ZIP unsafe path ($([string]$check.reason)): $raw"}
            $rawPaths.Add($raw)
            $mode=(([int64]$entry.ExternalAttributes -shr 16) -band 0xF000)
            if($mode -eq 0xA000){throw "Remote observer ZIP contains a symlink: $raw"}
            if($mode -in @(0x1000,0x2000,0x6000,0xC000)){throw "Remote observer ZIP contains a special device/FIFO/socket entry: $raw"}
        }

        $rawFilePaths=@($archive.Entries|Where-Object{-not ([string]$_.FullName).EndsWith('/')}|ForEach-Object{[string]$_.FullName})
        $wrapper=$null;$strip=$false
        if($WrapperMode -ceq 'required'){
            $wrapper=Get-CustomAppObserverCommonWrapper -Paths ([string[]]$rawFilePaths)
            if([string]::IsNullOrWhiteSpace($wrapper)){throw 'Remote observer GitHub zipball does not have one unambiguous wrapper directory.'}
            $strip=$true
        } elseif($WrapperMode -ceq 'auto'){
            $lowerRaw=@($rawFilePaths|ForEach-Object{$_.ToLowerInvariant()})
            $hasRootIndex=($lowerRaw -contains 'index.js');$hasRootManifest=($lowerRaw -contains 'manifest.json')
            if(-not ($hasRootIndex -and $hasRootManifest)){
                $candidate=Get-CustomAppObserverCommonWrapper -Paths ([string[]]$rawFilePaths)
                if(-not [string]::IsNullOrWhiteSpace($candidate)){
                    $prefix=$candidate.ToLowerInvariant()+'/'
                    $stripped=@($lowerRaw|ForEach-Object{if($_.StartsWith($prefix,[StringComparison]::Ordinal)){ $_.Substring($prefix.Length) }else{$_}})
                    if(($stripped -contains 'index.js') -and ($stripped -contains 'manifest.json')){$wrapper=$candidate;$strip=$true}
                }
            }
        }

        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
        $files=New-Object System.Collections.Generic.List[object]
        $rows=New-Object System.Collections.Generic.List[string]
        [int64]$expanded=0
        $manifestEntry=$null;$packageEntry=$null
        foreach($entry in @($archive.Entries)){
            $raw=[string]$entry.FullName
            if($raw.EndsWith('/')){continue}
            $logical=$raw
            if($strip){
                $prefix=$wrapper+'/'
                if(-not $logical.StartsWith($prefix,[StringComparison]::Ordinal)){throw "Remote observer wrapper containment drift: $logical"}
                $logical=$logical.Substring($prefix.Length)
            }
            $logicalCheck=Test-CustomAppObserverArchivePath $logical
            if(-not [bool]$logicalCheck.safe){throw "Remote observer logical ZIP path unsafe ($([string]$logicalCheck.reason)): $logical"}
            $logical=[string]$logicalCheck.canonical
            if(-not $seen.Add($logical)){throw "Remote observer ZIP contains a case-colliding logical path: $logical"}
            $len=[int64]$entry.Length
            if($len -lt 0 -or $len -gt $MaxEntryBytes){throw "Remote observer ZIP entry exceeds the per-file safety limit: $logical"}
            $expanded += $len
            if($expanded -gt $MaxExpandedBytes){throw 'Remote observer ZIP expanded-byte total exceeds the safety limit.'}
            $stream=$entry.Open();$sha=$null
            try{
                $sha=[Security.Cryptography.SHA256]::Create()
                $hash=([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant())
            } finally {
                if($null -ne $sha){$sha.Dispose()};$stream.Dispose()
            }
            $file=[pscustomobject]@{path=$logical;type='file';size=$len;sha256=$hash}
            $files.Add($file)
            $rows.Add(('f|'+$logical.ToLowerInvariant()+'|'+$len+'|'+$hash))
            if($logical -ceq 'manifest.json'){$manifestEntry=$entry}
            elseif($logical -ceq 'package.json'){$packageEntry=$entry}
        }
        if($files.Count -lt 1){throw 'Remote observer ZIP contains no files.'}

        $array=[string[]]$rows.ToArray();[Array]::Sort($array,[StringComparer]::Ordinal)
        $tree=Get-CustomAppObserverStringSha256 (($array -join "`n")+"`n")

        $indexDirs=@{};$manifestDirs=@{}
        foreach($file in @($files.ToArray())){
            $lower=([string]$file.path).ToLowerInvariant();$dir=Get-CustomAppObserverDirectoryName $lower
            if($lower.EndsWith('/index.js',[StringComparison]::Ordinal) -or $lower -ceq 'index.js'){$indexDirs[$dir]=$true}
            if($lower.EndsWith('/manifest.json',[StringComparison]::Ordinal) -or $lower -ceq 'manifest.json'){$manifestDirs[$dir]=$true}
        }
        $roots=New-Object System.Collections.Generic.List[string]
        foreach($key in @($indexDirs.Keys)){if($manifestDirs.ContainsKey($key)){$roots.Add([string]$key)}}
        $rootCount=$roots.Count;$layout=$(if($rootCount -eq 1){[string]$roots[0]}else{$null})
        $readyRoot=($rootCount -eq 1 -and $layout -ceq '.')

        $manifestValid=$false;$manifestName=$null
        if($readyRoot -and $null -ne $manifestEntry){
            try{
                $manifestText=Read-CustomAppObserverZipEntryText -Entry $manifestEntry -MaxBytes 1048576
                $manifest=$manifestText|ConvertFrom-Json -ErrorAction Stop
                $manifestName=([string]$manifest.name).Trim()
                $manifestValid=(-not [string]::IsNullOrWhiteSpace($manifestName) -and $manifestName.Length -le 256)
            }catch{$manifestValid=$false;$manifestName=$null}
        }

        $packageRepo=$null
        if($readyRoot -and $null -ne $packageEntry){
            try{
                $packageText=Read-CustomAppObserverZipEntryText -Entry $packageEntry -MaxBytes 1048576
                $package=$packageText|ConvertFrom-Json -ErrorAction Stop
                $packageRepo=Get-CustomAppObserverPackageRepositoryIdentity $package
            }catch{$packageRepo='invalid-package-repository'}
        }

        return [pscustomobject]@{
            files=$files.ToArray();tree_sha256=$tree;file_count=$files.Count;expanded_bytes=$expanded
            wrapper_stripped=$strip;wrapper_name=$wrapper;app_root_count=$rootCount;layout_root=$layout
            build_required=(-not $readyRoot);manifest_valid=$manifestValid;manifest_name=$manifestName;package_repository_identity=$packageRepo
            archive_unsafe=$false;has_symlink=$false;has_hardlink=$false;has_submodule=$false;has_device_entry=$false
        }
    } finally {$archive.Dispose()}
}

function Get-CustomAppObserverRepositoryMetadata {
    param([Parameter(Mandatory=$true)][string]$Source)
    $source=(ConvertTo-CustomAppObserverSourceIdentity $Source)
    if($null -eq $source){throw 'Remote observer source is not a canonical GitHub repository identity.'}
    $base=Get-CustomAppObserverRepoApiBase $source
    $repo=Invoke-CustomAppObserverApiJson $base
    if(([string]$repo.full_name).ToLowerInvariant() -cne $source){throw 'GitHub repository full_name does not match the proven source identity.'}
    if([bool]$repo.private){throw 'Remote observer does not enroll private repositories in v0.1.0.'}
    if([bool]$repo.archived -or [bool]$repo.disabled){throw 'Remote observer repository is archived or disabled.'}
    if([int64]$repo.id -le 0 -or [string]::IsNullOrWhiteSpace([string]$repo.default_branch)){throw 'GitHub repository metadata is incomplete.'}
    return [pscustomobject]@{source_identity=$source;github_repo_id=[int64]$repo.id;default_branch=[string]$repo.default_branch;api_base=$base}
}

function Resolve-CustomAppObserverGitObjectToCommit {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$ObjectSha,[Parameter(Mandatory=$true)][string]$ObjectType)
    $base=Get-CustomAppObserverRepoApiBase $Source
    $sha=$ObjectSha.ToLowerInvariant();$type=$ObjectType.ToLowerInvariant()
    for($depth=0;$depth -lt 8;$depth++){
        if($type -ceq 'commit'){
            if(-not (Test-CustomAppObserverCommitSha $sha)){throw 'Resolved GitHub commit SHA is invalid.'}
            return $sha
        }
        if($type -cne 'tag' -or -not (Test-CustomAppObserverCommitSha $sha)){throw "GitHub tag object resolved to unsupported type '$type'."}
        $tag=Invoke-CustomAppObserverApiJson ($base+'/git/tags/'+$sha)
        $sha=([string]$tag.object.sha).ToLowerInvariant();$type=([string]$tag.object.type).ToLowerInvariant()
    }
    throw 'GitHub annotated tag dereference depth exceeded the safety limit.'
}

function Resolve-CustomAppObserverReleaseTagCommit {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$TagName)
    if([string]::IsNullOrWhiteSpace($TagName)){throw 'Release tag name is empty.'}
    $base=Get-CustomAppObserverRepoApiBase $Source
    $encoded=[Uri]::EscapeDataString($TagName)
    $ref=Invoke-CustomAppObserverApiJson ($base+'/git/ref/tags/'+$encoded)
    return Resolve-CustomAppObserverGitObjectToCommit -Source $Source -ObjectSha ([string]$ref.object.sha) -ObjectType ([string]$ref.object.type)
}

function Test-CustomAppObserverRepoHasSubmodule {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$CommitSha)
    $base=Get-CustomAppObserverRepoApiBase $Source
    $commit=Invoke-CustomAppObserverApiJson ($base+'/git/commits/'+$CommitSha)
    $treeSha=[string]$commit.tree.sha
    if(-not (Test-CustomAppObserverCommitSha $treeSha)){throw 'GitHub commit tree SHA is invalid.'}
    $tree=Invoke-CustomAppObserverApiJson ($base+'/git/trees/'+$treeSha+'?recursive=1')
    if([bool]$tree.truncated){return $true}
    foreach($entry in @($tree.tree)){
        if([string]$entry.mode -ceq '160000' -or [string]$entry.type -ceq 'commit'){return $true}
    }
    return $false
}

function New-CustomAppObserverObservation {
    param($Repo,[string]$CommitSha,[string]$SurfaceKind,$ZipEvidence,$Release,$Asset,[int]$ReleaseZipAssetCount,[bool]$HasSubmodule)
    $o=[ordered]@{
        schema=$CustomAppRemoteObserverSchema;source_identity=[string]$Repo.source_identity;github_repo_id=[int64]$Repo.github_repo_id;transport='github-api-https';commit_sha=$CommitSha;surface_kind=$SurfaceKind
        archive_unsafe=[bool]$ZipEvidence.archive_unsafe;has_symlink=[bool]$ZipEvidence.has_symlink;has_hardlink=[bool]$ZipEvidence.has_hardlink;has_submodule=$HasSubmodule;has_device_entry=[bool]$ZipEvidence.has_device_entry
        build_required=[bool]$ZipEvidence.build_required;app_root_count=[int]$ZipEvidence.app_root_count;layout_root=$ZipEvidence.layout_root;manifest_valid=[bool]$ZipEvidence.manifest_valid;manifest_name=$ZipEvidence.manifest_name;package_repository_identity=$ZipEvidence.package_repository_identity
        files=@($ZipEvidence.files);tree_sha256=[string]$ZipEvidence.tree_sha256;wrapper_stripped=[bool]$ZipEvidence.wrapper_stripped;wrapper_name=$ZipEvidence.wrapper_name
        mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false
    }
    if($SurfaceKind -ceq 'release-asset'){
        $digest=([string]$Asset.digest).ToLowerInvariant()
        if($digest.StartsWith('sha256:')){$digest=$digest.Substring(7)}
        $o.release_id=[int64]$Release.id;$o.release_tag=[string]$Release.tag_name;$o.asset_id=[int64]$Asset.id;$o.asset_name=[string]$Asset.name;$o.asset_size=[int64]$Asset.size;$o.asset_digest_sha256=$digest;$o.release_zip_asset_count=$ReleaseZipAssetCount
    }
    return [pscustomobject]$o
}

function Get-CustomAppObserverReleaseObservation {
    param([Parameter(Mandatory=$true)][string]$Source,[Nullable[Int64]]$ReleaseId=$null)
    $repo=Get-CustomAppObserverRepositoryMetadata $Source;$base=[string]$repo.api_base
    $releaseUri=$(if($null -ne $ReleaseId -and $ReleaseId.Value -gt 0){$base+'/releases/'+$ReleaseId.Value}else{$base+'/releases/latest'})
    $release=Invoke-CustomAppObserverApiJson $releaseUri
    if([bool]$release.draft -or [bool]$release.prerelease){throw 'Remote observer release is draft or prerelease.'}
    if([int64]$release.id -le 0 -or [string]::IsNullOrWhiteSpace([string]$release.tag_name)){throw 'Remote observer release identity is incomplete.'}
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
        [void](Invoke-CustomAppObserverBoundedDownload -Uri ($base+'/zipball/'+$commit) -Destination $zip -MaxBytes 134217728)
        $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode required
        return New-CustomAppObserverObservation -Repo $repo -CommitSha $commit -SurfaceKind 'repo-commit-root' -ZipEvidence $evidence -Release $null -Asset $null -ReleaseZipAssetCount 0 -HasSubmodule $hasSubmodule
    } finally {Remove-CustomAppObserverTempDirectory $temp}
}

function Get-CustomAppRemoteObservationSet {
    param([Parameter(Mandatory=$true)][string]$Source,[AllowNull()]$Binding)
    $observations=New-Object System.Collections.Generic.List[object]
    $errors=New-Object System.Collections.Generic.List[object]
    $surface=$(if($null -ne $Binding){([string]$Binding.surface_kind).ToLowerInvariant()}else{''})
    if([string]::IsNullOrWhiteSpace($surface) -or $surface -ceq 'release-asset'){
        try{$observations.Add((Get-CustomAppObserverReleaseObservation -Source $Source))}catch{$errors.Add([pscustomobject]@{surface='release-asset';error=$_.Exception.Message})}
    }
    if([string]::IsNullOrWhiteSpace($surface) -or $surface -ceq 'repo-commit-root'){
        try{$observations.Add((Get-CustomAppObserverRepoCommitObservation -Source $Source))}catch{$errors.Add([pscustomobject]@{surface='repo-commit-root';error=$_.Exception.Message})}
    }
    if(-not [string]::IsNullOrWhiteSpace($surface) -and $surface -notin @('release-asset','repo-commit-root')){$errors.Add([pscustomobject]@{surface=$surface;error='unsupported-bound-surface'})}
    return [pscustomobject]@{schema=$CustomAppRemoteObserverSchema;source_identity=(ConvertTo-CustomAppObserverSourceIdentity $Source);observations=$observations.ToArray();errors=$errors.ToArray();mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}
