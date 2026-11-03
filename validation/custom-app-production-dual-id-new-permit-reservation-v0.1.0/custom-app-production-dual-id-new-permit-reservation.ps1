$CustomAppProductionDualIdNewPermitReservationSchema = 1
$CustomAppProductionDualIdNewPermitReservationManagedBy = 'custom-app-production-dual-id-new-permit-reservation-v1'
$CustomAppProductionDualIdNewPermitReservationQualifiedIssuerHead = '2954d4b9cf5c5cc8a99543c686541d397fc909c6'
$CustomAppProductionDualIdNewPermitReservationQualifiedIssuerCoreBlob = 'c3a79490d569798775696626d10f73485275c4bc'
$CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionHead = 'af4e28791b4e5633cc97bb7f7bbab2bc3ad3fdf0'
$CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionCoreBlob = '731c6d096298199b784d3da8b3a9610ff880cd98'
$CustomAppProductionDualIdNewPermitReservationQualifiedReservationHead = 'edb8a34c61abb28838ba6ca89cf539bdf28bec2a'
$CustomAppProductionDualIdNewPermitReservationQualifiedReservationCoreBlob = '54c1c6a3be4b8646d87a06cef9903ebb01479fd6'
$CustomAppProductionDualIdNewPermitReservationPersistenceWindowSeconds = 3

function Get-CustomAppProductionDualIdNewPermitReservationSha256V010 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}
function Test-CustomAppProductionDualIdNewPermitReservationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Test-CustomAppProductionDualIdNewPermitReservationNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}
function New-CustomAppProductionDualIdNewPermitReservationDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()]$OriginalState=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;next_state=$OriginalState;receipt=$null
        reservation_created=$false;reservation_persisted=$false;transaction_binding_verified=$false
        session_key_persisted=$false;session_key_exposed=$false;nonce_reserved_in_memory=$false;nonce_durably_reserved=$false
        permit_reserved_in_memory=$false;permit_durably_reserved=$false;permit_consumed=$false
        requires_atomic_persistence_before_executor=$true;requires_recovery_aware_persistence_revalidation=$true;requires_single_use_consumption=$true
        reservation_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionDualIdNewPermitReservationReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_issuer_head,[string]$Receipt.qualified_issuer_core_blob,[string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,[string]$Receipt.qualified_reservation_head,[string]$Receipt.qualified_reservation_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.historical_permit_transaction_id,[string]$Receipt.historical_journal_transaction_id,[string]$Receipt.new_permit_transaction_id,[string]$Receipt.transaction_id_namespaces_pairwise_distinct,
        [string]$Receipt.issuer_fingerprint,[string]$Receipt.transaction_binding_hmac_sha256,[string]$Receipt.transaction_binding_domain,[string]$Receipt.transaction_binding_verified,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_nonce,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.permit_issued_at,[string]$Receipt.permit_expires_at,[string]$Receipt.issuer_reservation_eligible_until,
        [string]$Receipt.prior_issuance_admission_fingerprint,[string]$Receipt.pre_reservation_issuance_admission_fingerprint,[string]$Receipt.post_reservation_issuance_admission_fingerprint,
        [string]$Receipt.housekeeping_cleanup_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.reservation_id,[string]$Receipt.state_revision_before,[string]$Receipt.state_revision_after,[string]$Receipt.reserved_at,[string]$Receipt.checked_at,[string]$Receipt.persistence_eligible_until,
        [string]$Receipt.reservation_created,[string]$Receipt.reservation_persisted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,[string]$Receipt.nonce_reserved_in_memory,[string]$Receipt.nonce_durably_reserved,[string]$Receipt.permit_reserved_in_memory,[string]$Receipt.permit_durably_reserved,[string]$Receipt.permit_consumed,
        [string]$Receipt.requires_atomic_persistence_before_executor,[string]$Receipt.requires_recovery_aware_persistence_revalidation,[string]$Receipt.requires_single_use_consumption,[string]$Receipt.requires_fresh_admission_revalidation_on_consume,[string]$Receipt.requires_external_consumption_ledger,
        [string]$Receipt.reservation_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionDualIdNewPermitReservationReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if ($null -eq $Receipt) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-receipt-null'} }
    $required=@(
        'schema','managed_by','qualified_issuer_head','qualified_issuer_core_blob','qualified_issuance_admission_head','qualified_issuance_admission_core_blob','qualified_reservation_head','qualified_reservation_core_blob',
        'name','source_identity','github_repo_id','surface_kind','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct',
        'issuer_fingerprint','transaction_binding_hmac_sha256','transaction_binding_domain','transaction_binding_verified','permit_token_id','permit_nonce','permit_hmac_sha256','permit_issued_at','permit_expires_at','issuer_reservation_eligible_until',
        'prior_issuance_admission_fingerprint','pre_reservation_issuance_admission_fingerprint','post_reservation_issuance_admission_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint',
        'reservation_id','state_revision_before','state_revision_after','reserved_at','checked_at','persistence_eligible_until','reservation_created','reservation_persisted','session_key_persisted','session_key_exposed','nonce_reserved_in_memory','nonce_durably_reserved','permit_reserved_in_memory','permit_durably_reserved','permit_consumed',
        'requires_atomic_persistence_before_executor','requires_recovery_aware_persistence_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_external_consumption_ledger','reservation_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','reservation_fingerprint'
    )
    foreach ($f in $required) { if (-not $Receipt.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-reservation-receipt-field-missing-'+$f)} } }
    if ([int]$Receipt.schema -ne $CustomAppProductionDualIdNewPermitReservationSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionDualIdNewPermitReservationManagedBy) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-receipt-owner-schema-invalid'} }
    if ([string]$Receipt.qualified_issuer_head -cne $CustomAppProductionDualIdNewPermitReservationQualifiedIssuerHead -or [string]$Receipt.qualified_issuer_core_blob -cne $CustomAppProductionDualIdNewPermitReservationQualifiedIssuerCoreBlob -or [string]$Receipt.qualified_issuance_admission_head -cne $CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionHead -or [string]$Receipt.qualified_issuance_admission_core_blob -cne $CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionCoreBlob -or [string]$Receipt.qualified_reservation_head -cne $CustomAppProductionDualIdNewPermitReservationQualifiedReservationHead -or [string]$Receipt.qualified_reservation_core_blob -cne $CustomAppProductionDualIdNewPermitReservationQualifiedReservationCoreBlob) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-receipt-lineage-invalid'} }
    if ([string]$Receipt.transaction_binding_domain -cne $CustomAppProductionDualIdNewPermitIssuerBindingDomain) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-binding-domain-invalid'} }
    foreach ($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','issuer_fingerprint','transaction_binding_hmac_sha256','permit_token_id','permit_hmac_sha256','prior_issuance_admission_fingerprint','pre_reservation_issuance_admission_fingerprint','post_reservation_issuance_admission_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','reservation_id','reservation_fingerprint')) {
        if (-not (Test-CustomAppProductionDualIdNewPermitReservationSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-reservation-receipt-invalid-'+$f)} }
    }
    if (-not (Test-CustomAppProductionDualIdNewPermitReservationNonceV010 ([string]$Receipt.permit_nonce)) -or ([string]$Receipt.current_remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$') { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-nonce-or-commit-invalid'} }
    $oldPermit=([string]$Receipt.historical_permit_transaction_id).Trim().ToLowerInvariant();$journal=([string]$Receipt.historical_journal_transaction_id).Trim().ToLowerInvariant();$new=([string]$Receipt.new_permit_transaction_id).Trim().ToLowerInvariant()
    if ($oldPermit -ceq $journal -or $oldPermit -ceq $new -or $journal -ceq $new -or -not [bool]$Receipt.transaction_id_namespaces_pairwise_distinct) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-transaction-namespaces-not-pairwise-distinct'} }
    if (([string]$Receipt.pre_reservation_issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_reservation_issuance_admission_fingerprint).Trim().ToLowerInvariant()) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-pre-post-admission-drift'} }
    foreach ($f in @('transaction_binding_verified','reservation_created','nonce_reserved_in_memory','permit_reserved_in_memory','requires_atomic_persistence_before_executor','requires_recovery_aware_persistence_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_external_consumption_ledger')) { if (-not [bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-reservation-required-flag-false-'+$f)} } }
    foreach ($f in @('reservation_persisted','session_key_persisted','session_key_exposed','nonce_durably_reserved','permit_durably_reserved','permit_consumed','reservation_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')) { if ([bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-reservation-authority-or-persistence-escaped-'+$f)} } }
    try { $before=[int64]$Receipt.state_revision_before;$after=[int64]$Receipt.state_revision_after } catch { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-state-revision-invalid'} }
    if ($before -lt 0 -or $after -ne ($before+1)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-state-revision-chain-invalid'} }
    $reserved=[DateTimeOffset]::MinValue;$checked=[DateTimeOffset]::MinValue;$until=[DateTimeOffset]::MinValue;$issuerUntil=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Receipt.reserved_at,[ref]$reserved) -or -not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$checked) -or -not [DateTimeOffset]::TryParse([string]$Receipt.persistence_eligible_until,[ref]$until) -or -not [DateTimeOffset]::TryParse([string]$Receipt.issuer_reservation_eligible_until,[ref]$issuerUntil)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-time-invalid'} }
    if ($reserved.ToUniversalTime().Ticks -ne $checked.ToUniversalTime().Ticks) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-reserved-at-mismatch'} }
    if ($until -le $checked -or $until -gt $checked.AddSeconds($CustomAppProductionDualIdNewPermitReservationPersistenceWindowSeconds) -or $until -gt $issuerUntil) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-persistence-window-invalid'} }
    if ($Now -lt $checked.AddSeconds(-5)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-not-yet-valid'} }
    if ($Now -ge $until) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-persistence-window-expired'} }
    $expected=Get-CustomAppProductionDualIdNewPermitReservationSha256V010 (Get-CustomAppProductionDualIdNewPermitReservationReceiptMaterialV010 -Receipt $Receipt)
    if (([string]$Receipt.reservation_fingerprint).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-reservation-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-reservation-valid-in-memory-not-persisted';reservation_id=([string]$Receipt.reservation_id).Trim().ToLowerInvariant();new_permit_transaction_id=$new;requires_atomic_persistence_before_executor=$true;executor_may_start=$false;production_mutation_authorized=$false}
}
function Test-CustomAppProductionDualIdNewPermitReservationIssuerAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$IssuerReceipt,[Parameter(Mandatory=$true)]$AdmissionReceipt)
    $pairs=@(
        @('name','name'),@('source_identity','source_identity'),@('historical_permit_transaction_id','historical_permit_transaction_id'),@('historical_journal_transaction_id','historical_journal_transaction_id'),@('new_permit_transaction_id','new_permit_transaction_id'),
        @('housekeeping_cleanup_fingerprint','housekeeping_cleanup_fingerprint'),@('recovery_evidence_fingerprint','recovery_evidence_fingerprint'),@('stable_live_tree_sha256','stable_live_tree_sha256'),@('stable_persistence_fingerprint','stable_persistence_fingerprint'),
        @('current_remote_tree_sha256','current_remote_tree_sha256'),@('current_remote_commit_sha','current_remote_commit_sha'),@('current_binding_fingerprint','current_binding_fingerprint'),@('current_provenance_fingerprint','current_provenance_fingerprint'),@('live_admission_fingerprint','live_admission_fingerprint'),@('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint')
    )
    foreach ($p in $pairs) { if (([string]$IssuerReceipt.($p[0])).Trim().ToLowerInvariant() -cne ([string]$AdmissionReceipt.($p[1])).Trim().ToLowerInvariant()) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-reservation-issuer-admission-mismatch-'+[string]$p[0])} } }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-reservation-issuer-admission-continuity-exact'}
}
function Invoke-CustomAppProductionDualIdNewPermitReservationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,[Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,[Parameter(Mandatory=$true)]$PriorReadinessReceipt,[Parameter(Mandatory=$true)]$IssuanceAdmissionReceipt,
        [Parameter(Mandatory=$true)]$IssuerResult,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)]$ReservationState,[Parameter(Mandatory=$true)][int64]$ExpectedRevision,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionDualIdNewPermitReservationDeniedV010 -Reason $Reason -OriginalState $ReservationState}
    if ($SessionKey.Length -lt 32) { return (& $deny 'dual-id-new-permit-reservation-session-key-too-short') }
    if ($null -eq $IssuerResult -or -not [bool]$IssuerResult.ok -or $null -eq $IssuerResult.permit -or $null -eq $IssuerResult.receipt) { return (& $deny 'dual-id-new-permit-reservation-issuer-result-invalid') }
    $issuerCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $Now
    if ($null -eq $issuerCheck -or -not [bool]$issuerCheck.ok) { return (& $deny ('dual-id-new-permit-reservation-issuer-receipt-invalid:'+[string]$issuerCheck.reason)) }
    $oldPermit=$HistoricalPermitTransactionId.Trim().ToLowerInvariant();$journal=$HistoricalJournalTransactionId.Trim().ToLowerInvariant();$new=$NewPermitTransactionId.Trim().ToLowerInvariant();$nameKey=$Name.Trim().ToLowerInvariant();$ir=$IssuerResult.receipt
    if (([string]$ir.name).Trim().ToLowerInvariant() -cne $nameKey -or ([string]$ir.historical_permit_transaction_id).Trim().ToLowerInvariant() -cne $oldPermit -or ([string]$ir.historical_journal_transaction_id).Trim().ToLowerInvariant() -cne $journal -or ([string]$ir.new_permit_transaction_id).Trim().ToLowerInvariant() -cne $new) { return (& $deny 'dual-id-new-permit-reservation-issuer-identity-or-transaction-mismatch') }
    if (([string]$IssuerResult.permit.token_id).Trim().ToLowerInvariant() -cne ([string]$ir.permit_token_id).Trim().ToLowerInvariant() -or ([string]$IssuerResult.permit.nonce).Trim().ToLowerInvariant() -cne ([string]$ir.permit_nonce).Trim().ToLowerInvariant() -or ([string]$IssuerResult.permit.hmac_sha256).Trim().ToLowerInvariant() -cne ([string]$ir.permit_hmac_sha256).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-reservation-permit-receipt-identity-mismatch') }
    $priorCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $IssuanceAdmissionReceipt -Now $Now
    if ($null -eq $priorCheck -or -not [bool]$priorCheck.ok) { return (& $deny ('dual-id-new-permit-reservation-prior-admission-invalid:'+[string]$priorCheck.reason)) }
    if (([string]$IssuanceAdmissionReceipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$ir.prior_issuance_admission_fingerprint).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-reservation-prior-admission-fingerprint-mismatch') }
    $pre=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $pre -or -not [bool]$pre.ok) { return (& $deny ('dual-id-new-permit-reservation-pre-admission-denied:'+[string]$pre.reason)) }
    $preCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if ($null -eq $preCheck -or -not [bool]$preCheck.ok) { return (& $deny ('dual-id-new-permit-reservation-pre-admission-invalid:'+[string]$preCheck.reason)) }
    $continuity=Test-CustomAppProductionDualIdNewPermitReservationIssuerAdmissionContinuityV010 -IssuerReceipt $ir -AdmissionReceipt $pre.receipt
    if (-not [bool]$continuity.ok) { return (& $deny ([string]$continuity.reason)) }
    $generic=Invoke-CustomAppProductionPermitReservationV010 -Permit $IssuerResult.permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -ReservationState $ReservationState -ExpectedRevision $ExpectedRevision -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $generic -or -not [bool]$generic.ok -or -not [bool]$generic.reservation_created) { return (& $deny ('dual-id-new-permit-reservation-generic-reservation-denied:'+[string]$generic.reason)) }
    $rows=@($generic.next_state.reservations)
    if ($rows.Count -lt 1) { return (& $deny 'dual-id-new-permit-reservation-generic-row-missing') }
    $row=$rows[$rows.Count-1]
    if (([string]$row.reservation_id).Trim().ToLowerInvariant() -cne ([string]$generic.reservation_id).Trim().ToLowerInvariant() -or ([string]$row.token_id).Trim().ToLowerInvariant() -cne ([string]$ir.permit_token_id).Trim().ToLowerInvariant() -or ([string]$row.permit_nonce).Trim().ToLowerInvariant() -cne ([string]$ir.permit_nonce).Trim().ToLowerInvariant() -or ([string]$row.permit_hmac_sha256).Trim().ToLowerInvariant() -cne ([string]$ir.permit_hmac_sha256).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-reservation-generic-row-continuity-mismatch') }
    $post=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $post -or -not [bool]$post.ok) { return (& $deny ('dual-id-new-permit-reservation-post-admission-denied:'+[string]$post.reason)) }
    $postCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if ($null -eq $postCheck -or -not [bool]$postCheck.ok) { return (& $deny ('dual-id-new-permit-reservation-post-admission-invalid:'+[string]$postCheck.reason)) }
    if (([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-reservation-admission-drift-during-reservation') }
    $issuerUntil=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$ir.reservation_eligible_until,[ref]$issuerUntil) -or $issuerUntil -le $Now) { return (& $deny 'dual-id-new-permit-reservation-issuer-window-expired') }
    $persistenceUntil=$Now.AddSeconds($CustomAppProductionDualIdNewPermitReservationPersistenceWindowSeconds)
    if ($persistenceUntil -gt $issuerUntil) { $persistenceUntil=$issuerUntil }
    if ($persistenceUntil -le $Now) { return (& $deny 'dual-id-new-permit-reservation-no-persistence-window') }
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionDualIdNewPermitReservationSchema;managed_by=$CustomAppProductionDualIdNewPermitReservationManagedBy;qualified_issuer_head=$CustomAppProductionDualIdNewPermitReservationQualifiedIssuerHead;qualified_issuer_core_blob=$CustomAppProductionDualIdNewPermitReservationQualifiedIssuerCoreBlob;qualified_issuance_admission_head=$CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionDualIdNewPermitReservationQualifiedAdmissionCoreBlob;qualified_reservation_head=$CustomAppProductionDualIdNewPermitReservationQualifiedReservationHead;qualified_reservation_core_blob=$CustomAppProductionDualIdNewPermitReservationQualifiedReservationCoreBlob
        name=([string]$ir.name).Trim().ToLowerInvariant();source_identity=([string]$ir.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$ir.github_repo_id;surface_kind=([string]$ir.surface_kind).Trim().ToLowerInvariant();historical_permit_transaction_id=$oldPermit;historical_journal_transaction_id=$journal;new_permit_transaction_id=$new;transaction_id_namespaces_pairwise_distinct=$true
        issuer_fingerprint=([string]$ir.issuer_fingerprint).Trim().ToLowerInvariant();transaction_binding_hmac_sha256=([string]$ir.transaction_binding_hmac_sha256).Trim().ToLowerInvariant();transaction_binding_domain=[string]$ir.transaction_binding_domain;transaction_binding_verified=$true;permit_token_id=([string]$ir.permit_token_id).Trim().ToLowerInvariant();permit_nonce=([string]$ir.permit_nonce).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$ir.permit_hmac_sha256).Trim().ToLowerInvariant();permit_issued_at=[string]$ir.permit_issued_at;permit_expires_at=[string]$ir.permit_expires_at;issuer_reservation_eligible_until=[string]$ir.reservation_eligible_until
        prior_issuance_admission_fingerprint=([string]$IssuanceAdmissionReceipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();pre_reservation_issuance_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_reservation_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();housekeeping_cleanup_fingerprint=([string]$ir.housekeeping_cleanup_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$ir.recovery_evidence_fingerprint).Trim().ToLowerInvariant();stable_live_tree_sha256=([string]$ir.stable_live_tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$ir.stable_persistence_fingerprint).Trim().ToLowerInvariant();current_remote_tree_sha256=([string]$ir.current_remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$ir.current_remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$ir.current_binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$ir.current_provenance_fingerprint).Trim().ToLowerInvariant();live_admission_fingerprint=([string]$ir.live_admission_fingerprint).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$ir.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$ir.live_attested_qualification_fingerprint).Trim().ToLowerInvariant()
        reservation_id=([string]$row.reservation_id).Trim().ToLowerInvariant();state_revision_before=[int64]$row.state_revision_before;state_revision_after=[int64]$row.state_revision_after;reserved_at=$Now.ToUniversalTime().ToString('o');checked_at=$Now.ToUniversalTime().ToString('o');persistence_eligible_until=$persistenceUntil.ToUniversalTime().ToString('o');reservation_created=$true;reservation_persisted=$false;session_key_persisted=$false;session_key_exposed=$false;nonce_reserved_in_memory=$true;nonce_durably_reserved=$false;permit_reserved_in_memory=$true;permit_durably_reserved=$false;permit_consumed=$false
        requires_atomic_persistence_before_executor=$true;requires_recovery_aware_persistence_revalidation=$true;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_external_consumption_ledger=$true;reservation_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;reservation_fingerprint=$null
    }
    $receipt.reservation_fingerprint=Get-CustomAppProductionDualIdNewPermitReservationSha256V010 (Get-CustomAppProductionDualIdNewPermitReservationReceiptMaterialV010 -Receipt $receipt)
    $self=Test-CustomAppProductionDualIdNewPermitReservationReceiptV010 -Receipt $receipt -Now $Now
    if ($null -eq $self -or -not [bool]$self.ok) { return (& $deny ('dual-id-new-permit-reservation-self-check-failed:'+[string]$self.reason)) }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-reserved-in-memory-transaction-bound-requires-atomic-persistence';next_state=$generic.next_state;receipt=$receipt;reservation_created=$true;reservation_persisted=$false;transaction_binding_verified=$true;session_key_persisted=$false;session_key_exposed=$false;nonce_reserved_in_memory=$true;nonce_durably_reserved=$false;permit_reserved_in_memory=$true;permit_durably_reserved=$false;permit_consumed=$false;requires_atomic_persistence_before_executor=$true;requires_recovery_aware_persistence_revalidation=$true;requires_single_use_consumption=$true;reservation_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
