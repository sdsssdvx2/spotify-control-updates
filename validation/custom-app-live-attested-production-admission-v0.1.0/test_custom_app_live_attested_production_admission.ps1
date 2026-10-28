$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1')
. (Join-Path $PSScriptRoot 'custom-app-live-attested-production-admission.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Copy-Fixture {param($Object)return ($Object|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
function Assert-AdmissionAuthorityDenied {
    param($Decision,[string]$Label)
    Assert-True ([string]$Decision.mutation_mode -ceq 'deny') "$Label mutation mode drifted"
    Assert-False ([bool]$Decision.mutation_authorized) "$Label mutation_authorized"
    Assert-False ([bool]$Decision.auto_update_authorized) "$Label auto_update_authorized"
    Assert-False ([bool]$Decision.auto_install_authorized) "$Label auto_install_authorized"
    Assert-False ([bool]$Decision.canary_execution_authorized) "$Label canary_execution_authorized"
    Assert-False ([bool]$Decision.production_mutation_authorized) "$Label production_mutation_authorized"
    Assert-False ([bool]$Decision.production_permit_issued) "$Label production permit issued"
    Assert-False ([bool]$Decision.admission_is_authority) "$Label admission became authority"
    Assert-True ([bool]$Decision.requires_fresh_revalidation_before_any_future_action) "$Label fresh revalidation missing"
}

function New-AdmissionFixture {
    param([string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $path=('C:\fixture\CustomApps\'+$Name);$localTree=('1'*64);$remoteTree=('2'*64);$provFp=('3'*64);$assetDigest=('4'*64);$commit=('a'*40);$observed='2026-10-28T10:30:00+00:00'
    $lifecycle=[pscustomobject]@{schema=1;managed_by='dynamic-spicetify-v1';kind='custom-app';name=$Name;present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($path);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $provenance=[pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';name=$Name;source_identity=$Source;last_proven_source=$Source;source_changed=$false;requires_reenrollment=$false;evidence_fingerprint=$provFp;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $immutable=[pscustomobject]@{schema=1;managed_by='custom-app-remote-source-v1';source_identity=$Source;github_repo_id=[int64]987654321;surface_kind='release-asset';layout_root='.';manifest_name=$Manifest;last_verified_local_tree_sha256=$localTree;last_verified_remote_tree_sha256=$remoteTree;last_verified_commit_sha=$commit;release_asset_selector='unique-zip-asset';asset_name=($Name+'-v2.zip');last_observed_asset_id=[int64]418974188;last_observed_asset_digest_sha256=$assetDigest;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $binding=[pscustomobject]@{schema=1;managed_by='custom-app-remote-binding-observer-v1';name=$Name;active=$true;source_identity=$Source;binding=$immutable;last_success=$observed;last_status='remote-change-observed';last_reason='verified-remote-runtime-change';last_error=$null;last_local_tree_sha256=$localTree;last_local_manifest_name=$Manifest;last_remote_tree_sha256=$remoteTree;last_remote_commit_sha=$commit;update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=$localTree;manifest_name=$Manifest;path=$path}
    $shadow=[pscustomobject]@{schema=1;managed_by='custom-app-shadow-protocol-qualification-v1';validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead;production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256;push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true;push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId;push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
    return [pscustomobject]@{name=$Name;lifecycle=$lifecycle;provenance=$provenance;binding=$binding;baseline=$baseline;shadow=$shadow;live=(New-CustomAppLiveAttestedProtocolQualificationV010)}
}

function Invoke-AdmissionFixture {param($F,[DateTimeOffset]$Now=([DateTimeOffset]'2026-10-28T10:40:00+00:00'))return Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name $F.name -LifecycleRow $F.lifecycle -ProvenanceRow $F.provenance -BindingRow $F.binding -CurrentBaseline $F.baseline -ShadowProtocolQualification $F.shadow -LiveAttestedQualification $F.live -Now $Now}
function Assert-Denied {param($Decision,[string]$Label)Assert-False ([bool]$Decision.production_admission_eligible) "$Label unexpectedly eligible";Assert-AdmissionAuthorityDenied $Decision $Label}

$count=0
$tagify=New-AdmissionFixture;$d=Invoke-AdmissionFixture $tagify;Assert-True ([bool]$d.production_admission_eligible) ('Tagify admission denied: '+[string]$d.reason);Assert-True ([string]$d.reason -ceq 'fresh-current-evidence-plus-live-attested-protocol-qualified') 'Tagify positive reason drifted';Assert-True (Test-CustomAppLiveAdmissionSha256V010 ([string]$d.admission_fingerprint)) 'Tagify admission fingerprint invalid';Assert-AdmissionAuthorityDenied $d 'tagify-positive';$count++
$future=New-AdmissionFixture -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App';$fd=Invoke-AdmissionFixture $future;Assert-True ([bool]$fd.production_admission_eligible) ('Generic future app admission denied: '+[string]$fd.reason);Assert-AdmissionAuthorityDenied $fd 'future-app-positive';$count++
$d2=Invoke-AdmissionFixture $tagify;Assert-True ([string]$d.admission_fingerprint -ceq [string]$d2.admission_fingerprint) 'Admission fingerprint nondeterministic';$count++

$cases=New-Object System.Collections.Generic.List[object]
function Add-DenialCase {param([string]$Label,[scriptblock]$Mutate,[string]$Expected)$f=New-AdmissionFixture;& $Mutate $f;$cases.Add([pscustomobject]@{label=$Label;fixture=$f;expected=$Expected})}
Add-DenialCase 'live-head-mismatch' {param($f)$f.live.validated_live_head=('b'*40)} 'live-qualification-lineage-mismatch'
Add-DenialCase 'live-push-digest-mismatch' {param($f)$f.live.push_artifact_digest=('sha256:'+('5'*64))} 'live-qualification-artifact-digest-mismatch'
Add-DenialCase 'live-commit-evidence-missing' {param($f)$f.live.committed_preserved_passed=$false} 'live-qualification-evidence-incomplete-committed_preserved_passed'
Add-DenialCase 'live-authority-corruption' {param($f)$f.live.production_mutation_authorized=$true} 'live-qualification-production_mutation_authorized-true'
Add-DenialCase 'live-separation-corruption' {param($f)$f.live.qualification_is_authority=$true} 'live-qualification-authority-separation-invalid'
Add-DenialCase 'user-removed' {param($f)$f.lifecycle.user_removed=$true;$f.lifecycle.present=$false} 'current-eligibility-denied:lifecycle-not-current-safe-single-path'
Add-DenialCase 'source-change' {param($f)$f.provenance.source_changed=$true} 'current-eligibility-denied:provenance-not-current-strong'
Add-DenialCase 'remote-stale' {param($f)$f.binding.last_success='2026-10-26T00:00:00+00:00'} 'current-eligibility-denied:binding-remote-observation-stale'
Add-DenialCase 'runtime-drift' {param($f)$f.baseline.tree_sha256=('8'*64)} 'current-eligibility-denied:current-runtime-drifted-since-binding-observation'
Add-DenialCase 'shadow-protocol-drift' {param($f)$f.shadow.validated_shadow_head=('c'*40)} 'current-eligibility-denied:qualified-shadow-head-mismatch'
Add-DenialCase 'current-authority-corruption' {param($f)$f.provenance.auto_update_authorized=$true} 'current-eligibility-denied:provenance-row-auto-authority-true'
foreach($c in $cases){$x=Invoke-AdmissionFixture $c.fixture;Assert-Denied $x $c.label;Assert-True ([string]$x.reason -ceq [string]$c.expected) ($c.label+' reason drifted: '+[string]$x.reason+' != '+[string]$c.expected);$count++}

$nullLive=New-AdmissionFixture;$nullLive.live=$null;$x=Invoke-AdmissionFixture $nullLive;Assert-Denied $x 'null-live';Assert-True ([string]$x.reason -ceq 'live-qualification-null') 'null live reason drifted';$count++
$empty=New-AdmissionFixture;$empty.name=' ';$x=Invoke-AdmissionFixture $empty;Assert-Denied $x 'empty-name';Assert-True ([string]$x.reason -ceq 'name-empty') 'empty name reason drifted';$count++

Write-Host ('CUSTOM_APP_LIVE_ATTESTED_PRODUCTION_ADMISSION_MATRIX_PASS total='+$count+' eligible=3 denied='+($count-3))
