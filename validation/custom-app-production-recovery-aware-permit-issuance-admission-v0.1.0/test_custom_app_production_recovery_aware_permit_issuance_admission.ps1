$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse the exact validated durable-recovery/readiness fixture family. The workflow
# materializes this sibling test/core byte-for-byte before this script executes.
. (Join-Path $root 'validation/custom-app-production-recovery-aware-new-permit-readiness-v0.1.0/test_custom_app_production_recovery_aware_new_permit_readiness.ps1')
. (Join-Path $root 'validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1')
. (Join-Path $root 'validation/custom-app-live-attested-production-admission-v0.1.0/custom-app-live-attested-production-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-issuance-admission.ps1')

function Assert-RAIssueTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RAIssueFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RAIssueEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RAIssue($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAIssueLiveContextV010 {
    param([Parameter(Mandatory=$true)]$Bundle)
    $path=[string]$Bundle.lifecycle.locations[0]
    $baseline=[pscustomobject]@{
        safe=$true;installable=$true;tree_sha256=[string]$Bundle.binding.last_local_tree_sha256
        manifest_name=[string]$Bundle.binding.last_local_manifest_name;path=$path
    }
    $shadow=[pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-protocol-qualification-v1'
        validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead;production_main=$CustomAppPromotionQualifiedProductionMain
        addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256
        push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true
        push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId
        push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    return [pscustomobject]@{baseline=$baseline;shadow=$shadow;live=(New-CustomAppLiveAttestedProtocolQualificationV010)}
}

function Invoke-RAIssueV010 {
    param(
        [Parameter(Mandatory=$true)]$Q,[AllowNull()]$Bundle=$null,[AllowNull()]$ResumeResult=$null,
        [AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,
        [AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue
    )
    if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$ResumeResult){$ResumeResult=$Q.resume.result};if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$Q.f.ce.q.f.f.identity.transaction_id};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    if($null-eq$Baseline){$Baseline=$ctx.baseline};if($null-eq$ShadowQualification){$ShadowQualification=$ctx.shadow};if($null-eq$LiveQualification){$LiveQualification=$ctx.live}
    return Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $ResumeResult -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId $Tx -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -Now $At
}

function Assert-RAIssueZeroAuthorityV010($R,[string]$Label){
    $x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R}
    foreach($f in @('issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RAIssueFalse ([bool]$x.$f) "$Label authority escaped $f"}
}
function Assert-RAIssueDeniedV010($R,[string]$Label){Assert-RAIssueFalse ([bool]$R.ok) "$Label unexpectedly eligible";Assert-RAIssueZeroAuthorityV010 $R $Label}

function Invoke-RAIssueWithForgedLiveDecisionV010 {
    param([Parameter(Mandatory=$true)]$Q,[Parameter(Mandatory=$true)]$Decision,[AllowNull()]$Bundle=$null)
    if($null-eq$Bundle){$Bundle=$Q.bundle}
    $original=(Get-Command Resolve-CustomAppLiveAttestedProductionAdmissionV010 -CommandType Function).ScriptBlock
    $script:RAIssueForgedLiveDecision=$Decision
    try{
        Set-Item -Path Function:\Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Value {
            param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$Now,$MaxRemoteObservationAgeHours)
            return $script:RAIssueForgedLiveDecision
        }
        return Invoke-RAIssueV010 -Q $Q -Bundle $Bundle
    } finally {
        Set-Item -Path Function:\Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Value $original
        $script:RAIssueForgedLiveDecision=$null
    }
}

function Invoke-RAIssueWithForgedReadinessV010 {
    param([Parameter(Mandatory=$true)]$Q,[Parameter(Mandatory=$true)]$ReadinessResult,[Parameter(Mandatory=$true)]$Bundle)
    $original=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 -CommandType Function).ScriptBlock
    $script:RAIssueForgedReadiness=$ReadinessResult
    try{
        Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 -Value {
            param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now)
            return $script:RAIssueForgedReadiness
        }
        return Invoke-RAIssueV010 -Q $Q -Bundle $Bundle
    } finally {
        Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitReadinessV010 -Value $original
        $script:RAIssueForgedReadiness=$null
    }
}

$count=0
$valid=New-RAReadyFixtureV010 -Label 'issuance-valid' -Nonce ('1'*32)
$r=Invoke-RAIssueV010 -Q $valid
Assert-RAIssueTrue ([bool]$r.ok) ('valid issuance admission denied: '+[string]$r.reason)
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-eligible-zero-authority' 'valid reason'
Assert-RAIssueTrue ([bool]$r.receipt.permit_issuance_eligible) 'valid permit issuance eligibility false'
Assert-RAIssueTrue ([bool]$r.receipt.requires_fresh_permit_creation_revalidation) 'valid fresh permit creation revalidation missing'
Assert-RAIssueTrue ([bool]$r.receipt.requires_single_use_permit) 'valid single-use requirement missing'
Assert-RAIssueTrue ([bool]$r.receipt.requires_external_consumption_ledger) 'valid external consumption ledger requirement missing'
Assert-RAIssueZeroAuthorityV010 $r 'valid'
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $r.receipt -Now $valid.at.AddSeconds(1)
Assert-RAIssueTrue ([bool]$ck.ok) ('valid issuance receipt invalid: '+[string]$ck.reason)
$validReceipt=Copy-RAIssue $r.receipt
$count++

$r2=Invoke-RAIssueV010 -Q $valid
Assert-RAIssueTrue ([bool]$r2.ok) ('deterministic repeat denied: '+[string]$r2.reason)
Assert-RAIssueEq $r2.receipt.issuance_admission_fingerprint $validReceipt.issuance_admission_fingerprint 'issuance fingerprint nondeterministic'
$count++

$future=New-RAReadyFixtureV010 -Label 'issuance-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$r=Invoke-RAIssueV010 -Q $future
Assert-RAIssueTrue ([bool]$r.ok) ('future app issuance admission denied: '+[string]$r.reason)
Assert-RAIssueEq $r.receipt.name 'future-app' 'future app name'
Assert-RAIssueEq $r.receipt.source_identity 'owner/future-app' 'future app source'
Assert-RAIssueZeroAuthorityV010 $r 'future-app'
$count++

$newRemote=Copy-RAIssue $valid.bundle
$newRemote.binding.last_remote_tree_sha256=('b'*64);$newRemote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$newRemote.binding.last_remote_commit_sha=('c'*40);$newRemote.binding.binding.last_verified_commit_sha=('c'*40)
[void](Sync-PromotionBundleFingerprints -Bundle $newRemote)
$r=Invoke-RAIssueV010 -Q $valid -Bundle $newRemote
Assert-RAIssueTrue ([bool]$r.ok) ('newer remote commit issuance admission denied: '+[string]$r.reason)
Assert-RAIssueEq $r.receipt.current_remote_commit_sha ('c'*40) 'newer remote commit not bound'
Assert-RAIssueEq $r.receipt.current_remote_tree_sha256 ('b'*64) 'newer remote tree not bound'
$count++

$userRemoved=Copy-RAIssue $valid.bundle;$userRemoved.lifecycle.user_removed=$true;$userRemoved.lifecycle.present=$false
$r=Invoke-RAIssueV010 -Q $valid -Bundle $userRemoved
Assert-RAIssueDeniedV010 $r 'user removed'
Assert-RAIssueTrue ([string]$r.reason-like'recovery-aware-permit-issuance-admission-readiness-denied:*') 'user removed denial did not come from fresh readiness'
$count++

$ctx=New-RAIssueLiveContextV010 -Bundle $valid.bundle;$badBaseline=Copy-RAIssue $ctx.baseline;$badBaseline.tree_sha256=('8'*64)
$r=Invoke-RAIssueV010 -Q $valid -Baseline $badBaseline
Assert-RAIssueDeniedV010 $r 'current baseline drift'
Assert-RAIssueTrue ([string]$r.reason-like'recovery-aware-permit-issuance-admission-live-admission-denied:*') 'baseline drift did not fail fresh live admission'
$count++

$badLive=Copy-RAIssue $ctx.live;$badLive.production_mutation_authorized=$true
$r=Invoke-RAIssueV010 -Q $valid -LiveQualification $badLive
Assert-RAIssueDeniedV010 $r 'live qualification authority corruption'
Assert-RAIssueTrue ([string]$r.reason-like'recovery-aware-permit-issuance-admission-live-admission-denied:*') 'live authority corruption reason'
$count++

$badShadow=Copy-RAIssue $ctx.shadow;$badShadow.validated_shadow_head=('f'*40)
$r=Invoke-RAIssueV010 -Q $valid -ShadowQualification $badShadow
Assert-RAIssueDeniedV010 $r 'shadow protocol drift'
Assert-RAIssueTrue ([string]$r.reason-like'recovery-aware-permit-issuance-admission-live-admission-denied:*') 'shadow drift reason'
$count++

$stale=Copy-RAIssue $valid.bundle;$stale.binding.last_success=$valid.at.AddHours(-40).ToUniversalTime().ToString('o');[void](Sync-PromotionBundleFingerprints -Bundle $stale)
$r=Invoke-RAIssueV010 -Q $valid -Bundle $stale
Assert-RAIssueDeniedV010 $r 'stale remote observation'
$count++

$r=Invoke-RAIssueV010 -Q $valid -Tx 'bad'
Assert-RAIssueDeniedV010 $r 'malformed transaction'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-transaction-id-invalid' 'malformed transaction reason'
$count++

$r=Invoke-RAIssueV010 -Q $valid -Tx ('f'*64)
Assert-RAIssueDeniedV010 $r 'wrong durable transaction'
Assert-RAIssueTrue ([string]$r.reason-like'recovery-aware-permit-issuance-admission-readiness-denied:*') 'wrong transaction reason'
$count++

# Prove that the integration continuity checks are not redundant with the permit admission validator.
$actualLive=Resolve-CustomAppLiveAttestedProductionAdmissionV010 -Name ([string]$valid.bundle.lifecycle.name) -LifecycleRow $valid.bundle.lifecycle -ProvenanceRow $valid.bundle.provenance -BindingRow $valid.bundle.binding -CurrentBaseline $ctx.baseline -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -Now $valid.at
$actualCheck=Test-CustomAppProductionPermitAdmissionDecisionV010 -Decision $actualLive
Assert-RAIssueTrue ([bool]$actualCheck.ok) ('continuity control live admission invalid: '+[string]$actualCheck.reason)

$forged=Copy-RAIssue $actualLive;$forged.name='other-app'
$r=Invoke-RAIssueWithForgedLiveDecisionV010 -Q $valid -Decision $forged
Assert-RAIssueDeniedV010 $r 'forged live name continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-name-mismatch' 'live name continuity reason'
$count++

$forged=Copy-RAIssue $actualLive;$forged.source_identity='other/repo'
$r=Invoke-RAIssueWithForgedLiveDecisionV010 -Q $valid -Decision $forged
Assert-RAIssueDeniedV010 $r 'forged live source continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-source-mismatch' 'live source continuity reason'
$count++

$forged=Copy-RAIssue $actualLive;$forged.current_tree_sha256=('8'*64)
$r=Invoke-RAIssueWithForgedLiveDecisionV010 -Q $valid -Decision $forged
Assert-RAIssueDeniedV010 $r 'forged live current tree continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-current-tree-mismatch' 'live current continuity reason'
$count++

$forged=Copy-RAIssue $actualLive;$forged.remote_tree_sha256=('9'*64)
$r=Invoke-RAIssueWithForgedLiveDecisionV010 -Q $valid -Decision $forged
Assert-RAIssueDeniedV010 $r 'forged live remote tree continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-remote-tree-mismatch' 'live remote continuity reason'
$count++

$forged=Copy-RAIssue $actualLive;$forged.remote_commit_sha=('f'*40)
$r=Invoke-RAIssueWithForgedLiveDecisionV010 -Q $valid -Decision $forged
Assert-RAIssueDeniedV010 $r 'forged live remote commit continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-remote-commit-mismatch' 'live commit continuity reason'
$count++

$readyBase=Invoke-RAReadyV010 -Q $valid
Assert-RAIssueTrue ([bool]$readyBase.ok) ('forged readiness control invalid: '+[string]$readyBase.reason)

$bindingDrift=Copy-RAIssue $valid.bundle;$bindingDrift.binding.binding.last_observed_asset_id=[int64]$bindingDrift.binding.binding.last_observed_asset_id+1
$r=Invoke-RAIssueWithForgedReadinessV010 -Q $valid -ReadinessResult $readyBase -Bundle $bindingDrift
Assert-RAIssueDeniedV010 $r 'stale readiness binding continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-binding-fingerprint-mismatch' 'binding continuity reason'
$count++

$provDrift=Copy-RAIssue $valid.bundle;$provDrift.provenance.evidence_fingerprint=('9'*64)
$r=Invoke-RAIssueWithForgedReadinessV010 -Q $valid -ReadinessResult $readyBase -Bundle $provDrift
Assert-RAIssueDeniedV010 $r 'stale readiness provenance continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-provenance-fingerprint-mismatch' 'provenance continuity reason'
$count++

$observedDrift=Copy-RAIssue $valid.bundle;$observedDrift.binding.last_success=$valid.at.AddMinutes(-2).ToUniversalTime().ToString('o')
$readyObserved=Copy-RAIssue $readyBase
$readyObserved.receipt.current_binding_fingerprint=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $observedDrift.binding
$readyObserved.receipt.readiness_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReadinessSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReadinessMaterialV010 -Receipt $readyObserved.receipt)
$readyObservedCheck=Test-CustomAppProductionRecoveryAwarePermitReadinessReceiptV010 -Receipt $readyObserved.receipt -Now $valid.at
Assert-RAIssueTrue ([bool]$readyObservedCheck.ok) ('observed continuity forged readiness receipt invalid: '+[string]$readyObservedCheck.reason)
$r=Invoke-RAIssueWithForgedReadinessV010 -Q $valid -ReadinessResult $readyObserved -Bundle $observedDrift
Assert-RAIssueDeniedV010 $r 'stale readiness observed-at continuity'
Assert-RAIssueEq $r.reason 'recovery-aware-permit-issuance-admission-continuity-remote-observed-at-mismatch' 'observed-at continuity reason'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.permit_issued=$true;$bad.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $bad)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'permit-issued receipt tamper accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-authority-escaped-permit_issued' 'permit-issued tamper reason'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.session_key_accepted=$true;$bad.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $bad)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'session-key receipt tamper accepted'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.nonce_reserved=$true;$bad.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $bad)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'nonce-reserved receipt tamper accepted'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.requires_single_use_permit=$false;$bad.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $bad)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'single-use contract tamper accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-required-flag-false-requires_single_use_permit' 'single-use tamper reason'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.qualified_permit_head=('0'*40);$bad.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $bad)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'lineage-tampered receipt accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-parent-lineage-mismatch' 'lineage tamper reason'
$count++

$bad=Copy-RAIssue $validReceipt;$bad.issuance_admission_fingerprint=('0'*64)
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1)
Assert-RAIssueFalse ([bool]$ck.ok) 'fingerprint-tampered receipt accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-fingerprint-mismatch' 'fingerprint tamper reason'
$count++

$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $validReceipt -Now $valid.at.AddSeconds(5)
Assert-RAIssueFalse ([bool]$ck.ok) 'expired issuance admission receipt accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-expired' 'expiry reason'
$count++

$ck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $validReceipt -Now $valid.at.AddSeconds(-6)
Assert-RAIssueFalse ([bool]$ck.ok) 'not-yet-valid issuance admission receipt accepted'
Assert-RAIssueEq $ck.reason 'recovery-aware-permit-issuance-admission-not-yet-valid' 'not-yet-valid reason'
$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ISSUANCE_ADMISSION_MATRIX_PASS total=$count permit_created=false session_key_accepted=false nonce_reserved=false"