$CustomAppProductionAtomicLiveSwapSchema = 1
$CustomAppProductionAtomicLiveSwapManagedBy = 'custom-app-production-atomic-live-swap-v1'
$CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead = 'ddc84778ab4815d4174198727b8d1d052a02182e'

function Get-CustomAppAtomicCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){ throw 'atomic-path-empty' }
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppAtomicPathsOverlapV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    $a = Get-CustomAppAtomicCanonicalPathV010 -Path $A
    $b = Get-CustomAppAtomicCanonicalPathV010 -Path $B
    if($a.Equals($b,[StringComparison]::OrdinalIgnoreCase)){ return $true }
    return ($a.StartsWith($b+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))
}

function Assert-CustomAppAtomicSafeDirectoryV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[string]$Label='directory')
    $p = Get-CustomAppAtomicCanonicalPathV010 -Path $Path
    if(-not (Test-Path -LiteralPath $p -PathType Container)){ throw "$Label-missing" }
    $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw "$Label-reparse-point" }
    return $p
}

function Copy-CustomAppAtomicTreeV010 {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    $src = Assert-CustomAppAtomicSafeDirectoryV010 -Path $Source -Label 'copy-source'
    $dst = Get-CustomAppAtomicCanonicalPathV010 -Path $Destination
    if(Test-CustomAppAtomicPathsOverlapV010 -A $src -B $dst){ throw 'copy-source-destination-overlap' }
    if(Test-Path -LiteralPath $dst){ throw 'copy-destination-exists' }
    $snapshot = Get-CustomAppUpdateTreeSnapshotV010 -Root $src
    [IO.Directory]::CreateDirectory($dst) | Out-Null
    foreach($entry in @($snapshot.entries)){
        $relative = ([string]$entry.path).Replace('/',[IO.Path]::DirectorySeparatorChar)
        $target = Join-Path $dst $relative
        if([string]$entry.type -ceq 'dir'){
            [IO.Directory]::CreateDirectory($target) | Out-Null
            continue
        }
        $parent = [IO.Path]::GetDirectoryName($target)
        if(-not [string]::IsNullOrWhiteSpace($parent)){ [IO.Directory]::CreateDirectory($parent) | Out-Null }
        [IO.File]::Copy((Join-Path $src $relative),$target,$false)
    }
    $copied = Get-CustomAppUpdateTreeSnapshotV010 -Root $dst
    if([string]$copied.tree_sha256 -cne [string]$snapshot.tree_sha256 -or [int]$copied.file_count -ne [int]$snapshot.file_count -or [int64]$copied.total_bytes -ne [int64]$snapshot.total_bytes){ throw 'copy-tree-verification-failed' }
    return $copied
}

function Remove-CustomAppAtomicDirectoryV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedParent,[string]$ExpectedName=$null)
    $target = Get-CustomAppAtomicCanonicalPathV010 -Path $Path
    $parent = Get-CustomAppAtomicCanonicalPathV010 -Path $ExpectedParent
    if(-not ([IO.Path]::GetDirectoryName($target)).Equals($parent,[StringComparison]::OrdinalIgnoreCase)){ throw 'atomic-remove-parent-mismatch' }
    if(-not [string]::IsNullOrWhiteSpace($ExpectedName) -and [IO.Path]::GetFileName($target) -cne $ExpectedName){ throw 'atomic-remove-name-mismatch' }
    if(Test-Path -LiteralPath $target){
        $item=Get-Item -LiteralPath $target -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){ throw 'atomic-remove-reparse-point' }
        [IO.Directory]::Delete($target,$true)
    }
}

function Get-CustomAppAtomicGitSnapshotV010 {
    param([Parameter(Mandatory=$true)][string]$LivePath)
    $git = Join-Path $LivePath '.git'
    if(-not (Test-Path -LiteralPath $git)){ return [pscustomobject]@{present=$false;path=$git;tree_sha256=$null;file_count=0;total_bytes=0} }
    if(-not (Test-Path -LiteralPath $git -PathType Container)){ throw 'live-git-file-indirection-forbidden' }
    $snapshot = Get-CustomAppUpdateTreeSnapshotV010 -Root $git
    return [pscustomobject]@{present=$true;path=$git;tree_sha256=[string]$snapshot.tree_sha256;file_count=[int]$snapshot.file_count;total_bytes=[int64]$snapshot.total_bytes}
}

function Test-CustomAppAtomicGitSnapshotV010 {
    param([Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)]$Expected)
    $actual = Get-CustomAppAtomicGitSnapshotV010 -LivePath $LivePath
    if([bool]$actual.present -ne [bool]$Expected.present){ return [pscustomobject]@{ok=$false;reason='git-presence-mismatch';actual=$actual} }
    if([bool]$Expected.present -and ([string]$actual.tree_sha256 -cne [string]$Expected.tree_sha256 -or [int]$actual.file_count -ne [int]$Expected.file_count -or [int64]$actual.total_bytes -ne [int64]$Expected.total_bytes)){ return [pscustomobject]@{ok=$false;reason='git-tree-mismatch';actual=$actual} }
    return [pscustomobject]@{ok=$true;reason='git-preserved';actual=$actual}
}

function Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function to inject bounded fixture faults.
}

function Test-CustomAppProductionAtomicPreconditionsV010 {
    param(
        [AllowNull()]$PreparedResult,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    $preparedCheck = Test-CustomAppProductionPreApplyPreparedResultV010 -Result $PreparedResult
    if(-not [bool]$preparedCheck.ok){ return [pscustomobject]@{ok=$false;reason=('prepared-result-invalid:'+[string]$preparedCheck.reason)} }
    if(([string]$PreparedResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){ return [pscustomobject]@{ok=$false;reason='prepared-name-mismatch'} }
    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or -not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){ return [pscustomobject]@{ok=$false;reason='lifecycle-not-safe-current-single-location'} }
    $livePath = Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$LifecycleRow.locations[0]) -Label 'live-path'
    $parentPath = Assert-CustomAppAtomicSafeDirectoryV010 -Path ([IO.Path]::GetDirectoryName($livePath)) -Label 'customapps-parent'
    if([IO.Path]::GetFileName($livePath).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){ return [pscustomobject]@{ok=$false;reason='live-directory-name-mismatch'} }
    if(Test-CustomAppAtomicPathsOverlapV010 -A $livePath -B ([string]$PreparedResult.stage_workspace_path)){ return [pscustomobject]@{ok=$false;reason='live-stage-overlap'} }
    if(Test-CustomAppAtomicPathsOverlapV010 -A $livePath -B ([string]$PreparedResult.app_backup_root)){ return [pscustomobject]@{ok=$false;reason='live-app-backup-overlap'} }
    if(Test-CustomAppAtomicPathsOverlapV010 -A $livePath -B ([string]$PreparedResult.persistence_backup_root)){ return [pscustomobject]@{ok=$false;reason='live-persistence-backup-overlap'} }

    try { $liveRuntime = Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath }
    catch { return [pscustomobject]@{ok=$false;reason=('live-runtime-read-failed:'+[string]$_.Exception.Message)} }
    if(-not [bool]$liveRuntime.safe -or -not [bool]$liveRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveRuntime) -or [string]$liveRuntime.tree_sha256 -cne [string]$PreparedResult.live_tree_sha256){ return [pscustomobject]@{ok=$false;reason='live-runtime-precondition-mismatch'} }
    try { $fullLive = Get-CustomAppUpdateTreeSnapshotV010 -Root $livePath }
    catch { return [pscustomobject]@{ok=$false;reason=('live-full-tree-read-failed:'+[string]$_.Exception.Message)} }
    if([string]$fullLive.tree_sha256 -cne [string]$PreparedResult.app_backup_tree_sha256 -or [int]$fullLive.file_count -ne [int]$PreparedResult.app_backup_file_count -or [int64]$fullLive.total_bytes -ne [int64]$PreparedResult.app_backup_total_bytes){ return [pscustomobject]@{ok=$false;reason='live-full-tree-no-longer-matches-rollback-backup'} }
    try { $stageRuntime = Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$PreparedResult.stage_path) }
    catch { return [pscustomobject]@{ok=$false;reason=('stage-runtime-read-failed:'+[string]$_.Exception.Message)} }
    if(-not [bool]$stageRuntime.safe -or -not [bool]$stageRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stageRuntime) -or [string]$stageRuntime.tree_sha256 -cne [string]$PreparedResult.stage_tree_sha256){ return [pscustomobject]@{ok=$false;reason='stage-runtime-precondition-mismatch'} }
    if(Test-Path -LiteralPath (Join-Path ([string]$PreparedResult.stage_path) '.git')){ return [pscustomobject]@{ok=$false;reason='stage-vcs-metadata-forbidden'} }
    try { $gitSnapshot = Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath }
    catch { return [pscustomobject]@{ok=$false;reason=('live-git-precondition-failed:'+[string]$_.Exception.Message)} }
    $persistenceBackupCheck = Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$PreparedResult.persistence_fingerprint)
    if(-not [bool]$persistenceBackupCheck.ok){ return [pscustomobject]@{ok=$false;reason=('persistence-backup-invalid:'+[string]$persistenceBackupCheck.reason)} }
    try { $persistenceNow = Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot }
    catch { return [pscustomobject]@{ok=$false;reason=('persistence-read-failed:'+[string]$_.Exception.Message)} }
    if([string]$persistenceNow.fingerprint -cne [string]$PreparedResult.persistence_fingerprint){ return [pscustomobject]@{ok=$false;reason='protected-persistence-drift-before-swap'} }
    return [pscustomobject]@{ok=$true;reason='atomic-preconditions-valid';live_path=$livePath;parent_path=$parentPath;live_runtime=$liveRuntime;full_live=$fullLive;stage_runtime=$stageRuntime;git_snapshot=$gitSnapshot;persistence=$persistenceNow}
}

function Restore-CustomAppProductionAtomicLiveSwapV010 {
    param(
        [Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$AppBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupPath,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    $live = Get-CustomAppAtomicCanonicalPathV010 -Path $LivePath
    $parent = Get-CustomAppAtomicCanonicalPathV010 -Path ([IO.Path]::GetDirectoryName($live))
    try {
        if(Test-Path -LiteralPath $live){ Remove-CustomAppAtomicDirectoryV010 -Path $live -ExpectedParent $parent -ExpectedName ([IO.Path]::GetFileName($live)) }
        [void](Copy-CustomAppAtomicTreeV010 -Source $AppBackupPath -Destination $live)
        $restoredApp = Get-CustomAppUpdateTreeSnapshotV010 -Root $live
        if([string]$restoredApp.tree_sha256 -cne $ExpectedAppBackupTreeSha256){ throw 'app-rollback-tree-mismatch' }
        $restoredPersistence = Restore-SpotifyPersistenceBackup -BackupPath $PersistenceBackupPath -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if([string]$restoredPersistence.fingerprint -cne $ExpectedPersistenceFingerprint){ throw 'persistence-rollback-fingerprint-mismatch' }
        return [pscustomobject]@{ok=$true;reason='app-and-persistence-restored-exactly';app_tree_sha256=[string]$restoredApp.tree_sha256;persistence_fingerprint=[string]$restoredPersistence.fingerprint}
    } catch {
        return [pscustomobject]@{ok=$false;reason=('rollback-failed:'+[string]$_.Exception.Message)}
    }
}

function Invoke-CustomAppProductionAtomicLiveSwapV010 {
    param(
        [AllowNull()]$PreparedResult,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    $pre = Test-CustomAppProductionAtomicPreconditionsV010 -PreparedResult $PreparedResult -Name $Name -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    $baseFailure = { param([string]$Reason,[bool]$RollbackAttempted,[bool]$RollbackOk,$RollbackResult=$null) [pscustomobject]@{ok=$false;reason=$Reason;rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$RollbackResult;live_code_swap_performed=$false;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false} }
    if(-not [bool]$pre.ok){ return & $baseFailure ('atomic-precondition-denied:'+[string]$pre.reason) $false $false $null }

    $livePath = [string]$pre.live_path
    $parentPath = [string]$pre.parent_path
    $transactionRoot = Join-Path $parentPath ('.spotify-control-txn-'+[Guid]::NewGuid().ToString('N'))
    $candidatePath = Join-Path $transactionRoot 'candidate'
    $oldLivePath = Join-Path $transactionRoot 'old-live'
    if(Test-Path -LiteralPath $transactionRoot){ return & $baseFailure 'transaction-root-collision' $false $false $null }
    [IO.Directory]::CreateDirectory($transactionRoot) | Out-Null
    $transactionItem = Get-Item -LiteralPath $transactionRoot -Force
    if(($transactionItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){ return & $baseFailure 'transaction-root-reparse-point' $false $false $null }

    try {
        [void](Copy-CustomAppAtomicTreeV010 -Source ([string]$PreparedResult.stage_path) -Destination $candidatePath)
        if([bool]$pre.git_snapshot.present){ [void](Copy-CustomAppAtomicTreeV010 -Source (Join-Path $livePath '.git') -Destination (Join-Path $candidatePath '.git')) }
        $candidateRuntime = Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $candidatePath
        if(-not [bool]$candidateRuntime.safe -or -not [bool]$candidateRuntime.installable -or [string]$candidateRuntime.tree_sha256 -cne [string]$PreparedResult.stage_tree_sha256){ throw 'candidate-runtime-verification-failed' }
        $candidateGit = Test-CustomAppAtomicGitSnapshotV010 -LivePath $candidatePath -Expected $pre.git_snapshot
        if(-not [bool]$candidateGit.ok){ throw ('candidate-'+[string]$candidateGit.reason) }
        Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 -Checkpoint 'before-live-move' -Context ([pscustomobject]@{live_path=$livePath;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
    } catch {
        return & $baseFailure ('candidate-preparation-failed:'+[string]$_.Exception.Message) $false $false $null
    }

    $mutationStarted = $false
    try {
        [IO.Directory]::Move($livePath,$oldLivePath)
        $mutationStarted = $true
        Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 -Checkpoint 'after-live-move' -Context ([pscustomobject]@{live_path=$livePath;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        [IO.Directory]::Move($candidatePath,$livePath)
        Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 -Checkpoint 'after-candidate-move' -Context ([pscustomobject]@{live_path=$livePath;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})

        $postRuntime = Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath
        if(-not [bool]$postRuntime.safe -or -not [bool]$postRuntime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $postRuntime) -or [string]$postRuntime.tree_sha256 -cne [string]$PreparedResult.stage_tree_sha256){ throw 'post-swap-runtime-mismatch' }
        $postGit = Test-CustomAppAtomicGitSnapshotV010 -LivePath $livePath -Expected $pre.git_snapshot
        if(-not [bool]$postGit.ok){ throw ('post-swap-'+[string]$postGit.reason) }
        Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 -Checkpoint 'before-persistence-postcheck' -Context ([pscustomobject]@{live_path=$livePath;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
        $persistenceAfter = Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if([string]$persistenceAfter.fingerprint -cne [string]$PreparedResult.persistence_fingerprint){ throw 'protected-persistence-drift-after-swap' }
        Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 -Checkpoint 'after-post-verify' -Context ([pscustomobject]@{live_path=$livePath;candidate_path=$candidatePath;old_live_path=$oldLivePath;transaction_root=$transactionRoot;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})

        return [pscustomobject]@{
            ok=$true;reason='atomic-live-code-swap-verified-no-spicetify-apply';schema=$CustomAppProductionAtomicLiveSwapSchema;managed_by=$CustomAppProductionAtomicLiveSwapManagedBy;qualified_pre_apply_head=$CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead
            name=$Name;live_path=$livePath;transaction_root=$transactionRoot;old_live_path=$oldLivePath;post_runtime_tree_sha256=[string]$postRuntime.tree_sha256;preserved_git_tree_sha256=$(if([bool]$pre.git_snapshot.present){[string]$pre.git_snapshot.tree_sha256}else{$null});persistence_fingerprint=[string]$persistenceAfter.fingerprint
            rollback_attempted=$false;rollback_ok=$false;live_code_swap_performed=$true;requires_transaction_workspace_cleanup=$true;requires_spicetify_apply_phase=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false
        }
    } catch {
        $failure = [string]$_.Exception.Message
        if(-not $mutationStarted){ return & $baseFailure ('atomic-swap-failed-before-mutation:'+$failure) $false $false $null }
        $rollback = Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath $livePath -AppBackupPath ([string]$PreparedResult.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$PreparedResult.app_backup_tree_sha256) -PersistenceBackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$PreparedResult.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        return & $baseFailure ('atomic-swap-failed-rolled-back:'+$failure) $true ([bool]$rollback.ok) $rollback
    }
}
