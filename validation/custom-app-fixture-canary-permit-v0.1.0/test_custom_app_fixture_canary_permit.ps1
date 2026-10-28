$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'custom-app-promotion-eligibility-gate-v0.1.0\custom-app-promotion-eligibility.ps1')
. (Join-Path $PSScriptRoot 'custom-app-fixture-canary-permit.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Copy-Fixture {param([Parameter(Mandatory=$true)]$Object)return ($Object|ConvertTo-Json -Depth 40|ConvertFrom-Json)}
function Assert-ThrowsLike {
    param([scriptblock]$Action,[string]$Pattern,[string]$Label)
    $threw=$false
    try{& $Action}catch{$threw=$true;if([string]$_.Exception.Message -notlike $Pattern){throw "$Label wrong exception: $($_.Exception.Message)"}}
    if(-not $threw){throw "$Label did not throw"}
}
function Assert-NoProductionAuthority {
    param([Parameter(Mandatory=$true)]$Object,[string]$Label)
    foreach($n in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if($Object.PSObject.Properties[$n] -and [bool]$Object.$n){throw "$Label unexpectedly granted $n"}
    }
    if($Object.PSObject.Properties['mutation_mode'] -and [string]$Object.mutation_mode -cne 'deny'){throw "$Label mutation_mode drifted"}
}
function Assert-DeniedVerification {
    param([Parameter(Mandatory=$true)]$Result,[string]$Reason,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly verified"
    Assert-True ([string]$Result.reason -ceq $Reason) "$Label reason drifted: $($Result.reason) != $Reason"
    if($Result.PSObject.Properties['fixture_canary_execution_authorized']){Assert-False ([bool]$Result.fixture_canary_execution_authorized) "$Label granted fixture execution"}
    Assert-NoProductionAuthority -Object $Result -Label $Label
}

function New-ValidPromotionFixtureForCanary {
    $name='tagify';$source='alexk218/tagify';$path='C:\fixture\CustomApps\tagify'
    $local=('1'*64);$remote=('2'*64);$prov=('3'*64);$asset=('4'*64);$commit=('a'*40);$observed='2026-10-28T11:00:00+00:00'
    $lifecycle=[pscustomobject]@{schema=1;managed_by='dynamic-spicetify-v1';kind='custom-app';name=$name;present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($path);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $provenance=[pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';name=$name;source_identity=$source;last_proven_source=$source;source_changed=$false;requires_reenrollment=$false;evidence_fingerprint=$prov;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $inner=[pscustomobject]@{schema=1;managed_by='custom-app-remote-source-v1';source_identity=$source;github_repo_id=[int64]987654321;surface_kind='release-asset';layout_root='.';manifest_name='Tagify';last_verified_local_tree_sha256=$local;last_verified_remote_tree_sha256=$remote;last_verified_commit_sha=$commit;release_asset_selector='unique-zip-asset';asset_name='tagify-v3.3.2.zip';last_observed_asset_id=[int64]418974188;last_observed_asset_digest_sha256=$asset;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $binding=[pscustomobject]@{schema=1;managed_by='custom-app-remote-binding-observer-v1';name=$name;active=$true;source_identity=$source;binding=$inner;last_success=$observed;last_status='remote-change-observed';last_reason='verified-remote-runtime-change';last_error=$null;last_local_tree_sha256=$local;last_local_manifest_name='Tagify';last_remote_tree_sha256=$remote;last_remote_commit_sha=$commit;update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=$local;manifest_name='Tagify';path=$path}
    $qualification=[pscustomobject]@{schema=1;managed_by='custom-app-shadow-protocol-qualification-v1';validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead;production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256;push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true;push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId;push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
    $now=[DateTimeOffset]::Parse('2026-10-28T11:05:00+00:00')
    $decision=Resolve-CustomAppPromotionEligibilityV010 -Name $name -LifecycleRow $lifecycle -ProvenanceRow $provenance -BindingRow $binding -CurrentBaseline $baseline -ProtocolQualification $qualification -Now $now
    if(-not [bool]$decision.promotion_candidate_eligible){throw ('Could not create valid promotion decision fixture: '+[string]$decision.reason)}
    return [pscustomobject]@{decision=$decision;now=$now}
}

$fixture=New-ValidPromotionFixtureForCanary
$decision=$fixture.decision
$root=Get-CustomAppFixtureCanaryRootV010
$key=[byte[]](0..31);$wrongKey=[byte[]](32..63);$nonce='0123456789abcdef0123456789abcdef'
$issued=[DateTimeOffset]::Parse('2026-10-28T11:10:00+00:00');$verifyNow=[DateTimeOffset]::Parse('2026-10-28T11:11:00+00:00')
$permit=New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -Nonce $nonce -IssuedAt $issued -TtlMinutes 5
Assert-True ([bool]$permit.fixture_canary_execution_authorized) 'valid permit did not grant fixture-only execution'
Assert-NoProductionAuthority -Object $permit -Label 'valid-permit'
Assert-True ([string]$permit.scope -ceq 'fixture-canary-only') 'valid permit scope drifted'
Assert-True (Test-CustomAppFixtureCanarySha256V010 ([string]$permit.token_id)) 'valid permit token id invalid'
Assert-True (Test-CustomAppFixtureCanarySha256V010 ([string]$permit.hmac_sha256)) 'valid permit hmac invalid'

$verified=Test-CustomAppFixtureCanaryPermitV010 -Permit $permit -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -Now $verifyNow
Assert-True ([bool]$verified.ok) ('valid permit verification failed: '+[string]$verified.reason)
Assert-True ([bool]$verified.fixture_canary_execution_authorized) 'verified permit did not grant fixture-only execution'
Assert-NoProductionAuthority -Object $verified -Label 'verified-permit'
Assert-True ([string]$verified.token_id -ceq [string]$permit.token_id) 'verified token id drifted'

$state=New-CustomAppFixtureCanaryConsumptionStateV010
Assert-NoProductionAuthority -Object $state -Label 'fresh-consumption-state'
$consume=Invoke-CustomAppFixtureCanaryPermitConsumptionV010 -Permit $permit -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -ConsumptionState $state -Now $verifyNow
Assert-True ([bool]$consume.ok) ('valid permit consumption failed: '+[string]$consume.reason)
Assert-True ([bool]$consume.fixture_canary_execution_authorized) 'consumed permit did not grant fixture-only execution'
Assert-NoProductionAuthority -Object $consume -Label 'consumed-permit'
Assert-True (@($state.consumed_token_ids).Count -eq 0) 'consumption mutated caller state in place'
Assert-True (@($consume.next_state.consumed_token_ids).Count -eq 1) 'consumption did not return single-use state'
Assert-NoProductionAuthority -Object $consume.next_state -Label 'next-consumption-state'
$replay=Invoke-CustomAppFixtureCanaryPermitConsumptionV010 -Permit $permit -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -ConsumptionState $consume.next_state -Now $verifyNow
Assert-DeniedVerification -Result $replay -Reason 'permit-replay-detected' -Label 'replay'

$denied=New-Object System.Collections.Generic.List[object]
function Add-VerifyCase {
    param([string]$Label,[scriptblock]$MutatePermit,[scriptblock]$MutateDecision,[byte[]]$UseKey,[string]$UseRoot,[DateTimeOffset]$UseNow,[string]$Reason)
    $p=Copy-Fixture $permit;$d=Copy-Fixture $decision
    if($null -ne $MutatePermit){& $MutatePermit $p};if($null -ne $MutateDecision){& $MutateDecision $d}
    $denied.Add([pscustomobject]@{label=$Label;permit=$p;decision=$d;key=$UseKey;root=$UseRoot;now=$UseNow;reason=$Reason})
}

Add-VerifyCase 'wrong-session-key' $null $null $wrongKey $root $verifyNow 'permit-hmac-mismatch'
Add-VerifyCase 'expired' $null $null $key $root ([DateTimeOffset]::Parse('2026-10-28T11:15:00+00:00')) 'permit-expired'
Add-VerifyCase 'not-yet-valid' $null $null $key $root ([DateTimeOffset]::Parse('2026-10-28T11:09:00+00:00')) 'permit-not-yet-valid'
Add-VerifyCase 'wrong-request-root' $null $null $key (Join-Path ([IO.Path]::GetTempPath()) 'other-root') $verifyNow 'permit-fixture-root-scope-mismatch'
Add-VerifyCase 'scope-tamper' {param($p)$p.scope='production'} $null $key $root $verifyNow 'permit-owner-schema-scope-or-parent-mismatch'
Add-VerifyCase 'parent-head-tamper' {param($p)$p.qualified_eligibility_head=('b'*40)} $null $key $root $verifyNow 'permit-owner-schema-scope-or-parent-mismatch'
Add-VerifyCase 'fixture-authority-cleared' {param($p)$p.fixture_canary_execution_authorized=$false} $null $key $root $verifyNow 'permit-fixture-scope-flags-invalid'
Add-VerifyCase 'production-authority-tamper' {param($p)$p.production_mutation_authorized=$true} $null $key $root $verifyNow 'permit-production_mutation_authorized-true'
Add-VerifyCase 'generic-canary-authority-tamper' {param($p)$p.canary_execution_authorized=$true} $null $key $root $verifyNow 'permit-canary_execution_authorized-true'
Add-VerifyCase 'auto-update-authority-tamper' {param($p)$p.auto_update_authorized=$true} $null $key $root $verifyNow 'permit-auto_update_authorized-true'
Add-VerifyCase 'nonce-tamper' {param($p)$p.nonce='fedcba9876543210fedcba9876543210'} $null $key $root $verifyNow 'permit-token-id-mismatch'
Add-VerifyCase 'token-id-tamper' {param($p)$p.token_id=('5'*64)} $null $key $root $verifyNow 'permit-token-id-mismatch'
Add-VerifyCase 'hmac-tamper' {param($p)$p.hmac_sha256=('6'*64)} $null $key $root $verifyNow 'permit-hmac-mismatch'
Add-VerifyCase 'expiry-tamper' {param($p)$p.expires_at='2026-10-28T11:16:00.0000000+00:00'} $null $key $root $verifyNow 'permit-token-id-mismatch'
Add-VerifyCase 'permit-source-tamper' {param($p)$p.source_identity='owner/other'} $null $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-source_identity'
Add-VerifyCase 'permit-remote-tree-tamper' {param($p)$p.remote_tree_sha256=('7'*64)} $null $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-remote_tree_sha256'
Add-VerifyCase 'permit-remote-commit-tamper' {param($p)$p.remote_commit_sha=('b'*40)} $null $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-remote_commit_sha'
Add-VerifyCase 'permit-eligibility-fingerprint-tamper' {param($p)$p.eligibility_fingerprint=('8'*64)} $null $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-eligibility_fingerprint'
Add-VerifyCase 'eligibility-revoked' $null {param($d)$d.promotion_candidate_eligible=$false} $key $root $verifyNow 'permit-current-eligibility-denied:eligibility-not-current-candidate'
Add-VerifyCase 'eligibility-production-authority-drift' $null {param($d)$d.production_mutation_authorized=$true} $key $root $verifyNow 'permit-current-eligibility-denied:eligibility-decision-production_mutation_authorized-true'
Add-VerifyCase 'eligibility-source-drift' $null {param($d)$d.source_identity='owner/other'} $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-source_identity'
Add-VerifyCase 'eligibility-remote-tree-drift' $null {param($d)$d.remote_tree_sha256=('9'*64)} $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-remote_tree_sha256'
Add-VerifyCase 'eligibility-fingerprint-drift' $null {param($d)$d.eligibility_fingerprint=('a'*64)} $key $root $verifyNow 'permit-current-eligibility-binding-mismatch-eligibility_fingerprint'

$count=0
foreach($c in $denied){
    $r=Test-CustomAppFixtureCanaryPermitV010 -Permit $c.permit -EligibilityDecision $c.decision -FixtureRoot $c.root -SessionKey $c.key -Now $c.now
    Assert-DeniedVerification -Result $r -Reason ([string]$c.reason) -Label ([string]$c.label)
    $count++
}

$shortKey=[byte[]](0..15)
Assert-ThrowsLike -Action {New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot $root -SessionKey $shortKey -Nonce $nonce -IssuedAt $issued -TtlMinutes 5|Out-Null} -Pattern '*at least 32 bytes*' -Label 'short-key-issuance'
Assert-ThrowsLike -Action {New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -Nonce 'bad' -IssuedAt $issued -TtlMinutes 5|Out-Null} -Pattern '*32 lowercase hex*' -Label 'bad-nonce-issuance'
Assert-ThrowsLike -Action {New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -Nonce $nonce -IssuedAt $issued -TtlMinutes 11|Out-Null} -Pattern '*between 1 and 10 minutes*' -Label 'ttl-too-long-issuance'
Assert-ThrowsLike -Action {New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot (Join-Path ([IO.Path]::GetTempPath()) 'wrong') -SessionKey $key -Nonce $nonce -IssuedAt $issued -TtlMinutes 5|Out-Null} -Pattern '*dedicated fixture canary root*' -Label 'wrong-root-issuance'
$revoked=Copy-Fixture $decision;$revoked.promotion_candidate_eligible=$false
Assert-ThrowsLike -Action {New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $revoked -FixtureRoot $root -SessionKey $key -Nonce $nonce -IssuedAt $issued -TtlMinutes 5|Out-Null} -Pattern '*eligibility-not-current-candidate*' -Label 'revoked-eligibility-issuance'
$count+=5

$badState=New-CustomAppFixtureCanaryConsumptionStateV010;$badState.production_mutation_authorized=$true
$badConsume=Invoke-CustomAppFixtureCanaryPermitConsumptionV010 -Permit $permit -EligibilityDecision $decision -FixtureRoot $root -SessionKey $key -ConsumptionState $badState -Now $verifyNow
Assert-DeniedVerification -Result $badConsume -Reason 'consumption-state-invalid' -Label 'bad-consumption-state'
$count++

Write-Host ('CUSTOM_APP_FIXTURE_CANARY_PERMIT_MATRIX_PASS verified=1 consumed=1 replay_denied=1 denied='+$count+' total_checks='+($count+4))
