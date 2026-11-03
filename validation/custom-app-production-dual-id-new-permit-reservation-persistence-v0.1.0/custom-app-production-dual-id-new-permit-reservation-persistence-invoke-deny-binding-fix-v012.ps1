$CustomAppProductionDualIdNewPermitReservationPersistenceInvokeDenyBindingFixSchema = 1
$CustomAppProductionDualIdNewPermitReservationPersistenceInvokeDenyBindingFixManagedBy = 'custom-app-production-dual-id-new-permit-reservation-persistence-invoke-deny-binding-fix-v1.2'
$CustomAppProductionDualIdNewPermitReservationPersistenceInvokeDenyBindingFixQualifiedHead = 'e72167310e4eca9dd5dbb6a20e7fbd8809e7cc01'
$CustomAppProductionDualIdNewPermitReservationPersistenceInvokeDenyBindingFixQualifiedCoreBlob = '629c09384ac13d2fe148566deffcc413f91cdc5d'
$CustomAppProductionDualIdNewPermitReservationPersistenceInvokeDenyBindingFixQualifiedSaveFixBlob = '3350cd974bb9f9ae7345e490449c4875d571bf95'

# PS5.1 can mis-bind adjacent positional expressions passed to the local deny
# scriptblock. This overlay replaces only the public persistence wrapper and
# keeps the already-qualified validation algorithm/authority contract intact.
function Invoke-CustomAppProductionDualIdNewPermitReservationPersistenceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,
        [Parameter(Mandatory=$true)]$ShadowResult,
        [Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,
        [Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory,
        [Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,
        [Parameter(Mandatory=$true)][string]$NewPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,
        [AllowNull()]$ShadowProtocolQualification,
        [AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$PriorReadinessReceipt,
        [Parameter(Mandatory=$true)]$IssuanceAdmissionReceipt,
        [Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ReservationResult,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [int]$MaxRemoteObservationAgeHours=36,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={
        param([string]$Reason,[bool]$Persisted=$false,[AllowNull()]$Saved=$null)
        [pscustomobject]@{
            ok=$false;reason=$Reason;reservation_persisted=$Persisted;nonce_durably_reserved=$Persisted;permit_durably_reserved=$Persisted
            session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;transaction_binding_revalidated=$false
            requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true
            persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;saved=$Saved
        }
    }

    if($SessionKey.Length-lt32){return (& $deny -Reason 'dual-id-reservation-persistence-session-key-too-short')}
    if($null-eq$ReservationResult-or-not[bool]$ReservationResult.ok-or$null-eq$ReservationResult.receipt-or$null-eq$ReservationResult.next_state){return (& $deny -Reason 'dual-id-reservation-persistence-reservation-result-invalid')}
    $rr=$ReservationResult.receipt
    $checked=[DateTimeOffset]::MinValue;$until=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$rr.checked_at,[ref]$checked)-or-not[DateTimeOffset]::TryParse([string]$rr.persistence_eligible_until,[ref]$until)){return (& $deny -Reason 'dual-id-reservation-persistence-reservation-receipt-time-invalid')}
    $rrCheck=Test-CustomAppProductionDualIdNewPermitReservationReceiptV010 -Receipt $rr -Now $checked.AddMilliseconds(1)
    if(-not[bool]$rrCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-reservation-receipt-invalid:'+[string]$rrCheck.reason))}

    if($null-eq$IssuerResult-or-not[bool]$IssuerResult.ok-or$null-eq$IssuerResult.receipt){return (& $deny -Reason 'dual-id-reservation-persistence-issuer-result-invalid')}
    $issued=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$IssuerResult.receipt.permit_issued_at,[ref]$issued)){return (& $deny -Reason 'dual-id-reservation-persistence-issuer-time-invalid')}
    $issuerCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $issued.AddMilliseconds(1)
    if(-not[bool]$issuerCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-issuer-revalidation-denied:'+[string]$issuerCheck.reason))}

    foreach($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','issuer_fingerprint','transaction_binding_hmac_sha256','permit_token_id','permit_nonce','permit_hmac_sha256')){
        if(([string]$rr.$f).Trim().ToLowerInvariant()-cne([string]$IssuerResult.receipt.$f).Trim().ToLowerInvariant()){
            return (& $deny -Reason ('dual-id-reservation-persistence-reservation-issuer-continuity-'+$f+'-mismatch'))
        }
    }

    $oldPermit=$HistoricalPermitTransactionId.Trim().ToLowerInvariant();$journal=$HistoricalJournalTransactionId.Trim().ToLowerInvariant();$new=$NewPermitTransactionId.Trim().ToLowerInvariant()
    if(([string]$rr.historical_permit_transaction_id).Trim().ToLowerInvariant()-cne$oldPermit-or([string]$rr.historical_journal_transaction_id).Trim().ToLowerInvariant()-cne$journal-or([string]$rr.new_permit_transaction_id).Trim().ToLowerInvariant()-cne$new){return (& $deny -Reason 'dual-id-reservation-persistence-transaction-argument-mismatch')}

    $nextCheck=Test-CustomAppProductionPermitReservationStateV010 -State $ReservationResult.next_state
    if(-not[bool]$nextCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-next-state-invalid:'+[string]$nextCheck.reason))}
    $last=@($ReservationResult.next_state.reservations)[-1]
    if(([string]$last.reservation_id).Trim().ToLowerInvariant()-cne([string]$rr.reservation_id).Trim().ToLowerInvariant()-or([string]$last.token_id).Trim().ToLowerInvariant()-cne([string]$rr.permit_token_id).Trim().ToLowerInvariant()-or([string]$last.permit_nonce).Trim().ToLowerInvariant()-cne([string]$rr.permit_nonce).Trim().ToLowerInvariant()-or([string]$last.permit_hmac_sha256).Trim().ToLowerInvariant()-cne([string]$rr.permit_hmac_sha256).Trim().ToLowerInvariant()){
        return (& $deny -Reason 'dual-id-reservation-persistence-reservation-row-receipt-mismatch')
    }

    try {$preStore=Read-CustomAppProductionDualIdNewPermitReservationStoreV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory}catch {$preStore=$null}
    $alreadyPersisted=$false
    if($null-ne$preStore-and[bool]$preStore.ok-and[int64]$preStore.revision-eq[int64]$ReservationResult.next_state.revision){
        $alreadyPersisted=((Get-CustomAppProductionDualIdNewPermitReservationPersistenceStateJsonV010 -State $preStore.state)-ceq(Get-CustomAppProductionDualIdNewPermitReservationPersistenceStateJsonV010 -State $ReservationResult.next_state)-and$null-ne$preStore.envelope-and([string]$preStore.envelope.reservation_fingerprint).Trim().ToLowerInvariant()-ceq([string]$rr.reservation_fingerprint).Trim().ToLowerInvariant())
    }
    if(-not$alreadyPersisted-and$Now-ge$until){return (& $deny -Reason 'dual-id-reservation-persistence-window-expired-before-durable-write')}

    $pre=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$pre-or-not[bool]$pre.ok){return (& $deny -Reason ('dual-id-reservation-persistence-pre-admission-denied:'+[string]$pre.reason))}
    $preCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not[bool]$preCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-pre-admission-invalid:'+[string]$preCheck.reason))}
    $continuity=Test-CustomAppProductionDualIdNewPermitReservationPersistenceContinuityV010 -ReservationReceipt $rr -FreshAdmission $pre.receipt
    if(-not[bool]$continuity.ok){return (& $deny -Reason ([string]$continuity.reason))}

    $saved=Save-CustomAppProductionDualIdNewPermitReservationStateV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory -NextState $ReservationResult.next_state -ReservationReceipt $rr -ExpectedCurrentRevision ([int64]$rr.state_revision_before) -PersistenceAdmissionFingerprint ([string]$pre.receipt.issuance_admission_fingerprint) -Now $Now -FailurePoint $FailurePoint
    if(-not[bool]$saved.ok){return (& $deny -Reason ('dual-id-reservation-persistence-save-denied:'+[string]$saved.reason) -Persisted ([bool]$saved.persisted) -Saved $saved)}

    $post=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$post-or-not[bool]$post.ok){return (& $deny -Reason ('dual-id-reservation-persistence-post-admission-denied:'+[string]$post.reason) -Persisted $true -Saved $saved)}
    $postCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not[bool]$postCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-post-admission-invalid:'+[string]$postCheck.reason) -Persisted $true -Saved $saved)}
    $continuity2=Test-CustomAppProductionDualIdNewPermitReservationPersistenceContinuityV010 -ReservationReceipt $rr -FreshAdmission $post.receipt
    if(-not[bool]$continuity2.ok){return (& $deny -Reason ('dual-id-reservation-persistence-post-'+[string]$continuity2.reason) -Persisted $true -Saved $saved)}
    if(([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()-cne([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){
        return (& $deny -Reason 'dual-id-reservation-persistence-admission-drift-after-durable-write' -Persisted $true -Saved $saved)
    }

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionDualIdNewPermitReservationPersistenceSchema;managed_by=$CustomAppProductionDualIdNewPermitReservationPersistenceManagedBy
        qualified_reservation_head=$CustomAppProductionDualIdNewPermitReservationPersistenceQualifiedReservationHead;qualified_reservation_core_blob=$CustomAppProductionDualIdNewPermitReservationPersistenceQualifiedReservationCoreBlob
        qualified_issuance_admission_head=$CustomAppProductionDualIdNewPermitReservationPersistenceQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionDualIdNewPermitReservationPersistenceQualifiedAdmissionCoreBlob
        name=([string]$rr.name).Trim().ToLowerInvariant();source_identity=([string]$rr.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$rr.github_repo_id;surface_kind=([string]$rr.surface_kind).Trim().ToLowerInvariant()
        historical_permit_transaction_id=$oldPermit;historical_journal_transaction_id=$journal;new_permit_transaction_id=$new;transaction_id_namespaces_pairwise_distinct=$true
        issuer_fingerprint=([string]$rr.issuer_fingerprint).Trim().ToLowerInvariant();transaction_binding_hmac_sha256=([string]$rr.transaction_binding_hmac_sha256).Trim().ToLowerInvariant();transaction_binding_domain=[string]$rr.transaction_binding_domain
        reservation_id=([string]$rr.reservation_id).Trim().ToLowerInvariant();reservation_fingerprint=([string]$rr.reservation_fingerprint).Trim().ToLowerInvariant()
        pre_persistence_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_persistence_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$saved.envelope.envelope_sha256).Trim().ToLowerInvariant();persisted_revision=[int64]$saved.revision
        reservation_persisted=$true;nonce_durably_reserved=$true;permit_durably_reserved=$true;session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;transaction_binding_revalidated=$true
        read_after_write_verified=[bool]$saved.read_after_write_verified;reloaded_from_persistent_store=[bool]$saved.reloaded_from_persistent_store;write_performed=[bool]$saved.write_performed;recovered_existing_persistence=[bool]$saved.recovered_existing_persistence;repaired_current_pointer=[bool]$saved.repaired_current_pointer
        requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true
        persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;checked_at=$Now.ToUniversalTime().ToString('o');persistence_fingerprint=$null
    }
    $receipt.persistence_fingerprint=Get-CustomAppProductionDualIdNewPermitReservationPersistenceSha256V010(Get-CustomAppProductionDualIdNewPermitReservationPersistenceReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionDualIdNewPermitReservationPersistenceReceiptV010 -Receipt $receipt
    if(-not[bool]$receiptCheck.ok){return (& $deny -Reason ('dual-id-reservation-persistence-output-invalid:'+[string]$receiptCheck.reason) -Persisted $true -Saved $saved)}
    return [pscustomobject]@{
        ok=$true;reason='dual-id-new-permit-reservation-durably-persisted-zero-authority';receipt=$receipt;store=$saved
        reservation_persisted=$true;nonce_durably_reserved=$true;permit_durably_reserved=$true;session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;transaction_binding_revalidated=$true
        requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true
        persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
