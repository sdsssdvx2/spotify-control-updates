$CustomAppProductionRecoveryCleanupResumeAdmissionSchema = 1
$CustomAppProductionRecoveryCleanupResumeAdmissionManagedBy = 'custom-app-production-recovery-cleanup-resume-admission-v1'
$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedIntegrationHead = '5232e5adeb13e6942acb210b3cd13058e1eaaf05'
$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedEvidenceHead = '993af44afee9adb0c28e5fb702cb6ccfbd7cd99c'

function Get-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'cleanup-resume-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionRecoveryCleanupResumeAdmissionPathEqualV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    return (Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 $A).Equals((Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 $B),[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Label)
    $p=Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 $Path
    if(-not(Test-Path -LiteralPath $p -PathType Container)){throw "$Label missing"}
    $root=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label reparse point"}
    foreach($item in @(Get-ChildItem -LiteralPath $p -Force -Recurse -ErrorAction Stop)){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label contains reparse point"}
    }
    return $p
}

function Test-CustomAppProductionRecoveryCleanupResumeStageArtifactV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try{
        $workspace=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.stage_workspace_path) -Label 'cleanup-resume stage workspace'
        $stageRoot=Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 (Get-CustomAppStageWorkspaceRootV010)
        if(-not ([IO.Path]::GetDirectoryName($workspace)).Equals($stageRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($workspace) -notmatch '^[0-9a-fA-F]{32}$'){return [pscustomobject]@{ok=$false;reason='cleanup-resume-stage-workspace-path-shape-invalid'}}
        if(-not(Test-Path -LiteralPath $workspace)){return [pscustomobject]@{ok=$true;reason='cleanup-resume-stage-workspace-already-absent';status='already-absent';delete_path=$workspace;root=$stageRoot}}
        if(-not(Test-Path -LiteralPath $workspace -PathType Container)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-stage-workspace-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $workspace -Label 'cleanup-resume stage workspace')
        $stagePath=Join-Path $workspace 'stage'
        if(-not(Test-Path -LiteralPath $stagePath -PathType Container)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-stage-directory-missing'}}
        $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Envelope.name) -AppPath $stagePath
        if(-not[bool]$runtime.safe -or -not[bool]$runtime.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $runtime) -or [string]$runtime.tree_sha256 -cne [string]$Envelope.stage_tree_sha256){return [pscustomobject]@{ok=$false;reason='cleanup-resume-stage-tree-mismatch'}}
        return [pscustomobject]@{ok=$true;reason='cleanup-resume-stage-workspace-present-exact';status='present-verified';delete_path=$workspace;root=$stageRoot;tree_sha256=[string]$runtime.tree_sha256}
    }catch{return [pscustomobject]@{ok=$false;reason=('cleanup-resume-stage-read-failed:'+[string]$_.Exception.Message)}}
}

function Test-CustomAppProductionRecoveryCleanupResumeAppBackupArtifactV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try{
        $appPath=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.app_backup_path) -Label 'cleanup-resume app backup'
        if([IO.Path]::GetFileName($appPath) -cne 'app-code'){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-leaf-name-invalid'}}
        $container=Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 ([IO.Path]::GetDirectoryName($appPath))
        $root=Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 ([IO.Path]::GetDirectoryName($container))
        if([IO.Path]::GetFileName($container) -notmatch '^[0-9a-fA-F]{32}$'){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-container-name-invalid'}}
        if(-not(Test-Path -LiteralPath $container)){
            if(Test-Path -LiteralPath $appPath){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-leaf-without-container'}}
            return [pscustomobject]@{ok=$true;reason='cleanup-resume-app-backup-already-absent';status='already-absent';delete_path=$container;root=$root}
        }
        if(-not(Test-Path -LiteralPath $container -PathType Container)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-container-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $container -Label 'cleanup-resume app backup container')
        $children=@(Get-ChildItem -LiteralPath $container -Force -ErrorAction Stop)
        if($children.Count -ne 1 -or [string]$children[0].Name -cne 'app-code' -or -not $children[0].PSIsContainer){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-container-contents-invalid'}}
        $snap=Get-CustomAppUpdateTreeSnapshotV010 -Root $appPath
        if([string]$snap.tree_sha256 -cne [string]$Envelope.app_backup_tree_sha256 -or [int]$snap.file_count -ne [int]$Envelope.app_backup_file_count -or [int64]$snap.total_bytes -ne [int64]$Envelope.app_backup_total_bytes){return [pscustomobject]@{ok=$false;reason='cleanup-resume-app-backup-tree-mismatch'}}
        return [pscustomobject]@{ok=$true;reason='cleanup-resume-app-backup-present-exact';status='present-verified';delete_path=$container;root=$root;tree_sha256=[string]$snap.tree_sha256}
    }catch{return [pscustomobject]@{ok=$false;reason=('cleanup-resume-app-backup-read-failed:'+[string]$_.Exception.Message)}}
}

function Test-CustomAppProductionRecoveryCleanupResumePersistenceArtifactV010 {
    param([Parameter(Mandatory=$true)]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    try{
        $path=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.persistence_backup_path) -Label 'cleanup-resume persistence backup'
        $root=Get-CustomAppProductionRecoveryCleanupResumeAdmissionCanonicalPathV010 ([IO.Path]::GetDirectoryName($path))
        if([IO.Path]::GetFileName($path) -notmatch '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$'){return [pscustomobject]@{ok=$false;reason='cleanup-resume-persistence-backup-name-invalid'}}
        if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{ok=$true;reason='cleanup-resume-persistence-backup-already-absent';status='already-absent';delete_path=$path;root=$root}}
        if(-not(Test-Path -LiteralPath $path -PathType Container)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-persistence-backup-not-directory'}}
        [void](Assert-CustomAppProductionRecoveryCleanupResumeNoReparseTreeV010 -Path $path -Label 'cleanup-resume persistence backup')
        $check=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $path -ExpectedFingerprint ([string]$Envelope.persistence_fingerprint)
        if(-not[bool]$check.ok){return [pscustomobject]@{ok=$false;reason=('cleanup-resume-persistence-backup-invalid:'+[string]$check.reason)}}
        return [pscustomobject]@{ok=$true;reason='cleanup-resume-persistence-backup-present-exact';status='present-verified';delete_path=$path;root=$root}
    }catch{return [pscustomobject]@{ok=$false;reason=('cleanup-resume-persistence-backup-read-failed:'+[string]$_.Exception.Message)}}
}

function Get-CustomAppProductionRecoveryCleanupResumeAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_integration_head,[string]$Receipt.qualified_evidence_head,
        [string]$Receipt.transaction_id,[string]$Receipt.phase,[string]$Receipt.classification,[string]$Receipt.plan_fingerprint,[string]$Receipt.evidence_fingerprint,
        [string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,[string]$Receipt.name,[string]$Receipt.live_path,[string]$Receipt.transaction_root,
        [string]$Receipt.stage_workspace_path,[string]$Receipt.app_backup_path,[string]$Receipt.persistence_backup_path,[string]$Receipt.stage_status,[string]$Receipt.app_backup_status,[string]$Receipt.persistence_backup_status,
        [string]$Receipt.live_tree_sha256,[string]$Receipt.persistence_fingerprint,[string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.resume_cleanup_eligible,[string]$Receipt.requires_bounded_cleanup_only,[string]$Receipt.requires_future_executor_fresh_revalidation,
        [string]$Receipt.admission_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 $tx)){return & $deny 'cleanup-resume-transaction-id-invalid'}
    try{$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('cleanup-resume-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$journal-or-not[bool]$journal.ok-or$null-eq$journal.entry){return & $deny 'cleanup-resume-journal-invalid'}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant()-cne$tx-or([string]$journal.entry.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'cleanup-resume-journal-transaction-mismatch'}
    if([string]$journal.entry.phase-cne'cleanup-starting'){return & $deny 'cleanup-resume-phase-not-cleanup-starting'}

    try{$plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx}catch{return & $deny ('cleanup-resume-plan-resolution-failed:'+[string]$_.Exception.Message)}
    $pc=Test-CustomAppProductionRecoveryPlanV010 -Plan $plan;if(-not[bool]$pc.ok){return & $deny ('cleanup-resume-plan-invalid:'+[string]$pc.reason)}
    if([string]$plan.phase-cne'cleanup-starting'-or[string]$plan.classification-cne'fresh-revalidate-then-idempotent-housekeeping-only'-or-not[bool]$plan.housekeeping_only-or-not[bool]$plan.requires_idempotent_cleanup-or[bool]$plan.no_action-or[bool]$plan.requires_manual_inspection-or[bool]$plan.requires_recovery_apply-or[bool]$plan.requires_exact_app_restore-or[bool]$plan.requires_exact_persistence_restore){return & $deny 'cleanup-resume-plan-contract-invalid'}

    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$evidence-or-not[bool]$evidence.ok){return & $deny ('cleanup-resume-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$e.$f){return & $deny ('cleanup-resume-evidence-authority-escaped-'+$f)}}
    $pairs=@(
        @('name',[string]$journal.entry.name),@('source_identity',[string]$journal.entry.source_identity),@('remote_commit_sha',[string]$journal.entry.remote_commit_sha),@('consumption_id',[string]$journal.entry.consumption_id),@('stage_result_fingerprint',[string]$journal.entry.stage_result_fingerprint),@('preparation_fingerprint',[string]$journal.entry.preparation_fingerprint)
    )
    foreach($p in $pairs){if(([string]$e.($p[0])).Trim().ToLowerInvariant()-cne([string]$p[1]).Trim().ToLowerInvariant()){return & $deny ('cleanup-resume-evidence-journal-mismatch-'+$p[0])}}
    foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){if(-not(Test-CustomAppProductionRecoveryCleanupResumeAdmissionPathEqualV010 -A ([string]$e.$f) -B ([string]$journal.entry.$f))){return & $deny ('cleanup-resume-evidence-journal-path-mismatch-'+$f)}}

    try{$txn=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$e.transaction_root) -Label 'cleanup-resume transaction root'}catch{return & $deny ('cleanup-resume-transaction-root-path-invalid:'+[string]$_.Exception.Message)}
    if(Test-Path -LiteralPath $txn){return & $deny 'cleanup-resume-transaction-root-must-be-absent'}
    try{$livePath=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$e.live_path) -Label 'cleanup-resume live' -RequireExisting:$true}catch{return & $deny ('cleanup-resume-live-path-invalid:'+[string]$_.Exception.Message)}
    try{$live=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath $livePath}catch{return & $deny ('cleanup-resume-live-runtime-read-failed:'+[string]$_.Exception.Message)}
    if(-not[bool]$live.safe-or-not[bool]$live.installable-or(Test-CustomAppLocalRuntimeBaselineMutationAuthority $live)-or[string]$live.tree_sha256-cne[string]$e.stage_tree_sha256){return & $deny 'cleanup-resume-live-runtime-not-exact-applied-tree'}
    try{$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('cleanup-resume-protected-persistence-read-failed:'+[string]$_.Exception.Message)}
    if([string]$persist.fingerprint-cne[string]$e.persistence_fingerprint){return & $deny 'cleanup-resume-protected-persistence-drift'}

    $stage=Test-CustomAppProductionRecoveryCleanupResumeStageArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$stage.ok){return & $deny ([string]$stage.reason)}
    $app=Test-CustomAppProductionRecoveryCleanupResumeAppBackupArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$app.ok){return & $deny ([string]$app.reason)}
    $persistence=Test-CustomAppProductionRecoveryCleanupResumePersistenceArtifactV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$persistence.ok){return & $deny ([string]$persistence.reason)}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryCleanupResumeAdmissionSchema;managed_by=$CustomAppProductionRecoveryCleanupResumeAdmissionManagedBy;qualified_integration_head=$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedIntegrationHead;qualified_evidence_head=$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedEvidenceHead
        transaction_id=$tx;phase='cleanup-starting';classification='fresh-revalidate-then-idempotent-housekeeping-only';plan_fingerprint=([string]$plan.plan_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=([string]$e.evidence_fingerprint).Trim().ToLowerInvariant();journal_revision=[int64]$journal.revision;journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant();name=([string]$e.name).Trim().ToLowerInvariant()
        live_path=$livePath;transaction_root=$txn;stage_workspace_path=[string]$e.stage_workspace_path;app_backup_path=[string]$e.app_backup_path;persistence_backup_path=[string]$e.persistence_backup_path;stage_status=[string]$stage.status;app_backup_status=[string]$app.status;persistence_backup_status=[string]$persistence.status
        live_tree_sha256=([string]$live.tree_sha256).Trim().ToLowerInvariant();persistence_fingerprint=([string]$persist.fingerprint).Trim().ToLowerInvariant();checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        resume_cleanup_eligible=$true;requires_bounded_cleanup_only=$true;requires_future_executor_fresh_revalidation=$true;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;resume_admission_fingerprint=$null
    }
    $receipt.resume_admission_fingerprint=Get-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryCleanupResumeAdmissionMaterialV010 -Receipt $receipt)
    return [pscustomobject]@{ok=$true;reason='cleanup-starting-partial-artifact-resume-eligible-zero-authority';receipt=$receipt;evidence=$e;artifacts=[pscustomobject]@{stage=$stage;app_backup=$app;persistence_backup=$persistence}}
}

function Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_integration_head','qualified_evidence_head','transaction_id','phase','classification','plan_fingerprint','evidence_fingerprint','journal_revision','journal_entry_sha256','name','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','stage_status','app_backup_status','persistence_backup_status','live_tree_sha256','persistence_fingerprint','checked_at','eligible_until','resume_cleanup_eligible','requires_bounded_cleanup_only','requires_future_executor_fresh_revalidation','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','resume_admission_fingerprint')){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('cleanup-resume-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne1-or[string]$Receipt.managed_by-cne$CustomAppProductionRecoveryCleanupResumeAdmissionManagedBy-or[string]$Receipt.qualified_integration_head-cne$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedIntegrationHead-or[string]$Receipt.qualified_evidence_head-cne$CustomAppProductionRecoveryCleanupResumeAdmissionQualifiedEvidenceHead-or[string]$Receipt.phase-cne'cleanup-starting'-or[string]$Receipt.classification-cne'fresh-revalidate-then-idempotent-housekeeping-only'){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-owner-schema-parent-phase-invalid'}}
    foreach($f in @('transaction_id','plan_fingerprint','evidence_fingerprint','journal_entry_sha256','live_tree_sha256','persistence_fingerprint','resume_admission_fingerprint')){if(-not(Test-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('cleanup-resume-receipt-invalid-'+$f)}}}
    foreach($f in @('stage_status','app_backup_status','persistence_backup_status')){if([string]$Receipt.$f-notin@('present-verified','already-absent')){return [pscustomobject]@{ok=$false;reason=('cleanup-resume-receipt-invalid-'+$f)}}}
    if(-not[bool]$Receipt.resume_cleanup_eligible-or-not[bool]$Receipt.requires_bounded_cleanup_only-or-not[bool]$Receipt.requires_future_executor_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-separation-contract-invalid'}}
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('cleanup-resume-receipt-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-window-invalid'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-expired'}}
    $expected=Get-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryCleanupResumeAdmissionMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.resume_admission_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='cleanup-resume-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='cleanup-resume-admission-valid-zero-authority';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();journal_revision=[int64]$Receipt.journal_revision}
}
