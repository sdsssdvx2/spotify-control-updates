$CustomAppProductionSpicetifyApplyExecutorSchema = 1
$CustomAppProductionSpicetifyApplyExecutorManagedBy = 'custom-app-production-spicetify-apply-executor-v1'
$CustomAppProductionSpicetifyApplyExecutorQualifiedAdmissionHead = 'a4f6d4772afb895dd253a4c82a21643711ac0829'

function Get-CustomAppProductionSpicetifyApplyExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionSpicetifyApplyExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Get-CustomAppProductionSpicetifyApplyResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_admission_head,[string]$Result.status,[string]$Result.reason,
        [string]$Result.name,[string]$Result.consumption_id,[string]$Result.finalization_fingerprint,[string]$Result.preparation_fingerprint,[string]$Result.stage_result_fingerprint,[string]$Result.apply_admission_fingerprint,
        [string]$Result.live_tree_sha256,[string]$Result.remote_tree_sha256,[string]$Result.remote_commit_sha,[string]$Result.binding_fingerprint,[string]$Result.preserved_git_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.spicetify_executable_sha256,[string]$Result.primary_exit_code,[string]$Result.primary_timed_out,[string]$Result.apply_started_at,[string]$Result.apply_finished_at,
        [string]$Result.spicetify_apply_executed,[string]$Result.rollback_attempted,[string]$Result.rollback_ok,[string]$Result.requires_post_apply_commit_cleanup,[string]$Result.stage_workspace_preserved,[string]$Result.app_backup_preserved,[string]$Result.persistence_backup_preserved,
        [string]$Result.result_is_authority,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionSpicetifyApplyResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='apply-result-null'}}
    $required=@('schema','managed_by','qualified_admission_head','status','reason','name','consumption_id','finalization_fingerprint','preparation_fingerprint','stage_result_fingerprint','apply_admission_fingerprint','live_tree_sha256','remote_tree_sha256','remote_commit_sha','binding_fingerprint','persistence_fingerprint','spicetify_executable_sha256','primary_exit_code','primary_timed_out','apply_started_at','apply_finished_at','spicetify_apply_executed','rollback_attempted','rollback_ok','requires_post_apply_commit_cleanup','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','result_fingerprint','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')
    foreach($field in $required){if(-not $Result.PSObject.Properties[$field]){return [pscustomobject]@{ok=$false;reason=('apply-result-required-field-missing-'+$field)}}}
    if([int]$Result.schema -ne $CustomAppProductionSpicetifyApplyExecutorSchema -or [string]$Result.managed_by -cne $CustomAppProductionSpicetifyApplyExecutorManagedBy -or [string]$Result.qualified_admission_head -cne $CustomAppProductionSpicetifyApplyExecutorQualifiedAdmissionHead -or [string]$Result.status -cne 'spicetify-apply-verified-awaiting-commit-cleanup' -or [string]$Result.reason -cne 'exact-spicetify-apply-succeeded-and-post-state-verified'){return [pscustomobject]@{ok=$false;reason='apply-result-owner-schema-parent-status-or-reason-invalid'}}
    if(-not [bool]$Result.spicetify_apply_executed -or [bool]$Result.rollback_attempted -or [bool]$Result.rollback_ok -or -not [bool]$Result.requires_post_apply_commit_cleanup -or -not [bool]$Result.stage_workspace_preserved -or -not [bool]$Result.app_backup_preserved -or -not [bool]$Result.persistence_backup_preserved){return [pscustomobject]@{ok=$false;reason='apply-result-phase-contract-invalid'}}
    foreach($field in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$field){return [pscustomobject]@{ok=$false;reason=('apply-result-'+$field+'-true')}}}
    if([bool]$Result.primary_timed_out){return [pscustomobject]@{ok=$false;reason='apply-result-primary-timed-out'}}
    try{if([int]$Result.primary_exit_code -ne 0){return [pscustomobject]@{ok=$false;reason='apply-result-primary-exit-nonzero'}}}catch{return [pscustomobject]@{ok=$false;reason='apply-result-primary-exit-invalid'}}
    foreach($field in @('consumption_id','finalization_fingerprint','preparation_fingerprint','stage_result_fingerprint','apply_admission_fingerprint','live_tree_sha256','remote_tree_sha256','binding_fingerprint','persistence_fingerprint','spicetify_executable_sha256','result_fingerprint')){if(-not (Test-CustomAppProductionSpicetifyApplyExecutorSha256V010 (([string]$Result.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('apply-result-invalid-'+$field)}}}
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionSpicetifyApplyExecutorSha256V010 (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='apply-result-invalid-preserved-git-tree'}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='apply-result-invalid-remote-commit'}}
    $started=[DateTimeOffset]::MinValue;$finished=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Result.apply_started_at,[ref]$started) -or -not [DateTimeOffset]::TryParse([string]$Result.apply_finished_at,[ref]$finished) -or $finished -lt $started){return [pscustomobject]@{ok=$false;reason='apply-result-time-invalid'}}
    $expected=Get-CustomAppProductionSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionSpicetifyApplyResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='apply-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='apply-result-valid-non-authoritative';result_fingerprint=$expected}
}

function Open-CustomAppProductionSpicetifyExecutableV010 {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][string]$ExpectedSha256)
    $expected=$ExpectedSha256.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionSpicetifyApplyExecutorSha256V010 $expected)){throw 'spicetify-executable-expected-sha256-invalid'}
    $path=[IO.Path]::GetFullPath($ExecutablePath)
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'spicetify-executable-missing'}
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'spicetify-executable-reparse-point'}
    if([string]$item.Name -cne 'spicetify.exe'){throw 'spicetify-executable-name-invalid'}
    $stream=$null
    try{
        $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
        if($actual -cne $expected){throw 'spicetify-executable-sha256-mismatch'}
        return [pscustomobject]@{path=$path;sha256=$actual;stream=$stream}
    }catch{if($null -ne $stream){$stream.Dispose()};throw}
}

function Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath,[int]$TimeoutSeconds=180)
    if($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 600){throw 'spicetify-apply-timeout-policy-invalid'}
    $started=[DateTimeOffset]::UtcNow;$p=$null
    try{
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=[IO.Path]::GetFullPath($ExecutablePath)
        $psi.Arguments='apply'
        $psi.WorkingDirectory=[IO.Path]::GetDirectoryName($psi.FileName)
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$false
        $psi.RedirectStandardError=$false
        $p=New-Object Diagnostics.Process
        $p.StartInfo=$psi
        if(-not $p.Start()){return [pscustomobject]@{ok=$false;reason='spicetify-apply-process-start-returned-false';exit_code=$null;timed_out=$false;started_at=$started;finished_at=[DateTimeOffset]::UtcNow}}
        $finished=$p.WaitForExit($TimeoutSeconds*1000)
        if(-not $finished){
            try{$p.Kill()}catch{}
            try{$p.WaitForExit()}catch{}
            return [pscustomobject]@{ok=$false;reason='spicetify-apply-process-timeout';exit_code=$null;timed_out=$true;started_at=$started;finished_at=[DateTimeOffset]::UtcNow}
        }
        $exit=[int]$p.ExitCode
        return [pscustomobject]@{ok=($exit -eq 0);reason=$(if($exit -eq 0){'spicetify-apply-exit-zero'}else{'spicetify-apply-exit-nonzero'});exit_code=$exit;timed_out=$false;started_at=$started;finished_at=[DateTimeOffset]::UtcNow}
    }catch{return [pscustomobject]@{ok=$false;reason=('spicetify-apply-process-error:'+[string]$_.Exception.Message);exit_code=$null;timed_out=$false;started_at=$started;finished_at=[DateTimeOffset]::UtcNow}}
    finally{if($null -ne $p){$p.Dispose()}}
}

function Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Validation harness may replace this no-op to inject bounded fixture faults.
}

function Test-CustomAppProductionSpicetifyApplyPostStateV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$FinalizationResult,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$StageExecutorResult,[Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot)
    try{$livePath=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$LifecycleRow.locations[0]) -Label 'post-apply-live-path'}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-live-path-invalid:'+[string]$_.Exception.Message)}}
    try{$live=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-live-runtime-read-failed:'+[string]$_.Exception.Message)}}
    if(-not [bool]$live.safe -or -not [bool]$live.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $live) -or [string]$live.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256 -or [string]$live.tree_sha256 -cne [string]$FinalizationResult.live_runtime_tree_sha256){return [pscustomobject]@{ok=$false;reason='post-apply-live-runtime-drift'}}
    try{$git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-git-read-failed:'+[string]$_.Exception.Message)}}
    if($FinalizationResult.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$FinalizationResult.preserved_git_tree_sha256)){
        if(-not [bool]$git.present -or [string]$git.tree_sha256 -cne [string]$FinalizationResult.preserved_git_tree_sha256){return [pscustomobject]@{ok=$false;reason='post-apply-git-drift'}}
    }elseif([bool]$git.present){return [pscustomobject]@{ok=$false;reason='post-apply-unexpected-git'}}
    $backup=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$PreparedResult.persistence_fingerprint)
    if(-not [bool]$backup.ok){return [pscustomobject]@{ok=$false;reason=('post-apply-persistence-backup-invalid:'+[string]$backup.reason)}}
    try{$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-persistence-read-failed:'+[string]$_.Exception.Message)}}
    if([string]$persist.fingerprint -cne [string]$PreparedResult.persistence_fingerprint -or [string]$persist.fingerprint -cne [string]$FinalizationResult.persistence_fingerprint){return [pscustomobject]@{ok=$false;reason='post-apply-protected-persistence-drift'}}
    try{$stage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$PreparedResult.stage_path)}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-retained-stage-read-failed:'+[string]$_.Exception.Message)}}
    if(-not [bool]$stage.safe -or -not [bool]$stage.installable -or [string]$stage.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256){return [pscustomobject]@{ok=$false;reason='post-apply-retained-stage-drift'}}
    try{$appBackup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$PreparedResult.app_backup_path)}catch{return [pscustomobject]@{ok=$false;reason=('post-apply-app-backup-read-failed:'+[string]$_.Exception.Message)}}
    if([string]$appBackup.tree_sha256 -cne [string]$PreparedResult.app_backup_tree_sha256 -or [int]$appBackup.file_count -ne [int]$PreparedResult.app_backup_file_count -or [int64]$appBackup.total_bytes -ne [int64]$PreparedResult.app_backup_total_bytes){return [pscustomobject]@{ok=$false;reason='post-apply-app-backup-drift'}}
    return [pscustomobject]@{ok=$true;reason='post-apply-live-stage-backups-and-persistence-valid';live_path=$livePath;live=$live;git=$git;persistence=$persist}
}

function Invoke-CustomAppProductionSpicetifyApplyRollbackV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[Parameter(Mandatory=$true)][string]$SpicetifyExecutablePath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,[int]$TimeoutSeconds=180)
    $livePath=[string]$LifecycleRow.locations[0]
    $restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath $livePath -AppBackupPath ([string]$PreparedResult.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$PreparedResult.app_backup_tree_sha256) -PersistenceBackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$PreparedResult.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if(-not [bool]$restore.ok){return [pscustomobject]@{ok=$false;reason=('rollback-restore-failed:'+[string]$restore.reason);restore=$restore;recovery_apply=$null}}
    Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 -Checkpoint 'after-rollback-restore-before-recovery-apply' -Context ([pscustomobject]@{live_path=$livePath;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})
    $lock=$null
    try{$lock=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyExecutablePath -ExpectedSha256 $ExpectedSpicetifySha256;$reapply=Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 -ExecutablePath ([string]$lock.path) -TimeoutSeconds $TimeoutSeconds}
    catch{return [pscustomobject]@{ok=$false;reason=('rollback-recovery-executable-denied:'+[string]$_.Exception.Message);restore=$restore;recovery_apply=$null}}
    finally{if($null -ne $lock -and $null -ne $lock.stream){$lock.stream.Dispose()}}
    Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 -Checkpoint 'after-recovery-apply' -Context ([pscustomobject]@{live_path=$livePath;local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot;recovery_apply=$reapply})
    if(-not [bool]$reapply.ok){return [pscustomobject]@{ok=$false;reason=('rollback-recovery-apply-failed:'+[string]$reapply.reason);restore=$restore;recovery_apply=$reapply}}
    try{$full=Get-CustomAppUpdateTreeSnapshotV010 -Root $livePath;$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return [pscustomobject]@{ok=$false;reason=('rollback-postcheck-read-failed:'+[string]$_.Exception.Message);restore=$restore;recovery_apply=$reapply}}
    if([string]$full.tree_sha256 -cne [string]$PreparedResult.app_backup_tree_sha256){return [pscustomobject]@{ok=$false;reason='rollback-postcheck-app-tree-mismatch';restore=$restore;recovery_apply=$reapply}}
    if([string]$persist.fingerprint -cne [string]$PreparedResult.persistence_fingerprint){return [pscustomobject]@{ok=$false;reason='rollback-postcheck-persistence-mismatch';restore=$restore;recovery_apply=$reapply}}
    return [pscustomobject]@{ok=$true;reason='rollback-restored-and-old-state-reapplied';restore=$restore;recovery_apply=$reapply;app_tree_sha256=[string]$full.tree_sha256;persistence_fingerprint=[string]$persist.fingerprint}
}

function Invoke-CustomAppProductionSpicetifyApplyExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$Permit,[AllowNull()]$FinalizationResult,[AllowNull()]$PreparedResult,[AllowNull()]$StageExecutorResult,[Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[Parameter(Mandatory=$true)][string]$SpicetifyExecutablePath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,[int]$TimeoutSeconds=180
    )
    $deny={param([string]$Reason,$Primary=$null,[bool]$RollbackAttempted=$false,[bool]$RollbackOk=$false,$Rollback=$null)[pscustomobject]@{ok=$false;reason=$Reason;primary_apply=$Primary;spicetify_apply_executed=($null -ne $Primary);rollback_attempted=$RollbackAttempted;rollback_ok=$RollbackOk;rollback_result=$Rollback;requires_post_apply_commit_cleanup=$false;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 600){return & $deny 'spicetify-apply-timeout-policy-invalid'}

    Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 -Checkpoint 'before-final-admission' -Context ([pscustomobject]@{name=$Name})
    $admission=Resolve-CustomAppProductionPostSwapApplyAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -FinalizationResult $FinalizationResult -PreparedResult $PreparedResult -StageExecutorResult $StageExecutorResult -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -SessionKey $SessionKey -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $admission -or -not [bool]$admission.ok){return & $deny ('apply-final-admission-denied:'+[string]$admission.reason)}
    $decisionCheck=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 -Decision $admission.decision
    if(-not [bool]$decisionCheck.ok){return & $deny ('apply-final-admission-invalid:'+[string]$decisionCheck.reason)}

    $exe=$null
    try{$exe=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyExecutablePath -ExpectedSha256 $ExpectedSpicetifySha256}
    catch{return & $deny ('spicetify-executable-denied:'+[string]$_.Exception.Message)}
    $primary=$null
    try{
        $primary=Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 -ExecutablePath ([string]$exe.path) -TimeoutSeconds $TimeoutSeconds
    }finally{if($null -ne $exe -and $null -ne $exe.stream){$exe.stream.Dispose()}}

    if(-not [bool]$primary.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $PreparedResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('primary-spicetify-apply-failed:'+[string]$primary.reason) $primary $true ([bool]$rollback.ok) $rollback
    }

    try{Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 -Checkpoint 'after-primary-apply-before-postcheck' -Context ([pscustomobject]@{live_path=[string]$LifecycleRow.locations[0];local_appdata=$LocalAppDataRoot;appdata=$AppDataRoot})}
    catch{
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $PreparedResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('post-apply-hook-failed:'+[string]$_.Exception.Message) $primary $true ([bool]$rollback.ok) $rollback
    }

    $post=Test-CustomAppProductionSpicetifyApplyPostStateV010 -Name $Name -FinalizationResult $FinalizationResult -PreparedResult $PreparedResult -StageExecutorResult $StageExecutorResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if(-not [bool]$post.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $PreparedResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('post-spicetify-apply-verification-failed:'+[string]$post.reason) $primary $true ([bool]$rollback.ok) $rollback
    }
    $consumption=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -StageExecutorResult $StageExecutorResult -Name $Name
    if(-not [bool]$consumption.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $PreparedResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('post-spicetify-apply-consumption-revalidation-failed:'+[string]$consumption.reason) $primary $true ([bool]$rollback.ok) $rollback
    }

    $result=[pscustomobject]@{
        schema=$CustomAppProductionSpicetifyApplyExecutorSchema;managed_by=$CustomAppProductionSpicetifyApplyExecutorManagedBy;qualified_admission_head=$CustomAppProductionSpicetifyApplyExecutorQualifiedAdmissionHead;status='spicetify-apply-verified-awaiting-commit-cleanup';reason='exact-spicetify-apply-succeeded-and-post-state-verified'
        name=$Name;consumption_id=([string]$ExpectedConsumptionId).Trim().ToLowerInvariant();finalization_fingerprint=([string]$FinalizationResult.finalization_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$PreparedResult.preparation_fingerprint).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();apply_admission_fingerprint=([string]$admission.decision.admission_fingerprint).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$post.live.tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$StageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$StageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$StageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant();preserved_git_tree_sha256=$(if([bool]$post.git.present){([string]$post.git.tree_sha256).Trim().ToLowerInvariant()}else{$null});persistence_fingerprint=([string]$post.persistence.fingerprint).Trim().ToLowerInvariant()
        spicetify_executable_sha256=([string]$exe.sha256).Trim().ToLowerInvariant();primary_exit_code=[int]$primary.exit_code;primary_timed_out=[bool]$primary.timed_out;apply_started_at=$primary.started_at.ToUniversalTime().ToString('o');apply_finished_at=$primary.finished_at.ToUniversalTime().ToString('o');spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false
        requires_post_apply_commit_cleanup=$true;stage_workspace_preserved=$true;app_backup_preserved=$true;persistence_backup_preserved=$true;result_fingerprint=$null;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.result_fingerprint=Get-CustomAppProductionSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionSpicetifyApplyResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionSpicetifyApplyResultV010 -Result $result
    if(-not [bool]$check.ok){
        $rollback=Invoke-CustomAppProductionSpicetifyApplyRollbackV010 -Name $Name -PreparedResult $PreparedResult -LifecycleRow $LifecycleRow -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyExecutablePath $SpicetifyExecutablePath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds
        return & $deny ('apply-result-self-validation-failed:'+[string]$check.reason) $primary $true ([bool]$rollback.ok) $rollback
    }
    return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false;requires_post_apply_commit_cleanup=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
