$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=Resolve-Path (Join-Path $here '..\..')
. (Join-Path $root 'validation\custom-app-remote-observation-collector-v0.1.0\custom-app-remote-observer.ps1')
. (Join-Path $root 'validation\custom-app-remote-observation-collector-v0.1.1\release-id-fix-v011.ps1')
. (Join-Path $root 'validation\custom-app-remote-source-contract-v0.1.0\custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation\custom-app-remote-source-contract-v0.1.1\release-continuity-v011.ps1')
. (Join-Path $root 'validation\custom-app-local-runtime-baseline-v0.1.0\custom-app-local-runtime-baseline.ps1')
. (Join-Path $here 'custom-app-stage-acquisition.ps1')

$script:Cases=0
function Need([bool]$Condition,[string]$Message){$script:Cases++;if(-not $Condition){throw "CASE $($script:Cases) FAILED: $Message"}}
function NeedReason($Decision,[string]$Expected,[string]$Label){Need (-not [bool]$Decision.ok -and [string]$Decision.reason -ceq $Expected) "$Label reason=$([string]$Decision.reason) expected=$Expected"}
function Clone($o){return (($o|ConvertTo-Json -Depth 30)|ConvertFrom-Json)}

function New-TestZip {
    param([Parameter(Mandatory=$true)][string]$ZipPath,[Parameter(Mandatory=$true)][hashtable]$Entries)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $parent=Split-Path -Parent $ZipPath;if(-not (Test-Path $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $stream=[IO.File]::Open($ZipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    try{
        foreach($name in @($Entries.Keys)){
            $entry=$zip.CreateEntry([string]$name,[IO.Compression.CompressionLevel]::Optimal)
            $s=$entry.Open()
            try{$bytes=[Text.Encoding]::UTF8.GetBytes([string]$Entries[$name]);$s.Write($bytes,0,$bytes.Length)}finally{$s.Dispose()}
        }
    }finally{$zip.Dispose();$stream.Dispose()}
}

function New-GoodBindingRow {
    param([string]$Surface='repo-commit-root',[string]$Tree=('a'*64),[string]$Commit=('b'*40),[string]$Manifest='Future App',[string]$Source='example/future-app',[int64]$RepoId=123456)
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity=$Source;github_repo_id=$RepoId;surface_kind=$Surface;asset_name=$null;layout_root='.';manifest_name=$Manifest
        last_verified_local_tree_sha256=('c'*64);last_verified_remote_tree_sha256=$Tree;last_verified_commit_sha=$Commit;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    if($Surface -ceq 'release-asset'){
        $binding.release_asset_selector='unique-zip-asset';$binding.asset_name='future-app.zip';$binding.last_observed_asset_id=[int64]987654;$binding.last_observed_asset_digest_sha256=('d'*64)
    }
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name='future-app';active=$true;source_identity=$Source;binding=$binding
        last_success='2026-10-28T09:00:00+00:00';last_status='remote-change-observed';last_remote_tree_sha256=$Tree;last_remote_commit_sha=$Commit
        update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
}

$workspaces=New-Object System.Collections.Generic.List[string]
try{
    $row=New-GoodBindingRow
    $d=Test-CustomAppStageBindingRowV010 -BindingRow $row -ExpectedName 'future-app'
    Need ([bool]$d.ok -and [string]$d.reason -ceq 'binding-current-strict-deny') 'good binding row was not accepted'
    Need (Test-CustomAppStageSha256V010 ([string]$d.binding_fingerprint)) 'binding fingerprint missing'
    Need ((Get-CustomAppStageBindingFingerprintV010 $row) -ceq (Get-CustomAppStageBindingFingerprintV010 $row)) 'binding fingerprint is not deterministic'

    $x=Clone $row;$x.PSObject.Properties.Remove('mutation_mode');NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-authority-schema-missing-mutation_mode' 'missing row mutation_mode'
    $x=Clone $row;$x.PSObject.Properties.Remove('auto_update_authorized');NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-authority-schema-missing-auto_update_authorized' 'missing row auto_update'
    $x=Clone $row;$x.auto_install_authorized=$true;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-auto-authority-true' 'row authority true'
    $x=Clone $row;$x.binding.PSObject.Properties.Remove('mutation_mode');NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'immutable-binding-authority-schema-missing-mutation_mode' 'missing immutable mutation_mode'
    $x=Clone $row;$x.binding.PSObject.Properties.Remove('auto_install_authorized');NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'immutable-binding-authority-schema-missing-auto_install_authorized' 'missing immutable auto_install'
    $x=Clone $row;$x.binding.auto_update_authorized=$true;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'immutable-binding-auto-authority-true' 'immutable authority true'
    $x=Clone $row;$x.active=$false;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-not-active-current' 'inactive row'
    $x=Clone $row;$x.update_observed=$false;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-no-current-remote-change' 'no current update'
    $x=Clone $row;$x.requires_reenrollment=$true;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-not-active-current' 'reenrollment row'
    $x=Clone $row;$x.user_removed=$true;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-not-active-current' 'removed row'
    $x=Clone $row;$x.last_success='not-a-time';NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-last-success-invalid' 'bad last success'
    $x=Clone $row;$x.source_identity='Bad Source';NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-source-invalid' 'bad source'
    $x=Clone $row;$x.binding.github_repo_id=0;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'immutable-binding-repo-id-invalid' 'bad repo id'
    $x=Clone $row;$x.last_remote_commit_sha='bad';NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'binding-row-remote-identity-invalid' 'bad commit'
    $x=Clone $row;$x.binding.last_verified_remote_tree_sha256=('e'*64);NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'immutable-binding-remote-continuity-drift' 'remote tree continuity drift'

    $release=New-GoodBindingRow -Surface 'release-asset'
    Need ([bool](Test-CustomAppStageBindingRowV010 $release 'future-app').ok) 'good release binding denied'
    $x=Clone $release;$x.binding.release_asset_selector='latest-by-name';NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'release-selector-invalid' 'release selector drift'
    $x=Clone $release;$x.binding.last_observed_asset_id=0;NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'release-asset-id-or-digest-invalid' 'release asset id invalid'
    $x=Clone $release;$x.binding.last_observed_asset_digest_sha256='bad';NeedReason (Test-CustomAppStageBindingRowV010 $x 'future-app') 'release-asset-id-or-digest-invalid' 'release digest invalid'

    $workspace=New-CustomAppStageWorkspaceV010;$workspaces.Add($workspace)
    $repoZip=Join-Path $workspace 'repo.zip'
    New-TestZip $repoZip @{
        'wrapper/index.js'="console.log('v2');`n";
        'wrapper/manifest.json'='{"name":"Future App"}';
        'wrapper/assets/payload.txt'='payload-v2'
    }
    $e=Get-CustomAppObserverZipEvidence -ZipPath $repoZip -WrapperMode required
    Need ([bool]$e.manifest_valid -and [string]$e.manifest_name -ceq 'Future App' -and [string]$e.layout_root -ceq '.') 'repo fixture evidence invalid'
    $dest=Join-Path $workspace 'stage-repo'
    $stage=Expand-CustomAppStageArchiveV010 -ZipPath $repoZip -Destination $dest -ValidationRoot $workspace -WrapperMode required -Name 'future-app' -ExpectedTreeSha256 ([string]$e.tree_sha256) -ExpectedManifestName 'Future App'
    Need ([string]$stage.tree_sha256 -ceq [string]$e.tree_sha256 -and [bool]$stage.baseline.installable) 'repo wrapper stage did not reproduce exact tree'
    Need (-not (Test-CustomAppStageAcquisitionMutationAuthorityV010 $stage)) 'stage extraction result gained authority'

    $workspace2=New-CustomAppStageWorkspaceV010;$workspaces.Add($workspace2)
    $releaseZip=Join-Path $workspace2 'release.zip'
    New-TestZip $releaseZip @{'index.js'='x';'manifest.json'='{"name":"Future App"}';'package.json'='{"repository":"https://github.com/example/future-app"}'}
    $e2=Get-CustomAppObserverZipEvidence -ZipPath $releaseZip -WrapperMode auto
    $stage2=Expand-CustomAppStageArchiveV010 -ZipPath $releaseZip -Destination (Join-Path $workspace2 'stage-release') -ValidationRoot $workspace2 -WrapperMode auto -Name 'future-app' -ExpectedTreeSha256 ([string]$e2.tree_sha256) -ExpectedManifestName 'Future App'
    Need ([string]$stage2.tree_sha256 -ceq [string]$e2.tree_sha256) 'release-root stage did not reproduce exact tree'
    $bindingCheck=Test-CustomAppStageBindingRowV010 (New-GoodBindingRow -Tree ([string]$e2.tree_sha256)) 'future-app'
    Need ([bool](Test-CustomAppStageEvidenceAgainstBindingV010 $e2 $bindingCheck).ok) 'matching package repository evidence denied'

    $badPkgZip=Join-Path $workspace2 'badpkg.zip'
    New-TestZip $badPkgZip @{'index.js'='x';'manifest.json'='{"name":"Future App"}';'package.json'='{"repository":"https://github.com/other/repo"}'}
    $badPkg=Get-CustomAppObserverZipEvidence -ZipPath $badPkgZip -WrapperMode auto
    $bc=Test-CustomAppStageBindingRowV010 (New-GoodBindingRow -Tree ([string]$badPkg.tree_sha256)) 'future-app'
    NeedReason (Test-CustomAppStageEvidenceAgainstBindingV010 $badPkg $bc) 'remote-package-repository-conflict' 'package repository conflict'

    $preexisting=Join-Path $workspace2 'already';New-Item -ItemType Directory -Path $preexisting|Out-Null
    $threw=$false;try{Expand-CustomAppStageArchiveV010 -ZipPath $releaseZip -Destination $preexisting -ValidationRoot $workspace2 -WrapperMode auto -Name 'future-app' -ExpectedTreeSha256 ([string]$e2.tree_sha256) -ExpectedManifestName 'Future App'|Out-Null}catch{$threw=$true}
    Need $threw 'pre-existing stage destination was not denied'

    $wrongDest=Join-Path $workspace2 'wrong-tree';$threw=$false;try{Expand-CustomAppStageArchiveV010 -ZipPath $releaseZip -Destination $wrongDest -ValidationRoot $workspace2 -WrapperMode auto -Name 'future-app' -ExpectedTreeSha256 ('f'*64) -ExpectedManifestName 'Future App'|Out-Null}catch{$threw=$true}
    Need ($threw -and -not (Test-Path $wrongDest)) 'tree mismatch did not fail before/residue-free extraction'

    $wrongManifest=Join-Path $workspace2 'wrong-manifest';$threw=$false;try{Expand-CustomAppStageArchiveV010 -ZipPath $releaseZip -Destination $wrongManifest -ValidationRoot $workspace2 -WrapperMode auto -Name 'future-app' -ExpectedTreeSha256 ([string]$e2.tree_sha256) -ExpectedManifestName 'Other App'|Out-Null}catch{$threw=$true}
    Need ($threw -and -not (Test-Path $wrongManifest)) 'manifest mismatch did not fail without residue'

    $vcsZip=Join-Path $workspace2 'vcs.zip';New-TestZip $vcsZip @{'index.js'='x';'manifest.json'='{"name":"Future App"}';'.git/config'='secret'}
    $vcsEvidence=Get-CustomAppObserverZipEvidence -ZipPath $vcsZip -WrapperMode auto
    $bc=Test-CustomAppStageBindingRowV010 (New-GoodBindingRow -Tree ([string]$vcsEvidence.tree_sha256)) 'future-app'
    NeedReason (Test-CustomAppStageEvidenceAgainstBindingV010 $vcsEvidence $bc) 'remote-vcs-metadata-forbidden' 'archive VCS metadata'
    $vcsDest=Join-Path $workspace2 'vcs-stage';$threw=$false;try{Expand-CustomAppStageArchiveV010 -ZipPath $vcsZip -Destination $vcsDest -ValidationRoot $workspace2 -WrapperMode auto -Name 'future-app' -ExpectedTreeSha256 ([string]$vcsEvidence.tree_sha256) -ExpectedManifestName 'Future App'|Out-Null}catch{$threw=$true}
    Need ($threw -and -not (Test-Path $vcsDest)) 'VCS metadata archive was extracted or left residue'

    $caseZip=Join-Path $workspace2 'case.zip';New-TestZip $caseZip @{'index.js'='x';'INDEX.JS'='y';'manifest.json'='{"name":"Future App"}'}
    $threw=$false;try{Get-CustomAppObserverZipEvidence -ZipPath $caseZip -WrapperMode auto|Out-Null}catch{$threw=$true};Need $threw 'case-colliding archive was not denied'

    $traversalZip=Join-Path $workspace2 'traversal.zip';New-TestZip $traversalZip @{'../escape.txt'='x';'index.js'='x';'manifest.json'='{"name":"Future App"}'}
    $threw=$false;try{Get-CustomAppObserverZipEvidence -ZipPath $traversalZip -WrapperMode auto|Out-Null}catch{$threw=$true};Need $threw 'path traversal archive was not denied'

    $outside=Join-Path ([IO.Path]::GetTempPath()) ('outside-'+[guid]::NewGuid().ToString('N'))
    $threw=$false;try{Assert-CustomAppStagePathV010 -Root $workspace2 -Path $outside -Label 'outside'|Out-Null}catch{$threw=$true};Need $threw 'outside stage path was not denied'
    $threw=$false;try{Remove-CustomAppStageWorkspaceV010 -Path $outside}catch{$threw=$true};Need $threw 'cleanup accepted path outside dedicated stage root'

    $result=[pscustomobject]@{mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false}
    Need (-not (Test-CustomAppStageAcquisitionMutationAuthorityV010 $result)) 'strict denied stage result was considered authorized'
    $result.PSObject.Properties.Remove('mutation_mode');Need (Test-CustomAppStageAcquisitionMutationAuthorityV010 $result) 'missing stage-result authority schema did not fail closed'

    Write-Host "CUSTOM_APP_STAGE_ACQUISITION_ACCEPTANCE_PASS cases=$script:Cases"
} finally {
    foreach($w in @($workspaces.ToArray())){try{if(Test-Path -LiteralPath $w){Remove-CustomAppStageWorkspaceV010 -Path $w}}catch{}}
}
