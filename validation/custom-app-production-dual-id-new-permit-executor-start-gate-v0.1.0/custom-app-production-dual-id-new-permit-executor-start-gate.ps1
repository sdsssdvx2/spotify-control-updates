# Validation-only new-cycle Triple-ID executor start eligibility. No stage/apply/mutation authority.
$DualIdNewExecutorStartSchema=1
$DualIdNewExecutorStartManagedBy='custom-app-production-dual-id-new-permit-executor-start-gate-v1'
$DualIdNewExecutorStartQualifiedPersistenceHead='33100251692a2486313456643842095a163267d6'
$DualIdNewExecutorStartQualifiedPersistenceCoreBlob='65799d084ea7fb18ac735c08c2f6b09abe7fd0ee'
$DualIdNewExecutorStartQualifiedGenericStartBlob='1fa3ca9e77b4c8a48ef56afd656fd102e1636676'
$DualIdNewExecutorStartQualifiedHistoricalStoreBlob='5712edc5a5c8720d3254d9f3a9f151042e8c5187'
$DualIdNewExecutorStartQualifiedAdmissionBlob='731c6d096298199b784d3da8b3a9610ff880cd98'
$DualIdNewExecutorStartQualifiedIssuerBlob='c3a79490d569798775696626d10f73485275c4bc'

function Get-DualIdNewExecutorStartShaV010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$h.Dispose()}
}
function Test-DualIdNewExecutorStartHashV010 {
    param([AllowNull()][string]$Value)
    return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function New-DualIdNewExecutorStartDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;decision=$null;staging_eligible=$false
        historical_persistence_attested=$false;current_consumption_reloaded=$false;fresh_issuance_admission_revalidated=$false
        session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true
        requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-DualIdNewExecutorStartMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    $fields=@(
        'schema','managed_by','qualified_persistence_head','qualified_persistence_core_blob',
        'qualified_generic_start_blob','qualified_historical_store_blob','qualified_admission_blob','qualified_issuer_blob',
        'name','source_identity','github_repo_id','surface_kind',
        'historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct',
        'consumption_id','consumption_persistence_fingerprint','issuer_fingerprint',
        'persisted_consumption_revision','historical_persistence_envelope_sha256',
        'current_consumption_store_revision','current_persistence_envelope_sha256',
        'pre_start_issuance_admission_fingerprint','post_start_issuance_admission_fingerprint',
        'generic_start_eligibility_fingerprint','evaluated_at','staging_eligibility_expires_at',
        'staging_eligible','historical_persistence_attested','current_consumption_reloaded','fresh_issuance_admission_revalidated',
        'session_key_accepted','session_key_persisted','session_key_exposed',
        'eligibility_is_authority','requires_fresh_revalidation_before_stage_acquisition',
        'requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply',
        'stage_acquisition_authorized','executor_may_start','executor_may_stage','executor_may_apply',
        'production_execution_authorized','production_mutation_authorized'
    )
    return (($fields|ForEach-Object{[string]$Receipt.PSObject.Properties[[string]$_].Value})-join([string][char]10))
}
function Test-DualIdNewExecutorStartReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='triple-id-start-receipt-null'}}
    $fields=@(
        'schema','managed_by','qualified_persistence_head','qualified_persistence_core_blob',
        'qualified_generic_start_blob','qualified_historical_store_blob','qualified_admission_blob','qualified_issuer_blob',
        'name','source_identity','github_repo_id','surface_kind','historical_permit_transaction_id',
        'historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct',
        'consumption_id','consumption_persistence_fingerprint','issuer_fingerprint',
        'persisted_consumption_revision','historical_persistence_envelope_sha256',
        'current_consumption_store_revision','current_persistence_envelope_sha256',
        'pre_start_issuance_admission_fingerprint','post_start_issuance_admission_fingerprint',
        'generic_start_eligibility_fingerprint','evaluated_at','staging_eligibility_expires_at',
        'staging_eligible','historical_persistence_attested','current_consumption_reloaded','fresh_issuance_admission_revalidated',
        'session_key_accepted','session_key_persisted','session_key_exposed','eligibility_is_authority',
        'requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage',
        'requires_fresh_revalidation_before_apply','stage_acquisition_authorized','executor_may_start',
        'executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','start_fingerprint'
    )
    foreach($f in $fields){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('triple-id-start-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne$DualIdNewExecutorStartSchema-or[string]$Receipt.managed_by-cne$DualIdNewExecutorStartManagedBy){return [pscustomobject]@{ok=$false;reason='triple-id-start-owner-invalid'}}
    foreach($pin in @(
        @('qualified_persistence_head',$DualIdNewExecutorStartQualifiedPersistenceHead),
        @('qualified_persistence_core_blob',$DualIdNewExecutorStartQualifiedPersistenceCoreBlob),
        @('qualified_generic_start_blob',$DualIdNewExecutorStartQualifiedGenericStartBlob),
        @('qualified_historical_store_blob',$DualIdNewExecutorStartQualifiedHistoricalStoreBlob),
        @('qualified_admission_blob',$DualIdNewExecutorStartQualifiedAdmissionBlob),
        @('qualified_issuer_blob',$DualIdNewExecutorStartQualifiedIssuerBlob)
    )){if([string]$Receipt.($pin[0])-cne[string]$pin[1]){return [pscustomobject]@{ok=$false;reason=('triple-id-start-lineage-'+$pin[0])}}}
    foreach($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id',
        'consumption_id','consumption_persistence_fingerprint','issuer_fingerprint',
        'historical_persistence_envelope_sha256','current_persistence_envelope_sha256',
        'pre_start_issuance_admission_fingerprint','post_start_issuance_admission_fingerprint',
        'generic_start_eligibility_fingerprint','start_fingerprint')){
        if(-not(Test-DualIdNewExecutorStartHashV010 ([string]$Receipt.$f))){return [pscustomobject]@{ok=$false;reason=('triple-id-start-hash-invalid-'+$f)}}
    }
    $old=[string]$Receipt.historical_permit_transaction_id;$journal=[string]$Receipt.historical_journal_transaction_id;$new=[string]$Receipt.new_permit_transaction_id
    if($old-ceq$journal-or$old-ceq$new-or$journal-ceq$new-or-not[bool]$Receipt.transaction_id_namespaces_pairwise_distinct){return [pscustomobject]@{ok=$false;reason='triple-id-start-ids-conflated'}}
    foreach($f in @('staging_eligible','historical_persistence_attested','current_consumption_reloaded','fresh_issuance_admission_revalidated','session_key_accepted',
        'requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){
        if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('triple-id-start-required-flag-false-'+$f)}}
    }
    foreach($f in @('session_key_persisted','session_key_exposed','eligibility_is_authority',
        'stage_acquisition_authorized','executor_may_start','executor_may_stage','executor_may_apply',
        'production_execution_authorized','production_mutation_authorized')){
        if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('triple-id-start-authority-escaped-'+$f)}}
    }
    try{
        $persisted=[int64]$Receipt.persisted_consumption_revision
        $current=[int64]$Receipt.current_consumption_store_revision
        $evaluated=[DateTimeOffset]::Parse([string]$Receipt.evaluated_at)
        $expires=[DateTimeOffset]::Parse([string]$Receipt.staging_eligibility_expires_at)
        [void][int64]$Receipt.github_repo_id
    }catch{return [pscustomobject]@{ok=$false;reason='triple-id-start-numeric-or-time-invalid'}}
    if($persisted-lt1-or$current-lt$persisted){return [pscustomobject]@{ok=$false;reason='triple-id-start-store-revision-regression'}}
    if($expires-le$evaluated-or$expires-gt$evaluated.AddSeconds(5)-or$Now-lt$evaluated.AddSeconds(-5)-or$Now-ge$expires){return [pscustomobject]@{ok=$false;reason='triple-id-start-eligibility-expired-or-invalid'}}
    if([string]$Receipt.pre_start_issuance_admission_fingerprint-cne[string]$Receipt.post_start_issuance_admission_fingerprint){return [pscustomobject]@{ok=$false;reason='triple-id-start-admission-drift'}}
    $expected=Get-DualIdNewExecutorStartShaV010 (Get-DualIdNewExecutorStartMaterialV010 -Receipt $Receipt)
    if([string]$Receipt.start_fingerprint-cne$expected){return [pscustomobject]@{ok=$false;reason='triple-id-start-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='triple-id-new-permit-start-staging-only-zero-authority';consumption_id=[string]$Receipt.consumption_id;production_mutation_authorized=$false}
}
function Test-DualIdNewExecutorStartContinuityV010 {
    param([AllowNull()]$PersistenceReceipt,[AllowNull()]$IssuerReceipt,[AllowNull()]$FreshAdmission,[AllowNull()]$Decision)
    if($null-eq$PersistenceReceipt-or$null-eq$IssuerReceipt-or$null-eq$FreshAdmission){return [pscustomobject]@{ok=$false;reason='triple-id-start-continuity-null'}}
    foreach($r in @($IssuerReceipt,$FreshAdmission)){
        foreach($f in @('name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id')){
            if([string]$PersistenceReceipt.$f-cne[string]$r.$f){return [pscustomobject]@{ok=$false;reason=('triple-id-start-continuity-'+$f+'-mismatch')}}
        }
    }
    if([string]$PersistenceReceipt.issuer_fingerprint-cne[string]$IssuerReceipt.issuer_fingerprint){return [pscustomobject]@{ok=$false;reason='triple-id-start-issuer-fingerprint-mismatch'}}
    if([string]$PersistenceReceipt.pre_persistence_admission_fingerprint-cne[string]$FreshAdmission.issuance_admission_fingerprint-or
       [string]$PersistenceReceipt.post_persistence_admission_fingerprint-cne[string]$FreshAdmission.issuance_admission_fingerprint){
        return [pscustomobject]@{ok=$false;reason='triple-id-start-issuance-admission-drift'}
    }
    if($null-ne$Decision){
        foreach($f in @('github_repo_id','surface_kind')){
            if(([string]$Decision.$f).Trim().ToLowerInvariant()-cne([string]$IssuerReceipt.$f).Trim().ToLowerInvariant()){
                return [pscustomobject]@{ok=$false;reason=('triple-id-start-decision-issuer-'+$f+'-mismatch')}
            }
        }
        foreach($p in @(@('name','name'),@('source_identity','source_identity'),
            @('current_tree_sha256','stable_live_tree_sha256'),@('remote_tree_sha256','current_remote_tree_sha256'),
            @('remote_commit_sha','current_remote_commit_sha'),@('current_eligibility_fingerprint','current_eligibility_fingerprint'),
            @('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','live_admission_fingerprint'))){
            if(([string]$Decision.($p[0])).Trim().ToLowerInvariant()-cne([string]$FreshAdmission.($p[1])).Trim().ToLowerInvariant()){
                return [pscustomobject]@{ok=$false;reason=('triple-id-start-decision-fresh-'+$p[0]+'-mismatch')}
            }
        }
    }
    return [pscustomobject]@{ok=$true;reason='triple-id-start-exact-continuity'}
}
function Resolve-DualIdNewExecutorStartGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$PriorReadinessReceipt,[Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ConsumptionPersistenceResult,[AllowNull()]$Permit,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)New-DualIdNewExecutorStartDeniedV010 -Reason $Reason}
    if($SessionKey.Length-lt32){return (& $deny 'triple-id-start-session-key-too-short')}
    if($null-eq$ConsumptionPersistenceResult-or-not[bool]$ConsumptionPersistenceResult.ok-or$null-eq$ConsumptionPersistenceResult.receipt-or$null-eq$ConsumptionPersistenceResult.persisted_snapshot){
        return (& $deny 'triple-id-start-persistence-result-invalid')
    }
    $pr=$ConsumptionPersistenceResult.receipt
    $prCheck=Test-DualIdNewConsumptionPersistenceReceiptV010 -Receipt $pr
    if(-not[bool]$prCheck.ok){return (& $deny ('triple-id-start-persistence-receipt-invalid:'+[string]$prCheck.reason))}
    if($null-eq$IssuerResult-or-not[bool]$IssuerResult.ok-or$null-eq$IssuerResult.receipt-or$null-eq$IssuerResult.permit){
        return (& $deny 'triple-id-start-issuer-result-invalid')
    }
    if($null-eq$Permit){return (& $deny 'triple-id-start-permit-missing')}
    $issued=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$IssuerResult.receipt.permit_issued_at,[ref]$issued)){return (& $deny 'triple-id-start-issuer-issued-time-invalid')}
    $issuerCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $issued.AddMilliseconds(1)
    if(-not[bool]$issuerCheck.ok){return (& $deny ('triple-id-start-issuer-hmac-invalid:'+[string]$issuerCheck.reason))}
    foreach($f in @('token_id','hmac_sha256','nonce')){
        if(([string]$Permit.$f).Trim().ToLowerInvariant()-cne([string]$IssuerResult.permit.$f).Trim().ToLowerInvariant()){
            return (& $deny ('triple-id-start-issued-permit-'+$f+'-mismatch'))
        }
    }
    $ids=@($HistoricalPermitTransactionId.Trim().ToLowerInvariant(),$HistoricalJournalTransactionId.Trim().ToLowerInvariant(),$NewPermitTransactionId.Trim().ToLowerInvariant())
    foreach($id in $ids){if(-not(Test-DualIdNewExecutorStartHashV010 $id)){return (& $deny 'triple-id-start-id-invalid')}}
    if($ids[0]-ceq$ids[1]-or$ids[0]-ceq$ids[2]-or$ids[1]-ceq$ids[2]){return (& $deny 'triple-id-start-id-conflation')}
    foreach($rec in @($pr,$IssuerResult.receipt)){
        foreach($p in @(@('historical_permit_transaction_id',$ids[0]),@('historical_journal_transaction_id',$ids[1]),@('new_permit_transaction_id',$ids[2]))){
            if(([string]$rec.($p[0])).Trim().ToLowerInvariant()-cne$p[1]){return (& $deny ('triple-id-start-'+$p[0]+'-mismatch'))}
        }
    }
    $nameKey=$Name.Trim().ToLowerInvariant()
    if($nameKey-cne([string]$pr.name).Trim().ToLowerInvariant()){return (& $deny 'triple-id-start-name-mismatch')}
    $snapshotCheck=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $ConsumptionPersistenceResult.persisted_snapshot -ExpectedConsumptionId ([string]$pr.consumption_id)
    if(-not[bool]$snapshotCheck.ok){return (& $deny ('triple-id-start-snapshot-barrier-invalid:'+[string]$snapshotCheck.reason))}
    $target=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -TargetState $ConsumptionPersistenceResult.persisted_snapshot.state -TargetRevision ([int64]$pr.persisted_revision) -ExpectedConsumptionId ([string]$pr.consumption_id)
    if($null-eq$target-or-not[bool]$target.ok){return (& $deny ('triple-id-start-historical-target-denied:'+[string]$target.reason))}
    if(([string]$target.target_envelope.envelope_sha256).Trim().ToLowerInvariant()-cne([string]$pr.persistence_envelope_sha256).Trim().ToLowerInvariant()){
        return (& $deny 'triple-id-start-historical-envelope-mismatch')
    }
    if([int64]$target.current_revision-lt[int64]$pr.current_store_revision_at_attestation){return (& $deny 'triple-id-start-store-rollback')}
    $ctx=@{
        Name=$Name;LifecycleRow=$LifecycleRow;ProvenanceRow=$ProvenanceRow;BindingRow=$BindingRow;StageResult=$StageResult;ShadowResult=$ShadowResult;HousekeepingResult=$HousekeepingResult;
        AllowedRoot=$AllowedRoot;StoreDirectory=$RecoveryStoreDirectory;HistoricalPermitTransactionId=$ids[0];HistoricalJournalTransactionId=$ids[1];NewPermitTransactionId=$ids[2];
        LocalAppDataRoot=$LocalAppDataRoot;AppDataRoot=$AppDataRoot;CurrentBaseline=$CurrentBaseline;ShadowProtocolQualification=$ShadowProtocolQualification;LiveAttestedQualification=$LiveAttestedQualification;
        PriorReadinessReceipt=$PriorReadinessReceipt;Now=$Now;MaxRemoteObservationAgeHours=$MaxRemoteObservationAgeHours
    }
    $pre=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 @ctx
    if($null-eq$pre-or-not[bool]$pre.ok){return (& $deny ('triple-id-start-pre-admission-denied:'+[string]$pre.reason))}
    $pc=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not[bool]$pc.ok){return (& $deny ('triple-id-start-pre-admission-invalid:'+[string]$pc.reason))}
    $continuity=Test-DualIdNewExecutorStartContinuityV010 -PersistenceReceipt $pr -IssuerReceipt $IssuerResult.receipt -FreshAdmission $pre.receipt
    if(-not[bool]$continuity.ok){return (& $deny ([string]$continuity.reason))}
    $start=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -ExpectedConsumptionId ([string]$pr.consumption_id) -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$start-or-not[bool]$start.ok-or-not[bool]$start.staging_eligible){return (& $deny ('triple-id-start-generic-denied:'+[string]$start.reason))}
    $startCheck=Test-CustomAppProductionExecutorStartEligibilityV010 -Decision $start.decision
    if(-not[bool]$startCheck.ok){return (& $deny ('triple-id-start-generic-decision-invalid:'+[string]$startCheck.reason))}
    if([string]$start.decision.consumption_id-cne[string]$pr.consumption_id-or[int64]$start.decision.consumption_store_revision-lt[int64]$target.current_revision){
        return (& $deny 'triple-id-start-generic-consumption-or-revision-mismatch')
    }
    $decisionContinuity=Test-DualIdNewExecutorStartContinuityV010 -PersistenceReceipt $pr -IssuerReceipt $IssuerResult.receipt -FreshAdmission $pre.receipt -Decision $start.decision
    if(-not[bool]$decisionContinuity.ok){return (& $deny ([string]$decisionContinuity.reason))}
    $post=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 @ctx
    if($null-eq$post-or-not[bool]$post.ok){return (& $deny ('triple-id-start-post-admission-denied:'+[string]$post.reason))}
    $postCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not[bool]$postCheck.ok){return (& $deny ('triple-id-start-post-admission-invalid:'+[string]$postCheck.reason))}
    $postContinuity=Test-DualIdNewExecutorStartContinuityV010 -PersistenceReceipt $pr -IssuerReceipt $IssuerResult.receipt -FreshAdmission $post.receipt -Decision $start.decision
    if(-not[bool]$postContinuity.ok){return (& $deny ('post-'+[string]$postContinuity.reason))}
    if([string]$pre.receipt.issuance_admission_fingerprint-cne[string]$post.receipt.issuance_admission_fingerprint){return (& $deny 'triple-id-start-admission-drift')}
    $expiry=[DateTimeOffset]::MinValue;$admissionExpiry=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$start.decision.staging_eligibility_expires_at,[ref]$expiry)-or
       -not[DateTimeOffset]::TryParse([string]$post.receipt.eligible_until,[ref]$admissionExpiry)){return (& $deny 'triple-id-start-expiry-invalid')}
    if($admissionExpiry-lt$expiry){$expiry=$admissionExpiry}
    if($expiry-gt$Now.AddSeconds(5)){$expiry=$Now.AddSeconds(5)}
    if($expiry-le$Now){return (& $deny 'triple-id-start-expiry-window-empty')}
    $receipt=[pscustomobject]@{
        schema=$DualIdNewExecutorStartSchema;managed_by=$DualIdNewExecutorStartManagedBy
        qualified_persistence_head=$DualIdNewExecutorStartQualifiedPersistenceHead;qualified_persistence_core_blob=$DualIdNewExecutorStartQualifiedPersistenceCoreBlob
        qualified_generic_start_blob=$DualIdNewExecutorStartQualifiedGenericStartBlob;qualified_historical_store_blob=$DualIdNewExecutorStartQualifiedHistoricalStoreBlob
        qualified_admission_blob=$DualIdNewExecutorStartQualifiedAdmissionBlob;qualified_issuer_blob=$DualIdNewExecutorStartQualifiedIssuerBlob
        name=$nameKey;source_identity=([string]$pr.source_identity).Trim().ToLowerInvariant()
        github_repo_id=[int64]$IssuerResult.receipt.github_repo_id;surface_kind=([string]$IssuerResult.receipt.surface_kind).Trim().ToLowerInvariant()
        historical_permit_transaction_id=$ids[0];historical_journal_transaction_id=$ids[1];new_permit_transaction_id=$ids[2];transaction_id_namespaces_pairwise_distinct=$true
        consumption_id=[string]$pr.consumption_id;consumption_persistence_fingerprint=[string]$pr.persistence_fingerprint;issuer_fingerprint=[string]$pr.issuer_fingerprint
        persisted_consumption_revision=[int64]$pr.persisted_revision;historical_persistence_envelope_sha256=[string]$pr.persistence_envelope_sha256
        current_consumption_store_revision=[int64]$start.decision.consumption_store_revision;current_persistence_envelope_sha256=[string]$start.decision.persistence_envelope_sha256
        pre_start_issuance_admission_fingerprint=[string]$pre.receipt.issuance_admission_fingerprint
        post_start_issuance_admission_fingerprint=[string]$post.receipt.issuance_admission_fingerprint
        generic_start_eligibility_fingerprint=[string]$start.decision.eligibility_fingerprint
        evaluated_at=$Now.ToUniversalTime().ToString('o');staging_eligibility_expires_at=$expiry.ToUniversalTime().ToString('o')
        staging_eligible=$true;historical_persistence_attested=$true;current_consumption_reloaded=$true;fresh_issuance_admission_revalidated=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true
        requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false;start_fingerprint=$null
    }
    $receipt.start_fingerprint=Get-DualIdNewExecutorStartShaV010 (Get-DualIdNewExecutorStartMaterialV010 -Receipt $receipt)
    $verified=Test-DualIdNewExecutorStartReceiptV010 -Receipt $receipt -Now $Now
    if(-not[bool]$verified.ok){return (& $deny ('triple-id-start-self-validation-failed:'+[string]$verified.reason))}
    return [pscustomobject]@{
        ok=$true;reason='triple-id-new-permit-persisted-consumption-freshly-revalidated-staging-only'
        receipt=$receipt;decision=$start.decision;staging_eligible=$true
        historical_persistence_attested=$true;current_consumption_reloaded=$true;fresh_issuance_admission_revalidated=$true
        session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true
        requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
