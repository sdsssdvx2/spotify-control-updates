$CustomAppProductionDualIdNewPermitIssuanceAdmissionSchema = 1
$CustomAppProductionDualIdNewPermitIssuanceAdmissionManagedBy = 'custom-app-production-dual-id-new-permit-issuance-admission-v1'
$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessHead = '29129bff0a6cc8560b9052a1d213f602f73f76a7'
$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessCoreBlob = 'a6734b92b3c529fe81ab9c0f947956b425833998'
$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedLiveAdmissionHead = 'c128595c3ac7eab338f5d23d7041ae56a6822948'
$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedPermitHead = 'd77f646d23652b0f066248230756d9e207a10fbd'

function Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionDualIdNewPermitIssuanceAdmissionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false; reason=$Reason; receipt=$null; permit_issuance_eligible=$false
        requires_fresh_permit_creation_revalidation=$true; requires_single_use_permit=$true; requires_external_consumption_ledger=$true
        issuance_admission_is_authority=$false; permit_issued=$false; session_key_accepted=$false; nonce_reserved=$false
        execution_authorized=$false; restore_authorized=$false; apply_authorized=$false; cleanup_authorized=$false; production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_readiness_head,[string]$Receipt.qualified_readiness_core_blob,[string]$Receipt.qualified_live_admission_head,[string]$Receipt.qualified_permit_head,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.historical_permit_transaction_id,[string]$Receipt.historical_journal_transaction_id,[string]$Receipt.new_permit_transaction_id,[string]$Receipt.transaction_id_namespaces_pairwise_distinct,
        [string]$Receipt.prior_readiness_fingerprint,[string]$Receipt.fresh_readiness_fingerprint,[string]$Receipt.housekeeping_cleanup_fingerprint,[string]$Receipt.recovery_evidence_fingerprint,[string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.fresh_readiness_revalidated,[string]$Receipt.fresh_live_admission_revalidated,[string]$Receipt.readiness_live_admission_continuity_verified,[string]$Receipt.new_transaction_namespace_verified,
        [string]$Receipt.permit_issuance_eligible,[string]$Receipt.requires_fresh_permit_creation_revalidation,[string]$Receipt.requires_single_use_permit,[string]$Receipt.requires_external_consumption_ledger,[string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.issuance_admission_is_authority,[string]$Receipt.permit_issued,[string]$Receipt.session_key_accepted,[string]$Receipt.nonce_reserved,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if ($null -eq $Receipt) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-null'} }
    $required = @(
        'schema','managed_by','qualified_readiness_head','qualified_readiness_core_blob','qualified_live_admission_head','qualified_permit_head','name','source_identity',
        'historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','transaction_id_namespaces_pairwise_distinct',
        'prior_readiness_fingerprint','fresh_readiness_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint',
        'current_eligibility_fingerprint','live_attested_qualification_fingerprint','fresh_readiness_revalidated','fresh_live_admission_revalidated','readiness_live_admission_continuity_verified','new_transaction_namespace_verified',
        'permit_issuance_eligible','requires_fresh_permit_creation_revalidation','requires_single_use_permit','requires_external_consumption_ledger','checked_at','eligible_until',
        'issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','issuance_admission_fingerprint'
    )
    foreach ($f in $required) {
        if (-not $Receipt.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuance-admission-receipt-field-missing-'+$f)} }
    }
    if ([int]$Receipt.schema -ne $CustomAppProductionDualIdNewPermitIssuanceAdmissionSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionDualIdNewPermitIssuanceAdmissionManagedBy) {
        return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-owner-schema-invalid'}
    }
    if ([string]$Receipt.qualified_readiness_head -cne $CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessHead -or
        [string]$Receipt.qualified_readiness_core_blob -cne $CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessCoreBlob -or
        [string]$Receipt.qualified_live_admission_head -cne $CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedLiveAdmissionHead -or
        [string]$Receipt.qualified_permit_head -cne $CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedPermitHead) {
        return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-lineage-invalid'}
    }
    foreach ($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id','prior_readiness_fingerprint','fresh_readiness_fingerprint','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','issuance_admission_fingerprint')) {
        if (-not (Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))) {
            return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuance-admission-receipt-invalid-'+$f)}
        }
    }
    $a = ([string]$Receipt.historical_permit_transaction_id).Trim().ToLowerInvariant()
    $b = ([string]$Receipt.historical_journal_transaction_id).Trim().ToLowerInvariant()
    $c = ([string]$Receipt.new_permit_transaction_id).Trim().ToLowerInvariant()
    if ($a -ceq $b -or $a -ceq $c -or $b -ceq $c -or -not [bool]$Receipt.transaction_id_namespaces_pairwise_distinct -or -not [bool]$Receipt.new_transaction_namespace_verified) {
        return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-transaction-namespaces-not-pairwise-distinct'}
    }
    if (([string]$Receipt.current_remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$') { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-remote-commit-invalid'} }
    foreach ($f in @('fresh_readiness_revalidated','fresh_live_admission_revalidated','readiness_live_admission_continuity_verified','permit_issuance_eligible','requires_fresh_permit_creation_revalidation','requires_single_use_permit','requires_external_consumption_ledger')) {
        if (-not [bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuance-admission-receipt-required-flag-false-'+$f)} }
    }
    foreach ($f in @('issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')) {
        if ([bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('dual-id-new-permit-issuance-admission-receipt-authority-escaped-'+$f)} }
    }
    $start=[DateTimeOffset]::MinValue; $end=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start) -or -not [DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-time-invalid'} }
    if ($end -le $start -or $end -gt $start.AddSeconds(5)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-window-invalid'} }
    if ($Now -lt $start.AddSeconds(-5)) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-not-yet-valid'} }
    if ($Now -ge $end) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-expired'} }
    $expected = Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionMaterialV010 $Receipt)
    if (([string]$Receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='dual-id-new-permit-issuance-admission-receipt-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-issuance-admission-valid-zero-authority';new_permit_transaction_id=$c;issuance_admission_fingerprint=$expected;permit_issued=$false;production_mutation_authorized=$false}
}

function Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,[Parameter(Mandatory=$true)]$ProvenanceRow,[Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)]$StageResult,[Parameter(Mandatory=$true)]$ShadowResult,[Parameter(Mandatory=$true)]$HousekeepingResult,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$HistoricalPermitTransactionId,[Parameter(Mandatory=$true)][string]$HistoricalJournalTransactionId,[Parameter(Mandatory=$true)][string]$NewPermitTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)]$PriorReadinessReceipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny = { param([string]$Reason) New-CustomAppProductionDualIdNewPermitIssuanceAdmissionDeniedV010 -Reason $Reason }
    $nameKey = $Name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($nameKey)) { return (& $deny 'dual-id-new-permit-issuance-admission-name-empty') }
    $oldPermit = $HistoricalPermitTransactionId.Trim().ToLowerInvariant()
    $journal = $HistoricalJournalTransactionId.Trim().ToLowerInvariant()
    $new = $NewPermitTransactionId.Trim().ToLowerInvariant()
    foreach ($p in @(@('historical-permit',$oldPermit),@('historical-journal',$journal),@('new-permit',$new))) {
        if (-not (Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 ([string]$p[1]))) { return (& $deny ('dual-id-new-permit-issuance-admission-'+[string]$p[0]+'-transaction-id-invalid')) }
    }
    if ($oldPermit -ceq $journal) { return (& $deny 'dual-id-new-permit-issuance-admission-historical-ids-conflated') }
    if ($new -ceq $oldPermit -or $new -ceq $journal) { return (& $deny 'dual-id-new-permit-issuance-admission-new-transaction-id-reused') }

    $pc = Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $PriorReadinessReceipt -Now $Now
    if ($null -eq $pc -or -not [bool]$pc.ok) { return (& $deny ('dual-id-new-permit-issuance-admission-prior-readiness-invalid:'+[string]$pc.reason)) }
    if (([string]$PriorReadinessReceipt.name).Trim().ToLowerInvariant() -cne $nameKey -or
        ([string]$PriorReadinessReceipt.permit_transaction_id).Trim().ToLowerInvariant() -cne $oldPermit -or
        ([string]$PriorReadinessReceipt.journal_transaction_id).Trim().ToLowerInvariant() -cne $journal) {
        return (& $deny 'dual-id-new-permit-issuance-admission-prior-readiness-identity-mismatch')
    }

    $fresh = Resolve-CustomAppProductionDualIdNewPermitReadinessV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -HousekeepingResult $HousekeepingResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedPermitTransactionId $oldPermit -ExpectedJournalTransactionId $journal -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if ($null -eq $fresh -or -not [bool]$fresh.ok) { return (& $deny ('dual-id-new-permit-issuance-admission-fresh-readiness-denied:'+[string]$fresh.reason)) }
    $fc = Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $fresh.receipt -Now $Now
    if ($null -eq $fc -or -not [bool]$fc.ok) { return (& $deny ('dual-id-new-permit-issuance-admission-fresh-readiness-invalid:'+[string]$fc.reason)) }
    $r = $fresh.receipt
    foreach ($f in @('name','source_identity','permit_transaction_id','journal_transaction_id','housekeeping_cleanup_fingerprint','recovery_evidence_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at')) {
        if (([string]$PriorReadinessReceipt.$f).Trim().ToLowerInvariant() -cne ([string]$r.$f).Trim().ToLowerInvariant()) { return (& $deny ('dual-id-new-permit-issuance-admission-readiness-continuity-mismatch-'+$f)) }
    }

    $live = Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    $lc = Test-CustomAppProductionPermitAdmissionDecisionV010 -Decision $live
    if ($null -eq $lc -or -not [bool]$lc.ok) { return (& $deny ('dual-id-new-permit-issuance-admission-live-admission-denied:'+[string]$lc.reason)) }
    if (([string]$r.name).Trim().ToLowerInvariant() -cne ([string]$lc.name).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-live-name-mismatch') }
    if (([string]$r.source_identity).Trim().ToLowerInvariant() -cne ([string]$lc.source).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-live-source-mismatch') }
    if (([string]$r.stable_live_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$lc.current).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-live-current-tree-mismatch') }
    if (([string]$r.current_remote_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$lc.remote).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-live-remote-tree-mismatch') }
    if (([string]$r.current_remote_commit_sha).Trim().ToLowerInvariant() -cne ([string]$lc.commit).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-live-remote-commit-mismatch') }
    if (([string]$r.current_provenance_fingerprint).Trim().ToLowerInvariant() -cne ([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-provenance-fingerprint-mismatch') }
    $bindingFp = Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow
    if (([string]$r.current_binding_fingerprint).Trim().ToLowerInvariant() -cne ([string]$bindingFp).Trim().ToLowerInvariant()) { return (& $deny 'dual-id-new-permit-issuance-admission-binding-fingerprint-mismatch') }

    $receipt = [pscustomobject]@{
        schema=1; managed_by=$CustomAppProductionDualIdNewPermitIssuanceAdmissionManagedBy
        qualified_readiness_head=$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessHead; qualified_readiness_core_blob=$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedReadinessCoreBlob
        qualified_live_admission_head=$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedLiveAdmissionHead; qualified_permit_head=$CustomAppProductionDualIdNewPermitIssuanceAdmissionQualifiedPermitHead
        name=$nameKey; source_identity=([string]$r.source_identity).Trim().ToLowerInvariant(); historical_permit_transaction_id=$oldPermit; historical_journal_transaction_id=$journal; new_permit_transaction_id=$new; transaction_id_namespaces_pairwise_distinct=$true
        prior_readiness_fingerprint=([string]$PriorReadinessReceipt.readiness_fingerprint).Trim().ToLowerInvariant(); fresh_readiness_fingerprint=([string]$r.readiness_fingerprint).Trim().ToLowerInvariant(); housekeeping_cleanup_fingerprint=([string]$r.housekeeping_cleanup_fingerprint).Trim().ToLowerInvariant(); recovery_evidence_fingerprint=([string]$r.recovery_evidence_fingerprint).Trim().ToLowerInvariant()
        stable_live_tree_sha256=([string]$r.stable_live_tree_sha256).Trim().ToLowerInvariant(); stable_persistence_fingerprint=([string]$r.stable_persistence_fingerprint).Trim().ToLowerInvariant(); current_remote_tree_sha256=([string]$r.current_remote_tree_sha256).Trim().ToLowerInvariant(); current_remote_commit_sha=([string]$r.current_remote_commit_sha).Trim().ToLowerInvariant(); current_binding_fingerprint=([string]$r.current_binding_fingerprint).Trim().ToLowerInvariant(); current_provenance_fingerprint=([string]$r.current_provenance_fingerprint).Trim().ToLowerInvariant(); current_remote_observed_at=[string]$r.current_remote_observed_at
        live_admission_fingerprint=([string]$lc.admission_fingerprint).Trim().ToLowerInvariant(); current_eligibility_fingerprint=([string]$lc.eligibility_fingerprint).Trim().ToLowerInvariant(); live_attested_qualification_fingerprint=([string]$lc.live_fingerprint).Trim().ToLowerInvariant()
        fresh_readiness_revalidated=$true; fresh_live_admission_revalidated=$true; readiness_live_admission_continuity_verified=$true; new_transaction_namespace_verified=$true
        permit_issuance_eligible=$true; requires_fresh_permit_creation_revalidation=$true; requires_single_use_permit=$true; requires_external_consumption_ledger=$true
        checked_at=$Now.ToUniversalTime().ToString('o'); eligible_until=$Now.AddSeconds(5).ToUniversalTime().ToString('o')
        issuance_admission_is_authority=$false; permit_issued=$false; session_key_accepted=$false; nonce_reserved=$false; execution_authorized=$false; restore_authorized=$false; apply_authorized=$false; cleanup_authorized=$false; production_mutation_authorized=$false
        issuance_admission_fingerprint=$null
    }
    $receipt.issuance_admission_fingerprint = Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionMaterialV010 $receipt)
    return [pscustomobject]@{ok=$true;reason='dual-id-new-permit-issuance-admission-ready-zero-authority';receipt=$receipt;permit_issuance_eligible=$true;permit_issued=$false;execution_authorized=$false;production_mutation_authorized=$false}
}
