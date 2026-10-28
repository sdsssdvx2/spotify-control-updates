$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=Split-Path -Parent (Split-Path -Parent $here)
$depRoot=Join-Path $env:TEMP ('custom-app-shadow-deps-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $depRoot|Out-Null
function Get-PinnedDependencyFile([string]$Commit,[string]$RepoPath,[string]$Name){
    $lines=@(& git -C $root show "$Commit`:$RepoPath")
    if($LASTEXITCODE -ne 0){throw "Could not materialize pinned dependency: $Commit`:$RepoPath"}
    $out=Join-Path $depRoot $Name
    [IO.File]::WriteAllText($out,(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
    return $out
}
. (Get-PinnedDependencyFile '57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b' 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1' 'lifecycle-settings-core.ps1')
. (Get-PinnedDependencyFile 'b339f2b79a267c13cf3c5974aea2fff3786d3093' 'validation/custom-app-provenance-enrollment-v0.1.0/custom-app-provenance.ps1' 'custom-app-provenance.ps1')
. (Get-PinnedDependencyFile '19109205bd2e61e862c3b9acd61946568397ecb5' 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1' 'custom-app-remote-source-contract.ps1')
. (Get-PinnedDependencyFile '7402ea5c77e58cd072f0166411d40e7726093f3c' 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1' 'custom-app-local-runtime-baseline.ps1')
. (Get-PinnedDependencyFile 'c420a1df6f306c7ba74772b91241cb14abd04738' 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1' 'custom-app-stage-acquisition.ps1')
. (Get-PinnedDependencyFile '1a2461a6929e9cabd50d27f95e0744f83443b9e8' 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1' 'custom-app-update-transaction.ps1')
. (Join-Path $here 'custom-app-shadow-executor.ps1')
. (Join-Path $here 'shadow-executor-safety-overlay.ps1')

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

$script:Cases=0
function Need([bool]$Condition,[string]$Message){$script:Cases++;if(-not $Condition){throw "CASE $($script:Cases) FAILED: $Message"}}
function Write-Utf8NoBom([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if(-not(Test-Path $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null};[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}

function New-ShadowFixture {
    param([bool]$ChangePackageVersion=$true)
    $validationRoot=Get-CustomAppStageWorkspaceRootV010
    if(-not(Test-Path $validationRoot)){New-Item -ItemType Directory -Force -Path $validationRoot|Out-Null}
    $fixture=Join-Path $validationRoot ('shadow-fixture-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $fixture|Out-Null
    $live=Join-Path $fixture 'live';$stageWorkspace=Join-Path $fixture 'stage-workspace';$stagePath=Join-Path $stageWorkspace 'stage'
    New-Item -ItemType Directory -Force -Path $live,$stagePath|Out-Null
    Write-Utf8NoBom (Join-Path $live 'index.js') "console.log('old');`n"
    Write-Utf8NoBom (Join-Path $live 'manifest.json') '{"name":"Future App"}'
    Write-Utf8NoBom (Join-Path $live 'package.json') '{"name":"future-app","version":"1.0.0","repository":"https://github.com/example/future-app"}'
    $git=Join-Path $live '.git';New-Item -ItemType Directory -Force -Path $git|Out-Null
    $gitConfig=((@('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/example/future-app.git') -join "`n")+"`n")
    Write-Utf8NoBom (Join-Path $git 'config') $gitConfig

    Write-Utf8NoBom (Join-Path $stagePath 'index.js') "console.log('new');`n"
    Write-Utf8NoBom (Join-Path $stagePath 'manifest.json') '{"name":"Future App"}'
    $newVersion=if($ChangePackageVersion){'2.0.0'}else{'1.0.0'}
    Write-Utf8NoBom (Join-Path $stagePath 'package.json') ('{"name":"future-app","version":"'+$newVersion+'","repository":"https://github.com/example/future-app"}')

    $current=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $live
    $stageBaseline=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $stagePath
    if(-not $current.safe -or -not $stageBaseline.safe){throw 'Fixture baseline unsafe.'}
    $lifecycle=[pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name='future-app';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($live);mutation_mode='deny'}
    $lifeRoot=[pscustomobject]@{};$lifeRoot|Add-Member -NotePropertyName 'custom-app:future-app' -NotePropertyValue $lifecycle
    $state=[pscustomobject]@{lifecycle=$lifeRoot}
    $evidence=Get-CustomAppLocalProvenanceEvidence -Name 'future-app' -AppPath $live
    $prov=Update-CustomAppProvenanceEnrollment -State $state -Evidence $evidence -ObservedAt '2026-10-28T11:00:00+00:00'
    $commit=('b'*40)
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity='example/future-app';github_repo_id=[int64]123456;surface_kind='repo-commit-root';asset_name=$null;layout_root='.';manifest_name='Future App'
        last_verified_local_tree_sha256=[string]$current.tree_sha256;last_verified_remote_tree_sha256=[string]$stageBaseline.tree_sha256;last_verified_commit_sha=$commit
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $row=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name='future-app';active=$true;source_identity='example/future-app';binding=$binding
        last_success='2026-10-28T11:01:00+00:00';last_status='remote-change-observed';last_local_tree_sha256=[string]$current.tree_sha256;last_local_manifest_name=[string]$current.manifest_name;last_remote_tree_sha256=[string]$stageBaseline.tree_sha256;last_remote_commit_sha=$commit
        update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $bindingCheck=Test-CustomAppStageBindingRowV010 -BindingRow $row -ExpectedName 'future-app';if(-not $bindingCheck.ok){throw "Fixture binding invalid: $($bindingCheck.reason)"}
    $stageResult=[pscustomobject]@{
        schema=1;managed_by='custom-app-stage-acquisition-v1';status='staged-verified';name='future-app';source_identity='example/future-app';github_repo_id=[int64]123456;surface_kind='repo-commit-root'
        commit_sha=$commit;remote_tree_sha256=[string]$stageBaseline.tree_sha256;binding_fingerprint=[string]$bindingCheck.binding_fingerprint;workspace_path=$stageWorkspace;stage_path=$stagePath;archive_sha256=('a'*64);stage_baseline=$stageBaseline
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $local=Join-Path $fixture 'persistence\Local';$app=Join-Path $fixture 'persistence\Roaming';$backups=Join-Path $fixture 'persistence\Backups'
    $ldb=Join-Path $local 'Spotify\Browser\Local Storage\leveldb\000001.ldb';Write-Utf8NoBom $ldb 'marketplace-fixture'
    $cfg=Join-Path $app 'spicetify\config-xpui.ini';Write-Utf8NoBom $cfg "[AdditionalOptions]`nextensions = fixture.js`n"
    $persistBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $app
    return [pscustomobject]@{fixture=$fixture;validation_root=$validationRoot;live=$live;stage=$stageResult;lifecycle=$lifecycle;provenance=$prov;binding=$row;current=$current;remote=$stageBaseline;local=$local;app=$app;backups=$backups;drift_target=$ldb;persistence_before=$persistBefore}
}

function Remove-ShadowFixture($F){if($null -ne $F -and (Test-Path -LiteralPath $F.fixture)){Remove-Item -LiteralPath $F.fixture -Recurse -Force -ErrorAction SilentlyContinue}}

$f=$null
try{
    $f=New-ShadowFixture -ChangePackageVersion $true
    $fresh=Test-CustomAppShadowFreshProvenanceV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding
    Need ([bool]$fresh.ok) "fresh provenance denied: $($fresh.reason)"
    Need ([string]$fresh.evidence_fingerprint -ceq [string]$f.provenance.evidence_fingerprint) 'fresh provenance fingerprint mismatch'
    $r=Invoke-CustomAppShadowWithAcquiredStageV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -StageResult $f.stage -LocalAppDataRoot $f.local -AppDataRoot $f.app -PersistenceBackupRoot $f.backups
    Need ([string]$r.status -ceq 'committed-shadow-fixture' -and [bool]$r.committed -and -not [bool]$r.production_mutation_authorized) "normal shadow commit failed: $($r.status) / $($r.reason)"
    $after=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $f.live;Need ([string]$after.tree_sha256 -ceq [string]$f.remote.tree_sha256) 'normal shadow commit did not install remote runtime tree'
    Need (Test-Path -LiteralPath (Join-Path $f.live '.git\config') -PathType Leaf) 'safe live git provenance was not preserved'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $f.local -AppDataRoot $f.app;Need ([string]$persist.fingerprint -ceq [string]$f.persistence_before.fingerprint) 'normal shadow commit changed persistence'
    Need ([string]$r.post_provenance_fingerprint -cne [string]$r.fresh_provenance_fingerprint) 'package version change did not exercise allowed post-update provenance fingerprint change'
} finally {Remove-ShadowFixture $f}

try{
    $f=New-ShadowFixture -ChangePackageVersion $true
    $r=Invoke-CustomAppShadowWithAcquiredStageV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -StageResult $f.stage -LocalAppDataRoot $f.local -AppDataRoot $f.app -PersistenceBackupRoot $f.backups -InjectTransactionPostApplyFailure
    Need ([string]$r.status -ceq 'rolled-back-shadow-fixture' -and [bool]$r.rolled_back) "injected transaction failure did not rollback: $($r.status) / $($r.reason)"
    $after=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $f.live;Need ([string]$after.tree_sha256 -ceq [string]$f.current.tree_sha256) 'transaction rollback did not restore original runtime tree'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $f.local -AppDataRoot $f.app;Need ([string]$persist.fingerprint -ceq [string]$f.persistence_before.fingerprint) 'transaction rollback changed persistence'
} finally {Remove-ShadowFixture $f}

try{
    $f=New-ShadowFixture -ChangePackageVersion $true
    $r=Invoke-CustomAppShadowWithAcquiredStageV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -StageResult $f.stage -LocalAppDataRoot $f.local -AppDataRoot $f.app -PersistenceBackupRoot $f.backups -InjectPersistenceDriftAfterApply -PersistenceDriftTarget $f.drift_target
    Need ([string]$r.status -ceq 'rolled-back-after-persistence-drift' -and [bool]$r.rolled_back) "persistence drift did not trigger verified rollback: $($r.status) / $($r.reason)"
    $after=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $f.live;Need ([string]$after.tree_sha256 -ceq [string]$f.current.tree_sha256) 'persistence rollback did not restore original runtime tree'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $f.local -AppDataRoot $f.app;Need ([string]$persist.fingerprint -ceq [string]$f.persistence_before.fingerprint) 'persistence rollback did not restore exact persistence fingerprint'
} finally {Remove-ShadowFixture $f}

try{
    $f=New-ShadowFixture -ChangePackageVersion $false
    $driftGit=((@('[remote "origin"]','    url = https://github.com/other/fork.git') -join "`n")+"`n")
    Write-Utf8NoBom (Join-Path $f.live '.git\config') $driftGit
    $fresh=Test-CustomAppShadowFreshProvenanceV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding
    Need (-not [bool]$fresh.ok -and ([string]$fresh.reason -in @('fresh-provenance-source-drift','fresh-provenance-fingerprint-drift','fresh-provenance-not-strong:conflicting-source-claims'))) "pre-acquisition source drift escaped: $($fresh.reason)"
} finally {Remove-ShadowFixture $f}

try{
    $f=New-ShadowFixture -ChangePackageVersion $false
    $f.provenance.PSObject.Properties.Remove('mutation_mode')
    $fresh=Test-CustomAppShadowFreshProvenanceV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding
    Need (-not [bool]$fresh.ok -and [string]$fresh.reason -like 'provenance-row-authority-schema-missing-*') "missing provenance authority schema escaped: $($fresh.reason)"
} finally {Remove-ShadowFixture $f}

try{
    $f=New-ShadowFixture -ChangePackageVersion $false
    $f.stage.binding_fingerprint=('f'*64)
    $r=Invoke-CustomAppShadowWithAcquiredStageV010 -Name 'future-app' -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -StageResult $f.stage -LocalAppDataRoot $f.local -AppDataRoot $f.app -PersistenceBackupRoot $f.backups
    Need ([string]$r.status -ceq 'denied-or-failed-shadow' -and [string]$r.reason -like '*cryptographically bound*') "stage binding fingerprint swap escaped: $($r.status) / $($r.reason)"
    $after=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $f.live;Need ([string]$after.tree_sha256 -ceq [string]$f.current.tree_sha256) 'denied stage binding swap mutated live runtime'
} finally {Remove-ShadowFixture $f}

$outsideLocal=$null;$outsideApp=$null;$outsideBack=$null
try{
    $f=New-ShadowFixture -ChangePackageVersion $false
    $outsideLocal=Join-Path $env:TEMP ('outside-shadow-'+[guid]::NewGuid().ToString('N'));$outsideApp=Join-Path $env:TEMP ('outside-shadow-'+[guid]::NewGuid().ToString('N'));$outsideBack=Join-Path $env:TEMP ('outside-shadow-'+[guid]::NewGuid().ToString('N'))
    $threw=$false;try{New-CustomAppShadowPersistenceSessionV010 -LocalAppDataRoot $outsideLocal -AppDataRoot $outsideApp -BackupRoot $outsideBack|Out-Null}catch{$threw=$true}
    Need $threw 'shadow persistence session accepted roots outside dedicated fixture root'
} finally {Remove-ShadowFixture $f;foreach($p in @($outsideLocal,$outsideApp,$outsideBack)){if($p -and (Test-Path $p)){Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue}}}

Write-Host "CUSTOM_APP_SHADOW_EXECUTOR_ACCEPTANCE_PASS cases=$script:Cases"
