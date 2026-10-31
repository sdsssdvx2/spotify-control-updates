$CustomAppProductionRecoveryAwarePermitIssuerSchema = 1
$CustomAppProductionRecoveryAwarePermitIssuerManagedBy = 'custom-app-production-recovery-aware-permit-issuer-v1'
$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'
$CustomAppProductionRecoveryAwarePermitIssuerQualifiedPermitHead = 'd77f646d23652b0f066248230756d9e207a10fbd'
$CustomAppProductionRecoveryAwarePermitIssuerPermitTtlMinutes = 1
$CustomAppProductionRecoveryAwarePermitIssuerReservationWindowSeconds = 5

function Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwarePermitIssuerSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Test-CustomAppProductionRecoveryAwarePermitIssuerNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}
function New-CustomAppProductionRecoveryAwarePermitIssuerDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;permit=$null;receipt=$null
        permit_created=$false;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false;nonce_accepted=$false;nonce_reserved=$false;permit_reserved=$false;permit_consumed=$false
        issuer_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,[string]$Receipt.qualified_permit_head,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.prior_issuance_admission_fingerprint,[string]$Receipt.fresh_issuance_admission_fingerprint,[string]$Receipt.post_creation_issuance_admission_fingerprint,
        [string]$Receipt.recovery_resume_result_fingerprint,[string]$Receipt.stable_live_tree_sha256,[string]$Receipt.stable_persistence_fingerprint,
        [string]$Receipt.current_remote_tree_sha256,[string]$Receipt.current_remote_commit_sha,[string]$Receipt.current_binding_fingerprint,[string]$Receipt.current_provenance_fingerprint,[string]$Receipt.current_remote_observed_at,
        [string]$Receipt.live_admission_fingerprint,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.permit_nonce,[string]$Receipt.permit_issued_at,[string]$Receipt.permit_expires_at,[string]$Receipt.reservation_eligible_until,
        [string]$Receipt.permit_created,[string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,[string]$Receipt.nonce_accepted,[string]$Receipt.nonce_reserved,[string]$Receipt.permit_reserved,[string]$Receipt.permit_consumed,
        [string]$Receipt.single_use,[string]$Receipt.requires_immediate_external_reservation,[string]$Receipt.requires_atomic_reservation_persistence_before_executor,[string]$Receipt.requires_recovery_aware_reservation_revalidation,
        [string]$Receipt.requires_single_use_consumption,[string]$Receipt.requires_fresh_admission_revalidation_on_consume,[string]$Receipt.replay_protection_requires_external_consumption_ledger,
        [string]$Receipt.issuer_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryAwarePermitIssuerAdmissionContinuityV010 {
    param([AllowNull()]$Prior,[AllowNull()]$Fresh)
    if($null -eq $Prior -or $null -eq $Fresh){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-admission-continuity-null'}}
    $pairs=@(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('recovery_resume_result_fingerprint','recovery_resume_result_fingerprint'),@('stable_live_tree_sha256','stable_live_tree_sha256'),@('stable_persistence_fingerprint','stable_persistence_fingerprint'),
        @('current_remote_tree_sha256','current_remote_tree_sha256'),@('current_remote_commit_sha','current_remote_commit_sha'),@('current_binding_fingerprint','current_binding_fingerprint'),@('current_provenance_fingerprint','current_provenance_fingerprint'),
        @('live_admission_fingerprint','live_admission_fingerprint'),@('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint')
    )
    foreach($p in $pairs){$a=([string]$Prior.($p[0])).Trim().ToLowerInvariant();$b=([string]$Fresh.($p[1])).Trim().ToLowerInvariant();if($a-cne$b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuer-admission-continuity-'+$p[0]+'-mismatch')}}}
    $aTime=[DateTimeOffset]::MinValue;$bTime=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Prior.current_remote_observed_at,[ref]$aTime) -or -not [DateTimeOffset]::TryParse([string]$Fresh.current_remote_observed_at,[ref]$bTime) -or $aTime.ToUniversalTime().Ticks-ne$bTime.ToUniversalTime().Ticks){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-admission-continuity-current_remote_observed_at-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-issuer-admission-continuity-exact'}
}
function Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-receipt-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_issuance_admission_head','qualified_issuance_admission_core_blob','qualified_permit_head','name','source_identity','transaction_id','github_repo_id','surface_kind',
        'prior_issuance_admission_fingerprint','fresh_issuance_admission_fingerprint','post_creation_issuance_admission_fingerprint','recovery_resume_result_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint',
        'current_remote_tree_sha256','current_remote_commit_sha','current_binding_fingerprint','current_provenance_fingerprint','current_remote_observed_at','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint',
        'permit_token_id','permit_hmac_sha256','permit_nonce','permit_issued_at','permit_expires_at','reservation_eligible_until','permit_created','session_key_accepted','session_key_persisted','session_key_exposed','nonce_accepted','nonce_reserved','permit_reserved','permit_consumed','single_use',
        'requires_immediate_external_reservation','requires_atomic_reservation_persistence_before_executor','requires_recovery_aware_reservation_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','replay_protection_requires_external_consumption_ledger',
        'issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','issuer_fingerprint'
    )){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuer-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne$CustomAppProductionRecoveryAwarePermitIssuerSchema -or [string]$Receipt.managed_by-cne$CustomAppProductionRecoveryAwarePermitIssuerManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_issuance_admission_head-cne$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionHead -or [string]$Receipt.qualified_issuance_admission_core_blob-cne$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionCoreBlob -or [string]$Receipt.qualified_permit_head-cne$CustomAppProductionRecoveryAwarePermitIssuerQualifiedPermitHead){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-parent-lineage-mismatch'}}
    if([string]::IsNullOrWhiteSpace([string]$Receipt.name) -or [string]$Receipt.source_identity-notmatch'^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or [int64]$Receipt.github_repo_id-le0 -or [string]::IsNullOrWhiteSpace([string]$Receipt.surface_kind)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-identity-invalid'}}
    foreach($f in @('transaction_id','prior_issuance_admission_fingerprint','fresh_issuance_admission_fingerprint','post_creation_issuance_admission_fingerprint','recovery_resume_result_fingerprint','stable_live_tree_sha256','stable_persistence_fingerprint','current_remote_tree_sha256','current_binding_fingerprint','current_provenance_fingerprint','live_admission_fingerprint','current_eligibility_fingerprint','live_attested_qualification_fingerprint','permit_token_id','permit_hmac_sha256','issuer_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuer-invalid-'+$f)}}}
    if([string]$Receipt.current_remote_commit_sha-notmatch'^[0-9a-f]{40}$' -or -not(Test-CustomAppProductionRecoveryAwarePermitIssuerNonceV010([string]$Receipt.permit_nonce))){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-remote-commit-or-nonce-invalid'}}
    foreach($f in @('permit_created','session_key_accepted','nonce_accepted','single_use','requires_immediate_external_reservation','requires_atomic_reservation_persistence_before_executor','requires_recovery_aware_reservation_revalidation','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','replay_protection_requires_external_consumption_ledger')){if(-not[bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuer-required-flag-false-'+$f)}}}
    foreach($f in @('session_key_persisted','session_key_exposed','nonce_reserved','permit_reserved','permit_consumed','issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-permit-issuer-authority-or-state-escaped-'+$f)}}}
    if(([string]$Receipt.fresh_issuance_admission_fingerprint).Trim().ToLowerInvariant()-cne([string]$Receipt.post_creation_issuance_admission_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-pre-post-admission-drift'}}
    $issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue;$reserveUntil=[DateTimeOffset]::MinValue;$observed=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.permit_issued_at,[ref]$issued) -or -not[DateTimeOffset]::TryParse([string]$Receipt.permit_expires_at,[ref]$expires) -or -not[DateTimeOffset]::TryParse([string]$Receipt.reservation_eligible_until,[ref]$reserveUntil) -or -not[DateTimeOffset]::TryParse([string]$Receipt.current_remote_observed_at,[ref]$observed)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-time-invalid'}}
    if($expires.ToUniversalTime().Ticks-ne$issued.AddMinutes($CustomAppProductionRecoveryAwarePermitIssuerPermitTtlMinutes).ToUniversalTime().Ticks){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-permit-ttl-not-exactly-one-minute'}}
    if($reserveUntil-le$issued -or $reserveUntil-gt$issued.AddSeconds($CustomAppProductionRecoveryAwarePermitIssuerReservationWindowSeconds)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-reservation-window-invalid'}}
    if($Now-lt$issued.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-not-yet-valid'}}
    if($Now-ge$reserveUntil){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-reservation-window-expired'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.issuer_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-permit-issuer-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-created-but-unreserved-zero-authority';token_id=([string]$Receipt.permit_token_id).Trim().ToLowerInvariant();nonce=([string]$Receipt.permit_nonce).Trim().ToLowerInvariant();requires_immediate_external_reservation=$true;production_execution_authorized=$false;production_mutation_authorized=$false}
}
function Invoke-CustomAppProductionRecoveryAwarePermitIssuerV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$IssuanceAdmissionReceipt,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$Nonce,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$TtlMinutes=1,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitIssuerDeniedV010 -Reason $Reason}
    if($SessionKey.Length-lt32){return & $deny 'recovery-aware-permit-issuer-session-key-too-short'}
    if(-not(Test-CustomAppProductionRecoveryAwarePermitIssuerNonceV010 $Nonce)){return & $deny 'recovery-aware-permit-issuer-nonce-must-be-exactly-32-lowercase-hex'}
    if($TtlMinutes-ne$CustomAppProductionRecoveryAwarePermitIssuerPermitTtlMinutes){return & $deny 'recovery-aware-permit-issuer-ttl-must-be-exactly-one-minute'}
    $priorCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $IssuanceAdmissionReceipt -Now $Now
    if(-not[bool]$priorCheck.ok){return & $deny ('recovery-aware-permit-issuer-prior-admission-invalid:'+[string]$priorCheck.reason)}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(([string]$IssuanceAdmissionReceipt.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'recovery-aware-permit-issuer-prior-admission-transaction-mismatch'}
    if(([string]$IssuanceAdmissionReceipt.name).Trim().ToLowerInvariant()-cne$Name.Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuer-prior-admission-name-mismatch'}

    $fresh=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$fresh-or-not[bool]$fresh.ok){return & $deny ('recovery-aware-permit-issuer-fresh-admission-denied:'+[string]$fresh.reason)}
    $freshCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $fresh.receipt -Now $Now
    if(-not[bool]$freshCheck.ok){return & $deny ('recovery-aware-permit-issuer-fresh-admission-invalid:'+[string]$freshCheck.reason)}
    $continuity=Test-CustomAppProductionRecoveryAwarePermitIssuerAdmissionContinuityV010 -Prior $IssuanceAdmissionReceipt -Fresh $fresh.receipt
    if(-not[bool]$continuity.ok){return & $deny ([string]$continuity.reason)}

    try{$permit=New-CustomAppProductionPermitV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Nonce $Nonce -IssuedAt $Now -TtlMinutes $CustomAppProductionRecoveryAwarePermitIssuerPermitTtlMinutes -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours}
    catch{return & $deny ('recovery-aware-permit-issuer-permit-creation-failed:'+[string]$_.Exception.Message)}
    $permitCheck=Test-CustomAppProductionPermitV010 -Permit $permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if(-not[bool]$permitCheck.ok){return & $deny ('recovery-aware-permit-issuer-created-permit-invalid:'+[string]$permitCheck.reason)}

    $post=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null-eq$post-or-not[bool]$post.ok){return & $deny ('recovery-aware-permit-issuer-post-creation-admission-denied:'+[string]$post.reason)}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not[bool]$postCheck.ok){return & $deny ('recovery-aware-permit-issuer-post-creation-admission-invalid:'+[string]$postCheck.reason)}
    if(([string]$fresh.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()-cne([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-permit-issuer-admission-drift-during-permit-creation'}

    $permitPairs=@(
        @('name',[string]$fresh.receipt.name),@('source_identity',[string]$fresh.receipt.source_identity),@('github_repo_id',[string]$fresh.receipt.github_repo_id),@('surface_kind',[string]$fresh.receipt.surface_kind),
        @('current_tree_sha256',[string]$fresh.receipt.stable_live_tree_sha256),@('remote_tree_sha256',[string]$fresh.receipt.current_remote_tree_sha256),@('remote_commit_sha',[string]$fresh.receipt.current_remote_commit_sha),
        @('current_eligibility_fingerprint',[string]$fresh.receipt.current_eligibility_fingerprint),@('live_attested_qualification_fingerprint',[string]$fresh.receipt.live_attested_qualification_fingerprint),@('admission_fingerprint',[string]$fresh.receipt.live_admission_fingerprint)
    )
    foreach($p in $permitPairs){if(([string]$permit.($p[0])).Trim().ToLowerInvariant()-cne([string]$p[1]).Trim().ToLowerInvariant()){return & $deny ('recovery-aware-permit-issuer-permit-continuity-'+$p[0]+'-mismatch')}}
    if(-not[bool]$permit.production_permit_issued -or [bool]$permit.permit_is_authority -or -not[bool]$permit.single_use -or -not[bool]$permit.requires_single_use_consumption -or -not[bool]$permit.requires_fresh_admission_revalidation_on_consume -or -not[bool]$permit.replay_protection_requires_external_consumption_ledger){return & $deny 'recovery-aware-permit-issuer-permit-consumption-contract-invalid'}
    foreach($f in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$permit.$f){return & $deny ('recovery-aware-permit-issuer-created-permit-authority-escaped-'+$f)}}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitIssuerSchema;managed_by=$CustomAppProductionRecoveryAwarePermitIssuerManagedBy
        qualified_issuance_admission_head=$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionRecoveryAwarePermitIssuerQualifiedAdmissionCoreBlob;qualified_permit_head=$CustomAppProductionRecoveryAwarePermitIssuerQualifiedPermitHead
        name=([string]$fresh.receipt.name).Trim().ToLowerInvariant();source_identity=([string]$fresh.receipt.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$fresh.receipt.github_repo_id;surface_kind=[string]$fresh.receipt.surface_kind
        prior_issuance_admission_fingerprint=([string]$IssuanceAdmissionReceipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();fresh_issuance_admission_fingerprint=([string]$fresh.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_creation_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        recovery_resume_result_fingerprint=([string]$fresh.receipt.recovery_resume_result_fingerprint).Trim().ToLowerInvariant();stable_live_tree_sha256=([string]$fresh.receipt.stable_live_tree_sha256).Trim().ToLowerInvariant();stable_persistence_fingerprint=([string]$fresh.receipt.stable_persistence_fingerprint).Trim().ToLowerInvariant()
        current_remote_tree_sha256=([string]$fresh.receipt.current_remote_tree_sha256).Trim().ToLowerInvariant();current_remote_commit_sha=([string]$fresh.receipt.current_remote_commit_sha).Trim().ToLowerInvariant();current_binding_fingerprint=([string]$fresh.receipt.current_binding_fingerprint).Trim().ToLowerInvariant();current_provenance_fingerprint=([string]$fresh.receipt.current_provenance_fingerprint).Trim().ToLowerInvariant();current_remote_observed_at=[string]$fresh.receipt.current_remote_observed_at
        live_admission_fingerprint=([string]$fresh.receipt.live_admission_fingerprint).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$fresh.receipt.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$fresh.receipt.live_attested_qualification_fingerprint).Trim().ToLowerInvariant()
        permit_token_id=([string]$permit.token_id).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$permit.hmac_sha256).Trim().ToLowerInvariant();permit_nonce=([string]$permit.nonce).Trim().ToLowerInvariant();permit_issued_at=[string]$permit.issued_at;permit_expires_at=[string]$permit.expires_at;reservation_eligible_until=$Now.AddSeconds($CustomAppProductionRecoveryAwarePermitIssuerReservationWindowSeconds).ToUniversalTime().ToString('o')
        permit_created=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;nonce_accepted=$true;nonce_reserved=$false;permit_reserved=$false;permit_consumed=$false;single_use=$true
        requires_immediate_external_reservation=$true;requires_atomic_reservation_persistence_before_executor=$true;requires_recovery_aware_reservation_revalidation=$true;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;replay_protection_requires_external_consumption_ledger=$true
        issuer_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;issuer_fingerprint=$null
    }
    $receipt.issuer_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $receipt -Now $Now
    if(-not[bool]$receiptCheck.ok){return & $deny ('recovery-aware-permit-issuer-result-invalid:'+[string]$receiptCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-production-permit-created-requires-immediate-external-reservation';permit=$permit;receipt=$receipt
        permit_created=$true;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false;nonce_accepted=$true;nonce_reserved=$false;permit_reserved=$false;permit_consumed=$false
        issuer_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}