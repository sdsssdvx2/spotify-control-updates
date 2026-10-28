$CustomAppProductionPromotionGateSchema = 1
$CustomAppProductionPromotionGateManagedBy = 'custom-app-production-promotion-gate-v1'

function Test-CustomAppPromotionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppPromotionCommitShaV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Get-CustomAppPromotionStringSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
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

function New-CustomAppProductionPromotionDecisionV010 {
    param([bool]$Eligible,[string]$Reason,[AllowNull()]$Evidence=$null)
    $fingerprint=$null
    if($null -ne $Evidence){
        $material=@(
            [string]$Evidence.name,[string]$Evidence.source_identity,[string]$Evidence.github_repo_id,[string]$Evidence.surface_kind,
            [string]$Evidence.local_tree_sha256,[string]$Evidence.remote_tree_sha256,[string]$Evidence.remote_commit_sha,
            [string]$Evidence.manifest_name,[string]$Evidence.provenance_fingerprint,[string]$Evidence.binding_fingerprint,
            [string]$Evidence.persistence_fingerprint,[string]$Evidence.shadow_transaction_id,[string]$Evidence.remote_observed_at
        ) -join "`n"
        $fingerprint=Get-CustomAppPromotionStringSha256V010 -Text $material
    }
    return [pscustomobject]@{
        schema=$CustomAppProductionPromotionGateSchema
        managed_by=$CustomAppProductionPromotionGateManagedBy
        eligible_for_production_promotion=$Eligible
        status=$(if($Eligible){'eligible-to-propose-production-promotion'}else{'production-promotion-denied'})
        reason=$Reason
        evidence=$Evidence
        decision_fingerprint=$fingerprint
        promotion_decision_only=$true
        promotion_token_issued=$false
        mutation_mode='deny'
        mutation_authorized=$false
        auto_update_authorized=$false
        auto_install_authorized=$false
        production_mutation_authorized=$false
    }
}

function Resolve-CustomAppProductionPromotionEligibilityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$StageResult,
        [Parameter(Mandatory=$true)]$ShadowResult
    )

    if([string]::IsNullOrWhiteSpace($Name)){return New-CustomAppProductionPromotionDecisionV010 $false 'name-empty'}
    $nameKey=$Name.Trim().ToLowerInvariant()

    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or [string]$LifecycleRow.kind -cne 'custom-app'){
        return New-CustomAppProductionPromotionDecisionV010 $false 'lifecycle-owner-or-kind-mismatch'
    }
    if($LifecycleRow.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$LifecycleRow.name) -and ([string]$LifecycleRow.name).Trim().ToLowerInvariant() -cne $nameKey){return New-CustomAppProductionPromotionDecisionV010 $false 'lifecycle-name-mismatch'}
    if(-not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed){return New-CustomAppProductionPromotionDecisionV010 $false 'lifecycle-user-removed-or-absent'}
    if([bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$LifecycleRow.locations[0])){return New-CustomAppProductionPromotionDecisionV010 $false 'lifecycle-not-current-safe-single-path'}
    if($LifecycleRow.PSObject.Properties['mutation_mode']){
        $lifecycleAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $LifecycleRow -Label 'lifecycle-row'
        if(-not [bool]$lifecycleAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$lifecycleAuthority.reason)}
    }

    $provAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $ProvenanceRow -Label 'provenance-row'
    if(-not [bool]$provAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$provAuthority.reason)}
    if([string]$ProvenanceRow.managed_by -cne 'custom-app-provenance-v1'){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-owner-mismatch'}
    if($ProvenanceRow.PSObject.Properties['name'] -and ([string]$ProvenanceRow.name).Trim().ToLowerInvariant() -cne $nameKey){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-name-mismatch'}
    $source=([string]$ProvenanceRow.source_identity).Trim().ToLowerInvariant()
    if($source -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$'){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-source-invalid'}
    if(([string]$ProvenanceRow.last_proven_source).Trim().ToLowerInvariant() -cne $source -or [bool]$ProvenanceRow.source_changed -or [bool]$ProvenanceRow.requires_reenrollment){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-not-current-or-reenrollment-required'}
    if($ProvenanceRow.PSObject.Properties['observed_source_candidate'] -and -not [string]::IsNullOrWhiteSpace([string]$ProvenanceRow.observed_source_candidate) -and ([string]$ProvenanceRow.observed_source_candidate).Trim().ToLowerInvariant() -cne $source){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-observed-candidate-drift'}
    if(([string]$ProvenanceRow.source_status) -notlike 'proven-local-git-origin*'){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-not-strong-local-git-proof'}
    $provenanceFingerprint=([string]$ProvenanceRow.evidence_fingerprint).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionSha256V010 $provenanceFingerprint)){return New-CustomAppProductionPromotionDecisionV010 $false 'provenance-fingerprint-invalid'}

    $bindingAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $BindingRow -Label 'binding-row'
    if(-not [bool]$bindingAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$bindingAuthority.reason)}
    if([int]$BindingRow.schema -ne 1 -or [string]$BindingRow.managed_by -cne 'custom-app-remote-binding-observer-v1'){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-owner-or-schema-mismatch'}
    if(([string]$BindingRow.name).Trim().ToLowerInvariant() -cne $nameKey){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-name-mismatch'}
    if(-not [bool]$BindingRow.active -or [bool]$BindingRow.user_removed -or [bool]$BindingRow.requires_reenrollment){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-not-active-current'}
    if(-not [bool]$BindingRow.update_observed -or [string]$BindingRow.last_status -cne 'remote-change-observed'){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-no-current-remote-change'}
    $remoteObservedAt=[DateTimeOffset]::MinValue
    if([string]::IsNullOrWhiteSpace([string]$BindingRow.last_success) -or -not [DateTimeOffset]::TryParse([string]$BindingRow.last_success,[ref]$remoteObservedAt)){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-last-success-invalid'}
    if(([string]$BindingRow.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-source-does-not-match-provenance'}
    $localTree=([string]$BindingRow.last_local_tree_sha256).Trim().ToLowerInvariant()
    $remoteTree=([string]$BindingRow.last_remote_tree_sha256).Trim().ToLowerInvariant()
    $remoteCommit=([string]$BindingRow.last_remote_commit_sha).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionSha256V010 $localTree) -or -not (Test-CustomAppPromotionSha256V010 $remoteTree) -or -not (Test-CustomAppPromotionCommitShaV010 $remoteCommit)){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-local-or-remote-identity-invalid'}
    if($localTree -ceq $remoteTree){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-does-not-represent-a-new-remote-tree'}

    $binding=$BindingRow.binding
    $immutableAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $binding -Label 'immutable-binding'
    if(-not [bool]$immutableAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$immutableAuthority.reason)}
    if([int]$binding.schema -ne 1 -or [string]$binding.managed_by -cne 'custom-app-remote-source-v1'){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-owner-or-schema-mismatch'}
    if(([string]$binding.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-source-mismatch'}
    try{$repoId=[int64]$binding.github_repo_id}catch{return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-repo-id-invalid'}
    if($repoId -le 0){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-repo-id-invalid'}
    $surface=([string]$binding.surface_kind).Trim().ToLowerInvariant()
    if($surface -notin @('repo-commit-root','release-asset') -or [string]$binding.layout_root -cne '.'){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-surface-or-layout-invalid'}
    $manifest=([string]$binding.manifest_name).Trim()
    if([string]::IsNullOrWhiteSpace($manifest) -or $manifest.Length -gt 256){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-manifest-invalid'}
    if(([string]$BindingRow.last_local_manifest_name).Trim() -cne $manifest){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-local-manifest-continuity-drift'}
    if(([string]$binding.last_verified_local_tree_sha256).Trim().ToLowerInvariant() -cne $localTree){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-local-tree-continuity-drift'}
    if(([string]$binding.last_verified_remote_tree_sha256).Trim().ToLowerInvariant() -cne $remoteTree -or ([string]$binding.last_verified_commit_sha).Trim().ToLowerInvariant() -cne $remoteCommit){return New-CustomAppProductionPromotionDecisionV010 $false 'immutable-binding-remote-continuity-drift'}
    if($surface -ceq 'release-asset'){
        if([string]$binding.release_asset_selector -cne 'unique-zip-asset'){return New-CustomAppProductionPromotionDecisionV010 $false 'release-selector-invalid'}
        $assetName=([string]$binding.asset_name).Trim();if([string]::IsNullOrWhiteSpace($assetName) -or -not $assetName.EndsWith('.zip',[StringComparison]::OrdinalIgnoreCase)){return New-CustomAppProductionPromotionDecisionV010 $false 'release-asset-name-invalid'}
        try{$assetId=[int64]$binding.last_observed_asset_id}catch{return New-CustomAppProductionPromotionDecisionV010 $false 'release-asset-id-invalid'}
        if($assetId -le 0 -or -not (Test-CustomAppPromotionSha256V010 (([string]$binding.last_observed_asset_digest_sha256).Trim().ToLowerInvariant()))){return New-CustomAppProductionPromotionDecisionV010 $false 'release-asset-id-or-digest-invalid'}
    }
    $bindingFingerprint=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow
    if(-not (Test-CustomAppPromotionSha256V010 $bindingFingerprint)){return New-CustomAppProductionPromotionDecisionV010 $false 'binding-fingerprint-invalid'}

    $stageAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $StageResult -Label 'stage-result'
    if(-not [bool]$stageAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$stageAuthority.reason)}
    if([string]$StageResult.status -cne 'staged-verified'){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-not-verified'}
    if(([string]$StageResult.source_identity).Trim().ToLowerInvariant() -cne $source){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-source-mismatch'}
    if(([string]$StageResult.remote_tree_sha256).Trim().ToLowerInvariant() -cne $remoteTree -or ([string]$StageResult.commit_sha).Trim().ToLowerInvariant() -cne $remoteCommit){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-remote-identity-drift'}
    if(([string]$StageResult.binding_fingerprint).Trim().ToLowerInvariant() -cne $bindingFingerprint){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-binding-fingerprint-drift'}
    if($null -eq $StageResult.stage_baseline -or -not [bool]$StageResult.stage_baseline.safe -or -not [bool]$StageResult.stage_baseline.installable){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-baseline-not-safe-installable'}
    if(([string]$StageResult.stage_baseline.tree_sha256).Trim().ToLowerInvariant() -cne $remoteTree -or ([string]$StageResult.stage_baseline.manifest_name).Trim() -cne $manifest){return New-CustomAppProductionPromotionDecisionV010 $false 'stage-baseline-identity-drift'}

    $shadowAuthority=Test-CustomAppPromotionStrictDeniedAuthorityV010 -Object $ShadowResult -Label 'shadow-result'
    if(-not [bool]$shadowAuthority.ok){return New-CustomAppProductionPromotionDecisionV010 $false ([string]$shadowAuthority.reason)}
    if([int]$ShadowResult.schema -ne 1 -or [string]$ShadowResult.managed_by -cne 'custom-app-shadow-executor-v1'){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-owner-or-schema-mismatch'}
    if(([string]$ShadowResult.name).Trim().ToLowerInvariant() -cne $nameKey){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-name-mismatch'}
    if([string]$ShadowResult.status -cne 'committed-shadow-fixture' -or [string]$ShadowResult.reason -cne 'fresh-provenance-stage-transaction-persistence-all-verified' -or -not [bool]$ShadowResult.committed -or [bool]$ShadowResult.rolled_back){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-not-clean-committed-proof'}
    if(([string]$ShadowResult.fresh_provenance_fingerprint).Trim().ToLowerInvariant() -cne $provenanceFingerprint){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-provenance-fingerprint-drift'}
    if(([string]$ShadowResult.binding_fingerprint).Trim().ToLowerInvariant() -cne $bindingFingerprint){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-binding-fingerprint-drift'}
    if(([string]$ShadowResult.stage_tree_sha256).Trim().ToLowerInvariant() -cne $remoteTree){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-stage-tree-drift'}
    if([string]::IsNullOrWhiteSpace([string]$ShadowResult.transaction_id)){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-transaction-id-missing'}
    $prePersistence=([string]$ShadowResult.pre_persistence_fingerprint).Trim().ToLowerInvariant();$postPersistence=([string]$ShadowResult.post_persistence_fingerprint).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppPromotionSha256V010 $prePersistence) -or -not (Test-CustomAppPromotionSha256V010 $postPersistence)){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-persistence-fingerprint-invalid'}
    if($prePersistence -cne $postPersistence){return New-CustomAppProductionPromotionDecisionV010 $false 'shadow-persistence-byte-fingerprint-drift'}

    $evidence=[pscustomobject]@{
        name=$Name;source_identity=$source;github_repo_id=$repoId;surface_kind=$surface
        local_tree_sha256=$localTree;remote_tree_sha256=$remoteTree;remote_commit_sha=$remoteCommit;manifest_name=$manifest
        provenance_fingerprint=$provenanceFingerprint;binding_fingerprint=$bindingFingerprint;persistence_fingerprint=$prePersistence
        shadow_transaction_id=[string]$ShadowResult.transaction_id;remote_observed_at=[string]$BindingRow.last_success
    }
    return New-CustomAppProductionPromotionDecisionV010 $true 'shadow-protocol-evidence-complete-read-only-promotion-eligibility' $evidence
}
