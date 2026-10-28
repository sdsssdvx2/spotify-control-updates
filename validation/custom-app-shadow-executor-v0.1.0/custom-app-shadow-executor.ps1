$CustomAppShadowExecutorSchema = 1
$CustomAppShadowExecutorManagedBy = 'custom-app-shadow-executor-v1'

function Test-CustomAppShadowPathWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Test-CustomAppShadowFreshProvenanceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow
    )
    $nameKey=$Name.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey)){return [pscustomobject]@{ok=$false;reason='name-empty'}}
    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$LifecycleRow.kind -cne 'custom-app'){return [pscustomobject]@{ok=$false;reason='lifecycle-owner-or-kind-mismatch'}}
    if($LifecycleRow.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$LifecycleRow.name) -and ([string]$LifecycleRow.name).Trim().ToLowerInvariant() -cne $nameKey){return [pscustomobject]@{ok=$false;reason='lifecycle-name-mismatch'}}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){return [pscustomobject]@{ok=$false;reason='lifecycle-not-current-safe-single-path'}}
    $live=[IO.Path]::GetFullPath([string]$LifecycleRow.locations[0])
    $shadowRoot=Get-CustomAppStageWorkspaceRootV010
    if(-not (Test-CustomAppShadowPathWithinV010 -Root $shadowRoot -Path $live)){return [pscustomobject]@{ok=$false;reason='shadow-live-path-outside-dedicated-fixture-root'}}
    if(-not (Test-Path -LiteralPath $live -PathType Container)){return [pscustomobject]@{ok=$false;reason='shadow-live-path-missing'}}
    $liveItem=Get-Item -LiteralPath $live -Force -ErrorAction Stop
    if(($liveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return [pscustomobject]@{ok=$false;reason='shadow-live-root-reparse'}}

    if($null -eq $ProvenanceRow -or [string]$ProvenanceRow.managed_by -cne 'custom-app-provenance-v1'){return [pscustomobject]@{ok=$false;reason='provenance-owner-mismatch'}}
    if($ProvenanceRow.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$ProvenanceRow.name) -and ([string]$ProvenanceRow.name).Trim().ToLowerInvariant() -cne $nameKey){return [pscustomobject]@{ok=$false;reason='provenance-name-mismatch'}}
    $provAuthority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $ProvenanceRow -Label 'provenance-row'
    if(-not [bool]$provAuthority.ok){return [pscustomobject]@{ok=$false;reason=[string]$provAuthority.reason}}
    $source=([string]$ProvenanceRow.source_identity).Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($source) -or [bool]$ProvenanceRow.source_changed -or [bool]$ProvenanceRow.requires_reenrollment -or ([string]$ProvenanceRow.last_proven_source).Trim().ToLowerInvariant() -cne $source){return [pscustomobject]@{ok=$false;reason='provenance-not-current-or-reenrollment-required'}}
    $storedFingerprint=([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppStageSha256V010 $storedFingerprint)){return [pscustomobject]@{ok=$false;reason='provenance-stored-fingerprint-invalid'}}

    $bindingCheck=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$bindingCheck.ok){return [pscustomobject]@{ok=$false;reason=('binding-denied:'+[string]$bindingCheck.reason)}}
    if([string]$bindingCheck.source -cne $source){return [pscustomobject]@{ok=$false;reason='binding-source-does-not-match-provenance'}}

    $fresh=Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath $live
    if(-not [bool]$fresh.source_proven -or [bool]$fresh.requires_reenrollment){return [pscustomobject]@{ok=$false;reason=('fresh-provenance-not-strong:'+[string]$fresh.status)}}
    if(([string]$fresh.source_candidate).Trim().ToLowerInvariant() -cne $source){return [pscustomobject]@{ok=$false;reason='fresh-provenance-source-drift'}}
    if(([string]$fresh.evidence_fingerprint).Trim().ToLowerInvariant() -cne $storedFingerprint){return [pscustomobject]@{ok=$false;reason='fresh-provenance-fingerprint-drift'}}
    if([IO.Path]::GetFullPath([string]$fresh.path) -cne $live){return [pscustomobject]@{ok=$false;reason='fresh-provenance-path-drift'}}
    return [pscustomobject]@{
        ok=$true;reason='fresh-provenance-and-binding-continuity-proven';name=$Name;source_identity=$source;live_path=$live
        evidence_fingerprint=$storedFingerprint;binding_fingerprint=[string]$bindingCheck.binding_fingerprint
        remote_tree_sha256=[string]$bindingCheck.remote_tree_sha256;remote_commit_sha=[string]$bindingCheck.commit_sha
        manifest_name=[string]$bindingCheck.manifest_name;fresh_evidence=$fresh;binding_check=$bindingCheck
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
}

function New-CustomAppShadowPersistenceSessionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$BackupRoot
    )
    foreach($root in @($LocalAppDataRoot,$AppDataRoot,$BackupRoot)){if([string]::IsNullOrWhiteSpace($root)){throw 'Shadow persistence root is empty.'}}
    if(-not (Test-Path -LiteralPath $LocalAppDataRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $LocalAppDataRoot|Out-Null}
    if(-not (Test-Path -LiteralPath $AppDataRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $AppDataRoot|Out-Null}
    if(-not (Test-Path -LiteralPath $BackupRoot -PathType Container)){New-Item -ItemType Directory -Force -Path $BackupRoot|Out-Null}
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

function New-CustomAppShadowTransactionPersistenceProofV010 {
    param([Parameter(Mandatory=$true)]$Session)
    $authority=Test-CustomAppStageStrictDeniedAuthorityV010 -Object $Session -Label 'shadow-persistence-session'
    if(-not [bool]$authority.ok -or -not [bool]$Session.backup_complete){throw 'Shadow persistence session is not complete denied-authority evidence.'}
    $current=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$Session.local_root) -AppDataRoot ([string]$Session.app_root)
    if([string]$current.fingerprint -cne [string]$Session.pre_fingerprint){throw 'Persistence drifted after backup and before transaction apply.'}
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-preapply-persistence-proof-v1';backup_required=$true;backup_complete=$true
        pre_snapshot_fingerprint=[string]$Session.pre_fingerprint;post_snapshot_fingerprint=[string]$current.fingerprint
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
}

function Restore-CustomAppShadowAfterPersistenceDriftV010 {
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$ValidationRoot,
        [Parameter(Mandatory=$true)]$PersistenceSession,
        [Parameter(Mandatory=$true)][string]$ExpectedOriginalRuntimeTree
    )
    $restoredApp=Restore-CustomAppUpdateFixtureBackupV010 -Plan $Plan -ValidationRoot $ValidationRoot
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Plan.name) -AppPath ([string]$Plan.live_path)
    if([string]$baseline.tree_sha256 -cne $ExpectedOriginalRuntimeTree){throw 'Shadow emergency app rollback did not restore original runtime tree.'}
    $restoredPersistence=Restore-SpotifyPersistenceBackup -BackupPath ([string]$PersistenceSession.backup_path) -LocalAppDataRoot ([string]$PersistenceSession.local_root) -AppDataRoot ([string]$PersistenceSession.app_root)
    if([string]$restoredPersistence.fingerprint -cne [string]$PersistenceSession.pre_fingerprint){throw 'Shadow emergency persistence rollback did not restore exact pre-update fingerprint.'}
    return [pscustomobject]@{app=$restoredApp;baseline=$baseline;persistence=$restoredPersistence}
}

function Remove-CustomAppShadowPersistenceBackupV010 {
    param([Parameter(Mandatory=$true)]$Session)
    $root=[IO.Path]::GetFullPath([string]$Session.backup_root)
    $path=[IO.Path]::GetFullPath([string]$Session.backup_path)
    if(-not (Test-CustomAppShadowPathWithinV010 -Root $root -Path $path)){throw 'Shadow persistence cleanup escaped backup root.'}
    if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop}
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
        fresh_provenance_fingerprint=$null;binding_fingerprint=$null;stage_tree_sha256=$null;transaction_id=$null;pre_persistence_fingerprint=$null;post_persistence_fingerprint=$null
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
            $result.status='rolled-back-shadow-fixture';$result.reason=[string]$tx.reason;$result.rolled_back=$true;$result.post_persistence_fingerprint=[string]$afterRollback.fingerprint
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
        $postProv=Get-CustomAppLocalProvenanceEvidence -Name $Name -AppPath ([string]$plan.live_path)
        if(-not [bool]$postProv.source_proven -or ([string]$postProv.source_candidate).Trim().ToLowerInvariant() -cne [string]$fresh1.source_identity -or [string]$postProv.evidence_fingerprint -cne [string]$fresh1.evidence_fingerprint){
            [void](Restore-CustomAppShadowAfterPersistenceDriftV010 -Plan $plan -ValidationRoot $validationRoot -PersistenceSession $session -ExpectedOriginalRuntimeTree ([string]$current.tree_sha256))
            $result.status='rolled-back-after-provenance-drift';$result.reason='post-apply-local-provenance-drift';$result.rolled_back=$true
            if(Test-Path -LiteralPath $plan.backup_path){Remove-CustomAppUpdateTreeFixtureV010 -Path ([string]$plan.backup_path) -ValidationRoot $validationRoot}
            return $result
        }
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

function Invoke-CustomAppShadowExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [switch]$InjectTransactionPostApplyFailure,
        [switch]$InjectPersistenceDriftAfterApply,
        [AllowNull()][string]$PersistenceDriftTarget=$null
    )
    $pre=Test-CustomAppShadowFreshProvenanceV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow
    if(-not [bool]$pre.ok){return [pscustomobject]@{schema=$CustomAppShadowExecutorSchema;managed_by=$CustomAppShadowExecutorManagedBy;name=$Name;status='denied-before-acquisition';reason=[string]$pre.reason;committed=$false;rolled_back=$false;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false}}
    $stage=$null
    try{
        $stage=Invoke-CustomAppStageAcquisitionV010 -Name $Name -BindingRow $BindingRow
        return Invoke-CustomAppShadowWithAcquiredStageV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $stage -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -PersistenceBackupRoot $PersistenceBackupRoot -InjectTransactionPostApplyFailure:$InjectTransactionPostApplyFailure -InjectPersistenceDriftAfterApply:$InjectPersistenceDriftAfterApply -PersistenceDriftTarget $PersistenceDriftTarget
    }catch{
        if($null -ne $stage -and $stage.PSObject.Properties['workspace_path']){try{Remove-CustomAppStageWorkspaceV010 -Path ([string]$stage.workspace_path)}catch{}}
        return [pscustomobject]@{schema=$CustomAppShadowExecutorSchema;managed_by=$CustomAppShadowExecutorManagedBy;name=$Name;status='denied-or-failed-shadow';reason=[string]$_.Exception.Message;committed=$false;rolled_back=$false;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false}
    }
}
