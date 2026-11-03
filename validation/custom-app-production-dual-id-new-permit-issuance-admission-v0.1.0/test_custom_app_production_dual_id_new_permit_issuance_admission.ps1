$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay qualified parent matrices and reuse their fixture constructors.
. (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-readiness-v0.1.0/test_custom_app_production_dual_id_new_permit_readiness.ps1')
. (Join-Path $root 'validation/custom-app-live-attested-production-admission-v0.1.0/test_custom_app_live_attested_production_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-new-permit-issuance-admission.ps1')

function Assert-DINPIATrue([bool]$v,[string]$m){if(-not$v){throw$m}}
function Assert-DINPIAFalse([bool]$v,[string]$m){if($v){throw$m}}
function Assert-DINPIAEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw"$m actual=<$a> expected=<$b>"}}
function Copy-DINPIA($x){return(($x|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}
function Get-DINPIANewTransactionId([string]$Label){return Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010('next-permit-transaction|'+$Label)}
function Assert-DINPIAZeroAuthority($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']-and$null-ne$R.receipt){$R.receipt}else{$R};foreach($f in @('issuance_admission_is_authority','permit_issued','session_key_accepted','nonce_reserved','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-DINPIAFalse([bool]$x.$f)"$Label authority escaped $f"}}}
function Assert-DINPIADenied($R,[string]$Label){Assert-DINPIAFalse([bool]$R.ok)"$Label unexpectedly admitted";Assert-DINPIAZeroAuthority $R $Label}

function New-DINPIAFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    $q=New-DINPFixtureV010 ('issuance-'+$Label)
    $prior=Invoke-DINPV010 $q
    Assert-DINPIATrue([bool]$prior.ok)("$Label parent readiness denied: $([string]$prior.reason)")
    $manifest=[string]$q.bundle.binding.binding.manifest_name
    $live=New-AdmissionFixture -Name ([string]$q.bundle.lifecycle.name) -Source ([string]$q.bundle.provenance.source_identity) -Manifest $manifest
    $live.lifecycle=$q.bundle.lifecycle;$live.provenance=$q.bundle.provenance;$live.binding=$q.bundle.binding
    $live.baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=[string]$q.house.result.live_runtime_tree_sha256;manifest_name=$manifest;path=[string]$q.x.f.x.fixture.q.x.live}
    return[pscustomobject]@{q=$q;prior=$prior.receipt;live=$live;new_id=(Get-DINPIANewTransactionId $Label)}
}
function Invoke-DINPIAV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()]$Bundle=$null,[AllowNull()]$HousekeepingResult=$null,[AllowNull()]$PriorReadinessReceipt=$null,[AllowNull()][string]$HistoricalPermitId=$null,[AllowNull()][string]$HistoricalJournalId=$null,[AllowNull()][string]$NewPermitId=$null,[AllowNull()]$CurrentBaseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    if($null-eq$Bundle){$Bundle=$F.q.bundle};if($null-eq$HousekeepingResult){$HousekeepingResult=$F.q.house.result};if($null-eq$PriorReadinessReceipt){$PriorReadinessReceipt=$F.prior};if([string]::IsNullOrWhiteSpace($HistoricalPermitId)){$HistoricalPermitId=[string]$F.q.house.result.permit_transaction_id};if([string]::IsNullOrWhiteSpace($HistoricalJournalId)){$HistoricalJournalId=[string]$F.q.house.result.journal_transaction_id};if([string]::IsNullOrWhiteSpace($NewPermitId)){$NewPermitId=[string]$F.new_id};if($null-eq$CurrentBaseline){$CurrentBaseline=$F.live.baseline};if($null-eq$ShadowQualification){$ShadowQualification=$F.live.shadow};if($null-eq$LiveQualification){$LiveQualification=$F.live.live};if($At-eq[DateTimeOffset]::MinValue){$At=$F.q.at}
    return Resolve-CustomAppProductionDualIdNewPermitIssuanceAdmissionV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -HousekeepingResult $HousekeepingResult -AllowedRoot $F.q.x.f.trust -StoreDirectory $F.q.x.f.store -HistoricalPermitTransactionId $HistoricalPermitId -HistoricalJournalTransactionId $HistoricalJournalId -NewPermitTransactionId $NewPermitId -LocalAppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$F.q.x.f.x.fixture.q.persistence.roaming) -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -PriorReadinessReceipt $PriorReadinessReceipt -Now $At
}

$count=0
$valid=New-DINPIAFixtureV010 'valid';$r=Invoke-DINPIAV010 $valid;Assert-DINPIATrue([bool]$r.ok)('valid issuance admission denied: '+[string]$r.reason);Assert-DINPIATrue([bool]$r.receipt.permit_issuance_eligible)'valid eligibility false';Assert-DINPIATrue([bool]$r.receipt.transaction_id_namespaces_pairwise_distinct)'valid namespaces not distinct';Assert-DINPIAEq $r.receipt.new_permit_transaction_id $valid.new_id 'valid new transaction id';Assert-DINPIAFalse(([string]$r.receipt.new_permit_transaction_id)-ceq([string]$r.receipt.historical_permit_transaction_id))'new id reused historical permit id';Assert-DINPIAFalse(([string]$r.receipt.new_permit_transaction_id)-ceq([string]$r.receipt.historical_journal_transaction_id))'new id reused journal id';Assert-DINPIAZeroAuthority $r 'valid';$ck=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $r.receipt -Now $valid.q.at.AddSeconds(1);Assert-DINPIATrue([bool]$ck.ok)('valid receipt invalid: '+[string]$ck.reason);$validReceipt=Copy-DINPIA $r.receipt;$count++

$reusePermit=New-DINPIAFixtureV010 'reuse-permit';$r=Invoke-DINPIAV010 -F $reusePermit -NewPermitId ([string]$reusePermit.q.house.result.permit_transaction_id);Assert-DINPIADenied $r 'reuse historical permit';Assert-DINPIAEq $r.reason 'dual-id-new-permit-issuance-admission-new-transaction-id-reused' 'reuse permit reason';$count++
$reuseJournal=New-DINPIAFixtureV010 'reuse-journal';$r=Invoke-DINPIAV010 -F $reuseJournal -NewPermitId ([string]$reuseJournal.q.house.result.journal_transaction_id);Assert-DINPIADenied $r 'reuse journal';Assert-DINPIAEq $r.reason 'dual-id-new-permit-issuance-admission-new-transaction-id-reused' 'reuse journal reason';$count++
$badNew=New-DINPIAFixtureV010 'bad-new';$r=Invoke-DINPIAV010 -F $badNew -NewPermitId 'bad';Assert-DINPIADenied $r 'bad new id';Assert-DINPIAEq $r.reason 'dual-id-new-permit-issuance-admission-new-permit-transaction-id-invalid' 'bad new id reason';$count++

$priorTamper=New-DINPIAFixtureV010 'prior-tamper';$bad=Copy-DINPIA $priorTamper.prior;$bad.permit_issued=$true;$bad.readiness_fingerprint=Get-CustomAppProductionDualIdNewPermitReadinessSha256V010(Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $bad);$r=Invoke-DINPIAV010 -F $priorTamper -PriorReadinessReceipt $bad;Assert-DINPIADenied $r 'prior readiness authority tamper';Assert-DINPIATrue([string]$r.reason-like'*prior-readiness-invalid:*authority-escaped-permit_issued*')'prior tamper reason';$count++

$priorId=New-DINPIAFixtureV010 'prior-id';$bad=Copy-DINPIA $priorId.prior;$bad.permit_transaction_id=('9'*64);$bad.readiness_fingerprint=Get-CustomAppProductionDualIdNewPermitReadinessSha256V010(Get-CustomAppProductionDualIdNewPermitReadinessMaterialV010 $bad);$r=Invoke-DINPIAV010 -F $priorId -PriorReadinessReceipt $bad;Assert-DINPIADenied $r 'prior id drift';Assert-DINPIAEq $r.reason 'dual-id-new-permit-issuance-admission-prior-readiness-identity-mismatch' 'prior id reason';$count++

$liveDrift=New-DINPIAFixtureV010 'live-drift';$baseline=Copy-DINPIA $liveDrift.live.baseline;$baseline.tree_sha256=('8'*64);$r=Invoke-DINPIAV010 -F $liveDrift -CurrentBaseline $baseline;Assert-DINPIADenied $r 'live admission runtime drift';Assert-DINPIATrue([string]$r.reason-like'dual-id-new-permit-issuance-admission-live-admission-denied:*')'live drift reason';$count++

$liveQualification=New-DINPIAFixtureV010 'live-qualification';$q=Copy-DINPIA $liveQualification.live.live;$q.production_mutation_authorized=$true;$r=Invoke-DINPIAV010 -F $liveQualification -LiveQualification $q;Assert-DINPIADenied $r 'live qualification authority drift';Assert-DINPIATrue([string]$r.reason-like'*live-admission-denied:*')'live qualification reason';$count++

$remote=New-DINPIAFixtureV010 'remote-drift';$b=Copy-DINPIA $remote.q.bundle;$b.binding.last_remote_tree_sha256=('7'*64);$b.binding.binding.last_verified_remote_tree_sha256=('7'*64);$b.binding.last_remote_commit_sha=('6'*40);$b.binding.binding.last_verified_commit_sha=('6'*40);[void](Sync-PromotionBundleFingerprints $b);$r=Invoke-DINPIAV010 -F $remote -Bundle $b;Assert-DINPIADenied $r 'remote changed after prior readiness';Assert-DINPIATrue([string]$r.reason-like'dual-id-new-permit-issuance-admission-readiness-continuity-mismatch-*')'remote drift continuity reason';$count++

$prov=New-DINPIAFixtureV010 'provenance-drift';$b=Copy-DINPIA $prov.q.bundle;$b.provenance.evidence_fingerprint=('4'*64);$b.shadow.fresh_provenance_fingerprint=('4'*64);$r=Invoke-DINPIAV010 -F $prov -Bundle $b;Assert-DINPIADenied $r 'provenance changed after prior readiness';$count++

$receiptTamper=Copy-DINPIA $validReceipt;$receiptTamper.permit_issued=$true;$receiptTamper.issuance_admission_fingerprint=Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionSha256V010(Get-CustomAppProductionDualIdNewPermitIssuanceAdmissionMaterialV010 $receiptTamper);$c=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $receiptTamper -Now $valid.q.at.AddSeconds(1);Assert-DINPIAFalse([bool]$c.ok)'permit-issued issuance receipt tamper accepted';Assert-DINPIATrue([string]$c.reason-like'*authority-escaped-permit_issued*')'issuance receipt authority reason';$count++
$c=Test-CustomAppProductionDualIdNewPermitIssuanceAdmissionReceiptV010 -Receipt $validReceipt -Now $valid.q.at.AddSeconds(6);Assert-DINPIAFalse([bool]$c.ok)'expired issuance receipt accepted';Assert-DINPIAEq $c.reason 'dual-id-new-permit-issuance-admission-receipt-expired' 'expired receipt reason';$count++

if($count-ne12){throw"dual-ID new permit issuance admission matrix count mismatch $count"}
Write-Host"CUSTOM_APP_PRODUCTION_DUAL_ID_NEW_PERMIT_ISSUANCE_ADMISSION_MATRIX_PASS cases=$count historical_ids_preserved=true new_permit_id_distinct=true permit_issued=false zero_authority=true"
