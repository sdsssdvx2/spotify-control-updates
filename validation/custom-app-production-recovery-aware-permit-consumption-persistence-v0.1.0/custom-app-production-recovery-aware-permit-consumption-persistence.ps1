$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSchema = 1
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceManagedBy = 'custom-app-production-recovery-aware-permit-consumption-persistence-v1'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionHead = '5e6644d94be2440222e4a23613edce0610ad3545'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionCoreBlob = '9945b980c6cf8e09e8d929820a7db13fdccda545'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreHead = '1b680f0fc637b393aa7571690c8aa40adda59800'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreCoreBlob = 'd5b70c943d0880e98ee907ae52d4c02ad8720f73'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreContractBlob = '07de3a6d3aec00636d8b1c7bd20dcbc72d1b7ada'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'

function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$Persisted=$false,[AllowNull()]$PersistedSnapshot=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;persisted_snapshot=$PersistedSnapshot
        consumption_persisted=$Persisted;read_after_write_verified=$Persisted;persisted_consumption_barrier_attested=$false
        recovery_aware_persistence_revalidated=$false;write_performed=$false;recovered_existing_persistence=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true
        requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionCandidateV010 {
    param([AllowNull()]$ConsumptionResult)
    if($null -eq $ConsumptionResult -or -not [bool]$ConsumptionResult.ok -or $null -eq $ConsumptionResult.receipt -or $null -eq $ConsumptionResult.next_state){return [pscustomobject]@{ok=$false;reason='consumption-result-null-or-not-ok'}}
    $r=$ConsumptionResult.receipt
    $rc=Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 -Receipt $r
    if(-not [bool]$rc.ok){return [pscustomobject]@{ok=$false;reason=('consumption-receipt-invalid:'+[string]$rc.reason)}}
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $ConsumptionResult.next_state
    if(-not [bool]$stateCheck.ok){return [pscustomobject]@{ok=$false;reason=('consumption-next-state-invalid:'+[string]$stateCheck.reason)}}
    try{$before=[int64]$r.consumption_state_revision_before;$after=[int64]$r.consumption_state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='consumption-receipt-revision-invalid'}}
    if([int64]$ConsumptionResult.next_state.revision -ne $after -or $after -ne ($before+1)){return [pscustomobject]@{ok=$false;reason='consumption-result-revision-mismatch'}}
    $rows=@($ConsumptionResult.next_state.consumptions)
    if($rows.Count -ne $after -or $rows.Count -lt 1){return [pscustomobject]@{ok=$false;reason='consumption-result-row-count-mismatch'}}
    $row=$rows[-1]
    foreach($pair in @(
        @('consumption_id','consumption_id'),@('reservation_id','reservation_id'),@('token_id','permit_token_id'),@('permit_nonce','permit_nonce'),@('permit_hmac_sha256','permit_hmac_sha256'),
        @('name','name'),@('source_identity','source_identity'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('current_tree_sha256','current_tree_sha256'),@('remote_tree_sha256','remote_tree_sha256'),@('remote_commit_sha','remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','admission_fingerprint'),
        @('state_revision_before','consumption_state_revision_before'),@('state_revision_after','consumption_state_revision_after')
    )){
        $a=([string]$row.($pair[0])).Trim().ToLowerInvariant();$b=([string]$r.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('consumption-result-row-receipt-mismatch-'+$pair[0])}}
    }
    if(-not [bool]$r.single_use_consumption_candidate_created -or [bool]$r.consumption_persisted -or [bool]$r.executor_may_start -or [bool]$r.production_execution_authorized -or [bool]$r.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason='consumption-result-authority-or-persistence-contract-invalid'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-consumption-candidate-bound-to-next-state';receipt=$r;next_state=$ConsumptionResult.next_state;last_row=$row;before=$before;after=$after}
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceAdmissionContinuityV010 {
    param([AllowNull()]$ConsumptionReceipt,[AllowNull()]$FreshAdmission)
    if($null -eq $ConsumptionReceipt -or $null -eq $FreshAdmission){return [pscustomobject]@{ok=$false;reason='consumption-persistence-admission-continuity-null'}}
    foreach($pair in @(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('current_tree_sha256','stable_live_tree_sha256'),@('remote_tree_sha256','current_remote_tree_sha256'),@('remote_commit_sha','current_remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','live_admission_fingerprint')
    )){
        $a=([string]$ConsumptionReceipt.($pair[0])).Trim().ToLowerInvariant();$b=([string]$FreshAdmission.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('consumption-persistence-fresh-'+$pair[0]+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='consumption-persistence-fresh-admission-continuity-exact'}
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceStateEqualsV010 {
    param([AllowNull()]$Left,[AllowNull()]$Right)
    if($null -eq $Left -or $null -eq $Right){return $false}
    return (($Left|ConvertTo-Json -Depth 60 -Compress) -ceq ($Right|ConvertTo-Json -Depth 60 -Compress))
}

function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)]$TargetState,[Parameter(Mandatory=$true)][int64]$TargetRevision,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId
    )
    try{$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return [pscustomobject]@{ok=$false;reason=('consumption-persistence-path-denied:'+[string]$_.Exception.Message)}}
    $lock=$null
    try{
        try{$lock=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths}catch{return [pscustomobject]@{ok=$false;reason=[string]$_.Exception.Message}}
        try{$current=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths}catch{return [pscustomobject]@{ok=$false;reason=('consumption-persistence-read-denied:'+[string]$_.Exception.Message)}}
        if(-not [bool]$current.ok){return [pscustomobject]@{ok=$false;reason=[string]$current.reason;initialized=$false}}
        if([int64]$current.revision -lt $TargetRevision){return [pscustomobject]@{ok=$false;reason='consumption-persistence-target-revision-not-yet-present';initialized=$true;current_revision=[int64]$current.revision;state=$current.state;envelope=$current.envelope}}
        $targetEnvelope=$null
        if([int64]$current.revision -eq $TargetRevision){$targetEnvelope=$current.envelope}
        else {
            $pattern=('{0:D20}-*.json' -f $TargetRevision)
            $files=@(Get-ChildItem -LiteralPath ([string]$paths.history) -File -Filter $pattern -Force)
            if($files.Count -ne 1){return [pscustomobject]@{ok=$false;reason='consumption-persistence-historical-envelope-not-unique';initialized=$true;current_revision=[int64]$current.revision}}
            try{$targetEnvelope=(ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 -Path $files[0].FullName).envelope}catch{return [pscustomobject]@{ok=$false;reason=('consumption-persistence-historical-envelope-invalid:'+[string]$_.Exception.Message);initialized=$true;current_revision=[int64]$current.revision}}
        }
        if([int64]$targetEnvelope.revision -ne $TargetRevision -or -not (Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceStateEqualsV010 -Left $targetEnvelope.state -Right $TargetState)){return [pscustomobject]@{ok=$false;reason='consumption-persistence-existing-target-conflict';initialized=$true;current_revision=[int64]$current.revision}}
        $rows=@($targetEnvelope.state.consumptions)
        if($rows.Count -ne $TargetRevision -or $rows.Count -lt 1 -or ([string]$rows[-1].consumption_id).Trim().ToLowerInvariant() -cne $ExpectedConsumptionId.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='consumption-persistence-existing-target-id-mismatch';initialized=$true;current_revision=[int64]$current.revision}}
        $snapshot=[pscustomobject]@{ok=$true;reason='consumption-store-historical-target-reloaded';initialized=$true;revision=$TargetRevision;state=$targetEnvelope.state;envelope=$targetEnvelope;history_count=[int]$current.history_count;current_matches_history=$true;reloaded_from_persistent_store=$true;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
        return [pscustomobject]@{ok=$true;reason='consumption-persistence-target-already-durable';initialized=$true;recovered_existing_persistence=$true;write_performed=$false;target_snapshot=$snapshot;target_envelope=$targetEnvelope;target_revision=$TargetRevision;current_revision=[int64]$current.revision;current_state=$current.state;current_envelope=$current.envelope}
    } finally {if($null -ne $lock){$lock.Dispose()}}
}

function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_consumption_head,[string]$Receipt.qualified_consumption_core_blob,
        [string]$Receipt.qualified_store_head,[string]$Receipt.qualified_store_core_blob,[string]$Receipt.qualified_store_contract_blob,
        [string]$Receipt.qualified_admission_head,[string]$Receipt.qualified_admission_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.consumption_id,[string]$Receipt.consumption_candidate_fingerprint,[string]$Receipt.consumption_state_revision_before,[string]$Receipt.consumption_state_revision_after,
        [string]$Receipt.pre_persistence_admission_fingerprint,[string]$Receipt.post_persistence_admission_fingerprint,
        [string]$Receipt.persistence_envelope_sha256,[string]$Receipt.persisted_revision,[string]$Receipt.current_store_revision_at_attestation,
        [string]$Receipt.consumption_persisted,[string]$Receipt.read_after_write_verified,[string]$Receipt.persisted_consumption_barrier_attested,[string]$Receipt.recovery_aware_persistence_revalidated,
        [string]$Receipt.write_performed,[string]$Receipt.recovered_existing_persistence,[string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,
        [string]$Receipt.requires_persisted_consumption_before_executor,[string]$Receipt.requires_fresh_permit_revalidation_at_executor_start,[string]$Receipt.requires_fresh_revalidation_after_stage,[string]$Receipt.requires_fresh_revalidation_before_apply,
        [string]$Receipt.persistence_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.executor_may_stage,[string]$Receipt.executor_may_apply,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized,[string]$Receipt.checked_at
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_consumption_head','qualified_consumption_core_blob','qualified_store_head','qualified_store_core_blob','qualified_store_contract_blob','qualified_admission_head','qualified_admission_core_blob','name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_candidate_fingerprint','consumption_state_revision_before','consumption_state_revision_after','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','persistence_envelope_sha256','persisted_revision','current_store_revision_at_attestation','consumption_persisted','read_after_write_verified','persisted_consumption_barrier_attested','recovery_aware_persistence_revalidated','write_performed','recovered_existing_persistence','session_key_accepted','session_key_persisted','session_key_exposed','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','checked_at','persistence_fingerprint')){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_consumption_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionHead -or [string]$Receipt.qualified_consumption_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionCoreBlob -or [string]$Receipt.qualified_store_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreHead -or [string]$Receipt.qualified_store_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreCoreBlob -or [string]$Receipt.qualified_store_contract_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreContractBlob -or [string]$Receipt.qualified_admission_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionHead -or [string]$Receipt.qualified_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_candidate_fingerprint','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','persistence_envelope_sha256','persistence_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-receipt-invalid-'+$f)}}}
    foreach($f in @('consumption_persisted','read_after_write_verified','persisted_consumption_barrier_attested','recovery_aware_persistence_revalidated','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-receipt-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_accepted','session_key_persisted','session_key_exposed','persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-receipt-authority-escaped-'+$f)}}}
    if([bool]$Receipt.write_performed -eq [bool]$Receipt.recovered_existing_persistence){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-write-recovery-flags-invalid'}}
    try{$before=[int64]$Receipt.consumption_state_revision_before;$after=[int64]$Receipt.consumption_state_revision_after;$persisted=[int64]$Receipt.persisted_revision;$current=[int64]$Receipt.current_store_revision_at_attestation}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-revision-invalid'}}
    if($before -lt 0 -or $after -ne ($before+1) -or $persisted -ne $after -or $current -lt $persisted){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-revision-chain-invalid'}}
    if(([string]$Receipt.pre_persistence_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_persistence_admission_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-admission-drift'}}
    try{[void][DateTimeOffset]::Parse([string]$Receipt.checked_at)}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.persistence_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-consumption-persistence-valid-zero-authority';consumption_id=([string]$Receipt.consumption_id).Trim().ToLowerInvariant();persisted_revision=$persisted;executor_may_start=$false;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionResult,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason,[bool]$Persisted=$false,[AllowNull()]$Snapshot=$null) New-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceDeniedV010 -Reason $Reason -Persisted:$Persisted -PersistedSnapshot $Snapshot}
    $candidate=Test-CustomAppProductionRecoveryAwarePermitConsumptionCandidateV010 -ConsumptionResult $ConsumptionResult
    if(-not [bool]$candidate.ok){return & $deny ('recovery-aware-consumption-persistence-candidate-invalid:'+[string]$candidate.reason)}
    $r=$candidate.receipt;$nameKey=$Name.Trim().ToLowerInvariant();$tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey) -or ([string]$r.name).Trim().ToLowerInvariant() -cne $nameKey){return & $deny 'recovery-aware-consumption-persistence-name-mismatch'}
    if(-not (Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 $tx) -or ([string]$r.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-aware-consumption-persistence-transaction-mismatch'}

    $pre=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $pre -or -not [bool]$pre.ok){return & $deny ('recovery-aware-consumption-persistence-pre-admission-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-consumption-persistence-pre-admission-invalid:'+[string]$preCheck.reason)}
    $preContinuity=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceAdmissionContinuityV010 -ConsumptionReceipt $r -FreshAdmission $pre.receipt
    if(-not [bool]$preContinuity.ok){return & $deny ([string]$preContinuity.reason)}

    try{$initial=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory}catch{return & $deny ('recovery-aware-consumption-persistence-store-read-denied:'+[string]$_.Exception.Message)}
    if(-not [bool]$initial.ok){
        if([string]$initial.reason -cne 'consumption-store-uninitialized'){return & $deny ('recovery-aware-consumption-persistence-store-not-ready:'+[string]$initial.reason)}
        if([int64]$candidate.before -ne 0){return & $deny 'recovery-aware-consumption-persistence-uninitialized-store-nonzero-candidate-base'}
        try{$init=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -Now $Now}catch{return & $deny ('recovery-aware-consumption-persistence-initialize-denied:'+[string]$_.Exception.Message)}
        if($null -eq $init -or -not [bool]$init.ok){return & $deny ('recovery-aware-consumption-persistence-initialize-failed:'+[string]$init.reason)}
        $initial=$init
    }

    $existing=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -TargetState $candidate.next_state -TargetRevision ([int64]$candidate.after) -ExpectedConsumptionId ([string]$r.consumption_id)
    $persistedSnapshot=$null;$writePerformed=$false;$recovered=$false;$currentRevisionAtAttestation=$null
    if([bool]$existing.ok){
        $persistedSnapshot=$existing.target_snapshot;$writePerformed=$false;$recovered=$true;$currentRevisionAtAttestation=[int64]$existing.current_revision
    } else {
        if([string]$existing.reason -notin @('consumption-persistence-target-revision-not-yet-present')){return & $deny ('recovery-aware-consumption-persistence-existing-target-denied:'+[string]$existing.reason)}
        if(-not $existing.PSObject.Properties['current_revision'] -or [int64]$existing.current_revision -ne [int64]$candidate.before){return & $deny 'recovery-aware-consumption-persistence-store-revision-conflict'}
        $saved=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -NextState $candidate.next_state -ExpectedCurrentRevision ([int64]$candidate.before) -Now $Now -FailurePoint $FailurePoint
        if($null -eq $saved -or -not [bool]$saved.ok){return & $deny ('recovery-aware-consumption-persistence-save-denied:'+[string]$saved.reason) ([bool]($null -ne $saved -and $saved.persisted)) $saved}
        $persistedSnapshot=$saved;$writePerformed=$true;$recovered=$false;$currentRevisionAtAttestation=[int64]$saved.revision
    }

    $barrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $persistedSnapshot -ExpectedConsumptionId ([string]$r.consumption_id)
    if($null -eq $barrier -or -not [bool]$barrier.ok){return & $deny ('recovery-aware-consumption-persistence-barrier-denied:'+[string]$barrier.reason) $true $persistedSnapshot}

    $post=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $post -or -not [bool]$post.ok){return & $deny ('recovery-aware-consumption-persistence-post-admission-denied:'+[string]$post.reason) $true $persistedSnapshot}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not [bool]$postCheck.ok){return & $deny ('recovery-aware-consumption-persistence-post-admission-invalid:'+[string]$postCheck.reason) $true $persistedSnapshot}
    $postContinuity=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceAdmissionContinuityV010 -ConsumptionReceipt $r -FreshAdmission $post.receipt
    if(-not [bool]$postContinuity.ok){return & $deny ('recovery-aware-consumption-persistence-post-'+[string]$postContinuity.reason) $true $persistedSnapshot}
    if(([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-consumption-persistence-admission-drift-during-persistence' $true $persistedSnapshot}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSchema;managed_by=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceManagedBy
        qualified_consumption_head=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionHead;qualified_consumption_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedConsumptionCoreBlob
        qualified_store_head=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreHead;qualified_store_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreCoreBlob;qualified_store_contract_blob=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedStoreContractBlob
        qualified_admission_head=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionHead;qualified_admission_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionPersistenceQualifiedAdmissionCoreBlob
        name=$nameKey;source_identity=([string]$r.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$r.github_repo_id;surface_kind=([string]$r.surface_kind).Trim().ToLowerInvariant()
        consumption_id=([string]$r.consumption_id).Trim().ToLowerInvariant();consumption_candidate_fingerprint=([string]$r.consumption_fingerprint).Trim().ToLowerInvariant();consumption_state_revision_before=[int64]$candidate.before;consumption_state_revision_after=[int64]$candidate.after
        pre_persistence_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_persistence_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$persistedSnapshot.envelope.envelope_sha256).Trim().ToLowerInvariant();persisted_revision=[int64]$candidate.after;current_store_revision_at_attestation=[int64]$currentRevisionAtAttestation
        consumption_persisted=$true;read_after_write_verified=$true;persisted_consumption_barrier_attested=$true;recovery_aware_persistence_revalidated=$true
        write_performed=$writePerformed;recovered_existing_persistence=$recovered;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        checked_at=$Now.ToUniversalTime().ToString('o');persistence_fingerprint=$null
    }
    $receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $receipt
    if(-not [bool]$receiptCheck.ok){return & $deny ('recovery-aware-consumption-persistence-output-invalid:'+[string]$receiptCheck.reason) $true $persistedSnapshot}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-consumption-durably-persisted-barrier-attested-zero-authority';receipt=$receipt;persisted_snapshot=$persistedSnapshot
        consumption_persisted=$true;read_after_write_verified=$true;persisted_consumption_barrier_attested=$true;recovery_aware_persistence_revalidated=$true
        write_performed=$writePerformed;recovered_existing_persistence=$recovered;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
