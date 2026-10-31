$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSchema = 1
$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionManagedBy = 'custom-app-production-recovery-aware-permit-issuance-admission-v1'
$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessIntegrationHead = '42dbdca7ef310772ed7e978e9a953c3319b05199'
$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessCoreBlob = '0c73b5352c7b9bd29472d3a145a4fc4333d0574b'
$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedLiveAdmissionHead = 'c128595c3ac7eab338f5d23d7041ae56a6822948'
$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedPermitHead = 'd77f646d23652b0f066248230756d9e207a10fbd'

function Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_readiness_integration_head,[string]$Receipt.qualified_readiness_core_blob,[string]$Receipt.qualified_live_admission_head,[string]$Receipt.qualified_permit_head,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.readiness_fingerprint,[string]$Receipt.recovery_resume_result_fingerprint,[string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.fresh_recovery_readiness_revalidated,[string]$Receipt.fresh_live_admission_revalidated,[string]$Receipt.readiness_live_admission_continuity_verified,
        [string]$Receipt.permit_issuance_eligible,[string]$Receipt.requires_fresh_permit_creation_revalidation,[string]$Receipt.requires_single_use_permit,[string]$Receipt.requires_external_consumption_ledger,
        [string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.issuance_admission_is_authority,[string]$Receipt.permit_issued,[string]$Receipt.session_key_accepted,[string]$Receipt.nonce_reserved,
        [string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}
function New-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;permit_issuance_eligible=$false;requires_fresh_permit_creation_revalidation=$true;requires_single_use_permit=$true;requires_external_consumption_ledger=$true
        issuance_admission_is_authority=$false;permit_issued=$false;session_key_accepted=$false;nonce_reserved=$false
        execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false
    }
}
function Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-receipt-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_readiness_integration_head','qualified_readiness_core_blob','qualified_live_admission_head','qualified_permit_head',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','readiness_fingerprint','recovery_resume_result_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint',
        'fresh_recovery_readiness_revalidated','fresh_live_admission_revalidated','readiness_live_admission_continuity_verified','permit_issuance_eligible','requires_fresh_permit_creation_revalidation','requires_single_use_permit','requires_external_consumption_ledger',
        'checked_at','eligible_until','issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','issuance_admission_fingerprint'
    )){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuance-admission-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_readiness_integration_head -cne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessIntegrationHead -or [string]$Receipt.qualified_readiness_core_blob -cne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessCoreBlob -or [string]$Receipt.qualified_live_admission_head -cne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedLiveAdmissionHead -or [string]$Receipt.qualified_permit_head -cne $CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedPermitHead){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-parent-lineage-mismatch'}}
    if([string]::IsNullOrWhiteSpace([string]$Receipt.name) -or [string]$Receipt.source_identity -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or [int64]$Receipt.github_repo_id -le 0 -or [string]::IsNullOrWhiteSpace([string]$Receipt.surface_kind)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-identity-invalid'}}
    foreach($f in @('transaction_id','readiness_fingerprint','recovery_resume_result_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','issuance_admission_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuance-admission-invalid-'+$f)}}}
    if([string]$Receipt.current_remote_commit_sha -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-invalid-current_remote_commit_sha'}}
    foreach($f in @('fresh_recovery_readiness_revalidated','fresh_live_admission_revalidated','readiness_live_admission_continuity_verified','permit_issuance_eligible','requires_fresh_permit_creation_revalidation','requires_single_use_permit','requires_external_consumption_ledger')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuance-admission-required-flag-false-'+$f)}}}
    foreach($f in @('issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuance-admission-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;$observed=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start) -or -not [DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end) -or -not [DateTimeOffset]::TryParse([string]$Receipt.current_remote_observed_at,[ref]$observed)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-time-invalid'}}
    if($end -le $start -or $end -gt $start.AddSeconds(5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-window-invalid'}}
    if($Now -lt $start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-not-yet-valid'}}
    if($Now -ge $end){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-expired'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuance-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-issuance-admission-valid-zero-authority';name=([string]$Receipt.name).Trim().ToLowerInvariant();source=([string]$Receipt.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant()}
}
function Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,
        [AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionDeniedV010 -Reason $Reason}
    $nameKey=$Name.Trim().ToLowerInvariant();if([string]::IsNullOrWhiteSpace($nameKey)){return & $deny 'recovery-aware-permit-issuance-admission-name-empty'}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 $tx)){return & $deny 'recovery-aware-permit-issuance-admission-transaction-id-invalid'}

    $ready=Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
    if($null -eq $ready -or -not [bool]$ready.ok){return & $deny ('recovery-aware-permit-issuance-admission-readiness-denied:'+[string]$ready.reason)}
    $rc=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $ready.receipt -Now $Now
    if(-not [bool]$rc.ok){return & $deny ('recovery-aware-permit-issuance-admission-readiness-invalid:'+[string]$rc.reason)}
    $r=$ready.receipt
    if(-not [bool]$r.eligible_to_request_new_update_permit -or -not [bool]$r.requires_new_update_permit){return & $deny 'recovery-aware-permit-issuance-admission-readiness-not-eligible-for-new-permit'}

    $live=Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    $a=Test-CustomAppProductionPermitAdmissionDecisionV010 -Decision $live
    if($null -eq $a -or -not [bool]$a.ok){return & $deny ('recovery-aware-permit-issuance-admission-live-admission-denied:'+[string]$a.reason)}

    if(([string]$r.name).Trim().ToLowerInvariant() -cne ([string]$a.name).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-name-mismatch'}
    if(([string]$r.source_identity).Trim().ToLowerInvariant() -cne ([string]$a.source).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-source-mismatch'}
    if(([string]$r.stable_live_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$a.current).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-current-tree-mismatch'}
    if(([string]$r.current_remote_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$a.remote).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-remote-tree-mismatch'}
    if(([string]$r.current_remote_commit_sha).Trim().ToLowerInvariant() -cne ([string]$a.commit).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-remote-commit-mismatch'}
    $bindingFp=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow
    if([string]::IsNullOrWhiteSpace($bindingFp) -or ([string]$r.current_binding_fingerprint).Trim().ToLowerInvariant() -cne ([string]$bindingFp).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-binding-fingerprint-mismatch'}
    if($null -eq $ProvenanceRow -or ([string]$r.current_provenance_fingerprint).Trim().ToLowerInvariant() -cne ([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuance-admission-continuity-provenance-fingerprint-mismatch'}
    $observed=[DateTimeOffset]::MinValue;$bindingObserved=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$r.current_remote_observed_at,[ref]$observed) -or -not [DateTimeOffset]::TryParse([string]$BindingRow.last_success,[ref]$bindingObserved) -or $observed.ToUniversalTime().Ticks -ne $bindingObserved.ToUniversalTime().Ticks){return & $deny 'recovery-aware-permit-issuance-admission-continuity-remote-observed-at-mismatch'}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSchema;managed_by=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionManagedBy
        qualified_readiness_integration_head=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessIntegrationHead;qualified_readiness_core_blob=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedReadinessCoreBlob;qualified_live_admission_head=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedLiveAdmissionHead;qualified_permit_head=$CustomAppProductionRecoveryAwarePermitIssuanceAdmissionQualifiedPermitHead
        name=$nameKey;source_identity=([string]$a.source).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$a.repo_id;surface_kind=[string]$a.surface
        readiness_fingerprint=([string]$r.readiness_fingerprint).Trim().ToLowerInvariant();recovery_resume_result_fingerprint=([string]$r.recovery_resume_result_fingerprint).Trim().ToLowerInvariant();stable_live_tree_sha256=([string]$r.stable_live_tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$r.stable_persistence_fingerprint).Trim().ToLowerInvariant()
        current_remote_tree_sha256=([string]$r.current_remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$r.current_remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$r.current_binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$r.current_provenance_fingerprint).Trim().ToLowerInvariant();current_remote_observed_at=$observed.ToUniversalTime().ToString('o')
        live_admission_fingerprint=([string]$a.admission_fingerprint).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$a.eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$a.live_fingerprint).Trim().ToLowerInvariant()
        fresh_recovery_readiness_revalidated=$true;fresh_live_admission_revalidated=$true;readiness_live_admission_continuity_verified=$true
        permit_issuance_eligible=$true;requires_fresh_permit_creation_revalidation=$true;requires_single_use_permit=$true;requires_external_consumption_ledger=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(5).ToUniversalTime().ToString('o')
        issuance_admission_is_authority=$false;permit_issued=$false;session_key_accepted=$false;nonce_reserved=$false
        execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;issuance_admission_fingerprint=$null
    }
    $receipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $receipt)
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-issuance-admission-eligible-zero-authority';receipt=$receipt;readiness=$r;live_admission=$live}
}
