$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay both exact validated proof families and reuse only their fixture constructors.
. (Join-Path $root 'validation/custom-app-production-promotion-gate-v0.1.0/test_custom_app_production_promotion_gate.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-artifact-retirement-resume-executor-v0.1.0/test_custom_app_production_recovery_artifact_retirement_resume_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-new-permit-readiness.ps1')

function Assert-RAReadyTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RAReadyFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RAReadyEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RAReady($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAReadyPromotionBundleV010 {
    param([Parameter(Mandatory=$true)]$RecoveryResult,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow,[string]$RemoteTree=('d'*64),[string]$RemoteCommit=('e'*40))
    $b=New-ValidPromotionBundle
    $name=([string]$RecoveryResult.name).Trim().ToLowerInvariant();$source=([string]$RecoveryResult.source_identity).Trim().ToLowerInvariant();$manifest=$(if($name-ceq'tagify'){'tagify'}else{$name})
    $b.lifecycle.name=$name;$b.lifecycle.locations=@("C:\fixture\CustomApps\$name")
    $b.provenance.name=$name;$b.provenance.source_identity=$source;$b.provenance.last_proven_source=$source;$b.provenance.observed_source_candidate=$source
    $b.binding.name=$name;$b.binding.source_identity=$source;$b.binding.binding.source_identity=$source;$b.binding.binding.manifest_name=$manifest;$b.binding.last_local_manifest_name=$manifest
    $b.binding.last_local_tree_sha256=[string]$RecoveryResult.live_tree_sha256;$b.binding.binding.last_verified_local_tree_sha256=[string]$RecoveryResult.live_tree_sha256
    $b.binding.last_remote_tree_sha256=$RemoteTree;$b.binding.binding.last_verified_remote_tree_sha256=$RemoteTree;$b.binding.last_remote_commit_sha=$RemoteCommit;$b.binding.binding.last_verified_commit_sha=$RemoteCommit;$b.binding.last_success=$At.AddMinutes(-1).ToUniversalTime().ToString('o')
    $b.stage.source_identity=$source;$b.shadow.name=$name;$b.shadow.pre_persistence_fingerprint=[string]$RecoveryResult.persistence_fingerprint;$b.shadow.post_persistence_fingerprint=[string]$RecoveryResult.persistence_fingerprint;$b.shadow.fresh_provenance_fingerprint=[string]$b.provenance.evidence_fingerprint
    [void](Sync-PromotionBundleFingerprints -Bundle $b)
    return $b
}
function New-RAReadyFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('a'*32),[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    $f=New-CRFixtureV010 -Label ('ready-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $resume=Invoke-RRResumeV010 -F $f -At $At.AddSeconds(-1)
    Assert-RAReadyTrue ([bool]$resume.ok) ("$Label retirement resume denied: $([string]$resume.reason)")
    $bundle=New-RAReadyPromotionBundleV010 -RecoveryResult $resume.result -At $At
    return [pscustomobject]@{f=$f;resume=$resume;bundle=$bundle;at=$At}
}
function Invoke-RAReadyV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()]$Bundle=$null,[AllowNull()]$ResumeResult=$null,[AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$ResumeResult){$ResumeResult=$Q.resume.result};if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$Q.f.ce.q.f.f.identity.transaction_id};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at}
    return Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $ResumeResult -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId $Tx -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -Now $At
}
function Assert-RAReadyZeroAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R};foreach($f in @('readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RAReadyFalse ([bool]$x.$f) "$Label authority escaped $f"}}
function Assert-RAReadyDeniedV010($R,[string]$Label){Assert-RAReadyFalse ([bool]$R.ok) "$Label unexpectedly ready";Assert-RAReadyZeroAuthorityV010 $R $Label}

$count=0
$valid=New-RAReadyFixtureV010 -Label 'valid' -Nonce ('1'*32);$r=Invoke-RAReadyV010 $valid;Assert-RAReadyTrue ([bool]$r.ok) ('valid readiness denied: '+[string]$r.reason);Assert-RAReadyTrue ([bool]$r.receipt.eligible_to_request_new_update_permit) 'valid readiness flag false';Assert-RAReadyTrue ([bool]$r.receipt.requires_new_update_permit) 'valid new-permit requirement false';Assert-RAReadyZeroAuthorityV010 $r 'valid';$ck=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $r.receipt -Now $valid.at.AddSeconds(1);Assert-RAReadyTrue ([bool]$ck.ok) ('valid receipt invalid: '+[string]$ck.reason);$validReceipt=Copy-RAReady $r.receipt;$count++

# A newer upstream commit after recovery closure is intentionally allowed as long as the stable local starting state is unchanged.
$newRemote=Copy-RAReady $valid.bundle;$newRemote.binding.last_remote_tree_sha256=('b'*64);$newRemote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$newRemote.binding.last_remote_commit_sha=('c'*40);$newRemote.binding.binding.last_verified_commit_sha=('c'*40);[void](Sync-PromotionBundleFingerprints $newRemote);$r=Invoke-RAReadyV010 -Q $valid -Bundle $newRemote;Assert-RAReadyTrue ([bool]$r.ok) ('newer remote commit incorrectly denied: '+[string]$r.reason);Assert-RAReadyEq $r.receipt.current_remote_commit_sha ('c'*40) 'newer remote commit not bound';$count++

$future=New-RAReadyFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32);$r=Invoke-RAReadyV010 $future;Assert-RAReadyTrue ([bool]$r.ok) ('future app readiness denied: '+[string]$r.reason);Assert-RAReadyEq $r.receipt.name 'future-app' 'future app name';Assert-RAReadyEq $r.receipt.source_identity 'owner/future-app' 'future app source';$count++

$userRemoved=New-RAReadyFixtureV010 -Label 'user-removed' -Nonce ('3'*32);$b=Copy-RAReady $userRemoved.bundle;$b.lifecycle.user_removed=$true;$r=Invoke-RAReadyV010 -Q $userRemoved -Bundle $b;Assert-RAReadyDeniedV010 $r 'user removed';Assert-RAReadyTrue ([string]$r.reason-like'*current-promotion-denied*') 'user removed reason drift';$count++

$stageDrift=New-RAReadyFixtureV010 -Label 'stage-drift' -Nonce ('4'*32);$b=Copy-RAReady $stageDrift.bundle;$b.stage.remote_tree_sha256=('7'*64);$r=Invoke-RAReadyV010 -Q $stageDrift -Bundle $b;Assert-RAReadyDeniedV010 $r 'stage drift';$count++

# Make a self-consistent promotion proof whose local baseline differs from the recovery-stable live tree: old promotion gate passes, recovery-aware continuity must deny.
$localDrift=New-RAReadyFixtureV010 -Label 'local-drift' -Nonce ('5'*32);$b=Copy-RAReady $localDrift.bundle;$b.binding.last_local_tree_sha256=('8'*64);$b.binding.binding.last_verified_local_tree_sha256=('8'*64);[void](Sync-PromotionBundleFingerprints $b);$old=Resolve-Bundle $b;Assert-RAReadyTrue ([bool]$old.eligible_for_production_promotion) 'local drift control did not pass old promotion gate';$r=Invoke-RAReadyV010 -Q $localDrift -Bundle $b;Assert-RAReadyDeniedV010 $r 'stable local continuity drift';Assert-RAReadyTrue ([string]$r.reason-like'*current-local-tree-does-not-match-stable-recovery*') 'stable local drift reason';$count++

$persistDrift=New-RAReadyFixtureV010 -Label 'promotion-persistence-drift' -Nonce ('6'*32);$b=Copy-RAReady $persistDrift.bundle;$b.shadow.pre_persistence_fingerprint=('9'*64);$b.shadow.post_persistence_fingerprint=('9'*64);$old=Resolve-Bundle $b;Assert-RAReadyTrue ([bool]$old.eligible_for_production_promotion) 'persistence drift control did not pass old promotion gate';$r=Invoke-RAReadyV010 -Q $persistDrift -Bundle $b;Assert-RAReadyDeniedV010 $r 'stable persistence continuity drift';Assert-RAReadyTrue ([string]$r.reason-like'*current-persistence-does-not-match-stable-recovery*') 'stable persistence drift reason';$count++

$sourceDrift=New-RAReadyFixtureV010 -Label 'source-drift' -Nonce ('7'*32);$b=Copy-RAReady $sourceDrift.bundle;$newSource='other/repo';$b.provenance.source_identity=$newSource;$b.provenance.last_proven_source=$newSource;$b.provenance.observed_source_candidate=$newSource;$b.binding.source_identity=$newSource;$b.binding.binding.source_identity=$newSource;$b.stage.source_identity=$newSource;[void](Sync-PromotionBundleFingerprints $b);$old=Resolve-Bundle $b;Assert-RAReadyTrue ([bool]$old.eligible_for_production_promotion) 'source drift control did not pass old promotion gate';$r=Invoke-RAReadyV010 -Q $sourceDrift -Bundle $b;Assert-RAReadyDeniedV010 $r 'stable source continuity drift';Assert-RAReadyTrue ([string]$r.reason-like'*current-identity-does-not-match-stable-recovery*') 'stable source drift reason';$count++

$stale=New-RAReadyFixtureV010 -Label 'stale-remote' -Nonce ('8'*32);$b=Copy-RAReady $stale.bundle;$b.binding.last_success=$stale.at.AddMinutes(-11).ToUniversalTime().ToString('o');$r=Invoke-RAReadyV010 -Q $stale -Bundle $b;Assert-RAReadyDeniedV010 $r 'stale remote observation';Assert-RAReadyEq $r.reason 'recovery-aware-readiness-current-remote-observation-not-fresh' 'stale remote reason';$count++

$resumeAuthority=New-RAReadyFixtureV010 -Label 'resume-authority' -Nonce ('9'*32);$bad=Copy-RAReady $resumeAuthority.resume.result;$bad.cleanup_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 -Result $bad);$r=Invoke-RAReadyV010 -Q $resumeAuthority -ResumeResult $bad;Assert-RAReadyDeniedV010 $r 'resume authority tamper';Assert-RAReadyTrue ([string]$r.reason-like'*retirement-resume-result-invalid:*authority-escaped-cleanup_authorized*') 'resume authority reason';$count++

$resumeFp=New-RAReadyFixtureV010 -Label 'resume-fingerprint' -Nonce ('a'*32);$bad=Copy-RAReady $resumeFp.resume.result;$bad.result_fingerprint=('0'*64);$r=Invoke-RAReadyV010 -Q $resumeFp -ResumeResult $bad;Assert-RAReadyDeniedV010 $r 'resume fingerprint tamper';$count++

# A historically valid result is insufficient if a retired artifact reappears in durable state.
$reappear=New-RAReadyFixtureV010 -Label 'artifact-reappears' -Nonce ('b'*32);[IO.Directory]::CreateDirectory([string]$reappear.resume.result.stage_workspace_path)|Out-Null;$r=Invoke-RAReadyV010 $reappear;Assert-RAReadyDeniedV010 $r 'retired artifact reappeared';Assert-RAReadyTrue ([string]$r.reason-like'*terminal-recovery-not-closed*'-or[string]$r.reason-like'*terminal-bridge-denied:*') 'artifact reappear reason';$count++

$liveDrift=New-RAReadyFixtureV010 -Label 'live-drift' -Nonce ('c'*32);[IO.File]::AppendAllText((Join-Path $liveDrift.f.ce.q.f.f.q.x.live 'index.js'),"// readiness live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-RAReadyV010 $liveDrift;Assert-RAReadyDeniedV010 $r 'live drift after recovery';Assert-RAReadyTrue ([string]$r.reason-like'*terminal-bridge-denied:*') 'live drift reason';$count++

$persistenceDrift=New-RAReadyFixtureV010 -Label 'protected-persistence-drift' -Nonce ('d'*32);[IO.File]::AppendAllText((Join-Path $persistenceDrift.f.ce.q.f.f.q.persistence.local 'Spotify\Browser\IndexedDB\000001.log'),'drift',[Text.UTF8Encoding]::new($false));$r=Invoke-RAReadyV010 $persistenceDrift;Assert-RAReadyDeniedV010 $r 'protected persistence drift after recovery';Assert-RAReadyTrue ([string]$r.reason-like'*terminal-bridge-denied:*') 'protected persistence drift reason';$count++

$continuityTamper=New-RAReadyFixtureV010 -Label 'resume-continuity' -Nonce ('e'*32);$bad=Copy-RAReady $continuityTamper.resume.result;$bad.live_tree_sha256=('f'*64);$bad.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 -Result $bad);$check=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $bad;Assert-RAReadyTrue ([bool]$check.ok) 'resume continuity control did not remain self-valid';$r=Invoke-RAReadyV010 -Q $continuityTamper -ResumeResult $bad;Assert-RAReadyDeniedV010 $r 'recovery continuity tamper';Assert-RAReadyTrue ([string]$r.reason-like'*recovery-continuity-mismatch-live_tree_sha256*') 'recovery continuity reason';$count++

$wrongTx=New-RAReadyFixtureV010 -Label 'wrong-tx' -Nonce ('f'*32);$r=Invoke-RAReadyV010 -Q $wrongTx -Tx ('f'*64);Assert-RAReadyDeniedV010 $r 'wrong transaction';$count++

$receiptTamper=Copy-RAReady $validReceipt;$receiptTamper.permit_issued=$true;$receiptTamper.readiness_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010 -Receipt $receiptTamper);$c=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $receiptTamper -Now $valid.at.AddSeconds(1);Assert-RAReadyFalse ([bool]$c.ok) 'permit-issued tampered receipt accepted';Assert-RAReadyTrue ([string]$c.reason-like'*authority-escaped-permit_issued*') 'receipt authority tamper reason';$count++

$c=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $validReceipt -Now $valid.at.AddSeconds(11);Assert-RAReadyFalse ([bool]$c.ok) 'expired readiness receipt accepted';Assert-RAReadyEq $c.reason 'recovery-aware-readiness-expired' 'readiness expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_NEW_PERMIT_READINESS_MATRIX_PASS total=$count"
