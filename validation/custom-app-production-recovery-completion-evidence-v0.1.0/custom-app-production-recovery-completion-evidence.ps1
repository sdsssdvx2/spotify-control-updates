$CustomAppProductionRecoveryCompletionEvidenceSchema = 1
$CustomAppProductionRecoveryCompletionEvidenceManagedBy = 'custom-app-production-recovery-completion-evidence-v1'
$CustomAppProductionRecoveryCompletionEvidenceQualifiedExecutorHead = 'c3e1f960447ba84d2410af9c37a22a384f2a5436'
$CustomAppProductionRecoveryCompletionEvidenceQualifiedEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'
$CustomAppProductionRecoveryCompletionEvidenceQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'
$CustomAppProductionRecoveryCompletionEvidenceMaxBytes = 4194304

function Get-CustomAppProductionRecoveryCompletionEvidenceSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryCompletionEvidenceSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $jp=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    $store=[string]$jp.store
    $file=Join-Path $store 'recovery-completion-evidence.json'
    $lock=Join-Path $store '.recovery-completion-evidence.lock'
    [void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $file -Label 'recovery completion evidence file')
    [void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $lock -Label 'recovery completion evidence lock')
    return [pscustomobject]@{store=$store;file=$file;lock=$lock}
}

function Open-CustomAppProductionRecoveryCompletionEvidenceLockV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $p=Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    if(Test-Path -LiteralPath $p.lock){
        $i=Get-Item -LiteralPath $p.lock -Force -ErrorAction Stop
        if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'recovery-completion-evidence-lock-path-unsafe'}
    }
    try{return [IO.File]::Open([string]$p.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{throw 'recovery-completion-evidence-lock-busy'}
}

function Get-CustomAppProductionRecoveryCompletionEvidenceMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_executor_head,[string]$Envelope.qualified_evidence_head,[string]$Envelope.qualified_journal_head,
        [string]$Envelope.transaction_id,[string]$Envelope.name,[string]$Envelope.source_identity,[string]$Envelope.remote_commit_sha,[string]$Envelope.consumption_id,[string]$Envelope.preparation_fingerprint,[string]$Envelope.recovery_evidence_fingerprint,[string]$Envelope.executor_result_fingerprint,
        [string]$Envelope.rollback_complete_revision,[string]$Envelope.rollback_complete_entry_sha256,[string]$Envelope.live_path,[string]$Envelope.transaction_root,[string]$Envelope.stage_workspace_path,[string]$Envelope.app_backup_path,[string]$Envelope.persistence_backup_path,
        [string]$Envelope.live_tree_sha256,[string]$Envelope.app_backup_tree_sha256,[string]$Envelope.app_backup_file_count,[string]$Envelope.app_backup_total_bytes,[string]$Envelope.persistence_fingerprint,[string]$Envelope.stage_tree_sha256,
        [string]$Envelope.transaction_status,[string]$Envelope.transaction_old_status,[string]$Envelope.transaction_candidate_status,[string]$Envelope.spicetify_executable_sha256,[string]$Envelope.apply_exit_code,[string]$Envelope.apply_timed_out,[string]$Envelope.apply_started_at,[string]$Envelope.apply_finished_at,
        [string]$Envelope.evidence_written_at,[string]$Envelope.executor_result_embedded,[string]$Envelope.current_old_state_verified,[string]$Envelope.retained_stage_verified,[string]$Envelope.retained_backups_verified,[string]$Envelope.transaction_bounded_verified,[string]$Envelope.retirement_admission_required,[string]$Envelope.requires_future_fresh_revalidation,
        [string]$Envelope.evidence_is_authority,[string]$Envelope.execution_authorized,[string]$Envelope.restore_authorized,[string]$Envelope.apply_authorized,[string]$Envelope.cleanup_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryCompletionEvidenceEnvelopeV010 {
    param([AllowNull()]$Envelope)
    if($null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-envelope-null'}}
    foreach($f in @('schema','managed_by','qualified_executor_head','qualified_evidence_head','qualified_journal_head','transaction_id','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','recovery_evidence_fingerprint','executor_result_fingerprint','rollback_complete_revision','rollback_complete_entry_sha256','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','live_tree_sha256','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_fingerprint','stage_tree_sha256','transaction_status','transaction_old_status','transaction_candidate_status','spicetify_executable_sha256','apply_exit_code','apply_timed_out','apply_started_at','apply_finished_at','evidence_written_at','executor_result_embedded','current_old_state_verified','retained_stage_verified','retained_backups_verified','transaction_bounded_verified','retirement_admission_required','requires_future_fresh_revalidation','evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','executor_result','completion_fingerprint')){if(-not $Envelope.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-field-missing-'+$f)}}}
    if([int]$Envelope.schema -ne $CustomAppProductionRecoveryCompletionEvidenceSchema -or [string]$Envelope.managed_by -cne $CustomAppProductionRecoveryCompletionEvidenceManagedBy -or [string]$Envelope.qualified_executor_head -cne $CustomAppProductionRecoveryCompletionEvidenceQualifiedExecutorHead -or [string]$Envelope.qualified_evidence_head -cne $CustomAppProductionRecoveryCompletionEvidenceQualifiedEvidenceHead -or [string]$Envelope.qualified_journal_head -cne $CustomAppProductionRecoveryCompletionEvidenceQualifiedJournalHead){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-owner-schema-parent-invalid'}}
    foreach($f in @('transaction_id','consumption_id','preparation_fingerprint','recovery_evidence_fingerprint','executor_result_fingerprint','rollback_complete_entry_sha256','live_tree_sha256','app_backup_tree_sha256','persistence_fingerprint','stage_tree_sha256','spicetify_executable_sha256','completion_fingerprint')){if(-not(Test-CustomAppProductionRecoveryCompletionEvidenceSha256V010(([string]$Envelope.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-invalid-'+$f)}}}
    if(([string]$Envelope.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-remote-commit-invalid'}}
    if([string]$Envelope.transaction_status -notin @('already-absent','present-verified')){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-transaction-status-invalid'}}
    if([string]$Envelope.transaction_status -ceq 'present-verified'){
        if([string]$Envelope.transaction_old_status -cne 'present-verified' -or [string]$Envelope.transaction_candidate_status -notin @('absent','present-verified')){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-transaction-shape-invalid'}}
    } elseif([string]$Envelope.transaction_old_status -cne 'absent' -or [string]$Envelope.transaction_candidate_status -cne 'absent'){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-absent-transaction-shape-invalid'}}
    try{if([int64]$Envelope.rollback_complete_revision -lt 1 -or [int]$Envelope.apply_exit_code -ne 0 -or [int]$Envelope.app_backup_file_count -lt 1 -or [int64]$Envelope.app_backup_total_bytes -lt 1){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-numeric-contract-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-numeric-field-invalid'}}
    if([bool]$Envelope.apply_timed_out){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-apply-timeout-invalid'}}
    foreach($f in @('executor_result_embedded','current_old_state_verified','retained_stage_verified','retained_backups_verified','transaction_bounded_verified','retirement_admission_required','requires_future_fresh_revalidation')){if(-not [bool]$Envelope.$f){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-required-flag-false-'+$f)}}}
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Envelope.$f){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$finish=[DateTimeOffset]::MinValue;$written=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Envelope.apply_started_at,[ref]$start) -or -not[DateTimeOffset]::TryParse([string]$Envelope.apply_finished_at,[ref]$finish) -or -not[DateTimeOffset]::TryParse([string]$Envelope.evidence_written_at,[ref]$written) -or $finish -lt $start -or $written -lt $finish.AddMinutes(-5)){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-time-invalid'}}
    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $Envelope.executor_result
    if(-not [bool]$rc.ok){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-executor-result-invalid:'+[string]$rc.reason)}}
    $r=$Envelope.executor_result
    foreach($pair in @(
        @('transaction_id','transaction_id'),@('name','name'),@('source_identity','source_identity'),@('remote_commit_sha','remote_commit_sha'),@('consumption_id','consumption_id'),@('preparation_fingerprint','preparation_fingerprint'),@('recovery_evidence_fingerprint','evidence_fingerprint'),@('executor_result_fingerprint','result_fingerprint'),@('rollback_complete_revision','rollback_complete_revision'),@('rollback_complete_entry_sha256','rollback_complete_entry_sha256'),@('live_path','live_path'),@('transaction_root','transaction_root'),@('stage_workspace_path','stage_workspace_path'),@('app_backup_path','app_backup_path'),@('persistence_backup_path','persistence_backup_path'),@('live_tree_sha256','app_tree_sha256'),@('persistence_fingerprint','persistence_fingerprint'),@('spicetify_executable_sha256','spicetify_executable_sha256'),@('apply_exit_code','apply_exit_code'),@('apply_timed_out','apply_timed_out'),@('apply_started_at','apply_started_at'),@('apply_finished_at','apply_finished_at')
    )){if(([string]$Envelope.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$r.($pair[1])).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-completion-evidence-executor-continuity-mismatch-'+$pair[0])}}}
    $expected=Get-CustomAppProductionRecoveryCompletionEvidenceSha256V010 (Get-CustomAppProductionRecoveryCompletionEvidenceMaterialV010 -Envelope $Envelope)
    if(([string]$Envelope.completion_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-completion-evidence-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-completion-evidence-envelope-valid-zero-authority';transaction_id=([string]$Envelope.transaction_id).Trim().ToLowerInvariant();completion_fingerprint=$expected}
}

function Read-CustomAppProductionRecoveryCompletionEvidenceV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryCompletionEvidenceSha256V010 $tx)){return & $deny 'recovery-completion-evidence-transaction-id-invalid'}
    $lock=$null
    try{$lock=Open-CustomAppProductionRecoveryCompletionEvidenceLockV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ([string]$_.Exception.Message)}
    try{
        $p=Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if(-not(Test-Path -LiteralPath $p.file -PathType Leaf)){return & $deny 'recovery-completion-evidence-file-missing'}
        $item=Get-Item -LiteralPath $p.file -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){return & $deny 'recovery-completion-evidence-file-reparse-point'}
        if([int64]$item.Length -gt $CustomAppProductionRecoveryCompletionEvidenceMaxBytes){return & $deny 'recovery-completion-evidence-file-exceeds-4-MiB'}
        try{$obj=[IO.File]::ReadAllText([string]$p.file,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json}catch{return & $deny 'recovery-completion-evidence-JSON-invalid'}
        $ck=Test-CustomAppProductionRecoveryCompletionEvidenceEnvelopeV010 -Envelope $obj;if(-not[bool]$ck.ok){return & $deny ([string]$ck.reason)}
        if(([string]$obj.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-completion-evidence-transaction-mismatch'}
        $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null-eq$j -or -not[bool]$j.ok -or $null-eq$j.entry){return & $deny 'recovery-completion-evidence-journal-read-invalid'}
        if(([string]$j.transaction_id).Trim().ToLowerInvariant() -cne $tx -or [string]$j.entry.phase -cne 'rollback-complete' -or [int64]$j.revision -ne [int64]$obj.rollback_complete_revision -or ([string]$j.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$obj.rollback_complete_entry_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-evidence-journal-anchor-mismatch'}
        return [pscustomobject]@{ok=$true;reason='recovery-completion-evidence-reloaded-and-journal-anchored';path=[string]$p.file;envelope=$obj;completion_fingerprint=[string]$obj.completion_fingerprint;reloaded_from_persistent_store=$true;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
    } catch {return & $deny ('recovery-completion-evidence-read-failed:'+[string]$_.Exception.Message)}
    finally{if($null-ne$lock){$lock.Dispose()}}
}

function Write-CustomAppProductionRecoveryCompletionEvidenceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$ExecutorResult,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyAllowedRoot,[Parameter(Mandatory=$true)][string]$SpicetifyPath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;read_after_write_verified=$false;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryCompletionEvidenceSha256V010 $tx)){return & $deny 'recovery-completion-evidence-transaction-id-invalid'}
    $erc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $ExecutorResult;if(-not[bool]$erc.ok){return & $deny ('recovery-completion-evidence-executor-result-invalid:'+[string]$erc.reason)}
    if(([string]$ExecutorResult.transaction_id).Trim().ToLowerInvariant() -cne $tx -or -not[bool]$ExecutorResult.rollback_complete_persisted -or -not[bool]$ExecutorResult.requires_recovery_artifact_retirement){return & $deny 'recovery-completion-evidence-executor-result-not-retirement-pending'}
    if(([string]$ExecutorResult.spicetify_executable_sha256).Trim().ToLowerInvariant() -cne $ExpectedSpicetifySha256.Trim().ToLowerInvariant()){return & $deny 'recovery-completion-evidence-spicetify-pin-input-mismatch'}

    $lock=$null;$written=$false;$envelope=$null;$path=$null
    try{$lock=Open-CustomAppProductionRecoveryCompletionEvidenceLockV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ([string]$_.Exception.Message)}
    try{
        $p=Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$path=[string]$p.file
        if(Test-Path -LiteralPath $path){return & $deny 'recovery-completion-evidence-already-exists-replay-denied'}
        $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null-eq$j -or -not[bool]$j.ok -or $null-eq$j.entry){return & $deny 'recovery-completion-evidence-journal-read-invalid'}
        if(([string]$j.transaction_id).Trim().ToLowerInvariant() -cne $tx -or [string]$j.entry.phase -cne 'rollback-complete' -or [int64]$j.revision -ne [int64]$ExecutorResult.rollback_complete_revision -or ([string]$j.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$ExecutorResult.rollback_complete_entry_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-evidence-executor-journal-anchor-mismatch'}

        $re=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
        if($null-eq$re -or -not[bool]$re.ok){return & $deny ('recovery-completion-evidence-recovery-evidence-read-denied:'+[string]$re.reason)}
        $e=$re.envelope
        foreach($pair in @(@('name','name'),@('source_identity','source_identity'),@('remote_commit_sha','remote_commit_sha'),@('consumption_id','consumption_id'),@('preparation_fingerprint','preparation_fingerprint'),@('evidence_fingerprint','evidence_fingerprint'),@('live_path','live_path'),@('transaction_root','transaction_root'),@('stage_workspace_path','stage_workspace_path'),@('app_backup_path','app_backup_path'),@('persistence_backup_path','persistence_backup_path'),@('persistence_fingerprint','persistence_fingerprint'))){if(([string]$ExecutorResult.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$e.($pair[1])).Trim().ToLowerInvariant()){return & $deny ('recovery-completion-evidence-durable-continuity-mismatch-'+$pair[0])}}
        if(([string]$ExecutorResult.app_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$e.app_backup_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-evidence-restored-app-tree-not-durable-old-tree'}

        $stage=Test-CustomAppProductionRecoveryRestoreResumeStageV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$stage.ok){return & $deny ('recovery-completion-evidence-stage-invalid:'+[string]$stage.reason)}
        $backups=Test-CustomAppProductionRecoveryRestoreResumeBackupsV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$backups.ok){return & $deny ('recovery-completion-evidence-backups-invalid:'+[string]$backups.reason)}
        $txn=Get-CustomAppProductionRecoveryRestoreResumeTransactionStateV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$txn.ok){return & $deny ('recovery-completion-evidence-transaction-invalid:'+[string]$txn.reason)}
        if([string]$txn.status -ceq 'present-verified' -and ([string]$txn.old_status -cne 'present-verified' -or [string]$txn.candidate_status -notin @('absent','present-verified'))){return & $deny 'recovery-completion-evidence-transaction-present-shape-invalid'}

        try{$live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$e.live_path);$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('recovery-completion-evidence-current-state-read-failed:'+[string]$_.Exception.Message)}
        if([string]$live.tree_sha256 -cne [string]$e.app_backup_tree_sha256 -or [int]$live.file_count -ne [int]$e.app_backup_file_count -or [int64]$live.total_bytes -ne [int64]$e.app_backup_total_bytes){return & $deny 'recovery-completion-evidence-current-live-not-exact-old-state'}
        if([string]$persist.fingerprint -cne [string]$e.persistence_fingerprint){return & $deny 'recovery-completion-evidence-current-persistence-not-exact-old-state'}

        $exe=$null
        try{$exe=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256;if(([string]$exe.sha256).Trim().ToLowerInvariant() -cne ([string]$ExecutorResult.spicetify_executable_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-completion-evidence-spicetify-result-pin-mismatch'}}
        catch{return & $deny ('recovery-completion-evidence-spicetify-recheck-denied:'+[string]$_.Exception.Message)}
        finally{if($null-ne$exe -and $null-ne$exe.stream){$exe.stream.Dispose()}}

        $embedded=(($ExecutorResult|ConvertTo-Json -Depth 60)|ConvertFrom-Json)
        $envelope=[pscustomobject]@{
            schema=$CustomAppProductionRecoveryCompletionEvidenceSchema;managed_by=$CustomAppProductionRecoveryCompletionEvidenceManagedBy;qualified_executor_head=$CustomAppProductionRecoveryCompletionEvidenceQualifiedExecutorHead;qualified_evidence_head=$CustomAppProductionRecoveryCompletionEvidenceQualifiedEvidenceHead;qualified_journal_head=$CustomAppProductionRecoveryCompletionEvidenceQualifiedJournalHead
            transaction_id=$tx;name=[string]$e.name;source_identity=[string]$e.source_identity;remote_commit_sha=[string]$e.remote_commit_sha;consumption_id=[string]$e.consumption_id;preparation_fingerprint=[string]$e.preparation_fingerprint;recovery_evidence_fingerprint=[string]$e.evidence_fingerprint;executor_result_fingerprint=[string]$ExecutorResult.result_fingerprint
            rollback_complete_revision=[int64]$j.revision;rollback_complete_entry_sha256=([string]$j.entry.entry_sha256).Trim().ToLowerInvariant();live_path=[string]$e.live_path;transaction_root=[string]$e.transaction_root;stage_workspace_path=[string]$e.stage_workspace_path;app_backup_path=[string]$e.app_backup_path;persistence_backup_path=[string]$e.persistence_backup_path
            live_tree_sha256=[string]$live.tree_sha256;app_backup_tree_sha256=[string]$e.app_backup_tree_sha256;app_backup_file_count=[int]$e.app_backup_file_count;app_backup_total_bytes=[int64]$e.app_backup_total_bytes;persistence_fingerprint=[string]$persist.fingerprint;stage_tree_sha256=[string]$e.stage_tree_sha256
            transaction_status=[string]$txn.status;transaction_old_status=[string]$txn.old_status;transaction_candidate_status=[string]$txn.candidate_status;spicetify_executable_sha256=[string]$ExecutorResult.spicetify_executable_sha256;apply_exit_code=[int]$ExecutorResult.apply_exit_code;apply_timed_out=[bool]$ExecutorResult.apply_timed_out;apply_started_at=[string]$ExecutorResult.apply_started_at;apply_finished_at=[string]$ExecutorResult.apply_finished_at
            evidence_written_at=$Now.ToUniversalTime().ToString('o');executor_result_embedded=$true;current_old_state_verified=$true;retained_stage_verified=$true;retained_backups_verified=$true;transaction_bounded_verified=$true;retirement_admission_required=$true;requires_future_fresh_revalidation=$true
            evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;executor_result=$embedded;completion_fingerprint=$null
        }
        $envelope.completion_fingerprint=Get-CustomAppProductionRecoveryCompletionEvidenceSha256V010 (Get-CustomAppProductionRecoveryCompletionEvidenceMaterialV010 -Envelope $envelope)
        $ec=Test-CustomAppProductionRecoveryCompletionEvidenceEnvelopeV010 -Envelope $envelope;if(-not[bool]$ec.ok){return & $deny ('recovery-completion-evidence-self-validation-failed:'+[string]$ec.reason)}
        $json=$envelope|ConvertTo-Json -Depth 60 -Compress;$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
        if($bytes.Length -gt $CustomAppProductionRecoveryCompletionEvidenceMaxBytes){return & $deny 'recovery-completion-evidence-serialized-exceeds-4-MiB'}
        $tmp=Join-Path ([string]$p.store) ('.recovery-completion-evidence-'+[Guid]::NewGuid().ToString('N')+'.tmp')
        $fs=$null
        try{$fs=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true);$fs.Dispose();$fs=$null;[IO.File]::Move($tmp,$path);$written=$true}
        catch{return & $deny ('recovery-completion-evidence-persist-failed:'+[string]$_.Exception.Message)}
        finally{if($null-ne$fs){$fs.Dispose()};if(Test-Path -LiteralPath $tmp){try{[IO.File]::Delete($tmp)}catch{}}}
    } catch {return & $deny ('recovery-completion-evidence-write-failed:'+[string]$_.Exception.Message)}
    finally{if($null-ne$lock){$lock.Dispose()}}
    if(-not$written){return & $deny 'recovery-completion-evidence-not-written'}
    $read=Read-CustomAppProductionRecoveryCompletionEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$read -or -not[bool]$read.ok -or ([string]$read.completion_fingerprint).Trim().ToLowerInvariant() -cne ([string]$envelope.completion_fingerprint).Trim().ToLowerInvariant()){return & $deny ('recovery-completion-evidence-read-after-write-failed:'+[string]$read.reason)}
    return [pscustomobject]@{ok=$true;reason='recovery-completion-evidence-persisted-readback-verified';path=$path;envelope=$read.envelope;completion_fingerprint=[string]$read.completion_fingerprint;persisted=$true;read_after_write_verified=$true;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}
