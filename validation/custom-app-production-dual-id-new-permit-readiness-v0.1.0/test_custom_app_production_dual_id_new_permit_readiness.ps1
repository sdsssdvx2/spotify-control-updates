$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay the exact validated normal-success terminal chain and the exact promotion gate.
. (Join-Path $root 'validation/custom-app-production-promotion-gate-v0.1.0/test_custom_app_production_promotion_gate.ps1')
. (Join-Path $root 'validation/custom-app-production-dual-id-housekeeping-resume-executor-v0.1.0/test_custom_app_production_dual_id_housekeeping_resume_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-readiness.ps1')

function Assert-DINPTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-DINPFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-DINPEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-DINP($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}
function Assert-DINPZeroAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']-and$null-ne$R.receipt){$R.receipt}else{$R};foreach($f in @('readiness_is_authority','promotion_token_issued','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-DINPFalse([bool]$x.$f) "$Label authority escaped $f"}}}
function Assert-DINPDeniedV010($R,[string]$Label){Assert-DINPFalse([bool]$R.ok) "$Label unexpectedly ready";Assert-DINPZeroAuthorityV010 $R $Label}

function New-DINPPromotionBundleV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)]$HousekeepingResult,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow,[string]$RemoteTree=('d'*64),[string]$RemoteCommit=('e'*40))
    $pre=Read-CustomAppProductionDurableDualTransactionIdBridgeIntegrationPrecommitV010 -AllowedRoot $X.f.trust -JournalStoreDirectory $X.f.store
    Assert-DINPTrue($null-ne$pre-and[bool]$pre.ok)('promotion bundle precommit unreadable: '+[string]$pre.reason)
    $b=New-ValidPromotionBundle
    $name=([string]$pre.precommit.name).Trim().ToLowerInvariant();$source=([string]$pre.precommit.source_identity).Trim().ToLowerInvariant();$manifest=$(if($name-ceq'tagify'){'tagify'}else{$name})
    $b.lifecycle.name=$name;$b.lifecycle.locations=@([string]$X.f.x.fixture.q.x.live)
    $b.provenance.name=$name;$b.provenance.source_identity=$source;$b.provenance.last_proven_source=$source;$b.provenance.observed_source_candidate=$source
    $b.binding.name=$name;$b.binding.source_identity=$source;$b.binding.binding.source_identity=$source;$b.binding.binding.manifest_name=$manifest;$b.binding.last_local_manifest_name=$manifest
    $b.binding.last_local_tree_sha256=[string]$HousekeepingResult.live_runtime_tree_sha256;$b.binding.binding.last_verified_local_tree_sha256=[string]$HousekeepingResult.live_runtime_tree_sha256
    $b.binding.last_remote_tree_sha256=$RemoteTree;$b.binding.binding.last_verified_remote_tree_sha256=$RemoteTree;$b.binding.last_remote_commit_sha=$RemoteCommit;$b.binding.binding.last_verified_commit_sha=$RemoteCommit;$b.binding.last_success=$At.AddMinutes(-1).ToUniversalTime().ToString('o')
    $b.stage.source_identity=$source;$b.shadow.name=$name;$b.shadow.pre_persistence_fingerprint=[string]$HousekeepingResult.persistence_fingerprint;$b.shadow.post_persistence_fingerprint=[string]$HousekeepingResult.persistence_fingerprint;$b.shadow.fresh_provenance_fingerprint=[string]$b.provenance.evidence_fingerprint
    [void](Sync-PromotionBundleFingerprints -Bundle $b)
    return $b
}
function New-DINPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    $x=New-DBACFixtureV010 ('dinp-'+$Label)
    $house=Invoke-DIHRV010 $x
    Assert-DINPTrue($null-ne$house-and[bool]$house.ok)("$Label housekeeping denied: $([string]$house.reason)")
    $at=[DateTimeOffset]::UtcNow
    $bundle=New-DINPPromotionBundleV010 -X $x -HousekeepingResult $house.result -At $at
    return [pscustomobject]@{x=$x;house=$house;bundle=$bundle;at=$at}
}
function Invoke-DINPV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()]$Bundle=$null,[AllowNull()]$HousekeepingResult=$null,[AllowNull()][string]$PermitId=$null,[AllowNull()][string]$JournalId=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$HousekeepingResult){$HousekeepingResult=$Q.house.result};if([string]::IsNullOrWhiteSpace($PermitId)){$PermitId=[string]$Q.house.result.permit_transaction_id};if([string]::IsNullOrWhiteSpace($JournalId)){$JournalId=[string]$Q.house.result.journal_transaction_id};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at}
    return Resolve-CustomAppProductionDualIdNewPermitReadinessV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -HousekeepingResult $HousekeepingResult -AllowedRoot $Q.x.f.trust -StoreDirectory $Q.x.f.store -ExpectedPermitTransactionId $PermitId -ExpectedJournalTransactionId $JournalId -LocalAppDataRoot ([string]$Q.x.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$Q.x.f.x.fixture.q.persistence.roaming) -Now $At
}

$count=0

$valid=New-DINPFixtureV010 'valid';$r=Invoke-DINPV010 $valid;Assert-DINPTrue([bool]$r.ok)('valid readiness denied: '+[string]$r.reason);Assert-DINPTrue([bool]$r.receipt.eligible_to_request_new_update_permit)'valid eligibility false';Assert-DINPTrue([bool]$r.receipt.requires_new_update_permit)'valid new permit requirement false';Assert-DINPTrue([bool]$r.receipt.transaction_id_namespaces_distinct)'valid IDs not marked distinct';Assert-DINPFalse(([string]$r.receipt.permit_transaction_id)-ceq([string]$r.receipt.journal_transaction_id))'valid IDs conflated';Assert-DINPZeroAuthorityV010 $r 'valid';$ck=Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $r.receipt -Now $valid.at.AddSeconds(1);Assert-DINPTrue([bool]$ck.ok)('valid receipt invalid: '+[string]$ck.reason);$validReceipt=Copy-DINP $r.receipt;$count++

# A newer remote commit is allowed; readiness is about a fresh permit request from unchanged stable local state.
$newRemote=Copy-DINP $valid.bundle;$newRemote.binding.last_remote_tree_sha256=('b'*64);$newRemote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$newRemote.binding.last_remote_commit_sha=('c'*40);$newRemote.binding.binding.last_verified_commit_sha=('c'*40);[void](Sync-PromotionBundleFingerprints $newRemote);$r=Invoke-DINPV010 -Q $valid -Bundle $newRemote;Assert-DINPTrue([bool]$r.ok)('new remote commit denied: '+[string]$r.reason);Assert-DINPEq $r.receipt.current_remote_commit_sha ('c'*40) 'new remote commit not bound';$count++

$userRemoved=New-DINPFixtureV010 'user-removed';$b=Copy-DINP $userRemoved.bundle;$b.lifecycle.user_removed=$true;$r=Invoke-DINPV010 -Q $userRemoved -Bundle $b;Assert-DINPDeniedV010 $r 'user removed';Assert-DINPTrue([string]$r.reason-like'*current-promotion-denied*')'user removed reason drift';$count++

$stale=New-DINPFixtureV010 'stale-remote';$b=Copy-DINP $stale.bundle;$b.binding.last_success=$stale.at.AddMinutes(-11).ToUniversalTime().ToString('o');[void](Sync-PromotionBundleFingerprints $b);$r=Invoke-DINPV010 -Q $stale -Bundle $b;Assert-DINPDeniedV010 $r 'stale remote';Assert-DINPEq $r.reason 'dual-id-readiness-current-remote-observation-not-fresh' 'stale remote reason';$count++

$wrongPermit=New-DINPFixtureV010 'wrong-permit';$wrong=('0'*64);if($wrong-ceq[string]$wrongPermit.house.result.journal_transaction_id){$wrong=('1'*64)};$r=Invoke-DINPV010 -Q $wrongPermit -PermitId $wrong;Assert-DINPDeniedV010 $r 'wrong permit id';Assert-DINPEq $r.reason 'dual-id-readiness-housekeeping-permit-id-mismatch' 'wrong permit reason';$count++

$wrongJournal=New-DINPFixtureV010 'wrong-journal';$wrong=('f'*64);if($wrong-ceq[string]$wrongJournal.house.result.permit_transaction_id){$wrong=('e'*64)};$r=Invoke-DINPV010 -Q $wrongJournal -JournalId $wrong;Assert-DINPDeniedV010 $r 'wrong journal id';Assert-DINPEq $r.reason 'dual-id-readiness-housekeeping-journal-id-mismatch' 'wrong journal reason';$count++

$conflated=New-DINPFixtureV010 'conflated';$r=Invoke-DINPV010 -Q $conflated -JournalId ([string]$conflated.house.result.permit_transaction_id);Assert-DINPDeniedV010 $r 'conflated IDs';Assert-DINPEq $r.reason 'dual-id-readiness-transaction-namespaces-conflated' 'conflated reason';$count++

$authority=New-DINPFixtureV010 'authority-tamper';$bad=Copy-DINP $authority.house.result;$bad.cleanup_authorized=$true;$bad.cleanup_fingerprint=Get-CustomAppProductionDualIdHousekeepingResumeSha256V010(Get-CustomAppProductionDualIdHousekeepingResumeResultMaterialV010 $bad);$r=Invoke-DINPV010 -Q $authority -HousekeepingResult $bad;Assert-DINPDeniedV010 $r 'housekeeping authority tamper';Assert-DINPTrue([string]$r.reason-like'*housekeeping-result-invalid:*authority-escaped-cleanup_authorized*')'authority tamper reason';$count++

$fp=New-DINPFixtureV010 'fingerprint-tamper';$bad=Copy-DINP $fp.house.result;$bad.cleanup_fingerprint=('0'*64);$r=Invoke-DINPV010 -Q $fp -HousekeepingResult $bad;Assert-DINPDeniedV010 $r 'housekeeping fingerprint tamper';$count++

$artifact=New-DINPFixtureV010 'artifact-reappears';$j=Read-DBACJournalV010 $artifact.x;[IO.Directory]::CreateDirectory([string]$j.entry.stage_workspace_path)|Out-Null;$r=Invoke-DINPV010 $artifact;Assert-DINPDeniedV010 $r 'transaction artifact reappeared';Assert-DINPEq $r.reason 'dual-id-readiness-transaction-artifact-reappeared' 'artifact reappear reason';$count++

$evidenceMissing=New-DINPFixtureV010 'evidence-missing';$evidencePath=Join-Path $evidenceMissing.x.f.store 'recovery-evidence.json';Assert-DINPTrue(Test-Path -LiteralPath $evidencePath -PathType Leaf)'evidence fixture missing before test';Remove-Item -LiteralPath $evidencePath -Force;$r=Invoke-DINPV010 $evidenceMissing;Assert-DINPDeniedV010 $r 'missing recovery evidence';Assert-DINPTrue([string]$r.reason-like'dual-id-readiness-recovery-evidence-denied:*')'missing evidence reason';$count++

$live=New-DINPFixtureV010 'live-drift';[IO.File]::AppendAllText((Join-Path ([string]$live.x.f.x.fixture.q.x.live) 'index.js'),"// dual-id readiness live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-DINPV010 $live;Assert-DINPDeniedV010 $r 'live drift';Assert-DINPEq $r.reason 'dual-id-readiness-live-tree-drift' 'live drift reason';$count++

$persist=New-DINPFixtureV010 'persistence-drift';[IO.File]::AppendAllText((Join-Path ([string]$persist.x.f.x.fixture.q.persistence.local) 'Spotify\Browser\IndexedDB\000001.log'),'drift',[Text.UTF8Encoding]::new($false));$r=Invoke-DINPV010 $persist;Assert-DINPDeniedV010 $r 'persistence drift';Assert-DINPEq $r.reason 'dual-id-readiness-persistence-drift' 'persistence drift reason';$count++

$receiptTamper=Copy-DINP $validReceipt;$receiptTamper.permit_issued=$true;$receiptTamper.readiness_fingerprint=Get-CustomAppProductionDualIdNewPermitReadinessSha256V010(Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $receiptTamper);$c=Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $receiptTamper -Now $valid.at.AddSeconds(1);Assert-DINPFalse([bool]$c.ok)'permit-issued receipt tamper accepted';Assert-DINPTrue([string]$c.reason-like'*authority-escaped-permit_issued*')'receipt tamper reason';$count++

$c=Test-CustomAppProductionDualIdNewPermitReadinessReceiptV010 -Receipt $validReceipt -Now $valid.at.AddSeconds(11);Assert-DINPFalse([bool]$c.ok)'expired readiness receipt accepted';Assert-DINPEq $c.reason 'dual-id-readiness-receipt-expired' 'expired receipt reason';$count++

if($count-ne15){throw "dual-ID new permit readiness matrix count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_DUAL_ID_NEW_PERMIT_READINESS_MATRIX_PASS cases=$count committed_clean=true ids_distinct=true recovery_evidence_retained=true transaction_artifacts_absent=true current_promotion_fresh=true permit_issued=false zero_authority=true"
