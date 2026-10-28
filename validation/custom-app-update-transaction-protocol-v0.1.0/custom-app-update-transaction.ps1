$CustomAppUpdateTransactionSchema = 1

function Test-CustomAppUpdateSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppUpdateCommitShaV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Get-CustomAppUpdateStringSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Get-CustomAppUpdateCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Transaction path cannot be empty.'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppUpdatePathWithinRootV010 {
    param([Parameter(Mandatory=$true)][string]$ValidationRoot,[Parameter(Mandatory=$true)][string]$Path)
    $root=Get-CustomAppUpdateCanonicalPathV010 $ValidationRoot
    $target=Get-CustomAppUpdateCanonicalPathV010 $Path
    if($target.Equals($root,[StringComparison]::OrdinalIgnoreCase)){return $false}
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    return $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-CustomAppUpdateFixturePathV010 {
    param([Parameter(Mandatory=$true)][string]$ValidationRoot,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='path')
    $root=Get-CustomAppUpdateCanonicalPathV010 $ValidationRoot
    $target=Get-CustomAppUpdateCanonicalPathV010 $Path
    if(-not (Test-Path -LiteralPath $root -PathType Container)){throw 'Fixture validation root is missing.'}
    $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Fixture validation root is a reparse point.'}
    if(-not (Test-CustomAppUpdatePathWithinRootV010 -ValidationRoot $root -Path $target)){throw "$Label escaped the fixture validation root."}
    $probe=$target
    while($probe.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and -not $probe.Equals($root,[StringComparison]::OrdinalIgnoreCase)){
        if(Test-Path -LiteralPath $probe){
            $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse-point ancestor."}
        }
        $parent=[IO.Directory]::GetParent($probe)
        if($null -eq $parent){break}
        $probe=$parent.FullName
    }
    return $target
}

function Test-CustomAppUpdatePathsOverlapV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    $aFull=Get-CustomAppUpdateCanonicalPathV010 $A;$bFull=Get-CustomAppUpdateCanonicalPathV010 $B
    if($aFull.Equals($bFull,[StringComparison]::OrdinalIgnoreCase)){return $true}
    $aPrefix=$aFull+[IO.Path]::DirectorySeparatorChar;$bPrefix=$bFull+[IO.Path]::DirectorySeparatorChar
    return ($aFull.StartsWith($bPrefix,[StringComparison]::OrdinalIgnoreCase) -or $bFull.StartsWith($aPrefix,[StringComparison]::OrdinalIgnoreCase))
}

function Get-CustomAppUpdateTreeSnapshotV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [int]$MaxFiles=20000,
        [int64]$MaxFileBytes=67108864,
        [int64]$MaxTotalBytes=268435456
    )
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){throw 'Transaction tree root is missing.'}
    $rootFull=Get-CustomAppUpdateCanonicalPathV010 $Root
    $rootItem=Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Transaction tree root is a reparse point.'}
    $rows=New-Object System.Collections.Generic.List[string]
    $entries=New-Object System.Collections.Generic.List[object]
    [int64]$total=0;$fileCount=0
    $stack=New-Object System.Collections.Generic.Stack[string];$stack.Push($rootFull)
    while($stack.Count -gt 0){
        $dir=$stack.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)){
            $full=[IO.Path]::GetFullPath($item.FullName);$prefix=$rootFull+[IO.Path]::DirectorySeparatorChar
            if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Transaction tree entry escaped root.'}
            $relative=$full.Substring($prefix.Length).Replace('\','/')
            if([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('../') -or $relative.Contains('/../')){throw 'Transaction tree relative path is unsafe.'}
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Transaction tree contains a reparse point: $relative"}
            if($item.PSIsContainer){$rows.Add('d|'+$relative.ToLowerInvariant());$entries.Add([pscustomobject]@{path=$relative;type='dir';size=0;sha256=$null});$stack.Push([string]$item.FullName);continue}
            [int64]$size=$item.Length;if($size -lt 0 -or $size -gt $MaxFileBytes){throw "Transaction file exceeds per-file limit: $relative"}
            $total+=$size;if($total -gt $MaxTotalBytes){throw 'Transaction tree exceeds total byte limit.'}
            $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$fileCount++
            if($fileCount -gt $MaxFiles){throw 'Transaction tree exceeds file-count limit.'}
            $rows.Add('f|'+$relative.ToLowerInvariant()+'|'+$size+'|'+$hash);$entries.Add([pscustomobject]@{path=$relative;type='file';size=$size;sha256=$hash})
        }
    }
    $array=[string[]]$rows.ToArray();[Array]::Sort($array,[StringComparer]::Ordinal)
    return [pscustomobject]@{schema=1;root=$rootFull;tree_sha256=(Get-CustomAppUpdateStringSha256V010 (($array -join "`n")+"`n"));file_count=$fileCount;total_bytes=$total;entries=$entries.ToArray()}
}

function Copy-CustomAppUpdateTreeFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination,[Parameter(Mandatory=$true)][string]$ValidationRoot)
    $src=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $ValidationRoot -Path $Source -Label 'source'
    $dst=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $ValidationRoot -Path $Destination -Label 'destination'
    if(Test-CustomAppUpdatePathsOverlapV010 $src $dst){throw 'Fixture copy source and destination overlap.'}
    if(-not (Test-Path -LiteralPath $src -PathType Container)){throw 'Fixture copy source is missing.'}
    if(Test-Path -LiteralPath $dst){throw 'Fixture copy destination already exists.'}
    $snapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $src
    [IO.Directory]::CreateDirectory($dst)|Out-Null
    foreach($entry in @($snapshot.entries)){
        $target=Join-Path $dst ([string]$entry.path).Replace('/',[IO.Path]::DirectorySeparatorChar)
        if([string]$entry.type -ceq 'dir'){[IO.Directory]::CreateDirectory($target)|Out-Null;continue}
        $parent=[IO.Path]::GetDirectoryName($target);if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
        $sourceFile=Join-Path $src ([string]$entry.path).Replace('/',[IO.Path]::DirectorySeparatorChar)
        [IO.File]::Copy($sourceFile,$target,$false)
    }
    $copied=Get-CustomAppUpdateTreeSnapshotV010 -Root $dst
    if([string]$copied.tree_sha256 -cne [string]$snapshot.tree_sha256){throw 'Fixture copy verification failed.'}
    return $copied
}

function Remove-CustomAppUpdateTreeFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ValidationRoot)
    $target=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $ValidationRoot -Path $Path -Label 'remove target'
    if(-not (Test-Path -LiteralPath $target)){return}
    [IO.Directory]::Delete($target,$true)
}

function Test-CustomAppUpdateDeniedAuthorityV010 {
    param([AllowNull()]$Object)
    if($null -eq $Object){return $true}
    if($Object.PSObject.Properties['mutation_mode'] -and [string]$Object.mutation_mode -cne 'deny'){return $false}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','production_mutation_authorized')){if($Object.PSObject.Properties[$name] -and [bool]$Object.PSObject.Properties[$name].Value){return $false}}
    return $true
}

function New-CustomAppUpdateDecisionV010 {
    param([bool]$Eligible,[string]$Reason,$Plan=$null)
    return [pscustomobject]@{schema=$CustomAppUpdateTransactionSchema;eligible=$Eligible;reason=$Reason;plan=$Plan;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false;fixture_apply_authorized=$Eligible}
}

function Resolve-CustomAppUpdateTransactionEligibilityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$CurrentBaseline,
        [Parameter(Mandatory=$true)]$StageBaseline,
        [Parameter(Mandatory=$true)][string]$ValidationRoot,
        [Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)][string]$BackupPath,
        [Parameter(Mandatory=$true)][string]$RollbackPath
    )
    if([string]::IsNullOrWhiteSpace($Name)){return New-CustomAppUpdateDecisionV010 $false 'name-empty'}
    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$LifecycleRow.kind -cne 'custom-app'){return New-CustomAppUpdateDecisionV010 $false 'lifecycle-owner-or-kind-mismatch'}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed){return New-CustomAppUpdateDecisionV010 $false 'user-removed-or-absent'}
    if([bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){return New-CustomAppUpdateDecisionV010 $false 'lifecycle-unsafe-or-ambiguous'}
    $livePath=[string]$LifecycleRow.locations[0]
    if([string]::IsNullOrWhiteSpace($livePath)){return New-CustomAppUpdateDecisionV010 $false 'lifecycle-path-empty'}
    if($null -eq $ProvenanceRow -or [string]$ProvenanceRow.managed_by -cne 'custom-app-provenance-v1'){return New-CustomAppUpdateDecisionV010 $false 'provenance-owner-mismatch'}
    $source=([string]$ProvenanceRow.source_identity).Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($source) -or [bool]$ProvenanceRow.source_changed -or [bool]$ProvenanceRow.requires_reenrollment -or [string]$ProvenanceRow.last_proven_source -cne $source -or -not (Test-CustomAppUpdateDeniedAuthorityV010 $ProvenanceRow)){return New-CustomAppUpdateDecisionV010 $false 'provenance-not-current-denied-or-reenrollment-required'}
    if($null -eq $BindingRow -or [string]$BindingRow.managed_by -cne 'custom-app-remote-binding-observer-v1'){return New-CustomAppUpdateDecisionV010 $false 'binding-owner-mismatch'}
    if(-not [bool]$BindingRow.active -or [bool]$BindingRow.user_removed -or [bool]$BindingRow.requires_reenrollment -or -not [bool]$BindingRow.update_observed){return New-CustomAppUpdateDecisionV010 $false 'binding-not-active-current-update'}
    if(([string]$BindingRow.source_identity).Trim().ToLowerInvariant() -cne $source -or -not (Test-CustomAppUpdateDeniedAuthorityV010 $BindingRow)){return New-CustomAppUpdateDecisionV010 $false 'binding-source-or-authority-drift'}
    if($null -eq $BindingRow.binding -or [string]$BindingRow.binding.managed_by -cne 'custom-app-remote-source-v1' -or [int]$BindingRow.binding.schema -ne 1 -or -not (Test-CustomAppUpdateDeniedAuthorityV010 $BindingRow.binding)){return New-CustomAppUpdateDecisionV010 $false 'immutable-binding-invalid'}
    if(([string]$BindingRow.binding.source_identity).Trim().ToLowerInvariant() -cne $source -or [string]$BindingRow.binding.layout_root -cne '.'){return New-CustomAppUpdateDecisionV010 $false 'immutable-binding-source-or-layout-drift'}
    if($null -eq $CurrentBaseline -or -not [bool]$CurrentBaseline.safe -or -not [bool]$CurrentBaseline.installable -or -not (Test-CustomAppUpdateSha256V010 ([string]$CurrentBaseline.tree_sha256)){return New-CustomAppUpdateDecisionV010 $false 'current-local-baseline-invalid'}
    if((Get-CustomAppUpdateCanonicalPathV010 ([string]$CurrentBaseline.path)) -cne (Get-CustomAppUpdateCanonicalPathV010 $livePath)){return New-CustomAppUpdateDecisionV010 $false 'current-local-path-mismatch'}
    if([string]$CurrentBaseline.manifest_name -cne [string]$BindingRow.binding.manifest_name){return New-CustomAppUpdateDecisionV010 $false 'current-manifest-identity-drift'}
    $currentTree=([string]$CurrentBaseline.tree_sha256).ToLowerInvariant()
    if(-not (Test-CustomAppUpdateSha256V010 ([string]$BindingRow.last_local_tree_sha256)) -or [string]$BindingRow.last_local_tree_sha256 -cne $currentTree){return New-CustomAppUpdateDecisionV010 $false 'current-local-tree-drift'}
    if(-not (Test-CustomAppUpdateSha256V010 ([string]$BindingRow.binding.last_verified_local_tree_sha256)) -or [string]$BindingRow.binding.last_verified_local_tree_sha256 -cne $currentTree){return New-CustomAppUpdateDecisionV010 $false 'binding-local-continuity-drift'}
    $remoteTree=([string]$BindingRow.last_remote_tree_sha256).ToLowerInvariant();$remoteCommit=([string]$BindingRow.last_remote_commit_sha).ToLowerInvariant()
    if(-not (Test-CustomAppUpdateSha256V010 $remoteTree) -or -not (Test-CustomAppUpdateCommitShaV010 $remoteCommit) -or $remoteTree -ceq $currentTree){return New-CustomAppUpdateDecisionV010 $false 'remote-update-identity-invalid-or-current'}
    if([string]$BindingRow.binding.last_verified_remote_tree_sha256 -cne $remoteTree -or [string]$BindingRow.binding.last_verified_commit_sha -cne $remoteCommit){return New-CustomAppUpdateDecisionV010 $false 'binding-remote-continuity-drift'}
    if($null -eq $StageBaseline -or -not [bool]$StageBaseline.safe -or -not [bool]$StageBaseline.installable -or -not (Test-CustomAppUpdateSha256V010 ([string]$StageBaseline.tree_sha256)){return New-CustomAppUpdateDecisionV010 $false 'stage-baseline-invalid'}
    if([string]$StageBaseline.tree_sha256 -cne $remoteTree){return New-CustomAppUpdateDecisionV010 $false 'stage-tree-does-not-match-verified-remote'}
    if([string]$StageBaseline.manifest_name -cne [string]$BindingRow.binding.manifest_name){return New-CustomAppUpdateDecisionV010 $false 'stage-manifest-identity-drift'}
    try{
        $root=Get-CustomAppUpdateCanonicalPathV010 $ValidationRoot
        $live=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $root -Path $livePath -Label 'live path'
        $stage=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $root -Path $StagePath -Label 'stage path'
        $backup=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $root -Path $BackupPath -Label 'backup path'
        $rollback=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $root -Path $RollbackPath -Label 'rollback path'
        if((Get-CustomAppUpdateCanonicalPathV010 ([string]$StageBaseline.path)) -cne $stage){return New-CustomAppUpdateDecisionV010 $false 'stage-path-mismatch'}
        foreach($pair in @(@($live,$stage),@($live,$backup),@($live,$rollback),@($stage,$backup),@($stage,$rollback),@($backup,$rollback))){if(Test-CustomAppUpdatePathsOverlapV010 $pair[0] $pair[1]){return New-CustomAppUpdateDecisionV010 $false 'transaction-path-overlap'}}
    }catch{return New-CustomAppUpdateDecisionV010 $false ('fixture-path-denied:'+([string]$_.Exception.Message))}
    $identityMaterial=(@($Name.ToLowerInvariant(),$source,$live,$stage,$currentTree,$remoteTree,$remoteCommit,[string]$BindingRow.binding.manifest_name,[string]$BindingRow.binding.surface_kind,[string]$BindingRow.binding.github_repo_id) -join "`n")
    $plan=[pscustomobject]@{
        schema=$CustomAppUpdateTransactionSchema;managed_by='custom-app-update-transaction-v1';transaction_id=(Get-CustomAppUpdateStringSha256V010 $identityMaterial)
        name=$Name;source_identity=$source;live_path=$live;stage_path=$stage;backup_path=$backup;rollback_path=$rollback
        expected_local_tree_sha256=$currentTree;expected_remote_tree_sha256=$remoteTree;expected_remote_commit_sha=$remoteCommit;manifest_name=[string]$BindingRow.binding.manifest_name
        surface_kind=[string]$BindingRow.binding.surface_kind;github_repo_id=[int64]$BindingRow.binding.github_repo_id
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false;fixture_apply_authorized=$true
    }
    return New-CustomAppUpdateDecisionV010 $true 'eligible-fixture-transaction-plan' $plan
}

function Test-CustomAppUpdatePersistenceProofV010 {
    param([AllowNull()]$Proof)
    if($null -eq $Proof){return [pscustomobject]@{ok=$false;reason='persistence-proof-missing'}}
    if(-not [bool]$Proof.backup_required -or -not [bool]$Proof.backup_complete){return [pscustomobject]@{ok=$false;reason='persistence-backup-incomplete'}}
    $pre=[string]$Proof.pre_snapshot_fingerprint;$post=[string]$Proof.post_snapshot_fingerprint
    if(-not (Test-CustomAppUpdateSha256V010 $pre) -or -not (Test-CustomAppUpdateSha256V010 $post)){return [pscustomobject]@{ok=$false;reason='persistence-fingerprint-invalid'}}
    if($pre -cne $post){return [pscustomobject]@{ok=$false;reason='persistence-state-changed'}}
    return [pscustomobject]@{ok=$true;reason='persistence-byte-state-preserved'}
}

function Restore-CustomAppUpdateFixtureBackupV010 {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][string]$ValidationRoot)
    if(-not (Test-Path -LiteralPath $Plan.backup_path -PathType Container)){throw 'Transaction backup is missing.'}
    $backupSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $Plan.backup_path
    if(Test-Path -LiteralPath $Plan.live_path){Remove-CustomAppUpdateTreeFixtureV010 -Path $Plan.live_path -ValidationRoot $ValidationRoot}
    [void](Copy-CustomAppUpdateTreeFixtureV010 -Source $Plan.backup_path -Destination $Plan.live_path -ValidationRoot $ValidationRoot)
    $restored=Get-CustomAppUpdateTreeSnapshotV010 -Root $Plan.live_path
    if([string]$restored.tree_sha256 -cne [string]$backupSnapshot.tree_sha256){throw 'Rollback byte-tree verification failed.'}
    return $restored
}

function Invoke-CustomAppUpdateFixtureTransactionV010 {
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$ValidationRoot,
        [Parameter(Mandatory=$true)]$PersistenceProof,
        [switch]$InjectPostApplyFailure,
        [switch]$InjectRollbackFailure
    )
    $result=[pscustomobject]@{schema=1;transaction_id=[string]$Plan.transaction_id;status='starting';committed=$false;rolled_back=$false;rollback_verified=$false;reason=$null;pre_full_tree_sha256=$null;post_full_tree_sha256=$null;backup_full_tree_sha256=$null;mutation_mode='deny';production_mutation_authorized=$false}
    try{
        if($null -eq $Plan -or [string]$Plan.managed_by -cne 'custom-app-update-transaction-v1' -or -not [bool]$Plan.fixture_apply_authorized -or -not (Test-CustomAppUpdateDeniedAuthorityV010 $Plan)){throw 'Transaction plan is not fixture-only denied-authority.'}
        $root=Get-CustomAppUpdateCanonicalPathV010 $ValidationRoot
        foreach($p in @($Plan.live_path,$Plan.stage_path,$Plan.backup_path,$Plan.rollback_path)){[void](Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $root -Path ([string]$p) -Label 'transaction path')}
        if(Test-Path -LiteralPath $Plan.backup_path){throw 'Transaction backup path already exists; replay/stale transaction denied.'}
        if(Test-Path -LiteralPath $Plan.rollback_path){throw 'Transaction rollback path already exists; interrupted transaction requires recovery.'}
        $current=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Plan.name) -AppPath ([string]$Plan.live_path)
        $stage=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Plan.name) -AppPath ([string]$Plan.stage_path)
        if([string]$current.tree_sha256 -cne [string]$Plan.expected_local_tree_sha256){throw 'Transaction plan is stale: live tree changed.'}
        if([string]$stage.tree_sha256 -cne [string]$Plan.expected_remote_tree_sha256){throw 'Transaction plan is stale: stage tree changed.'}
        if([string]$current.manifest_name -cne [string]$Plan.manifest_name -or [string]$stage.manifest_name -cne [string]$Plan.manifest_name){throw 'Transaction manifest identity changed after planning.'}
        $persistence=Test-CustomAppUpdatePersistenceProofV010 $PersistenceProof
        if(-not [bool]$persistence.ok){throw ('Persistence guard denied apply: '+[string]$persistence.reason)}
        $pre=Get-CustomAppUpdateTreeSnapshotV010 -Root $Plan.live_path;$result.pre_full_tree_sha256=[string]$pre.tree_sha256
        $backup=Copy-CustomAppUpdateTreeFixtureV010 -Source $Plan.live_path -Destination $Plan.backup_path -ValidationRoot $root;$result.backup_full_tree_sha256=[string]$backup.tree_sha256
        if([string]$backup.tree_sha256 -cne [string]$pre.tree_sha256){throw 'Pre-apply backup does not exactly match live tree.'}
        [IO.Directory]::Move([string]$Plan.live_path,[string]$Plan.rollback_path)
        try{
            [void](Copy-CustomAppUpdateTreeFixtureV010 -Source $Plan.stage_path -Destination $Plan.live_path -ValidationRoot $root)
            $postBaseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Plan.name) -AppPath ([string]$Plan.live_path)
            if([string]$postBaseline.tree_sha256 -cne [string]$Plan.expected_remote_tree_sha256){throw 'Applied runtime tree does not match the verified remote tree.'}
            if($InjectPostApplyFailure){throw 'Injected post-apply verification failure.'}
            $post=Get-CustomAppUpdateTreeSnapshotV010 -Root $Plan.live_path;$result.post_full_tree_sha256=[string]$post.tree_sha256
            $persistenceAfter=Test-CustomAppUpdatePersistenceProofV010 $PersistenceProof
            if(-not [bool]$persistenceAfter.ok){throw ('Persistence verification failed after apply: '+[string]$persistenceAfter.reason)}
            Remove-CustomAppUpdateTreeFixtureV010 -Path $Plan.rollback_path -ValidationRoot $root
            $result.status='committed';$result.committed=$true;$result.reason='fixture-apply-and-verification-complete'
            return $result
        }catch{
            $failure=[string]$_.Exception.Message
            if($InjectRollbackFailure){$result.status='rollback-failed';$result.reason=$failure+'; injected rollback failure';return $result}
            if(Test-Path -LiteralPath $Plan.live_path){Remove-CustomAppUpdateTreeFixtureV010 -Path $Plan.live_path -ValidationRoot $root}
            if(Test-Path -LiteralPath $Plan.rollback_path){[IO.Directory]::Move([string]$Plan.rollback_path,[string]$Plan.live_path)}
            else{[void](Restore-CustomAppUpdateFixtureBackupV010 -Plan $Plan -ValidationRoot $root)}
            $restored=Get-CustomAppUpdateTreeSnapshotV010 -Root $Plan.live_path
            if([string]$restored.tree_sha256 -cne [string]$pre.tree_sha256){$result.status='rollback-failed';$result.reason=$failure+'; rollback tree mismatch';return $result}
            $result.status='rolled-back';$result.rolled_back=$true;$result.rollback_verified=$true;$result.reason=$failure;$result.post_full_tree_sha256=[string]$restored.tree_sha256
            return $result
        }
    }catch{
        $result.status='denied-before-apply';$result.reason=[string]$_.Exception.Message
        return $result
    }
}
