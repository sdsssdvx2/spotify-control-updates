# V024 validation-only, fail-closed admission for REAL official native scoped
# refresh on a previously journaled, HMAC-authenticated whole-tree atomic swap.
# This is NOT the old generic 'apply' result schema and grants NO production
# mutation/commit authority. Reuses historical verified V010 functions.
function New-CustomAppRealNativeJournalDeniedV024 {
    param([string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;real_vendor_authorized=$false
        protected_source_verified=$false;mutation_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Test-CustomAppRealNativeJournalAdmissionV024 {
    param(
      [Parameter(Mandatory=$true)][hashtable]$Proof,
      [Parameter(Mandatory=$true)][ValidateSet('transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting')][string]$ExpectedPhase
    )
    $deny={param($reason) New-CustomAppRealNativeJournalDeniedV024 -Reason ([string]$reason)}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        return (& $deny 'v024-hosted-only')
    }
    $required=@('Name','LiveAppPath','AllowedRoot','JournalStoreDirectory',
      'ConsumptionStoreDirectory','ExpectedJournalTransactionId',
      'ExpectedFinalizationFingerprint','Permit','SessionKey','PreparedResult',
      'StageExecutorResult','EvidenceBoundAtomicResult','LifecycleRow',
      'ProvenanceRow','BindingRow','LocalAppDataRoot','AppDataRoot','Now')
    foreach($key in $required){
        if(-not$Proof.ContainsKey($key) -or $null-eq$Proof[$key]){
            return (& $deny ('v024-required-proof-missing-'+$key))
        }
    }
    if([string]$Proof.Name -cne 'tagify'){return (& $deny 'v024-target-identity-denied')}
    $prepared=$Proof.PreparedResult
    $stage=$Proof.StageExecutorResult
    $atomic=$Proof.EvidenceBoundAtomicResult
    $jid=[string]$Proof.ExpectedJournalTransactionId
    $cid=[string]$stage.consumption_id
    $fin=[string]$Proof.ExpectedFinalizationFingerprint
    if($jid -cnotmatch '^[a-f0-9]{64}$' -or $cid -cnotmatch '^[a-f0-9]{64}$' -or
       $fin -cnotmatch '^[a-f0-9]{64}$' -or $jid -ceq $cid){
        return (& $deny 'v024-journal-permit-consumption-identity-invalid')
    }
    try {
        $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$Proof.AllowedRoot) -StoreDirectory ([string]$Proof.JournalStoreDirectory)
        $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$Proof.AllowedRoot) -StoreDirectory ([string]$Proof.JournalStoreDirectory) -ExpectedTransactionId $jid
    }catch{return (& $deny ('v024-persisted-journal-or-recovery-read-denied:'+[string]$_.Exception.Message))}
    if($null-eq$j -or -not[bool]$j.ok -or -not[bool]$j.reloaded_from_persistent_store -or
       [string]$j.transaction_id -cne $jid -or [string]$j.entry.phase -cne $ExpectedPhase -or
       [string]$j.entry.finalization_fingerprint -cne $fin -or
       [string]$j.entry.consumption_id -cne $cid -or
       [string]$j.entry.remote_commit_sha -cne [string]$stage.remote_commit_sha -or
       [string]$j.entry.source_identity -cne [string]$stage.source_identity -or
       [string]$j.entry.stage_result_fingerprint -cne [string]$prepared.stage_result_fingerprint -or
       [string]$j.entry.preparation_fingerprint -cne [string]$prepared.preparation_fingerprint -or
       [string]$j.entry.live_path -cne [string]$Proof.LiveAppPath -or
       $null-eq$ev -or -not[bool]$ev.ok -or
       [string]$ev.evidence_fingerprint -cne [string]$atomic.recovery_evidence_fingerprint){
        return (& $deny 'v024-journal-or-recovery-identity-drift')
    }
    if(-not[bool](Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 $atomic).ok -or
       [string]$atomic.transaction_id -cne $jid -or
       [string]$atomic.consumption_id -cne $cid -or
       [string]$prepared.consumption_id -cne $cid -or
       [string]$prepared.stage_tree_sha256 -cne [string]$stage.remote_tree_sha256 -or
       [string]$prepared.app_backup_tree_sha256 -cnotmatch '^[a-f0-9]{64}$'){
        return (& $deny 'v024-original-atomic-or-stage-receipt-drift')
    }
    try {
        $permit=Test-CustomAppProductionPostSwapPermitIntegrityV010 -Permit $Proof.Permit -SessionKey $Proof.SessionKey -Now $Proof.Now
        $bind=Test-CustomAppProductionPostSwapPermitStageContinuityV010 -Permit $Proof.Permit -StageExecutorResult $stage -Name $Proof.Name
        $cons=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $Proof.AllowedRoot -StoreDirectory $Proof.ConsumptionStoreDirectory -ExpectedConsumptionId $cid -Permit $Proof.Permit -StageExecutorResult $stage -Name $Proof.Name
        $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $Proof.LifecycleRow -ProvenanceRow $Proof.ProvenanceRow
        $b=Test-CustomAppStageBindingRowV010 -BindingRow $Proof.BindingRow -ExpectedName $Proof.Name
    }catch{return (& $deny 'v024-signed-permit-consumption-provenance-threw')}
    if(-not[bool]$permit.ok -or -not[bool]$bind.ok -or -not[bool]$cons.ok -or
       -not[bool]$cons.store.reloaded_from_persistent_store -or
       -not[bool]$elig.ok -or -not[bool]$b.ok -or
       [string]$b.remote_tree_sha256 -cne [string]$stage.remote_tree_sha256 -or
       [string]$b.commit_sha -cne [string]$stage.remote_commit_sha -or
       [string]$b.source -cne [string]$stage.source_identity){
        return (& $deny 'v024-current-signed-permit-consumption-or-binding-denied')
    }
    if([bool]$Proof.LifecycleRow.user_removed -or [bool]$Proof.LifecycleRow.ambiguous -or
       @($Proof.LifecycleRow.locations).Count -ne 1 -or
       -not([IO.Path]::GetFullPath([string]$Proof.LifecycleRow.locations[0])).Equals(
          [IO.Path]::GetFullPath([string]$Proof.LiveAppPath),[StringComparison]::OrdinalIgnoreCase)){
        return (& $deny 'v024-current-lifecycle-wrong-single-app')
    }
    try {
        $live=Get-CustomAppLocalRuntimeBaseline -Name $Proof.Name -AppPath $Proof.LiveAppPath
        $src=Get-CustomAppLocalRuntimeBaseline -Name $Proof.Name -AppPath ([string]$prepared.stage_path)
        $git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $Proof.LiveAppPath
        $backup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$prepared.app_backup_path)
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Proof.LocalAppDataRoot -AppDataRoot $Proof.AppDataRoot
        $old=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$atomic.old_live_path)
    }catch{return (& $deny ('v024-current-tree-or-backup-read-denied:'+[string]$_.Exception.Message))}
    if(-not[bool]$live.safe -or -not[bool]$live.installable -or
       -not[bool]$src.safe -or -not[bool]$src.installable -or
       [string]$live.tree_sha256 -cne [string]$stage.remote_tree_sha256 -or
       [string]$src.tree_sha256 -cne [string]$stage.remote_tree_sha256 -or
       [string]$live.manifest_name -cne [string]$Proof.BindingRow.binding.manifest_name -or
       [string]$old.tree_sha256 -cne [string]$prepared.app_backup_tree_sha256 -or
       [string]$backup.tree_sha256 -cne [string]$prepared.app_backup_tree_sha256 -or
       [string]$git.tree_sha256 -cne [string]$atomic.preserved_git_tree_sha256 -or
       [string]$persist.fingerprint -cne [string]$prepared.persistence_fingerprint){
        return (& $deny 'v024-current-whole-tree-backup-git-or-persistence-drift')
    }
    return [pscustomobject]@{
        ok=$true;reason='real-HMAC-whole-tree-journal-native-readonly-admission'
        name=[string]$Proof.Name;journal_transaction_id=$jid
        consumption_id=$cid;source_identity=[string]$stage.source_identity
        remote_commit_sha=[string]$stage.remote_commit_sha
        source_tree_sha256=[string]$live.tree_sha256
        journal_revision=[int64]$j.revision
        journal_entry_sha256=[string]$j.entry.entry_sha256
        recovery_evidence_fingerprint=[string]$ev.evidence_fingerprint
        signed_permit_and_whole_tree_bound=$true
        protected_source_verified=$true;real_vendor_authorized=$false
        mutation_authorized=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}
