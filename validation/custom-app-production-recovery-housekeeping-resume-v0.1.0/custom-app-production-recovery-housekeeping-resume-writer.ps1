function Resolve-CustomAppProductionRecoveryHousekeepingFreshIntegrationV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason}}
    $plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId
    $pc=Test-CustomAppProductionRecoveryPlanV010 $plan
    if(-not[bool]$pc.ok){return & $deny ('housekeeping-resume-plan-invalid:'+[string]$pc.reason)}
    if([string]$plan.phase -notin @('apply-verified','cleanup-starting') -or -not[bool]$plan.housekeeping_only -or -not[bool]$plan.requires_idempotent_cleanup -or [bool]$plan.requires_manual_inspection -or [bool]$plan.no_action){return & $deny 'housekeeping-resume-phase-not-housekeeping'}
    $pre=Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Plan $plan
    if($null-eq$pre -or -not[bool]$pre.ok){return & $deny ('housekeeping-resume-preflight-denied:'+[string]$pre.reason)}
    $integration=Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Plan $plan -PreflightReceipt $pre.receipt -Now $Now
    if($null-eq$integration -or -not[bool]$integration.ok){return & $deny ('housekeeping-resume-integration-denied:'+[string]$integration.reason)}
    $ic=Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 -Receipt $integration.receipt -Now $Now
    if(-not[bool]$ic.ok -or [string]$integration.receipt.executor_class -cne 'idempotent-housekeeping' -or -not[bool]$integration.receipt.requires_idempotent_cleanup){return & $deny 'housekeeping-resume-integration-invalid-or-not-housekeeping'}
    return [pscustomobject]@{ok=$true;reason='housekeeping-resume-fresh-integration-valid';plan=$plan;preflight=$pre.receipt;integration=$integration}
}

function New-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $fresh=Resolve-CustomAppProductionRecoveryHousekeepingFreshIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Now $Now
    if(-not[bool]$fresh.ok){return & $deny ([string]$fresh.reason)}
    $e=$fresh.integration.evidence;$prepared=$e.prepared_result;$r=$fresh.integration.receipt
    try{
        $livePath=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$e.live_path)
        $live=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath $livePath
        if(-not[bool]$live.safe -or -not[bool]$live.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $live) -or [string]$live.tree_sha256 -cne [string]$e.stage_tree_sha256){throw 'housekeeping-resume-live-not-applied-stage-tree'}
        $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if([string]$persist.fingerprint -cne [string]$e.persistence_fingerprint){throw 'housekeeping-resume-persistence-drift-before-envelope'}

        $stageWorkspace=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.stage_workspace_path)
        $stagePath=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.stage_path)
        $stageRoot=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 (Get-CustomAppStageWorkspaceRootV010)
        if(-not([IO.Path]::GetDirectoryName($stageWorkspace)).Equals($stageRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'housekeeping-resume-stage-workspace-parent-invalid'}
        if([IO.Path]::GetFileName($stageWorkspace) -notmatch '^[0-9a-fA-F]{32}$'){throw 'housekeeping-resume-stage-workspace-name-invalid'}
        $expectedStage=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 (Join-Path $stageWorkspace 'stage')
        if(-not $stagePath.Equals($expectedStage,[StringComparison]::OrdinalIgnoreCase)){throw 'housekeeping-resume-stage-path-shape-invalid'}
        if(-not(Test-Path -LiteralPath $stageWorkspace -PathType Container) -or -not(Test-Path -LiteralPath $stagePath -PathType Container)){throw 'housekeeping-resume-stage-missing-before-envelope'}
        $stageItem=Get-Item -LiteralPath $stageWorkspace -Force -ErrorAction Stop
        if(($stageItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'housekeeping-resume-stage-workspace-reparse-point'}
        $stage=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath $stagePath
        if(-not[bool]$stage.safe -or -not[bool]$stage.installable -or [string]$stage.tree_sha256 -cne [string]$e.stage_tree_sha256 -or (Test-Path -LiteralPath (Join-Path $stagePath '.git'))){throw 'housekeeping-resume-stage-tree-invalid'}

        $appPlan=Test-CustomAppProductionPostApplyAppBackupCleanupArtifactV010 -PreparedResult $prepared
        if(-not[bool]$appPlan.ok -or [string]$appPlan.status -cne 'present-verified'){throw ('housekeeping-resume-app-backup-invalid:'+[string]$appPlan.reason)}
        $persistencePlan=Test-CustomAppProductionPostApplyPersistenceCleanupArtifactV010 -PreparedResult $prepared
        if(-not[bool]$persistencePlan.ok -or [string]$persistencePlan.status -cne 'present-verified'){throw ('housekeeping-resume-persistence-backup-invalid:'+[string]$persistencePlan.reason)}

        $envelope=[pscustomobject]@{
            schema=1;managed_by=$CustomAppProductionRecoveryHousekeepingResumeManagedBy;qualified_integration_head=$CustomAppProductionRecoveryHousekeepingResumeQualifiedIntegrationHead;qualified_cleanup_head=$CustomAppProductionRecoveryHousekeepingResumeQualifiedCleanupHead
            transaction_id=([string]$r.transaction_id).Trim().ToLowerInvariant();evidence_fingerprint=([string]$r.evidence_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$r.preparation_fingerprint).Trim().ToLowerInvariant();source_journal_revision=[int64]$r.journal_revision;source_journal_entry_sha256=([string]$r.journal_entry_sha256).Trim().ToLowerInvariant();source_phase=[string]$r.phase
            name=([string]$r.name).Trim().ToLowerInvariant();source_identity=([string]$r.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$r.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$r.consumption_id).Trim().ToLowerInvariant()
            live_path=$livePath;live_runtime_tree_sha256=([string]$live.tree_sha256).Trim().ToLowerInvariant();preserved_git_present=[bool]$git.present;preserved_git_tree_sha256=$(if([bool]$git.present){([string]$git.tree_sha256).Trim().ToLowerInvariant()}else{''});persistence_fingerprint=([string]$persist.fingerprint).Trim().ToLowerInvariant()
            local_appdata_root=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 $LocalAppDataRoot);appdata_root=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 $AppDataRoot)
            stage_workspace_root=$stageRoot;stage_workspace_path=$stageWorkspace;stage_path=$stagePath;stage_tree_sha256=([string]$stage.tree_sha256).Trim().ToLowerInvariant()
            app_backup_root=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.app_backup_root));app_backup_path=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.app_backup_path));app_backup_tree_sha256=([string]$prepared.app_backup_tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$prepared.app_backup_file_count;app_backup_total_bytes=[int64]$prepared.app_backup_total_bytes
            persistence_backup_root=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.persistence_backup_root));persistence_backup_path=(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.persistence_backup_path);created_at=$Now.ToUniversalTime().ToString('o'))
            resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;resume_fingerprint=$null
        }
        $envelope.resume_fingerprint=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeEnvelopeMaterialV010 $envelope)
        $ec=Test-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 $envelope
        if(-not[bool]$ec.ok){throw ('housekeeping-resume-envelope-self-invalid:'+[string]$ec.reason)}
        return [pscustomobject]@{ok=$true;reason='housekeeping-resume-envelope-built-from-fresh-integration';envelope=$envelope;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('housekeeping-resume-envelope-preparation-failed:'+[string]$_.Exception.Message)}
}

function Initialize-CustomAppProductionRecoveryHousekeepingResumeV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $built=New-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if(-not[bool]$built.ok){return $built}
    return Write-CustomAppProductionRecoveryHousekeepingResumeEnvelopeFileV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Envelope $built.envelope
}
