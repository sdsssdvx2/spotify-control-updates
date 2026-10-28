$CustomAppLiveAdmissionSchema = 1
$CustomAppLiveAdmissionManagedBy = 'custom-app-live-attested-production-admission-v1'
$CustomAppLiveQualificationManagedBy = 'custom-app-live-attested-protocol-qualification-v1'
$CustomAppLiveQualifiedHead = 'c3ce2311268a078ec6f2b4e512e56110aa347d58'
$CustomAppLiveQualifiedReceiptParent = '635e25a4a06320cd103e07b1506f0ba8787e5c3a'
$CustomAppLiveQualifiedProductionMain = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
$CustomAppLiveQualifiedAddonSha256 = 'b2cec989ef399aed4a8763105121b21181ffb493ed9e3e884baa1d62a634f94b'
$CustomAppLiveQualifiedSpotifySha256 = '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'
$CustomAppLiveQualifiedPushRunId = [int64]40694858363
$CustomAppLiveQualifiedPrRunId = [int64]40695079070
$CustomAppLiveQualifiedPushArtifactId = [int64]12819520599
$CustomAppLiveQualifiedPrArtifactId = [int64]12818612777
$CustomAppLiveQualifiedPushDigest = 'sha256:e025e59499e1e1e5e7a3f7a260cac57f42d9326325fa434d45b39b677fba8a9c'
$CustomAppLiveQualifiedPrDigest = 'sha256:0966b860f4011939248dab1e56a91eb5917c4f51701bbba9c85814a38fd8eda1'

function Get-CustomAppLiveAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppLiveAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppLiveAdmissionDigestV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^sha256:[0-9a-f]{64}$')
}

function Test-CustomAppLiveAdmissionDeniedAuthorityV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','auto_update_authorized','auto_install_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if($Object.PSObject.Properties[$name] -and [bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-authority-denied')}
}

function New-CustomAppLiveAttestedProtocolQualificationV010 {
    return [pscustomobject]@{
        schema=1;managed_by=$CustomAppLiveQualificationManagedBy
        validated_live_head=$CustomAppLiveQualifiedHead;validated_receipt_parent=$CustomAppLiveQualifiedReceiptParent;production_main=$CustomAppLiveQualifiedProductionMain
        addon_manager_sha256=$CustomAppLiveQualifiedAddonSha256;spotify_control_sha256=$CustomAppLiveQualifiedSpotifySha256
        push_success=$true;pull_request_success=$true;committed_preserved_passed=$true;denied_no_mutation_passed=$true;rolled_back_restored_passed=$true
        persistence_preserved_passed=$true;strong_git_provenance_preserved_passed=$true;receipt_parent_replayed=$true;executor_parent_replayed=$true;parent_selftest_passed=$true
        push_run_id=$CustomAppLiveQualifiedPushRunId;pull_request_run_id=$CustomAppLiveQualifiedPrRunId;push_artifact_id=$CustomAppLiveQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppLiveQualifiedPrArtifactId
        push_artifact_digest=$CustomAppLiveQualifiedPushDigest;pull_request_artifact_digest=$CustomAppLiveQualifiedPrDigest
        qualification_is_authority=$false;requires_fresh_current_revalidation=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppLiveAttestedProtocolQualificationV010 {
    param([AllowNull()]$Qualification)
    if($null -eq $Qualification){return [pscustomobject]@{ok=$false;reason='live-qualification-null';fingerprint=$null}}
    if([int]$Qualification.schema -ne 1 -or [string]$Qualification.managed_by -cne $CustomAppLiveQualificationManagedBy){return [pscustomobject]@{ok=$false;reason='live-qualification-owner-or-schema-mismatch';fingerprint=$null}}
    $authority=Test-CustomAppLiveAdmissionDeniedAuthorityV010 -Object $Qualification -Label 'live-qualification'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason;fingerprint=$null}}
    if([bool]$Qualification.qualification_is_authority -or -not [bool]$Qualification.requires_fresh_current_revalidation){return [pscustomobject]@{ok=$false;reason='live-qualification-authority-separation-invalid';fingerprint=$null}}
    if([string]$Qualification.validated_live_head -cne $CustomAppLiveQualifiedHead -or [string]$Qualification.validated_receipt_parent -cne $CustomAppLiveQualifiedReceiptParent -or [string]$Qualification.production_main -cne $CustomAppLiveQualifiedProductionMain){return [pscustomobject]@{ok=$false;reason='live-qualification-lineage-mismatch';fingerprint=$null}}
    if([string]$Qualification.addon_manager_sha256 -cne $CustomAppLiveQualifiedAddonSha256 -or [string]$Qualification.spotify_control_sha256 -cne $CustomAppLiveQualifiedSpotifySha256){return [pscustomobject]@{ok=$false;reason='live-qualification-binary-identity-mismatch';fingerprint=$null}}
    foreach($flag in @('push_success','pull_request_success','committed_preserved_passed','denied_no_mutation_passed','rolled_back_restored_passed','persistence_preserved_passed','strong_git_provenance_preserved_passed','receipt_parent_replayed','executor_parent_replayed','parent_selftest_passed')){
        if(-not $Qualification.PSObject.Properties[$flag] -or -not [bool]$Qualification.$flag){return [pscustomobject]@{ok=$false;reason=('live-qualification-evidence-incomplete-'+$flag);fingerprint=$null}}
    }
    if([int64]$Qualification.push_run_id -ne $CustomAppLiveQualifiedPushRunId -or [int64]$Qualification.pull_request_run_id -ne $CustomAppLiveQualifiedPrRunId){return [pscustomobject]@{ok=$false;reason='live-qualification-run-identity-mismatch';fingerprint=$null}}
    if([int64]$Qualification.push_artifact_id -ne $CustomAppLiveQualifiedPushArtifactId -or [int64]$Qualification.pull_request_artifact_id -ne $CustomAppLiveQualifiedPrArtifactId){return [pscustomobject]@{ok=$false;reason='live-qualification-artifact-identity-mismatch';fingerprint=$null}}
    $push=([string]$Qualification.push_artifact_digest).Trim().ToLowerInvariant();$pr=([string]$Qualification.pull_request_artifact_digest).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppLiveAdmissionDigestV010 $push) -or -not (Test-CustomAppLiveAdmissionDigestV010 $pr) -or $push -cne $CustomAppLiveQualifiedPushDigest -or $pr -cne $CustomAppLiveQualifiedPrDigest -or $push -ceq $pr){return [pscustomobject]@{ok=$false;reason='live-qualification-artifact-digest-mismatch';fingerprint=$null}}
    $material=@([string]$Qualification.validated_live_head,[string]$Qualification.validated_receipt_parent,[string]$Qualification.production_main,[string]$Qualification.addon_manager_sha256,[string]$Qualification.spotify_control_sha256,[string]$Qualification.push_run_id,[string]$Qualification.pull_request_run_id,[string]$Qualification.push_artifact_id,[string]$Qualification.pull_request_artifact_id,$push,$pr) -join "`n"
    return [pscustomobject]@{ok=$true;reason='live-attested-protocol-independently-qualified';fingerprint=(Get-CustomAppLiveAdmissionSha256V010 $material)}
}

function New-CustomAppLiveProductionAdmissionDecisionV010 {
    param([string]$Name,[bool]$Eligible,[string]$Reason,[AllowNull()]$Eligibility=$null,[AllowNull()][string]$LiveQualificationFingerprint=$null)
    $admissionFingerprint=$null
    if($Eligible -and $null -ne $Eligibility){
        $admissionFingerprint=Get-CustomAppLiveAdmissionSha256V010 ((@([string]$Name,[string]$Eligibility.source_identity,[string]$Eligibility.github_repo_id,[string]$Eligibility.current_tree_sha256,[string]$Eligibility.remote_tree_sha256,[string]$Eligibility.remote_commit_sha,[string]$Eligibility.eligibility_fingerprint,$LiveQualificationFingerprint) -join "`n"))
    }
    return [pscustomobject]@{
        schema=$CustomAppLiveAdmissionSchema;managed_by=$CustomAppLiveAdmissionManagedBy;name=$Name
        production_admission_eligible=$Eligible;reason=$Reason
        source_identity=$(if($null -ne $Eligibility){[string]$Eligibility.source_identity}else{$null});github_repo_id=$(if($null -ne $Eligibility){$Eligibility.github_repo_id}else{$null});surface_kind=$(if($null -ne $Eligibility){[string]$Eligibility.surface_kind}else{$null})
        current_tree_sha256=$(if($null -ne $Eligibility){[string]$Eligibility.current_tree_sha256}else{$null});remote_tree_sha256=$(if($null -ne $Eligibility){[string]$Eligibility.remote_tree_sha256}else{$null});remote_commit_sha=$(if($null -ne $Eligibility){[string]$Eligibility.remote_commit_sha}else{$null})
        current_eligibility_fingerprint=$(if($null -ne $Eligibility){[string]$Eligibility.eligibility_fingerprint}else{$null});live_attested_qualification_fingerprint=$LiveQualificationFingerprint;admission_fingerprint=$admissionFingerprint
        admission_is_authority=$false;production_permit_issued=$false;requires_fresh_revalidation_before_any_future_action=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Resolve-CustomAppLiveAttestedProductionAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    if([string]::IsNullOrWhiteSpace($Name)){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason 'name-empty'}
    $live=Test-CustomAppLiveAttestedProtocolQualificationV010 -Qualification $LiveAttestedQualification
    if(-not [bool]$live.ok){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$live.reason)}
    $eligibility=Resolve-CustomAppPromotionEligibilityV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ProtocolQualification $ShadowProtocolQualification -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $eligibility -or [int]$eligibility.schema -ne 1 -or [string]$eligibility.managed_by -cne 'custom-app-promotion-eligibility-v1'){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason 'current-eligibility-owner-or-schema-mismatch' -Eligibility $eligibility -LiveQualificationFingerprint ([string]$live.fingerprint)}
    $authority=Test-CustomAppLiveAdmissionDeniedAuthorityV010 -Object $eligibility -Label 'current-eligibility'
    if(-not [bool]$authority.ok){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$authority.reason) -Eligibility $eligibility -LiveQualificationFingerprint ([string]$live.fingerprint)}
    if(-not [bool]$eligibility.promotion_candidate_eligible){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason ('current-eligibility-denied:'+[string]$eligibility.reason) -Eligibility $eligibility -LiveQualificationFingerprint ([string]$live.fingerprint)}
    if(-not [bool]$eligibility.requires_revalidation_before_any_mutation -or -not (Test-CustomAppLiveAdmissionSha256V010 ([string]$eligibility.eligibility_fingerprint))){return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $false -Reason 'current-eligibility-revalidation-contract-invalid' -Eligibility $eligibility -LiveQualificationFingerprint ([string]$live.fingerprint)}
    return New-CustomAppLiveProductionAdmissionDecisionV010 -Name $Name -Eligible $true -Reason 'fresh-current-evidence-plus-live-attested-protocol-qualified' -Eligibility $eligibility -LiveQualificationFingerprint ([string]$live.fingerprint)
}
