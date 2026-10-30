$CustomAppProductionRecoveryArtifactRetirementExecutorSchema = 1
$CustomAppProductionRecoveryArtifactRetirementExecutorManagedBy = 'custom-app-production-recovery-artifact-retirement-executor-v1'
$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedAdmissionHead = '16cac85b7bde1b652be67e8d657136409ec7f8b9'
$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedCleanupHead = '67458cbb96b5d1ed92e26c2b81debd6894044749'

function Get-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Open-CustomAppProductionRecoveryArtifactRetirementExecutorLockV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    $path=Join-Path ([string]$paths.store) '.artifact-retirement-executor.lock'
    if(Test-Path -LiteralPath $path){
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-artifact-retirement-executor-lock-path-unsafe'}
    }
    try{return [IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{throw 'recovery-artifact-retirement-executor-lock-busy'}
}
function Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Validation harness may replace this no-op to inject bounded fixture races/crashes.
}
function Get-CustomAppProductionRecoveryArtifactRetirementExecutorResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_admission_head,[string]$Result.qualified_cleanup_head,
        [string]$Result.status,[string]$Result.reason,[string]$Result.transaction_id,[string]$Result.name,[string]$Result.source_identity,[string]$Result.remote_commit_sha,[string]$Result.consumption_id,[string]$Result.preparation_fingerprint,[string]$Result.evidence_fingerprint,[string]$Result.restore_result_fingerprint,
        [string]$Result.phase,[string]$Result.journal_revision,[string]$Result.journal_entry_sha256,[string]$Result.initial_admission_fingerprint,[string]$Result.final_admission_fingerprint,
        [string]$Result.transaction_action,[string]$Result.stage_action,[string]$Result.app_backup_action,[string]$Result.persistence_backup_action,
        [string]$Result.live_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.completed_at,[string]$Result.retirement_performed,[string]$Result.initially_already_complete,[string]$Result.artifact_retirement_complete,[string]$Result.journal_retained,[string]$Result.recovery_evidence_retained,[string]$Result.requires_new_update_permit,[string]$Result.requires_future_fresh_revalidation,
        [string]$Result.result_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryArtifactRetirementExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-null'}}
    foreach($f in @('schema','managed_by','qualified_admission_head','qualified_cleanup_head','status','reason','transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','evidence_fingerprint','restore_result_fingerprint','phase','journal_revision','journal_entry_sha256','initial_admission_fingerprint','final_admission_fingerprint','transaction_action','stage_action','app_backup_action','persistence_backup_action','live_tree_sha256','persistence_fingerprint','completed_at','retirement_performed','initially_already_complete','artifact_retirement_complete','journal_retained','recovery_evidence_retained','requires_new_update_permit','requires_future_fresh_revalidation','result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','result_fingerprint')){
        if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-executor-result-field-missing-'+$f)}}
    }
    if([int]$Result.schema-ne1 -or [string]$Result.managed_by-cne$CustomAppProductionRecoveryArtifactRetirementExecutorManagedBy -or [string]$Result.qualified_admission_head-cne$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedAdmissionHead -or [string]$Result.qualified_cleanup_head-cne$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedCleanupHead){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-owner-schema-parent-invalid'}}
    if([string]$Result.status-cne'recovery-artifacts-retired-live-and-persistence-reverified' -or [string]$Result.reason-cne'bounded-recovery-artifact-retirement-complete' -or [string]$Result.phase-cne'rollback-complete'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-status-invalid'}}
    foreach($f in @('transaction_id','consumption_id','preparation_fingerprint','evidence_fingerprint','restore_result_fingerprint','journal_entry_sha256','initial_admission_fingerprint','final_admission_fingerprint','live_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-executor-result-invalid-'+$f)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-remote-commit-invalid'}}
    foreach($f in @('transaction_action','stage_action','app_backup_action','persistence_backup_action')){if([string]$Result.$f-notin@('deleted-now','already-absent')){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-executor-result-action-invalid-'+$f)}}}
    if(-not[bool]$Result.artifact_retirement_complete -or -not[bool]$Result.journal_retained -or -not[bool]$Result.recovery_evidence_retained -or -not[bool]$Result.requires_new_update_permit -or -not[bool]$Result.requires_future_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-lifecycle-contract-invalid'}}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-executor-result-authority-escaped-'+$f)}}
    $didDelete=([string]$Result.transaction_action-ceq'deleted-now' -or [string]$Result.stage_action-ceq'deleted-now' -or [string]$Result.app_backup_action-ceq'deleted-now' -or [string]$Result.persistence_backup_action-ceq'deleted-now')
    if([bool]$Result.retirement_performed-ne[bool]$didDelete){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-action-semantics-drift'}}
    if([bool]$Result.initially_already_complete -and $didDelete){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-complete-state-mutated'}}
    $when=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Result.completed_at,[ref]$when)){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-time-invalid'}}
    try{if([int64]$Result.journal_revision-lt1){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-journal-revision-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-journal-revision-invalid'}}
    $expected=Get-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementExecutorResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-artifact-retirement-executor-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-artifact-retirement-executor-result-valid-zero-authority';transaction_id=([string]$Result.transaction_id).Trim().ToLowerInvariant();result_fingerprint=$expected}
}
function Test-CustomAppProductionRecoveryArtifactRetirementExecutorAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$Initial,[Parameter(Mandatory=$true)]$Current)
    foreach($f in @('transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','evidence_fingerprint','restore_result_fingerprint','phase','journal_revision','journal_entry_sha256','live_tree_sha256','persistence_fingerprint')){
        if(([string]$Initial.$f).Trim().ToLowerInvariant()-cne([string]$Current.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-artifact-retirement-executor-admission-continuity-mismatch-'+$f)}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-artifact-retirement-executor-admission-continuity-exact'}
}
function Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$RestoreExecutorResult,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[string]$TransactionAction='already-absent',[string]$StageAction='already-absent',[string]$AppAction='already-absent',[string]$PersistenceAction='already-absent')[pscustomobject]@{ok=$false;reason=$Reason;transaction_action=$TransactionAction;stage_action=$StageAction;app_backup_action=$AppAction;persistence_backup_action=$PersistenceAction;artifact_retirement_complete=$false;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $lock=$null
    try{$lock=Open-CustomAppProductionRecoveryArtifactRetirementExecutorLockV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ([string]$_.Exception.Message)}
    try{
        $initial=Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -RestoreExecutorResult $RestoreExecutorResult -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
        if($null-eq$initial-or-not[bool]$initial.ok){return & $deny ('recovery-artifact-retirement-executor-initial-admission-denied:'+[string]$initial.reason)}
        $ic=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $initial.receipt -Now $Now
        if(-not[bool]$ic.ok){return & $deny ('recovery-artifact-retirement-executor-initial-admission-invalid:'+[string]$ic.reason)}
        $anchor=$initial.receipt
        $actions=[ordered]@{transaction='already-absent';stage='already-absent';app_backup='already-absent';persistence_backup='already-absent'}
        $initiallyComplete=[bool]$anchor.retirement_already_complete
        $specs=@(
            [pscustomobject]@{key='transaction';status='transaction_status';artifact='transaction';path='path';root='root';pattern='^\.spotify-control-txn-[0-9a-fA-F]{32}$'},
            [pscustomobject]@{key='stage';status='stage_status';artifact='stage';path='delete_path';root='root';pattern='^[0-9a-fA-F]{32}$'},
            [pscustomobject]@{key='app_backup';status='app_backup_status';artifact='app_backup';path='delete_path';root='root';pattern='^[0-9a-fA-F]{32}$'},
            [pscustomobject]@{key='persistence_backup';status='persistence_backup_status';artifact='persistence_backup';path='delete_path';root='root';pattern='^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$'}
        )
        $step=0
        foreach($s in $specs){
            $step++
            Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorValidationHookV010 -Checkpoint ('before-'+[string]$s.key+'-retirement') -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store_directory=$StoreDirectory;anchor=$anchor;actions=$actions})
            $at=$Now.AddMilliseconds($step*10)
            $fresh=Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -RestoreExecutorResult $RestoreExecutorResult -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $at
            if($null-eq$fresh-or-not[bool]$fresh.ok){return & $deny ('recovery-artifact-retirement-executor-pre-delete-admission-denied-'+[string]$s.key+':' + [string]$fresh.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            $fc=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $fresh.receipt -Now $at
            if(-not[bool]$fc.ok){return & $deny ('recovery-artifact-retirement-executor-pre-delete-admission-invalid-'+[string]$s.key+':' + [string]$fc.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            $cont=Test-CustomAppProductionRecoveryArtifactRetirementExecutorAdmissionContinuityV010 -Initial $anchor -Current $fresh.receipt
            if(-not[bool]$cont.ok){return & $deny ([string]$cont.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            $status=[string]$fresh.receipt.([string]$s.status)
            if($status-ceq'present-verified'){
                $artifact=$fresh.artifacts.([string]$s.artifact)
                if($null-eq$artifact){return & $deny ('recovery-artifact-retirement-executor-artifact-evidence-missing-'+[string]$s.key) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
                try{$actions[[string]$s.key]=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$artifact.([string]$s.path)) -ExpectedRoot ([string]$artifact.([string]$s.root)) -ExpectedNamePattern ([string]$s.pattern) -Label ('recovery-'+[string]$s.key)}
                catch{return & $deny ('recovery-artifact-retirement-executor-delete-failed-'+[string]$s.key+':' + [string]$_.Exception.Message) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            } elseif($status-ceq'already-absent'){$actions[[string]$s.key]='already-absent'}
            else{return & $deny ('recovery-artifact-retirement-executor-unexpected-status-'+[string]$s.key+':' + $status) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorValidationHookV010 -Checkpoint ('after-'+[string]$s.key+'-retirement') -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store_directory=$StoreDirectory;anchor=$anchor;actions=$actions})
            $postAt=$at.AddMilliseconds(1)
            $post=Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -RestoreExecutorResult $RestoreExecutorResult -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $postAt
            if($null-eq$post-or-not[bool]$post.ok){return & $deny ('recovery-artifact-retirement-executor-post-delete-admission-denied-'+[string]$s.key+':' + [string]$post.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            $pc=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $post.receipt -Now $postAt
            if(-not[bool]$pc.ok){return & $deny ('recovery-artifact-retirement-executor-post-delete-admission-invalid-'+[string]$s.key+':' + [string]$pc.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            $cont=Test-CustomAppProductionRecoveryArtifactRetirementExecutorAdmissionContinuityV010 -Initial $anchor -Current $post.receipt
            if(-not[bool]$cont.ok){return & $deny ([string]$cont.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
            if([string]$post.receipt.([string]$s.status)-cne'already-absent'){return & $deny ('recovery-artifact-retirement-executor-artifact-remained-'+[string]$s.key) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
        }
        $finalAt=$Now.AddMilliseconds(100)
        $final=Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -RestoreExecutorResult $RestoreExecutorResult -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $finalAt
        if($null-eq$final-or-not[bool]$final.ok){return & $deny ('recovery-artifact-retirement-executor-final-admission-denied:'+[string]$final.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
        $finalCheck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $final.receipt -Now $finalAt
        if(-not[bool]$finalCheck.ok){return & $deny ('recovery-artifact-retirement-executor-final-admission-invalid:'+[string]$finalCheck.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
        $cont=Test-CustomAppProductionRecoveryArtifactRetirementExecutorAdmissionContinuityV010 -Initial $anchor -Current $final.receipt
        if(-not[bool]$cont.ok){return & $deny ([string]$cont.reason) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
        if([bool]$final.receipt.retirement_needed -or [bool]$final.receipt.retirement_eligible -or -not[bool]$final.receipt.retirement_already_complete -or [bool]$final.receipt.requires_bounded_artifact_retirement){return & $deny 'recovery-artifact-retirement-executor-final-state-not-complete' $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}
        foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){if([string]$final.receipt.$f-cne'already-absent'){return & $deny ('recovery-artifact-retirement-executor-final-artifact-not-absent-'+$f) $actions.transaction $actions.stage $actions.app_backup $actions.persistence_backup}}
        $performed=($actions.transaction-ceq'deleted-now' -or $actions.stage-ceq'deleted-now' -or $actions.app_backup-ceq'deleted-now' -or $actions.persistence_backup-ceq'deleted-now')
        $result=[pscustomobject]@{
            schema=$CustomAppProductionRecoveryArtifactRetirementExecutorSchema;managed_by=$CustomAppProductionRecoveryArtifactRetirementExecutorManagedBy;qualified_admission_head=$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedAdmissionHead;qualified_cleanup_head=$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedCleanupHead
            status='recovery-artifacts-retired-live-and-persistence-reverified';reason='bounded-recovery-artifact-retirement-complete';transaction_id=[string]$final.receipt.transaction_id;name=[string]$final.receipt.name;source_identity=[string]$final.receipt.source_identity;remote_commit_sha=[string]$final.receipt.remote_commit_sha;consumption_id=[string]$final.receipt.consumption_id;preparation_fingerprint=[string]$final.receipt.preparation_fingerprint;evidence_fingerprint=[string]$final.receipt.evidence_fingerprint;restore_result_fingerprint=[string]$final.receipt.restore_result_fingerprint
            phase='rollback-complete';journal_revision=[int64]$final.receipt.journal_revision;journal_entry_sha256=[string]$final.receipt.journal_entry_sha256;initial_admission_fingerprint=[string]$anchor.receipt_fingerprint;final_admission_fingerprint=[string]$final.receipt.receipt_fingerprint
            transaction_action=[string]$actions.transaction;stage_action=[string]$actions.stage;app_backup_action=[string]$actions.app_backup;persistence_backup_action=[string]$actions.persistence_backup;live_tree_sha256=[string]$final.receipt.live_tree_sha256;persistence_fingerprint=[string]$final.receipt.persistence_fingerprint;completed_at=$finalAt.ToUniversalTime().ToString('o')
            retirement_performed=[bool]$performed;initially_already_complete=$initiallyComplete;artifact_retirement_complete=$true;journal_retained=$true;recovery_evidence_retained=$true;requires_new_update_permit=$true;requires_future_fresh_revalidation=$true
            result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
        }
        $result.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementExecutorResultMaterialV010 -Result $result)
        return [pscustomobject]@{ok=$true;reason='bounded-recovery-artifact-retirement-complete';result=$result;final_admission=$final.receipt}
    }finally{if($null-ne$lock){$lock.Dispose()}}
}
