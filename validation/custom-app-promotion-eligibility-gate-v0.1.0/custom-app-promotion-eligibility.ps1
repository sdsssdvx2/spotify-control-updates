$CustomAppPromotionEligibilitySchema = 1
$CustomAppPromotionEligibilityManagedBy = 'custom-app-promotion-eligibility-v1'
$CustomAppPromotionQualifiedShadowHead = '22eb3561843fbe4016023d527186aa629512b67d'
$CustomAppPromotionQualifiedStageHead = 'c420a1df6f306c7ba74772b91241cb14abd04738'
$CustomAppPromotionQualifiedProductionMain = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
$CustomAppPromotionQualifiedAddonSha256 = 'b2cec989ef399aed4a8763105121b21181ffb493ed9e3e884baa1d62a634f94b'
$CustomAppPromotionQualifiedSpotifySha256 = '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'
$CustomAppPromotionQualifiedPushRunId = [int64]40673331603
$CustomAppPromotionQualifiedPrRunId = [int64]40673541954
$CustomAppPromotionQualifiedPushArtifactId = [int64]12808363735
$CustomAppPromotionQualifiedPrArtifactId = [int64]12809940304
$CustomAppPromotionQualifiedPushArtifactDigest = 'sha256:ab1d0b651e89c19670d75fc07082cdadde81f5082a791554ed4861b02b8740dd'
$CustomAppPromotionQualifiedPrArtifactDigest = 'sha256:9ce022e987f6522b767aa330f2e1338210b13ceb5c34617377b548949dcc6c0c'

function Get-CustomAppPromotionStringSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppPromotionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppPromotionCommitShaV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Test-CustomAppPromotionArtifactDigestV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^sha256:[0-9a-f]{64}$')
}

function Test-CustomAppPromotionSourceV010 {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return $false}
    return ($Value.Trim().ToLowerInvariant() -cmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$')
}

function Test-CustomAppPromotionStrictDeniedAuthorityV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','auto_update_authorized','auto_install_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    if([bool]$Object.auto_update_authorized -or [bool]$Object.auto_install_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-auto-authority-true')}}
    if($Object.PSObject.Properties['mutation_authorized'] -and [bool]$Object.mutation_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-authorized-true')}}
    if($Object.PSObject.Properties['production_mutation_authorized'] -and [bool]$Object.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-production-authority-true')}}
    if($Object.PSObject.Properties['canary_execution_authorized'] -and [bool]$Object.canary_execution_authorized){return [pscustomobject]@{ok=$false;reason=($Label+'-canary-authority-true')}}
    return [pscustomobject]@{ok=$true;reason=($Label+'-strict-denied-authority')}
}

function Get-CustomAppPromotionBindingFingerprintV010 {
    param([Parameter(Mandatory=$true)]$BindingRow)
    $binding=$BindingRow.binding
    if($null -eq $binding){return $null}
    $material=@(
        [string]$BindingRow.name,[string]$BindingRow.source_identity,[string]$BindingRow.last_success,
        [string]$BindingRow.last_remote_tree_sha256,[string]$BindingRow.last_remote_commit_sha,
        [string]$binding.source_identity,[string]$binding.github_repo_id,[string]$binding.surface_kind,
        [string]$binding.layout_root,[string]$binding.manifest_name,[string]$binding.last_verified_local_tree_sha256,
        [string]$binding.last_verified_remote_tree_sha256,[string]$binding.last_verified_commit_sha,
        [string]$binding.release_asset_selector,[string]$binding.asset_name,[string]$binding.last_observed_asset_id,
        [string]$binding.last_observed_asset_digest_sha256
    ) -join "`n"
    return Get-CustomAppPromotionStringSha256V010 -Text $material
}

function Test-CustomAppPromotionProtocolQualificationV010 {
    param([AllowNull()]$Qualification)
    if($null -eq $Qualification){return [pscustomobject]@{ok=$false;reason='protocol-qualification-null';fingerprint=$null}}
    if([int]$Qualification.schema -ne 1 -or [string]$Qualification.managed_by -cne 'custom-app-shadow-protocol-qualification-v1'){
        return [pscustomobject]@{ok=$false;reason='protocol-qualification-owner-or-schema-mismatch';fingerprint=$null}
    }
    $authority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $Qualification -Label 'protocol-qualification'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason;fingerprint=$null}}
    if([string]$Qualification.validated_shadow_head -cne $CustomAppPromotionQualifiedShadowHead){return [pscustomobject]@{ok=$false;reason='qualified-shadow-head-mismatch';fingerprint=$null}}
    if([string]$Qualification.validated_stage_parent -cne $CustomAppPromotionQualifiedStageHead){return [pscustomobject]@{ok=$false;reason='qualified-stage-head-mismatch';fingerprint=$null}}
    if([string]$Qualification.production_main -cne $CustomAppPromotionQualifiedProductionMain){return [pscustomobject]@{ok=$false;reason='qualified-production-main-mismatch';fingerprint=$null}}
    if([string]$Qualification.addon_manager_sha256 -cne $CustomAppPromotionQualifiedAddonSha256 -or [string]$Qualification.spotify_control_sha256 -cne $CustomAppPromotionQualifiedSpotifySha256){return [pscustomobject]@{ok=$false;reason='qualified-parent-binary-identity-mismatch';fingerprint=$null}}
    if(-not [bool]$Qualification.push_success -or -not [bool]$Qualification.pull_request_success -or -not [bool]$Qualification.offline_matrix_passed -or -not [bool]$Qualification.live_tagify_331_to_332_passed -or -not [bool]$Qualification.parent_selftest_passed){return [pscustomobject]@{ok=$false;reason='qualified-shadow-evidence-incomplete';fingerprint=$null}}
    if([int64]$Qualification.push_run_id -ne $CustomAppPromotionQualifiedPushRunId -or [int64]$Qualification.pull_request_run_id -ne $CustomAppPromotionQualifiedPrRunId){return [pscustomobject]@{ok=$false;reason='qualified-run-identity-mismatch';fingerprint=$null}}
    if([int64]$Qualification.push_artifact_id -ne $CustomAppPromotionQualifiedPushArtifactId -or [int64]$Qualification.pull_request_artifact_id -ne $CustomAppPromotionQualifiedPrArtifactId){return [pscustomobject]@{ok=$false;reason='qualified-artifact-identity-mismatch';fingerprint=$null}}
    $pushDigest=([string]$Qualification.push_artifact_digest).Trim().ToLowerInvariant();$prDigest=([string]$Qualification.pull_request_artifact_digest).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionArtifactDigestV010 $pushDigest) -or -not (Test-CustomAppPromotionArtifactDigestV010 $prDigest)){return [pscustomobject]@{ok=$false;reason='qualified-artifact-digest-invalid';fingerprint=$null}}
    if($pushDigest -cne $CustomAppPromotionQualifiedPushArtifactDigest -or $prDigest -cne $CustomAppPromotionQualifiedPrArtifactDigest -or $pushDigest -ceq $prDigest){return [pscustomobject]@{ok=$false;reason='qualified-artifact-digest-mismatch';fingerprint=$null}}
    $material=@(
        [string]$Qualification.validated_shadow_head,[string]$Qualification.validated_stage_parent,[string]$Qualification.production_main,
        [string]$Qualification.addon_manager_sha256,[string]$Qualification.spotify_control_sha256,[string]$Qualification.push_run_id,
        [string]$Qualification.pull_request_run_id,[string]$Qualification.push_artifact_id,[string]$Qualification.pull_request_artifact_id,
        $pushDigest,$prDigest
    ) -join "`n"
    return [pscustomobject]@{ok=$true;reason='shadow-protocol-independently-qualified';fingerprint=(Get-CustomAppPromotionStringSha256V010 -Text $material)}
}

function New-CustomAppPromotionDecisionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][bool]$Eligible,
        [Parameter(Mandatory=$true)][string]$Reason,
        [AllowNull()][string]$Source=$null,[AllowNull()]$RepoId=$null,[AllowNull()][string]$Surface=$null,
        [AllowNull()][string]$CurrentTree=$null,[AllowNull()][string]$RemoteTree=$null,[AllowNull()][string]$RemoteCommit=$null,
        [AllowNull()][string]$ProvenanceFingerprint=$null,[AllowNull()][string]$BindingFingerprint=$null,
        [AllowNull()][string]$ProtocolFingerprint=$null,[AllowNull()][string]$EligibilityFingerprint=$null
    )
    return [pscustomobject]@{
        schema=$CustomAppPromotionEligibilitySchema;managed_by=$CustomAppPromotionEligibilityManagedBy;name=$Name
        promotion_candidate_eligible=$Eligible;reason=$Reason;source_identity=$Source;github_repo_id=$RepoId;surface_kind=$Surface
        current_tree_sha256=$CurrentTree;remote_tree_sha256=$RemoteTree;remote_commit_sha=$RemoteCommit
        provenance_fingerprint=$ProvenanceFingerprint;binding_fingerprint=$BindingFingerprint;protocol_qualification_fingerprint=$ProtocolFingerprint;eligibility_fingerprint=$EligibilityFingerprint
        requires_revalidation_before_any_mutation=$true;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false
        canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Resolve-CustomAppPromotionEligibilityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ProtocolQualification,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $nameKey=$Name.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'name-empty'}
    if($MaxRemoteObservationAgeHours -lt 1 -or $MaxRemoteObservationAgeHours -gt 168){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'remote-observation-age-policy-invalid'}

    $protocol=Test-CustomAppPromotionProtocolQualificationV010 -Qualification $ProtocolQualification
    if(-not [bool]$protocol.ok){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$protocol.reason)}

    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$LifecycleRow.kind -cne 'custom-app'){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'lifecycle-owner-or-kind-mismatch' -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($LifecycleRow.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$LifecycleRow.name) -and ([string]$LifecycleRow.name).Trim().ToLowerInvariant() -cne $nameKey){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'lifecycle-name-mismatch' -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$LifecycleRow.locations[0])){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'lifecycle-not-current-safe-single-path' -ProtocolFingerprint ([string]$protocol.fingerprint)}
    try{$livePath=[IO.Path]::GetFullPath([string]$LifecycleRow.locations[0])}catch{return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'lifecycle-path-invalid' -ProtocolFingerprint ([string]$protocol.fingerprint)}

    if($null -eq $ProvenanceRow -or [int]$ProvenanceRow.schema -ne 1 -or [string]$ProvenanceRow.managed_by -cne 'custom-app-provenance-v1'){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'provenance-owner-or-schema-mismatch' -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $provAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $ProvenanceRow -Label 'provenance-row'
    if(-not [bool]$provAuthority.ok){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$provAuthority.reason) -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $source=([string]$ProvenanceRow.source_identity).Trim().ToLowerInvariant();$lastSource=([string]$ProvenanceRow.last_proven_source).Trim().ToLowerInvariant();$provFp=([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionSourceV010 $source) -or $lastSource -cne $source -or [bool]$ProvenanceRow.source_changed -or [bool]$ProvenanceRow.requires_reenrollment -or -not (Test-CustomAppPromotionSha256V010 $provFp)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'provenance-not-current-strong' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}

    if($null -eq $BindingRow -or [int]$BindingRow.schema -ne 1 -or [string]$BindingRow.managed_by -cne 'custom-app-remote-binding-observer-v1'){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-owner-or-schema-mismatch' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $rowAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $BindingRow -Label 'binding-row'
    if(-not [bool]$rowAuthority.ok){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$rowAuthority.reason) -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if(-not [bool]$BindingRow.active -or [bool]$BindingRow.user_removed -or [bool]$BindingRow.requires_reenrollment -or -not [bool]$BindingRow.update_observed -or [string]$BindingRow.last_status -cne 'remote-change-observed'){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-not-current-with-verified-remote-change' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if(([string]$BindingRow.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-source-does-not-match-provenance' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $lastSuccess=[DateTimeOffset]::MinValue
    if([string]::IsNullOrWhiteSpace([string]$BindingRow.last_success) -or -not [DateTimeOffset]::TryParse([string]$BindingRow.last_success,[ref]$lastSuccess)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-last-success-invalid' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($Now -lt $lastSuccess.AddMinutes(-5)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-last-success-in-future' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($Now -gt $lastSuccess.AddHours($MaxRemoteObservationAgeHours)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-remote-observation-stale' -Source $source -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}

    $localTree=([string]$BindingRow.last_local_tree_sha256).Trim().ToLowerInvariant();$remoteTree=([string]$BindingRow.last_remote_tree_sha256).Trim().ToLowerInvariant();$commit=([string]$BindingRow.last_remote_commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionSha256V010 $localTree) -or -not (Test-CustomAppPromotionSha256V010 $remoteTree) -or -not (Test-CustomAppPromotionCommitShaV010 $commit)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-runtime-identity-invalid' -Source $source -CurrentTree $localTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($localTree -ceq $remoteTree){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'no-pending-runtime-change' -Source $source -CurrentTree $localTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}

    $binding=$BindingRow.binding
    if($null -eq $binding -or [int]$binding.schema -ne 1 -or [string]$binding.managed_by -cne 'custom-app-remote-source-v1'){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'immutable-binding-owner-or-schema-mismatch' -Source $source -CurrentTree $localTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $bindingAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $binding -Label 'immutable-binding'
    if(-not [bool]$bindingAuthority.ok){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason ([string]$bindingAuthority.reason) -Source $source -CurrentTree $localTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if(([string]$binding.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'immutable-binding-source-mismatch' -Source $source -CurrentTree $localTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    try{$repoId=[int64]$binding.github_repo_id}catch{return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'immutable-binding-repo-id-invalid' -Source $source -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $surface=([string]$binding.surface_kind).Trim().ToLowerInvariant();$manifest=([string]$binding.manifest_name).Trim()
    if($repoId -le 0 -or $surface -notin @('repo-commit-root','release-asset') -or [string]$binding.layout_root -cne '.' -or [string]::IsNullOrWhiteSpace($manifest)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'immutable-binding-identity-invalid' -Source $source -RepoId $repoId -Surface $surface -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if(([string]$binding.last_verified_local_tree_sha256).Trim().ToLowerInvariant() -cne $localTree -or ([string]$binding.last_verified_remote_tree_sha256).Trim().ToLowerInvariant() -cne $remoteTree -or ([string]$binding.last_verified_commit_sha).Trim().ToLowerInvariant() -cne $commit){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'immutable-binding-runtime-continuity-drift' -Source $source -RepoId $repoId -Surface $surface -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($surface -ceq 'release-asset'){
        if([string]$binding.release_asset_selector -cne 'unique-zip-asset' -or [string]::IsNullOrWhiteSpace([string]$binding.asset_name) -or -not ([string]$binding.asset_name).EndsWith('.zip',[StringComparison]::OrdinalIgnoreCase)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'release-binding-selector-or-name-invalid' -Source $source -RepoId $repoId -Surface $surface -ProtocolFingerprint ([string]$protocol.fingerprint)}
        try{$assetId=[int64]$binding.last_observed_asset_id}catch{$assetId=0}
        if($assetId -le 0 -or -not (Test-CustomAppPromotionSha256V010 (([string]$binding.last_observed_asset_digest_sha256).Trim().ToLowerInvariant()))){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'release-binding-asset-id-or-digest-invalid' -Source $source -RepoId $repoId -Surface $surface -ProtocolFingerprint ([string]$protocol.fingerprint)}
    }
    $bindingFp=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow
    if(-not (Test-CustomAppPromotionSha256V010 $bindingFp)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'binding-fingerprint-invalid' -Source $source -RepoId $repoId -Surface $surface -ProtocolFingerprint ([string]$protocol.fingerprint)}

    if($null -eq $CurrentBaseline -or -not [bool]$CurrentBaseline.safe -or -not [bool]$CurrentBaseline.installable){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'current-runtime-baseline-not-safe-installable' -Source $source -RepoId $repoId -Surface $surface -BindingFingerprint $bindingFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    $currentTree=([string]$CurrentBaseline.tree_sha256).Trim().ToLowerInvariant();$currentManifest=([string]$CurrentBaseline.manifest_name).Trim()
    if(-not (Test-CustomAppPromotionSha256V010 $currentTree) -or $currentTree -cne $localTree -or $currentManifest -cne ([string]$BindingRow.last_local_manifest_name).Trim() -or $currentManifest -cne $manifest){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'current-runtime-drifted-since-binding-observation' -Source $source -RepoId $repoId -Surface $surface -CurrentTree $currentTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -BindingFingerprint $bindingFp -ProtocolFingerprint ([string]$protocol.fingerprint)}
    if($CurrentBaseline.PSObject.Properties['path'] -and -not [string]::IsNullOrWhiteSpace([string]$CurrentBaseline.path)){
        try{$baselinePath=[IO.Path]::GetFullPath([string]$CurrentBaseline.path)}catch{return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'current-runtime-path-invalid' -Source $source -ProtocolFingerprint ([string]$protocol.fingerprint)}
        if(-not $baselinePath.Equals($livePath,[StringComparison]::OrdinalIgnoreCase)){return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $false -Reason 'current-runtime-path-does-not-match-lifecycle' -Source $source -ProtocolFingerprint ([string]$protocol.fingerprint)}
    }

    $eligibilityMaterial=@($nameKey,$source,[string]$repoId,$surface,$manifest,$livePath,$currentTree,$remoteTree,$commit,$provFp,$bindingFp,[string]$protocol.fingerprint,[string]$BindingRow.last_success) -join "`n"
    $eligibilityFp=Get-CustomAppPromotionStringSha256V010 -Text $eligibilityMaterial
    return New-CustomAppPromotionDecisionV010 -Name $Name -Eligible $true -Reason 'all-current-evidence-and-shadow-protocol-qualified' -Source $source -RepoId $repoId -Surface $surface -CurrentTree $currentTree -RemoteTree $remoteTree -RemoteCommit $commit -ProvenanceFingerprint $provFp -BindingFingerprint $bindingFp -ProtocolFingerprint ([string]$protocol.fingerprint) -EligibilityFingerprint $eligibilityFp
}
