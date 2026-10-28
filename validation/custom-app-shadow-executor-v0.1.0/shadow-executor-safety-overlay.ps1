function New-CustomAppShadowPersistenceSessionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$BackupRoot
    )
    $shadowRoot=Get-CustomAppStageWorkspaceRootV010
    foreach($root in @($LocalAppDataRoot,$AppDataRoot,$BackupRoot)){
        if([string]::IsNullOrWhiteSpace($root)){throw 'Shadow persistence root is empty.'}
        if(-not (Test-CustomAppShadowPathWithinV010 -Root $shadowRoot -Path $root)){throw 'Shadow persistence roots must stay inside the dedicated fixture root.'}
    }
    if(-not (Test-Path -LiteralPath $LocalAppDataRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $LocalAppDataRoot|Out-Null}
    if(-not (Test-Path -LiteralPath $AppDataRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $AppDataRoot|Out-Null}
    if(-not (Test-Path -LiteralPath $BackupRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $BackupRoot|Out-Null}
    foreach($root in @($LocalAppDataRoot,$AppDataRoot,$BackupRoot)){
        $item=Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Shadow persistence root is a reparse point.'}
    }
    $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    $guard=New-RequiredSpotifyPersistenceBackup -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -BackupRootOverride $BackupRoot
    if([string]$guard.fingerprint -cne [string]$before.fingerprint){throw 'Shadow persistence backup did not pin exact pre-transaction fingerprint.'}
    $verify=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if([string]$verify.fingerprint -cne [string]$before.fingerprint){throw 'Persistence changed while creating shadow backup.'}
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-persistence-v1';local_root=[IO.Path]::GetFullPath($LocalAppDataRoot);app_root=[IO.Path]::GetFullPath($AppDataRoot)
        backup_root=[IO.Path]::GetFullPath($BackupRoot);backup_path=[IO.Path]::GetFullPath([string]$guard.path);pre_snapshot=$before;pre_fingerprint=[string]$before.fingerprint
        backup_complete=$true;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppShadowPostApplyProvenanceContinuityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LivePath,
        [Parameter(Mandatory=$true)]$FreshBefore
    )
    $post=Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath $LivePath
    if(-not [bool]$post.source_proven -or [bool]$post.requires_reenrollment){return [pscustomobject]@{ok=$false;reason=('post-provenance-not-strong:'+[string]$post.status);evidence=$post}}
    if(([string]$post.source_candidate).Trim().ToLowerInvariant() -cne ([string]$FreshBefore.source_identity).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='post-provenance-source-drift';evidence=$post}}
    $preGit=$FreshBefore.fresh_evidence.git;$postGit=$post.git
    if($null -eq $preGit -or $null -eq $postGit -or -not [bool]$preGit.safe -or -not [bool]$postGit.safe){return [pscustomobject]@{ok=$false;reason='post-provenance-git-proof-missing-or-unsafe';evidence=$post}}
    if([string]$preGit.file_sha256 -cne [string]$postGit.file_sha256){return [pscustomobject]@{ok=$false;reason='post-provenance-git-config-byte-drift';evidence=$post}}
    if($null -eq $postGit.claim -or -not [bool]$postGit.claim.ok -or -not [bool]$postGit.claim.secure -or ([string]$postGit.claim.identity).Trim().ToLowerInvariant() -cne ([string]$FreshBefore.source_identity).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='post-provenance-git-origin-drift';evidence=$post}}
    if($null -ne $post.package -and $null -ne $post.package.claim -and [bool]$post.package.claim.ok -and ([string]$post.package.claim.identity).Trim().ToLowerInvariant() -cne ([string]$FreshBefore.source_identity).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='post-provenance-package-source-conflict';evidence=$post}}
    return [pscustomobject]@{ok=$true;reason='post-provenance-strong-origin-continuity-proven';evidence=$post}
}

function Invoke-CustomAppShadowWithAcquiredStageV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [switch]$InjectTransactionPostApplyFailure,
        [switch]$InjectPersistenceDriftAfterApply,
        [AllowNull()][string]$PersistenceDriftTarget=$null
    )
    $result=[pscustomobject]@{
        schema=$CustomAppShadowExecutorSchema;managed_by=$CustomAppShadowExecutorManagedBy;name=$Name;status='starting';reason=$null;committed=$false;rolled_back=$false
        fresh_provenance_fingerprint=$null;post_provenance_fingerprint=$null;binding_fingerprint=$null;stage_tree_sha256=$null;transaction_id=$null;pre_persistence_fingerprint=$null;post_persistence_fingerprint=$null
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $session=$null;$plan=$null
    try{
        $fresh1=Test-CustomAppShadowFreshProvenanceV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow
        if(-not [bool]$fresh1.ok){throw ('Initial fresh provenance denied shadow execution: '+[string]$fresh1.reason)}
        $result.fresh_provenance_fingerprint=[string]$fresh1.evidence_fingerprint;$result.binding_fingerprint=[string]$fresh1.binding_fingerprint
        $stageAuthority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $StageResult -Label 'stage-result'
        if(-not [bool]$stageAuthority.ok -or [string]$StageResult.status -cne 'staged-verified'){throw 'Shadow stage result is not verified strict-deny evidence.'}
        if([string]$StageResult.source_identity -cne [string]$fresh1.source_identity -or [string]$StageResult.remote_tree_sha256 -cne [string]$fresh1.remote_tree_sha256 -or [string]$StageResult.commit_sha -cne [string]$fresh1.remote_commit_sha -or [string]$StageResult.binding_fingerprint -cne [string]$fresh1.binding_fingerprint){throw 'Shadow stage result is not cryptographically bound to the fresh local provenance/binding decision.'}
        if([string]$StageResult.stage_baseline.tree_sha256 -cne [string]$fresh1.remote_tree_sha256 -or [string]$StageResult.stage_baseline.manifest_name -cne [string]$fresh1.manifest_name){throw 'Shadow acquired stage baseline drifted from binding.'}
        $result.stage_tree_sha256=[string]$StageResult.stage_baseline.tree_sha256

        $fresh2=Test-CustomAppShadowFreshProvenanceV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow
        if(-not [bool]$fresh2.ok -or [string]$fresh2.evidence_fingerprint -cne [string]$fresh1.evidence_fingerprint -or [string]$fresh2.binding_fingerprint -cne [string]$fresh1.binding_fingerprint){throw 'Local provenance or binding changed during remote stage acquisition.'}
        $current=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$fresh2.live_path)
        if(-not [bool]$current.safe -or -not [bool]$current.installable){throw 'Current shadow live runtime baseline is unsafe or not installable.'}
        $validationRoot=Get-CustomAppStageWorkspaceRootV010
        $txRoot=Join-Path $validationRoot ('shadow-tx-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $txRoot|Out-Null
        $backup=Join-Path $txRoot 'backup';$rollback=Join-Path $txRoot 'rollback'
        $decision=Resolve-CustomAppUpdateTransactionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $current -StageBaseline $StageResult.stage_baseline -ValidationRoot $validationRoot -StagePath ([string]$StageResult.stage_path) -BackupPath $backup -RollbackPath $rollback
        if(-not [bool]$decision.eligible -or $null -eq $decision.plan){throw ('Shadow transaction eligibility denied: '+[string]$decision.reason)}
        $plan=$decision.plan;$result.transaction_id=[string]$plan.transaction_id
        $planAuthority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $plan -Label 'transaction-plan'
        if(-not [bool]$planAuthority.ok -or -not [bool]$plan.fixture_apply_authorized){throw 'Shadow transaction plan authority schema is not explicit fixture-only deny.'}
        if([string]$plan.source_identity -cne [string]$fresh2.source_identity -or [string]$plan.expected_remote_tree_sha256 -cne [string]$StageResult.stage_baseline.tree_sha256 -or [string]$plan.expected_remote_commit_sha -cne [string]$StageResult.commit_sha){throw 'Shadow transaction plan is not bound to acquired stage identity.'}

        $session=New-CustomAppShadowPersistenceSessionV010 -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -BackupRoot $PersistenceBackupRoot
        $result.pre_persistence_fingerprint=[string]$session.pre_fingerprint
        $proof=New-CustomAppShadowTransactionPersistenceProofV010 -Session $session
        $tx=Invoke-CustomAppUpdateFixtureTransactionV010 -Plan $plan -ValidationRoot $validationRoot -PersistenceProof $proof -InjectPostApplyFailure:$InjectTransactionPostApplyFailure
        if([string]$tx.status -eq 'rolled-back'){
            $afterRollback=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
            if([string]$afterRollback.fingerprint -cne [string]$session.pre_fingerprint){throw 'Persistence changed during transaction rollback path.'}
            $freshRollback=Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath ([string]$plan.live_path)
            if([string]$freshRollback.evidence_fingerprint -cne [string]$fresh1.evidence_fingerprint){throw 'Local provenance changed across transaction rollback.'}
            $result.status='rolled-back-shadow-fixture';$result.reason=[string]$tx.reason;$result.rolled_back=$true;$result.post_persistence_fingerprint=[string]$afterRollback.fingerprint;$result.post_provenance_fingerprint=[string]$freshRollback.evidence_fingerprint
            if(Test-Path -LiteralPath $plan.backup_path){Remove-CustomAppUpdateTreeFixtureV010 -Path ([string]$plan.backup_path) -ValidationRoot $validationRoot}
            return $result
        }
        if([string]$tx.status -ne 'committed' -or -not [bool]$tx.committed){throw ('Shadow fixture transaction did not commit or verify: '+[string]$tx.status+' / '+[string]$tx.reason)}

        if($InjectPersistenceDriftAfterApply){
            if([string]::IsNullOrWhiteSpace($PersistenceDriftTarget)){throw 'Persistence drift injection requested without target.'}
            $target=[IO.Path]::GetFullPath($PersistenceDriftTarget);$local=[IO.Path]::GetFullPath($LocalAppDataRoot);$app=[IO.Path]::GetFullPath($AppDataRoot)
            if(-not ((Test-CustomAppShadowPathWithinV010 -Root $local -Path $target) -or (Test-CustomAppShadowPathWithinV010 -Root $app -Path $target))){throw 'Persistence drift injection target escaped fixture persistence roots.'}
            if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'Persistence drift injection target is missing.'}
            [IO.File]::AppendAllText($target,'shadow-persistence-drift',[Text.UTF8Encoding]::new($false))
        }
        $post=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot;$result.post_persistence_fingerprint=[string]$post.fingerprint
        if([string]$post.fingerprint -cne [string]$session.pre_fingerprint){
            [void](Restore-CustomAppShadowAfterPersistenceDriftV010 -Plan $plan -ValidationRoot $validationRoot -PersistenceSession $session -ExpectedOriginalRuntimeTree ([string]$current.tree_sha256))
            $result.status='rolled-back-after-persistence-drift';$result.reason='actual-post-apply-persistence-fingerprint-drift';$result.rolled_back=$true;$result.post_persistence_fingerprint=[string]$session.pre_fingerprint
            if(Test-Path -LiteralPath $plan.backup_path){Remove-CustomAppUpdateTreeFixtureV010 -Path ([string]$plan.backup_path) -ValidationRoot $validationRoot}
            return $result
        }
        $postProv=Test-CustomAppShadowPostApplyProvenanceContinuityV010 -Name $Name -LivePath ([string]$plan.live_path) -FreshBefore $fresh1
        if(-not [bool]$postProv.ok){
            [void](Restore-CustomAppShadowAfterPersistenceDriftV010 -Plan $plan -ValidationRoot $validationRoot -PersistenceSession $session -ExpectedOriginalRuntimeTree ([string]$current.tree_sha256))
            $result.status='rolled-back-after-provenance-drift';$result.reason=[string]$postProv.reason;$result.rolled_back=$true
            if(Test-Path -LiteralPath $plan.backup_path){Remove-CustomAppUpdateTreeFixtureV010 -Path ([string]$plan.backup_path) -ValidationRoot $validationRoot}
            return $result
        }
        $result.post_provenance_fingerprint=[string]$postProv.evidence.evidence_fingerprint
        if(Test-Path -LiteralPath $plan.backup_path){Remove-CustomAppUpdateTreeFixtureV010 -Path ([string]$plan.backup_path) -ValidationRoot $validationRoot}
        $result.status='committed-shadow-fixture';$result.reason='fresh-provenance-stage-transaction-persistence-all-verified';$result.committed=$true
        return $result
    }catch{
        $result.status='denied-or-failed-shadow';$result.reason=[string]$_.Exception.Message
        return $result
    }finally{
        if($null -ne $session){try{Remove-CustomAppShadowPersistenceBackupV010 -Session $session}catch{}}
        if($null -ne $StageResult -and $StageResult.PSObject.Properties['workspace_path'] -and -not [string]::IsNullOrWhiteSpace([string]$StageResult.workspace_path)){try{if(Test-Path -LiteralPath ([string]$StageResult.workspace_path)){Remove-CustomAppStageWorkspaceV010 -Path ([string]$StageResult.workspace_path)}}catch{}}
        if($null -ne $plan){try{$txDir=Split-Path -Parent ([string]$plan.backup_path);if(Test-Path -LiteralPath $txDir){Remove-Item -LiteralPath $txDir -Recurse -Force -ErrorAction Stop}}catch{}}
    }
}
