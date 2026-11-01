$CustomAppProductionAtomicLiveSwapMutationSchema = 1
$CustomAppProductionAtomicLiveSwapMutationManagedBy = 'custom-app-production-atomic-live-swap-mutation-v1'
$CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicHead = '574fe182168271fa3497d58e269e9af1f60d9033'
$CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicCoreBlob = 'e91fa6a125f77352907c1119f6d9f47be9682550'

function Get-CustomAppProductionAtomicLiveSwapMutationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionAtomicLiveSwapMutationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function for bounded faults.
}

function New-CustomAppProductionAtomicLiveSwapMutationDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$MutationStarted=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,[AllowNull()]$RollbackResult=$null,[AllowNull()][string]$TransactionRoot=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;mutation_started=$MutationStarted;rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$RollbackResult;transaction_root=$TransactionRoot
        live_code_swap_performed=$false;caller_admission_is_authority=$false;result_is_authority=$false;requires_fresh_caller_admission=$true;requires_cleanup_if_not_promoted=$true
        spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionAtomicLiveSwapMutationResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_atomic_head,[string]$Result.qualified_atomic_core_blob,[string]$Result.status,
        [string]$Result.name,[string]$Result.caller_admission_managed_by,[string]$Result.caller_admission_fingerprint,
        [string]$Result.live_path,[string]$Result.stage_path,[string]$Result.transaction_root,[string]$Result.old_live_path,
        [string]$Result.pre_live_runtime_tree_sha256,[string]$Result.pre_live_full_tree_sha256,[string]$Result.pre_stage_runtime_tree_sha256,[string]$Result.old_live_tree_sha256,
        [string]$Result.post_runtime_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.mutated_at,[string]$Result.live_code_swap_performed,[string]$Result.transaction_workspace_retained,[string]$Result.requires_transaction_workspace_cleanup,
        [string]$Result.requires_spicetify_apply_phase,[string]$Result.caller_admission_is_authority,[string]$Result.result_is_authority,[string]$Result.requires_fresh_caller_admission,
        [string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionAtomicLiveSwapMutationResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-null'}}
    foreach($f in @('schema','managed_by','qualified_atomic_head','qualified_atomic_core_blob','status','name','caller_admission_managed_by','caller_admission_fingerprint','live_path','stage_path','transaction_root','old_live_path','pre_live_runtime_tree_sha256','pre_live_full_tree_sha256','pre_stage_runtime_tree_sha256','old_live_tree_sha256','post_runtime_tree_sha256','persistence_fingerprint','mutated_at','live_code_swap_performed','transaction_workspace_retained','requires_transaction_workspace_cleanup','requires_spicetify_apply_phase','caller_admission_is_authority','result_is_authority','requires_fresh_caller_admission','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint')){
        if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('atomic-mutation-result-field-missing-'+$f)}}
    }
    if([int]$Result.schema -ne $CustomAppProductionAtomicLiveSwapMutationSchema -or [string]$Result.managed_by -cne $CustomAppProductionAtomicLiveSwapMutationManagedBy -or [string]$Result.qualified_atomic_head -cne $CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicHead -or [string]$Result.qualified_atomic_core_blob -cne $CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicCoreBlob -or [string]$Result.status -cne 'atomic-live-swap-mutation-verified-no-future-authority'){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-owner-schema-lineage-status-invalid'}}
    if([string]::IsNullOrWhiteSpace([string]$Result.name) -or [string]::IsNullOrWhiteSpace([string]$Result.caller_admission_managed_by)){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-name-or-caller-invalid'}}
    foreach($f in @('caller_admission_fingerprint','pre_live_runtime_tree_sha256','pre_live_full_tree_sha256','pre_stage_runtime_tree_sha256','old_live_tree_sha256','post_runtime_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionAtomicLiveSwapMutationSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('atomic-mutation-result-invalid-'+$f)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionAtomicLiveSwapMutationSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-invalid-preserved-git-tree'}}
    $at=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Result.mutated_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-time-invalid'}}
    if(-not [bool]$Result.live_code_swap_performed -or -not [bool]$Result.transaction_workspace_retained -or -not [bool]$Result.requires_transaction_workspace_cleanup -or -not [bool]$Result.requires_spicetify_apply_phase -or -not [bool]$Result.requires_fresh_caller_admission){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-lifecycle-contract-invalid'}}
    foreach($f in @('caller_admission_is_authority','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('atomic-mutation-result-authority-escaped-'+$f)}}}
    try{
        $live=Get-CustomAppAtomicCanonicalPathV010 -Path ([string]$Result.live_path);$txn=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$Result.transaction_root) -Label 'mutation-result-transaction-root';$old=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$Result.old_live_path) -Label 'mutation-result-old-live'
        if(-not (Get-CustomAppAtomicCanonicalPathV010 -Path (Join-Path $txn 'old-live')).Equals($old,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-old-live-path-mismatch'}}
        if(-not (Test-Path -LiteralPath $live -PathType Container)){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-live-missing'}}
    }catch{return [pscustomobject]@{ok=$false;reason=('atomic-mutation-result-path-invalid:'+[string]$_.Exception.Message)}}
    $expected=Get-CustomAppProductionAtomicLiveSwapMutationSha256V010 (Get-CustomAppProductionAtomicLiveSwapMutationResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='atomic-mutation-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='atomic-mutation-result-valid-no-future-authority';result_fingerprint=$expected}
}

function Invoke-CustomAppProductionAtomicLiveSwapMutationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$CallerAdmissionManagedBy,[Parameter(Mandatory=$true)][string]$CallerAdmissionFingerprint,
        [Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,
        [Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$AppBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[bool]$MutationStarted=$false,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$RollbackResult=$null,[string]$TransactionRoot=$null) New-CustomAppProductionAtomicLiveSwapMutationDeniedV010 -Reason $Reason -MutationStarted $MutationStarted -RollbackAttempted $RollbackAttempted -RollbackOk $RollbackOk -RollbackResult $RollbackResult -TransactionRoot $TransactionRoot}
    if([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($CallerAdmissionManagedBy)){return & $deny 'atomic-mutation-name-or-caller-empty'}
    foreach($v in @($CallerAdmissionFingerprint,$ExpectedLiveRuntimeTreeSha256,$ExpectedLiveFullTreeSha256,$ExpectedStageRuntimeTreeSha256,$ExpectedAppBackupTreeSha256,$ExpectedPersistenceFingerprint)){if(-not (Test-CustomAppProductionAtomicLiveSwapMutationSha256V010 (([string]$v).Trim().ToLowerInvariant()))){return & $deny 'atomic-mutation-sha-input-invalid'}}
    if($ExpectedLiveFullFileCount -lt 1 -or $ExpectedLiveFullTotalBytes -lt 1 -or $ExpectedAppBackupFileCount -lt 1 -or $ExpectedAppBackupTotalBytes -lt 1){return & $deny 'atomic-mutation-count-or-byte-input-invalid'}
    if($ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -cne $ExpectedAppBackupTreeSha256.Trim().ToLowerInvariant() -or $ExpectedLiveFullFileCount -ne $ExpectedAppBackupFileCount -or $ExpectedLiveFullTotalBytes -ne $ExpectedAppBackupTotalBytes){return & $deny 'atomic-mutation-live-backup-contract-mismatch'}

    try{
        $live=Assert-CustomAppAtomicSafeDirectoryV010 -Path $LivePath -Label 'mutation-live';$parent=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([IO.Path]::GetDirectoryName($live)) -Label 'mutation-live-parent'
        $stage=Assert-CustomAppAtomicSafeDirectoryV010 -Path $StagePath -Label 'mutation-stage';$backup=Assert-CustomAppAtomicSafeDirectoryV010 -Path $AppBackupPath -Label 'mutation-app-backup'
        if(Test-CustomAppAtomicPathsOverlapV010 -A $live -B $stage){return & $deny 'atomic-mutation-live-stage-overlap'}
        if(Test-CustomAppAtomicPathsOverlapV010 -A $live -B $backup){return & $deny 'atomic-mutation-live-backup-overlap'}
        if(Test-CustomAppAtomicPathsOverlapV010 -A $live -B $PersistenceBackupPath){return & $deny 'atomic-mutation-live-persistence-backup-overlap'}
    }catch{return & $deny ('atomic-mutation-path-precondition-failed:'+[string]$_.Exception.Message)}

    try{$liveRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live}catch{return & $deny ('atomic-mutation-live-runtime-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$liveRuntime.safe -or -not [bool]$liveRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveRuntime) -or ([string]$liveRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveRuntimeTreeSha256.Trim().ToLowerInvariant()){return & $deny 'atomic-mutation-live-runtime-mismatch'}
    try{$fullLive=Get-CustomAppUpdateTreeSnapshotV010 -Root $live}catch{return & $deny ('atomic-mutation-live-full-tree-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$fullLive.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$fullLive.file_count -ne $ExpectedLiveFullFileCount -or [int64]$fullLive.total_bytes -ne $ExpectedLiveFullTotalBytes){return & $deny 'atomic-mutation-live-full-tree-mismatch'}
    try{$backupSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $backup}catch{return & $deny ('atomic-mutation-app-backup-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$backupSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedAppBackupTreeSha256.Trim().ToLowerInvariant() -or [int]$backupSnapshot.file_count -ne $ExpectedAppBackupFileCount -or [int64]$backupSnapshot.total_bytes -ne $ExpectedAppBackupTotalBytes){return & $deny 'atomic-mutation-app-backup-mismatch'}
    try{$stageRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage}catch{return & $deny ('atomic-mutation-stage-runtime-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$stageRuntime.safe -or -not [bool]$stageRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stageRuntime) -or ([string]$stageRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){return & $deny 'atomic-mutation-stage-runtime-mismatch'}
    if(Test-Path -LiteralPath (Join-Path $stage '.git')){return & $deny 'atomic-mutation-stage-vcs-metadata-forbidden'}
    try{$gitSnapshot=Get-CustomAppAtomicGitSnapshotV010 -LivePath $live}catch{return & $deny ('atomic-mutation-live-git-read-failed:'+[string]$_.Exception.Message)}
    $persistenceBackupCheck=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $PersistenceBackupPath -ExpectedFingerprint $ExpectedPersistenceFingerprint
    if(-not [bool]$persistenceBackupCheck.ok){return & $deny ('atomic-mutation-persistence-backup-invalid:'+[string]$persistenceBackupCheck.reason)}
    try{$persistenceBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('atomic-mutation-persistence-read-failed:'+[string]$_.Exception.Message)}
    if(([string]$persistenceBefore.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){return & $deny 'atomic-mutation-protected-persistence-drift-before-swap'}

    $transactionRoot=Join-Path $parent ('.spotify-control-txn-'+[Guid]::NewGuid().ToString('N'));$candidatePath=Join-Path $transactionRoot 'candidate';$oldLivePath=Join-Path $transactionRoot 'old-live'
    if(Test-Path -LiteralPath $transactionRoot){return & $deny 'atomic-mutation-transaction-root-collision'}
    [IO.Directory]::CreateDirectory($transactionRoot)|Out-Null
    $transactionItem=Get-Item -LiteralPath $transactionRoot -Force
    if(($transactionItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){return & $deny 'atomic-mutation-transaction-root-reparse-point' $false $false $false $null $transactionRoot}

    try{
        [void](Copy-CustomAppAtomicTreeV010 -Source $stage -Destination $candidatePath)
        if([bool]$gitSnapshot.present){[void](Copy-CustomAppAtomicTreeV010 -Source (Join-Path $live '.git') -Destination (Join-Path $candidatePath '.git'))}
        $candidateRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $candidatePath
        if(-not [bool]$candidateRuntime.safe -or -not [bool]$candidateRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $candidateRuntime) -or ([string]$candidateRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){throw 'candidate-runtime-verification-failed'}
        $candidateGit=Test-CustomAppAtomicGitSnapshotV010 -LivePath $candidatePath -Expected $gitSnapshot;if(-not [bool]$candidateGit.ok){throw ('candidate-'+[string]$candidateGit.reason)}
        Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 -Checkpoint 'before-live-move' -Context ([pscustomobject]@{live_path=$live;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
    }catch{return & $deny ('atomic-mutation-candidate-preparation-failed:'+[string]$_.Exception.Message) $false $false $false $null $transactionRoot}

    $mutationStarted=$false
    try{
        [IO.Directory]::Move($live,$oldLivePath);$mutationStarted=$true
        Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 -Checkpoint 'after-live-move' -Context ([pscustomobject]@{live_path=$live;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        [IO.Directory]::Move($candidatePath,$live)
        Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 -Checkpoint 'after-candidate-move' -Context ([pscustomobject]@{live_path=$live;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        $postRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live
        if(-not [bool]$postRuntime.safe -or -not [bool]$postRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $postRuntime) -or ([string]$postRuntime.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedStageRuntimeTreeSha256.Trim().ToLowerInvariant()){throw 'post-swap-runtime-mismatch'}
        $postGit=Test-CustomAppAtomicGitSnapshotV010 -LivePath $live -Expected $gitSnapshot;if(-not [bool]$postGit.ok){throw ('post-swap-'+[string]$postGit.reason)}
        Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 -Checkpoint 'before-persistence-postcheck' -Context ([pscustomobject]@{live_path=$live;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        $persistenceAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if(([string]$persistenceAfter.fingerprint).Trim().ToLowerInvariant() -cne $ExpectedPersistenceFingerprint.Trim().ToLowerInvariant()){throw 'protected-persistence-drift-after-swap'}
        Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 -Checkpoint 'after-post-verify' -Context ([pscustomobject]@{live_path=$live;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        $oldSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $oldLivePath
        if(([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant() -cne $ExpectedLiveFullTreeSha256.Trim().ToLowerInvariant() -or [int]$oldSnapshot.file_count -ne $ExpectedLiveFullFileCount -or [int64]$oldSnapshot.total_bytes -ne $ExpectedLiveFullTotalBytes){throw 'old-live-tree-mismatch'}
        $result=[pscustomobject]@{
            schema=$CustomAppProductionAtomicLiveSwapMutationSchema;managed_by=$CustomAppProductionAtomicLiveSwapMutationManagedBy;qualified_atomic_head=$CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicHead;qualified_atomic_core_blob=$CustomAppProductionAtomicLiveSwapMutationQualifiedAtomicCoreBlob;status='atomic-live-swap-mutation-verified-no-future-authority'
            name=$Name;caller_admission_managed_by=$CallerAdmissionManagedBy;caller_admission_fingerprint=$CallerAdmissionFingerprint.Trim().ToLowerInvariant();live_path=$live;stage_path=$stage;transaction_root=$transactionRoot;old_live_path=$oldLivePath
            pre_live_runtime_tree_sha256=([string]$liveRuntime.tree_sha256).Trim().ToLowerInvariant();pre_live_full_tree_sha256=([string]$fullLive.tree_sha256).Trim().ToLowerInvariant();pre_stage_runtime_tree_sha256=([string]$stageRuntime.tree_sha256).Trim().ToLowerInvariant();old_live_tree_sha256=([string]$oldSnapshot.tree_sha256).Trim().ToLowerInvariant();post_runtime_tree_sha256=([string]$postRuntime.tree_sha256).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if([bool]$gitSnapshot.present){[string]$gitSnapshot.tree_sha256}else{$null});persistence_fingerprint=([string]$persistenceAfter.fingerprint).Trim().ToLowerInvariant();mutated_at=$Now.ToUniversalTime().ToString('o')
            live_code_swap_performed=$true;transaction_workspace_retained=$true;requires_transaction_workspace_cleanup=$true;requires_spicetify_apply_phase=$true;caller_admission_is_authority=$false;result_is_authority=$false;requires_fresh_caller_admission=$true
            spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
        }
        $result.result_fingerprint=Get-CustomAppProductionAtomicLiveSwapMutationSha256V010 (Get-CustomAppProductionAtomicLiveSwapMutationResultMaterialV010 -Result $result)
        $check=Test-CustomAppProductionAtomicLiveSwapMutationResultV010 -Result $result;if(-not [bool]$check.ok){throw ('output-self-validation-failed:'+[string]$check.reason)}
        return [pscustomobject]@{ok=$true;reason='atomic-live-swap-mutation-verified-no-future-authority';result=$result;mutation_started=$true;rollback_attempted=$false;rollback_ok=$false;live_code_swap_performed=$true;result_is_authority=$false;requires_fresh_caller_admission=$true;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{
        $failure=[string]$_.Exception.Message
        if(-not $mutationStarted){return & $deny ('atomic-mutation-swap-failed-before-mutation:'+$failure) $false $false $false $null $transactionRoot}
        $rollback=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath $live -AppBackupPath $backup -ExpectedAppBackupTreeSha256 $ExpectedAppBackupTreeSha256 -PersistenceBackupPath $PersistenceBackupPath -ExpectedPersistenceFingerprint $ExpectedPersistenceFingerprint -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        return & $deny ('atomic-mutation-swap-failed-rolled-back:'+$failure) $true $true ([bool]$rollback.ok) $rollback $transactionRoot
    }
}
