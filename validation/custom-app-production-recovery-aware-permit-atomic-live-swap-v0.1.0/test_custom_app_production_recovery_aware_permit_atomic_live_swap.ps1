$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')

function Assert-RAALTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAALFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAALEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAAL($Object){return (($Object|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}

$script:RAALKey=New-Object byte[] 32;for($i=0;$i -lt 32;$i++){$script:RAALKey[$i]=0x31}
$script:RAALMode='valid';$script:RAALRecoveryCalls=0;$script:RAALMutationCalls=0;$script:RAALRestoreCalls=0;$script:RAALCleanupCalls=0;$script:RAALLastMutationArgs=$null

function New-RAALStageV010 {
    [pscustomobject]@{name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';remote_commit_sha=('b'*40);consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);local_tree_sha256=('1'*64);remote_tree_sha256=('2'*64);result_fingerprint=('3'*64);stage_path='C:\fixture\stage';apply_authorized=$false}
}
function New-RAALPreparedV010 {
    [pscustomobject]@{name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';remote_commit_sha=('b'*40);consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);recovery_stage_result_fingerprint=('3'*64);app_backup_tree_sha256=('8'*64);app_backup_file_count=4;app_backup_total_bytes=1234;app_backup_path='C:\fixture\app-backup';persistence_backup_path='C:\fixture\persistence-backup';persistence_fingerprint=('9'*64);result_fingerprint=('0'*64);apply_authorized=$false}
}
function New-RAALPersistenceV010 {
    [pscustomobject]@{receipt=[pscustomobject]@{persisted_revision=1};persisted_snapshot=[pscustomobject]@{state=[pscustomobject]@{revision=1;consumptions=@([pscustomobject]@{name='tagify';consumption_id=('c'*64)})}}}
}
function New-RAALBindingV010 {[pscustomobject]@{ok=$true;reason='binding-ok';source='alexk218/tagify';surface='github';commit_sha=('b'*40);remote_tree_sha256=('2'*64);binding_fingerprint=('f'*64);repo_id=12345}}
function New-RAALReceiptV010 {[pscustomobject]@{managed_by='custom-app-production-recovery-aware-permit-stage-acquisition-admission-v1';name='tagify';source_identity='alexk218/tagify';transaction_id=('a'*64);github_repo_id=12345;surface_kind='github';consumption_id=('c'*64);consumption_persistence_fingerprint=('d'*64);historical_consumption_envelope_sha256=('e'*64);binding_fingerprint=('f'*64);admission_fingerprint=('4'*64)}}
function New-RAALMutationResultV010 {
    [pscustomobject]@{caller_admission_fingerprint=('4'*64);pre_live_runtime_tree_sha256=('6'*64);pre_live_full_tree_sha256=('8'*64);pre_stage_runtime_tree_sha256=('2'*64);old_live_tree_sha256=('8'*64);post_runtime_tree_sha256=('2'*64);result_fingerprint=('7'*64);live_path='C:\fixture\live';transaction_root='C:\fixture\.spotify-control-txn-11111111111111111111111111111111';old_live_path='C:\fixture\.spotify-control-txn-11111111111111111111111111111111\old-live';preserved_git_tree_sha256=$null;persistence_fingerprint=('9'*64)}
}

function Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 {param($Result) if($script:RAALMode -ceq 'stage-invalid' -or $null -eq $Result -or [string]$Result.result_fingerprint -cne ('3'*64)){[pscustomobject]@{ok=$false;reason='stage-invalid'}}else{[pscustomobject]@{ok=$true;reason='stage-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {param($Result) if($script:RAALMode -ceq 'prepared-invalid' -or $null -eq $Result -or [string]$Result.result_fingerprint -cne ('0'*64)){[pscustomobject]@{ok=$false;reason='prepared-invalid'}}else{[pscustomobject]@{ok=$true;reason='prepared-valid'}}}
function Test-CustomAppStageBindingRowV010 {param($BindingRow,[string]$ExpectedName) if($script:RAALMode -ceq 'binding-drift'){[pscustomobject]@{ok=$false;reason='binding-drift'}}else{New-RAALBindingV010}}
function Test-CustomAppProductionStageExecutorLiveBaselineV010 {param($LifecycleRow,$Permit,$BindingRow,[string]$Name) if($script:RAALMode -ceq 'stable-live-denied'){[pscustomobject]@{ok=$false;reason='stable-live-denied'}}else{[pscustomobject]@{ok=$true;reason='stable-live-valid';tree_sha256=('1'*64);baseline=[pscustomobject]@{tree_sha256=('1'*64)}}}}
function Get-CustomAppLocalRuntimeBaseline {param([string]$Name,[string]$AppPath) [pscustomobject]@{safe=$true;installable=$true;tree_sha256=('6'*64)}}
function Test-CustomAppLocalRuntimeBaselineMutationAuthority {param($Baseline) return $false}
function Get-CustomAppUpdateTreeSnapshotV010 {param([string]$Root) if($script:RAALMode -ceq 'byte-real-live-drift'){[pscustomobject]@{tree_sha256=('5'*64);file_count=4;total_bytes=1234}}else{[pscustomobject]@{tree_sha256=('8'*64);file_count=4;total_bytes=1234}}}
function Resolve-CustomAppProductionRecoveryAwarePermitStageAcquisitionAdmissionV010 {
    param($Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$StageResult,$ShadowResult,$RetirementResumeResult,$CurrentBaseline,$ShadowProtocolQualification,$LiveAttestedQualification,$AllowedRoot,$RecoveryStoreDirectory,$ConsumptionStoreDirectory,$ExpectedTransactionId,$LocalAppDataRoot,$AppDataRoot,$ConsumptionPersistenceResult,$Permit,[byte[]]$SessionKey,$Now,$MaxRemoteObservationAgeHours)
    $script:RAALRecoveryCalls++
    if($script:RAALMode -ceq 'recovery-denied' -or $SessionKey[0] -ne 0x31){return [pscustomobject]@{ok=$false;reason='recovery-denied';stage_acquisition_eligible=$false;receipt=$null}}
    [pscustomobject]@{ok=$true;reason='recovery-valid';stage_acquisition_eligible=$true;receipt=(New-RAALReceiptV010)}
}
function Test-CustomAppProductionRecoveryAwarePermitStageAdmissionReceiptV010 {param($Receipt,$Now) [pscustomobject]@{ok=$true;reason='receipt-valid'}}
function Invoke-CustomAppProductionAtomicLiveSwapMutationV010 {
    param($Name,$CallerAdmissionManagedBy,$CallerAdmissionFingerprint,$LivePath,$StagePath,$ExpectedLiveRuntimeTreeSha256,$ExpectedLiveFullTreeSha256,$ExpectedLiveFullFileCount,$ExpectedLiveFullTotalBytes,$ExpectedStageRuntimeTreeSha256,$AppBackupPath,$ExpectedAppBackupTreeSha256,$ExpectedAppBackupFileCount,$ExpectedAppBackupTotalBytes,$PersistenceBackupPath,$ExpectedPersistenceFingerprint,$LocalAppDataRoot,$AppDataRoot,$Now)
    $script:RAALMutationCalls++;$script:RAALLastMutationArgs=[pscustomobject]@{caller=$CallerAdmissionFingerprint;live_runtime=$ExpectedLiveRuntimeTreeSha256;live_full=$ExpectedLiveFullTreeSha256;stage=$ExpectedStageRuntimeTreeSha256;backup=$ExpectedAppBackupTreeSha256}
    if($script:RAALMode -ceq 'mutation-pre-denied'){return [pscustomobject]@{ok=$false;reason='fixture-mutation-pre-denied';mutation_started=$false;rollback_attempted=$false;rollback_ok=$false;transaction_root='C:\fixture\.spotify-control-txn-22222222222222222222222222222222'}}
    if($script:RAALMode -ceq 'mutation-rollback'){return [pscustomobject]@{ok=$false;reason='fixture-mutation-post-fault';mutation_started=$true;rollback_attempted=$true;rollback_ok=$true;rollback_result=[pscustomobject]@{ok=$true;reason='primitive-restored'};transaction_root='C:\fixture\.spotify-control-txn-33333333333333333333333333333333'}}
    [pscustomobject]@{ok=$true;reason='atomic-live-swap-mutation-verified-no-future-authority';result=(New-RAALMutationResultV010);mutation_started=$true;rollback_attempted=$false;rollback_ok=$false}
}
function Test-CustomAppProductionAtomicLiveSwapMutationResultV010 {param($Result) if($script:RAALMode -ceq 'mutation-result-invalid'){[pscustomobject]@{ok=$false;reason='mutation-result-invalid'}}else{[pscustomobject]@{ok=$true;reason='mutation-result-valid'}}}
function Invoke-CustomAppProductionRecoveryAwarePermitAtomicValidationHookV010 {param([string]$Checkpoint,$Context) if($script:RAALMode -ceq 'post-hook-fail'){throw 'fixture-post-hook-fail'}}
function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 {
    param($AllowedRoot,$StoreDirectory,$TargetState,$TargetRevision,$ExpectedConsumptionId)
    if($script:RAALMode -ceq 'historical-reload-fail'){return [pscustomobject]@{ok=$false;reason='fixture-historical-reload-fail'}}
    $rows=@([pscustomobject]@{name='tagify';consumption_id=('c'*64)})
    $rev=1;$currentEnvelope=('a'*64)
    if($script:RAALMode -ceq 'unrelated-newer'){$rows+= [pscustomobject]@{name='future-app';consumption_id=('5'*64)};$rev=2;$currentEnvelope=('b'*64)}
    if($script:RAALMode -ceq 'same-app-newer'){$rows+= [pscustomobject]@{name='tagify';consumption_id=('5'*64)};$rev=2;$currentEnvelope=('b'*64)}
    [pscustomobject]@{ok=$true;reason='persisted-target-valid';target_envelope=[pscustomobject]@{envelope_sha256=('e'*64)};current_envelope=[pscustomobject]@{envelope_sha256=$currentEnvelope};current_state=[pscustomobject]@{revision=$rev;consumptions=$rows};current_revision=$rev}
}
function Restore-CustomAppProductionRecoveryAwarePermitAtomicAfterWrapperFailureV010 {param($LivePath,$PreparedResult,$TransactionRoot,$LocalAppDataRoot,$AppDataRoot) $script:RAALRestoreCalls++;[pscustomobject]@{ok=$true;reason='fixture-wrapper-restore-ok'}}
function Remove-CustomAppProductionRecoveryAwarePermitAtomicTransactionV010 {param($TransactionRoot,$LivePath) $script:RAALCleanupCalls++;[pscustomobject]@{ok=$true;reason='fixture-cleanup-ok'}}

function Invoke-RAALCaseV010 {
    param([AllowNull()]$Stage=$null,[AllowNull()]$Prepared=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()]$Persistence=$null)
    if($null -eq $Stage){$Stage=New-RAALStageV010};if($null -eq $Prepared){$Prepared=New-RAALPreparedV010};if($null -eq $Key){$Key=$script:RAALKey};if($null -eq $Persistence){$Persistence=New-RAALPersistenceV010}
    Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 -RecoveryAwareStageExecutorResult $Stage -RecoveryAwarePreparedResult $Prepared -Name 'tagify' -LifecycleRow ([pscustomobject]@{locations=@('C:\fixture\live')}) -ProvenanceRow ([pscustomobject]@{}) -BindingRow ([pscustomobject]@{}) -LifecycleStageResult ([pscustomobject]@{}) -ShadowResult ([pscustomobject]@{}) -RetirementResumeResult ([pscustomobject]@{}) -ShadowProtocolQualification ([pscustomobject]@{}) -LiveAttestedQualification ([pscustomobject]@{}) -AllowedRoot 'C:\fixture\allowed' -RecoveryStoreDirectory 'C:\fixture\recovery' -ConsumptionStoreDirectory 'C:\fixture\consumption' -ExpectedTransactionId ('a'*64) -LocalAppDataRoot 'C:\fixture\local' -AppDataRoot 'C:\fixture\roaming' -ConsumptionPersistenceResult $Persistence -Permit ([pscustomobject]@{}) -SessionKey $Key -Now ([DateTimeOffset]'2026-11-01T00:00:00Z')
}
function Reset-RAALV010([string]$Mode){$script:RAALMode=$Mode;$script:RAALRecoveryCalls=0;$script:RAALMutationCalls=0;$script:RAALRestoreCalls=0;$script:RAALCleanupCalls=0;$script:RAALLastMutationArgs=$null}
function Assert-RAALNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['result'] -and $null -ne $R.result){$R.result}else{$R};foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALFalse ([bool]$x.$f) "$Label escaped $f"};Assert-RAALTrue ([bool]$x.requires_spicetify_apply_phase) "$Label lost apply-phase separation"}

$count=0
Reset-RAALV010 'valid';$valid=Invoke-RAALCaseV010
Assert-RAALTrue ([bool]$valid.ok) ('valid denied: '+[string]$valid.reason);Assert-RAALEq $script:RAALRecoveryCalls 1 'valid recovery admission count';Assert-RAALEq $script:RAALMutationCalls 1 'valid mutation count';Assert-RAALEq $script:RAALRestoreCalls 0 'valid unexpected restore';Assert-RAALTrue ([bool]$valid.result.byte_real_live_reverified -and [bool]$valid.result.historical_consumption_reverified_after_atomic -and [bool]$valid.result.same_app_newer_consumption_absent) 'valid evidence flags missing';Assert-RAALEq $script:RAALLastMutationArgs.live_runtime ('6'*64) 'actual runtime not passed to primitive';Assert-RAALEq $script:RAALLastMutationArgs.live_full ('8'*64) 'byte-real full tree not passed to primitive';Assert-RAALEq $script:RAALLastMutationArgs.stage ('2'*64) 'stage tree not passed to primitive';Assert-RAALEq $script:RAALLastMutationArgs.caller ('4'*64) 'recovery admission fingerprint not bound';Assert-RAALNoAuthorityV010 $valid 'valid';$c=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 $valid.result;Assert-RAALTrue ([bool]$c.ok) ('valid result validator: '+[string]$c.reason);$count++
$auth=Copy-RAAL $valid.result;$auth.production_mutation_authorized=$true;$auth.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitAtomicSha256V010 (Get-CustomAppProductionRecoveryAwarePermitAtomicResultMaterialV010 -Result $auth);$c=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 $auth;Assert-RAALFalse ([bool]$c.ok) 'rehashed authority escape accepted';$count++
$finger=Copy-RAAL $valid.result;$finger.result_fingerprint=('5'*64);$c=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 $finger;Assert-RAALFalse ([bool]$c.ok) 'result fingerprint tamper accepted';$count++

Reset-RAALV010 'stage-invalid';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'stage invalid accepted';Assert-RAALEq $script:RAALRecoveryCalls 0 'stage invalid reached recovery';Assert-RAALEq $script:RAALMutationCalls 0 'stage invalid reached mutation';$count++
Reset-RAALV010 'prepared-invalid';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'prepared invalid accepted';Assert-RAALEq $script:RAALMutationCalls 0 'prepared invalid reached mutation';$count++
Reset-RAALV010 'stable-live-denied';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'stable live denial accepted';Assert-RAALEq $script:RAALRecoveryCalls 0 'stable live denial reached recovery';Assert-RAALEq $script:RAALMutationCalls 0 'stable live denial reached mutation';$count++
Reset-RAALV010 'byte-real-live-drift';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'byte-real live drift accepted';Assert-RAALTrue ([string]$r.reason -like '*byte-real-live-backup-mismatch*') 'byte-real drift reason';Assert-RAALEq $script:RAALRecoveryCalls 0 'byte-real drift reached recovery';Assert-RAALEq $script:RAALMutationCalls 0 'byte-real drift reached mutation';$count++
Reset-RAALV010 'valid';$badKey=New-Object byte[] 32;for($i=0;$i -lt 32;$i++){$badKey[$i]=0x32};$r=Invoke-RAALCaseV010 -Key $badKey;Assert-RAALFalse ([bool]$r.ok) 'wrong key accepted';Assert-RAALEq $script:RAALRecoveryCalls 1 'wrong key recovery count';Assert-RAALEq $script:RAALMutationCalls 0 'wrong key reached mutation';$count++
Reset-RAALV010 'binding-drift';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'binding drift accepted';Assert-RAALEq $script:RAALMutationCalls 0 'binding drift reached mutation';$count++

Reset-RAALV010 'mutation-pre-denied';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'mutation pre-denial succeeded';Assert-RAALEq $script:RAALMutationCalls 1 'mutation pre-denial call count';Assert-RAALEq $script:RAALRestoreCalls 0 'pre-mutation denial restored unnecessarily';Assert-RAALEq $script:RAALCleanupCalls 1 'pre-mutation transaction cleanup count';Assert-RAALNoAuthorityV010 $r 'mutation pre-denial';$count++
Reset-RAALV010 'mutation-rollback';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'mutation rollback path succeeded';Assert-RAALTrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) 'primitive rollback evidence lost';Assert-RAALEq $script:RAALRestoreCalls 0 'wrapper duplicated verified primitive rollback';Assert-RAALEq $script:RAALCleanupCalls 1 'rollback transaction cleanup count';Assert-RAALNoAuthorityV010 $r 'mutation rollback';$count++
Reset-RAALV010 'historical-reload-fail';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'historical reload failure succeeded';Assert-RAALEq $script:RAALRestoreCalls 1 'historical reload failure did not restore';Assert-RAALTrue ([bool]$r.rollback_ok) 'historical reload wrapper rollback not verified';$count++
Reset-RAALV010 'same-app-newer';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'same-app newer consumption accepted';Assert-RAALTrue ([string]$r.reason -like '*same-app-newer-consumption*') 'same-app newer reason';Assert-RAALEq $script:RAALRestoreCalls 1 'same-app newer did not restore';$count++
Reset-RAALV010 'unrelated-newer';$r=Invoke-RAALCaseV010;Assert-RAALTrue ([bool]$r.ok) ('unrelated newer denied: '+[string]$r.reason);Assert-RAALEq $r.result.current_consumption_revision 2 'unrelated newer current revision';Assert-RAALEq $r.result.historical_consumption_envelope_sha256 ('e'*64) 'unrelated newer lost historical envelope';Assert-RAALEq $r.result.current_consumption_envelope_sha256 ('b'*64) 'unrelated newer current envelope';Assert-RAALEq $script:RAALRestoreCalls 0 'unrelated newer unexpectedly restored';$count++
Reset-RAALV010 'post-hook-fail';$r=Invoke-RAALCaseV010;Assert-RAALFalse ([bool]$r.ok) 'post hook failure succeeded';Assert-RAALEq $script:RAALRestoreCalls 1 'post hook failure did not restore';Assert-RAALTrue ([bool]$r.rollback_ok) 'post hook rollback not verified';$count++

if($count -ne 15){throw "recovery-aware bounded atomic wrapper matrix count drifted: $count != 15"}
Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_WRAPPER_MATRIX_PASS count=$count recovery_admission_exactly_once=true bounded_mutation_exactly_once=true stable_and_byte_real_views_separated=true historical_append_supported=true same_app_newer_fail_closed=true wrapper_rollback_verified=true zero_apply_authority=true"
