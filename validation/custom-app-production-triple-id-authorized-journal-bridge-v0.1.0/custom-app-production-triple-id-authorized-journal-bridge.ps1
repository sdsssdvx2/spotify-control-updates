# VALIDATION ONLY: never install. This binds ONE fresh third Triple-ID HMAC
# admission and durable single-use consumption to ONE evidence-bound journal swap.
# Does not enable the intentionally disabled production FullChain or apply.
$CustomAppProductionTripleIdAuthorizedJournalBridgeSchemaV010=1
$CustomAppProductionTripleIdAuthorizedJournalBridgeManagedByV010='custom-app-production-triple-id-authorized-journal-bridge-v1'
function New-CustomAppProductionTripleIdAuthorizedJournalBridgeDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$MutationAttempted=$false,[bool]$RequiresRecovery=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;mutation_attempted=$MutationAttempted;requires_recovery=$RequiresRecovery
        result=$null;atomic_result=$null;result_is_authority=$false
        spicetify_apply_authorized=$false;additional_mutation_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
        session_key_not_serialized=$true
    }
}
function Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 {
    param(
        [Parameter(Mandatory=$true)][hashtable]$AtomicPreconditionArgs,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
        [Parameter(Mandatory=$true)][string]$TransactionNonce,
        [DateTimeOffset]$JournalNow=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[bool]$Attempt=$false,[bool]$Recovery=$false)
        New-CustomAppProductionTripleIdAuthorizedJournalBridgeDeniedV010 -Reason $Reason -MutationAttempted $Attempt -RequiresRecovery $Recovery
    }
    # The bridge cannot be invoked on the user PC in this validation candidate.
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        return & $deny 'third-id-journal-bridge-hosted-windows-only'
    }
    if($TransactionNonce -cnotmatch '^[0-9a-fA-F]{32}$'){return & $deny 'third-id-journal-bridge-nonce-invalid'}
    $required=@('AllowedRoot','StoreDirectory','ExpectedConsumptionId','StageExecutorResult','PreparedResult','Permit','Name','LifecycleRow','ProvenanceRow','BindingRow','ShadowProtocolQualification','LiveAttestedQualification','SessionKey','LocalAppDataRoot','AppDataRoot','Now')
    foreach($key in $required){
        if(-not $AtomicPreconditionArgs.ContainsKey($key) -or $null -eq $AtomicPreconditionArgs[$key]){return & $deny ('third-id-journal-bridge-argument-missing-'+$key)}
    }
    foreach($key in $AtomicPreconditionArgs.Keys){
        if($key -notin ($required+@('MaxRemoteObservationAgeHours'))){return & $deny ('third-id-journal-bridge-argument-unknown-'+[string]$key)}
    }
    if(-not($AtomicPreconditionArgs.SessionKey -is [byte[]]) -or @($AtomicPreconditionArgs.SessionKey).Count -lt 16){return & $deny 'third-id-journal-bridge-invalid-ephemeral-hmac-key'}
    $name=[string]$AtomicPreconditionArgs.Name
    $allowed=[string]$AtomicPreconditionArgs.AllowedRoot
    $store=[string]$AtomicPreconditionArgs.StoreDirectory
    $cid=[string]$AtomicPreconditionArgs.ExpectedConsumptionId
    $stage=$AtomicPreconditionArgs.StageExecutorResult
    $prepared=$AtomicPreconditionArgs.PreparedResult
    $permit=$AtomicPreconditionArgs.Permit
    try {
        $base=[IO.Path]::GetFullPath($allowed).TrimEnd('\','/')
        $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $journalPath=[IO.Path]::GetFullPath($JournalStoreDirectory).TrimEnd('\','/')
        $consumptionPath=[IO.Path]::GetFullPath($store).TrimEnd('\','/')
        if(-not $base.Equals($runner,[StringComparison]::OrdinalIgnoreCase)){return & $deny 'third-id-journal-bridge-not-isolated-hosted-runner'}
        if(-not $journalPath.StartsWith(($base+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){return & $deny 'third-id-journal-bridge-journal-escaped-runner'}
        if([IO.Path]::GetFileName($journalPath).Length -lt 12 -or (Test-Path -LiteralPath $journalPath)){return & $deny 'third-id-journal-bridge-requires-fresh-journal'}
        $restricted=@($consumptionPath,[string]$prepared.stage_workspace_path,[string]$prepared.stage_path,[string]$prepared.app_backup_path,[string]$prepared.persistence_backup_path,[string]$AtomicPreconditionArgs.LifecycleRow.locations[0])
        foreach($raw in $restricted){
            $p=[IO.Path]::GetFullPath($raw).TrimEnd('\','/')
            if($p.Equals($journalPath,[StringComparison]::OrdinalIgnoreCase) -or
                $p.StartsWith(($journalPath+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase) -or
                $journalPath.StartsWith(($p+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
                return & $deny 'third-id-journal-bridge-restricted-path-overlap'
            }
        }
        $live=[IO.Path]::GetFullPath([string]$AtomicPreconditionArgs.LifecycleRow.locations[0]).TrimEnd('\','/')
    } catch {return & $deny ('third-id-journal-bridge-path-invalid:'+[string]$_.Exception.Message)}
    $pre=$null
    try{$pre=Test-CustomAppProductionAtomicPreconditionsV010 @AtomicPreconditionArgs}
    catch{return & $deny ('third-id-journal-bridge-hmac-preflight-threw:'+[string]$_.Exception.Message)}
    if($null -eq $pre -or -not[bool]$pre.ok -or $null -eq $pre.fresh_admission){return & $deny ('third-id-journal-bridge-hmac-preflight-denied:'+[string]$pre.reason)}
    $admission=$pre.fresh_admission
    if(([string]$admission.consumption_id).Trim().ToLowerInvariant() -cne $cid.Trim().ToLowerInvariant() -or
        ([string]$admission.admission_fingerprint).Trim().ToLowerInvariant() -cnotmatch '^[0-9a-f]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$admission.managed_by)){
        return & $deny 'third-id-journal-bridge-fresh-admission-identity-invalid'
    }
    # Additional independent read-back of the latest persisted single-use
    # consumption. A caller-supplied receipt or stale record is not sufficient.
    $durable=$null
    try{
        $identity=Test-CustomAppProductionPostSwapPermitStageContinuityV010 -Permit $permit -StageExecutorResult $stage -Name $name
        if($null -eq $identity -or -not[bool]$identity.ok){return & $deny ('third-id-journal-bridge-permit-stage-denied:'+[string]$identity.reason)}
        $durable=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $allowed -StoreDirectory $store -ExpectedConsumptionId $cid -Permit $permit -StageExecutorResult $stage -Name $name
        if($null -eq $durable -or -not[bool]$durable.ok -or $null -eq $durable.store -or -not[bool]$durable.store.reloaded_from_persistent_store){
            return & $deny ('third-id-journal-bridge-durable-consumption-denied:'+[string]$durable.reason)
        }
    }catch{return & $deny ('third-id-journal-bridge-durable-consumption-threw:'+[string]$_.Exception.Message)}
    # Never accept a caller-provided admission fingerprint. Derive every
    # mutation argument from the freshly validated preflight and prepared data.
    $args=@{
        GenericPreparedResult=$prepared;Name=$name
        CallerAdmissionManagedBy=[string]$admission.managed_by
        CallerAdmissionFingerprint=[string]$admission.admission_fingerprint
        AllowedRoot=$allowed;JournalStoreDirectory=$journalPath;TransactionNonce=$TransactionNonce
        ConsumptionId=$cid;SourceIdentity=[string]$prepared.source_identity
        RemoteCommitSha=[string]$prepared.remote_commit_sha
        StageResultFingerprint=[string]$prepared.stage_result_fingerprint
        PreparationFingerprint=[string]$prepared.preparation_fingerprint
        StageWorkspacePath=[string]$prepared.stage_workspace_path
        LivePath=$live;StagePath=[string]$prepared.stage_path
        ExpectedLiveRuntimeTreeSha256=[string]$pre.live_runtime.tree_sha256
        ExpectedLiveFullTreeSha256=[string]$pre.full_live.tree_sha256
        ExpectedLiveFullFileCount=[int]$pre.full_live.file_count
        ExpectedLiveFullTotalBytes=[int64]$pre.full_live.total_bytes
        ExpectedStageRuntimeTreeSha256=[string]$prepared.stage_tree_sha256
        AppBackupPath=[string]$prepared.app_backup_path
        ExpectedAppBackupTreeSha256=[string]$prepared.app_backup_tree_sha256
        ExpectedAppBackupFileCount=[int]$prepared.app_backup_file_count
        ExpectedAppBackupTotalBytes=[int64]$prepared.app_backup_total_bytes
        PersistenceBackupPath=[string]$prepared.persistence_backup_path
        ExpectedPersistenceFingerprint=[string]$prepared.persistence_fingerprint
        LocalAppDataRoot=[string]$AtomicPreconditionArgs.LocalAppDataRoot
        AppDataRoot=[string]$AtomicPreconditionArgs.AppDataRoot;Now=$JournalNow
    }
    $mut=$null
    try{$mut=Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 @args}
    catch{return & $deny ('third-id-journal-bridge-atomic-threw-needs-inspection:'+[string]$_.Exception.Message) $true $true}
    if($null -eq $mut -or -not[bool]$mut.ok){
        return & $deny ('third-id-journal-bridge-atomic-denied:'+[string]$mut.reason) $true ([bool]$mut.requires_recovery)
    }
    $receipt=Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 -Result $mut.result
    if($null -eq $receipt -or -not[bool]$receipt.ok){return & $deny 'third-id-journal-bridge-atomic-result-invalid' $true $true}
    try{
        $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $allowed -StoreDirectory $journalPath
        $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $allowed -StoreDirectory $journalPath -ExpectedTransactionId ([string]$mut.result.transaction_id)
        if(-not[bool]$journal.ok -or -not[bool]$journal.reloaded_from_persistent_store -or
            [string]$journal.entry.phase -cne 'candidate-live' -or [string]$journal.entry.consumption_id -cne $cid -or
            [string]$journal.transaction_id -cne [string]$mut.result.transaction_id -or
            [string]$journal.entry.entry_sha256 -cne [string]$mut.result.journal_entry_sha256 -or
            -not[bool]$evidence.ok -or [string]$evidence.evidence_fingerprint -cne [string]$mut.result.recovery_evidence_fingerprint){
            return & $deny 'third-id-journal-bridge-durable-journal-evidence-readback-invalid' $true $true
        }
    }catch{return & $deny ('third-id-journal-bridge-durable-readback-threw:'+[string]$_.Exception.Message) $true $true}
    return [pscustomobject]@{
        ok=$true;reason='third-id-hmac-durable-consumption-journal-atomic-verified'
        result=$mut.result;atomic_result=$mut.result;mutation_attempted=$true;requires_recovery=$true
        journal_phase='candidate-live';journal_revision=[int64]$journal.revision
        transaction_id=[string]$mut.result.transaction_id
        recovery_evidence_fingerprint=[string]$mut.result.recovery_evidence_fingerprint
        durable_consumption_envelope_sha256=[string]$durable.current_envelope_sha256
        session_key_not_serialized=$true;result_is_authority=$false
        spicetify_apply_authorized=$false;additional_mutation_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
