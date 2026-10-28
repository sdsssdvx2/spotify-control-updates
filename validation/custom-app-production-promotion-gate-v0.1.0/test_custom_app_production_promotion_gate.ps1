$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'custom-app-production-promotion-gate.ps1')

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw $Message}
}

function Assert-False {
    param([bool]$Condition,[string]$Message)
    if($Condition){throw $Message}
}

function Copy-FixtureObject {
    param([Parameter(Mandatory=$true)]$Object)
    return ($Object | ConvertTo-Json -Depth 50 | ConvertFrom-Json)
}

function New-ValidPromotionBundle {
    $localTree=('1'*64)
    $remoteTree=('2'*64)
    $commit=('3'*40)
    $assetDigest=('4'*64)
    $persistence=('5'*64)
    $provenanceFingerprint=('6'*64)

    $lifecycle=[pscustomobject]@{
        schema=1;managed_by='dynamic-spicetify-v1';kind='custom-app';name='tagify';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true
        locations=@('C:\fixture\CustomApps\tagify');mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    $provenance=[pscustomobject]@{
        schema=1;managed_by='custom-app-provenance-v1';name='tagify';source_identity='alexk218/tagify';last_proven_source='alexk218/tagify';observed_source_candidate='alexk218/tagify'
        source_status='proven-local-git-origin-corroborated';evidence_fingerprint=$provenanceFingerprint;source_changed=$false;requires_reenrollment=$false
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $immutable=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity='alexk218/tagify';github_repo_id=[int64]1021838879;surface_kind='release-asset';layout_root='.';manifest_name='tagify'
        last_verified_local_tree_sha256=$localTree;last_verified_remote_tree_sha256=$remoteTree;last_verified_commit_sha=$commit
        release_asset_selector='unique-zip-asset';asset_name='tagify.zip';last_observed_asset_id=[int64]660754674;last_observed_asset_digest_sha256=$assetDigest
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name='tagify';active=$true;source_identity='alexk218/tagify';binding=$immutable
        last_success='2026-10-28T10:30:00+00:00';last_status='remote-change-observed';last_local_tree_sha256=$localTree;last_local_manifest_name='tagify'
        last_remote_tree_sha256=$remoteTree;last_remote_commit_sha=$commit;update_observed=$true;requires_reenrollment=$false;user_removed=$false
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $bindingFingerprint=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $binding
    $stage=[pscustomobject]@{
        schema=1;managed_by='custom-app-stage-acquisition-v1';status='staged-verified';source_identity='alexk218/tagify';remote_tree_sha256=$remoteTree;commit_sha=$commit;binding_fingerprint=$bindingFingerprint
        stage_baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=$remoteTree;manifest_name='tagify'}
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $shadow=[pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-executor-v1';name='tagify';status='committed-shadow-fixture';reason='fresh-provenance-stage-transaction-persistence-all-verified'
        committed=$true;rolled_back=$false;fresh_provenance_fingerprint=$provenanceFingerprint;binding_fingerprint=$bindingFingerprint;stage_tree_sha256=$remoteTree
        transaction_id='tx-fixture-001';pre_persistence_fingerprint=$persistence;post_persistence_fingerprint=$persistence
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    return [pscustomobject]@{lifecycle=$lifecycle;provenance=$provenance;binding=$binding;stage=$stage;shadow=$shadow}
}

function Sync-PromotionBundleFingerprints {
    param([Parameter(Mandatory=$true)]$Bundle)
    $fp=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $Bundle.binding
    $Bundle.stage.binding_fingerprint=$fp
    $Bundle.shadow.binding_fingerprint=$fp
    $Bundle.stage.remote_tree_sha256=[string]$Bundle.binding.last_remote_tree_sha256
    $Bundle.stage.commit_sha=[string]$Bundle.binding.last_remote_commit_sha
    $Bundle.stage.stage_baseline.tree_sha256=[string]$Bundle.binding.last_remote_tree_sha256
    $Bundle.stage.stage_baseline.manifest_name=[string]$Bundle.binding.binding.manifest_name
    $Bundle.shadow.stage_tree_sha256=[string]$Bundle.binding.last_remote_tree_sha256
    return $Bundle
}

function Resolve-Bundle {
    param([Parameter(Mandatory=$true)]$Bundle)
    return Resolve-CustomAppProductionPromotionEligibilityV010 -Name 'tagify' -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow
}

function Assert-DeniedAndAuthorityClosed {
    param([Parameter(Mandatory=$true)]$Decision,[string]$Label)
    Assert-False ([bool]$Decision.eligible_for_production_promotion) "$Label unexpectedly became promotion-eligible."
    Assert-True ([string]$Decision.status -ceq 'production-promotion-denied') "$Label returned wrong denial status."
    Assert-True ([bool]$Decision.promotion_decision_only) "$Label lost decision-only marker."
    Assert-False ([bool]$Decision.promotion_token_issued) "$Label issued a promotion token."
    Assert-True ([string]$Decision.mutation_mode -ceq 'deny') "$Label changed mutation_mode."
    Assert-False ([bool]$Decision.mutation_authorized) "$Label granted mutation authority."
    Assert-False ([bool]$Decision.auto_update_authorized) "$Label granted auto-update authority."
    Assert-False ([bool]$Decision.auto_install_authorized) "$Label granted auto-install authority."
    Assert-False ([bool]$Decision.production_mutation_authorized) "$Label granted production mutation authority."
}

$valid=New-ValidPromotionBundle
$d1=Resolve-Bundle $valid
Assert-True ([bool]$d1.eligible_for_production_promotion) 'Valid complete proof was not promotion-eligible.'
Assert-True ([string]$d1.status -ceq 'eligible-to-propose-production-promotion') 'Valid proof returned wrong status.'
Assert-True ([string]$d1.reason -ceq 'shadow-protocol-evidence-complete-read-only-promotion-eligibility') 'Valid proof returned wrong reason.'
Assert-True ([bool]$d1.promotion_decision_only) 'Valid decision is not decision-only.'
Assert-False ([bool]$d1.promotion_token_issued) 'Valid decision issued a promotion token.'
Assert-True ([string]$d1.mutation_mode -ceq 'deny') 'Eligible decision changed mutation mode.'
Assert-False ([bool]$d1.mutation_authorized) 'Eligible decision granted mutation authority.'
Assert-False ([bool]$d1.auto_update_authorized) 'Eligible decision granted auto-update authority.'
Assert-False ([bool]$d1.auto_install_authorized) 'Eligible decision granted auto-install authority.'
Assert-False ([bool]$d1.production_mutation_authorized) 'Eligible decision granted production mutation authority.'
Assert-True (Test-CustomAppPromotionSha256V010 ([string]$d1.decision_fingerprint)) 'Eligible decision fingerprint is invalid.'
$d2=Resolve-Bundle (Copy-FixtureObject $valid)
Assert-True ([string]$d1.decision_fingerprint -ceq [string]$d2.decision_fingerprint) 'Promotion decision fingerprint is not deterministic.'

$repoRoot=Copy-FixtureObject $valid
$repoRoot.binding.binding.surface_kind='repo-commit-root'
$repoRoot.binding.binding.release_asset_selector=$null
$repoRoot.binding.binding.asset_name=$null
$repoRoot.binding.binding.last_observed_asset_id=$null
$repoRoot.binding.binding.last_observed_asset_digest_sha256=$null
[void](Sync-PromotionBundleFingerprints $repoRoot)
Assert-True ([bool](Resolve-Bundle $repoRoot).eligible_for_production_promotion) 'Valid repo-commit-root proof was denied.'

$cases=New-Object System.Collections.Generic.List[object]
function Add-DenialCase {
    param([string]$Name,[scriptblock]$Mutate)
    $b=Copy-FixtureObject (New-ValidPromotionBundle)
    & $Mutate $b
    $cases.Add([pscustomobject]@{name=$Name;bundle=$b})
}

Add-DenialCase 'lifecycle-absent' {param($b)$b.lifecycle.present=$false}
Add-DenialCase 'lifecycle-user-removed' {param($b)$b.lifecycle.user_removed=$true}
Add-DenialCase 'lifecycle-ambiguous' {param($b)$b.lifecycle.ambiguous=$true}
Add-DenialCase 'lifecycle-unsafe' {param($b)$b.lifecycle.safe_local_identity=$false}
Add-DenialCase 'lifecycle-multiple-paths' {param($b)$b.lifecycle.locations=@('C:\a','C:\b')}
Add-DenialCase 'lifecycle-authority-drift' {param($b)$b.lifecycle.mutation_mode='auto'}
Add-DenialCase 'provenance-authority-drift' {param($b)$b.provenance.auto_update_authorized=$true}
Add-DenialCase 'provenance-source-changed' {param($b)$b.provenance.source_changed=$true}
Add-DenialCase 'provenance-reenrollment-required' {param($b)$b.provenance.requires_reenrollment=$true}
Add-DenialCase 'provenance-package-only' {param($b)$b.provenance.source_status='declared-package-only'}
Add-DenialCase 'provenance-candidate-drift' {param($b)$b.provenance.observed_source_candidate='other/repo'}
Add-DenialCase 'provenance-fingerprint-invalid' {param($b)$b.provenance.evidence_fingerprint='bad'}
Add-DenialCase 'binding-inactive' {param($b)$b.binding.active=$false}
Add-DenialCase 'binding-user-removed' {param($b)$b.binding.user_removed=$true}
Add-DenialCase 'binding-reenrollment-required' {param($b)$b.binding.requires_reenrollment=$true}
Add-DenialCase 'binding-no-update' {param($b)$b.binding.update_observed=$false}
Add-DenialCase 'binding-status-drift' {param($b)$b.binding.last_status='binding-enrolled'}
Add-DenialCase 'binding-time-invalid' {param($b)$b.binding.last_success='not-a-time'}
Add-DenialCase 'binding-source-drift' {param($b)$b.binding.source_identity='other/repo'}
Add-DenialCase 'binding-local-equals-remote' {param($b)$b.binding.last_local_tree_sha256=$b.binding.last_remote_tree_sha256;$b.binding.binding.last_verified_local_tree_sha256=$b.binding.last_remote_tree_sha256;[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'immutable-binding-authority-drift' {param($b)$b.binding.binding.auto_install_authorized=$true}
Add-DenialCase 'immutable-binding-repo-id-invalid' {param($b)$b.binding.binding.github_repo_id=0;[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'immutable-binding-surface-invalid' {param($b)$b.binding.binding.surface_kind='mystery';[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'release-asset-digest-invalid' {param($b)$b.binding.binding.last_observed_asset_digest_sha256='bad';[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'binding-local-tree-continuity-drift' {param($b)$b.binding.binding.last_verified_local_tree_sha256=('7'*64);[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'binding-remote-tree-continuity-drift' {param($b)$b.binding.binding.last_verified_remote_tree_sha256=('7'*64);[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'binding-commit-continuity-drift' {param($b)$b.binding.binding.last_verified_commit_sha=('7'*40);[void](Sync-PromotionBundleFingerprints $b)}
Add-DenialCase 'stage-authority-drift' {param($b)$b.stage.production_mutation_authorized=$true}
Add-DenialCase 'stage-status-drift' {param($b)$b.stage.status='downloaded'}
Add-DenialCase 'stage-source-drift' {param($b)$b.stage.source_identity='other/repo'}
Add-DenialCase 'stage-tree-drift' {param($b)$b.stage.remote_tree_sha256=('7'*64)}
Add-DenialCase 'stage-commit-drift' {param($b)$b.stage.commit_sha=('7'*40)}
Add-DenialCase 'stage-binding-fingerprint-drift' {param($b)$b.stage.binding_fingerprint=('7'*64)}
Add-DenialCase 'stage-baseline-unsafe' {param($b)$b.stage.stage_baseline.safe=$false}
Add-DenialCase 'stage-baseline-uninstallable' {param($b)$b.stage.stage_baseline.installable=$false}
Add-DenialCase 'stage-manifest-drift' {param($b)$b.stage.stage_baseline.manifest_name='other'}
Add-DenialCase 'shadow-authority-drift' {param($b)$b.shadow.production_mutation_authorized=$true}
Add-DenialCase 'shadow-status-drift' {param($b)$b.shadow.status='rolled-back-shadow-fixture'}
Add-DenialCase 'shadow-reason-drift' {param($b)$b.shadow.reason='other'}
Add-DenialCase 'shadow-not-committed' {param($b)$b.shadow.committed=$false}
Add-DenialCase 'shadow-rolled-back' {param($b)$b.shadow.rolled_back=$true}
Add-DenialCase 'shadow-provenance-drift' {param($b)$b.shadow.fresh_provenance_fingerprint=('7'*64)}
Add-DenialCase 'shadow-binding-drift' {param($b)$b.shadow.binding_fingerprint=('7'*64)}
Add-DenialCase 'shadow-stage-tree-drift' {param($b)$b.shadow.stage_tree_sha256=('7'*64)}
Add-DenialCase 'shadow-transaction-id-missing' {param($b)$b.shadow.transaction_id=''}
Add-DenialCase 'shadow-persistence-invalid' {param($b)$b.shadow.pre_persistence_fingerprint='bad'}
Add-DenialCase 'shadow-persistence-drift' {param($b)$b.shadow.post_persistence_fingerprint=('7'*64)}

foreach($case in $cases){
    $decision=Resolve-Bundle $case.bundle
    Assert-DeniedAndAuthorityClosed -Decision $decision -Label ([string]$case.name)
}

$emptyNameBundle=New-ValidPromotionBundle
$empty=Resolve-CustomAppProductionPromotionEligibilityV010 -Name '' -LifecycleRow $emptyNameBundle.lifecycle -ProvenanceRow $emptyNameBundle.provenance -BindingRow $emptyNameBundle.binding -StageResult $emptyNameBundle.stage -ShadowResult $emptyNameBundle.shadow
Assert-DeniedAndAuthorityClosed -Decision $empty -Label 'empty-name'

Write-Host ('CUSTOM_APP_PRODUCTION_PROMOTION_GATE_MATRIX_PASS cases=' + ($cases.Count+4))
