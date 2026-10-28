$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$root=Resolve-Path (Join-Path $here '..\..')
. (Join-Path $root 'validation\custom-app-remote-source-contract-v0.1.0\custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation\custom-app-local-runtime-baseline-v0.1.0\custom-app-local-runtime-baseline.ps1')
. (Join-Path $here 'custom-app-update-transaction.ps1')

$script:Cases=0
function Need([bool]$Condition,[string]$Message){$script:Cases++;if(-not $Condition){throw "CASE $($script:Cases) FAILED: $Message"}}
function NeedReason($Decision,[string]$Expected,[string]$Label){Need (-not [bool]$Decision.eligible -and [string]$Decision.reason -ceq $Expected) "$Label reason=$([string]$Decision.reason) expected=$Expected"}

function Write-FixtureApp {
    param([string]$Path,[string]$Version,[string]$ManifestName='Future App',[bool]$WithGit=$false,[string]$GitSource='example/future-app')
    New-Item -ItemType Directory -Force -Path $Path|Out-Null
    [IO.File]::WriteAllText((Join-Path $Path 'index.js'),"// version $Version`nconsole.log('$Version');`n",[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $Path 'manifest.json'),('{"name":"'+$ManifestName+'"}'),[Text.Encoding]::UTF8)
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'assets')|Out-Null
    [IO.File]::WriteAllText((Join-Path $Path 'assets\payload.txt'),("payload-"+$Version),[Text.Encoding]::UTF8)
    if($WithGit){New-Item -ItemType Directory -Force -Path (Join-Path $Path '.git')|Out-Null;[IO.File]::WriteAllText((Join-Path $Path '.git\config'),("[remote `"origin`"]`n    url = https://github.com/$GitSource.git`n"),[Text.Encoding]::ASCII)}
}

function New-GoodContext {
    param([string]$Tag,[bool]$WithGit=$true)
    $vr=Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-update-tx-'+$Tag+'-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $vr|Out-Null
    $live=Join-Path $vr 'live';$stage=Join-Path $vr 'stage';$backup=Join-Path $vr 'backup';$rollback=Join-Path $vr 'rollback'
    Write-FixtureApp $live '1.0.0' 'Future App' $WithGit;Write-FixtureApp $stage '2.0.0' 'Future App' $false
    $current=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $live;$staged=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $stage
    $source='example/future-app';$commit=('b'*40)
    $lifecycle=[pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name='future-app';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($live)}
    $provenance=[pscustomobject]@{managed_by='custom-app-provenance-v1';name='future-app';source_identity=$source;last_proven_source=$source;source_changed=$false;requires_reenrollment=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $binding=[pscustomobject]@{schema=1;managed_by='custom-app-remote-source-v1';source_identity=$source;github_repo_id=[int64]123456;surface_kind='repo-commit-root';asset_name=$null;layout_root='.';manifest_name='Future App';last_verified_local_tree_sha256=[string]$current.tree_sha256;last_verified_remote_tree_sha256=[string]$staged.tree_sha256;last_verified_commit_sha=$commit;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $bindingRow=[pscustomobject]@{schema=1;managed_by='custom-app-remote-binding-observer-v1';name='future-app';active=$true;source_identity=$source;binding=$binding;last_success='2026-10-28T08:00:00+00:00';last_status='remote-change-observed';last_reason='verified-same-repository-and-surface-new-tree-observed';last_error=$null;last_local_tree_sha256=[string]$current.tree_sha256;last_local_manifest_name='Future App';last_remote_tree_sha256=[string]$staged.tree_sha256;last_remote_commit_sha=$commit;update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    return [pscustomobject]@{root=$vr;live=$live;stage=$stage;backup=$backup;rollback=$rollback;current=$current;staged=$staged;lifecycle=$lifecycle;provenance=$provenance;bindingRow=$bindingRow}
}

function Decide($c){Resolve-CustomAppUpdateTransactionEligibilityV010 -Name 'future-app' -LifecycleRow $c.lifecycle -ProvenanceRow $c.provenance -BindingRow $c.bindingRow -CurrentBaseline $c.current -StageBaseline $c.staged -ValidationRoot $c.root -StagePath $c.stage -BackupPath $c.backup -RollbackPath $c.rollback}
function Clone($o){return (($o|ConvertTo-Json -Depth 20)|ConvertFrom-Json)}
function GoodProof(){return [pscustomobject]@{backup_required=$true;backup_complete=$true;pre_snapshot_fingerprint=('a'*64);post_snapshot_fingerprint=('a'*64)}}

$contexts=New-Object System.Collections.Generic.List[object]
try{
    $c=New-GoodContext 'eligible';$contexts.Add($c);$d=Decide $c
    Need ([bool]$d.eligible -and [string]$d.reason -ceq 'eligible-fixture-transaction-plan') 'happy-path eligibility failed'
    Need ([string]$d.plan.mutation_mode -ceq 'deny' -and -not [bool]$d.plan.production_mutation_authorized -and [bool]$d.plan.fixture_apply_authorized) 'plan authority contract drifted'
    Need ([bool]$d.plan.preserve_git) 'safe local .git was not marked for preservation'

    $x=New-GoodContext 'no-update';$contexts.Add($x);$x.bindingRow.update_observed=$false;NeedReason (Decide $x) 'binding-not-active-current-update' 'no update'
    $x=New-GoodContext 'inactive';$contexts.Add($x);$x.bindingRow.active=$false;NeedReason (Decide $x) 'binding-not-active-current-update' 'inactive binding'
    $x=New-GoodContext 'reenroll';$contexts.Add($x);$x.provenance.requires_reenrollment=$true;NeedReason (Decide $x) 'provenance-not-current-denied-or-reenrollment-required' 'reenrollment'
    $x=New-GoodContext 'removed';$contexts.Add($x);$x.lifecycle.user_removed=$true;NeedReason (Decide $x) 'user-removed-or-absent' 'user removal'
    $x=New-GoodContext 'ambiguous';$contexts.Add($x);$x.lifecycle.ambiguous=$true;NeedReason (Decide $x) 'lifecycle-unsafe-or-ambiguous' 'ambiguous lifecycle'
    $x=New-GoodContext 'life-name';$contexts.Add($x);$x.lifecycle.name='other';NeedReason (Decide $x) 'lifecycle-name-mismatch' 'lifecycle name mismatch'
    $x=New-GoodContext 'prov-name';$contexts.Add($x);$x.provenance.name='other';NeedReason (Decide $x) 'provenance-name-mismatch' 'provenance name mismatch'
    $x=New-GoodContext 'binding-name';$contexts.Add($x);$x.bindingRow.name='other';NeedReason (Decide $x) 'binding-name-mismatch' 'binding name mismatch'
    $x=New-GoodContext 'source';$contexts.Add($x);$x.bindingRow.source_identity='example/other';NeedReason (Decide $x) 'binding-source-or-authority-drift' 'binding source mismatch'
    $x=New-GoodContext 'authority';$contexts.Add($x);$x.bindingRow.auto_update_authorized=$true;NeedReason (Decide $x) 'binding-source-or-authority-drift' 'binding authority drift'
    $x=New-GoodContext 'local-drift';$contexts.Add($x);$x.bindingRow.last_local_tree_sha256=('c'*64);NeedReason (Decide $x) 'current-local-tree-drift' 'local tree drift'
    $x=New-GoodContext 'remote-drift';$contexts.Add($x);$x.bindingRow.binding.last_verified_remote_tree_sha256=('d'*64);NeedReason (Decide $x) 'binding-remote-continuity-drift' 'remote binding continuity drift'
    $x=New-GoodContext 'stage-tree';$contexts.Add($x);$x.bindingRow.last_remote_tree_sha256=('e'*64);$x.bindingRow.binding.last_verified_remote_tree_sha256=('e'*64);NeedReason (Decide $x) 'stage-tree-does-not-match-verified-remote' 'stage tree mismatch'
    $x=New-GoodContext 'manifest';$contexts.Add($x);$x.bindingRow.binding.manifest_name='Other App';NeedReason (Decide $x) 'current-manifest-identity-drift' 'manifest mismatch'
    $x=New-GoodContext 'overlap';$contexts.Add($x);$x.backup=Join-Path $x.live 'backup';NeedReason (Decide $x) 'transaction-path-overlap' 'path overlap'
    $x=New-GoodContext 'outside';$contexts.Add($x);$sub=Join-Path $x.root 'validation-only';New-Item -ItemType Directory -Force -Path $sub|Out-Null;$r=Resolve-CustomAppUpdateTransactionEligibilityV010 -Name 'future-app' -LifecycleRow $x.lifecycle -ProvenanceRow $x.provenance -BindingRow $x.bindingRow -CurrentBaseline $x.current -StageBaseline $x.staged -ValidationRoot $sub -StagePath $x.stage -BackupPath $x.backup -RollbackPath $x.rollback;Need (-not [bool]$r.eligible -and [string]$r.reason -like 'fixture-path-denied:*') 'outside validation root was not denied'
    $x=New-GoodContext 'stage-git';$contexts.Add($x);New-Item -ItemType Directory -Force -Path (Join-Path $x.stage '.git')|Out-Null;[IO.File]::WriteAllText((Join-Path $x.stage '.git\config'),'x');NeedReason (Decide $x) 'stage-vcs-metadata-forbidden' 'stage .git'
    $x=New-GoodContext 'git-file';$contexts.Add($x);[IO.Directory]::Delete((Join-Path $x.live '.git'),$true);[IO.File]::WriteAllText((Join-Path $x.live '.git'),'gitdir: elsewhere');NeedReason (Decide $x) 'live-git-file-indirection-forbidden' 'live .git file'

    $x=New-GoodContext 'commit';$contexts.Add($x);$plan=(Decide $x).plan;$pre=Get-CustomAppUpdateTreeSnapshotV010 $x.live;$res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof (GoodProof)
    Need ([bool]$res.committed -and [string]$res.status -ceq 'committed' -and -not [bool]$res.production_mutation_authorized) 'fixture transaction did not commit safely'
    $postRuntime=Get-CustomAppLocalRuntimeBaseline -Name 'future-app' -AppPath $x.live;Need ([string]$postRuntime.tree_sha256 -ceq [string]$plan.expected_remote_tree_sha256) 'committed runtime tree does not equal remote tree'
    Need (Test-Path -LiteralPath (Join-Path $x.live '.git\config') -PathType Leaf) 'local .git provenance was not preserved on commit'
    Need (([IO.File]::ReadAllText((Join-Path $x.live '.git\config'))).Contains('example/future-app')) 'preserved .git provenance content drifted'
    $replay=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof (GoodProof);Need (-not [bool]$replay.committed -and [string]$replay.status -ceq 'denied-before-apply') 'transaction replay was not denied'

    $x=New-GoodContext 'rollback';$contexts.Add($x);$plan=(Decide $x).plan;$pre=Get-CustomAppUpdateTreeSnapshotV010 $x.live;$res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof (GoodProof) -InjectPostApplyFailure
    $after=Get-CustomAppUpdateTreeSnapshotV010 $x.live;Need ([bool]$res.rolled_back -and [bool]$res.rollback_verified -and [string]$after.tree_sha256 -ceq [string]$pre.tree_sha256) 'forced post-apply failure did not byte-restore live tree'

    $x=New-GoodContext 'persistence-pre';$contexts.Add($x);$plan=(Decide $x).plan;$bad=[pscustomobject]@{backup_required=$true;backup_complete=$false;pre_snapshot_fingerprint=('a'*64);post_snapshot_fingerprint=('a'*64)};$res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof $bad
    Need ([string]$res.status -ceq 'denied-before-apply' -and -not (Test-Path -LiteralPath $x.backup)) 'incomplete persistence backup mutated fixture'

    $x=New-GoodContext 'persistence-post';$contexts.Add($x);$plan=(Decide $x).plan;$pre=Get-CustomAppUpdateTreeSnapshotV010 $x.live;$script:PostReads=0;$proof=[pscustomobject]@{backup_required=$true;backup_complete=$true;pre_snapshot_fingerprint=('a'*64)};$proof|Add-Member -MemberType ScriptProperty -Name post_snapshot_fingerprint -Value {$script:PostReads++;if($script:PostReads -eq 1){'a'*64}else{'b'*64}}
    $res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof $proof;$after=Get-CustomAppUpdateTreeSnapshotV010 $x.live
    Need ([bool]$res.rolled_back -and [string]$res.reason -like 'Persistence verification failed after apply:*' -and [string]$after.tree_sha256 -ceq [string]$pre.tree_sha256) 'post-apply persistence drift did not roll back'

    $x=New-GoodContext 'stale-plan';$contexts.Add($x);$plan=(Decide $x).plan;[IO.File]::AppendAllText((Join-Path $x.live 'index.js'),'// local drift');$res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof (GoodProof)
    Need ([string]$res.status -ceq 'denied-before-apply' -and [string]$res.reason -like '*live tree changed*' -and -not (Test-Path -LiteralPath $x.backup)) 'stale plan was not denied before mutation'

    $x=New-GoodContext 'rollback-fail';$contexts.Add($x);$plan=(Decide $x).plan;$res=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $x.root -PersistenceProof (GoodProof) -InjectPostApplyFailure -InjectRollbackFailure
    Need ([string]$res.status -ceq 'rollback-failed' -and -not [bool]$res.committed) 'rollback failure was incorrectly committed'

    $x=New-GoodContext 'no-git';$contexts.Add($x);$d=Decide $x;Need ([bool]$d.eligible -and -not [bool]$d.plan.preserve_git) 'git-free fixture plan incorrectly requires VCS preservation'

    Write-Host "CUSTOM_APP_UPDATE_TRANSACTION_ACCEPTANCE_PASS cases=$script:Cases"
} finally {
    foreach($c in @($contexts.ToArray())){if($null -ne $c -and (Test-Path -LiteralPath $c.root)){Remove-Item -LiteralPath $c.root -Recurse -Force -ErrorAction SilentlyContinue}}
}
