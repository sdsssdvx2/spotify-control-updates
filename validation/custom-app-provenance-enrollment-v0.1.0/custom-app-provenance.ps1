$CustomAppProvenanceSchema = 1

function Get-ProvenanceStringSha256Lower {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function ConvertTo-GitHubRepositoryClaim {
    param([AllowNull()][string]$Value)
    $raw=if($null -eq $Value){''}else{$Value.Trim()}
    if([string]::IsNullOrWhiteSpace($raw)){
        return [pscustomobject]@{ ok=$false; identity=$null; secure=$false; transport=$null; reason='empty' }
    }

    $candidate=$raw
    $transport=$null
    $secure=$false
    if($candidate -match '^git\+https://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='git+https';$secure=$true}
    elseif($candidate -match '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='https';$secure=$true}
    elseif($candidate -match '^ssh://git@github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='ssh';$secure=$true}
    elseif($candidate -match '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='ssh-scp';$secure=$true}
    elseif($candidate -match '^git://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='git';$secure=$false}
    elseif($candidate -match '^http://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+)$'){$transport='http';$secure=$false}
    else{return [pscustomobject]@{ ok=$false; identity=$null; secure=$false; transport=$null; reason='not-exact-github-repository-url' }}

    $owner=[string]$Matches['owner'];$repo=[string]$Matches['repo']
    if($repo.EndsWith('.git',[StringComparison]::OrdinalIgnoreCase)){$repo=$repo.Substring(0,$repo.Length-4)}
    if([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)){
        return [pscustomobject]@{ ok=$false; identity=$null; secure=$secure; transport=$transport; reason='owner-or-repo-empty' }
    }
    if($owner -notmatch '^[A-Za-z0-9_.-]+$' -or $repo -notmatch '^[A-Za-z0-9_.-]+$' -or $owner -in @('.','..') -or $repo -in @('.','..')){
        return [pscustomobject]@{ ok=$false; identity=$null; secure=$secure; transport=$transport; reason='owner-or-repo-invalid' }
    }
    $identity=($owner.ToLowerInvariant()+'/'+$repo.ToLowerInvariant())
    return [pscustomobject]@{ ok=$true; identity=$identity; secure=$secure; transport=$transport; reason=$(if($secure){'normalized-secure-github'}else{'normalized-insecure-github'}) }
}

function Get-ProvenanceFileSha256Lower {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Get-CustomAppGitOriginEvidence {
    param([Parameter(Mandatory=$true)][string]$AppPath)
    $git=Join-Path $AppPath '.git'
    if(-not (Test-Path -LiteralPath $git)){return [pscustomobject]@{ present=$false; safe=$true; claim=$null; raw=$null; file_sha256=$null; reason='git-metadata-absent' }}
    $item=Get-Item -LiteralPath $git -Force -ErrorAction Stop
    if(-not $item.PSIsContainer){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=$null; reason='git-file-indirection-denied' }}
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=$null; reason='git-reparse-point-denied' }}
    $config=Join-Path $git 'config'
    if(-not (Test-Path -LiteralPath $config -PathType Leaf)){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=$null; reason='git-config-missing' }}
    $cfg=Get-Item -LiteralPath $config -Force -ErrorAction Stop
    if(($cfg.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [int64]$cfg.Length -gt 1048576){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=$null; reason='git-config-unsafe' }}
    $lines=@(Get-Content -LiteralPath $config -ErrorAction Stop)
    $inOrigin=$false;$urls=New-Object System.Collections.Generic.List[string]
    foreach($line in $lines){
        $t=$line.Trim()
        if($t -match '^\[(?<section>[^\]]+)\]$'){$inOrigin=([string]$Matches['section'] -match '^remote\s+"origin"$');continue}
        if($inOrigin -and $t -match '^url\s*=\s*(?<url>.+?)\s*$'){$urls.Add(([string]$Matches['url']).Trim())}
    }
    $distinct=@($urls.ToArray()|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique)
    if($distinct.Count -ne 1){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$(if($distinct.Count){$distinct -join '|'}else{$null}); file_sha256=(Get-ProvenanceFileSha256Lower $config); reason=$(if($distinct.Count -eq 0){'git-origin-missing'}else{'git-origin-ambiguous'}) }}
    $claim=ConvertTo-GitHubRepositoryClaim -Value $distinct[0]
    return [pscustomobject]@{ present=$true; safe=([bool]$claim.ok -and [bool]$claim.secure); claim=$claim; raw=$distinct[0]; file_sha256=(Get-ProvenanceFileSha256Lower $config); reason=$(if(-not $claim.ok){'git-origin-not-github'}elseif(-not $claim.secure){'git-origin-insecure'}else{'git-origin-secure'}) }
}

function Get-CustomAppPackageRepositoryEvidence {
    param([Parameter(Mandatory=$true)][string]$AppPath)
    $package=Join-Path $AppPath 'package.json'
    if(-not (Test-Path -LiteralPath $package -PathType Leaf)){return [pscustomobject]@{ present=$false; safe=$true; claim=$null; raw=$null; file_sha256=$null; reason='package-json-absent' }}
    $item=Get-Item -LiteralPath $package -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [int64]$item.Length -gt 1048576){return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=$null; reason='package-json-unsafe' }}
    try{$obj=Get-Content -LiteralPath $package -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}catch{return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=(Get-ProvenanceFileSha256Lower $package); reason='package-json-invalid' }}
    if(-not $obj.PSObject.Properties['repository'] -or $null -eq $obj.repository){return [pscustomobject]@{ present=$true; safe=$true; claim=$null; raw=$null; file_sha256=(Get-ProvenanceFileSha256Lower $package); reason='package-repository-absent' }}
    $raw=$null
    if($obj.repository -is [string]){$raw=[string]$obj.repository}
    elseif($obj.repository.PSObject.Properties['url']){$raw=[string]$obj.repository.url}
    else{return [pscustomobject]@{ present=$true; safe=$false; claim=$null; raw=$null; file_sha256=(Get-ProvenanceFileSha256Lower $package); reason='package-repository-shape-unsupported' }}
    $claim=ConvertTo-GitHubRepositoryClaim -Value $raw
    return [pscustomobject]@{ present=$true; safe=[bool]$claim.ok; claim=$claim; raw=$raw; file_sha256=(Get-ProvenanceFileSha256Lower $package); reason=$(if($claim.ok){'package-repository-github'}else{'package-repository-not-exact-github'}) }
}

function Get-CustomAppLocalProvenanceEvidence {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$AppPath)
    $full=[IO.Path]::GetFullPath($AppPath)
    if(-not (Test-Path -LiteralPath $full -PathType Container)){
        return [pscustomobject]@{schema=$CustomAppProvenanceSchema;name=$Name;path=$full;status='absent';source_candidate=$null;source_proven=$false;requires_reenrollment=$false;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower ('absent|'+$Name.ToLowerInvariant()));git=$null;package=$null}
    }
    $root=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        return [pscustomobject]@{schema=$CustomAppProvenanceSchema;name=$Name;path=$full;status='unsafe-local-root';source_candidate=$null;source_proven=$false;requires_reenrollment=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower ('unsafe-root|'+$Name.ToLowerInvariant()));git=$null;package=$null}
    }
    $git=Get-CustomAppGitOriginEvidence -AppPath $full;$pkg=Get-CustomAppPackageRepositoryEvidence -AppPath $full
    $claims=New-Object System.Collections.Generic.List[string]
    if($git.claim -and [bool]$git.claim.ok){$claims.Add([string]$git.claim.identity)}
    if($pkg.claim -and [bool]$pkg.claim.ok){$claims.Add([string]$pkg.claim.identity)}
    $ids=@($claims.ToArray()|Sort-Object -Unique)
    $status='unresolved';$candidate=$null;$proven=$false;$reenroll=$false
    if(-not [bool]$git.safe -or -not [bool]$pkg.safe){$status='unsafe-or-inconclusive-evidence';$reenroll=$true}
    elseif($ids.Count -gt 1){$status='conflicting-source-claims';$reenroll=$true}
    elseif($git.claim -and [bool]$git.claim.ok -and [bool]$git.claim.secure -and $ids.Count -eq 1){$candidate=$ids[0];$proven=$true;$status=$(if($pkg.claim -and [bool]$pkg.claim.ok){'proven-local-git-origin-corroborated'}else{'proven-local-git-origin'})}
    elseif($pkg.claim -and [bool]$pkg.claim.ok -and $ids.Count -eq 1){$candidate=$ids[0];$status='declared-package-only'}
    elseif($git.claim -and [bool]$git.claim.ok -and -not [bool]$git.claim.secure -and $ids.Count -eq 1){$candidate=$ids[0];$status='insecure-git-origin';$reenroll=$true}
    $canon=@(
        'schema='+$CustomAppProvenanceSchema,
        'name='+$Name.ToLowerInvariant(),
        'status='+$status,
        'candidate='+$(if($candidate){$candidate}else{''}),
        'git-reason='+[string]$git.reason,
        'git-id='+$(if($git.claim -and $git.claim.identity){[string]$git.claim.identity}else{''}),
        'git-sha='+[string]$git.file_sha256,
        'pkg-reason='+[string]$pkg.reason,
        'pkg-id='+$(if($pkg.claim -and $pkg.claim.identity){[string]$pkg.claim.identity}else{''}),
        'pkg-sha='+[string]$pkg.file_sha256
    ) -join "`n"
    return [pscustomobject]@{schema=$CustomAppProvenanceSchema;name=$Name;path=$full;status=$status;source_candidate=$candidate;source_proven=$proven;requires_reenrollment=$reenroll;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;evidence_fingerprint=(Get-ProvenanceStringSha256Lower $canon);git=$git;package=$pkg}
}

function Ensure-CustomAppProvenanceLedgerRoot {
    param([Parameter(Mandatory=$true)]$State)
    if(-not $State.PSObject.Properties['custom_app_provenance']){$State|Add-Member -NotePropertyName custom_app_provenance -NotePropertyValue ([pscustomobject]@{})}
    if($null -eq $State.custom_app_provenance){$State.custom_app_provenance=[pscustomobject]@{}}
    return $State.custom_app_provenance
}

function Get-CustomAppLifecycleRowForProvenance {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$Name)
    if(-not $State.PSObject.Properties['lifecycle'] -or $null -eq $State.lifecycle){return $null}
    $key='custom-app:'+$Name.Trim().ToLowerInvariant()
    if(-not $State.lifecycle.PSObject.Properties[$key]){return $null}
    return $State.lifecycle.PSObject.Properties[$key].Value
}

function Update-CustomAppProvenanceEnrollment {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Evidence,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')))
    $root=Ensure-CustomAppProvenanceLedgerRoot -State $State
    $name=[string]$Evidence.name;$key='custom-app:'+$name.Trim().ToLowerInvariant();$lifecycle=Get-CustomAppLifecycleRowForProvenance -State $State -Name $name
    if(-not $root.PSObject.Properties[$key]){
        $root|Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{schema=$CustomAppProvenanceSchema;key=$key;managed_by='custom-app-provenance-v1';name=$name;first_seen=$ObservedAt;last_seen=$null;source_identity=$null;last_proven_source=$null;observed_source_candidate=$null;source_status='new';evidence_fingerprint=$null;enrolled_at=$null;source_changed=$false;requires_reenrollment=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false})
    }
    $row=$root.PSObject.Properties[$key].Value
    if($null -eq $lifecycle -or [string]$lifecycle.managed_by -cne 'dynamic-spicetify-v1'){
        $row.last_seen=$ObservedAt;$row.source_identity=$null;$row.source_status='lifecycle-missing-or-owner-mismatch';$row.observed_source_candidate=[string]$Evidence.source_candidate;$row.evidence_fingerprint=[string]$Evidence.evidence_fingerprint;$row.requires_reenrollment=$true;$row.mutation_mode='deny';$row.auto_update_authorized=$false;$row.auto_install_authorized=$false
        return $row
    }
    if(-not [bool]$lifecycle.present -or [bool]$lifecycle.user_removed){
        $row.last_seen=$ObservedAt;$row.source_identity=$null;$row.source_status=$(if([bool]$lifecycle.user_removed){'user-removed'}else{'lifecycle-absent'});$row.observed_source_candidate=[string]$Evidence.source_candidate;$row.evidence_fingerprint=[string]$Evidence.evidence_fingerprint;$row.mutation_mode='deny';$row.auto_update_authorized=$false;$row.auto_install_authorized=$false
        return $row
    }
    if([bool]$lifecycle.ambiguous -or -not [bool]$lifecycle.safe_local_identity -or @($lifecycle.locations).Count -ne 1){
        $row.last_seen=$ObservedAt;$row.source_identity=$null;$row.source_status='unsafe-local-lifecycle';$row.observed_source_candidate=[string]$Evidence.source_candidate;$row.evidence_fingerprint=[string]$Evidence.evidence_fingerprint;$row.requires_reenrollment=$true;$row.mutation_mode='deny';$row.auto_update_authorized=$false;$row.auto_install_authorized=$false
        return $row
    }

    $row.last_seen=$ObservedAt;$row.observed_source_candidate=[string]$Evidence.source_candidate;$row.evidence_fingerprint=[string]$Evidence.evidence_fingerprint;$row.mutation_mode='deny';$row.auto_update_authorized=$false;$row.auto_install_authorized=$false
    if([bool]$Evidence.source_proven -and -not [string]::IsNullOrWhiteSpace([string]$Evidence.source_candidate)){
        $candidate=[string]$Evidence.source_candidate
        if([string]::IsNullOrWhiteSpace([string]$row.last_proven_source)){
            $row.last_proven_source=$candidate;$row.source_identity=$candidate;$row.source_status=[string]$Evidence.status;$row.enrolled_at=$ObservedAt;$row.source_changed=$false;$row.requires_reenrollment=$false
        }elseif([string]$row.last_proven_source -ceq $candidate){
            $row.source_identity=$candidate;$row.source_status=[string]$Evidence.status;$row.source_changed=$false;$row.requires_reenrollment=$false
        }else{
            $row.source_identity=$null;$row.source_status='source-change-blocked';$row.source_changed=$true;$row.requires_reenrollment=$true
        }
    }else{
        $row.source_identity=$null;$row.source_status=[string]$Evidence.status;$row.source_changed=$false;$row.requires_reenrollment=([bool]$Evidence.requires_reenrollment -or -not [string]::IsNullOrWhiteSpace([string]$row.last_proven_source))
    }
    return $row
}

function Test-CustomAppProvenanceMutationAuthority {
    param([Parameter(Mandatory=$true)]$Row)
    return ([string]$Row.mutation_mode -cne 'deny' -or [bool]$Row.auto_update_authorized -or [bool]$Row.auto_install_authorized)
}
