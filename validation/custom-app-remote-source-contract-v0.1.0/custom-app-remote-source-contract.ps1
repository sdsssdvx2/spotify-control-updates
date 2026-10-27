$CustomAppRemoteSourceContractSchema = 1

function Test-CustomAppRemoteSha256 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppRemoteCommitSha {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Test-CustomAppRemoteCanonicalSourceIdentity {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return $false}
    return ($Value -cmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -and $Value -notmatch '(^|/)(\.|\.\.)(/|$)')
}

function Get-CustomAppRemoteStringSha256 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppRemoteWindowsReservedSegment {
    param([Parameter(Mandatory=$true)][string]$Segment)
    $base=($Segment.Split('.')[0]).ToUpperInvariant()
    if($base -in @('CON','PRN','AUX','NUL')){return $true}
    if($base -match '^(COM|LPT)[1-9]$'){return $true}
    return $false
}

function Test-CustomAppRemoteRelativePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-empty'}}
    if($Path.IndexOf([char]0) -ge 0){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-nul'}}
    if($Path -match '[\x00-\x1f]'){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-control-character'}}
    $p=$Path.Replace('\\','/')
    if($p.StartsWith('/') -or $p.StartsWith('//') -or $p -match '^[A-Za-z]:'){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-absolute'}}
    if($p.Contains('//')){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-empty-segment'}}
    $segments=@($p.Split('/'))
    if($segments.Count -eq 0){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-empty'}}
    foreach($segment in $segments){
        if([string]::IsNullOrWhiteSpace($segment) -or $segment -ceq '.' -or $segment -ceq '..'){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-dot-or-empty-segment'}}
        if($segment.Contains(':')){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-ads-or-colon'}}
        if($segment.EndsWith(' ') -or $segment.EndsWith('.')){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-windows-trailing-space-or-dot'}}
        if(Test-CustomAppRemoteWindowsReservedSegment -Segment $segment){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-windows-reserved-name'}}
    }
    if($p.Length -gt 1024){return [pscustomobject]@{safe=$false;canonical=$null;reason='path-too-long'}}
    return [pscustomobject]@{safe=$true;canonical=$p;reason='safe-relative-path'}
}

function Test-CustomAppRemoteRuntimeFileSet {
    param([Parameter(Mandatory=$true)]$Observation)
    $entries=@($Observation.files)
    if($entries.Count -lt 2){return [pscustomobject]@{safe=$false;installable=$false;reason='file-set-too-small';tree_sha256=$null;file_count=0;total_bytes=0}}
    if($entries.Count -gt 20000){return [pscustomobject]@{safe=$false;installable=$false;reason='file-count-limit-exceeded';tree_sha256=$null;file_count=$entries.Count;total_bytes=0}}
    $seen=@{};$rows=New-Object System.Collections.Generic.List[string];$total=[int64]0;$fileCount=0;$hasIndex=$false;$hasManifest=$false
    foreach($entry in $entries){
        if($null -eq $entry){return [pscustomobject]@{safe=$false;installable=$false;reason='null-entry';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        $pathCheck=Test-CustomAppRemoteRelativePath -Path ([string]$entry.path)
        if(-not [bool]$pathCheck.safe){return [pscustomobject]@{safe=$false;installable=$false;reason=[string]$pathCheck.reason;tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        $path=[string]$pathCheck.canonical;$key=$path.ToLowerInvariant()
        if($seen.ContainsKey($key)){return [pscustomobject]@{safe=$false;installable=$false;reason='case-insensitive-duplicate-path';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        $seen[$key]=$true
        $type=([string]$entry.type).Trim().ToLowerInvariant()
        if($type -notin @('file','dir')){return [pscustomobject]@{safe=$false;installable=$false;reason='non-regular-entry-type';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        if($type -eq 'dir'){$rows.Add(('d|'+$key));continue}
        $size=[int64]$entry.size
        if($size -lt 0 -or $size -gt 67108864){return [pscustomobject]@{safe=$false;installable=$false;reason='individual-file-size-limit';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        $hash=([string]$entry.sha256).Trim().ToLowerInvariant()
        if(-not (Test-CustomAppRemoteSha256 $hash)){return [pscustomobject]@{safe=$false;installable=$false;reason='file-sha256-invalid';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        $total+=$size;$fileCount++
        if($total -gt 268435456){return [pscustomobject]@{safe=$false;installable=$false;reason='expanded-size-limit-exceeded';tree_sha256=$null;file_count=$fileCount;total_bytes=$total}}
        if($key -ceq 'index.js'){$hasIndex=$true}
        if($key -ceq 'manifest.json'){$hasManifest=$true}
        $rows.Add(('f|'+$key+'|'+$size+'|'+$hash))
    }
    $array=[string[]]$rows.ToArray();[Array]::Sort($array,[StringComparer]::Ordinal)
    $tree=Get-CustomAppRemoteStringSha256 (($array -join "`n")+"`n")
    if($Observation.PSObject.Properties['tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Observation.tree_sha256) -and [string]$Observation.tree_sha256 -cne $tree){
        return [pscustomobject]@{safe=$false;installable=$false;reason='declared-tree-fingerprint-mismatch';tree_sha256=$tree;file_count=$fileCount;total_bytes=$total}
    }
    if(-not $hasIndex -or -not $hasManifest){return [pscustomobject]@{safe=$true;installable=$false;reason=$(if(-not $hasIndex){'root-index-js-missing'}else{'root-manifest-json-missing'});tree_sha256=$tree;file_count=$fileCount;total_bytes=$total}}
    return [pscustomobject]@{safe=$true;installable=$true;reason='safe-ready-runtime-root';tree_sha256=$tree;file_count=$fileCount;total_bytes=$total}
}

function New-CustomAppRemoteSourceDecision {
    param(
        [bool]$Applicable,[bool]$Conclusive,[string]$Status,[string]$Reason,
        [bool]$SourceIdentityVerified,[bool]$RepoIdVerified,[bool]$SurfaceVerified,[bool]$LocalContinuityVerified,
        [bool]$UpdateObserved,[bool]$EnrollmentCandidate,[bool]$RequiresReenrollment,
        $BindingCandidate,[AllowNull()][string]$RemoteTreeSha256
    )
    return [pscustomobject]@{
        schema=$CustomAppRemoteSourceContractSchema;applicable=$Applicable;conclusive=$Conclusive;status=$Status;reason=$Reason
        source_identity_verified=$SourceIdentityVerified;repo_id_verified=$RepoIdVerified;surface_verified=$SurfaceVerified;local_continuity_verified=$LocalContinuityVerified
        update_observed=$UpdateObserved;enrollment_candidate=$EnrollmentCandidate;requires_reenrollment=$RequiresReenrollment
        binding_candidate=$BindingCandidate;remote_tree_sha256=$RemoteTreeSha256
        mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false
    }
}

function Test-CustomAppRemoteProvenanceRow {
    param([Parameter(Mandatory=$true)]$Row)
    if($null -eq $Row){return [pscustomobject]@{ok=$false;reason='provenance-null'}}
    if([string]$Row.managed_by -cne 'custom-app-provenance-v1'){return [pscustomobject]@{ok=$false;reason='provenance-owner-mismatch'}}
    $source=[string]$Row.source_identity
    if(-not (Test-CustomAppRemoteCanonicalSourceIdentity $source)){return [pscustomobject]@{ok=$false;reason='provenance-source-unavailable'}}
    if([bool]$Row.source_changed -or [bool]$Row.requires_reenrollment){return [pscustomobject]@{ok=$false;reason='provenance-reenrollment-required'}}
    if([string]$Row.last_proven_source -cne $source){return [pscustomobject]@{ok=$false;reason='provenance-history-mismatch'}}
    if([string]$Row.mutation_mode -cne 'deny' -or [bool]$Row.auto_update_authorized -or [bool]$Row.auto_install_authorized){return [pscustomobject]@{ok=$false;reason='provenance-authority-drift'}}
    return [pscustomobject]@{ok=$true;reason='provenance-active-and-denied';source=$source}
}

function Test-CustomAppRemoteSurfaceObservation {
    param([Parameter(Mandatory=$true)]$Observation,[Parameter(Mandatory=$true)][string]$ExpectedSource)
    if($null -eq $Observation){return [pscustomobject]@{ok=$false;reason='remote-observation-null';tree_sha256=$null}}
    $source=([string]$Observation.source_identity).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppRemoteCanonicalSourceIdentity $source) -or $source -cne $ExpectedSource){return [pscustomobject]@{ok=$false;reason='remote-source-mismatch';tree_sha256=$null}}
    if([string]$Observation.transport -cne 'github-api-https'){return [pscustomobject]@{ok=$false;reason='remote-transport-not-pinned-https';tree_sha256=$null}}
    try{$repoId=[int64]$Observation.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='remote-repo-id-invalid';tree_sha256=$null}}
    if($repoId -le 0){return [pscustomobject]@{ok=$false;reason='remote-repo-id-invalid';tree_sha256=$null}}
    $commit=([string]$Observation.commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppRemoteCommitSha $commit)){return [pscustomobject]@{ok=$false;reason='remote-commit-not-immutable-sha';tree_sha256=$null}}
    if([bool]$Observation.archive_unsafe -or [bool]$Observation.has_symlink -or [bool]$Observation.has_hardlink -or [bool]$Observation.has_submodule -or [bool]$Observation.has_device_entry){return [pscustomobject]@{ok=$false;reason='remote-archive-unsafe-entry';tree_sha256=$null}}
    if([bool]$Observation.build_required){return [pscustomobject]@{ok=$false;reason='remote-surface-requires-build';tree_sha256=$null}}
    if([int]$Observation.app_root_count -ne 1 -or [string]$Observation.layout_root -cne '.'){return [pscustomobject]@{ok=$false;reason='remote-app-root-not-unique-root';tree_sha256=$null}}
    if(-not [bool]$Observation.manifest_valid -or [string]::IsNullOrWhiteSpace([string]$Observation.manifest_name) -or ([string]$Observation.manifest_name).Length -gt 256){return [pscustomobject]@{ok=$false;reason='remote-manifest-invalid';tree_sha256=$null}}
    $pkg=([string]$Observation.package_repository_identity).Trim().ToLowerInvariant()
    if(-not [string]::IsNullOrWhiteSpace($pkg) -and (-not (Test-CustomAppRemoteCanonicalSourceIdentity $pkg) -or $pkg -cne $ExpectedSource)){return [pscustomobject]@{ok=$false;reason='remote-package-repository-conflict';tree_sha256=$null}}
    $surface=([string]$Observation.surface_kind).Trim().ToLowerInvariant()
    if($surface -notin @('repo-commit-root','release-asset')){return [pscustomobject]@{ok=$false;reason='remote-surface-kind-unsupported';tree_sha256=$null}}
    if($surface -eq 'release-asset'){
        try{$releaseId=[int64]$Observation.release_id;$assetId=[int64]$Observation.asset_id;$assetSize=[int64]$Observation.asset_size}catch{return [pscustomobject]@{ok=$false;reason='release-asset-identity-invalid';tree_sha256=$null}}
        $assetName=[string]$Observation.asset_name;$assetDigest=([string]$Observation.asset_digest_sha256).Trim().ToLowerInvariant()
        if($releaseId -le 0 -or $assetId -le 0 -or $assetSize -le 0 -or [string]::IsNullOrWhiteSpace($assetName) -or -not $assetName.EndsWith('.zip',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-CustomAppRemoteSha256 $assetDigest)){
            return [pscustomobject]@{ok=$false;reason='release-asset-identity-invalid';tree_sha256=$null}
        }
    }
    $files=Test-CustomAppRemoteRuntimeFileSet -Observation $Observation
    if(-not [bool]$files.safe){return [pscustomobject]@{ok=$false;reason=[string]$files.reason;tree_sha256=[string]$files.tree_sha256}}
    if(-not [bool]$files.installable){return [pscustomobject]@{ok=$false;reason=[string]$files.reason;tree_sha256=[string]$files.tree_sha256}}
    return [pscustomobject]@{ok=$true;reason='remote-installable-surface-verified';tree_sha256=[string]$files.tree_sha256;source=$source;repo_id=$repoId;commit_sha=$commit;surface_kind=$surface;manifest_name=[string]$Observation.manifest_name;asset_name=$(if($surface -eq 'release-asset'){[string]$Observation.asset_name}else{$null})}
}

function Resolve-CustomAppRemoteSourceContract {
    param(
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$RemoteObservation,
        [AllowNull()]$Binding,
        [Parameter(Mandatory=$true)][string]$CurrentLocalTreeSha256,
        [Parameter(Mandatory=$true)][string]$CurrentLocalManifestName
    )
    $prov=Test-CustomAppRemoteProvenanceRow -Row $ProvenanceRow
    if(-not [bool]$prov.ok){return New-CustomAppRemoteSourceDecision $true $false 'provenance-denied' ([string]$prov.reason) $false $false $false $false $false $false $true $null $null}
    $source=[string]$prov.source
    if(-not (Test-CustomAppRemoteSha256 $CurrentLocalTreeSha256) -or [string]::IsNullOrWhiteSpace($CurrentLocalManifestName)){
        return New-CustomAppRemoteSourceDecision $true $false 'local-baseline-invalid' 'local-tree-or-manifest-invalid' $true $false $false $false $false $false $true $null $null
    }
    $remote=Test-CustomAppRemoteSurfaceObservation -Observation $RemoteObservation -ExpectedSource $source
    if(-not [bool]$remote.ok){return New-CustomAppRemoteSourceDecision $true $false 'remote-denied' ([string]$remote.reason) $true $false $false $false $false $false $true $null ([string]$remote.tree_sha256)}
    if([string]$remote.manifest_name -cne $CurrentLocalManifestName){
        return New-CustomAppRemoteSourceDecision $true $false 'manifest-identity-drift' 'remote-manifest-name-does-not-match-local' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }

    if($null -eq $Binding){
        if([string]$remote.tree_sha256 -cne $CurrentLocalTreeSha256){
            return New-CustomAppRemoteSourceDecision $true $false 'initial-content-match-required' 'remote-surface-does-not-exactly-match-current-local-tree' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
        }
        $candidate=[pscustomobject]@{
            schema=$CustomAppRemoteSourceContractSchema;managed_by='custom-app-remote-source-v1';source_identity=$source;github_repo_id=[int64]$remote.repo_id
            surface_kind=[string]$remote.surface_kind;asset_name=$remote.asset_name;layout_root='.';manifest_name=[string]$remote.manifest_name
            last_verified_local_tree_sha256=$CurrentLocalTreeSha256;last_verified_remote_tree_sha256=[string]$remote.tree_sha256
            last_verified_commit_sha=[string]$remote.commit_sha;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
        }
        return New-CustomAppRemoteSourceDecision $true $true 'binding-enrollment-candidate' 'exact-local-content-match-and-repo-id-observed' $true $false $true $true $false $true $false $candidate ([string]$remote.tree_sha256)
    }

    if([string]$Binding.managed_by -cne 'custom-app-remote-source-v1' -or [int]$Binding.schema -ne $CustomAppRemoteSourceContractSchema){
        return New-CustomAppRemoteSourceDecision $true $false 'binding-denied' 'binding-owner-or-schema-mismatch' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if([string]$Binding.mutation_mode -cne 'deny' -or [bool]$Binding.auto_update_authorized -or [bool]$Binding.auto_install_authorized){
        return New-CustomAppRemoteSourceDecision $true $false 'binding-denied' 'binding-authority-drift' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if(([string]$Binding.source_identity).ToLowerInvariant() -cne $source){
        return New-CustomAppRemoteSourceDecision $true $false 'binding-denied' 'binding-source-mismatch' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if([int64]$Binding.github_repo_id -ne [int64]$remote.repo_id){
        return New-CustomAppRemoteSourceDecision $true $false 'repo-id-drift' 'github-numeric-repository-id-changed' $true $false $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if([string]$Binding.surface_kind -cne [string]$remote.surface_kind -or [string]$Binding.layout_root -cne '.'){
        return New-CustomAppRemoteSourceDecision $true $false 'surface-contract-drift' 'bound-remote-surface-or-layout-changed' $true $true $false $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if([string]$Binding.manifest_name -cne [string]$remote.manifest_name -or [string]$Binding.manifest_name -cne $CurrentLocalManifestName){
        return New-CustomAppRemoteSourceDecision $true $false 'manifest-identity-drift' 'bound-manifest-name-changed' $true $true $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if([string]$remote.surface_kind -ceq 'release-asset' -and [string]$Binding.asset_name -cne [string]$remote.asset_name){
        return New-CustomAppRemoteSourceDecision $true $false 'release-asset-continuity-drift' 'bound-release-asset-name-changed' $true $true $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    if(-not (Test-CustomAppRemoteSha256 ([string]$Binding.last_verified_local_tree_sha256)) -or [string]$Binding.last_verified_local_tree_sha256 -cne $CurrentLocalTreeSha256){
        return New-CustomAppRemoteSourceDecision $true $false 'local-tree-drift' 'current-local-tree-no-longer-matches-last-verified-tree' $true $true $true $false $false $false $true $null ([string]$remote.tree_sha256)
    }
    $changed=([string]$remote.tree_sha256 -cne $CurrentLocalTreeSha256)
    $status=$(if($changed){'remote-change-observed'}else{'remote-current'})
    $reason=$(if($changed){'verified-same-repository-and-surface-new-tree-observed'}else{'verified-same-repository-and-surface-current-tree'})
    return New-CustomAppRemoteSourceDecision $true $true $status $reason $true $true $true $true $changed $false $false $null ([string]$remote.tree_sha256)
}

function Test-CustomAppRemoteSourceMutationAuthority {
    param([Parameter(Mandatory=$true)]$Decision)
    return ([bool]$Decision.mutation_authorized -or [bool]$Decision.auto_update_authorized -or [bool]$Decision.auto_install_authorized)
}
