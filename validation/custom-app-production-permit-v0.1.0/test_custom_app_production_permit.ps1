$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1')
. (Join-Path $root 'validation/custom-app-live-attested-production-admission-v0.1.0/custom-app-live-attested-production-admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-permit.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Copy-Fixture {param($Object)return ($Object|ConvertTo-Json -Depth 30|ConvertFrom-Json)}
function Assert-NoExecutionAuthority {param($Result,[string]$Label)Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority";Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority";Assert-True ([bool]$Result.requires_single_use_consumption) "$Label single-use consumption missing";Assert-True ([bool]$Result.requires_fresh_admission_revalidation) "$Label fresh admission revalidation missing"}

function New-PermitFixture {
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

$now=[DateTimeOffset]'2026-10-28T10:40:00+00:00';$key=[byte[]](1..32);$wrongKey=[byte[]](33..64);$nonce='0123456789abcdef0123456789abcdef'
function New-FixturePermit {param($F,[DateTimeOffset]$IssuedAt=$now,[int]$Ttl=3,[byte[]]$SessionKey=$key,[string]$Nonce=$nonce)return New-CustomAppProductionPermitV010 -Name $F.name -LifecycleRow $F.lifecycle -ProvenanceRow $F.provenance -BindingRow $F.binding -CurrentBaseline $F.baseline -ShadowProtocolQualification $F.shadow -LiveAttestedQualification $F.live -SessionKey $SessionKey -Nonce $Nonce -IssuedAt $IssuedAt -TtlMinutes $Ttl}
function Test-FixturePermit {param($Permit,$F,[DateTimeOffset]$At=$now,[byte[]]$SessionKey=$key)return Test-CustomAppProductionPermitV010 -Permit $Permit -Name $F.name -LifecycleRow $F.lifecycle -ProvenanceRow $F.provenance -BindingRow $F.binding -CurrentBaseline $F.baseline -ShadowProtocolQualification $F.shadow -LiveAttestedQualification $F.live -SessionKey $SessionKey -Now $At}
function Assert-Denied {param($Result,[string]$Label)Assert-False ([bool]$Result.ok) "$Label unexpectedly valid";Assert-NoExecutionAuthority $Result $Label}
function Resign-Permit {param($Permit,[byte[]]$SessionKey=$key)$Permit.token_id=$null;$Permit.hmac_sha256=$null;$m=Get-CustomAppProductionPermitMaterialV010 $Permit;$Permit.token_id=Get-CustomAppProductionPermitSha256V010 $m;$Permit.hmac_sha256=Get-CustomAppProductionPermitHmacV010 $m $SessionKey;return $Permit}

$count=0
$f=New-PermitFixture;$permit=New-FixturePermit $f;$r=Test-FixturePermit $permit $f;Assert-True ([bool]$r.ok) ('valid Tagify permit denied: '+[string]$r.reason);Assert-True ([string]$r.reason -ceq 'production-permit-cryptographically-valid-prerequisite') 'valid permit reason drifted';Assert-NoExecutionAuthority $r 'valid-tagify';Assert-True ([bool]$permit.production_permit_issued -and -not [bool]$permit.permit_is_authority -and -not [bool]$permit.production_execution_authorized -and -not [bool]$permit.production_mutation_authorized) 'issued permit authority separation drifted';$count++
$f2=New-PermitFixture -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App';$p2=New-FixturePermit $f2;$r2=Test-FixturePermit $p2 $f2;Assert-True ([bool]$r2.ok) ('generic future-app permit denied: '+[string]$r2.reason);Assert-NoExecutionAuthority $r2 'future-app';$count++
$rAgain=Test-FixturePermit $permit $f;Assert-True ([bool]$rAgain.ok) 'stateless permit unexpectedly self-consumed';Assert-True ([bool]$rAgain.replay_protection_requires_external_consumption_ledger) 'external consumption-ledger requirement missing';Assert-NoExecutionAuthority $rAgain 'repeat-validation';$count++

$r=Test-FixturePermit $permit $f $now $wrongKey;Assert-Denied $r 'wrong-key';Assert-True ([string]$r.reason -ceq 'permit-hmac-mismatch') 'wrong key reason drifted';$count++
$t=Copy-Fixture $permit;$t.remote_tree_sha256=('9'*64);$r=Test-FixturePermit $t $f;Assert-Denied $r 'tamper-tree';Assert-True ([string]$r.reason -ceq 'permit-token-id-mismatch') 'tamper tree reason drifted';$count++
$t=Copy-Fixture $permit;$t.production_mutation_authorized=$true;$t=Resign-Permit $t;$r=Test-FixturePermit $t $f;Assert-Denied $r 'resigned-authority-tamper';Assert-True ([string]$r.reason -ceq 'permit-production_mutation_authorized-true') 'authority tamper reason drifted';$count++
$t=Copy-Fixture $permit;$t.permit_is_authority=$true;$t=Resign-Permit $t;$r=Test-FixturePermit $t $f;Assert-Denied $r 'resigned-permit-authority';Assert-True ([string]$r.reason -ceq 'permit-scope-or-consumption-flags-invalid') 'permit authority reason drifted';$count++
$t=Copy-Fixture $permit;$t.single_use=$false;$t=Resign-Permit $t;$r=Test-FixturePermit $t $f;Assert-Denied $r 'resigned-single-use-off';$count++
$r=Test-FixturePermit $permit $f $now.AddMinutes(4);Assert-Denied $r 'expired';Assert-True ([string]$r.reason -ceq 'permit-expired') 'expired reason drifted';$count++
$futurePermit=New-FixturePermit $f $now.AddMinutes(1);$r=Test-FixturePermit $futurePermit $f $now;Assert-Denied $r 'not-yet-valid';Assert-True ([string]$r.reason -ceq 'permit-not-yet-valid') 'future permit reason drifted';$count++
$fRemoved=New-PermitFixture;$p=New-FixturePermit $fRemoved;$fRemoved.lifecycle.user_removed=$true;$fRemoved.lifecycle.present=$false;$r=Test-FixturePermit $p $fRemoved;Assert-Denied $r 'user-removed-after-issue';Assert-True ([string]$r.reason -like 'permit-current-admission-denied:*') 'user removal did not force admission revalidation';$count++
$fSource=New-PermitFixture;$p=New-FixturePermit $fSource;$fSource.provenance.source_changed=$true;$r=Test-FixturePermit $p $fSource;Assert-Denied $r 'source-change-after-issue';$count++
$fDrift=New-PermitFixture;$p=New-FixturePermit $fDrift;$fDrift.baseline.tree_sha256=('8'*64);$r=Test-FixturePermit $p $fDrift;Assert-Denied $r 'runtime-drift-after-issue';$count++
$fStale=New-PermitFixture;$p=New-FixturePermit $fStale;$fStale.binding.last_success='2026-10-26T00:00:00+00:00';$r=Test-FixturePermit $p $fStale;Assert-Denied $r 'stale-binding-after-issue';$count++
$fLive=New-PermitFixture;$p=New-FixturePermit $fLive;$fLive.live.validated_live_head=('b'*40);$r=Test-FixturePermit $p $fLive;Assert-Denied $r 'live-qualification-drift-after-issue';$count++

$threw=$false;try{[void](New-FixturePermit $f $now 6)}catch{$threw=$true};Assert-True $threw 'TTL > 5 minutes was accepted';$count++
$threw=$false;try{[void](New-FixturePermit $f $now 3 $key 'bad')}catch{$threw=$true};Assert-True $threw 'invalid nonce was accepted';$count++
$short=[byte[]](1..16);$threw=$false;try{[void](New-FixturePermit $f $now 3 $short)}catch{$threw=$true};Assert-True $threw 'short session key was accepted';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_PERMIT_MATRIX_PASS total='+$count+' valid=3 denied_or_throw='+($count-3))
