$CustomAppStageAcquisitionSchema = 1
$CustomAppStageWorkspaceManagedBy = 'custom-app-stage-acquisition-v1'

function Test-CustomAppStageSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppStageCommitShaV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Get-CustomAppStageStringSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppStageStrictDeniedAuthorityV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','auto_update_authorized','auto_install_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    if([bool]$Object.auto_update_authorized -or [bool]$Object.auto_install_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-auto-authority-true')}}
    if($Object.PSObject.Properties['mutation_authorized'] -and [bool]$Object.mutation_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-authorized-true')}}
    if($Object.PSObject.Properties['production_mutation_authorized'] -and [bool]$Object.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-production-authority-true')}}
    return [pscustomobject]@{ok=$true;reason=($Label+'-strict-denied-authority')}
}

function Get-CustomAppStageBindingFingerprintV010 {
    param([Parameter(Mandatory=$true)]$BindingRow)
    $binding=$BindingRow.binding
    if($null -eq $binding){return $null}
    $material=@(
        [string]$BindingRow.name,[string]$BindingRow.source_identity,[string]$BindingRow.last_success,
        [string]$BindingRow.last_remote_tree_sha256,[string]$BindingRow.last_remote_commit_sha,
        [string]$binding.source_identity,[string]$binding.github_repo_id,[string]$binding.surface_kind,
        [string]$binding.layout_root,[string]$binding.manifest_name,[string]$binding.last_verified_local_tree_sha256,
        [string]$binding.last_verified_remote_tree_sha256,[string]$binding.last_verified_commit_sha,
        [string]$binding.release_asset_selector,[string]$binding.asset_name,[string]$binding.last_observed_asset_id,
        [string]$binding.last_observed_asset_digest_sha256
    ) -join "`n"
    return Get-CustomAppStageStringSha256V010 -Text $material
}

function Test-CustomAppStageBindingRowV010 {
    param([AllowNull()]$BindingRow,[AllowNull()][string]$ExpectedName=$null)
    if($null -eq $BindingRow){return [pscustomobject]@{ok=$false;reason='binding-row-null'}}
    if([int]$BindingRow.schema -ne 1 -or [string]$BindingRow.managed_by -cne 'custom-app-remote-binding-observer-v1'){return [pscustomobject]@{ok=$false;reason='binding-row-owner-or-schema-mismatch'}}
    $rowAuthority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $BindingRow -Label 'binding-row'
    if(-not [bool]$rowAuthority.ok){return [pscustomobject]@{ok=$false;reason=[string]$rowAuthority.reason}}
    $name=([string]$BindingRow.name).Trim()
    if([string]::IsNullOrWhiteSpace($name)){return [pscustomobject]@{ok=$false;reason='binding-row-name-empty'}}
    if(-not [string]::IsNullOrWhiteSpace($ExpectedName) -and $name.ToLowerInvariant() -cne $ExpectedName.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='binding-row-name-mismatch'}}
    if(-not [bool]$BindingRow.active -or [bool]$BindingRow.user_removed -or [bool]$BindingRow.requires_reenrollment){return [pscustomobject]@{ok=$false;reason='binding-row-not-active-current'}}
    if(-not [bool]$BindingRow.update_observed -or [string]$BindingRow.last_status -cne 'remote-change-observed'){return [pscustomobject]@{ok=$false;reason='binding-row-no-current-remote-change'}}
    $lastSuccess=[DateTimeOffset]::MinValue
    if([string]::IsNullOrWhiteSpace([string]$BindingRow.last_success) -or -not [DateTimeOffset]::TryParse([string]$BindingRow.last_success,[ref]$lastSuccess)){return [pscustomobject]@{ok=$false;reason='binding-row-last-success-invalid'}}
    $source=([string]$BindingRow.source_identity).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppRemoteCanonicalSourceIdentity -Value $source)){return [pscustomobject]@{ok=$false;reason='binding-row-source-invalid'}}
    $tree=([string]$BindingRow.last_remote_tree_sha256).Trim().ToLowerInvariant();$commit=([string]$BindingRow.last_remote_commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppStageSha256V010 $tree) -or -not (Test-CustomAppStageCommitShaV010 $commit)){return [pscustomobject]@{ok=$false;reason='binding-row-remote-identity-invalid'}}

    $binding=$BindingRow.binding
    if($null -eq $binding -or [int]$binding.schema -ne 1 -or [string]$binding.managed_by -cne 'custom-app-remote-source-v1'){return [pscustomobject]@{ok=$false;reason='immutable-binding-owner-or-schema-mismatch'}}
    $bindingAuthority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $binding -Label 'immutable-binding'
    if(-not [bool]$bindingAuthority.ok){return [pscustomobject]@{ok=$false;reason=[string]$bindingAuthority.reason}}
    if(([string]$binding.source_identity).Trim().ToLowerInvariant() -cne $source){return [pscustomobject]@{ok=$false;reason='immutable-binding-source-mismatch'}}
    try{$repoId=[int64]$binding.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='immutable-binding-repo-id-invalid'}}
    if($repoId -le 0){return [pscustomobject]@{ok=$false;reason='immutable-binding-repo-id-invalid'}}
    $surface=([string]$binding.surface_kind).Trim().ToLowerInvariant()
    if($surface -notin @('repo-commit-root','release-asset') -or [string]$binding.layout_root -cne '.'){return [pscustomobject]@{ok=$false;reason='immutable-binding-surface-or-layout-invalid'}}
    $manifest=([string]$binding.manifest_name).Trim()
    if([string]::IsNullOrWhiteSpace($manifest) -or $manifest.Length -gt 256){return [pscustomobject]@{ok=$false;reason='immutable-binding-manifest-invalid'}}
    if(-not (Test-CustomAppStageSha256V010 ([string]$binding.last_verified_local_tree_sha256))){return [pscustomobject]@{ok=$false;reason='immutable-binding-local-tree-invalid'}}
    if(([string]$binding.last_verified_remote_tree_sha256).ToLowerInvariant() -cne $tree -or ([string]$binding.last_verified_commit_sha).ToLowerInvariant() -cne $commit){return [pscustomobject]@{ok=$false;reason='immutable-binding-remote-continuity-drift'}}
    if($surface -ceq 'release-asset'){
        if([string]$binding.release_asset_selector -cne 'unique-zip-asset'){return [pscustomobject]@{ok=$false;reason='release-selector-invalid'}}
        $assetName=([string]$binding.asset_name).Trim()
        if([string]::IsNullOrWhiteSpace($assetName) -or -not $assetName.EndsWith('.zip',[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='release-asset-name-invalid'}}
        try{$assetId=[int64]$binding.last_observed_asset_id}catch{return [pscustomobject]@{ok=$false;reason='release-asset-id-invalid'}}
        $assetDigest=([string]$binding.last_observed_asset_digest_sha256).Trim().ToLowerInvariant()
        if($assetId -le 0 -or -not (Test-CustomAppStageSha256V010 $assetDigest)){return [pscustomobject]@{ok=$false;reason='release-asset-id-or-digest-invalid'}}
    }
    $fingerprint=Get-CustomAppStageBindingFingerprintV010 -BindingRow $BindingRow
    if(-not (Test-CustomAppStageSha256V010 $fingerprint)){return [pscustomobject]@{ok=$false;reason='binding-fingerprint-invalid'}}
    return [pscustomobject]@{ok=$true;reason='binding-current-strict-deny';name=$name;source=$source;repo_id=$repoId;surface=$surface;manifest_name=$manifest;remote_tree_sha256=$tree;commit_sha=$commit;binding_fingerprint=$fingerprint;last_success=[string]$BindingRow.last_success}
}

function Get-CustomAppStageWorkspaceRootV010 {
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    return [IO.Path]::GetFullPath((Join-Path $temp 'spotify-control-stage-acquisition')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppStagePathWithinRootV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $target=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if($target.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $target.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-CustomAppStagePathV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='stage path',[bool]$RequireExistingRoot=$true)
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if($RequireExistingRoot -and -not (Test-Path -LiteralPath $rootFull -PathType Container)){throw "$Label root is missing."}
    if(Test-Path -LiteralPath $rootFull){$rootItem=Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop;if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label root is a reparse point."}}
    $target=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-CustomAppStagePathWithinRootV010 -Root $rootFull -Path $target)){throw "$Label escaped the dedicated stage root."}
    $probe=$target
    while(-not $probe.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)){
        if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse-point ancestor."}}
        $parent=[IO.Directory]::GetParent($probe);if($null -eq $parent){throw "$Label parent chain escaped root."};$probe=$parent.FullName
        if(-not ($probe.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase) -or $probe.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw "$Label parent chain escaped root."}
    }
    return $target
}

function New-CustomAppStageWorkspaceV010 {
    $root=Get-CustomAppStageWorkspaceRootV010
    if(-not (Test-Path -LiteralPath $root)){[IO.Directory]::CreateDirectory($root)|Out-Null}
    $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Dedicated stage acquisition root is a reparse point.'}
    $workspace=Join-Path $root ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($workspace)|Out-Null
    return [IO.Path]::GetFullPath($workspace)
}

function Remove-CustomAppStageWorkspaceV010 {
    param([AllowNull()][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return}
    $root=Get-CustomAppStageWorkspaceRootV010
    $target=Assert-CustomAppStagePathV010 -Root $root -Path $Path -Label 'workspace cleanup'
    if(Test-Path -LiteralPath $target){[IO.Directory]::Delete($target,$true)}
}

function Test-CustomAppStageLogicalVcsPathV010 {
    param([Parameter(Mandatory=$true)][string]$LogicalPath)
    return ($LogicalPath.Equals('.git',[StringComparison]::OrdinalIgnoreCase) -or $LogicalPath.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase))
}

function Expand-CustomAppStageArchiveV010 {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$ValidationRoot,
        [ValidateSet('none','required','auto')][string]$WrapperMode,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ExpectedTreeSha256,
        [Parameter(Mandatory=$true)][string]$ExpectedManifestName
    )
    $root=[IO.Path]::GetFullPath($ValidationRoot)
    $zip=Assert-CustomAppStagePathV010 -Root $root -Path $ZipPath -Label 'stage archive'
    $dest=Assert-CustomAppStagePathV010 -Root $root -Path $Destination -Label 'stage destination'
    if(-not (Test-Path -LiteralPath $zip -PathType Leaf)){throw 'Stage archive is missing.'}
    if(Test-Path -LiteralPath $dest){throw 'Stage destination already exists.'}
    if(-not (Test-CustomAppStageSha256V010 $ExpectedTreeSha256)){throw 'Expected stage tree SHA-256 is invalid.'}
    if([string]::IsNullOrWhiteSpace($ExpectedManifestName)){throw 'Expected stage manifest name is empty.'}
    $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode $WrapperMode
    if([bool]$evidence.archive_unsafe -or [bool]$evidence.has_symlink -or [bool]$evidence.has_device_entry -or [bool]$evidence.build_required -or [int]$evidence.app_root_count -ne 1 -or [string]$evidence.layout_root -cne '.' -or -not [bool]$evidence.manifest_valid){throw 'Stage archive is not a verified ready runtime root.'}
    if([string]$evidence.tree_sha256 -cne $ExpectedTreeSha256.ToLowerInvariant()){throw 'Stage archive tree does not match the immutable binding.'}
    if([string]$evidence.manifest_name -cne $ExpectedManifestName){throw 'Stage archive manifest identity does not match the immutable binding.'}
    foreach($f in @($evidence.files)){if(Test-CustomAppStageLogicalVcsPathV010 -LogicalPath ([string]$f.path)){throw 'Stage archive contains forbidden VCS metadata.'}}

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    $created=$false
    try{
        $expected=@{}
        foreach($f in @($evidence.files)){$expected[([string]$f.path).ToLowerInvariant()]=$f}
        $rawFilePaths=@($archive.Entries|Where-Object{-not ([string]$_.FullName).EndsWith('/')}|ForEach-Object{[string]$_.FullName})
        $wrapper=$null;$strip=$false
        if($WrapperMode -ceq 'required'){$wrapper=Get-CustomAppObserverCommonWrapper -Paths ([string[]]$rawFilePaths);if([string]::IsNullOrWhiteSpace($wrapper)){throw 'Stage archive wrapper is ambiguous.'};$strip=$true}
        elseif($WrapperMode -ceq 'auto'){$wrapper=[string]$evidence.wrapper_name;$strip=[bool]$evidence.wrapper_stripped}
        [IO.Directory]::CreateDirectory($dest)|Out-Null;$created=$true
        $destPrefix=$dest.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
        [int64]$expanded=0;$fileCount=0
        foreach($entry in @($archive.Entries)){
            $raw=[string]$entry.FullName
            $rawCheck=Test-CustomAppObserverArchivePath -Path $raw
            if(-not [bool]$rawCheck.safe){throw "Unsafe stage archive path: $raw"}
            $mode=(([int64]$entry.ExternalAttributes -shr 16) -band 0xF000)
            if($mode -eq 0xA000 -or $mode -in @(0x1000,0x2000,0x6000,0xC000)){throw "Stage archive contains a non-regular unsafe entry: $raw"}
            if($raw.EndsWith('/')){continue}
            $logical=$raw
            if($strip){$prefix=$wrapper+'/';if(-not $logical.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Stage wrapper containment drift.'};$logical=$logical.Substring($prefix.Length)}
            $check=Test-CustomAppObserverArchivePath -Path $logical
            if(-not [bool]$check.safe){throw "Unsafe logical stage path: $logical"};$logical=[string]$check.canonical
            if(Test-CustomAppStageLogicalVcsPathV010 -LogicalPath $logical){throw 'Stage archive contains forbidden VCS metadata.'}
            if(-not $seen.Add($logical)){throw "Stage archive contains a case-colliding logical path: $logical"}
            $key=$logical.ToLowerInvariant();if(-not $expected.ContainsKey($key)){throw "Stage archive extraction set drift: $logical"}
            $exp=$expected[$key];$len=[int64]$entry.Length
            if($len -ne [int64]$exp.size -or $len -lt 0 -or $len -gt 67108864){throw "Stage entry size drift or limit violation: $logical"}
            $expanded += $len;if($expanded -gt 268435456){throw 'Stage expanded-byte limit exceeded.'};$fileCount++;if($fileCount -gt 20000){throw 'Stage file-count limit exceeded.'}
            $relative=$logical.Replace('/',[IO.Path]::DirectorySeparatorChar);$target=[IO.Path]::GetFullPath((Join-Path $dest $relative))
            if(-not $target.StartsWith($destPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Stage extraction target escaped destination.'}
            $parent=[IO.Path]::GetDirectoryName($target);if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
            $input=$null;$output=$null
            try{
                $input=$entry.Open();$output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $buffer=New-Object byte[] 65536;[int64]$written=0
                while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){$written+=$read;if($written -gt $len){throw "Stage entry expanded beyond declared length: $logical"};$output.Write($buffer,0,$read)}
                $output.Flush();if($written -ne $len){throw "Stage entry length changed while extracting: $logical"}
            }finally{if($null -ne $output){$output.Dispose()};if($null -ne $input){$input.Dispose()}}
            $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant();if($hash -cne [string]$exp.sha256){throw "Stage entry SHA-256 mismatch after extraction: $logical"}
        }
        if($fileCount -ne @($evidence.files).Count){throw 'Stage extraction file count does not match verified archive evidence.'}
        $baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $dest
        if(-not [bool]$baseline.safe -or -not [bool]$baseline.installable -or [string]$baseline.tree_sha256 -cne $ExpectedTreeSha256.ToLowerInvariant() -or [string]$baseline.manifest_name -cne $ExpectedManifestName){throw 'Extracted stage baseline does not exactly match the immutable remote runtime.'}
        return [pscustomobject]@{schema=$CustomAppStageAcquisitionSchema;stage_path=$dest;evidence=$evidence;baseline=$baseline;tree_sha256=[string]$baseline.tree_sha256;manifest_name=[string]$baseline.manifest_name;file_count=[int]$baseline.file_count;total_bytes=[int64]$baseline.total_bytes;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false}
    }catch{
        if($created -and (Test-Path -LiteralPath $dest)){[IO.Directory]::Delete($dest,$true)}
        throw
    }finally{$archive.Dispose()}
}

function Test-CustomAppStageEvidenceAgainstBindingV010 {
    param([Parameter(Mandatory=$true)]$Evidence,[Parameter(Mandatory=$true)]$BindingCheck)
    if([bool]$Evidence.archive_unsafe -or [bool]$Evidence.has_symlink -or [bool]$Evidence.has_hardlink -or [bool]$Evidence.has_device_entry -or [bool]$Evidence.build_required){return [pscustomobject]@{ok=$false;reason='remote-archive-or-build-unsafe'}}
    if([int]$Evidence.app_root_count -ne 1 -or [string]$Evidence.layout_root -cne '.' -or -not [bool]$Evidence.manifest_valid){return [pscustomobject]@{ok=$false;reason='remote-layout-or-manifest-invalid'}}
    if([string]$Evidence.manifest_name -cne [string]$BindingCheck.manifest_name){return [pscustomobject]@{ok=$false;reason='remote-manifest-binding-mismatch'}}
    if([string]$Evidence.tree_sha256 -cne [string]$BindingCheck.remote_tree_sha256){return [pscustomobject]@{ok=$false;reason='remote-tree-binding-mismatch'}}
    $pkg=([string]$Evidence.package_repository_identity).Trim().ToLowerInvariant()
    if(-not [string]::IsNullOrWhiteSpace($pkg) -and $pkg -cne [string]$BindingCheck.source){return [pscustomobject]@{ok=$false;reason='remote-package-repository-conflict'}}
    foreach($f in @($Evidence.files)){if(Test-CustomAppStageLogicalVcsPathV010 -LogicalPath ([string]$f.path)){return [pscustomobject]@{ok=$false;reason='remote-vcs-metadata-forbidden'}}}
    return [pscustomobject]@{ok=$true;reason='remote-evidence-matches-binding'}
}

function Invoke-CustomAppStageAcquisitionV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$BindingRow)
    $check=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$check.ok){throw ('Stage acquisition binding denied: '+[string]$check.reason)}
    $workspace=New-CustomAppStageWorkspaceV010;$success=$false
    try{
        $binding=$BindingRow.binding;$repo=Get-CustomAppObserverRepositoryMetadata -Source ([string]$check.source)
        if([int64]$repo.github_repo_id -ne [int64]$check.repo_id){throw 'Stage acquisition GitHub numeric repository identity drift.'}
        $commitObj=Invoke-CustomAppObserverApiJson ([string]$repo.api_base+'/commits/'+[string]$check.commit_sha)
        $resolved=([string]$commitObj.sha).Trim().ToLowerInvariant();if($resolved -cne [string]$check.commit_sha){throw 'Stage acquisition immutable commit resolution drift.'}
        $zip=Join-Path $workspace 'remote.zip';$wrapperMode='none';$archiveDigest=$null
        if([string]$check.surface -ceq 'repo-commit-root'){
            if(Test-CustomAppObserverRepoHasSubmodule -Source ([string]$check.source) -CommitSha ([string]$check.commit_sha)){throw 'Stage acquisition repo commit contains a submodule or truncated tree.'}
            [void](Invoke-CustomAppObserverBoundedArchiveDownloadV011 -Uri ([string]$repo.api_base+'/zipball/'+[string]$check.commit_sha) -Destination $zip -MaxBytes 134217728)
            $wrapperMode='required';$archiveDigest=Get-CustomAppObserverFileSha256 -Path $zip
        }else{
            $assetId=[int64]$binding.last_observed_asset_id
            $asset=Invoke-CustomAppObserverApiJson ([string]$repo.api_base+'/releases/assets/'+$assetId)
            if([int64]$asset.id -ne $assetId -or [string]$asset.name -cne [string]$binding.asset_name){throw 'Stage acquisition release asset identity drift.'}
            $digest=([string]$asset.digest).Trim().ToLowerInvariant();if($digest.StartsWith('sha256:')){$digest=$digest.Substring(7)}
            if($digest -cne ([string]$binding.last_observed_asset_digest_sha256).ToLowerInvariant() -or -not (Test-CustomAppStageSha256V010 $digest)){throw 'Stage acquisition release asset digest drift.'}
            if([int64]$asset.size -le 0 -or [int64]$asset.size -gt 134217728 -or [string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)){throw 'Stage acquisition release asset metadata is unsafe.'}
            $download=Invoke-CustomAppObserverBoundedDownload -Uri ([string]$asset.browser_download_url) -Destination $zip -MaxBytes 134217728
            if([int64]$download.bytes -ne [int64]$asset.size){throw 'Stage acquisition release asset size drift.'}
            $archiveDigest=Get-CustomAppObserverFileSha256 -Path $zip;if($archiveDigest -cne $digest){throw 'Stage acquisition release asset bytes do not match pinned GitHub SHA-256.'}
            $wrapperMode='auto'
        }
        $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode $wrapperMode
        $evidenceCheck=Test-CustomAppStageEvidenceAgainstBindingV010 -Evidence $evidence -BindingCheck $check
        if(-not [bool]$evidenceCheck.ok){throw ('Stage acquisition remote evidence denied: '+[string]$evidenceCheck.reason)}
        $stagePath=Join-Path $workspace 'stage'
        $stage=Expand-CustomAppStageArchiveV010 -ZipPath $zip -Destination $stagePath -ValidationRoot $workspace -WrapperMode $wrapperMode -Name $Name -ExpectedTreeSha256 ([string]$check.remote_tree_sha256) -ExpectedManifestName ([string]$check.manifest_name)
        $result=[pscustomobject]@{
            schema=$CustomAppStageAcquisitionSchema;managed_by=$CustomAppStageWorkspaceManagedBy;status='staged-verified';name=$Name;source_identity=[string]$check.source
            github_repo_id=[int64]$check.repo_id;surface_kind=[string]$check.surface;commit_sha=[string]$check.commit_sha;remote_tree_sha256=[string]$check.remote_tree_sha256
            binding_fingerprint=[string]$check.binding_fingerprint;binding_last_success=[string]$check.last_success;workspace_path=$workspace;stage_path=[string]$stage.stage_path
            archive_sha256=$archiveDigest;stage_baseline=$stage.baseline;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
        }
        $success=$true;return $result
    }finally{if(-not $success){Remove-CustomAppStageWorkspaceV010 -Path $workspace}}
}

function Test-CustomAppStageAcquisitionMutationAuthorityV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return $false}
    $strict=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $Result -Label 'stage-result'
    return (-not [bool]$strict.ok -or ([bool]$Result.PSObject.Properties['production_mutation_authorized'] -and [bool]$Result.production_mutation_authorized))
}
