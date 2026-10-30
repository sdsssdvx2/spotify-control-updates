$CustomAppProductionRecoveryRestoreResumeAdmissionSchema = 1
$CustomAppProductionRecoveryRestoreResumeAdmissionManagedBy = 'custom-app-production-recovery-restore-resume-admission-v1'
$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedCleanupResumeHead = 'd3969a746ed1736fe93586bd025116c2526fbff5'
$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'
$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'

function Get-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'restore-resume-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    return (Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 $A).Equals((Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 $B),[StringComparison]::OrdinalIgnoreCase)
}

function Test-CustomAppProductionRecoveryRestoreResumeStageV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try {
        $workspace=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.stage_workspace_path) -Label 'restore-resume stage workspace' -RequireExisting:$true
        $stageRoot=Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 (Get-CustomAppStageWorkspaceRootV010)
        if(-not ([IO.Path]::GetDirectoryName($workspace)).Equals($stageRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($workspace) -notmatch '^[0-9a-fA-F]{32}$'){
            return [pscustomobject]@{ok=$false;reason='restore-resume-stage-workspace-path-shape-invalid'}
        }
        if(-not (Test-Path -LiteralPath $workspace -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-stage-workspace-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $workspace -Label 'restore-resume stage workspace')
        $stage=Join-Path $workspace 'stage'
        if(-not (Test-Path -LiteralPath $stage -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-stage-directory-missing'}}
        $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Envelope.name) -AppPath $stage
        if(-not [bool]$runtime.safe -or -not [bool]$runtime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -or [string]$runtime.tree_sha256 -cne [string]$Envelope.stage_tree_sha256){
            return [pscustomobject]@{ok=$false;reason='restore-resume-stage-tree-mismatch'}
        }
        return [pscustomobject]@{ok=$true;reason='restore-resume-stage-exact';status='present-verified';workspace=$workspace;stage=$stage;tree_sha256=[string]$runtime.tree_sha256}
    } catch {
        return [pscustomobject]@{ok=$false;reason=('restore-resume-stage-read-failed:'+[string]$_.Exception.Message)}
    }
}

function Test-CustomAppProductionRecoveryRestoreResumeBackupsV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try {
        $app=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.app_backup_path) -Label 'restore-resume app backup' -RequireExisting:$true
        if(-not (Test-Path -LiteralPath $app -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-app-backup-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $app -Label 'restore-resume app backup')
        $snap=Get-CustomAppUpdateTreeSnapshotV010 -Root $app
        if([string]$snap.tree_sha256 -cne [string]$Envelope.app_backup_tree_sha256 -or [int]$snap.file_count -ne [int]$Envelope.app_backup_file_count -or [int64]$snap.total_bytes -ne [int64]$Envelope.app_backup_total_bytes){
            return [pscustomobject]@{ok=$false;reason='restore-resume-app-backup-integrity-mismatch'}
        }

        $persist=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.persistence_backup_path) -Label 'restore-resume persistence backup' -RequireExisting:$true
        if(-not (Test-Path -LiteralPath $persist -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-persistence-backup-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $persist -Label 'restore-resume persistence backup')
        $pc=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $persist -ExpectedFingerprint ([string]$Envelope.persistence_fingerprint)
        if(-not [bool]$pc.ok){return [pscustomobject]@{ok=$false;reason=('restore-resume-persistence-backup-invalid:'+[string]$pc.reason)}}
        return [pscustomobject]@{ok=$true;reason='restore-resume-backups-exact';app_path=$app;app_tree_sha256=[string]$snap.tree_sha256;app_file_count=[int]$snap.file_count;app_total_bytes=[int64]$snap.total_bytes;persistence_path=$persist;persistence_fingerprint=[string]$Envelope.persistence_fingerprint}
    } catch {
        return [pscustomobject]@{ok=$false;reason=('restore-resume-backup-read-failed:'+[string]$_.Exception.Message)}
    }
}

function Get-CustomAppProductionRecoveryRestoreResumeLiveStateV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try {
        $live=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.live_path) -Label 'restore-resume live'
        if(-not (Test-Path -LiteralPath $live)){return [pscustomobject]@{ok=$true;reason='restore-resume-live-absent';state='absent-after-live-move';path=$live;tree_sha256=''}}
        if(-not (Test-Path -LiteralPath $live -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-live-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $live -Label 'restore-resume live')
        $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Envelope.name) -AppPath $live
        if(-not [bool]$runtime.safe -or -not [bool]$runtime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime)){
            return [pscustomobject]@{ok=$false;reason='restore-resume-live-runtime-unsafe'}
        }
        $tree=([string]$runtime.tree_sha256).Trim().ToLowerInvariant()
        if($tree -ceq ([string]$Envelope.live_tree_sha256).Trim().ToLowerInvariant()){
            return [pscustomobject]@{ok=$true;reason='restore-resume-live-old-exact';state='old-live-exact';path=$live;tree_sha256=$tree}
        }
        if($tree -ceq ([string]$Envelope.stage_tree_sha256).Trim().ToLowerInvariant()){
            return [pscustomobject]@{ok=$true;reason='restore-resume-live-candidate-exact';state='candidate-live-exact';path=$live;tree_sha256=$tree}
        }
        return [pscustomobject]@{ok=$false;reason='restore-resume-live-tree-unrecognized'}
    } catch {
        return [pscustomobject]@{ok=$false;reason=('restore-resume-live-read-failed:'+[string]$_.Exception.Message)}
    }
}

function Get-CustomAppProductionRecoveryRestoreResumeTransactionStateV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try {
        $txn=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.transaction_root) -Label 'restore-resume transaction root'
        $live=Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 ([string]$Envelope.live_path)
        $parent=Get-CustomAppProductionRecoveryRestoreResumeCanonicalPathV010 ([IO.Path]::GetDirectoryName($live))
        if(-not ([IO.Path]::GetDirectoryName($txn)).Equals($parent,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($txn) -notmatch '^\.spotify-control-txn-[0-9a-fA-F]{32}$'){
            return [pscustomobject]@{ok=$false;reason='restore-resume-transaction-root-path-shape-invalid'}
        }
        if(-not (Test-Path -LiteralPath $txn)){
            return [pscustomobject]@{ok=$true;reason='restore-resume-transaction-root-absent';status='already-absent';path=$txn;root=$parent;old_status='absent';candidate_status='absent'}
        }
        if(-not (Test-Path -LiteralPath $txn -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-transaction-root-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $txn -Label 'restore-resume transaction root')
        $children=@(Get-ChildItem -LiteralPath $txn -Force -ErrorAction Stop)
        foreach($child in $children){
            if(-not $child.PSIsContainer -or [string]$child.Name -notin @('old-live','candidate')){
                return [pscustomobject]@{ok=$false;reason='restore-resume-transaction-root-contents-invalid'}
            }
        }

        $old=Join-Path $txn 'old-live'
        $candidate=Join-Path $txn 'candidate'
        $oldStatus='absent'
        $candidateStatus='absent'
        if(Test-Path -LiteralPath $old){
            if(-not (Test-Path -LiteralPath $old -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-old-live-not-directory'}}
            $snap=Get-CustomAppUpdateTreeSnapshotV010 -Root $old
            if([string]$snap.tree_sha256 -cne [string]$Envelope.app_backup_tree_sha256 -or [int]$snap.file_count -ne [int]$Envelope.app_backup_file_count -or [int64]$snap.total_bytes -ne [int64]$Envelope.app_backup_total_bytes){
                return [pscustomobject]@{ok=$false;reason='restore-resume-old-live-tree-mismatch'}
            }
            $oldStatus='present-verified'
        }
        if(Test-Path -LiteralPath $candidate){
            if(-not (Test-Path -LiteralPath $candidate -PathType Container)){return [pscustomobject]@{ok=$false;reason='restore-resume-candidate-not-directory'}}
            $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Envelope.name) -AppPath $candidate
            if(-not [bool]$runtime.safe -or -not [bool]$runtime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -or [string]$runtime.tree_sha256 -cne [string]$Envelope.stage_tree_sha256){
                return [pscustomobject]@{ok=$false;reason='restore-resume-candidate-tree-mismatch'}
            }
            $candidateStatus='present-verified'
        }
        return [pscustomobject]@{ok=$true;reason='restore-resume-transaction-root-bounded';status='present-verified';path=$txn;root=$parent;old_status=$oldStatus;candidate_status=$candidateStatus}
    } catch {
        return [pscustomobject]@{ok=$false;reason=('restore-resume-transaction-read-failed:'+[string]$_.Exception.Message)}
    }
}

function Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 {
    param([Parameter(Mandatory=$true)][string]$Phase,[Parameter(Mandatory=$true)]$Live,[Parameter(Mandatory=$true)]$Transaction)
    $ls=[string]$Live.state
    $ts=[string]$Transaction.status
    $os=[string]$Transaction.old_status
    $cs=[string]$Transaction.candidate_status
    switch($Phase){
        'live-moved-to-old' {
            if($ts -cne 'present-verified' -or $os -cne 'present-verified'){return [pscustomobject]@{ok=$false;reason='restore-resume-live-moved-transaction-state-invalid'}}
            if($ls -ceq 'absent-after-live-move' -and $cs -ceq 'present-verified'){return [pscustomobject]@{ok=$true;reason='restore-resume-live-moved-before-candidate-state'}}
            if($ls -ceq 'candidate-live-exact' -and $cs -ceq 'absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-live-moved-after-candidate-before-journal-state'}}
            return [pscustomobject]@{ok=$false;reason='restore-resume-live-moved-filesystem-state-invalid'}
        }
        'candidate-live' {
            if($ls -cne 'candidate-live-exact'){return [pscustomobject]@{ok=$false;reason='restore-resume-candidate-live-runtime-state-invalid'}}
            if($ts -ceq 'already-absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-candidate-live-after-finalize-before-journal-state'}}
            if($ts -ceq 'present-verified' -and $os -ceq 'present-verified' -and $cs -ceq 'absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-candidate-live-before-finalize-state'}}
            return [pscustomobject]@{ok=$false;reason='restore-resume-candidate-live-transaction-state-invalid'}
        }
        'transaction-finalized' {
            if($ls -ceq 'candidate-live-exact' -and $ts -ceq 'already-absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-transaction-finalized-state'}}
            return [pscustomobject]@{ok=$false;reason='restore-resume-transaction-finalized-filesystem-state-invalid'}
        }
        'apply-starting' {
            if($ls -ceq 'candidate-live-exact' -and $ts -ceq 'already-absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-apply-starting-state'}}
            return [pscustomobject]@{ok=$false;reason='restore-resume-apply-starting-filesystem-state-invalid'}
        }
        'apply-returned-success-pending-verification' {
            if($ls -ceq 'candidate-live-exact' -and $ts -ceq 'already-absent'){return [pscustomobject]@{ok=$true;reason='restore-resume-apply-returned-state'}}
            return [pscustomobject]@{ok=$false;reason='restore-resume-apply-returned-filesystem-state-invalid'}
        }
        'rollback-required' {
            if($ls -notin @('absent-after-live-move','old-live-exact','candidate-live-exact')){return [pscustomobject]@{ok=$false;reason='restore-resume-rollback-required-live-state-invalid'}}
            if($ts -notin @('present-verified','already-absent')){return [pscustomobject]@{ok=$false;reason='restore-resume-rollback-required-transaction-state-invalid'}}
            return [pscustomobject]@{ok=$true;reason='restore-resume-rollback-required-bounded-state'}
        }
        default {return [pscustomobject]@{ok=$false;reason='restore-resume-phase-not-auto-restorable'}}
    }
}

function Get-CustomAppProductionRecoveryRestoreResumeAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_cleanup_resume_head,[string]$Receipt.qualified_evidence_head,[string]$Receipt.qualified_journal_head,
        [string]$Receipt.transaction_id,[string]$Receipt.phase,[string]$Receipt.classification,[string]$Receipt.plan_fingerprint,[string]$Receipt.evidence_fingerprint,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.remote_commit_sha,[string]$Receipt.consumption_id,[string]$Receipt.preparation_fingerprint,
        [string]$Receipt.live_path,[string]$Receipt.transaction_root,[string]$Receipt.stage_workspace_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,
        [string]$Receipt.live_state,[string]$Receipt.live_runtime_tree_sha256,[string]$Receipt.transaction_status,[string]$Receipt.transaction_old_status,[string]$Receipt.transaction_candidate_status,[string]$Receipt.stage_status,
        [string]$Receipt.app_backup_tree_sha256,[string]$Receipt.persistence_fingerprint,[string]$Receipt.current_persistence_fingerprint,[string]$Receipt.current_persistence_matches_durable,
        [string]$Receipt.requires_recovery_apply,[string]$Receipt.spicetify_executable_sha256,[string]$Receipt.restore_resume_eligible,[string]$Receipt.requires_exact_restore,[string]$Receipt.requires_future_executor_fresh_revalidation,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,[string]$Receipt.admission_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,
        [AllowNull()][string]$SpicetifyPath=$null,
        [AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 $tx)){return & $deny 'restore-resume-transaction-id-invalid'}

    try{$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}
    catch{return & $deny ('restore-resume-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null -eq $journal -or -not [bool]$journal.ok -or $null -eq $journal.entry){return & $deny 'restore-resume-journal-invalid'}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$journal.entry.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'restore-resume-journal-transaction-mismatch'}
    $phase=[string]$journal.entry.phase
    if($phase -notin @('live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','rollback-required')){return & $deny 'restore-resume-phase-not-auto-restorable'}

    try{$plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx}
    catch{return & $deny ('restore-resume-plan-resolution-failed:'+[string]$_.Exception.Message)}
    $pc=Test-CustomAppProductionRecoveryPlanV010 -Plan $plan
    if(-not [bool]$pc.ok){return & $deny ('restore-resume-plan-invalid:'+[string]$pc.reason)}
    if(-not [bool]$plan.requires_recovery_executor -or -not [bool]$plan.requires_exact_app_restore -or -not [bool]$plan.requires_exact_persistence_restore -or [bool]$plan.housekeeping_only -or [bool]$plan.no_action -or [bool]$plan.requires_manual_inspection){
        return & $deny 'restore-resume-plan-contract-invalid'
    }
    if($phase -in @('live-moved-to-old','candidate-live','transaction-finalized')){
        if([string]$plan.classification -cne 'exact-app-and-persistence-recovery-required' -or [bool]$plan.requires_recovery_apply){return & $deny 'restore-resume-plan-pre-apply-mapping-invalid'}
    } else {
        if([string]$plan.classification -cne 'rollback-and-recovery-apply-required' -or -not [bool]$plan.requires_recovery_apply){return & $deny 'restore-resume-plan-apply-mapping-invalid'}
    }

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null -eq $evidence -or -not [bool]$evidence.ok){return & $deny ('restore-resume-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if([bool]$e.$f){return & $deny ('restore-resume-evidence-authority-escaped-'+$f)}
    }
    foreach($p in @(
        @('name',[string]$journal.entry.name),
        @('source_identity',[string]$journal.entry.source_identity),
        @('remote_commit_sha',[string]$journal.entry.remote_commit_sha),
        @('consumption_id',[string]$journal.entry.consumption_id),
        @('stage_result_fingerprint',[string]$journal.entry.stage_result_fingerprint),
        @('preparation_fingerprint',[string]$journal.entry.preparation_fingerprint)
    )){
        if(([string]$e.($p[0])).Trim().ToLowerInvariant() -cne ([string]$p[1]).Trim().ToLowerInvariant()){return & $deny ('restore-resume-evidence-journal-mismatch-'+$p[0])}
    }
    foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){
        if(-not (Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 -A ([string]$e.$f) -B ([string]$journal.entry.$f))){return & $deny ('restore-resume-evidence-journal-path-mismatch-'+$f)}
    }

    $stage=Test-CustomAppProductionRecoveryRestoreResumeStageV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$stage.ok){return & $deny ([string]$stage.reason)}
    $backups=Test-CustomAppProductionRecoveryRestoreResumeBackupsV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$backups.ok){return & $deny ([string]$backups.reason)}
    $live=Get-CustomAppProductionRecoveryRestoreResumeLiveStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$live.ok){return & $deny ([string]$live.reason)}
    $txn=Get-CustomAppProductionRecoveryRestoreResumeTransactionStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$txn.ok){return & $deny ([string]$txn.reason)}
    $mapping=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $phase -Live $live -Transaction $txn
    if(-not [bool]$mapping.ok){return & $deny ([string]$mapping.reason)}

    try{$persistNow=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}
    catch{return & $deny ('restore-resume-current-persistence-read-failed:'+[string]$_.Exception.Message)}
    if(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 ([string]$persistNow.fingerprint))){return & $deny 'restore-resume-current-persistence-fingerprint-invalid'}

    $exeSha=''
    if([bool]$plan.requires_recovery_apply){
        if(
            [string]::IsNullOrWhiteSpace($SpicetifyAllowedRoot) -or
            [string]::IsNullOrWhiteSpace($SpicetifyPath) -or
            [string]::IsNullOrWhiteSpace($ExpectedSpicetifySha256)
        ){
            return & $deny 'restore-resume-spicetify-pin-inputs-missing'
        }
        try{$exe=Get-CustomAppProductionRecoveryPreflightExecutableEvidenceV010 -AllowedRoot $SpicetifyAllowedRoot -Path $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256}
        catch{return & $deny ('restore-resume-spicetify-pin-invalid:'+[string]$_.Exception.Message)}
        $exeSha=([string]$exe.sha256).Trim().ToLowerInvariant()
    }

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryRestoreResumeAdmissionSchema
        managed_by=$CustomAppProductionRecoveryRestoreResumeAdmissionManagedBy
        qualified_cleanup_resume_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedCleanupResumeHead
        qualified_evidence_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedEvidenceHead
        qualified_journal_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedJournalHead
        transaction_id=$tx
        phase=$phase
        classification=[string]$plan.classification
        plan_fingerprint=([string]$plan.plan_fingerprint).Trim().ToLowerInvariant()
        evidence_fingerprint=([string]$e.evidence_fingerprint).Trim().ToLowerInvariant()
        journal_revision=[int64]$journal.revision
        journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()
        name=([string]$e.name).Trim().ToLowerInvariant()
        source_identity=([string]$e.source_identity).Trim().ToLowerInvariant()
        remote_commit_sha=([string]$e.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$e.consumption_id).Trim().ToLowerInvariant()
        preparation_fingerprint=([string]$e.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$e.live_path
        transaction_root=[string]$e.transaction_root
        stage_workspace_path=[string]$e.stage_workspace_path
        app_backup_path=[string]$e.app_backup_path
        persistence_backup_path=[string]$e.persistence_backup_path
        live_state=[string]$live.state
        live_runtime_tree_sha256=[string]$live.tree_sha256
        transaction_status=[string]$txn.status
        transaction_old_status=[string]$txn.old_status
        transaction_candidate_status=[string]$txn.candidate_status
        stage_status=[string]$stage.status
        app_backup_tree_sha256=([string]$e.app_backup_tree_sha256).Trim().ToLowerInvariant()
        persistence_fingerprint=([string]$e.persistence_fingerprint).Trim().ToLowerInvariant()
        current_persistence_fingerprint=([string]$persistNow.fingerprint).Trim().ToLowerInvariant()
        current_persistence_matches_durable=(([string]$persistNow.fingerprint).Trim().ToLowerInvariant() -ceq ([string]$e.persistence_fingerprint).Trim().ToLowerInvariant())
        requires_recovery_apply=[bool]$plan.requires_recovery_apply
        spicetify_executable_sha256=$exeSha
        restore_resume_eligible=$true
        requires_exact_restore=$true
        requires_future_executor_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o')
        eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        admission_is_authority=$false
        execution_authorized=$false
        restore_authorized=$false
        apply_authorized=$false
        cleanup_authorized=$false
        production_mutation_authorized=$false
        restore_resume_admission_fingerprint=$null
    }
    $receipt.restore_resume_admission_fingerprint=Get-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryRestoreResumeAdmissionMaterialV010 -Receipt $receipt)
    return [pscustomobject]@{ok=$true;reason='recovery-restore-resume-bounded-state-eligible-zero-authority';receipt=$receipt;evidence=$e;plan=$plan;live=$live;transaction=$txn;stage=$stage;backups=$backups;filesystem_mapping_reason=[string]$mapping.reason}
}

function Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-null'}}

    foreach($f in @(
        'schema','managed_by','qualified_cleanup_resume_head','qualified_evidence_head','qualified_journal_head','transaction_id','phase','classification','plan_fingerprint','evidence_fingerprint','journal_revision','journal_entry_sha256','name','source_identity','remote_commit_sha','consumption_id','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','live_state','live_runtime_tree_sha256','transaction_status','transaction_old_status','transaction_candidate_status','stage_status','app_backup_tree_sha256','persistence_fingerprint','current_persistence_fingerprint','current_persistence_matches_durable','requires_recovery_apply','spicetify_executable_sha256','restore_resume_eligible','requires_exact_restore','requires_future_executor_fresh_revalidation','checked_at','eligible_until','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','restore_resume_admission_fingerprint'
    )){
        if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('restore-resume-receipt-field-missing-'+$f)}}
    }
    if(
        [int]$Receipt.schema -ne 1 -or
        [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryRestoreResumeAdmissionManagedBy -or
        [string]$Receipt.qualified_cleanup_resume_head -cne $CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedCleanupResumeHead -or
        [string]$Receipt.qualified_evidence_head -cne $CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedEvidenceHead -or
        [string]$Receipt.qualified_journal_head -cne $CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedJournalHead
    ){
        return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-owner-schema-parent-invalid'}
    }
    foreach($f in @('transaction_id','plan_fingerprint','evidence_fingerprint','journal_entry_sha256','app_backup_tree_sha256','persistence_fingerprint','current_persistence_fingerprint','restore_resume_admission_fingerprint')){
        if(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('restore-resume-receipt-invalid-'+$f)}}
    }
    if(([string]$Receipt.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-remote-commit-invalid'}}
    if([string]$Receipt.phase -notin @('live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','rollback-required')){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-phase-invalid'}}

    if([string]$Receipt.phase -in @('live-moved-to-old','candidate-live','transaction-finalized')){
        if([string]$Receipt.classification -cne 'exact-app-and-persistence-recovery-required' -or [bool]$Receipt.requires_recovery_apply -or -not [string]::IsNullOrWhiteSpace([string]$Receipt.spicetify_executable_sha256)){
            return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-pre-apply-mapping-invalid'}
        }
    } else {
        if([string]$Receipt.classification -cne 'rollback-and-recovery-apply-required' -or -not [bool]$Receipt.requires_recovery_apply -or -not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 ([string]$Receipt.spicetify_executable_sha256)){
            return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-apply-mapping-invalid'}
        }
    }

    if([string]$Receipt.live_state -notin @('absent-after-live-move','old-live-exact','candidate-live-exact') -or [string]$Receipt.transaction_status -notin @('present-verified','already-absent') -or [string]$Receipt.transaction_old_status -notin @('present-verified','absent') -or [string]$Receipt.transaction_candidate_status -notin @('present-verified','absent') -or [string]$Receipt.stage_status -cne 'present-verified'){
        return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-filesystem-state-invalid'}
    }
    if([string]$Receipt.live_state -ceq 'absent-after-live-move'){
        if(-not [string]::IsNullOrWhiteSpace([string]$Receipt.live_runtime_tree_sha256)){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-absent-live-hash-set'}}
    } elseif(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 ([string]$Receipt.live_runtime_tree_sha256))){
        return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-live-hash-invalid'}
    }
    if(-not [bool]$Receipt.restore_resume_eligible -or -not [bool]$Receipt.requires_exact_restore -or -not [bool]$Receipt.requires_future_executor_fresh_revalidation){
        return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-separation-contract-invalid'}
    }
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('restore-resume-receipt-authority-escaped-'+$f)}}
    }

    $start=[DateTimeOffset]::MinValue
    $end=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start) -or -not [DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){
        return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-time-invalid'}
    }
    if($end -le $start -or $end -gt $start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-window-invalid'}}
    if($Now -lt $start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-not-yet-valid'}}
    if($Now -ge $end){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-expired'}}

    $expected=Get-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryRestoreResumeAdmissionMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.restore_resume_admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='restore-resume-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='restore-resume-admission-valid-zero-authority';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();phase=[string]$Receipt.phase;live_state=[string]$Receipt.live_state;transaction_status=[string]$Receipt.transaction_status}
}
