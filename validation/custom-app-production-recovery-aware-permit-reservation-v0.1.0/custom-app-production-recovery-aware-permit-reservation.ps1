$CustomAppProductionRecoveryAwarePermitReservationSchema = 1
$CustomAppProductionRecoveryAwarePermitReservationManagedBy = 'custom-app-production-recovery-aware-permit-reservation-v1'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerHead = 'b2fae45aa42a530aa2934b97c372b19aac4c4347'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerCoreBlob = '3878d44b334eb442f6ef4e776ab48ca2f03b7f4e'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationHead = 'edb8a34c61abb28838ba6ca89cf539bdf28bec2a'
$CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationCoreBlob = '54c1c6a3be4b8646d87a06cef9903ebb01479fd6'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceWindowSeconds = 3

function Get-CustomAppProductionRecoveryAwarePermitReservationSha256V010 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Test-CustomAppProductionRecoveryAwarePermitReservationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionRecoveryAwarePermitReservationNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}

function New-CustomAppProductionRecoveryAwarePermitReservationDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()]$OriginalState=$null)
    return [pscustomobject]@{
        ok=$false; reason=$Reason; next_state=$OriginalState; reservation_created=$false; reservation_persisted=$false
        session_key_persisted=$false; session_key_exposed=$false; nonce_reserved_in_memory=$false; nonce_durably_reserved=$false
        permit_reserved_in_memory=$false; permit_durably_reserved=$false; permit_consumed=$false
        requires_atomic_persistence_before_executor=$true; requires_recovery_aware_persistence_revalidation=$true
        requires_single_use_consumption=$true; requires_fresh_admission_revalidation_on_consume=$true
        reservation_is_authority=$false; executor_may_start=$false
        production_execution_authorized=$false; production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionRecoveryAwarePermitReservationMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_issuer_head,[string]$Receipt.qualified_issuer_core_blob,
        [string]$Receipt.qualified_admission_head,[string]$Receipt.qualified_admission_core_blob,
        [string]$Receipt.qualified_reservation_head,[string]$Receipt.qualified_reservation_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.issuer_fingerprint,[string]$Receipt.permit_token_id,[string]$Receipt.permit_nonce,[string]$Receipt.permit_hmac_sha256,
        [string]$Receipt.pre_reservation_issuance_admission_fingerprint,[string]$Receipt.post_reservation_issuance_admission_fingerprint,
        [string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,
        [string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,
        [string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.reservation_id,[string]$Receipt.state_revision_before,[string]$Receipt.state_revision_after,[string]$Receipt.reserved_at,
        [string]$Receipt.reservation_created,[string]$Receipt.reservation_persisted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,
        [string]$Receipt.nonce_reserved_in_memory,[string]$Receipt.nonce_durably_reserved,[string]$Receipt.permit_reserved_in_memory,[string]$Receipt.permit_durably_reserved,[string]$Receipt.permit_consumed,
        [string]$Receipt.requires_atomic_persistence_before_executor,[string]$Receipt.requires_recovery_aware_persistence_revalidation,
        [string]$Receipt.requires_single_use_consumption,[string]$Receipt.requires_fresh_admission_revalidation_on_consume,[string]$Receipt.requires_external_consumption_ledger,
        [string]$Receipt.checked_at,[string]$Receipt.persistence_eligible_until,
        [string]$Receipt.reservation_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if ($null -eq $Receipt) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-receipt-null'} }

    $required = @(
        'schema','managed_by','qualified_issuer_head','qualified_issuer_core_blob','qualified_admission_head','qualified_admission_core_blob','qualified_reservation_head','qualified_reservation_core_blob',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','issuer_fingerprint','permit_token_id','permit_nonce','permit_hmac_sha256',
        'pre_reservation_issuance_admission_fingerprint','post_reservation_issuance_admission_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint',
        'reservation_id','state_revision_before','state_revision_after','reserved_at','reservation_created','reservation_persisted','session_key_persisted','session_key_exposed',
        'nonce_reserved_in_memory','nonce_durably_reserved','permit_reserved_in_memory','permit_durably_reserved','permit_consumed',
        'requires_atomic_persistence_before_executor','requires_recovery_aware_persistence_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_external_consumption_ledger',
        'checked_at','persistence_eligible_until','reservation_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','reservation_fingerprint'
    )
    foreach ($f in $required) {
        if (-not $Receipt.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-reservation-required-field-missing-'+$f)} }
    }

    if ([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitReservationSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitReservationManagedBy) {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-owner-schema-mismatch'}
    }
    if ([string]$Receipt.qualified_issuer_head -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerHead -or
        [string]$Receipt.qualified_issuer_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerCoreBlob -or
        [string]$Receipt.qualified_admission_head -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionHead -or
        [string]$Receipt.qualified_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionCoreBlob -or
        [string]$Receipt.qualified_reservation_head -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationHead -or
        [string]$Receipt.qualified_reservation_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationCoreBlob) {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-parent-lineage-mismatch'}
    }
    if ([string]::IsNullOrWhiteSpace([string]$Receipt.name) -or [string]$Receipt.source_identity -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or [int64]$Receipt.github_repo_id -le 0 -or [string]::IsNullOrWhiteSpace([string]$Receipt.surface_kind)) {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-identity-invalid'}
    }

    foreach ($f in @('transaction_id','issuer_fingerprint','permit_token_id','permit_hmac_sha256','pre_reservation_issuance_admission_fingerprint','post_reservation_issuance_admission_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','reservation_id','reservation_fingerprint')) {
        if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))) {
            return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-reservation-invalid-'+$f)}
        }
    }
    if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationNonceV010 ([string]$Receipt.permit_nonce)) -or [string]$Receipt.current_remote_commit_sha -notmatch '^[0-9a-f]{40}$') {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-nonce-or-commit-invalid'}
    }
    if (([string]$Receipt.pre_reservation_issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_reservation_issuance_admission_fingerprint).Trim().ToLowerInvariant()) {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-pre-post-admission-drift'}
    }

    foreach ($f in @('reservation_created','nonce_reserved_in_memory','permit_reserved_in_memory','requires_atomic_persistence_before_executor','requires_recovery_aware_persistence_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_external_consumption_ledger')) {
        if (-not [bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-reservation-required-flag-false-'+$f)} }
    }
    foreach ($f in @('reservation_persisted','session_key_persisted','session_key_exposed','nonce_durably_reserved','permit_durably_reserved','permit_consumed','reservation_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')) {
        if ([bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-reservation-authority-or-persistence-escaped-'+$f)} }
    }

    try { $before=[int64]$Receipt.state_revision_before; $after=[int64]$Receipt.state_revision_after }
    catch { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-state-revision-invalid'} }
    if ($before -lt 0 -or $after -ne ($before+1)) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-state-revision-chain-invalid'} }

    $checked=[DateTimeOffset]::MinValue; $until=[DateTimeOffset]::MinValue; $reserved=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$checked) -or -not [DateTimeOffset]::TryParse([string]$Receipt.persistence_eligible_until,[ref]$until) -or -not [DateTimeOffset]::TryParse([string]$Receipt.reserved_at,[ref]$reserved)) {
        return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-time-invalid'}
    }
    if ($until -le $checked -or $until -gt $checked.AddSeconds($CustomAppProductionRecoveryAwarePermitReservationPersistenceWindowSeconds)) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-persistence-window-invalid'} }
    if ($reserved.ToUniversalTime().Ticks -ne $checked.ToUniversalTime().Ticks) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-reserved-at-mismatch'} }
    if ($Now -lt $checked.AddSeconds(-5)) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-not-yet-valid'} }
    if ($Now -ge $until) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-persistence-window-expired'} }

    $expected = Get-CustomAppProductionRecoveryAwarePermitReservationSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationMaterialV010 -Receipt $Receipt)
    if (([string]$Receipt.reservation_fingerprint).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-reservation-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-reservation-valid-in-memory-not-persisted';reservation_id=([string]$Receipt.reservation_id).Trim().ToLowerInvariant();requires_atomic_persistence_before_executor=$true;executor_may_start=$false;production_mutation_authorized=$false}
}

function Test-CustomAppProductionRecoveryAwarePermitReservationAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$IssuerReceipt,[Parameter(Mandatory=$true)]$FreshAdmission)
    $pairs = @(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('recovery_resume_result_fingerprint','recovery_resume_result_fingerprint'),@('stable_live_tree_sha256','stable_live_tree_sha256'),@('stable_persistence_fingerprint','stable_persistence_fingerprint'),
        @('current_remote_tree_sha256','current_remote_tree_sha256'),@('current_remote_commit_sha','current_remote_commit_sha'),@('current_binding_fingerprint','current_binding_fingerprint'),@('current_provenance_fingerprint','current_provenance_fingerprint'),
        @('live_admission_fingerprint','live_admission_fingerprint'),@('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint')
    )
    foreach ($p in $pairs) {
        if (([string]$IssuerReceipt.($p[0])).Trim().ToLowerInvariant() -cne ([string]$FreshAdmission.($p[1])).Trim().ToLowerInvariant()) {
            return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-reservation-issuer-fresh-'+$p[0]+'-mismatch')}
        }
    }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-reservation-issuer-fresh-continuity'}
}

function Invoke-CustomAppProductionRecoveryAwarePermitReservationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$IssuerResult,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ReservationState,[Parameter(Mandatory=$true)][int64]$ExpectedRevision,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny = { param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitReservationDeniedV010 -Reason $Reason -OriginalState $ReservationState }

    if ($null -eq $IssuerResult -or -not [bool]$IssuerResult.ok -or $null -eq $IssuerResult.permit -or $null -eq $IssuerResult.receipt) { return & $deny 'recovery-aware-permit-reservation-issuer-result-invalid' }
    $issuerCheck = Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -Now $Now
    if (-not [bool]$issuerCheck.ok) { return & $deny ('recovery-aware-permit-reservation-issuer-receipt-invalid:'+[string]$issuerCheck.reason) }
    $tx = $ExpectedTransactionId.Trim().ToLowerInvariant()
    if (([string]$IssuerResult.receipt.transaction_id).Trim().ToLowerInvariant() -cne $tx) { return & $deny 'recovery-aware-permit-reservation-transaction-mismatch' }
    if (([string]$IssuerResult.receipt.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()) { return & $deny 'recovery-aware-permit-reservation-name-mismatch' }
    if (([string]$IssuerResult.permit.token_id).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_token_id).Trim().ToLowerInvariant() -or
        ([string]$IssuerResult.permit.nonce).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_nonce).Trim().ToLowerInvariant() -or
        ([string]$IssuerResult.permit.hmac_sha256).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_hmac_sha256).Trim().ToLowerInvariant()) {
        return & $deny 'recovery-aware-permit-reservation-issuer-permit-receipt-mismatch'
    }
    if ($SessionKey.Length -lt 32) { return & $deny 'recovery-aware-permit-reservation-session-key-too-short' }

    $fresh = Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $fresh -or -not [bool]$fresh.ok) { return & $deny ('recovery-aware-permit-reservation-fresh-admission-denied:'+[string]$fresh.reason) }
    $freshCheck = Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $fresh.receipt -Now $Now
    if (-not [bool]$freshCheck.ok) { return & $deny ('recovery-aware-permit-reservation-fresh-admission-invalid:'+[string]$freshCheck.reason) }
    $continuity = Test-CustomAppProductionRecoveryAwarePermitReservationAdmissionContinuityV010 -IssuerReceipt $IssuerResult.receipt -FreshAdmission $fresh.receipt
    if (-not [bool]$continuity.ok) { return & $deny ([string]$continuity.reason) }

    $permitCheck = Test-CustomAppProductionPermitV010 -Permit $IssuerResult.permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if (-not [bool]$permitCheck.ok) { return & $deny ('recovery-aware-permit-reservation-permit-invalid:'+[string]$permitCheck.reason) }

    $reserve = Invoke-CustomAppProductionPermitReservationV010 -Permit $IssuerResult.permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -ReservationState $ReservationState -ExpectedRevision $ExpectedRevision -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $reserve -or -not [bool]$reserve.ok) { return & $deny ('recovery-aware-permit-reservation-core-denied:'+[string]$reserve.reason) }
    $nextCheck = Test-CustomAppProductionPermitReservationStateV010 -State $reserve.next_state
    if (-not [bool]$nextCheck.ok) { return & $deny ('recovery-aware-permit-reservation-next-state-invalid:'+[string]$nextCheck.reason) }
    if (-not [bool]$reserve.reservation_created -or [bool]$reserve.reservation_is_authority -or -not [bool]$reserve.requires_atomic_persistence_before_executor -or [bool]$reserve.production_execution_authorized -or [bool]$reserve.production_mutation_authorized) {
        return & $deny 'recovery-aware-permit-reservation-core-contract-invalid'
    }
    $rows = @($reserve.next_state.reservations | Where-Object { ([string]$_.reservation_id).Trim().ToLowerInvariant() -ceq ([string]$reserve.reservation_id).Trim().ToLowerInvariant() })
    if ($rows.Count -ne 1) { return & $deny 'recovery-aware-permit-reservation-row-not-unique' }
    $row = $rows[0]
    if (([string]$row.token_id).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_token_id).Trim().ToLowerInvariant() -or
        ([string]$row.permit_nonce).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_nonce).Trim().ToLowerInvariant() -or
        ([string]$row.permit_hmac_sha256).Trim().ToLowerInvariant() -cne ([string]$IssuerResult.receipt.permit_hmac_sha256).Trim().ToLowerInvariant()) {
        return & $deny 'recovery-aware-permit-reservation-row-permit-continuity-mismatch'
    }

    $post = Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $post -or -not [bool]$post.ok) { return & $deny ('recovery-aware-permit-reservation-post-admission-denied:'+[string]$post.reason) }
    $postCheck = Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if (-not [bool]$postCheck.ok) { return & $deny ('recovery-aware-permit-reservation-post-admission-invalid:'+[string]$postCheck.reason) }
    if (([string]$fresh.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()) {
        return & $deny 'recovery-aware-permit-reservation-admission-drift-during-reservation'
    }

    $issuerUntil=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$IssuerResult.receipt.reservation_eligible_until,[ref]$issuerUntil)) { return & $deny 'recovery-aware-permit-reservation-issuer-window-invalid' }
    $until = $Now.AddSeconds($CustomAppProductionRecoveryAwarePermitReservationPersistenceWindowSeconds)
    if ($issuerUntil -lt $until) { $until = $issuerUntil }
    if ($until -le $Now) { return & $deny 'recovery-aware-permit-reservation-no-persistence-window-left' }

    $receipt = [pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitReservationSchema; managed_by=$CustomAppProductionRecoveryAwarePermitReservationManagedBy
        qualified_issuer_head=$CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerHead; qualified_issuer_core_blob=$CustomAppProductionRecoveryAwarePermitReservationQualifiedIssuerCoreBlob
        qualified_admission_head=$CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionHead; qualified_admission_core_blob=$CustomAppProductionRecoveryAwarePermitReservationQualifiedAdmissionCoreBlob
        qualified_reservation_head=$CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationHead; qualified_reservation_core_blob=$CustomAppProductionRecoveryAwarePermitReservationQualifiedReservationCoreBlob
        name=([string]$fresh.receipt.name).Trim().ToLowerInvariant(); source_identity=([string]$fresh.receipt.source_identity).Trim().ToLowerInvariant(); transaction_id=$tx; github_repo_id=[int64]$fresh.receipt.github_repo_id; surface_kind=[string]$fresh.receipt.surface_kind
        issuer_fingerprint=([string]$IssuerResult.receipt.issuer_fingerprint).Trim().ToLowerInvariant(); permit_token_id=([string]$IssuerResult.receipt.permit_token_id).Trim().ToLowerInvariant(); permit_nonce=([string]$IssuerResult.receipt.permit_nonce).Trim().ToLowerInvariant(); permit_hmac_sha256=([string]$IssuerResult.receipt.permit_hmac_sha256).Trim().ToLowerInvariant()
        pre_reservation_issuance_admission_fingerprint=([string]$fresh.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant(); post_reservation_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        stable_live_tree_sha256=([string]$fresh.receipt.stable_live_tree_sha256).Trim().ToLowerInvariant(); stable_persistence_fingerprint=([string]$fresh.receipt.stable_persistence_fingerprint).Trim().ToLowerInvariant()
        current_remote_tree_sha256=([string]$fresh.receipt.current_remote_tree_sha256).Trim().ToLowerInvariant(); current_remote_commit_sha=([string]$fresh.receipt.current_remote_commit_sha).Trim().ToLowerInvariant(); current_binding_fingerprint=([string]$fresh.receipt.current_binding_fingerprint).Trim().ToLowerInvariant(); current_provenance_fingerprint=([string]$fresh.receipt.current_provenance_fingerprint).Trim().ToLowerInvariant(); live_admission_fingerprint=([string]$fresh.receipt.live_admission_fingerprint).Trim().ToLowerInvariant(); current_eligibility_fingerprint=([string]$fresh.receipt.current_eligibility_fingerprint).Trim().ToLowerInvariant(); live_attested_qualification_fingerprint=([string]$fresh.receipt.live_attested_qualification_fingerprint).Trim().ToLowerInvariant()
        reservation_id=([string]$reserve.reservation_id).Trim().ToLowerInvariant(); state_revision_before=[int64]$reserve.state_revision_before; state_revision_after=[int64]$reserve.state_revision_after; reserved_at=$Now.ToUniversalTime().ToString('o')
        reservation_created=$true; reservation_persisted=$false; session_key_persisted=$false; session_key_exposed=$false; nonce_reserved_in_memory=$true; nonce_durably_reserved=$false; permit_reserved_in_memory=$true; permit_durably_reserved=$false; permit_consumed=$false
        requires_atomic_persistence_before_executor=$true; requires_recovery_aware_persistence_revalidation=$true; requires_single_use_consumption=$true; requires_fresh_admission_revalidation_on_consume=$true; requires_external_consumption_ledger=$true
        checked_at=$Now.ToUniversalTime().ToString('o'); persistence_eligible_until=$until.ToUniversalTime().ToString('o')
        reservation_is_authority=$false; executor_may_start=$false; production_execution_authorized=$false; production_mutation_authorized=$false; reservation_fingerprint=$null
    }
    $receipt.reservation_fingerprint = Get-CustomAppProductionRecoveryAwarePermitReservationSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationMaterialV010 -Receipt $receipt)
    $receiptCheck = Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $receipt -Now $Now
    if (-not [bool]$receiptCheck.ok) { return & $deny ('recovery-aware-permit-reservation-result-invalid:'+[string]$receiptCheck.reason) }

    return [pscustomobject]@{
        ok=$true; reason='recovery-aware-permit-reserved-in-memory-requires-immediate-atomic-persistence'; next_state=$reserve.next_state; reservation=$row; receipt=$receipt
        reservation_created=$true; reservation_persisted=$false; session_key_persisted=$false; session_key_exposed=$false
        nonce_reserved_in_memory=$true; nonce_durably_reserved=$false; permit_reserved_in_memory=$true; permit_durably_reserved=$false; permit_consumed=$false
        requires_atomic_persistence_before_executor=$true; requires_recovery_aware_persistence_revalidation=$true; requires_single_use_consumption=$true; requires_fresh_admission_revalidation_on_consume=$true
        reservation_is_authority=$false; executor_may_start=$false; production_execution_authorized=$false; production_mutation_authorized=$false
    }
}
