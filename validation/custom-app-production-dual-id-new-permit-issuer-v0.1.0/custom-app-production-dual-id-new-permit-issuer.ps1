$CustomAppProductionDualIdNewPermitIssuerSchema = 1
$CustomAppProductionDualIdNewPermitIssuerManagedBy = 'custom-app-production-dual-id-new-permit-issuer-v1'
$CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionHead = 'af4e28791b4e5633cc97bb7f7bbab2bc3ad3fdf0'
$CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionCoreBlob = '731c6d096298199b784d3da8b3a9610ff880cd98'
$CustomAppProductionDualIdNewPermitIssuerQualifiedPermitHead = 'd77f646d23652b0f066248230756d9e207a10fbd'
$CustomAppProductionDualIdNewPermitIssuerQualifiedPermitCoreBlob = '2aff85ca092848ea254423bf5441b1a077dea5b7'
$CustomAppProductionDualIdNewPermitIssuerPermitTtlMinutes = 1
$CustomAppProductionDualIdNewPermitIssuerReservationWindowSeconds = 5
$CustomAppProductionDualIdNewPermitIssuerBindingDomain = 'spotify-control-dual-id-new-permit-transaction-binding-v1'

function Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Test-CustomAppProductionDualIdNewPermitIssuerSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionDualIdNewPermitIssuerNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}

function New-CustomAppProductionDualIdNewPermitIssuerDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false; reason=$Reason; permit=$null; receipt=$null
        permit_created=$false; transaction_binding_created=$false; session_key_accepted=$false; session_key_persisted=$false; session_key_exposed=$false
        nonce_accepted=$false; nonce_reserved=$false; permit_reserved=$false; permit_consumed=$false
        requires_immediate_external_reservation=$true; requires_atomic_reservation_persistence_before_executor=$true; requires_single_use_consumption=$true
        issuer_is_authority=$false; executor_may_start=$false; production_execution_authorized=$false; production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionDualIdNewPermitIssuerAdmissionContinuityV010 {
    param([AllowNull()]$Prior,[AllowNull()]$Current)
    if ($null -eq $Prior -or $null -eq $Current) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-admission-continuity-null'} }
    foreach ($f in @(
        'name','source_identity','historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id',
        'housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at',
        'live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint'
    )) {
        if (([string]$Prior.$f).Trim().ToLowerInvariant() -cne ([string]$Current.$f).Trim().ToLowerInvariant()) {
            return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-admission-continuity-mismatch-'+$f)}
        }
    }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-issuer-admission-continuity-exact'}
}

function Test-CustomAppProductionDualIdNewPermitIssuerPermitAdmissionContinuityV010 {
    param([Parameter(Mandatory=$true)]$Permit,[Parameter(Mandatory=$true)]$Admission)
    $pairs = @(
        @('name','name'),@('source_identity','source_identity'),
        @('current_tree_sha256','stable_live_tree_sha256'),@('remote_tree_sha256','current_remote_tree_sha256'),@('remote_commit_sha','current_remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','live_admission_fingerprint')
    )
    foreach ($p in $pairs) {
        if (([string]$Permit.($p[0])).Trim().ToLowerInvariant() -cne ([string]$Admission.($p[1])).Trim().ToLowerInvariant()) {
            return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-permit-admission-mismatch-'+[string]$p[0])}
        }
    }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-issuer-permit-admission-continuity-exact'}
}

function Get-CustomAppProductionDualIdNewPermitIssuerBindingMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        $CustomAppProductionDualIdNewPermitIssuerBindingDomain,
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,[string]$Receipt.qualified_permit_head,[string]$Receipt.qualified_permit_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.historical_permit_transaction_id,[string]$Receipt.historical_journal_transaction_id,[string]$Receipt.new_permit_transaction_id,
        [string]$Receipt.prior_issuance_admission_fingerprint,[string]$Receipt.fresh_issuance_admission_fingerprint,[string]$Receipt.post_creation_issuance_admission_fingerprint,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.permit_nonce,[string]$Receipt.permit_issued_at,[string]$Receipt.permit_expires_at,
        [string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,[string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,
        [string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint
    ) -join "`n"
}

function Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,[string]$Receipt.qualified_permit_head,[string]$Receipt.qualified_permit_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.historical_permit_transaction_id,[string]$Receipt.historical_journal_transaction_id,[string]$Receipt.new_permit_transaction_id,[string]$Receipt.transaction_id_namespaces_pairwise_distinct,
        [string]$Receipt.prior_issuance_admission_fingerprint,[string]$Receipt.fresh_issuance_admission_fingerprint,[string]$Receipt.post_creation_issuance_admission_fingerprint,
        [string]$Receipt.housekeeping_cleanup_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.permit_nonce,[string]$Receipt.permit_issued_at,[string]$Receipt.permit_expires_at,[string]$Receipt.reservation_eligible_until,
        [string]$Receipt.transaction_binding_hmac_sha256,[string]$Receipt.transaction_binding_domain,[string]$Receipt.transaction_binding_verified,
        [string]$Receipt.permit_created,[string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,[string]$Receipt.nonce_accepted,[string]$Receipt.nonce_reserved,[string]$Receipt.permit_reserved,[string]$Receipt.permit_consumed,
        [string]$Receipt.single_use,[string]$Receipt.requires_immediate_external_reservation,[string]$Receipt.requires_atomic_reservation_persistence_before_executor,[string]$Receipt.requires_single_use_consumption,[string]$Receipt.requires_fresh_admission_revalidation_on_reserve,[string]$Receipt.requires_fresh_admission_revalidation_on_consume,
        [string]$Receipt.issuer_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 {
    param([AllowNull()]$Receipt,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if ($null -eq $Receipt) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-receipt-null'} }
    if ($SessionKey.Length -lt 32) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-receipt-session-key-too-short'} }
    $required = @(
        'schema','managed_by','qualified_issuance_admission_head','qualified_issuance_admission_core_blob','qualified_permit_head','qualified_permit_core_blob','name','source_identity','github_repo_id','surface_kind',
        'historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct','prior_issuance_admission_fingerprint','fresh_issuance_admission_fingerprint','post_creation_issuance_admission_fingerprint',
        'housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint',
        'permit_token_id','permit_hmac_sha256','permit_nonce','permit_issued_at','permit_expires_at','reservation_eligible_until','transaction_binding_hmac_sha256','transaction_binding_domain','transaction_binding_verified',
        'permit_created','session_key_accepted','session_key_persisted','session_key_exposed','nonce_accepted','nonce_reserved','permit_reserved','permit_consumed','single_use','requires_immediate_external_reservation','requires_atomic_reservation_persistence_before_executor','requires_single_use_consumption','requires_fresh_admission_revalidation_on_reserve','requires_fresh_admission_revalidation_on_consume','issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','issuer_fingerprint'
    )
    foreach ($f in $required) { if (-not $Receipt.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-receipt-field-missing-'+$f)} } }
    if ([int]$Receipt.schema -ne $CustomAppProductionDualIdNewPermitIssuerSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionDualIdNewPermitIssuerManagedBy) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-receipt-owner-schema-invalid'} }
    if ([string]$Receipt.qualified_issuance_admission_head -cne $CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionHead -or [string]$Receipt.qualified_issuance_admission_core_blob -cne $CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionCoreBlob -or [string]$Receipt.qualified_permit_head -cne $CustomAppProductionDualIdNewPermitIssuerQualifiedPermitHead -or [string]$Receipt.qualified_permit_core_blob -cne $CustomAppProductionDualIdNewPermitIssuerQualifiedPermitCoreBlob) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-receipt-lineage-invalid'} }
    if ([string]$Receipt.transaction_binding_domain -cne $CustomAppProductionDualIdNewPermitIssuerBindingDomain) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-binding-domain-invalid'} }
    foreach ($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','prior_issuance_admission_fingerprint','fresh_issuance_admission_fingerprint','post_creation_issuance_admission_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','permit_token_id','permit_hmac_sha256','transaction_binding_hmac_sha256','issuer_fingerprint')) {
        if (-not (Test-CustomAppProductionDualIdNewPermitIssuerSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-receipt-invalid-'+$f)} }
    }
    $oldPermit=([string]$Receipt.historical_permit_transaction_id).Trim().ToLowerInvariant();$journal=([string]$Receipt.historical_journal_transaction_id).Trim().ToLowerInvariant();$new=([string]$Receipt.new_permit_transaction_id).Trim().ToLowerInvariant()
    if ($oldPermit -ceq $journal -or $oldPermit -ceq $new -or $journal -ceq $new -or -not [bool]$Receipt.transaction_id_namespaces_pairwise_distinct) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-transaction-namespaces-not-pairwise-distinct'} }
    if (-not (Test-CustomAppProductionDualIdNewPermitIssuerNonceV010 ([string]$Receipt.permit_nonce)) -or ([string]$Receipt.current_remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$') { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-nonce-or-commit-invalid'} }
    foreach ($f in @('transaction_binding_verified','permit_created','session_key_accepted','nonce_accepted','single_use','requires_immediate_external_reservation','requires_atomic_reservation_persistence_before_executor','requires_single_use_consumption','requires_fresh_admission_revalidation_on_reserve','requires_fresh_admission_revalidation_on_consume')) { if (-not [bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-required-flag-false-'+$f)} } }
    foreach ($f in @('session_key_persisted','session_key_exposed','nonce_reserved','permit_reserved','permit_consumed','issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')) { if ([bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuer-authority-or-state-escaped-'+$f)} } }
    $issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue;$reserve=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Receipt.permit_issued_at,[ref]$issued) -or -not [DateTimeOffset]::TryParse([string]$Receipt.permit_expires_at,[ref]$expires) -or -not [DateTimeOffset]::TryParse([string]$Receipt.reservation_eligible_until,[ref]$reserve)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-time-invalid'} }
    if ($expires.ToUniversalTime().Ticks -ne $issued.AddMinutes($CustomAppProductionDualIdNewPermitIssuerPermitTtlMinutes).ToUniversalTime().Ticks) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-permit-ttl-invalid'} }
    if ($reserve -le $issued -or $reserve -gt $issued.AddSeconds($CustomAppProductionDualIdNewPermitIssuerReservationWindowSeconds)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-reservation-window-invalid'} }
    if ($Now -lt $issued.AddSeconds(-5)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-not-yet-valid'} }
    if ($Now -ge $reserve) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-reservation-window-expired'} }
    $bindingMaterial=Get-CustomAppProductionDualIdNewPermitIssuerBindingMaterialV010 -Receipt $Receipt
    $expectedBinding=Get-CustomAppProductionPermitHmacV010 -Text $bindingMaterial -SessionKey $SessionKey
    if (-not (Test-CustomAppProductionPermitFixedTimeHexV010 ([string]$Receipt.transaction_binding_hmac_sha256).ToLowerInvariant() $expectedBinding)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-transaction-binding-hmac-mismatch'} }
    $expected=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $Receipt)
    if (([string]$Receipt.issuer_fingerprint).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuer-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-issued-transaction-bound-unreserved-zero-authority';new_permit_transaction_id=$new;permit_token_id=([string]$Receipt.permit_token_id).Trim().ToLowerInvariant();transaction_binding_hmac_sha256=$expectedBinding;requires_immediate_external_reservation=$true;production_execution_authorized=$false;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionDualIdNewPermitIssuerV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,[Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$IssuanceAdmissionReceipt,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$Nonce,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$TtlMinutes=1,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionDualIdNewPermitIssuerDeniedV010 -Reason $Reason}
    if ($SessionKey.Length -lt 32) { return (& $deny 'dual-id-new-permit-issuer-session-key-too-short') }
    if (-not (Test-CustomAppProductionDualIdNewPermitIssuerNonceV010 $Nonce)) { return (& $deny 'dual-id-new-permit-issuer-nonce-must-be-exactly-32-lowercase-hex') }
    if ($TtlMinutes -ne $CustomAppProductionDualIdNewPermitIssuerPermitTtlMinutes) { return (& $deny 'dual-id-new-permit-issuer-ttl-must-be-exactly-one-minute') }
    $priorCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $IssuanceAdmissionReceipt -Now $Now
    if ($null -eq $priorCheck -or -not [bool]$priorCheck.ok) { return (& $deny ('dual-id-new-permit-issuer-prior-admission-invalid:'+[string]$priorCheck.reason)) }
    $oldPermit=$HistoricalPermitTransactionId.Trim().ToLowerInvariant();$journal=$HistoricalJournalTransactionId.Trim().ToLowerInvariant();$new=$NewPermitTransactionId.Trim().ToLowerInvariant();$nameKey=$Name.Trim().ToLowerInvariant()
    if (([string]$IssuanceAdmissionReceipt.name).Trim().ToLowerInvariant() -cne $nameKey) { return (& $deny 'dual-id-new-permit-issuer-prior-admission-name-mismatch') }
    if (([string]$IssuanceAdmissionReceipt.historical_permit_transaction_id).Trim().ToLowerInvariant() -cne $oldPermit -or ([string]$IssuanceAdmissionReceipt.historical_journal_transaction_id).Trim().ToLowerInvariant() -cne $journal -or ([string]$IssuanceAdmissionReceipt.new_permit_transaction_id).Trim().ToLowerInvariant() -cne $new) { return (& $deny 'dual-id-new-permit-issuer-prior-admission-transaction-mismatch') }

    $fresh=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $null -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $fresh -or -not [bool]$fresh.ok) { return (& $deny ('dual-id-new-permit-issuer-fresh-admission-denied:'+[string]$fresh.reason)) }
    $freshCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $fresh.receipt -Now $Now
    if ($null -eq $freshCheck -or -not [bool]$freshCheck.ok) { return (& $deny ('dual-id-new-permit-issuer-fresh-admission-invalid:'+[string]$freshCheck.reason)) }
    $continuity=Get-CustomAppProductionDualIdNewPermitIssuerAdmissionContinuityV010 -Prior $IssuanceAdmissionReceipt -Current $fresh.receipt
    if (-not [bool]$continuity.ok) { return (& $deny ([string]$continuity.reason)) }

    try { $permit=New-CustomAppProductionPermitV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Nonce $Nonce -IssuedAt $Now -TtlMinutes $CustomAppProductionDualIdNewPermitIssuerPermitTtlMinutes -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours }
    catch { return (& $deny ('dual-id-new-permit-issuer-permit-creation-failed:'+[string]$_.Exception.Message)) }
    $permitCheck=Test-CustomAppProductionPermitV010 -Permit $permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $permitCheck -or -not [bool]$permitCheck.ok) { return (& $deny ('dual-id-new-permit-issuer-created-permit-invalid:'+[string]$permitCheck.reason)) }
    $permitContinuity=Test-CustomAppProductionDualIdNewPermitIssuerPermitAdmissionContinuityV010 -Permit $permit -Admission $fresh.receipt
    if (-not [bool]$permitContinuity.ok) { return (& $deny ([string]$permitContinuity.reason)) }

    $post=Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -HistoricalPermitTransactionId $oldPermit -HistoricalJournalTransactionId $journal -NewPermitTransactionId $new -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -PriorReadinessReceipt $null -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $post -or -not [bool]$post.ok) { return (& $deny ('dual-id-new-permit-issuer-post-creation-admission-denied:'+[string]$post.reason)) }
    $postCheck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if ($null -eq $postCheck -or -not [bool]$postCheck.ok) { return (& $deny ('dual-id-new-permit-issuer-post-creation-admission-invalid:'+[string]$postCheck.reason)) }
    $postContinuity=Get-CustomAppProductionDualIdNewPermitIssuerAdmissionContinuityV010 -Prior $fresh.receipt -Current $post.receipt
    if (-not [bool]$postContinuity.ok) { return (& $deny 'dual-id-new-permit-issuer-admission-drift-during-permit-creation') }

    $f=$fresh.receipt
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionDualIdNewPermitIssuerSchema;managed_by=$CustomAppProductionDualIdNewPermitIssuerManagedBy;qualified_issuance_admission_head=$CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionDualIdNewPermitIssuerQualifiedAdmissionCoreBlob;qualified_permit_head=$CustomAppProductionDualIdNewPermitIssuerQualifiedPermitHead;qualified_permit_core_blob=$CustomAppProductionDualIdNewPermitIssuerQualifiedPermitCoreBlob
        name=([string]$f.name).Trim().ToLowerInvariant();source_identity=([string]$f.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$permit.github_repo_id;surface_kind=([string]$permit.surface_kind).Trim().ToLowerInvariant()
        historical_permit_transaction_id=$oldPermit;historical_journal_transaction_id=$journal;new_permit_transaction_id=$new;transaction_id_namespaces_pairwise_distinct=$true
        prior_issuance_admission_fingerprint=([string]$IssuanceAdmissionReceipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();fresh_issuance_admission_fingerprint=([string]$f.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_creation_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        housekeeping_cleanup_fingerprint=([string]$f.housekeeping_cleanup_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$f.recovery_evidence_fingerprint).Trim().ToLowerInvariant();stable_live_tree_sha256=([string]$f.stable_live_tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$f.stable_persistence_fingerprint).Trim().ToLowerInvariant()
        current_remote_tree_sha256=([string]$f.current_remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$f.current_remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$f.current_binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$f.current_provenance_fingerprint).Trim().ToLowerInvariant();current_remote_observed_at=[string]$f.current_remote_observed_at
        live_admission_fingerprint=([string]$f.live_admission_fingerprint).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$f.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$f.live_attested_qualification_fingerprint).Trim().ToLowerInvariant()
        permit_token_id=([string]$permit.token_id).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$permit.hmac_sha256).Trim().ToLowerInvariant();permit_nonce=([string]$permit.nonce).Trim().ToLowerInvariant();permit_issued_at=[string]$permit.issued_at;permit_expires_at=[string]$permit.expires_at;reservation_eligible_until=$Now.AddSeconds($CustomAppProductionDualIdNewPermitIssuerReservationWindowSeconds).ToUniversalTime().ToString('o')
        transaction_binding_hmac_sha256=$null;transaction_binding_domain=$CustomAppProductionDualIdNewPermitIssuerBindingDomain;transaction_binding_verified=$true
        permit_created=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;nonce_accepted=$true;nonce_reserved=$false;permit_reserved=$false;permit_consumed=$false;single_use=$true
        requires_immediate_external_reservation=$true;requires_atomic_reservation_persistence_before_executor=$true;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_reserve=$true;requires_fresh_admission_revalidation_on_consume=$true
        issuer_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;issuer_fingerprint=$null
    }
    $receipt.transaction_binding_hmac_sha256=Get-CustomAppProductionPermitHmacV010 -Text (Get-CustomAppProductionDualIdNewPermitIssuerBindingMaterialV010 -Receipt $receipt) -SessionKey $SessionKey
    $receipt.issuer_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $receipt -SessionKey $SessionKey -Now $Now
    if (-not [bool]$receiptCheck.ok) { return (& $deny ('dual-id-new-permit-issuer-self-check-failed:'+[string]$receiptCheck.reason)) }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-production-permit-created-transaction-bound-requires-immediate-external-reservation';permit=$permit;receipt=$receipt;permit_created=$true;transaction_binding_created=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;nonce_accepted=$true;nonce_reserved=$false;permit_reserved=$false;permit_consumed=$false;requires_immediate_external_reservation=$true;requires_atomic_reservation_persistence_before_executor=$true;requires_single_use_consumption=$true;issuer_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
