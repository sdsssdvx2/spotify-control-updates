$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-promotion-eligibility.ps1')

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

function Assert-False {
    param([bool]$Condition,[string]$Message)
    if($Condition){throw $Message}
}

function Copy-Fixture {
    param([Parameter(Mandatory=$true)]$Object)
    return ($Object | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Assert-AuthorityRemainsDenied {
    param([Parameter(Mandatory=$true)]$Decision,[string]$Label)
    Assert-True ($Decision.PSObject.Properties['promotion_candidate_eligible'] -ne $null) "$Label missing promotion_candidate_eligible"
    Assert-True ($Decision.PSObject.Properties['requires_revalidation_before_any_mutation'] -ne $null) "$Label missing requires_revalidation_before_any_mutation"
    Assert-True ([bool]$Decision.requires_revalidation_before_any_mutation) "$Label did not require revalidation before mutation"
    Assert-True ([string]$Decision.mutation_mode -ceq 'deny') "$Label mutation_mode drifted"
    Assert-False ([bool]$Decision.mutation_authorized) "$Label granted mutation_authorized"
    Assert-False ([bool]$Decision.auto_update_authorized) "$Label granted auto_update_authorized"
    Assert-False ([bool]$Decision.auto_install_authorized) "$Label granted auto_install_authorized"
    Assert-False ([bool]$Decision.canary_execution_authorized) "$Label granted canary_execution_authorized"
    Assert-False ([bool]$Decision.production_mutation_authorized) "$Label granted production_mutation_authorized"
}

function New-ValidPromotionFixture {
    $name='tagify'
    $source='alexk218/tagify'
    $path='C:\fixture\CustomApps\tagify'
    $localTree=('1'*64)
    $remoteTree=('2'*64)
    $provFp=('3'*64)
    $assetDigest=('4'*64)
    $commit=('a'*40)
    $observed='2026-10-28T10:30:00+00:00'

    $lifecycle=[pscustomobject]@{
        schema=1;managed_by='dynamic-spicetify-v1';kind='custom-app';name=$name;present=$true;user_removed=$false
        ambiguous=$false;safe_local_identity=$true;locations=@($path);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $provenance=[pscustomobject]@{
        schema=1;managed_by='custom-app-provenance-v1';name=$name;source_identity=$source;last_proven_source=$source
        source_changed=$false;requires_reenrollment=$false;evidence_fingerprint=$provFp
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $immutable=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity=$source;github_repo_id=[int64]987654321
        surface_kind='release-asset';layout_root='.';manifest_name='Tagify';last_verified_local_tree_sha256=$localTree
        last_verified_remote_tree_sha256=$remoteTree;last_verified_commit_sha=$commit;release_asset_selector='unique-zip-asset'
        asset_name='tagify-v3.3.2.zip';last_observed_asset_id=[int64]418974188;last_observed_asset_digest_sha256=$assetDigest
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name=$name;active=$true;source_identity=$source;binding=$immutable
        last_success=$observed;last_status='remote-change-observed';last_reason='verified-remote-runtime-change';last_error=$null
        last_local_tree_sha256=$localTree;last_local_manifest_name='Tagify';last_remote_tree_sha256=$remoteTree;last_remote_commit_sha=$commit
        update_observed=$true;requires_reenrollment=$false;user_removed=$false
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=$localTree;manifest_name='Tagify';path=$path}
    $qualification=[pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-protocol-qualification-v1'
        validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead
        production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256
        spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256;push_success=$true;pull_request_success=$true
        offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true
        push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId
        push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId
        push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false;canary_execution_authorized=$false
    }
    return [pscustomobject]@{name=$name;lifecycle=$lifecycle;provenance=$provenance;binding=$binding;baseline=$baseline;qualification=$qualification}
}

$now=[DateTimeOffset]::Parse('2026-10-28T10:40:00+00:00')
$base=New-ValidPromotionFixture
$valid=Resolve-CustomAppPromotionEligibilityV010 -Name $base.name -LifecycleRow $base.lifecycle -ProvenanceRow $base.provenance -BindingRow $base.binding -CurrentBaseline $base.baseline -ProtocolQualification $base.qualification -Now $now
Assert-True ([bool]$valid.promotion_candidate_eligible) ('valid fixture denied: '+[string]$valid.reason)
Assert-True ([string]$valid.reason -ceq 'all-current-evidence-and-shadow-protocol-qualified') 'valid fixture reason drifted'
Assert-True (Test-CustomAppPromotionSha256V010 ([string]$valid.eligibility_fingerprint)) 'valid eligibility fingerprint invalid'
Assert-True (Test-CustomAppPromotionSha256V010 ([string]$valid.binding_fingerprint)) 'valid binding fingerprint invalid'
Assert-True (Test-CustomAppPromotionSha256V010 ([string]$valid.protocol_qualification_fingerprint)) 'valid protocol fingerprint invalid'
Assert-AuthorityRemainsDenied -Decision $valid -Label 'valid-decision'
$valid2=Resolve-CustomAppPromotionEligibilityV010 -Name $base.name -LifecycleRow $base.lifecycle -ProvenanceRow $base.provenance -BindingRow $base.binding -CurrentBaseline $base.baseline -ProtocolQualification $base.qualification -Now $now
Assert-True ([string]$valid2.eligibility_fingerprint -ceq [string]$valid.eligibility_fingerprint) 'eligibility fingerprint was not deterministic'

$cases=New-Object System.Collections.Generic.List[object]
function Add-DenialCase {
    param([string]$Label,[scriptblock]$Mutate,[string]$ExpectedReason)
    $fixture=New-ValidPromotionFixture
    & $Mutate $fixture
    $cases.Add([pscustomobject]@{label=$Label;fixture=$fixture;reason=$ExpectedReason})
}

Add-DenialCase 'protocol-shadow-head-mismatch' {param($f)$f.qualification.validated_shadow_head=('b'*40)} 'qualified-shadow-head-mismatch'
Add-DenialCase 'protocol-stage-head-mismatch' {param($f)$f.qualification.validated_stage_parent=('c'*40)} 'qualified-stage-head-mismatch'
Add-DenialCase 'protocol-main-mismatch' {param($f)$f.qualification.production_main=('d'*40)} 'qualified-production-main-mismatch'
Add-DenialCase 'protocol-addon-identity-mismatch' {param($f)$f.qualification.addon_manager_sha256=('5'*64)} 'qualified-parent-binary-identity-mismatch'
Add-DenialCase 'protocol-push-run-mismatch' {param($f)$f.qualification.push_run_id=[int64]1} 'qualified-run-identity-mismatch'
Add-DenialCase 'protocol-pr-artifact-mismatch' {param($f)$f.qualification.pull_request_artifact_id=[int64]1} 'qualified-artifact-identity-mismatch'
Add-DenialCase 'protocol-artifact-digest-mismatch' {param($f)$f.qualification.push_artifact_digest=('sha256:'+('6'*64))} 'qualified-artifact-digest-mismatch'
Add-DenialCase 'protocol-matrix-incomplete' {param($f)$f.qualification.offline_matrix_passed=$false} 'qualified-shadow-evidence-incomplete'
Add-DenialCase 'protocol-authority-drift' {param($f)$f.qualification.auto_update_authorized=$true} 'protocol-qualification-auto-authority-true'
Add-DenialCase 'lifecycle-user-removed' {param($f)$f.lifecycle.user_removed=$true;$f.lifecycle.present=$false} 'lifecycle-not-current-safe-single-path'
Add-DenialCase 'lifecycle-ambiguous' {param($f)$f.lifecycle.ambiguous=$true} 'lifecycle-not-current-safe-single-path'
Add-DenialCase 'lifecycle-multi-location' {param($f)$f.lifecycle.locations=@('C:\fixture\CustomApps\tagify','C:\fixture\Other\tagify')} 'lifecycle-not-current-safe-single-path'
Add-DenialCase 'lifecycle-name-mismatch' {param($f)$f.lifecycle.name='other'} 'lifecycle-name-mismatch'
Add-DenialCase 'provenance-source-changed' {param($f)$f.provenance.source_changed=$true} 'provenance-not-current-strong'
Add-DenialCase 'provenance-reenrollment' {param($f)$f.provenance.requires_reenrollment=$true} 'provenance-not-current-strong'
Add-DenialCase 'provenance-fingerprint-invalid' {param($f)$f.provenance.evidence_fingerprint='bad'} 'provenance-not-current-strong'
Add-DenialCase 'provenance-authority-drift' {param($f)$f.provenance.mutation_mode='auto'} 'provenance-row-mutation-mode-not-deny'
Add-DenialCase 'binding-inactive' {param($f)$f.binding.active=$false} 'binding-not-current-with-verified-remote-change'
Add-DenialCase 'binding-no-update-observed' {param($f)$f.binding.update_observed=$false} 'binding-not-current-with-verified-remote-change'
Add-DenialCase 'binding-status-wrong' {param($f)$f.binding.last_status='no-change'} 'binding-not-current-with-verified-remote-change'
Add-DenialCase 'binding-source-mismatch' {param($f)$f.binding.source_identity='owner/other'} 'binding-source-does-not-match-provenance'
Add-DenialCase 'binding-observation-stale' {param($f)$f.binding.last_success='2026-10-26T00:00:00+00:00'} 'binding-remote-observation-stale'
Add-DenialCase 'binding-observation-future' {param($f)$f.binding.last_success='2026-10-28T11:00:01+00:00'} 'binding-last-success-in-future'
Add-DenialCase 'binding-invalid-repo-id' {param($f)$f.binding.binding.github_repo_id=[int64]0} 'immutable-binding-identity-invalid'
Add-DenialCase 'binding-inner-source-mismatch' {param($f)$f.binding.binding.source_identity='owner/other'} 'immutable-binding-source-mismatch'
Add-DenialCase 'binding-inner-remote-tree-drift' {param($f)$f.binding.binding.last_verified_remote_tree_sha256=('7'*64)} 'immutable-binding-runtime-continuity-drift'
Add-DenialCase 'binding-release-selector-invalid' {param($f)$f.binding.binding.release_asset_selector='filename-regex'} 'release-binding-selector-or-name-invalid'
Add-DenialCase 'binding-release-digest-invalid' {param($f)$f.binding.binding.last_observed_asset_digest_sha256='bad'} 'release-binding-asset-id-or-digest-invalid'
Add-DenialCase 'binding-authority-drift' {param($f)$f.binding.auto_install_authorized=$true} 'binding-row-auto-authority-true'
Add-DenialCase 'current-baseline-unsafe' {param($f)$f.baseline.safe=$false} 'current-runtime-baseline-not-safe-installable'
Add-DenialCase 'current-tree-drift' {param($f)$f.baseline.tree_sha256=('8'*64)} 'current-runtime-drifted-since-binding-observation'
Add-DenialCase 'current-manifest-drift' {param($f)$f.baseline.manifest_name='Wrong'} 'current-runtime-drifted-since-binding-observation'
Add-DenialCase 'current-path-drift' {param($f)$f.baseline.path='C:\fixture\CustomApps\other'} 'current-runtime-path-does-not-match-lifecycle'
Add-DenialCase 'no-pending-runtime-change' {param($f)$f.binding.last_remote_tree_sha256=$f.binding.last_local_tree_sha256;$f.binding.binding.last_verified_remote_tree_sha256=$f.binding.last_local_tree_sha256} 'no-pending-runtime-change'

$count=0
foreach($case in $cases){
    $f=$case.fixture
    $decision=Resolve-CustomAppPromotionEligibilityV010 -Name $f.name -LifecycleRow $f.lifecycle -ProvenanceRow $f.provenance -BindingRow $f.binding -CurrentBaseline $f.baseline -ProtocolQualification $f.qualification -Now $now
    Assert-False ([bool]$decision.promotion_candidate_eligible) ($case.label+' unexpectedly eligible')
    Assert-True ([string]$decision.reason -ceq [string]$case.reason) ($case.label+' reason drifted: '+[string]$decision.reason+' != '+[string]$case.reason)
    Assert-AuthorityRemainsDenied -Decision $decision -Label $case.label
    $count++
}

$ageInvalid=Resolve-CustomAppPromotionEligibilityV010 -Name $base.name -LifecycleRow $base.lifecycle -ProvenanceRow $base.provenance -BindingRow $base.binding -CurrentBaseline $base.baseline -ProtocolQualification $base.qualification -Now $now -MaxRemoteObservationAgeHours 0
Assert-False ([bool]$ageInvalid.promotion_candidate_eligible) 'invalid observation-age policy unexpectedly eligible'
Assert-True ([string]$ageInvalid.reason -ceq 'remote-observation-age-policy-invalid') 'invalid observation-age policy reason drifted'
Assert-AuthorityRemainsDenied -Decision $ageInvalid -Label 'invalid-age-policy'
$count++

$emptyName=Resolve-CustomAppPromotionEligibilityV010 -Name ' ' -LifecycleRow $base.lifecycle -ProvenanceRow $base.provenance -BindingRow $base.binding -CurrentBaseline $base.baseline -ProtocolQualification $base.qualification -Now $now
Assert-False ([bool]$emptyName.promotion_candidate_eligible) 'empty name unexpectedly eligible'
Assert-True ([string]$emptyName.reason -ceq 'name-empty') 'empty name reason drifted'
Assert-AuthorityRemainsDenied -Decision $emptyName -Label 'empty-name'
$count++

Write-Host ('CUSTOM_APP_PROMOTION_ELIGIBILITY_MATRIX_PASS eligible=1 denied='+$count+' total='+($count+1))
