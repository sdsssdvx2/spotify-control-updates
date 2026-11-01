$CustomAppProductionRecoveryAwarePermitExecutorStartSchema = 1
$CustomAppProductionRecoveryAwarePermitExecutorStartManagedBy = 'custom-app-production-recovery-aware-permit-executor-start-gate-v1'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceHead = '26ee916c79fbe8a418361e22ce341517047d9d8e'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceCoreBlob = '5712edc5a5c8720d3254d9f3a9f151042e8c5187'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartHead = '29fe26f505d2f0fb8d9f47e76b5b819ebe1c129d'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartCoreBlob = '1fa3ca9e77b4c8a48ef56afd656fd102e1636676'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'

function Get-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitExecutorStartDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;decision=$null;staging_eligible=$false
        persisted_consumption_attested=$false;historical_consumption_envelope_attested=$false;fresh_recovery_admission_revalidated=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitExecutorStartAdmissionContinuityV010 {
    param([AllowNull()]$PersistenceReceipt,[AllowNull()]$FreshAdmission)
    if($null -eq $PersistenceReceipt -or $null -eq $FreshAdmission){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-admission-continuity-null'}}
    foreach($pair in @(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind')
    )){
        $a=([string]$PersistenceReceipt.($pair[0])).Trim().ToLowerInvariant();$b=([string]$FreshAdmission.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-persistence-fresh-'+$pair[0]+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-executor-start-persistence-fresh-continuity-exact'}
}

function Test-CustomAppProductionRecoveryAwarePermitExecutorStartDecisionContinuityV010 {
    param([AllowNull()]$Decision,[AllowNull()]$FreshAdmission)
    if($null -eq $Decision -or $null -eq $FreshAdmission){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-decision-continuity-null'}}
    foreach($pair in @(
        @('name','name'),@('source_identity','source_identity'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('current_tree_sha256','stable_live_tree_sha256'),@('remote_tree_sha256','current_remote_tree_sha256'),@('remote_commit_sha','current_remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','live_admission_fingerprint')
    )){
        $a=([string]$Decision.($pair[0])).Trim().ToLowerInvariant();$b=([string]$FreshAdmission.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-decision-fresh-'+$pair[0]+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-executor-start-decision-fresh-continuity-exact'}
}

function Get-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_consumption_persistence_head,[string]$Receipt.qualified_consumption_persistence_core_blob,
        [string]$Receipt.qualified_executor_start_head,[string]$Receipt.qualified_executor_start_core_blob,
        [string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.consumption_id,[string]$Receipt.consumption_persistence_fingerprint,[string]$Receipt.persisted_consumption_revision,
        [string]$Receipt.historical_persistence_envelope_sha256,[string]$Receipt.current_consumption_store_revision,[string]$Receipt.current_start_persistence_envelope_sha256,
        [string]$Receipt.pre_start_issuance_admission_fingerprint,[string]$Receipt.post_start_issuance_admission_fingerprint,
        [string]$Receipt.executor_start_eligibility_fingerprint,[string]$Receipt.evaluated_at,[string]$Receipt.staging_eligibility_expires_at,[string]$Receipt.staging_eligible,
        [string]$Receipt.persisted_consumption_attested,[string]$Receipt.historical_consumption_envelope_attested,[string]$Receipt.fresh_recovery_admission_revalidated,
        [string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,
        [string]$Receipt.eligibility_is_authority,[string]$Receipt.requires_fresh_revalidation_before_stage_acquisition,[string]$Receipt.requires_fresh_revalidation_after_stage,[string]$Receipt.requires_fresh_revalidation_before_apply,
        [string]$Receipt.stage_acquisition_authorized,[string]$Receipt.executor_may_start,[string]$Receipt.executor_may_stage,[string]$Receipt.executor_may_apply,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_consumption_persistence_head','qualified_consumption_persistence_core_blob','qualified_executor_start_head','qualified_executor_start_core_blob','qualified_issuance_admission_head','qualified_issuance_admission_core_blob',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','consumption_id','consumption_persistence_fingerprint','persisted_consumption_revision','historical_persistence_envelope_sha256','current_consumption_store_revision','current_start_persistence_envelope_sha256',
        'pre_start_issuance_admission_fingerprint','post_start_issuance_admission_fingerprint','executor_start_eligibility_fingerprint','evaluated_at','staging_eligibility_expires_at','staging_eligible',
        'persisted_consumption_attested','historical_consumption_envelope_attested','fresh_recovery_admission_revalidated','session_key_accepted','session_key_persisted','session_key_exposed','eligibility_is_authority',
        'requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','stage_acquisition_authorized','executor_may_start','executor_may_stage','executor_may_apply',
        'production_execution_authorized','production_mutation_authorized','start_fingerprint'
    )){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitExecutorStartSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitExecutorStartManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_consumption_persistence_head -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceHead -or [string]$Receipt.qualified_consumption_persistence_core_blob -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceCoreBlob -or [string]$Receipt.qualified_executor_start_head -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartHead -or [string]$Receipt.qualified_executor_start_core_blob -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartCoreBlob -or [string]$Receipt.qualified_issuance_admission_head -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionHead -or [string]$Receipt.qualified_issuance_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-lineage-mismatch'}}
    foreach($f in @('transaction_id','consumption_id','consumption_persistence_fingerprint','historical_persistence_envelope_sha256','current_start_persistence_envelope_sha256','pre_start_issuance_admission_fingerprint','post_start_issuance_admission_fingerprint','executor_start_eligibility_fingerprint','start_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-receipt-invalid-'+$f)}}}
    foreach($f in @('staging_eligible','persisted_consumption_attested','historical_consumption_envelope_attested','fresh_recovery_admission_revalidated','session_key_accepted','requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-receipt-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','eligibility_is_authority','stage_acquisition_authorized','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-executor-start-receipt-authority-escaped-'+$f)}}}
    try{$persisted=[int64]$Receipt.persisted_consumption_revision;$current=[int64]$Receipt.current_consumption_store_revision}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-revision-invalid'}}
    if($persisted -lt 1 -or $current -lt $persisted){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-revision-chain-invalid'}}
    if(([string]$Receipt.pre_start_issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_start_issuance_admission_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-admission-drift'}}
    $evaluated=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.evaluated_at,[ref]$evaluated) -or -not [DateTimeOffset]::TryParse([string]$Receipt.staging_eligibility_expires_at,[ref]$expires)){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-time-invalid'}}
    if($expires -le $evaluated -or $expires -gt $evaluated.AddSeconds(5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-window-invalid'}}
    if($Now -lt $evaluated.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-not-yet-valid'}}
    if($Now -ge $expires){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-expired'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 (Get-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.start_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-executor-start-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-executor-start-valid-staging-eligibility-zero-authority';consumption_id=([string]$Receipt.consumption_id).Trim().ToLowerInvariant();staging_eligibility_expires_at=[string]$Receipt.staging_eligibility_expires_at;production_mutation_authorized=$false}
}

function Resolve-CustomAppProductionRecoveryAwarePermitExecutorStartGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitExecutorStartDeniedV010 -Reason $Reason}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-executor-start-session-key-too-short'}
    if($null -eq $ConsumptionPersistenceResult -or -not [bool]$ConsumptionPersistenceResult.ok -or $null -eq $ConsumptionPersistenceResult.receipt -or $null -eq $ConsumptionPersistenceResult.persisted_snapshot){return & $deny 'recovery-aware-executor-start-persistence-result-invalid'}
    $pr=$ConsumptionPersistenceResult.receipt
    $prCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceReceiptV010 -Receipt $pr
    if(-not [bool]$prCheck.ok){return & $deny ('recovery-aware-executor-start-persistence-receipt-invalid:'+[string]$prCheck.reason)}
    $nameKey=$Name.Trim().ToLowerInvariant();$tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey) -or ([string]$pr.name).Trim().ToLowerInvariant() -cne $nameKey){return & $deny 'recovery-aware-executor-start-name-mismatch'}
    if(-not (Test-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 $tx) -or ([string]$pr.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-aware-executor-start-transaction-mismatch'}
    $snapshotBarrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $ConsumptionPersistenceResult.persisted_snapshot -ExpectedConsumptionId ([string]$pr.consumption_id)
    if($null -eq $snapshotBarrier -or -not [bool]$snapshotBarrier.ok){return & $deny ('recovery-aware-executor-start-persisted-snapshot-barrier-denied:'+[string]$snapshotBarrier.reason)}
    $target=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -TargetState $ConsumptionPersistenceResult.persisted_snapshot.state -TargetRevision ([int64]$pr.persisted_revision) -ExpectedConsumptionId ([string]$pr.consumption_id)
    if($null -eq $target -or -not [bool]$target.ok){return & $deny ('recovery-aware-executor-start-durable-target-denied:'+[string]$target.reason)}
    if(([string]$target.target_envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$pr.persistence_envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-executor-start-historical-envelope-mismatch'}
    if([int64]$target.current_revision -lt [int64]$pr.current_store_revision_at_attestation){return & $deny 'recovery-aware-executor-start-current-store-rollback'}

    $pre=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $pre -or -not [bool]$pre.ok){return & $deny ('recovery-aware-executor-start-pre-admission-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-executor-start-pre-admission-invalid:'+[string]$preCheck.reason)}
    $preContinuity=Test-CustomAppProductionRecoveryAwarePermitExecutorStartAdmissionContinuityV010 -PersistenceReceipt $pr -FreshAdmission $pre.receipt
    if(-not [bool]$preContinuity.ok){return & $deny ([string]$preContinuity.reason)}

    $start=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$pr.consumption_id) -Permit $Permit -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $start -or -not [bool]$start.ok -or -not [bool]$start.staging_eligible){return & $deny ('recovery-aware-executor-start-core-denied:'+[string]$start.reason)}
    $startCheck=Test-CustomAppProductionExecutorStartEligibilityV010 -Decision $start.decision
    if(-not [bool]$startCheck.ok){return & $deny ('recovery-aware-executor-start-core-decision-invalid:'+[string]$startCheck.reason)}
    if(([string]$start.decision.consumption_id).Trim().ToLowerInvariant() -cne ([string]$pr.consumption_id).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-executor-start-consumption-id-mismatch'}
    if([int64]$start.decision.consumption_store_revision -lt [int64]$target.current_revision){return & $deny 'recovery-aware-executor-start-observed-store-revision-regressed'}
    $startContinuity=Test-CustomAppProductionRecoveryAwarePermitExecutorStartDecisionContinuityV010 -Decision $start.decision -FreshAdmission $pre.receipt
    if(-not [bool]$startContinuity.ok){return & $deny ([string]$startContinuity.reason)}

    $post=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $post -or -not [bool]$post.ok){return & $deny ('recovery-aware-executor-start-post-admission-denied:'+[string]$post.reason)}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not [bool]$postCheck.ok){return & $deny ('recovery-aware-executor-start-post-admission-invalid:'+[string]$postCheck.reason)}
    $postContinuity=Test-CustomAppProductionRecoveryAwarePermitExecutorStartAdmissionContinuityV010 -PersistenceReceipt $pr -FreshAdmission $post.receipt
    if(-not [bool]$postContinuity.ok){return & $deny ('recovery-aware-executor-start-post-'+[string]$postContinuity.reason)}
    $postStartContinuity=Test-CustomAppProductionRecoveryAwarePermitExecutorStartDecisionContinuityV010 -Decision $start.decision -FreshAdmission $post.receipt
    if(-not [bool]$postStartContinuity.ok){return & $deny ('recovery-aware-executor-start-post-'+[string]$postStartContinuity.reason)}
    if(([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-executor-start-admission-drift-during-start-gate'}

    $startExpiry=[DateTimeOffset]::MinValue;$preExpiry=[DateTimeOffset]::MinValue;$postExpiry=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$start.decision.staging_eligibility_expires_at,[ref]$startExpiry) -or -not [DateTimeOffset]::TryParse([string]$pre.receipt.eligible_until,[ref]$preExpiry) -or -not [DateTimeOffset]::TryParse([string]$post.receipt.eligible_until,[ref]$postExpiry)){return & $deny 'recovery-aware-executor-start-eligibility-time-invalid'}
    $expires=$startExpiry;if($preExpiry -lt $expires){$expires=$preExpiry};if($postExpiry -lt $expires){$expires=$postExpiry};if($expires -le $Now){return & $deny 'recovery-aware-executor-start-eligibility-window-empty'}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitExecutorStartSchema;managed_by=$CustomAppProductionRecoveryAwarePermitExecutorStartManagedBy
        qualified_consumption_persistence_head=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceHead;qualified_consumption_persistence_core_blob=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedPersistenceCoreBlob
        qualified_executor_start_head=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartHead;qualified_executor_start_core_blob=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedStartCoreBlob
        qualified_issuance_admission_head=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionRecoveryAwarePermitExecutorStartQualifiedAdmissionCoreBlob
        name=$nameKey;source_identity=([string]$pr.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$pr.github_repo_id;surface_kind=([string]$pr.surface_kind).Trim().ToLowerInvariant()
        consumption_id=([string]$pr.consumption_id).Trim().ToLowerInvariant();consumption_persistence_fingerprint=([string]$pr.persistence_fingerprint).Trim().ToLowerInvariant();persisted_consumption_revision=[int64]$pr.persisted_revision
        historical_persistence_envelope_sha256=([string]$pr.persistence_envelope_sha256).Trim().ToLowerInvariant();current_consumption_store_revision=[int64]$start.decision.consumption_store_revision;current_start_persistence_envelope_sha256=([string]$start.decision.persistence_envelope_sha256).Trim().ToLowerInvariant()
        pre_start_issuance_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_start_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        executor_start_eligibility_fingerprint=([string]$start.decision.eligibility_fingerprint).Trim().ToLowerInvariant();evaluated_at=$Now.ToUniversalTime().ToString('o');staging_eligibility_expires_at=$expires.ToUniversalTime().ToString('o');staging_eligible=$true
        persisted_consumption_attested=$true;historical_consumption_envelope_attested=$true;fresh_recovery_admission_revalidated=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false;start_fingerprint=$null
    }
    $receipt.start_fingerprint=Get-CustomAppProductionRecoveryAwarePermitExecutorStartSha256V010 (Get-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitExecutorStartReceiptV010 -Receipt $receipt -Now $Now
    if(-not [bool]$receiptCheck.ok){return & $deny ('recovery-aware-executor-start-output-invalid:'+[string]$receiptCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-persisted-consumption-freshly-revalidated-staging-eligible-zero-authority';receipt=$receipt;decision=$start.decision;staging_eligible=$true
        persisted_consumption_attested=$true;historical_consumption_envelope_attested=$true;fresh_recovery_admission_revalidated=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;eligibility_is_authority=$false
        requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
