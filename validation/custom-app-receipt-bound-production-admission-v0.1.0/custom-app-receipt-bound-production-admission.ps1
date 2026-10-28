$CustomAppReceiptBoundAdmissionSchema = 1
$CustomAppReceiptBoundAdmissionManagedBy = 'custom-app-receipt-bound-production-admission-v1'
$CustomAppReceiptBoundAdmissionReceiptHead = '635e25a4a06320cd103e07b1506f0ba8787e5c3a'
$CustomAppReceiptBoundAdmissionEligibilityHead = '979e9d6362ead31016b9532f98629d6bcc2bbb56'
$CustomAppReceiptBoundAdmissionProductionMain = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'

function Get-CustomAppReceiptBoundAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppReceiptBoundAdmissionAuthorityDeniedV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-authority-denied')}
}

function New-CustomAppReceiptBoundAdmissionDecisionV010 {
    param([bool]$Eligible,[string]$Reason,[AllowNull()]$Receipt=$null,[AllowNull()]$Eligibility=$null)
    $fingerprint=$null
    if($null -ne $Receipt -and $null -ne $Eligibility){
        $material=@(
            [string]$Receipt.receipt_id,[string]$Receipt.observed_at,[string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
            [string]$Receipt.current_tree_sha256,[string]$Receipt.remote_tree_sha256,[string]$Receipt.remote_commit_sha,[string]$Receipt.before_provenance_evidence_fingerprint,
            [string]$Eligibility.eligibility_fingerprint,[string]$Eligibility.provenance_fingerprint,[string]$Eligibility.binding_fingerprint,[string]$Eligibility.protocol_qualification_fingerprint
        ) -join "`n"
        $fingerprint=Get-CustomAppReceiptBoundAdmissionSha256V010 -Text $material
    }
    return [pscustomobject]@{
        schema=$CustomAppReceiptBoundAdmissionSchema
        managed_by=$CustomAppReceiptBoundAdmissionManagedBy
        production_admission_eligible=$Eligible
        status=$(if($Eligible){'eligible-to-propose-production-permit'}else{'production-admission-denied'})
        reason=$Reason
        admission_fingerprint=$fingerprint
        receipt_id=$(if($null -ne $Receipt){[string]$Receipt.receipt_id}else{$null})
        current_eligibility_fingerprint=$(if($null -ne $Eligibility){[string]$Eligibility.eligibility_fingerprint}else{$null})
        production_admission_decision_only=$true
        production_permit_issued=$false
        receipt_is_authority=$false
        requires_fresh_revalidation_before_any_future_action=$true
        mutation_mode='deny'
        mutation_authorized=$false
        auto_update_authorized=$false
        auto_install_authorized=$false
        canary_execution_authorized=$false
        production_mutation_authorized=$false
    }
}

function Resolve-CustomAppReceiptBoundProductionAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ProtocolQualification,
        [Parameter(Mandatory=$true)]$Receipt,[Parameter(Mandatory=$true)][byte[]]$ReceiptKey,[Parameter(Mandatory=$true)]$ExecutorQualification,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,[int]$MaxReceiptAgeHours=24
    )
    if([string]::IsNullOrWhiteSpace($Name)){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'name-empty'}
    if($MaxRemoteObservationAgeHours -lt 1 -or $MaxRemoteObservationAgeHours -gt 168){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'remote-observation-age-policy-invalid'}
    if($MaxReceiptAgeHours -lt 1 -or $MaxReceiptAgeHours -gt 72){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-age-policy-invalid'}

    $receiptVerification=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $Receipt -ReceiptKey $ReceiptKey -ExecutorQualification $ExecutorQualification
    if(-not [bool]$receiptVerification.ok){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false ('receipt-verification-denied:'+[string]$receiptVerification.reason) -Receipt $Receipt}
    if([string]$Receipt.outcome_classification -cne 'committed-preserved' -or -not [bool]$Receipt.committed -or [bool]$Receipt.rolled_back -or -not [bool]$Receipt.outcome_safe -or -not [bool]$Receipt.outcome_evidence_qualified -or -not [bool]$Receipt.eligibility_candidate_snapshot){
        return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-is-not-qualified-committed-preserved-canary-evidence' -Receipt $Receipt
    }
    if([bool]$Receipt.receipt_is_authority -or -not [bool]$Receipt.requires_fresh_revalidation_before_any_future_action){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-authority-separation-invalid' -Receipt $Receipt}

    $observed=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.observed_at,[ref]$observed)){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-observed-at-invalid' -Receipt $Receipt}
    if($Now -lt $observed.AddMinutes(-5)){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-observed-in-future' -Receipt $Receipt}
    if($Now -gt $observed.AddHours($MaxReceiptAgeHours)){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-stale-for-production-admission' -Receipt $Receipt}

    $eligibility=Resolve-CustomAppPromotionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ProtocolQualification $ProtocolQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $eligibility -or [int]$eligibility.schema -ne 1 -or [string]$eligibility.managed_by -cne 'custom-app-promotion-eligibility-v1'){
        return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'current-eligibility-owner-or-schema-mismatch' -Receipt $Receipt -Eligibility $eligibility
    }
    $eligibilityAuthority=Test-CustomAppReceiptBoundAdmissionAuthorityDeniedV010 -Object $eligibility -Label 'current-eligibility'
    if(-not [bool]$eligibilityAuthority.ok){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false ([string]$eligibilityAuthority.reason) -Receipt $Receipt -Eligibility $eligibility}
    if(-not [bool]$eligibility.promotion_candidate_eligible -or -not [bool]$eligibility.requires_revalidation_before_any_mutation){
        return New-CustomAppReceiptBoundAdmissionDecisionV010 $false ('current-eligibility-denied:'+[string]$eligibility.reason) -Receipt $Receipt -Eligibility $eligibility
    }

    $nameKey=$Name.Trim();$source=([string]$eligibility.source_identity).Trim().ToLowerInvariant();$surface=([string]$eligibility.surface_kind).Trim().ToLowerInvariant()
    if([string]$Receipt.name -cne $nameKey){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-name-mismatch' -Receipt $Receipt -Eligibility $eligibility}
    if(([string]$Receipt.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-source-mismatch' -Receipt $Receipt -Eligibility $eligibility}
    try{$receiptRepo=[int64]$Receipt.github_repo_id;$currentRepo=[int64]$eligibility.github_repo_id}catch{return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-repo-id-invalid' -Receipt $Receipt -Eligibility $eligibility}
    if($receiptRepo -le 0 -or $receiptRepo -ne $currentRepo){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-repo-id-mismatch' -Receipt $Receipt -Eligibility $eligibility}
    if(([string]$Receipt.surface_kind).Trim().ToLowerInvariant() -cne $surface){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-surface-mismatch' -Receipt $Receipt -Eligibility $eligibility}

    foreach($pair in @(
        @('eligibility_fingerprint','eligibility_fingerprint'),
        @('current_tree_sha256','current_tree_sha256'),
        @('remote_tree_sha256','remote_tree_sha256'),
        @('remote_commit_sha','remote_commit_sha')
    )){
        $receiptValue=([string]$Receipt.($pair[0])).Trim().ToLowerInvariant();$currentValue=([string]$eligibility.($pair[1])).Trim().ToLowerInvariant()
        if($receiptValue -cne $currentValue){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false ('receipt-current-'+$pair[0]+'-mismatch') -Receipt $Receipt -Eligibility $eligibility}
    }
    if(([string]$Receipt.before_provenance_source).Trim().ToLowerInvariant() -cne $source -or ([string]$Receipt.after_provenance_source).Trim().ToLowerInvariant() -cne $source){return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-provenance-source-mismatch' -Receipt $Receipt -Eligibility $eligibility}
    if(([string]$Receipt.before_provenance_evidence_fingerprint).Trim().ToLowerInvariant() -cne ([string]$eligibility.provenance_fingerprint).Trim().ToLowerInvariant()){
        return New-CustomAppReceiptBoundAdmissionDecisionV010 $false 'receipt-current-provenance-fingerprint-mismatch' -Receipt $Receipt -Eligibility $eligibility
    }

    return New-CustomAppReceiptBoundAdmissionDecisionV010 $true 'fresh-current-eligibility-matches-qualified-committed-canary-receipt' -Receipt $Receipt -Eligibility $eligibility
}
