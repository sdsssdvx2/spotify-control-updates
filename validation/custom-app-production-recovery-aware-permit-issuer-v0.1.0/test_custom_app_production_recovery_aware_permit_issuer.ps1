$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-issuance-admission-v0.1.0/test_custom_app_production_recovery_aware_permit_issuance_admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-issuer.ps1')

function Assert-RAIssuerTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RAIssuerFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RAIssuerEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RAIssuer($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

$script:RAIssuerKey=[byte[]](1..32)
$script:RAIssuerWrongKey=[byte[]](33..64)
$script:RAIssuerNonce='0123456789abcdef0123456789abcdef'

function Get-RAIssuerTxV010($Q){return [string]$Q.f.ce.q.f.f.identity.transaction_id}
function New-RAIssuerPriorV010($Q,[AllowNull()]$Bundle=$null){if($null-eq$Bundle){$Bundle=$Q.bundle};$r=Invoke-RAIssueV010 -Q $Q -Bundle $Bundle;Assert-RAIssuerTrue ([bool]$r.ok) ('prior issuance admission denied: '+[string]$r.reason);return $r.receipt}
function Invoke-RAIssuerV010 {
    param(
        [Parameter(Mandatory=$true)]$Q,[Parameter(Mandatory=$true)]$Prior,[AllowNull()]$Bundle=$null,[AllowNull()]$ResumeResult=$null,
        [AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,
        [AllowNull()][string]$Name=$null,[AllowNull()][string]$Tx=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()][string]$Nonce=$null,
        [DateTimeOffset]$At=[DateTimeOffset]::MinValue,[int]$Ttl=1
    )
    if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$ResumeResult){$ResumeResult=$Q.resume.result};if([string]::IsNullOrWhiteSpace($Name)){$Name=[string]$Bundle.lifecycle.name};if([string]::IsNullOrWhiteSpace($Tx)){$Tx=Get-RAIssuerTxV010 $Q};if($null-eq$Key){$Key=$script:RAIssuerKey};if([string]::IsNullOrWhiteSpace($Nonce)){$Nonce=$script:RAIssuerNonce};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle;if($null-eq$Baseline){$Baseline=$ctx.baseline};if($null-eq$ShadowQualification){$ShadowQualification=$ctx.shadow};if($null-eq$LiveQualification){$LiveQualification=$ctx.live}
    return Invoke-CustomAppProductionRecoveryAwarePermitIssuerV010 -Name $Name -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $ResumeResult -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -StoreDirectory $Q.f.ce.q.f.f.store -ExpectedTransactionId $Tx -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -IssuanceAdmissionReceipt $Prior -SessionKey $Key -Nonce $Nonce -Now $At -TtlMinutes $Ttl
}
function Assert-RAIssuerNoAuthorityV010($R,[string]$Label){
    $x=if($R.PSObject.Properties['receipt']-and$null-ne$R.receipt){$R.receipt}else{$R}
    foreach($f in @('session_key_persisted','session_key_exposed','nonce_reserved','permit_reserved','permit_consumed','issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')){Assert-RAIssuerFalse ([bool]$x.$f) "$Label authority/state escaped $f"}
}
function Assert-RAIssuerDeniedV010($R,[string]$Label){Assert-RAIssuerFalse ([bool]$R.ok) "$Label unexpectedly issued";Assert-RAIssuerNoAuthorityV010 $R $Label}
function Test-RAIssuerPermitV010($R,$Q,[AllowNull()]$Bundle=$null,[AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][byte[]]$Key=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue){
    if($null-eq$Bundle){$Bundle=$Q.bundle};if($null-eq$Key){$Key=$script:RAIssuerKey};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.at};$ctx=New-RAIssueLiveContextV010 -Bundle $Bundle;if($null-eq$Baseline){$Baseline=$ctx.baseline};if($null-eq$ShadowQualification){$ShadowQualification=$ctx.shadow};if($null-eq$LiveQualification){$LiveQualification=$ctx.live}
    return Test-CustomAppProductionPermitV010 -Permit $R.permit -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -SessionKey $Key -Now $At
}

$count=0
$valid=New-RAReadyFixtureV010 -Label 'issuer-valid' -Nonce ('1'*32);$prior=New-RAIssuerPriorV010 $valid;$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior
Assert-RAIssuerTrue ([bool]$r.ok) ('valid issuer denied: '+[string]$r.reason);Assert-RAIssuerEq $r.reason 'recovery-aware-production-permit-created-requires-immediate-external-reservation' 'valid issuer reason';Assert-RAIssuerTrue ([bool]$r.permit_created) 'permit not created';Assert-RAIssuerTrue ([bool]$r.session_key_accepted) 'session key not accepted';Assert-RAIssuerTrue ([bool]$r.nonce_accepted) 'nonce not accepted';Assert-RAIssuerNoAuthorityV010 $r 'valid issuer'
$rc=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $r.receipt -Now $valid.at.AddSeconds(1);Assert-RAIssuerTrue ([bool]$rc.ok) ('issuer receipt invalid: '+[string]$rc.reason)
$pc=Test-RAIssuerPermitV010 -R $r -Q $valid;Assert-RAIssuerTrue ([bool]$pc.ok) ('created HMAC permit invalid: '+[string]$pc.reason);Assert-RAIssuerFalse ([bool]$pc.production_execution_authorized) 'permit validator granted execution';Assert-RAIssuerFalse ([bool]$pc.production_mutation_authorized) 'permit validator granted mutation';$count++

$wrong=Test-RAIssuerPermitV010 -R $r -Q $valid -Key $script:RAIssuerWrongKey;Assert-RAIssuerFalse ([bool]$wrong.ok) 'created permit accepted wrong key';Assert-RAIssuerEq $wrong.reason 'permit-hmac-mismatch' 'wrong-key reason';$count++

$future=New-RAReadyFixtureV010 -Label 'issuer-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32);$priorF=New-RAIssuerPriorV010 $future;$rf=Invoke-RAIssuerV010 -Q $future -Prior $priorF -Nonce ('2'*32);Assert-RAIssuerTrue ([bool]$rf.ok) ('future app issuer denied: '+[string]$rf.reason);Assert-RAIssuerEq $rf.receipt.name 'future-app' 'future app identity';Assert-RAIssuerNoAuthorityV010 $rf 'future app';$count++

$short=[byte[]](1..16);$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Key $short;Assert-RAIssuerDeniedV010 $r 'short session key';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-session-key-too-short' 'short-key reason';$count++
$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Nonce 'BAD';Assert-RAIssuerDeniedV010 $r 'bad nonce';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-nonce-must-be-exactly-32-lowercase-hex' 'bad nonce reason';$count++
$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Ttl 2;Assert-RAIssuerDeniedV010 $r 'wrong ttl';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-ttl-must-be-exactly-one-minute' 'ttl reason';$count++

$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -At $valid.at.AddSeconds(6);Assert-RAIssuerDeniedV010 $r 'expired prior admission';Assert-RAIssuerTrue ([string]$r.reason-like'recovery-aware-permit-issuer-prior-admission-invalid:*expired*') 'expired prior reason';$count++
$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Name 'other-app';Assert-RAIssuerDeniedV010 $r 'prior name mismatch';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-prior-admission-name-mismatch' 'name mismatch reason';$count++
$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Tx ('f'*64);Assert-RAIssuerDeniedV010 $r 'prior transaction mismatch';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-prior-admission-transaction-mismatch' 'tx mismatch reason';$count++

$removed=Copy-RAIssuer $valid.bundle;$removed.lifecycle.user_removed=$true;$removed.lifecycle.present=$false;$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Bundle $removed;Assert-RAIssuerDeniedV010 $r 'user removed after prior admission';Assert-RAIssuerTrue ([string]$r.reason-like'recovery-aware-permit-issuer-fresh-admission-denied:*') 'user removal did not fail fresh admission';$count++
$ctx=New-RAIssueLiveContextV010 -Bundle $valid.bundle;$driftBase=Copy-RAIssuer $ctx.baseline;$driftBase.tree_sha256=('8'*64);$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Baseline $driftBase;Assert-RAIssuerDeniedV010 $r 'baseline drift after prior admission';Assert-RAIssuerTrue ([string]$r.reason-like'recovery-aware-permit-issuer-fresh-admission-denied:*') 'baseline drift did not fail fresh admission';$count++

$remote=Copy-RAIssuer $valid.bundle;$remote.binding.last_remote_tree_sha256=('b'*64);$remote.binding.binding.last_verified_remote_tree_sha256=('b'*64);$remote.binding.last_remote_commit_sha=('c'*40);$remote.binding.binding.last_verified_commit_sha=('c'*40);[void](Sync-PromotionBundleFingerprints -Bundle $remote);$r=Invoke-RAIssuerV010 -Q $valid -Prior $prior -Bundle $remote;Assert-RAIssuerDeniedV010 $r 'remote drift after prior admission';Assert-RAIssuerTrue ([string]$r.reason-like'recovery-aware-permit-issuer-admission-continuity-*mismatch') ('remote drift continuity reason: '+[string]$r.reason);$count++

# The issuer must re-run admission after cryptographic permit creation. Forge only that second read.
$origResolve=(Get-Command Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock
$script:RAIssuerResolveCall=0;$script:RAIssuerFreshReceipt=Copy-RAIssuer $prior;$script:RAIssuerPostReceipt=Copy-RAIssuer $prior;$script:RAIssuerPostReceipt.current_remote_commit_sha=('d'*40);$script:RAIssuerPostReceipt.issuance_admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionMaterialV010 -Receipt $script:RAIssuerPostReceipt)
try{
    Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value {param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$StoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours);$script:RAIssuerResolveCall++;if($script:RAIssuerResolveCall-eq1){return [pscustomobject]@{ok=$true;reason='fixture-fresh';receipt=$script:RAIssuerFreshReceipt}};return [pscustomobject]@{ok=$true;reason='fixture-post';receipt=$script:RAIssuerPostReceipt}}
    $r=Invoke-RAIssuerV010 -Q $valid -Prior $prior
} finally {Set-Item -Path Function:\Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Value $origResolve;$script:RAIssuerResolveCall=0}
Assert-RAIssuerDeniedV010 $r 'post creation admission drift';Assert-RAIssuerEq $r.reason 'recovery-aware-permit-issuer-admission-drift-during-permit-creation' 'post creation drift reason';$count++

$good=Invoke-RAIssuerV010 -Q $valid -Prior $prior;Assert-RAIssuerTrue ([bool]$good.ok) 'receipt tamper setup failed'
$bad=Copy-RAIssuer $good.receipt;$bad.permit_reserved=$true;$bad.issuer_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1);Assert-RAIssuerFalse ([bool]$ck.ok) 'rehashed reserved receipt accepted';Assert-RAIssuerTrue ([string]$ck.reason-like'*authority-or-state-escaped-permit_reserved*') 'reserved receipt reason';$count++
$bad=Copy-RAIssuer $good.receipt;$bad.session_key_persisted=$true;$bad.issuer_fingerprint=Get-CustomAppProductionRecoveryAwarePermitIssuerSha256V010(Get-CustomAppProductionRecoveryAwarePermitIssuerMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1);Assert-RAIssuerFalse ([bool]$ck.ok) 'rehashed persisted-key receipt accepted';$count++
$bad=Copy-RAIssuer $good.receipt;$bad.issuer_fingerprint=('0'*64);$ck=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $bad -Now $valid.at.AddSeconds(1);Assert-RAIssuerFalse ([bool]$ck.ok) 'fingerprint-tampered issuer receipt accepted';Assert-RAIssuerEq $ck.reason 'recovery-aware-permit-issuer-fingerprint-mismatch' 'receipt fingerprint reason';$count++
$ck=Test-CustomAppProductionRecoveryAwarePermitIssuerReceiptV010 -Receipt $good.receipt -Now $valid.at.AddSeconds(6);Assert-RAIssuerFalse ([bool]$ck.ok) 'expired reservation window accepted';Assert-RAIssuerEq $ck.reason 'recovery-aware-permit-issuer-reservation-window-expired' 'reservation expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ISSUER_MATRIX_PASS total=$count"
