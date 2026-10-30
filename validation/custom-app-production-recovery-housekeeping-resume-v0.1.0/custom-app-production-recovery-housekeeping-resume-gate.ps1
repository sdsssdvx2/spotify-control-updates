function Resolve-CustomAppProductionRecoveryHousekeepingResumeGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    try{$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('housekeeping-resume-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$journal -or -not[bool]$journal.ok -or [string]$journal.entry.phase -cne 'cleanup-starting'){return & $deny 'housekeeping-resume-journal-not-cleanup-starting'}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not(Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010 $tx) -or ([string]$journal.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'housekeeping-resume-journal-transaction-mismatch'}

    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$ev -or -not[bool]$ev.ok){return & $deny ('housekeeping-resume-evidence-read-denied:'+[string]$ev.reason)}
    $e=$ev.envelope;$prepared=$e.prepared_result
    $rr=Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    if($null-eq$rr -or -not[bool]$rr.ok){return & $deny ('housekeeping-resume-envelope-read-denied:'+[string]$rr.reason)}
    $h=$rr.envelope

    $bindings=@(
        @('transaction_id',$tx),
        @('evidence_fingerprint',([string]$e.evidence_fingerprint).Trim().ToLowerInvariant()),
        @('preparation_fingerprint',([string]$e.preparation_fingerprint).Trim().ToLowerInvariant()),
        @('name',([string]$e.name).Trim().ToLowerInvariant()),
        @('source_identity',([string]$e.source_identity).Trim().ToLowerInvariant()),
        @('remote_commit_sha',([string]$e.remote_commit_sha).Trim().ToLowerInvariant()),
        @('consumption_id',([string]$e.consumption_id).Trim().ToLowerInvariant()),
        @('live_path',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$e.live_path))),
        @('stage_workspace_path',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.stage_workspace_path))),
        @('stage_path',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.stage_path))),
        @('app_backup_root',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.app_backup_root))),
        @('app_backup_path',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.app_backup_path))),
        @('persistence_backup_root',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.persistence_backup_root))),
        @('persistence_backup_path',(Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 ([string]$prepared.persistence_backup_path)))
    )
    foreach($pair in $bindings){if([string]$h.($pair[0]) -cne [string]$pair[1]){return & $deny ('housekeeping-resume-envelope-evidence-mismatch-'+$pair[0])}}
    if(([string]$h.app_backup_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$prepared.app_backup_tree_sha256).Trim().ToLowerInvariant() -or [int]$h.app_backup_file_count -ne [int]$prepared.app_backup_file_count -or [int64]$h.app_backup_total_bytes -ne [int64]$prepared.app_backup_total_bytes){return & $deny 'housekeeping-resume-app-backup-anchor-mismatch'}
    if(([string]$h.stage_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$e.stage_tree_sha256).Trim().ToLowerInvariant() -or ([string]$h.persistence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$e.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'housekeeping-resume-stage-or-persistence-anchor-mismatch'}
    if(([string]$journal.entry.name).Trim().ToLowerInvariant() -cne ([string]$h.name).Trim().ToLowerInvariant() -or ([string]$journal.entry.consumption_id).Trim().ToLowerInvariant() -cne ([string]$h.consumption_id).Trim().ToLowerInvariant() -or ([string]$journal.entry.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$h.preparation_fingerprint).Trim().ToLowerInvariant()){return & $deny 'housekeeping-resume-journal-identity-mismatch'}
    if((Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 $LocalAppDataRoot) -cne [string]$h.local_appdata_root -or (Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 $AppDataRoot) -cne [string]$h.appdata_root){return & $deny 'housekeeping-resume-persistence-root-mismatch'}

    try{
        $live=Get-CustomAppLocalRuntimeBaseline -Name ([string]$h.name) -AppPath ([string]$h.live_path)
        if(-not[bool]$live.safe -or -not[bool]$live.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $live) -or [string]$live.tree_sha256 -cne [string]$h.live_runtime_tree_sha256){throw 'live-runtime-drift'}
        $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath ([string]$h.live_path)
        if([bool]$git.present -ne [bool]$h.preserved_git_present){throw 'git-presence-drift'}
        if([bool]$h.preserved_git_present -and [string]$git.tree_sha256 -cne [string]$h.preserved_git_tree_sha256){throw 'git-tree-drift'}
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if([string]$persist.fingerprint -cne [string]$h.persistence_fingerprint){throw 'protected-persistence-drift'}

        $stageStatus='already-absent'
        if(Test-Path -LiteralPath ([string]$h.stage_workspace_path)){
            $stageRoot=Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 (Get-CustomAppStageWorkspaceRootV010)
            if($stageRoot -cne [string]$h.stage_workspace_root){throw 'stage-root-drift'}
            if(-not([IO.Path]::GetDirectoryName([string]$h.stage_workspace_path)).Equals($stageRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName([string]$h.stage_workspace_path) -notmatch '^[0-9a-fA-F]{32}$'){throw 'stage-workspace-path-shape-drift'}
            $wi=Get-Item -LiteralPath ([string]$h.stage_workspace_path) -Force -ErrorAction Stop
            if(($wi.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0 -or -not $wi.PSIsContainer){throw 'stage-workspace-unsafe'}
            if(-not(Test-Path -LiteralPath ([string]$h.stage_path) -PathType Container)){throw 'stage-path-missing-inside-present-workspace'}
            $sr=Get-CustomAppLocalRuntimeBaseline -Name ([string]$h.name) -AppPath ([string]$h.stage_path)
            if(-not[bool]$sr.safe -or -not[bool]$sr.installable -or [string]$sr.tree_sha256 -cne [string]$h.stage_tree_sha256 -or (Test-Path -LiteralPath (Join-Path ([string]$h.stage_path) '.git'))){throw 'stage-tree-drift'}
            $stageStatus='present-verified'
        }

        $appPlan=Test-CustomAppProductionPostApplyAppBackupCleanupArtifactV010 -PreparedResult $prepared
        if(-not[bool]$appPlan.ok){throw ('app-backup-invalid:'+[string]$appPlan.reason)}
        $appStatus=[string]$appPlan.status
        $pPlan=Test-CustomAppProductionPostApplyPersistenceCleanupArtifactV010 -PreparedResult $prepared
        if(-not[bool]$pPlan.ok){throw ('persistence-backup-invalid:'+[string]$pPlan.reason)}
        $pStatus=[string]$pPlan.status
    }catch{return & $deny ('housekeeping-resume-current-state-denied:'+[string]$_.Exception.Message)}

    $d=[pscustomobject]@{
        schema=1;managed_by=$CustomAppProductionRecoveryHousekeepingResumeManagedBy;qualified_integration_head=$CustomAppProductionRecoveryHousekeepingResumeQualifiedIntegrationHead
        transaction_id=$tx;resume_fingerprint=([string]$h.resume_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=([string]$h.evidence_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$h.preparation_fingerprint).Trim().ToLowerInvariant();journal_revision=[int64]$journal.revision;journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant();phase='cleanup-starting';name=[string]$h.name
        live_runtime_tree_sha256=([string]$live.tree_sha256).Trim().ToLowerInvariant();preserved_git_present=[bool]$git.present;preserved_git_tree_sha256=$(if([bool]$git.present){([string]$git.tree_sha256).Trim().ToLowerInvariant()}else{''});persistence_fingerprint=([string]$persist.fingerprint).Trim().ToLowerInvariant()
        stage_cleanup_status=$stageStatus;app_backup_cleanup_status=$appStatus;persistence_backup_cleanup_status=$pStatus;checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o');resume_preconditions_satisfied=$true
        resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;decision_fingerprint=$null
    }
    $d.decision_fingerprint=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeDecisionMaterialV010 $d)
    $dc=Test-CustomAppProductionRecoveryHousekeepingResumeDecisionV010 -Decision $d -Now $Now
    if(-not[bool]$dc.ok){return & $deny ('housekeeping-resume-decision-self-invalid:'+[string]$dc.reason)}
    return [pscustomobject]@{ok=$true;reason='housekeeping-resume-partial-cleanup-state-valid-zero-authority';decision=$d;prepared_result=$prepared;resume_envelope=$h;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
