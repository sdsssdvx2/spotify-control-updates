$CustomAppProductionDualIdNewPermitConsumptionSchema = 1
$CustomAppProductionDualIdNewPermitConsumptionManagedBy = 'custom-app-production-dual-id-new-permit-consumption-v1'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceHead = '12acf9d2cc6ed20e51abfe4287854505bc7df61e'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceCoreBlob = '629c09384ac13d2fe148566deffcc413f91cdc5d'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedSaveFixBlob = '3350cd974bb9f9ae7345e490449c4875d571bf95'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedInvokeFixBlob = '224b9df9d020b74bd4d99c85ca6d06e28999101b'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericHead = 'ed7fa27fc9bfaa78858e130743a2de508a3c0bf9'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericBlob = 'ac1459254ce060806a338a443c755bbc9f65c9a2'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionHead = 'af4e28791b4e5633cc97bb7f7bbab2bc3ad3fdf0'
$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionBlob = '731c6d096298199b784d3da8b3a9610ff880cd98'

function Get-CustomAppProductionDualIdNewPermitConsumptionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionDualIdNewPermitConsumptionHashV010 {
    param([AllowNull()][string]$Text)
    return (-not[string]::IsNullOrWhiteSpace($Text)-and$Text-cmatch'^[0-9a-f]{64}$')
}
function New-CustomAppProductionDualIdNewPermitConsumptionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()]$OriginalState=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;next_state=$OriginalState
        consumption_created=$false;consumption_persisted=$false;session_key_persisted=$false;session_key_exposed=$false
        persisted_reservation_attested=$false;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionDualIdNewPermitConsumptionReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_persistence_head,[string]$Receipt.qualified_persistence_core_blob,
        [string]$Receipt.qualified_save_fix_blob,[string]$Receipt.qualified_invoke_fix_blob,
        [string]$Receipt.qualified_generic_head,[string]$Receipt.qualified_generic_blob,
        [string]$Receipt.qualified_admission_head,[string]$Receipt.qualified_admission_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,
        [string]$Receipt.historical_permit_transaction_id,[string]$Receipt.historical_journal_transaction_id,[string]$Receipt.new_permit_transaction_id,
        [string]$Receipt.transaction_id_namespaces_pairwise_distinct,
        [string]$Receipt.issuer_fingerprint,[string]$Receipt.transaction_binding_hmac_sha256,[string]$Receipt.reservation_id,[string]$Receipt.reservation_fingerprint,
        [string]$Receipt.reservation_persistence_fingerprint,[string]$Receipt.reservation_persistence_envelope_sha256,[string]$Receipt.persisted_reservation_revision,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_nonce,[string]$Receipt.permit_hmac_sha256,
        [string]$Receipt.pre_consumption_admission_fingerprint,[string]$Receipt.post_consumption_admission_fingerprint,
        [string]$Receipt.consumption_id,[string]$Receipt.consumption_state_revision_before,[string]$Receipt.consumption_state_revision_after,
        [string]$Receipt.persisted_reservation_attested,[string]$Receipt.fresh_new_cycle_admission_revalidated,
        [string]$Receipt.consumption_created,[string]$Receipt.consumption_persisted,[string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,
        [string]$Receipt.requires_atomic_compare_and_swap_persistence,[string]$Receipt.requires_persisted_consumption_before_executor,
        [string]$Receipt.requires_fresh_permit_revalidation_at_executor_start,[string]$Receipt.requires_fresh_revalidation_after_stage,[string]$Receipt.requires_fresh_revalidation_before_apply,
        [string]$Receipt.consumption_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.executor_may_stage,[string]$Receipt.executor_may_apply,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized,[string]$Receipt.checked_at
    )-join([string][char]10)
}
function Test-CustomAppProductionDualIdNewPermitConsumptionReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-null'}}
    $required=@('schema','managed_by','qualified_persistence_head','qualified_persistence_core_blob','qualified_save_fix_blob','qualified_invoke_fix_blob','qualified_generic_head','qualified_generic_blob','qualified_admission_head','qualified_admission_blob','name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct','issuer_fingerprint','transaction_binding_hmac_sha256','reservation_id','reservation_fingerprint','reservation_persistence_fingerprint','reservation_persistence_envelope_sha256','persisted_reservation_revision','permit_token_id','permit_nonce','permit_hmac_sha256','pre_consumption_admission_fingerprint','post_consumption_admission_fingerprint','consumption_id','consumption_state_revision_before','consumption_state_revision_after','persisted_reservation_attested','fresh_new_cycle_admission_revalidated','consumption_created','consumption_persisted','session_key_accepted','session_key_persisted','session_key_exposed','requires_atomic_compare_and_swap_persistence','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','consumption_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','checked_at','consumption_fingerprint')
    foreach($f in $required){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne$CustomAppProductionDualIdNewPermitConsumptionSchema-or[string]$Receipt.managed_by-cne$CustomAppProductionDualIdNewPermitConsumptionManagedBy){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-owner-schema-invalid'}}
    foreach($p in @(
        @('qualified_persistence_head',$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceHead),
        @('qualified_persistence_core_blob',$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceCoreBlob),
        @('qualified_save_fix_blob',$CustomAppProductionDualIdNewPermitConsumptionQualifiedSaveFixBlob),
        @('qualified_invoke_fix_blob',$CustomAppProductionDualIdNewPermitConsumptionQualifiedInvokeFixBlob),
        @('qualified_generic_head',$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericHead),
        @('qualified_generic_blob',$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericBlob),
        @('qualified_admission_head',$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionHead),
        @('qualified_admission_blob',$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionBlob)
    )){if([string]$Receipt.($p[0])-cne[string]$p[1]){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-receipt-lineage-invalid-'+$p[0])}}}
    foreach($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','issuer_fingerprint','transaction_binding_hmac_sha256','reservation_id','reservation_fingerprint','reservation_persistence_fingerprint','reservation_persistence_envelope_sha256','permit_token_id','permit_hmac_sha256','pre_consumption_admission_fingerprint','post_consumption_admission_fingerprint','consumption_id','consumption_fingerprint')){
        if(-not(Test-CustomAppProductionDualIdNewPermitConsumptionHashV010 ([string]$Receipt.$f))){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-receipt-hash-invalid-'+$f)}}
    }
    if([string]$Receipt.permit_nonce-notmatch'^[0-9a-f]{32}$'){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-nonce-invalid'}}
    $a=[string]$Receipt.historical_permit_transaction_id;$b=[string]$Receipt.historical_journal_transaction_id;$c=[string]$Receipt.new_permit_transaction_id
    if($a-ceq$b-or$a-ceq$c-or$b-ceq$c-or-not[bool]$Receipt.transaction_id_namespaces_pairwise_distinct){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-transaction-namespaces-conflated'}}
    foreach($f in @('persisted_reservation_attested','fresh_new_cycle_admission_revalidated','consumption_created','session_key_accepted','requires_atomic_compare_and_swap_persistence','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){
        if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-receipt-required-flag-false-'+$f)}}
    }
    foreach($f in @('consumption_persisted','session_key_persisted','session_key_exposed','consumption_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){
        if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-receipt-authority-escaped-'+$f)}}
    }
    try {$before=[int64]$Receipt.consumption_state_revision_before;$after=[int64]$Receipt.consumption_state_revision_after;$persisted=[int64]$Receipt.persisted_reservation_revision;[void][DateTimeOffset]::Parse([string]$Receipt.checked_at)}catch{return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-time-or-revision-invalid'}}
    if($before-lt0-or$after-ne($before+1)-or$persisted-lt1){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-revision-invalid'}}
    if([string]$Receipt.pre_consumption_admission_fingerprint-cne[string]$Receipt.post_consumption_admission_fingerprint){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-admission-drift'}}
    $expected=Get-CustomAppProductionDualIdNewPermitConsumptionSha256V010(Get-CustomAppProductionDualIdNewPermitConsumptionReceiptMaterialV010 -Receipt $Receipt)
    if([string]$Receipt.consumption_fingerprint-cne$expected){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='dual-id-new-consumption-candidate-valid-zero-authority';consumption_id=[string]$Receipt.consumption_id;new_permit_transaction_id=$c;consumption_persisted=$false;executor_may_start=$false}
}
function Test-CustomAppProductionDualIdNewPermitConsumptionAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$PersistenceReceipt,[Parameter(Mandatory=$true)]$IssuerReceipt,[Parameter(Mandatory=$true)]$FreshAdmission)
    foreach($f in @('name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id')){
        if(([string]$PersistenceReceipt.$f).Trim().ToLowerInvariant()-cne([string]$FreshAdmission.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-persistence-admission-'+$f+'-mismatch')}}
    }
    if(([string]$PersistenceReceipt.pre_persistence_admission_fingerprint).Trim().ToLowerInvariant()-cne([string]$PersistenceReceipt.post_persistence_admission_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='dual-id-new-consumption-prior-persistence-admission-drift'}}
    # The fresh admission receipt embeds checked_at and eligible_until; do not incorrectly
    # demand cross-clock fingerprint equality. Recheck immutable/current identity instead.
    foreach($f in @('housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint')){
        if(([string]$IssuerReceipt.$f).Trim().ToLowerInvariant()-cne([string]$FreshAdmission.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-fresh-current-identity-'+$f+'-mismatch')}}
    }
    foreach($f in @('name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','issuer_fingerprint')){
        if(([string]$IssuerReceipt.$f).Trim().ToLowerInvariant()-cne([string]$PersistenceReceipt.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('dual-id-new-consumption-persistence-issuer-'+$f+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-consumption-identity-admission-continuity-exact'}
}
function Invoke-CustomAppProductionDualIdNewPermitConsumptionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ReservationPersistenceStoreDirectory,
        [Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,[Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$PriorReadinessReceipt,[Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ReservationPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ConsumptionState,[Parameter(Mandatory=$true)][int64]$ExpectedConsumptionRevision,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)New-CustomAppProductionDualIdNewPermitConsumptionDeniedV010 -Reason $Reason -OriginalState $ConsumptionState}
    if([string]::IsNullOrWhiteSpace($Name)-or$SessionKey.Length-lt32){return (& $deny -Reason 'dual-id-new-consumption-name-or-key-invalid')}
    $oldPermit=$HistoricalPermitTransactionId.Trim().ToLowerInvariant();$journal=$HistoricalJournalTransactionId.Trim().ToLowerInvariant();$new=$NewPermitTransactionId.Trim().ToLowerInvariant()
    foreach($id in @($oldPermit,$journal,$new)){if(-not(Test-CustomAppProductionDualIdNewPermitConsumptionHashV010 $id)){return (& $deny -Reason 'dual-id-new-consumption-transaction-id-invalid')}}
    if($oldPermit-ceq$journal-or$oldPermit-ceq$new-or$journal-ceq$new){return (& $deny -Reason 'dual-id-new-consumption-three-id-conflation')}
    if($null-eq$ReservationPersistenceResult-or-not[bool]$ReservationPersistenceResult.ok-or$null-eq$ReservationPersistenceResult.receipt){return (& $deny -Reason 'dual-id-new-consumption-persistence-result-invalid')}
    $pr=$ReservationPersistenceResult.receipt
    $prCheck=Test-CustomAppProductionDualIdNewPermitReservationPersistenceReceiptV010 -Receipt $pr
    if(-not[bool]$prCheck.ok){return (& $deny -Reason ('dual-id-new-consumption-persistence-receipt-invalid:'+[string]$prCheck.reason))}
    if($null-eq$IssuerResult-or-not[bool]$IssuerResult.ok-or$null-eq$IssuerResult.receipt-or$null-eq$IssuerResult.permit){return (& $deny -Reason 'dual-id-new-consumption-issuer-invalid')}
    $issued=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$IssuerResult.receipt.permit_issued_at,[ref]$issued)){return (& $deny -Reason 'dual-id-new-consumption-issuer-time-invalid')}
    $ic=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $issued.AddMilliseconds(1)
    if(-not[bool]$ic.ok){return (& $deny -Reason ('dual-id-new-consumption-issuer-hmac-invalid:'+[string]$ic.reason))}
    if(([string]$Permit.token_id).Trim().ToLowerInvariant()-cne([string]$IssuerResult.permit.token_id).Trim().ToLowerInvariant()-or([string]$Permit.hmac_sha256).Trim().ToLowerInvariant()-cne([string]$IssuerResult.permit.hmac_sha256).Trim().ToLowerInvariant()){
        return (& $deny -Reason 'dual-id-new-consumption-permit-issuer-token-mismatch')
    }
    foreach($p in @(@('historical_permit_transaction_id',$oldPermit),@('historical_journal_transaction_id',$journal),@('new_permit_transaction_id',$new))){
        if(([string]$pr.($p[0])).Trim().ToLowerInvariant()-cne[string]$p[1]){return (& $deny -Reason ('dual-id-new-consumption-persistence-id-mismatch-'+$p[0]))}
    }
    try {$store=Read-CustomAppProductionDualIdNewPermitReservationStoreV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $ReservationPersistenceStoreDirectory}catch{return (& $deny -Reason ('dual-id-new-consumption-durable-store-denied:'+[string]$_.Exception.Message))}
    if($null-eq$store-or-not[bool]$store.ok-or[string]$store.current_status-cne'matches-latest'-or$null-eq$store.envelope){return (& $deny -Reason 'dual-id-new-consumption-durable-store-not-current')}
    if([int64]$store.revision-ne[int64]$pr.persisted_revision-or([string]$store.envelope.envelope_sha256).Trim().ToLowerInvariant()-cne([string]$pr.persistence_envelope_sha256).Trim().ToLowerInvariant()){
        return (& $deny -Reason 'dual-id-new-consumption-durable-store-revision-or-sha-drift')
    }
    foreach($f in @('reservation_id','reservation_fingerprint','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','issuer_fingerprint','transaction_binding_hmac_sha256')){
        if(([string]$store.envelope.$f).Trim().ToLowerInvariant()-cne([string]$pr.$f).Trim().ToLowerInvariant()){return (& $deny -Reason ('dual-id-new-consumption-durable-envelope-'+$f+'-drift'))}
    }
    $stateCheck=Test-CustomAppProductionPermitReservationStateV010 -State $store.state
    if(-not[bool]$stateCheck.ok){return (& $deny -Reason ('dual-id-new-consumption-durable-reservation-state-invalid:'+[string]$stateCheck.reason))}
    $rows=@($store.state.reservations|Where-Object{([string]$_.reservation_id).Trim().ToLowerInvariant()-ceq([string]$pr.reservation_id).Trim().ToLowerInvariant()})
    if($rows.Count-ne1){return (& $deny -Reason 'dual-id-new-consumption-durable-reservation-row-not-unique')}
    $continuity=Test-CustomAppProductionReservationPermitContinuityV010 -ReservationRow $rows[0] -Permit $Permit
    if(-not[bool]$continuity.ok){return (& $deny -Reason ('dual-id-new-consumption-reservation-permit-invalid:'+[string]$continuity.reason))}
    $ctx=@{
        Name=$Name;LifecycleRow=$LifecycleRow;ProvenanceRow=$ProvenanceRow;BindingRow=$BindingRow;StageResult=$StageResult;ShadowResult=$ShadowResult;HousekeepingResult=$HousekeepingResult
        AllowedRoot=$AllowedRoot;StoreDirectory=$RecoveryStoreDirectory;HistoricalPermitTransactionId=$oldPermit;HistoricalJournalTransactionId=$journal;NewPermitTransactionId=$new
        LocalAppDataRoot=$LocalAppDataRoot;AppDataRoot=$AppDataRoot;CurrentBaseline=$CurrentBaseline;ShadowProtocolQualification=$ShadowProtocolQualification;LiveAttestedQualification=$LiveAttestedQualification
        PriorReadinessReceipt=$PriorReadinessReceipt;Now=$Now;MaxRemoteObservationAgeHours=$MaxRemoteObservationAgeHours
    }
    $pre=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 @ctx
    if($null-eq$pre-or-not[bool]$pre.ok){return (& $deny -Reason ('dual-id-new-consumption-pre-admission-denied:'+[string]$pre.reason))}
    $pc=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not[bool]$pc.ok){return (& $deny -Reason ('dual-id-new-consumption-pre-admission-invalid:'+[string]$pc.reason))}
    $ac=Test-CustomAppProductionDualIdNewPermitConsumptionAdmissionContinuityV010 -PersistenceReceipt $pr -IssuerReceipt $IssuerResult.receipt -FreshAdmission $pre.receipt
    if(-not[bool]$ac.ok){return (& $deny -Reason ([string]$ac.reason))}
    $consumed=Invoke-CustomAppProductionExecutorConsumptionV010 -Permit $Permit -ReservationId ([string]$pr.reservation_id) -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -ReservationState $store.state -ExpectedReservationRevision ([int64]$store.revision) -ConsumptionState $ConsumptionState -ExpectedConsumptionRevision $ExpectedConsumptionRevision -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$consumed-or-not[bool]$consumed.ok){return (& $deny -Reason ('dual-id-new-consumption-core-denied:'+[string]$consumed.reason))}
    $post=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 @ctx
    if($null-eq$post-or-not[bool]$post.ok){return (& $deny -Reason ('dual-id-new-consumption-post-admission-denied:'+[string]$post.reason))}
    $qc=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not[bool]$qc.ok){return (& $deny -Reason ('dual-id-new-consumption-post-admission-invalid:'+[string]$qc.reason))}
    $bc=Test-CustomAppProductionDualIdNewPermitConsumptionAdmissionContinuityV010 -PersistenceReceipt $pr -IssuerReceipt $IssuerResult.receipt -FreshAdmission $post.receipt
    if(-not[bool]$bc.ok){return (& $deny -Reason ('dual-id-new-consumption-post-'+[string]$bc.reason))}
    if(([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()-cne([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){
        return (& $deny -Reason 'dual-id-new-consumption-admission-drift-during-consumption')
    }
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionDualIdNewPermitConsumptionSchema;managed_by=$CustomAppProductionDualIdNewPermitConsumptionManagedBy
        qualified_persistence_head=$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceHead;qualified_persistence_core_blob=$CustomAppProductionDualIdNewPermitConsumptionQualifiedPersistenceCoreBlob
        qualified_save_fix_blob=$CustomAppProductionDualIdNewPermitConsumptionQualifiedSaveFixBlob;qualified_invoke_fix_blob=$CustomAppProductionDualIdNewPermitConsumptionQualifiedInvokeFixBlob
        qualified_generic_head=$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericHead;qualified_generic_blob=$CustomAppProductionDualIdNewPermitConsumptionQualifiedGenericBlob
        qualified_admission_head=$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionHead;qualified_admission_blob=$CustomAppProductionDualIdNewPermitConsumptionQualifiedAdmissionBlob
        name=([string]$pr.name).Trim().ToLowerInvariant();source_identity=([string]$pr.source_identity).Trim().ToLowerInvariant()
        historical_permit_transaction_id=$oldPermit;historical_journal_transaction_id=$journal;new_permit_transaction_id=$new;transaction_id_namespaces_pairwise_distinct=$true
        issuer_fingerprint=[string]$pr.issuer_fingerprint;transaction_binding_hmac_sha256=[string]$pr.transaction_binding_hmac_sha256
        reservation_id=[string]$pr.reservation_id;reservation_fingerprint=[string]$pr.reservation_fingerprint
        reservation_persistence_fingerprint=[string]$pr.persistence_fingerprint;reservation_persistence_envelope_sha256=[string]$pr.persistence_envelope_sha256;persisted_reservation_revision=[int64]$pr.persisted_revision
        permit_token_id=([string]$Permit.token_id).Trim().ToLowerInvariant();permit_nonce=([string]$Permit.nonce).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$Permit.hmac_sha256).Trim().ToLowerInvariant()
        pre_consumption_admission_fingerprint=[string]$pre.receipt.issuance_admission_fingerprint;post_consumption_admission_fingerprint=[string]$post.receipt.issuance_admission_fingerprint
        consumption_id=[string]$consumed.consumption_id;consumption_state_revision_before=[int64]$consumed.state_revision_before;consumption_state_revision_after=[int64]$consumed.state_revision_after
        persisted_reservation_attested=$true;fresh_new_cycle_admission_revalidated=$true;consumption_created=$true;consumption_persisted=$false;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true
        requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        checked_at=$Now.ToUniversalTime().ToString('o');consumption_fingerprint=$null
    }
    $receipt.consumption_fingerprint=Get-CustomAppProductionDualIdNewPermitConsumptionSha256V010(Get-CustomAppProductionDualIdNewPermitConsumptionReceiptMaterialV010 -Receipt $receipt)
    $ck=Test-CustomAppProductionDualIdNewPermitConsumptionReceiptV010 -Receipt $receipt
    if(-not[bool]$ck.ok){return (& $deny -Reason ('dual-id-new-consumption-output-invalid:'+[string]$ck.reason))}
    return [pscustomobject]@{
        ok=$true;reason='dual-id-new-single-use-consumption-created-requires-durable-persistence'
        receipt=$receipt;next_state=$consumed.next_state;consumption_id=[string]$consumed.consumption_id
        consumption_created=$true;consumption_persisted=$false;session_key_persisted=$false;session_key_exposed=$false
        persisted_reservation_attested=$true;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
