$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-issuance-admission-v0.1.0/test_custom_app_production_dual_id_new_permit_issuance_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-issuer.ps1')

function Assert-DINPITrue([bool]$v,[string]$m){if(-not $v){throw $m}}
function Assert-DINPIFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-DINPIEq($a,$b,[string]$m){if([string]$a -cne [string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-DINPI($x){return (($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

$script:DINPIKey=[byte[]](1..32)
$script:DINPIWrongKey=[byte[]](33..64)
$script:DINPINonce='0123456789abcdef0123456789abcdef'

function New-DINPIIssuerFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    $f=New-DINPIAFixtureV010 ('permit-issuer-'+$Label)
    $a=Invoke-DINPIAV010 $f
    Assert-DINPITrue ([bool]$a.ok) ("$Label issuance admission setup denied: $([string]$a.reason)")
    return [pscustomobject]@{f=$f;admission=$a.receipt}
}
function Invoke-DINPIIssuerV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()]$Bundle=$null,[AllowNull()]$HousekeepingResult=$null,[AllowNull()]$PriorReadinessReceipt=$null,[AllowNull()]$IssuanceAdmissionReceipt=$null,[AllowNull()][string]$HistoricalPermitId=$null,[AllowNull()][string]$HistoricalJournalId=$null,[AllowNull()][string]$NewPermitId=$null,[AllowNull()]$CurrentBaseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()][string]$Nonce=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue,[int]$Ttl=1)
    $F=$Q.f
    if($null -eq $Bundle){$Bundle=$F.q.bundle};if($null -eq $HousekeepingResult){$HousekeepingResult=$F.q.house.result};if($null -eq $PriorReadinessReceipt){$PriorReadinessReceipt=$F.prior};if($null -eq $IssuanceAdmissionReceipt){$IssuanceAdmissionReceipt=$Q.admission}
    if([string]::IsNullOrWhiteSpace($HistoricalPermitId)){$HistoricalPermitId=[string]$F.q.house.result.permit_transaction_id};if([string]::IsNullOrWhiteSpace($HistoricalJournalId)){$HistoricalJournalId=[string]$F.q.house.result.journal_transaction_id};if([string]::IsNullOrWhiteSpace($NewPermitId)){$NewPermitId=[string]$F.new_id}
    if($null -eq $CurrentBaseline){$CurrentBaseline=$F.live.baseline};if($null -eq $ShadowQualification){$ShadowQualification=$F.live.shadow};if($null -eq $LiveQualification){$LiveQualification=$F.live.live};if($null -eq $Key){$Key=$script:DINPIKey};if([string]::IsNullOrWhiteSpace($Nonce)){$Nonce=$script:DINPINonce};if($At -eq [DateTimeOffset]::MinValue){$At=$F.q.at}
    return Invoke-CustomAppProductionDualIdNewPermitIssuerV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -HousekeepingResult $HousekeepingResult -AllowedRoot $F.q.x.f.trust -StoreDirectory $F.q.x.f.store -HistoricalPermitTransactionId $HistoricalPermitId -HistoricalJournalTransactionId $HistoricalJournalId -NewPermitTransactionId $NewPermitId -LocalAppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.roaming) -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -PriorReadinessReceipt $PriorReadinessReceipt -IssuanceAdmissionReceipt $IssuanceAdmissionReceipt -SessionKey $Key -Nonce $Nonce -Now $At -TtlMinutes $Ttl
}
function Assert-DINPIZeroAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt'] -and $null -ne $R.receipt){$R.receipt}else{$R};foreach($f in @('session_key_persisted','session_key_exposed','nonce_reserved','permit_reserved','permit_consumed','issuer_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-DINPIFalse ([bool]$x.$f) "$Label escaped $f"}}}
function Assert-DINPIDeniedV010($R,[string]$Label){Assert-DINPIFalse ([bool]$R.ok) "$Label unexpectedly issued";Assert-DINPIZeroAuthorityV010 $R $Label}
function Test-DINPIGenericPermitV010($Q,$R,[AllowNull()][byte[]]$Key=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue){$F=$Q.f;if($null -eq $Key){$Key=$script:DINPIKey};if($At -eq [DateTimeOffset]::MinValue){$At=$F.q.at};return Test-CustomAppProductionPermitV010 -Permit $R.permit -Name ([string]$F.q.bundle.lifecycle.name) -LifecycleRow $F.q.bundle.lifecycle -ProvenanceRow $F.q.bundle.provenance -BindingRow $F.q.bundle.binding -CurrentBaseline $F.live.baseline -ShadowProtocolQualification $F.live.shadow -LiveAttestedQualification $F.live.live -SessionKey $Key -Now $At}

$count=0
$valid=New-DINPIIssuerFixtureV010 'valid';$r=Invoke-DINPIIssuerV010 $valid
Assert-DINPITrue ([bool]$r.ok) ('valid issuer denied: '+[string]$r.reason);Assert-DINPIEq $r.reason 'dual-id-new-production-permit-created-transaction-bound-requires-immediate-external-reservation' 'valid issuer reason';Assert-DINPITrue ([bool]$r.permit_created) 'permit not created';Assert-DINPITrue ([bool]$r.transaction_binding_created) 'transaction binding not created';Assert-DINPITrue ([bool]$r.receipt.transaction_binding_verified) 'binding verified flag false';Assert-DINPIEq $r.receipt.new_permit_transaction_id $valid.f.new_id 'new permit transaction id';Assert-DINPIZeroAuthorityV010 $r 'valid issuer'
$rc=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $r.receipt -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPITrue ([bool]$rc.ok) ('valid issuer receipt invalid: '+[string]$rc.reason)
$pc=Test-DINPIGenericPermitV010 -Q $valid -R $r;Assert-DINPITrue ([bool]$pc.ok) ('generic permit invalid: '+[string]$pc.reason);Assert-DINPIFalse ($null -ne $r.permit.PSObject.Properties['transaction_id']) 'generic permit format unexpectedly gained transaction_id';$validResult=$r;$count++

$wrong=Test-DINPIGenericPermitV010 -Q $valid -R $validResult -Key $script:DINPIWrongKey;Assert-DINPIFalse ([bool]$wrong.ok) 'generic permit accepted wrong key';Assert-DINPIEq $wrong.reason 'permit-hmac-mismatch' 'generic wrong key reason';$count++
$wrongBinding=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $validResult.receipt -SessionKey $script:DINPIWrongKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPIFalse ([bool]$wrongBinding.ok) 'transaction binding accepted wrong key';Assert-DINPIEq $wrongBinding.reason 'dual-id-new-permit-issuer-transaction-binding-hmac-mismatch' 'binding wrong key reason';$count++

$short=New-DINPIIssuerFixtureV010 'short-key';$r=Invoke-DINPIIssuerV010 -Q $short -Key ([byte[]](1..16));Assert-DINPIDeniedV010 $r 'short key';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-session-key-too-short' 'short key reason';$count++
$badNonce=New-DINPIIssuerFixtureV010 'bad-nonce';$r=Invoke-DINPIIssuerV010 -Q $badNonce -Nonce 'BAD';Assert-DINPIDeniedV010 $r 'bad nonce';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-nonce-must-be-exactly-32-lowercase-hex' 'bad nonce reason';$count++
$badTtl=New-DINPIIssuerFixtureV010 'bad-ttl';$r=Invoke-DINPIIssuerV010 -Q $badTtl -Ttl 2;Assert-DINPIDeniedV010 $r 'bad ttl';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-ttl-must-be-exactly-one-minute' 'bad ttl reason';$count++

$expired=New-DINPIIssuerFixtureV010 'expired';$r=Invoke-DINPIIssuerV010 -Q $expired -At $expired.f.q.at.AddSeconds(6);Assert-DINPIDeniedV010 $r 'expired prior issuance admission';Assert-DINPITrue ([string]$r.reason -like 'dual-id-new-permit-issuer-prior-admission-invalid:*expired*') ('expired reason '+[string]$r.reason);$count++

$txMismatch=New-DINPIIssuerFixtureV010 'tx-mismatch';$otherTx=Get-DINPIANewTransactionId 'other-cycle';$r=Invoke-DINPIIssuerV010 -Q $txMismatch -NewPermitId $otherTx;Assert-DINPIDeniedV010 $r 'new transaction mismatch';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-prior-admission-transaction-mismatch' 'new tx mismatch reason';$count++

$readinessMismatch=New-DINPIIssuerFixtureV010 'readiness-mismatch';$mismatchedPrior=Copy-DINPI $readinessMismatch.f.prior;$mismatchedPrior.current_remote_commit_sha=('9'*40);$mismatchedPrior.readiness_fingerprint=Get-CustomAppProductionDualIdNewPermitReadinessSha256V010 (Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $mismatchedPrior);$r=Invoke-DINPIIssuerV010 -Q $readinessMismatch -PriorReadinessReceipt $mismatchedPrior;Assert-DINPIDeniedV010 $r 'prior readiness mismatch';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-prior-readiness-fingerprint-mismatch' 'prior readiness mismatch reason';$count++

$liveDrift=New-DINPIIssuerFixtureV010 'live-drift';$baseline=Copy-DINPI $liveDrift.f.live.baseline;$baseline.tree_sha256=('8'*64);$r=Invoke-DINPIIssuerV010 -Q $liveDrift -CurrentBaseline $baseline;Assert-DINPIDeniedV010 $r 'live drift after admission';Assert-DINPITrue ([string]$r.reason -like 'dual-id-new-permit-issuer-fresh-admission-denied:*') ('live drift reason '+[string]$r.reason);$count++

# A plain receipt re-hash must not let an attacker transplant the permit into another transaction namespace.
$tampered=Copy-DINPI $validResult.receipt;$tampered.new_permit_transaction_id=Get-DINPIANewTransactionId 'binding-transplant';$tampered.issuer_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $tampered);$c=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $tampered -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPIFalse ([bool]$c.ok) 'rehashed transaction transplant accepted';Assert-DINPIEq $c.reason 'dual-id-new-permit-issuer-transaction-binding-hmac-mismatch' 'transaction transplant reason';$count++
$tampered=Copy-DINPI $validResult.receipt;$tampered.permit_token_id=('f'*64);$tampered.issuer_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $tampered);$c=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $tampered -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPIFalse ([bool]$c.ok) 'rehashed token transplant accepted';Assert-DINPIEq $c.reason 'dual-id-new-permit-issuer-transaction-binding-hmac-mismatch' 'token transplant reason';$count++
$tampered=Copy-DINPI $validResult.receipt;$tampered.transaction_binding_hmac_sha256=('0'*64);$tampered.issuer_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $tampered);$c=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $tampered -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPIFalse ([bool]$c.ok) 'binding HMAC tamper accepted';Assert-DINPIEq $c.reason 'dual-id-new-permit-issuer-transaction-binding-hmac-mismatch' 'binding tamper reason';$count++
$tampered=Copy-DINPI $validResult.receipt;$tampered.permit_reserved=$true;$tampered.issuer_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuerSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuerReceiptMaterialV010 -Receipt $tampered);$c=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $tampered -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(1);Assert-DINPIFalse ([bool]$c.ok) 'reserved state tamper accepted';Assert-DINPITrue ([string]$c.reason -like '*authority-or-state-escaped-permit_reserved*') 'reserved state reason';$count++

# Force only the post-creation admission to drift after the HMAC permit has been created.
$postDrift=New-DINPIIssuerFixtureV010 'post-drift';$orig=(Get-Command Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -CommandType Function).ScriptBlock;$script:DINPICall=0;$script:DINPIFresh=Copy-DINPI $postDrift.admission;$script:DINPIPost=Copy-DINPI $postDrift.admission;$script:DINPIPost.current_remote_commit_sha=('d'*40);$script:DINPIPost.issuance_admission_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010 (Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionMaterialV010 $script:DINPIPost)
try {
    Set-Item -Path Function:\Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Value {param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$HousekeepingResult,$AllowedRoot,$StoreDirectory,$HistoricalPermitTransactionId,$HistoricalJournalTransactionId,$NewPermitTransactionId,$LocalAppDataRoot,$AppDataRoot,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$PriorReadinessReceipt,$Now,$MaxRemoteObservationAgeHours);$script:DINPICall++;if($script:DINPICall -eq 1){return [pscustomobject]@{ok=$true;reason='fixture-fresh';receipt=$script:DINPIFresh}};return [pscustomobject]@{ok=$true;reason='fixture-post';receipt=$script:DINPIPost}}
    $r=Invoke-DINPIIssuerV010 $postDrift
} finally {Set-Item -Path Function:\Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Value $orig;$script:DINPICall=0}
Assert-DINPIDeniedV010 $r 'post creation admission drift';Assert-DINPIEq $r.reason 'dual-id-new-permit-issuer-admission-drift-during-permit-creation' 'post creation drift reason';$count++

$c=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $validResult.receipt -SessionKey $script:DINPIKey -Now $valid.f.q.at.AddSeconds(6);Assert-DINPIFalse ([bool]$c.ok) 'expired reservation window accepted';Assert-DINPIEq $c.reason 'dual-id-new-permit-issuer-reservation-window-expired' 'reservation expiry reason';$count++

if($count -ne 16){throw "dual-ID new permit issuer matrix count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_DUAL_ID_NEW_PERMIT_ISSUER_MATRIX_PASS cases=$count generic_permit_unchanged=true transaction_binding_hmac=true transaction_transplant_denied=true token_transplant_denied=true session_key_not_persisted=true permit_unreserved=true zero_authority=true"