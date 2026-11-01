$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$CustomAppProductionAtomicLiveSwapSchema=1
$CustomAppProductionAtomicLiveSwapManagedBy='custom-app-production-atomic-live-swap-v1'
$CustomAppProductionAtomicLiveSwapQualifiedPreApplyHead='ddc84778ab4815d4174198727b8d1d052a02182e'
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')

function Assert-RAALTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAALFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAALEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAAL($Object){return (($Object|ConvertTo-Json -Depth 50)|ConvertFrom-Json)}

$script:RAALKey=New-Object byte[] 32
for($i=0;$i -lt 32;$i++){$script:RAALKey[$i]=0x31}
$script:RAALMode='valid'
$script:RAALRecoveryCalls=0
$script:RAALAtomicCalls=0

function New-RAALStageV010 {
    [pscustomobject]@{name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';remote_commit_sha=('b'*40);consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);local_tree_sha256=('1'*64);remote_tree_sha256=('2'*64);result_fingerprint=('3'*64);apply_authorized=$false}
}
function New-RAALPreparedV010 {
    [pscustomobject]@{name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';remote_commit_sha=('b'*40);consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);recovery_stage_result_fingerprint=('3'*64);recovery_post_backup_admission_fingerprint=('4'*64);generic_stage_result_fingerprint=('5'*64);generic_preparation_fingerprint=('6'*64);generic_pre_apply_admission_fingerprint=('7'*64);live_tree_sha256=('1'*64);stage_tree_sha256=('2'*64);app_backup_tree_sha256=('8'*64);app_backup_path='C:\fixture\app-backup';persistence_backup_path='C:\fixture\persistence-backup';persistence_fingerprint=('9'*64);result_fingerprint=('0'*64);apply_authorized=$false}
}
function New-RAALBindingV010 {[pscustomobject]@{ok=$true;reason='binding-ok';source='alexk218/tagify';surface='github';commit_sha=('b'*40);remote_tree_sha256=('2'*64);binding_fingerprint=('f'*64);repo_id=12345}}
function New-RAALReceiptV010 {[pscustomobject]@{name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);admission_fingerprint=('a'*64)}}
function New-RAALGenericStageV010 {[pscustomobject]@{name='tagify';remote_tree_sha256=('2'*64);result_fingerprint=('5'*64)}}
function New-RAALGenericPreparedV010 {[pscustomobject]@{stage_tree_sha256=('2'*64);preparation_fingerprint=('6'*64);pre_apply_admission_fingerprint=('7'*64);app_backup_path='C:\fixture\app-backup';app_backup_tree_sha256=('8'*64);persistence_backup_path='C:\fixture\persistence-backup';persistence_fingerprint=('9'*64)}}

function Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 {param($Result) if($null -eq $Result -or [string]$Result.result_fingerprint -cne ('3'*64) -or [bool]$Result.apply_authorized){[pscustomobject]@{ok=$false;reason='stage-invalid'}}else{[pscustomobject]@{ok=$true;reason='stage-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {param($Result) if($null -eq $Result -or [string]$Result.result_fingerprint -cne ('0'*64) -or [bool]$Result.apply_authorized){[pscustomobject]@{ok=$false;reason='prepared-invalid'}}else{[pscustomobject]@{ok=$true;reason='prepared-valid'}}}
function Test-CustomAppStageBindingRowV010 {param($BindingRow,[string]$ExpectedName) if($null -ne $BindingRow -and $BindingRow.PSObject.Properties['bad'] -and [bool]$BindingRow.bad){[pscustomobject]@{ok=$false;reason='binding-drift'}}else{New-RAALBindingV010}}
function Test-CustomAppProductionStageExecutorLiveBaselineV010 {param($LifecycleRow,$Permit,$BindingRow,[string]$Name) if($script:RAALMode -ceq 'live-drift'){[pscustomobject]@{ok=$false;reason='live-drift'}}else{[pscustomobject]@{ok=$true;reason='live-valid';tree_sha256=('1'*64);baseline=[pscustomobject]@{tree_sha256=('1'*64)}}}}
function Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 {
    param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$RecoveryStoreDirectory,$ConsumptionStoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$ConsumptionPersistenceResult,$Permit,[byte[]]$SessionKey,$Now,$MaxRemoteObservationAgeHours)
    $script:RAALRecoveryCalls++
    if($script:RAALMode -ceq 'recovery-denied' -or $SessionKey[0] -ne 0x31){return [pscustomobject]@{ok=$false;reason='recovery-denied';stage_acquisition_eligible=$false;receipt=$null}}
    [pscustomobject]@{ok=$true;reason='recovery-valid';stage_acquisition_eligible=$true;receipt=(New-RAALReceiptV010)}
}
function Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 {param($Receipt,$Now) if($script:RAALMode -ceq 'receipt-invalid'){[pscustomobject]@{ok=$false;reason='receipt-invalid'}}else{[pscustomobject]@{ok=$true;reason='receipt-valid'}}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 {param($RecoveryAwareResult) New-RAALGenericStageV010}
function Test-CustomAppProductionStageExecutorResultV010 {param($Result) if($script:RAALMode -ceq 'generic-stage-invalid'){[pscustomobject]@{ok=$false;reason='generic-stage-invalid'}}else{[pscustomobject]@{ok=$true;reason='generic-stage-valid'}}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {param($Result) New-RAALGenericPreparedV010}
function Test-CustomAppProductionPreApplyPreparedResultV010 {param($Result) if($script:RAALMode -ceq 'generic-prepared-invalid'){[pscustomobject]@{ok=$false;reason='generic-prepared-invalid'}}else{[pscustomobject]@{ok=$true;reason='generic-prepared-valid'}}}
function Invoke-CustomAppProductionAtomicLiveSwapV010 {
    param($AllowedRoot,$StoreDirectory,$ExpectedConsumptionId,$StageExecutorResult,$PreparedResult,$Permit,$Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$ShadowProtocolQualification,$LiveAttestedQualification,[byte[]]$SessionKey,$LocalAppDataRoot,$AppDataRoot,$Now,$MaxRemoteObservationAgeHours)
    $script:RAALAtomicCalls++
    if($script:RAALMode -ceq 'atomic-rollback'){return [pscustomobject]@{ok=$false;reason='atomic-swap-failed-rolled-back:fixture';rollback_attempted=$true;rollback_ok=$true;rollback_result=[pscustomobject]@{ok=$true;reason='app-and-persistence-restored-exactly'}}}
    [pscustomobject]@{ok=$true;reason='atomic-live-code-swap-verified-no-spicetify-apply';schema=1;managed_by='custom-app-production-atomic-live-swap-v1';qualified_pre_apply_head='ddc84778ab4815d4174198727b8d1d052a02182e';name='tagify';live_path='C:\fixture\live';transaction_root='C:\fixture\.spotify-control-txn-1';old_live_path='C:\fixture\.spotify-control-txn-1\old-live';fresh_admission_fingerprint=('b'*64);post_runtime_tree_sha256=('2'*64);persistence_fingerprint=('9'*64);rollback_attempted=$false;rollback_ok=$false;live_code_swap_performed=$true;requires_transaction_workspace_cleanup=$true;requires_spicetify_apply_phase=$true;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_mutation_authorized=$false}
}

function Invoke-RAALCaseV010 {
    param($Stage,$Prepared,$Binding,[byte[]]$Key)
    if($null -eq $Stage){$Stage=New-RAALStageV010};if($null -eq $Prepared){$Prepared=New-RAALPreparedV010};if($null -eq $Binding){$Binding=[pscustomobject]@{}};if($null -eq $Key){$Key=$script:RAALKey}
    Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 -RecoveryAwareStageExecutorResult $Stage -RecoveryAwarePreparedResult $Prepared -Name 'tagify' -LifecycleRow ([pscustomobject]@{}) -ProvenanceRow ([pscustomobject]@{}) -BindingRow $Binding -LifecycleStageResult ([pscustomobject]@{}) -ShadowResult ([pscustomobject]@{}) -RetirementResumeResult ([pscustomobject]@{}) -ShadowProtocolQualification ([pscustomobject]@{}) -LiveAttestedQualification ([pscustomobject]@{}) -AllowedRoot 'C:\fixture\allowed' -RecoveryStoreDirectory 'C:\fixture\recovery' -ConsumptionStoreDirectory 'C:\fixture\consumption' -ExpectedTransactionId ('a'*64) -LocalAppDataRoot 'C:\fixture\local' -AppDataRoot 'C:\fixture\roaming' -ConsumptionPersistenceResult ([pscustomobject]@{}) -Permit ([pscustomobject]@{}) -SessionKey $Key -Now ([DateTimeOffset]'2026-11-01T00:00:00Z')
}
function Assert-RAALNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['result'] -and $null -ne $R.result){$R.result}else{$R};foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALFalse ([bool]$x.$f) "$Label escaped $f"};Assert-RAALTrue ([bool]$x.requires_spicetify_apply_phase) "$Label lost apply requirement"}

$count=0
$script:RAALMode='valid';$script:RAALRecoveryCalls=0;$script:RAALAtomicCalls=0
$r=Invoke-RAALCaseV010
Assert-RAALTrue ([bool]$r.ok) ('valid denied '+[string]$r.reason);Assert-RAALEq $r.reason 'recovery-aware-atomic-live-code-swap-verified-zero-apply-authority' 'valid reason';Assert-RAALTrue ([bool]$r.recovery_revalidated_immediately_before_atomic) 'valid recovery revalidation missing';Assert-RAALTrue ([bool]$r.result.requires_transaction_finalization) 'valid finalization requirement missing';Assert-RAALNoAuthorityV010 $r 'valid';Assert-RAALEq $script:RAALRecoveryCalls 1 'valid recovery call count';Assert-RAALEq $script:RAALAtomicCalls 1 'valid atomic call count';$check=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $r.result;Assert-RAALTrue ([bool]$check.ok) ('valid result validator '+[string]$check.reason);$count++
$auth=Copy-RAAL $r.result;$auth.spicetify_apply_authorized=$true;$auth.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicResultMaterialV010 -Result $auth);$c=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $auth;Assert-RAALFalse ([bool]$c.ok) 'rehashed authority result accepted';$count++
$finger=Copy-RAAL $r.result;$finger.result_fingerprint=('f'*64);$c=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $finger;Assert-RAALFalse ([bool]$c.ok) 'fingerprint tamper accepted';$count++
$badStage=New-RAALStageV010;$badStage.result_fingerprint=('f'*64);$r=Invoke-RAALCaseV010 -Stage $badStage;Assert-RAALFalse ([bool]$r.ok) 'stage tamper accepted';Assert-RAALTrue ([string]$r.reason -like 'recovery-aware-atomic-stage-result-invalid:*') 'stage tamper reason';$count++
$badPrepared=New-RAALPreparedV010;$badPrepared.result_fingerprint=('f'*64);$r=Invoke-RAALCaseV010 -Prepared $badPrepared;Assert-RAALFalse ([bool]$r.ok) 'prepared tamper accepted';Assert-RAALTrue ([string]$r.reason -like 'recovery-aware-atomic-prepared-result-invalid:*') 'prepared tamper reason';$count++
$script:RAALMode='live-drift';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'live drift accepted';Assert-RAALTrue ([string]$r.reason -like 'recovery-aware-atomic-live-revalidation-denied:*') 'live drift reason';$count++
$script:RAALMode='valid';$badKey=New-Object byte[] 32;for($i=0;$i -lt 32;$i++){$badKey[$i]=0x32};$r=Invoke-RAALCaseV010 -Key $badKey;Assert-RAALFalse ([bool]$r.ok) 'wrong key accepted';Assert-RAALTrue ([string]$r.reason -like 'recovery-aware-atomic-pre-mutation-admission-denied:*') 'wrong key reason';$count++
$badBinding=[pscustomobject]@{bad=$true};$r=Invoke-RAALCaseV010 -Binding $badBinding;Assert-RAALFalse ([bool]$r.ok) 'binding drift accepted';Assert-RAALTrue ([string]$r.reason -like 'recovery-aware-atomic-binding-denied:*') 'binding drift reason';$count++
$script:RAALMode='generic-stage-invalid';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'generic stage invalid accepted';Assert-RAALEq $script:RAALAtomicCalls 1 'atomic invoked after generic-stage-invalid';$count++
$script:RAALMode='atomic-rollback';$script:RAALAtomicCalls=0;$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'rollback failure path succeeded';Assert-RAALTrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) 'rollback evidence not propagated';Assert-RAALNoAuthorityV010 $r 'rollback';Assert-RAALEq $script:RAALAtomicCalls 1 'rollback atomic call count';$count++
if($count -ne 10){throw "recovery-aware atomic wrapper matrix count drifted: $count"}
Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_WRAPPER_MATRIX_PASS count=$count recovery_admission_exactly_once=true generic_atomic_exactly_once=true rollback_evidence_preserved=true spicetify_apply_authorized=false production_mutation_authorized=false"
