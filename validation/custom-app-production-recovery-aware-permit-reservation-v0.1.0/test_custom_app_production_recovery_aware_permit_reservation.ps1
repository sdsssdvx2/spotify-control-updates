$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-issuer-v0.1.0/test_custom_app_production_recovery_aware_permit_issuer.ps1')
. (Join-Path $root 'validation/custom-app-production-permit-reservation-v0.1.0/custom-app-production-permit-reservation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-reservation.ps1')

function Assert-RAPRTrue([bool]$v,[string]$m){if(-not$v){throw$m}}
function Assert-RAPRFalse([bool]$v,[string]$m){if($v){throw$m}}
function Assert-RAPREq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw"$m actual=<$a> expected=<$b>"}}
function Copy-RAPR($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPRFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('8'*32))
    $ready=New-RAReadyFixtureV010 -Label ('rapr-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $prior=New-RAIssuerPriorV010 $ready
    $issuer=Invoke-RAIssuerV010 -Q $ready -Prior $prior -Nonce $Nonce
    if(-not[bool]$issuer.ok){throw('RAPR issuer setup failed: '+[string]$issuer.reason)}
    return[pscustomobject]@{ready=$ready;prior=$prior;issuer=$issuer;state=(New-CustomAppProductionPermitReservationStateV010);nonce=$Nonce}
}
function Invoke-RAPRFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[AllowNull()]$Bundle=$null,[AllowNull()]$Issuer=$null,[AllowNull()]$State=$null,[AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()][string]$Name=$null,[AllowNull()][string]$Tx=$null,[AllowNull()][Int64]$ExpectedRevision=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue
    )
    $Q=$F.ready;if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$Issuer){$Issuer=$F.issuer};if($null-eq$State){$State=$F.state};if($null-eq$Key){$Key=$script:RAIssuerKey};if([string]::IsNullOrWhiteSpace($Name)){$Name=[string]$Bundle.lifecycle.name};if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$Q.f.ce.q.f.f.identity.transaction_id};if($null-eq$ExpectedRevision){$ExpectedRevision=[int64]$State.revision};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle;if($null-eq$Baseline){$Baseline=$ctx.baseline};if($null-eq$ShadowQualification){$ShadowQualification=$ctx.shadow};if($null-eq$LiveQualification){$LiveQualification=$ctx.live}
    return Invoke-CustomAppProductionRecoveryAwarePermitReservationV010 -Name $Name -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId $Tx -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -IssuerResult $Issuer -SessionKey $Key -ReservationState $State -ExpectedRevision $ExpectedRevision -Now $At
}
function Assert-RAPRNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']-and$null-ne$R.receipt){$R.receipt}else{$R};foreach($f in@('reservation_persisted','session_key_persisted','session_key_exposed','nonce_durably_reserved','permit_durably_reserved','permit_consumed','reservation_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')){Assert-RAPRFalse ([bool]$x.$f) "$Label escaped $f"}}
function Assert-RAPRDeniedV010($R,[string]$Label){Assert-RAPRFalse ([bool]$R.ok) "$Label unexpectedly succeeded";Assert-RAPRNoAuthorityV010 $R $Label}

$count=0
$valid=New-RAPRFixtureV010 'valid' -Nonce ('1'*32);$r=Invoke-RAPRFixtureV010 $valid
Assert-RAPRTrue ([bool]$r.ok) ('valid reservation denied: '+[string]$r.reason);Assert-RAPREq $r.reason 'recovery-aware-permit-reserved-in-memory-requires-immediate-atomic-persistence' 'valid reason';Assert-RAPRTrue ([bool]$r.reservation_created) 'reservation not created';Assert-RAPRFalse ([bool]$r.reservation_persisted) 'reservation unexpectedly persisted';Assert-RAPRTrue ([bool]$r.nonce_reserved_in_memory) 'nonce not reserved in memory';Assert-RAPRTrue ([bool]$r.permit_reserved_in_memory) 'permit not reserved in memory';Assert-RAPRNoAuthorityV010 $r 'valid'
Assert-RAPREq $valid.state.revision 0 'input reservation state mutated';Assert-RAPREq $r.next_state.revision 1 'next state revision';Assert-RAPREq @($r.next_state.reservations).Count 1 'next state row count';Assert-RAPREq $r.reservation.token_id $valid.issuer.receipt.permit_token_id 'reservation token';Assert-RAPREq $r.reservation.permit_nonce $valid.issuer.receipt.permit_nonce 'reservation nonce'
$ck=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $r.receipt -Now $valid.ready.at.AddSeconds(1);Assert-RAPRTrue ([bool]$ck.ok) ('valid reservation receipt denied: '+[string]$ck.reason);$count++

$future=New-RAPRFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32);$rf=Invoke-RAPRFixtureV010 $future;Assert-RAPRTrue ([bool]$rf.ok) ('future app reservation denied: '+[string]$rf.reason);Assert-RAPREq $rf.receipt.name 'future-app' 'future name';Assert-RAPRNoAuthorityV010 $rf 'future';$count++

$replay=Invoke-RAPRFixtureV010 -F $valid -State $r.next_state -ExpectedRevision 1;Assert-RAPRDeniedV010 $replay 'permit replay';Assert-RAPRTrue ([string]$replay.reason-like'*permit-already-reserved-token*') ('replay reason '+[string]$replay.reason);Assert-RAPREq $replay.next_state.revision 1 'replay leaked altered state';$count++
$stale=Invoke-RAPRFixtureV010 -F $valid -State $r.next_state -ExpectedRevision 0;Assert-RAPRDeniedV010 $stale 'stale CAS';Assert-RAPRTrue ([string]$stale.reason-like'*reservation-state-revision-conflict*') 'stale CAS reason';$count++

$expired=Invoke-RAPRFixtureV010 -F $valid -At $valid.ready.at.AddSeconds(6);Assert-RAPRDeniedV010 $expired 'expired issuer reservation window';Assert-RAPRTrue ([string]$expired.reason-like'*issuer-receipt-invalid:*expired*') ('expired issuer reason '+[string]$expired.reason);$count++
$wrongKey=Invoke-RAPRFixtureV010 -F $valid -Key $script:RAIssuerWrongKey;Assert-RAPRDeniedV010 $wrongKey 'wrong session key';Assert-RAPRTrue ([string]$wrongKey.reason-like'*permit-invalid:*hmac-mismatch*') ('wrong key reason '+[string]$wrongKey.reason);$count++

$removed=Copy-RAPR $valid.ready.bundle;$removed.lifecycle.user_removed=$true;$removed.lifecycle.present=$false;$rr=Invoke-RAPRFixtureV010 -F $valid -Bundle $removed;Assert-RAPRDeniedV010 $rr 'user removal after issuance';Assert-RAPRTrue ([string]$rr.reason-like'*fresh-admission-denied:*') ('user removal reason '+[string]$rr.reason);$count++
$ctx=New-RAIssueLiveContextV010 -Bundle $valid.ready.bundle;$driftBase=Copy-RAPR $ctx.baseline;$driftBase.tree_sha256=('7'*64);$rb=Invoke-RAPRFixtureV010 -F $valid -Baseline $driftBase;Assert-RAPRDeniedV010 $rb 'baseline drift after issuance';Assert-RAPRTrue ([string]$rb.reason-like'*fresh-admission-denied:*') ('baseline drift reason '+[string]$rb.reason);$count++

$remote=Copy-RAPR $valid.ready.bundle;$remote.binding.last_remote_tree_sha256=('b'*64);$remote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$remote.binding.last_remote_commit_sha=('c'*40);$remote.binding.binding.last_verified_commit_sha=('c'*40);[void](Sync-PromotionBundleFingerprints -Bundle $remote);$remoteR=Invoke-RAPRFixtureV010 -F $valid -Bundle $remote;Assert-RAPRDeniedV010 $remoteR 'remote drift after issuance';Assert-RAPRTrue ([string]$remoteR.reason-like'*issuer-fresh-*mismatch') ('remote drift reason '+[string]$remoteR.reason);$count++

$badIssuerReceipt=Copy-RAPR $valid.issuer.receipt;$badIssuerReceipt.permit_reserved=$true;$badIssuerReceipt.issuer_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 -Receipt $badIssuerReceipt);$badIssuer=[pscustomobject]@{ok=$true;permit=$valid.issuer.permit;receipt=$badIssuerReceipt};$ri=Invoke-RAPRFixtureV010 -F $valid -Issuer $badIssuer;Assert-RAPRDeniedV010 $ri 'pre-reserved issuer receipt';Assert-RAPRTrue ([string]$ri.reason-like'*issuer-receipt-invalid:*permit_reserved*') 'pre-reserved issuer reason';$count++

$badState=Copy-RAPR $valid.state;$badState.production_execution_authorized=$true;$rs=Invoke-RAPRFixtureV010 -F $valid -State $badState;Assert-RAPRDeniedV010 $rs 'authority-polluted reservation state';Assert-RAPRTrue ([string]$rs.reason-like'*reservation-state-production_execution_authorized-true*') ('bad state reason '+[string]$rs.reason);$count++

# Force only the post-reservation fresh recovery admission to drift. The returned failure must expose the original state, not the in-memory reservation.
$actualFresh=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $valid.ready.bundle.lifecycle.name -LifecycleRow $valid.ready.bundle.lifecycle -ProvenanceRow $valid.ready.bundle.provenance -BindingRow $valid.ready.bundle.binding -StageResult $valid.ready.bundle.stage -ShadowResult $valid.ready.bundle.shadow -RetirementResumeResult $valid.ready.resume.result -CurrentBaseline $ctx.baseline -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $valid.ready.f.ce.q.f.f.allowed -StoreDirectory $valid.ready.f.ce.q.f.f.store -ExpectedTransactionId ([string]$valid.ready.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $valid.ready.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.ready.f.ce.q.f.f.q.persistence.roaming -Now $valid.ready.at
Assert-RAPRTrue ([bool]$actualFresh.ok) 'post-drift fresh setup failed'
$script:RAPRCall=0;$script:RAPRFirst=$actualFresh;$script:RAPRSecondReceipt=Copy-RAPR $actualFresh.receipt;$script:RAPRSecondReceipt.current_remote_commit_sha=('d'*40);$script:RAPRSecondReceipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $script:RAPRSecondReceipt)
$origResolve=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock
try{
    Set-Item Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value {param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours);$script:RAPRCall++;if($script:RAPRCall-eq1){return$script:RAPRFirst};return[pscustomobject]@{ok=$true;reason='fixture-post-drift';receipt=$script:RAPRSecondReceipt}}
    $rd=Invoke-RAPRFixtureV010 -F $valid
} finally {Set-Item Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value $origResolve;$script:RAPRCall=0}
Assert-RAPRDeniedV010 $rd 'post-reservation admission drift';Assert-RAPREq $rd.reason 'recovery-aware-permit-reservation-admission-drift-during-reservation' 'post drift reason';Assert-RAPREq $rd.next_state.revision 0 'post drift leaked reserved next state';$count++

$good=Invoke-RAPRFixtureV010 $valid;Assert-RAPRTrue ([bool]$good.ok) 'receipt tamper setup failed'
$bad=Copy-RAPR $good.receipt;$bad.reservation_persisted=$true;$bad.reservation_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationSha256V010(Get-CustomAppProductionRecoveryAwarePermitReservationMaterialV010 -Receipt $bad);$c=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $bad -Now $valid.ready.at.AddSeconds(1);Assert-RAPRFalse ([bool]$c.ok) 'rehashed persisted reservation receipt accepted';Assert-RAPRTrue ([string]$c.reason-like'*persistence-escaped-reservation_persisted*') 'persisted receipt reason';$count++
$bad=Copy-RAPR $good.receipt;$bad.executor_may_start=$true;$bad.reservation_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationSha256V010(Get-CustomAppProductionRecoveryAwarePermitReservationMaterialV010 -Receipt $bad);$c=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $bad -Now $valid.ready.at.AddSeconds(1);Assert-RAPRFalse ([bool]$c.ok) 'rehashed executor-authorized reservation receipt accepted';$count++
$bad=Copy-RAPR $good.receipt;$bad.reservation_fingerprint=('0'*64);$c=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $bad -Now $valid.ready.at.AddSeconds(1);Assert-RAPRFalse ([bool]$c.ok) 'fingerprint-tampered reservation receipt accepted';Assert-RAPREq $c.reason 'recovery-aware-permit-reservation-fingerprint-mismatch' 'fingerprint reason';$count++
$c=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $good.receipt -Now $valid.ready.at.AddSeconds(4);Assert-RAPRFalse ([bool]$c.ok) 'expired persistence window accepted';Assert-RAPREq $c.reason 'recovery-aware-permit-reservation-persistence-window-expired' 'persistence expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_RESERVATION_MATRIX_PASS total=$count"
