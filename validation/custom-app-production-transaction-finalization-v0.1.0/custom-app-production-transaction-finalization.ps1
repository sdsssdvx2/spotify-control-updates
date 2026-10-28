$CustomAppProductionTransactionFinalizationSchema = 1
$CustomAppProductionTransactionFinalizationManagedBy = 'custom-app-production-transaction-finalization-v1'
$CustomAppProductionTransactionFinalizationQualifiedAtomicHead = '574fe182168271fa3497d58e269e9af1f60d9033'

function Get-CustomAppProductionTransactionFinalizationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){ $Text = '' }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Test-CustomAppProductionTransactionFinalizationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Invoke-CustomAppProductionTransactionFinalizationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function for bounded fixture faults.
}

function Test-CustomAppProductionAtomicSuccessResultV010 {
    param([AllowNull()]$Result,[Parameter(Mandatory=$true)][string]$ExpectedName)
    if($null -eq $Result){ return [pscustomobject]@{ok=$false;reason='atomic-result-null'} }
    $required=@('ok','reason','schema','managed_by','qualified_pre_apply_head','name','live_path','transaction_root','old_live_path','fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint','rollback_attempted','rollback_ok','live_code_swap_performed','requires_transaction_workspace_cleanup','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')
    foreach($field in $required){ if(-not $Result.PSObject.Properties[$field]){ return [pscustomobject]@{ok=$false;reason=('atomic-result-required-field-missing-'+$field)} } }
    if(-not [bool]$Result.ok -or [string]$Result.reason -cne 'atomic-live-code-swap-verified-no-spicetify-apply' -or [int]$Result.schema -ne $CustomAppProductionAtomicLiveSwapSchema -or [string]$Result.managed_by -cne $CustomAppProductionAtomicLiveSwapManagedBy -or [string]$Result.qualified_pre_apply_head -cne $CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead){ return [pscustomobject]@{ok=$false;reason='atomic-result-owner-schema-status-invalid'} }
    if(([string]$Result.name).Trim().ToLowerInvariant() -cne $ExpectedName.Trim().ToLowerInvariant()){ return [pscustomobject]@{ok=$false;reason='atomic-result-name-mismatch'} }
    if([bool]$Result.rollback_attempted -or [bool]$Result.rollback_ok -or -not [bool]$Result.live_code_swap_performed -or -not [bool]$Result.requires_transaction_workspace_cleanup -or -not [bool]$Result.requires_spicetify_apply_phase){ return [pscustomobject]@{ok=$false;reason='atomic-result-lifecycle-contract-invalid'} }
    foreach($field in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){ if([bool]$Result.$field){ return [pscustomobject]@{ok=$false;reason=('atomic-result-'+$field+'-true')} } }
    foreach($field in @('fresh_admission_fingerprint','post_runtime_tree_sha256','persistence_fingerprint')){ if(-not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.$field).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason=('atomic-result-invalid-'+$field)} } }
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason='atomic-result-invalid-preserved-git-tree'} }
    return [pscustomobject]@{ok=$true;reason='atomic-success-result-structurally-valid'}
}

function Test-CustomAppProductionTransactionFinalizationPreconditionsV010 {
    param(
        [AllowNull()]$AtomicResult,[AllowNull()]$PreparedResult,[AllowNull()]$StageExecutorResult,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    $preparedCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $PreparedResult
    if(-not [bool]$preparedCheck.ok){ return [pscustomobject]@{ok=$false;reason=('prepared-result-invalid:'+[string]$preparedCheck.reason)} }
    $stageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $StageExecutorResult
    if(-not [bool]$stageCheck.ok){ return [pscustomobject]@{ok=$false;reason=('stage-result-invalid:'+[string]$stageCheck.reason)} }
    $atomicCheck=Test-CustomAppProductionAtomicSuccessResultV010 -Result $AtomicResult -ExpectedName $Name
    if(-not [bool]$atomicCheck.ok){ return [pscustomobject]@{ok=$false;reason=('atomic-result-invalid:'+[string]$atomicCheck.reason)} }
    if(([string]$PreparedResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant() -or ([string]$StageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){ return [pscustomobject]@{ok=$false;reason='name-continuity-mismatch'} }
    if(([string]$PreparedResult.stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){ return [pscustomobject]@{ok=$false;reason='stage-result-fingerprint-continuity-mismatch'} }
    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or -not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){ return [pscustomobject]@{ok=$false;reason='lifecycle-not-safe-current-single-location'} }

    try {
        $livePath=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$LifecycleRow.locations[0]) -Label 'live-path'
        $parentPath=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([IO.Path]::GetDirectoryName($livePath)) -Label 'customapps-parent'
        $atomicLive=Get-CustomAppAtomicCanonicalPathV010 -Path ([string]$AtomicResult.live_path)
        if(-not $atomicLive.Equals($livePath,[StringComparison]::OrdinalIgnoreCase)){ return [pscustomobject]@{ok=$false;reason='atomic-live-path-mismatch'} }
        $transactionRoot=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$AtomicResult.transaction_root) -Label 'transaction-root'
        if(-not ([IO.Path]::GetDirectoryName($transactionRoot)).Equals($parentPath,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($transactionRoot) -notmatch '^\.spotify-control-txn-[0-9a-fA-F]{32}$'){ return [pscustomobject]@{ok=$false;reason='transaction-root-shape-invalid'} }
        if(Test-CustomAppAtomicPathsOverlapV010 -A $transactionRoot -B $livePath){ return [pscustomobject]@{ok=$false;reason='transaction-root-overlaps-live'} }
        $expectedOld=Get-CustomAppAtomicCanonicalPathV010 -Path (Join-Path $transactionRoot 'old-live')
        $oldLive=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$AtomicResult.old_live_path) -Label 'old-live'
        if(-not $oldLive.Equals($expectedOld,[StringComparison]::OrdinalIgnoreCase)){ return [pscustomobject]@{ok=$false;reason='old-live-path-mismatch'} }
        $children=@(Get-ChildItem -LiteralPath $transactionRoot -Force -ErrorAction Stop)
        if($children.Count -ne 1 -or -not $children[0].PSIsContainer -or [string]$children[0].Name -cne 'old-live' -or ($children[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ return [pscustomobject]@{ok=$false;reason='transaction-root-contents-not-exact-old-live-only'} }
        if(Test-Path -LiteralPath (Join-Path $transactionRoot 'candidate')){ return [pscustomobject]@{ok=$false;reason='transaction-candidate-still-present'} }
    } catch { return [pscustomobject]@{ok=$false;reason=('transaction-path-validation-failed:'+[string]$_.Exception.Message)} }

    try { $oldSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $oldLive }
    catch { return [pscustomobject]@{ok=$false;reason=('old-live-read-failed:'+[string]$_.Exception.Message)} }
    if([string]$oldSnapshot.tree_sha256 -cne [string]$PreparedResult.app_backup_tree_sha256 -or [int]$oldSnapshot.file_count -ne [int]$PreparedResult.app_backup_file_count -or [int64]$oldSnapshot.total_bytes -ne [int64]$PreparedResult.app_backup_total_bytes){ return [pscustomobject]@{ok=$false;reason='old-live-not-exact-pre-swap-tree'} }

    try { $liveRuntime=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath }
    catch { return [pscustomobject]@{ok=$false;reason=('live-runtime-read-failed:'+[string]$_.Exception.Message)} }
    if(-not [bool]$liveRuntime.safe -or -not [bool]$liveRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveRuntime) -or [string]$liveRuntime.tree_sha256 -cne [string]$PreparedResult.stage_tree_sha256 -or [string]$liveRuntime.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256 -or [string]$liveRuntime.tree_sha256 -cne [string]$AtomicResult.post_runtime_tree_sha256){ return [pscustomobject]@{ok=$false;reason='live-runtime-no-longer-exact-staged-tree'} }

    try { $liveGit=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath;$oldGit=Get-CustomAppAtomicGitSnapshotV010 -LivePath $oldLive }
    catch { return [pscustomobject]@{ok=$false;reason=('git-read-failed:'+[string]$_.Exception.Message)} }
    if([bool]$liveGit.present -ne [bool]$oldGit.present){ return [pscustomobject]@{ok=$false;reason='git-presence-drift'} }
    if([bool]$liveGit.present){
        if([string]$liveGit.tree_sha256 -cne [string]$oldGit.tree_sha256 -or [int]$liveGit.file_count -ne [int]$oldGit.file_count -or [int64]$liveGit.total_bytes -ne [int64]$oldGit.total_bytes){ return [pscustomobject]@{ok=$false;reason='git-tree-drift'} }
        if(-not $AtomicResult.PSObject.Properties['preserved_git_tree_sha256'] -or [string]$AtomicResult.preserved_git_tree_sha256 -cne [string]$liveGit.tree_sha256){ return [pscustomobject]@{ok=$false;reason='atomic-preserved-git-fingerprint-mismatch'} }
    } elseif($AtomicResult.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$AtomicResult.preserved_git_tree_sha256)){ return [pscustomobject]@{ok=$false;reason='atomic-reported-git-when-none-exists'} }

    $persistenceBackupCheck=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$PreparedResult.persistence_fingerprint)
    if(-not [bool]$persistenceBackupCheck.ok){ return [pscustomobject]@{ok=$false;reason=('persistence-backup-invalid:'+[string]$persistenceBackupCheck.reason)} }
    try { $persistenceNow=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot }
    catch { return [pscustomobject]@{ok=$false;reason=('persistence-read-failed:'+[string]$_.Exception.Message)} }
    if([string]$persistenceNow.fingerprint -cne [string]$PreparedResult.persistence_fingerprint -or [string]$persistenceNow.fingerprint -cne [string]$AtomicResult.persistence_fingerprint){ return [pscustomobject]@{ok=$false;reason='protected-persistence-drift-before-finalization'} }

    return [pscustomobject]@{ok=$true;reason='transaction-finalization-preconditions-valid';live_path=$livePath;parent_path=$parentPath;transaction_root=$transactionRoot;old_live_path=$oldLive;old_snapshot=$oldSnapshot;live_runtime=$liveRuntime;live_git=$liveGit;persistence=$persistenceNow}
}

function Get-CustomAppProductionTransactionFinalizationResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_atomic_head,[string]$Result.status,[string]$Result.name,[string]$Result.live_path,[string]$Result.transaction_root,
        [string]$Result.consumption_id,[string]$Result.stage_result_fingerprint,[string]$Result.preparation_fingerprint,[string]$Result.atomic_fresh_admission_fingerprint,
        [string]$Result.old_live_tree_sha256,[string]$Result.live_runtime_tree_sha256,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.finalized_at,
        [string]$Result.stage_workspace_path,[string]$Result.app_backup_path,[string]$Result.persistence_backup_path,[string]$Result.transaction_workspace_deleted,[string]$Result.stage_workspace_preserved,
        [string]$Result.app_backup_preserved,[string]$Result.persistence_backup_preserved,[string]$Result.requires_spicetify_apply_phase,[string]$Result.result_is_authority,
        [string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionTransactionFinalizationResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){ return [pscustomobject]@{ok=$false;reason='finalization-result-null'} }
    $required=@('schema','managed_by','qualified_atomic_head','status','name','live_path','transaction_root','consumption_id','stage_result_fingerprint','preparation_fingerprint','atomic_fresh_admission_fingerprint','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','finalized_at','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_workspace_deleted','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized','finalization_fingerprint')
    foreach($field in $required){ if(-not $Result.PSObject.Properties[$field]){ return [pscustomobject]@{ok=$false;reason=('finalization-result-required-field-missing-'+$field)} } }
    if([int]$Result.schema -ne $CustomAppProductionTransactionFinalizationSchema -or [string]$Result.managed_by -cne $CustomAppProductionTransactionFinalizationManagedBy -or [string]$Result.qualified_atomic_head -cne $CustomAppProductionTransactionFinalizationQualifiedAtomicHead -or [string]$Result.status -cne 'transaction-workspace-finalized-live-and-persistence-reverified'){ return [pscustomobject]@{ok=$false;reason='finalization-result-owner-schema-parent-or-status-invalid'} }
    if(-not [bool]$Result.transaction_workspace_deleted -or -not [bool]$Result.stage_workspace_preserved -or -not [bool]$Result.app_backup_preserved -or -not [bool]$Result.persistence_backup_preserved -or -not [bool]$Result.requires_spicetify_apply_phase){ return [pscustomobject]@{ok=$false;reason='finalization-result-preservation-contract-invalid'} }
    foreach($field in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){ if([bool]$Result.$field){ return [pscustomobject]@{ok=$false;reason=('finalization-result-'+$field+'-true')} } }
    foreach($field in @('consumption_id','stage_result_fingerprint','preparation_fingerprint','atomic_fresh_admission_fingerprint','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','finalization_fingerprint')){ if(-not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.$field).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason=('finalization-result-invalid-'+$field)} } }
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason='finalization-result-invalid-preserved-git-tree'} }
    try {
        if(Test-Path -LiteralPath ([string]$Result.transaction_root)){ return [pscustomobject]@{ok=$false;reason='finalization-result-transaction-root-still-exists'} }
        if(-not (Test-Path -LiteralPath ([string]$Result.live_path) -PathType Container)){ return [pscustomobject]@{ok=$false;reason='finalization-result-live-path-missing'} }
        foreach($field in @('stage_workspace_path','app_backup_path','persistence_backup_path')){ if(-not (Test-Path -LiteralPath ([string]$Result.$field) -PathType Container)){ return [pscustomobject]@{ok=$false;reason=('finalization-result-preserved-path-missing-'+$field)} } }
    } catch { return [pscustomobject]@{ok=$false;reason=('finalization-result-path-check-failed:'+[string]$_.Exception.Message)} }
    $expected=Get-CustomAppProductionTransactionFinalizationSha256V010 -Text (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $Result)
    if([string]$Result.finalization_fingerprint -cne $expected){ return [pscustomobject]@{ok=$false;reason='finalization-result-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='transaction-finalization-result-valid';fingerprint=$expected}
}

function Invoke-CustomAppProductionTransactionFinalizationV010 {
    param(
        [AllowNull()]$AtomicResult,[AllowNull()]$PreparedResult,[AllowNull()]$StageExecutorResult,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={ param([string]$Reason,[bool]$Attempted,[bool]$Deleted) [pscustomobject]@{ok=$false;reason=$Reason;cleanup_attempted=$Attempted;transaction_workspace_deleted=$Deleted;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false} }
    $pre=Test-CustomAppProductionTransactionFinalizationPreconditionsV010 -AtomicResult $AtomicResult -PreparedResult $PreparedResult -StageExecutorResult $StageExecutorResult -Name $Name -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if(-not [bool]$pre.ok){ return & $deny ('transaction-finalization-precondition-denied:'+[string]$pre.reason) $false $false }

    try {
        Invoke-CustomAppProductionTransactionFinalizationValidationHookV010 -Checkpoint 'before-cleanup' -Context ([pscustomobject]@{live_path=$pre.live_path;transaction_root=$pre.transaction_root;old_live_path=$pre.old_live_path;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        Remove-CustomAppAtomicDirectoryV010 -Path ([string]$pre.transaction_root) -ExpectedParent ([string]$pre.parent_path) -ExpectedName ([IO.Path]::GetFileName([string]$pre.transaction_root))
    } catch {
        return & $deny ('transaction-workspace-cleanup-failed:'+[string]$_.Exception.Message) $true (-not (Test-Path -LiteralPath ([string]$pre.transaction_root)))
    }
    if(Test-Path -LiteralPath ([string]$pre.transaction_root)){ return & $deny 'transaction-workspace-remained-after-cleanup' $true $false }

    try { Invoke-CustomAppProductionTransactionFinalizationValidationHookV010 -Checkpoint 'after-cleanup' -Context ([pscustomobject]@{live_path=$pre.live_path;transaction_root=$pre.transaction_root;old_live_path=$pre.old_live_path;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot}) }
    catch { return & $deny ('post-cleanup-hook-failed:'+[string]$_.Exception.Message) $true $true }

    try { $liveAfter=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$pre.live_path) }
    catch { return & $deny ('post-cleanup-live-read-failed:'+[string]$_.Exception.Message) $true $true }
    if(-not [bool]$liveAfter.safe -or -not [bool]$liveAfter.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveAfter) -or [string]$liveAfter.tree_sha256 -cne [string]$pre.live_runtime.tree_sha256){ return & $deny 'post-cleanup-live-runtime-drift' $true $true }
    try { $gitAfter=Get-CustomAppAtomicGitSnapshotV010 -LivePath ([string]$pre.live_path) }
    catch { return & $deny ('post-cleanup-git-read-failed:'+[string]$_.Exception.Message) $true $true }
    if([bool]$gitAfter.present -ne [bool]$pre.live_git.present -or ([bool]$gitAfter.present -and ([string]$gitAfter.tree_sha256 -cne [string]$pre.live_git.tree_sha256 -or [int]$gitAfter.file_count -ne [int]$pre.live_git.file_count -or [int64]$gitAfter.total_bytes -ne [int64]$pre.live_git.total_bytes))){ return & $deny 'post-cleanup-git-drift' $true $true }
    try { $persistenceAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot }
    catch { return & $deny ('post-cleanup-persistence-read-failed:'+[string]$_.Exception.Message) $true $true }
    if([string]$persistenceAfter.fingerprint -cne [string]$pre.persistence.fingerprint){ return & $deny 'post-cleanup-protected-persistence-drift' $true $true }

    $preparedAfter=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $PreparedResult
    if(-not [bool]$preparedAfter.ok){ return & $deny ('post-cleanup-prepared-evidence-drift:'+[string]$preparedAfter.reason) $true $true }
    $result=[pscustomobject]@{
        ok=$true;reason='transaction-workspace-finalized-live-and-persistence-reverified';schema=$CustomAppProductionTransactionFinalizationSchema;managed_by=$CustomAppProductionTransactionFinalizationManagedBy;qualified_atomic_head=$CustomAppProductionTransactionFinalizationQualifiedAtomicHead;status='transaction-workspace-finalized-live-and-persistence-reverified'
        name=$Name;live_path=[string]$pre.live_path;transaction_root=[string]$pre.transaction_root;consumption_id=[string]$PreparedResult.consumption_id;stage_result_fingerprint=[string]$StageExecutorResult.result_fingerprint;preparation_fingerprint=[string]$PreparedResult.preparation_fingerprint;atomic_fresh_admission_fingerprint=[string]$AtomicResult.fresh_admission_fingerprint
        old_live_tree_sha256=[string]$pre.old_snapshot.tree_sha256;live_runtime_tree_sha256=[string]$liveAfter.tree_sha256;preserved_git_tree_sha256=$(if([bool]$gitAfter.present){[string]$gitAfter.tree_sha256}else{$null});persistence_fingerprint=[string]$persistenceAfter.fingerprint;finalized_at=$Now.ToUniversalTime().ToString('o')
        stage_workspace_path=[string]$PreparedResult.stage_workspace_path;app_backup_path=[string]$PreparedResult.app_backup_path;persistence_backup_path=[string]$PreparedResult.persistence_backup_path;transaction_workspace_deleted=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;requires_spicetify_apply_phase=$true
        result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false;finalization_fingerprint=$null
    }
    $result.finalization_fingerprint=Get-CustomAppProductionTransactionFinalizationSha256V010 -Text (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $result)
    return $result
}
