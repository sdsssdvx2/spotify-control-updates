# Validation-only durable barrier for a new-cycle, triple-ID-bound consumption.
# Requires the exact qualified generic append-only consumption store and its v0.1.1 contract overlay.
$DualIdNewConsumptionPersistenceSchema=1
$DualIdNewConsumptionPersistenceManagedBy='custom-app-production-dual-id-new-permit-consumption-persistence-v1'
$DualIdNewConsumptionPersistenceQualifiedConsumptionHead='cc7a4d8d1f17e963961799c489d449902d06225d'
$DualIdNewConsumptionPersistenceQualifiedConsumptionBlob='048fdda7bf8b03810cec18803e6ab094e56e831e'
$DualIdNewConsumptionPersistenceQualifiedStoreBlob='d5b70c943d0880e98ee907ae52d4c02ad8720f73'
$DualIdNewConsumptionPersistenceQualifiedStoreContractBlob='07de3a6d3aec00636d8b1c7bd20dcbc72d1b7ada'
$DualIdNewConsumptionPersistenceQualifiedAdmissionHead='af4e28791b4e5633cc97bb7f7bbab2bc3ad3fdf0'
$DualIdNewConsumptionPersistenceQualifiedAdmissionBlob='731c6d096298199b784d3da8b3a9610ff880cd98'

function Get-DualIdNewConsumptionPersistenceShaV010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$h.Dispose()}
}
function Test-DualIdNewConsumptionPersistenceHashV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function New-DualIdNewConsumptionPersistenceDeniedV010 {
    param([string]$Reason,[bool]$Persisted=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;consumption_persisted=$Persisted;persisted_consumption_barrier_attested=$false
        read_after_write_verified=$false;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-DualIdNewConsumptionPersistenceMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    $fields=@(
        'schema','managed_by','qualified_consumption_head','qualified_consumption_blob','qualified_store_blob','qualified_store_contract_blob','qualified_admission_head','qualified_admission_blob',
        'name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct',
        'consumption_id','consumption_candidate_fingerprint','issuer_fingerprint','reservation_persistence_fingerprint','reservation_persistence_envelope_sha256','persisted_reservation_revision',
        'pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','consumption_state_revision_before','consumption_state_revision_after',
        'persistence_envelope_sha256','persisted_revision','current_store_revision_at_attestation',
        'consumption_persisted','read_after_write_verified','persisted_consumption_barrier_attested','fresh_admission_revalidated',
        'write_performed','recovered_existing_persistence','session_key_accepted','session_key_persisted','session_key_exposed',
        'requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply',
        'persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','checked_at'
    )
    return (($fields|ForEach-Object{[string]$Receipt.PSObject.Properties[[string]$_].Value})-join([string][char]10))
}
function Test-DualIdNewConsumptionPersistenceReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-receipt-null'}}
    $keys=@('schema','managed_by','qualified_consumption_head','qualified_consumption_blob','qualified_store_blob','qualified_store_contract_blob','qualified_admission_head','qualified_admission_blob','name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct','consumption_id','consumption_candidate_fingerprint','issuer_fingerprint','reservation_persistence_fingerprint','reservation_persistence_envelope_sha256','persisted_reservation_revision','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','consumption_state_revision_before','consumption_state_revision_after','persistence_envelope_sha256','persisted_revision','current_store_revision_at_attestation','consumption_persisted','read_after_write_verified','persisted_consumption_barrier_attested','fresh_admission_revalidated','write_performed','recovered_existing_persistence','session_key_accepted','session_key_persisted','session_key_exposed','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','checked_at','persistence_fingerprint')
    foreach($k in $keys){if(-not$Receipt.PSObject.Properties[$k]){return [pscustomobject]@{ok=$false;reason=('dual-id-consumption-persistence-missing-'+$k)}}}
    if([int]$Receipt.schema-ne$DualIdNewConsumptionPersistenceSchema-or [string]$Receipt.managed_by-cne$DualIdNewConsumptionPersistenceManagedBy){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-owner-invalid'}}
    foreach($pin in @(
        @('qualified_consumption_head',$DualIdNewConsumptionPersistenceQualifiedConsumptionHead),
        @('qualified_consumption_blob',$DualIdNewConsumptionPersistenceQualifiedConsumptionBlob),
        @('qualified_store_blob',$DualIdNewConsumptionPersistenceQualifiedStoreBlob),
        @('qualified_store_contract_blob',$DualIdNewConsumptionPersistenceQualifiedStoreContractBlob),
        @('qualified_admission_head',$DualIdNewConsumptionPersistenceQualifiedAdmissionHead),
        @('qualified_admission_blob',$DualIdNewConsumptionPersistenceQualifiedAdmissionBlob)
    )){if([string]$Receipt.($pin[0])-cne [string]$pin[1]){return [pscustomobject]@{ok=$false;reason=('dual-id-consumption-persistence-lineage-'+$pin[0])}}}
    foreach($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','consumption_id','consumption_candidate_fingerprint','issuer_fingerprint','reservation_persistence_fingerprint','reservation_persistence_envelope_sha256','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','persistence_envelope_sha256','persistence_fingerprint')){
        if(-not(Test-DualIdNewConsumptionPersistenceHashV010 ([string]$Receipt.$f))){return [pscustomobject]@{ok=$false;reason=('dual-id-consumption-persistence-hash-'+$f)}}
    }
    $a=[string]$Receipt.historical_permit_transaction_id;$b=[string]$Receipt.historical_journal_transaction_id;$c=[string]$Receipt.new_permit_transaction_id
    if($a-ceq$b-or$a-ceq$c-or$b-ceq$c-or-not [bool]$Receipt.transaction_id_namespaces_pairwise_distinct){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-transaction-ids-conflated'}}
    foreach($f in @('consumption_persisted','read_after_write_verified','persisted_consumption_barrier_attested','fresh_admission_revalidated','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){
        if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-consumption-persistence-required-flag-'+$f)}}
    }
    foreach($f in @('session_key_accepted','session_key_persisted','session_key_exposed','persistence_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){
        if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('dual-id-consumption-persistence-authority-escaped-'+$f)}}
    }
    if([bool]$Receipt.write_performed-eq [bool]$Receipt.recovered_existing_persistence){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-write-recovery-flags-invalid'}}
    try{
        $before=[int64]$Receipt.consumption_state_revision_before;$after=[int64]$Receipt.consumption_state_revision_after
        $stored=[int64]$Receipt.persisted_revision;$current=[int64]$Receipt.current_store_revision_at_attestation
        [void][DateTimeOffset]::Parse([string]$Receipt.checked_at)
    }catch{return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-revision-or-time-invalid'}}
    if($before-lt0-or$after-ne($before+1)-or$stored-ne$after-or$current-lt$stored){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-revision-chain-invalid'}}
    if([string]$Receipt.pre_persistence_admission_fingerprint-cne [string]$Receipt.post_persistence_admission_fingerprint){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-admission-drift'}}
    if([string]$Receipt.persistence_fingerprint-cne(Get-DualIdNewConsumptionPersistenceShaV010 (Get-DualIdNewConsumptionPersistenceMaterialV010 -Receipt $Receipt))){return [pscustomobject]@{ok=$false;reason='dual-id-consumption-persistence-fingerprint-invalid'}}
    return [pscustomobject]@{ok=$true;reason='dual-id-new-consumption-durable-barrier-valid-zero-authority';consumption_id=[string]$Receipt.consumption_id;executor_may_start=$false}
}
function Test-DualIdNewConsumptionPersistenceCandidateV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result-or-not [bool]$Result.ok-or$null-eq$Result.receipt-or$null-eq$Result.next_state){return [pscustomobject]@{ok=$false;reason='consumption-result-invalid'}}
    $r=$Result.receipt;$c=Test-CustomAppProductionDualIdNewPermitConsumptionReceiptV010 -Receipt $r
    if(-not [bool]$c.ok){return [pscustomobject]@{ok=$false;reason=('consumption-receipt-invalid:'+[string]$c.reason)}}
    $s=Test-CustomAppProductionExecutorConsumptionStateV010 -State $Result.next_state
    if(-not [bool]$s.ok){return [pscustomobject]@{ok=$false;reason=('consumption-next-state-invalid:'+[string]$s.reason)}}
    try{$before=[int64]$r.consumption_state_revision_before;$after=[int64]$r.consumption_state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='consumption-revision-invalid'}}
    if($before-lt0-or$after-ne($before+1)-or [int64]$Result.next_state.revision-ne$after){return [pscustomobject]@{ok=$false;reason='consumption-revision-mismatch'}}
    $rows=@($Result.next_state.consumptions)
    if($rows.Count-ne$after-or$rows.Count-lt1){return [pscustomobject]@{ok=$false;reason='consumption-row-count-mismatch'}}
    $last=$rows[-1]
    foreach($p in @(
        @('consumption_id','consumption_id'),@('reservation_id','reservation_id'),
        @('token_id','permit_token_id'),@('permit_nonce','permit_nonce'),@('permit_hmac_sha256','permit_hmac_sha256')
    )){
        if(([string]$last.($p[0])).Trim().ToLowerInvariant()-cne([string]$r.($p[1])).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('consumption-row-'+$p[0]+'-mismatch')}}
    }
    if(-not [bool]$r.consumption_created-or [bool]$r.consumption_persisted-or [bool]$r.executor_may_start){return [pscustomobject]@{ok=$false;reason='consumption-candidate-authority-escaped'}}
    return [pscustomobject]@{ok=$true;reason='dual-id-consumption-next-state-bound';receipt=$r;next_state=$Result.next_state;before=$before;after=$after}
}
function Test-DualIdNewConsumptionPersistenceContinuityV010 {
    param($CandidateReceipt,$IssuerReceipt,$ReservationReceipt,$FreshAdmission)
    if($null-eq$CandidateReceipt-or$null-eq$IssuerReceipt-or$null-eq$ReservationReceipt-or$null-eq$FreshAdmission){return [pscustomobject]@{ok=$false;reason='fresh-continuity-null'}}
    foreach($f in @('name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id')){
        foreach($x in @($IssuerReceipt,$ReservationReceipt,$FreshAdmission)){
            if(([string]$CandidateReceipt.$f).Trim().ToLowerInvariant()-cne([string]$x.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('fresh-continuity-'+$f+'-mismatch')}}
        }
    }
    foreach($p in @(@('issuer_fingerprint','issuer_fingerprint'),@('reservation_persistence_fingerprint','persistence_fingerprint'))){
        $v=if($p[0]-ceq'issuer_fingerprint'){$IssuerReceipt}else{$ReservationReceipt}
        if(([string]$CandidateReceipt.($p[0])).Trim().ToLowerInvariant()-cne([string]$v.($p[1])).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('fresh-continuity-'+$p[0]+'-mismatch')}}
    }
    foreach($f in @('stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint')){
        if(([string]$IssuerReceipt.$f).Trim().ToLowerInvariant()-cne([string]$FreshAdmission.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('fresh-continuity-current-'+$f+'-drift')}}
    }
    return [pscustomobject]@{ok=$true;reason='new-cycle-identity-and-current-admission-exact'}
}
function Invoke-DualIdNewConsumptionPersistenceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ReservationPersistenceStoreDirectory,[Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,[Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$PriorReadinessReceipt,[Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ReservationPersistenceResult,[Parameter(Mandatory=$true)]$ConsumptionResult,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason,[bool]$Persisted=$false)New-DualIdNewConsumptionPersistenceDeniedV010 -Reason $Reason -Persisted:$Persisted}
    if($SessionKey.Length-lt32){return (& $deny 'session-key-too-short')}
    $candidate=Test-DualIdNewConsumptionPersistenceCandidateV010 -Result $ConsumptionResult
    if(-not [bool]$candidate.ok){return (& $deny ('candidate-invalid:'+[string]$candidate.reason))}
    $r=$candidate.receipt
    $ids=@($HistoricalPermitTransactionId.Trim().ToLowerInvariant(),$HistoricalJournalTransactionId.Trim().ToLowerInvariant(),$NewPermitTransactionId.Trim().ToLowerInvariant())
    foreach($id in $ids){if(-not(Test-DualIdNewConsumptionPersistenceHashV010 $id)){return (& $deny 'transaction-id-invalid')}}
    if($ids[0]-ceq$ids[1]-or$ids[0]-ceq$ids[2]-or$ids[1]-ceq$ids[2]){return (& $deny 'transaction-id-conflation')}
    if(([string]$r.name).Trim().ToLowerInvariant()-cne$Name.Trim().ToLowerInvariant()){return (& $deny 'consumption-name-mismatch')}
    foreach($p in @(@('historical_permit_transaction_id',$ids[0]),@('historical_journal_transaction_id',$ids[1]),@('new_permit_transaction_id',$ids[2]))){
        if(([string]$r.($p[0])).Trim().ToLowerInvariant()-cne [string]$p[1]){return (& $deny ('consumption-'+$p[0]+'-mismatch'))}
    }
    $issuerCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $Now
    if(-not [bool]$issuerCheck.ok){return (& $deny ('issuer-invalid:'+[string]$issuerCheck.reason))}
    $reserveCheck=Test-CustomAppProductionDualIdNewPermitReservationPersistenceReceiptV010 -Receipt $ReservationPersistenceResult.receipt
    if(-not [bool]$reserveCheck.ok){return (& $deny ('reservation-persistence-invalid:'+[string]$reserveCheck.reason))}
    $runAdmission={
        Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -HistoricalPermitTransactionId $ids[0] -HistoricalJournalTransactionId $ids[1] -NewPermitTransactionId $ids[2] -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    }
    $pre=& $runAdmission
    if($null-eq$pre-or-not [bool]$pre.ok){return (& $deny ('pre-admission-denied:'+[string]$pre.reason))}
    $pc=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$pc.ok){return (& $deny ('pre-admission-invalid:'+[string]$pc.reason))}
    $continuity=Test-DualIdNewConsumptionPersistenceContinuityV010 -CandidateReceipt $r -IssuerReceipt $IssuerResult.receipt -ReservationReceipt $ReservationPersistenceResult.receipt -FreshAdmission $pre.receipt
    if(-not [bool]$continuity.ok){return (& $deny ([string]$continuity.reason))}
    try{$store=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory}catch{return (& $deny ('store-read-denied:'+[string]$_.Exception.Message))}
    if(-not [bool]$store.ok){
        if([string]$store.reason-cne'consumption-store-uninitialized'-or [int64]$candidate.before-ne0){return (& $deny ('store-not-ready:'+[string]$store.reason))}
        try{$store=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -Now $Now}catch{return (& $deny ('initialize-denied:'+[string]$_.Exception.Message))}
        if(-not [bool]$store.ok){return (& $deny ('initialize-failed:'+[string]$store.reason))}
    }
    $written=$false;$recovered=$false
    if([int64]$store.revision-eq [int64]$candidate.before){
        $saved=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory -NextState $candidate.next_state -ExpectedCurrentRevision ([int64]$candidate.before) -Now $Now -FailurePoint $FailurePoint
        if($null-eq$saved-or-not [bool]$saved.ok){return (& $deny ('save-denied:'+[string]$saved.reason))}
        $written=$true
    }elseif([int64]$store.revision-eq [int64]$candidate.after){
        $recovered=$true
    }else{return (& $deny 'store-revision-conflict')}
    try{$verify=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $ConsumptionStoreDirectory}catch{return (& $deny ('readback-denied:'+[string]$_.Exception.Message) $written)}
    if($null-eq$verify-or-not [bool]$verify.ok){return (& $deny 'readback-invalid' $written)}
    if([int64]$verify.revision-ne [int64]$candidate.after){return (& $deny 'readback-revision-mismatch' $written)}
    $expectedJson=$candidate.next_state|ConvertTo-Json -Depth 60 -Compress;$actualJson=$verify.state|ConvertTo-Json -Depth 60 -Compress
    if($expectedJson-cne$actualJson){return (& $deny 'readback-state-drift' $written)}
    $barrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $verify -ExpectedConsumptionId ([string]$r.consumption_id)
    if($null-eq$barrier-or-not [bool]$barrier.ok){return (& $deny ('barrier-denied:'+[string]$barrier.reason) $true)}
    $post=& $runAdmission
    if($null-eq$post-or-not [bool]$post.ok){return (& $deny ('post-admission-denied:'+[string]$post.reason) $true)}
    $postCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not [bool]$postCheck.ok){return (& $deny ('post-admission-invalid:'+[string]$postCheck.reason) $true)}
    $postC=Test-DualIdNewConsumptionPersistenceContinuityV010 -CandidateReceipt $r -IssuerReceipt $IssuerResult.receipt -ReservationReceipt $ReservationPersistenceResult.receipt -FreshAdmission $post.receipt
    if(-not [bool]$postC.ok){return (& $deny ('post-'+[string]$postC.reason) $true)}
    if([string]$pre.receipt.issuance_admission_fingerprint-cne [string]$post.receipt.issuance_admission_fingerprint){return (& $deny 'admission-drift-during-persistence' $true)}
    $receipt=[pscustomobject]@{
        schema=$DualIdNewConsumptionPersistenceSchema;managed_by=$DualIdNewConsumptionPersistenceManagedBy
        qualified_consumption_head=$DualIdNewConsumptionPersistenceQualifiedConsumptionHead;qualified_consumption_blob=$DualIdNewConsumptionPersistenceQualifiedConsumptionBlob
        qualified_store_blob=$DualIdNewConsumptionPersistenceQualifiedStoreBlob;qualified_store_contract_blob=$DualIdNewConsumptionPersistenceQualifiedStoreContractBlob
        qualified_admission_head=$DualIdNewConsumptionPersistenceQualifiedAdmissionHead;qualified_admission_blob=$DualIdNewConsumptionPersistenceQualifiedAdmissionBlob
        name=$Name.Trim().ToLowerInvariant();source_identity=[string]$r.source_identity
        historical_permit_transaction_id=$ids[0];historical_journal_transaction_id=$ids[1];new_permit_transaction_id=$ids[2];transaction_id_namespaces_pairwise_distinct=$true
        consumption_id=[string]$r.consumption_id;consumption_candidate_fingerprint=[string]$r.consumption_fingerprint
        issuer_fingerprint=[string]$r.issuer_fingerprint;reservation_persistence_fingerprint=[string]$r.reservation_persistence_fingerprint
        reservation_persistence_envelope_sha256=[string]$r.reservation_persistence_envelope_sha256;persisted_reservation_revision=[int64]$r.persisted_reservation_revision
        pre_persistence_admission_fingerprint=[string]$pre.receipt.issuance_admission_fingerprint;post_persistence_admission_fingerprint=[string]$post.receipt.issuance_admission_fingerprint
        consumption_state_revision_before=[int64]$candidate.before;consumption_state_revision_after=[int64]$candidate.after
        persistence_envelope_sha256=[string]$verify.envelope.envelope_sha256;persisted_revision=[int64]$verify.revision;current_store_revision_at_attestation=[int64]$verify.revision
        consumption_persisted=$true;read_after_write_verified=$true;persisted_consumption_barrier_attested=$true;fresh_admission_revalidated=$true
        write_performed=$written;recovered_existing_persistence=$recovered;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        checked_at=$Now.ToUniversalTime().ToString('o');persistence_fingerprint=$null
    }
    $receipt.persistence_fingerprint=Get-DualIdNewConsumptionPersistenceShaV010(Get-DualIdNewConsumptionPersistenceMaterialV010 -Receipt $receipt)
    $ck=Test-DualIdNewConsumptionPersistenceReceiptV010 -Receipt $receipt
    if(-not [bool]$ck.ok){return (& $deny ('output-receipt-invalid:'+[string]$ck.reason) $true)}
    return [pscustomobject]@{
        ok=$true;reason='dual-id-new-consumption-durably-persisted-zero-authority';receipt=$receipt;persisted_snapshot=$verify
        consumption_persisted=$true;read_after_write_verified=$true;persisted_consumption_barrier_attested=$true
        write_performed=$written;recovered_existing_persistence=$recovered;session_key_persisted=$false;session_key_exposed=$false
        persistence_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
