$CustomAppProductionRecoveryRestoreExecutorSchema = 1
$CustomAppProductionRecoveryRestoreExecutorManagedBy = 'custom-app-production-recovery-restore-executor-v1'
$CustomAppProductionRecoveryRestoreExecutorQualifiedAdmissionHead = 'd9a1face71511bdaeeef4e8c761415ef9ec95fc0'
$CustomAppProductionRecoveryRestoreExecutorQualifiedAtomicHead = '574fe182168271fa3497d58e269e9af1f60d9033'
$CustomAppProductionRecoveryRestoreExecutorQualifiedApplyHead = 'fe07d410531ea13c8fca379b01405631a3763e84'
$CustomAppProductionRecoveryRestoreExecutorQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'

function Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryRestoreExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Open-CustomAppProductionRecoveryRestoreExecutorLockV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    $path=Join-Path ([string]$paths.store) '.restore-executor.lock'
    if(Test-Path -LiteralPath $path){
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-restore-executor-lock-path-unsafe'}
    }
    try{return [IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{throw 'recovery-restore-executor-lock-busy'}
}

function Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_admission_head,[string]$Result.qualified_atomic_head,[string]$Result.qualified_apply_head,[string]$Result.qualified_journal_head,
        [string]$Result.status,[string]$Result.reason,[string]$Result.transaction_id,[string]$Result.name,[string]$Result.source_identity,[string]$Result.remote_commit_sha,[string]$Result.consumption_id,[string]$Result.preparation_fingerprint,[string]$Result.evidence_fingerprint,
        [string]$Result.started_phase,[string]$Result.rollback_required_was_appended,[string]$Result.initial_admission_fingerprint,[string]$Result.rollback_admission_fingerprint,[string]$Result.post_restore_admission_fingerprint,
        [string]$Result.live_path,[string]$Result.transaction_root,[string]$Result.stage_workspace_path,[string]$Result.app_backup_path,[string]$Result.persistence_backup_path,[string]$Result.app_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.spicetify_executable_sha256,[string]$Result.apply_exit_code,[string]$Result.apply_timed_out,[string]$Result.apply_started_at,[string]$Result.apply_finished_at,[string]$Result.rollback_complete_revision,[string]$Result.rollback_complete_entry_sha256,
        [string]$Result.restore_performed,[string]$Result.recovery_apply_executed,[string]$Result.rollback_complete_persisted,[string]$Result.requires_recovery_artifact_retirement,[string]$Result.requires_future_fresh_revalidation,
        [string]$Result.result_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryRestoreExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-null'}}
    foreach($f in @('schema','managed_by','qualified_admission_head','qualified_atomic_head','qualified_apply_head','qualified_journal_head','status','reason','transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','evidence_fingerprint','started_phase','rollback_required_was_appended','initial_admission_fingerprint','rollback_admission_fingerprint','post_restore_admission_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','app_tree_sha256','persistence_fingerprint','spicetify_executable_sha256','apply_exit_code','apply_timed_out','apply_started_at','apply_finished_at','rollback_complete_revision','rollback_complete_entry_sha256','restore_performed','recovery_apply_executed','rollback_complete_persisted','requires_recovery_artifact_retirement','requires_future_fresh_revalidation','result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','result_fingerprint')){
        if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-restore-executor-result-field-missing-'+$f)}}
    }
    if([int]$Result.schema -ne $CustomAppProductionRecoveryRestoreExecutorSchema -or [string]$Result.managed_by -cne $CustomAppProductionRecoveryRestoreExecutorManagedBy -or [string]$Result.qualified_admission_head -cne $CustomAppProductionRecoveryRestoreExecutorQualifiedAdmissionHead -or [string]$Result.qualified_atomic_head -cne $CustomAppProductionRecoveryRestoreExecutorQualifiedAtomicHead -or [string]$Result.qualified_apply_head -cne $CustomAppProductionRecoveryRestoreExecutorQualifiedApplyHead -or [string]$Result.qualified_journal_head -cne $CustomAppProductionRecoveryRestoreExecutorQualifiedJournalHead){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-owner-schema-parent-invalid'}}
    if([string]$Result.status -cne 'rollback-complete-verified-awaiting-artifact-retirement' -or [string]$Result.reason -cne 'old-app-and-persistence-restored-recovery-apply-verified-and-journal-completed'){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-status-or-reason-invalid'}}
    foreach($f in @('transaction_id','consumption_id','preparation_fingerprint','evidence_fingerprint','initial_admission_fingerprint','rollback_admission_fingerprint','post_restore_admission_fingerprint','app_tree_sha256','persistence_fingerprint','spicetify_executable_sha256','rollback_complete_entry_sha256','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryRestoreExecutorSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-restore-executor-result-invalid-'+$f)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-remote-commit-invalid'}}
    if([string]$Result.started_phase -notin @('live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','rollback-required')){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-started-phase-invalid'}}
    if(-not [bool]$Result.restore_performed -or -not [bool]$Result.recovery_apply_executed -or -not [bool]$Result.rollback_complete_persisted -or -not [bool]$Result.requires_recovery_artifact_retirement -or -not [bool]$Result.requires_future_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-phase-contract-invalid'}}
    if([bool]$Result.apply_timed_out){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-apply-timeout'}}
    try{if([int]$Result.apply_exit_code -ne 0){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-apply-exit-nonzero'}};if([int64]$Result.rollback_complete_revision -lt 1){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-journal-revision-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-numeric-field-invalid'}}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-restore-executor-result-authority-escaped-'+$f)}}}
    $started=[DateTimeOffset]::MinValue;$finished=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Result.apply_started_at,[ref]$started) -or -not[DateTimeOffset]::TryParse([string]$Result.apply_finished_at,[ref]$finished) -or $finished -lt $started){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-apply-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-restore-executor-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-restore-executor-result-valid-zero-authority';transaction_id=([string]$Result.transaction_id).Trim().ToLowerInvariant();result_fingerprint=$expected}
}

function Test-CustomAppProductionRecoveryRestoreExecutorAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$Initial,[Parameter(Mandatory=$true)]$Current)
    foreach($f in @('transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','evidence_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','app_backup_tree_sha256','persistence_fingerprint')){
        if(([string]$Initial.$f).Trim().ToLowerInvariant() -cne ([string]$Current.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-restore-executor-admission-continuity-mismatch-'+$f)}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-restore-executor-admission-continuity-exact'}
}

function Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Validation harness may replace this no-op to inject bounded fixture faults/races.
}

function Invoke-CustomAppProductionRecoveryRestoreExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyAllowedRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyPath,
        [Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [int]$TimeoutSeconds=180
    )
    $deny={param([string]$Reason,[bool]$RestorePerformed=$false,[bool]$ApplyExecuted=$false,$Apply=$null,[bool]$BarrierAppended=$false)[pscustomobject]@{ok=$false;reason=$Reason;restore_performed=$RestorePerformed;recovery_apply_executed=$ApplyExecuted;apply_result=$Apply;rollback_required_was_appended=$BarrierAppended;rollback_complete_persisted=$false;requires_recovery_artifact_retirement=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    if($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 600){return & $deny 'recovery-restore-executor-timeout-policy-invalid'}
    $lock=$null
    try{$lock=Open-CustomAppProductionRecoveryRestoreExecutorLockV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ([string]$_.Exception.Message)}
    try{
        $initial=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now
        if($null -eq $initial -or -not [bool]$initial.ok){return & $deny ('recovery-restore-executor-initial-admission-denied:'+[string]$initial.reason)}
        $ic=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $initial.receipt -Now $Now
        if(-not [bool]$ic.ok){return & $deny ('recovery-restore-executor-initial-admission-invalid:'+[string]$ic.reason)}
        $i=$initial.receipt

        # Every completed restore ends in rollback-required -> rollback-complete and therefore always needs an exact recovery apply.
        # Preflight the executable before changing the journal so a bad pin cannot create a new recovery obligation.
        $exePre=$null
        try{$exePre=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256}
        catch{return & $deny ('recovery-restore-executor-executable-precheck-denied:'+[string]$_.Exception.Message)}
        finally{if($null -ne $exePre -and $null -ne $exePre.stream){$exePre.stream.Dispose()}}

        $barrierAppended=$false
        if([string]$i.phase -cne 'rollback-required'){
            Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'before-rollback-required-append' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store_directory=$StoreDirectory;receipt=$i})
            $barrier=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$i.journal_revision) -ExpectedEntrySha256 ([string]$i.journal_entry_sha256) -Phase 'rollback-required' -Now $Now.AddMilliseconds(1)
            if($null -eq $barrier -or -not [bool]$barrier.ok){return & $deny ('recovery-restore-executor-rollback-required-append-denied:'+[string]$barrier.reason)}
            $barrierAppended=$true
        }
        Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'after-rollback-required-barrier' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store_directory=$StoreDirectory;initial_receipt=$i;barrier_appended=$barrierAppended})

        $fresh=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now.AddMilliseconds(2)
        if($null -eq $fresh -or -not [bool]$fresh.ok){return & $deny ('recovery-restore-executor-fresh-admission-denied:'+[string]$fresh.reason) $false $false $null $barrierAppended}
        $fc=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $fresh.receipt -Now $Now.AddMilliseconds(2)
        if(-not [bool]$fc.ok){return & $deny ('recovery-restore-executor-fresh-admission-invalid:'+[string]$fc.reason) $false $false $null $barrierAppended}
        if([string]$fresh.receipt.phase -cne 'rollback-required' -or -not[bool]$fresh.receipt.requires_recovery_apply -or -not[bool]$fresh.receipt.requires_exact_restore){return & $deny 'recovery-restore-executor-fresh-admission-not-rollback-required' $false $false $null $barrierAppended}
        $cont=Test-CustomAppProductionRecoveryRestoreExecutorAdmissionContinuityV010 -Initial $i -Current $fresh.receipt
        if(-not[bool]$cont.ok){return & $deny ([string]$cont.reason) $false $false $null $barrierAppended}

        Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'before-exact-restore' -Context ([pscustomobject]@{receipt=$fresh.receipt;evidence=$fresh.evidence})
        $restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$fresh.receipt.live_path) -AppBackupPath ([string]$fresh.receipt.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$fresh.receipt.app_backup_tree_sha256) -PersistenceBackupPath ([string]$fresh.receipt.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$fresh.receipt.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if($null -eq $restore -or -not[bool]$restore.ok){return & $deny ('recovery-restore-executor-exact-restore-failed:'+[string]$restore.reason) $true $false $null $barrierAppended}
        Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'after-exact-restore-before-apply-admission' -Context ([pscustomobject]@{receipt=$fresh.receipt;restore=$restore})

        # Re-run the crash-window admission after restoration. It must now observe the exact old live tree and durable persistence.
        $postRestore=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now.AddMilliseconds(3)
        if($null -eq $postRestore -or -not[bool]$postRestore.ok){return & $deny ('recovery-restore-executor-post-restore-admission-denied:'+[string]$postRestore.reason) $true $false $null $barrierAppended}
        $pc=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $postRestore.receipt -Now $Now.AddMilliseconds(3)
        if(-not[bool]$pc.ok){return & $deny ('recovery-restore-executor-post-restore-admission-invalid:'+[string]$pc.reason) $true $false $null $barrierAppended}
        $cont2=Test-CustomAppProductionRecoveryRestoreExecutorAdmissionContinuityV010 -Initial $fresh.receipt -Current $postRestore.receipt
        if(-not[bool]$cont2.ok){return & $deny ([string]$cont2.reason) $true $false $null $barrierAppended}
        if([string]$postRestore.receipt.phase -cne 'rollback-required' -or [string]$postRestore.receipt.live_state -cne 'old-live-exact' -or -not[bool]$postRestore.receipt.current_persistence_matches_durable){return & $deny 'recovery-restore-executor-post-restore-state-not-exact-old-state' $true $false $null $barrierAppended}

        $exe=$null;$apply=$null
        try{$exe=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256;$apply=Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 -ExecutablePath ([string]$exe.path) -TimeoutSeconds $TimeoutSeconds}
        catch{return & $deny ('recovery-restore-executor-recovery-apply-launch-denied:'+[string]$_.Exception.Message) $true $false $null $barrierAppended}
        finally{if($null -ne $exe -and $null -ne $exe.stream){$exe.stream.Dispose()}}
        if($null -eq $apply -or -not[bool]$apply.ok){return & $deny ('recovery-restore-executor-recovery-apply-failed:'+[string]$apply.reason) $true $true $apply $barrierAppended}
        Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'after-recovery-apply-before-postcheck' -Context ([pscustomobject]@{receipt=$postRestore.receipt;apply=$apply})

        try{$appNow=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$postRestore.receipt.live_path);$persistNow=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('recovery-restore-executor-postcheck-read-failed:'+[string]$_.Exception.Message) $true $true $apply $barrierAppended}
        if([string]$appNow.tree_sha256 -cne [string]$postRestore.evidence.app_backup_tree_sha256 -or [int]$appNow.file_count -ne [int]$postRestore.evidence.app_backup_file_count -or [int64]$appNow.total_bytes -ne [int64]$postRestore.evidence.app_backup_total_bytes){return & $deny 'recovery-restore-executor-postcheck-app-tree-mismatch' $true $true $apply $barrierAppended}
        if([string]$persistNow.fingerprint -cne [string]$postRestore.evidence.persistence_fingerprint){return & $deny 'recovery-restore-executor-postcheck-persistence-mismatch' $true $true $apply $barrierAppended}
        Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 -Checkpoint 'before-rollback-complete-append' -Context ([pscustomobject]@{receipt=$postRestore.receipt;apply=$apply;app=$appNow;persistence=$persistNow})

        $complete=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$postRestore.receipt.journal_revision) -ExpectedEntrySha256 ([string]$postRestore.receipt.journal_entry_sha256) -Phase 'rollback-complete' -Now $Now.AddMilliseconds(4)
        if($null -eq $complete -or -not[bool]$complete.ok){return & $deny ('recovery-restore-executor-rollback-complete-append-denied:'+[string]$complete.reason) $true $true $apply $barrierAppended}
        $final=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null -eq $final -or -not[bool]$final.ok -or [string]$final.entry.phase -cne 'rollback-complete' -or ([string]$final.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant() -or [int64]$final.revision -ne [int64]$complete.revision -or ([string]$final.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$complete.entry.entry_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-restore-executor-final-journal-readback-mismatch' $true $true $apply $barrierAppended}

        $result=[pscustomobject]@{
            schema=$CustomAppProductionRecoveryRestoreExecutorSchema;managed_by=$CustomAppProductionRecoveryRestoreExecutorManagedBy;qualified_admission_head=$CustomAppProductionRecoveryRestoreExecutorQualifiedAdmissionHead;qualified_atomic_head=$CustomAppProductionRecoveryRestoreExecutorQualifiedAtomicHead;qualified_apply_head=$CustomAppProductionRecoveryRestoreExecutorQualifiedApplyHead;qualified_journal_head=$CustomAppProductionRecoveryRestoreExecutorQualifiedJournalHead
            status='rollback-complete-verified-awaiting-artifact-retirement';reason='old-app-and-persistence-restored-recovery-apply-verified-and-journal-completed';transaction_id=$ExpectedTransactionId.Trim().ToLowerInvariant();name=[string]$postRestore.receipt.name;source_identity=[string]$postRestore.receipt.source_identity;remote_commit_sha=[string]$postRestore.receipt.remote_commit_sha;consumption_id=[string]$postRestore.receipt.consumption_id;preparation_fingerprint=[string]$postRestore.receipt.preparation_fingerprint;evidence_fingerprint=[string]$postRestore.receipt.evidence_fingerprint
            started_phase=[string]$i.phase;rollback_required_was_appended=$barrierAppended;initial_admission_fingerprint=[string]$i.restore_resume_admission_fingerprint;rollback_admission_fingerprint=[string]$fresh.receipt.restore_resume_admission_fingerprint;post_restore_admission_fingerprint=[string]$postRestore.receipt.restore_resume_admission_fingerprint
            live_path=[string]$postRestore.receipt.live_path;transaction_root=[string]$postRestore.receipt.transaction_root;stage_workspace_path=[string]$postRestore.receipt.stage_workspace_path;app_backup_path=[string]$postRestore.receipt.app_backup_path;persistence_backup_path=[string]$postRestore.receipt.persistence_backup_path;app_tree_sha256=[string]$appNow.tree_sha256;persistence_fingerprint=[string]$persistNow.fingerprint
            spicetify_executable_sha256=$ExpectedSpicetifySha256.Trim().ToLowerInvariant();apply_exit_code=[int]$apply.exit_code;apply_timed_out=[bool]$apply.timed_out;apply_started_at=$apply.started_at.ToUniversalTime().ToString('o');apply_finished_at=$apply.finished_at.ToUniversalTime().ToString('o');rollback_complete_revision=[int64]$final.revision;rollback_complete_entry_sha256=([string]$final.entry.entry_sha256).Trim().ToLowerInvariant()
            restore_performed=$true;recovery_apply_executed=$true;rollback_complete_persisted=$true;requires_recovery_artifact_retirement=$true;requires_future_fresh_revalidation=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
        }
        $result.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $result)
        $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $result
        if(-not[bool]$rc.ok){return & $deny ('recovery-restore-executor-result-self-validation-failed:'+[string]$rc.reason) $true $true $apply $barrierAppended}
        return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;restore_performed=$true;recovery_apply_executed=$true;rollback_complete_persisted=$true;requires_recovery_artifact_retirement=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
    } catch {
        return & $deny ('recovery-restore-executor-unhandled-fail-closed:'+[string]$_.Exception.Message)
    } finally {
        if($null -ne $lock){$lock.Dispose()}
    }
}
