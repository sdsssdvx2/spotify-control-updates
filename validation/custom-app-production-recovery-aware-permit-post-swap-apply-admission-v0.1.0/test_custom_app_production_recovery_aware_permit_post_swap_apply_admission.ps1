$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-post-swap-apply-admission.ps1')

function Assert-RAPSTrue([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Assert-RAPSFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPSEq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPS($Object){return (($Object|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}

$script:RAPSMode='valid';$script:RAPSLedgerCalls=0;$script:RAPSGenericCalls=0
function New-RAPSFixtureV010 {
    param([string]$Name='tagify')
    $hist=('a'*64);$current=('b'*64);$stageFp=('4'*64);$prepFp=('5'*64);$atomicFp=('6'*64);$finalFp=('8'*64);$tx=('1'*64);$cons=('c'*64);$binding=('f'*64);$remote=('2'*64);$commit=('d'*40)
    $stage=[pscustomobject]@{name=$Name;source_identity='owner/repo';transaction_id=$tx;github_repo_id=12345;surface_kind='github';remote_commit_sha=$commit;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;binding_fingerprint=$binding;remote_tree_sha256=$remote;result_fingerprint=$stageFp}
    $prepared=[pscustomobject]@{name=$Name;source_identity='owner/repo';transaction_id=$tx;github_repo_id=12345;surface_kind='github';remote_commit_sha=$commit;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;binding_fingerprint=$binding;recovery_stage_result_fingerprint=$stageFp;result_fingerprint=$prepFp}
    $atomic=[pscustomobject]@{name=$Name;source_identity='owner/repo';transaction_id=$tx;github_repo_id=12345;surface_kind='github';remote_commit_sha=$commit;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;current_consumption_envelope_sha256=$current;current_consumption_revision=1;binding_fingerprint=$binding;recovery_pre_mutation_admission_fingerprint=('7'*64);recovery_pre_apply_result_fingerprint=$prepFp;recovery_stage_result_fingerprint=$stageFp;result_fingerprint=$atomicFp}
    $final=[pscustomobject]@{name=$Name;source_identity='owner/repo';transaction_id=$tx;github_repo_id=12345;surface_kind='github';remote_commit_sha=$commit;binding_fingerprint=$binding;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;current_consumption_envelope_sha256=$current;current_consumption_revision=1;recovery_atomic_result_fingerprint=$atomicFp;recovery_pre_apply_result_fingerprint=$prepFp;recovery_stage_result_fingerprint=$stageFp;live_runtime_tree_sha256=$remote;persistence_fingerprint=('9'*64);result_fingerprint=$finalFp}
    return [pscustomobject]@{name=$Name;historical=$hist;current=$current;remote=$remote;binding=$binding;commit=$commit;stage=$stage;prepared=$prepared;atomic=$atomic;final=$final}
}

function Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultV010 {param($Result) if($script:RAPSMode-ceq'finalization-invalid'){[pscustomobject]@{ok=$false;reason='fixture-finalization-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-finalization-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 {param($Result) if($script:RAPSMode-ceq'atomic-invalid'){[pscustomobject]@{ok=$false;reason='fixture-atomic-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-atomic-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {param($Result) if($script:RAPSMode-ceq'prepared-invalid'){[pscustomobject]@{ok=$false;reason='fixture-prepared-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-prepared-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 {param($Result) if($script:RAPSMode-ceq'stage-invalid'){[pscustomobject]@{ok=$false;reason='fixture-stage-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-stage-valid'}}}

function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 {
    param($AtomicResult,$PreparedResult,$StageExecutorResult,$ConsumptionPersistenceResult,$AllowedRoot,$ConsumptionStoreDirectory,$Name)
    $script:RAPSLedgerCalls++
    if($script:RAPSMode-ceq'pre-ledger-denied' -and $script:RAPSLedgerCalls-eq1){return [pscustomobject]@{ok=$false;reason='fixture-pre-ledger-denied'}}
    if($script:RAPSMode-ceq'post-ledger-denied' -and $script:RAPSLedgerCalls-gt1){return [pscustomobject]@{ok=$false;reason='fixture-post-ledger-denied'}}
    $hist=('a'*64);$env=('b'*64);$rev=1
    switch($script:RAPSMode){
        'pre-regression' {if($script:RAPSLedgerCalls-eq1){$rev=0}}
        'pre-envelope-drift' {if($script:RAPSLedgerCalls-eq1){$env=('e'*64)}}
        'same-app-newer' {return [pscustomobject]@{ok=$false;reason='same-app-newer-consumption'}}
        'unrelated-newer-before' {$env=('e'*64);$rev=2}
        'post-regression' {if($script:RAPSLedgerCalls-eq1){$env=('e'*64);$rev=2}else{$env=('b'*64);$rev=1}}
        'post-envelope-drift' {if($script:RAPSLedgerCalls-gt1){$env=('e'*64)}}
        'ledger-race' {if($script:RAPSLedgerCalls-gt1){$env=('e'*64);$rev=2}}
        'historical-drift' {if($script:RAPSLedgerCalls-gt1){$hist=('f'*64)}}
    }
    [pscustomobject]@{ok=$true;reason='fixture-ledger-valid';historical_envelope_sha256=$hist;current_envelope_sha256=$env;current_revision=$rev;same_app_newer_consumption_absent=$true}
}

function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 {param($RecoveryAwareResult) [pscustomobject]@{result_fingerprint=('1'*64)}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {param($Result) [pscustomobject]@{preparation_fingerprint=('2'*64)}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 {param($RecoveryAwareFinalizationResult,$RecoveryAwareAtomicResult,$GenericPreparedResult,$GenericStageResult) [pscustomobject]@{finalization_fingerprint=('3'*64)}}
function Test-CustomAppProductionStageExecutorResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-stage-valid'}}
function Test-CustomAppProductionPreApplyPreparedResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-prepared-valid'}}
function Test-CustomAppProductionTransactionFinalizationResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-final-valid'}}
function Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 {param($Decision) [pscustomobject]@{ok=$true;reason='fixture-generic-decision-valid'}}
function Resolve-CustomAppProductionPostSwapApplyAdmissionV010 {
    param($AllowedRoot,$StoreDirectory,$ExpectedConsumptionId,$Permit,$FinalizationResult,$PreparedResult,$StageExecutorResult,$Name,$LifecycleRow,$ProvenanceRow,$BindingRow,[byte[]]$SessionKey,$LocalAppDataRoot,$AppDataRoot,[DateTimeOffset]$Now,[int]$MaxRemoteObservationAgeHours)
    $script:RAPSGenericCalls++
    if($script:RAPSMode-ceq'generic-denied'){return [pscustomobject]@{ok=$false;reason='fixture-generic-denied';decision=$null}}
    $env=if($script:RAPSMode-ceq'unrelated-newer-before'){('e'*64)}else{('b'*64)}
    if($script:RAPSMode-ceq'generic-envelope-mismatch'){$env=('e'*64)}
    $d=[pscustomobject]@{admission_fingerprint=('d'*64);live_tree_sha256=('2'*64);remote_tree_sha256=('2'*64);remote_commit_sha=('d'*40);binding_fingerprint=('f'*64);preserved_git_tree_sha256=$null;persistence_fingerprint=('9'*64);current_consumption_envelope_sha256=$env;evaluated_at='2026-11-01T20:00:03Z';apply_eligibility_expires_at='2026-11-01T20:00:13Z'}
    [pscustomobject]@{ok=$true;reason='fixture-generic-valid';decision=$d}
}

function Invoke-RAPSV010 {
    param($F,[AllowNull()]$Final=$null,[AllowNull()]$Atomic=$null,[AllowNull()]$Prepared=$null,[AllowNull()]$Stage=$null,[byte[]]$Key=([byte[]](1..32)))
    if($null-eq$Final){$Final=$F.final};if($null-eq$Atomic){$Atomic=$F.atomic};if($null-eq$Prepared){$Prepared=$F.prepared};if($null-eq$Stage){$Stage=$F.stage}
    Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010 -RecoveryAwareFinalizationResult $Final -RecoveryAwareAtomicResult $Atomic -RecoveryAwarePreparedResult $Prepared -RecoveryAwareStageExecutorResult $Stage -ConsumptionPersistenceResult ([pscustomobject]@{}) -Permit ([pscustomobject]@{}) -Name $F.name -LifecycleRow ([pscustomobject]@{}) -ProvenanceRow ([pscustomobject]@{}) -BindingRow ([pscustomobject]@{}) -AllowedRoot 'allowed' -ConsumptionStoreDirectory 'store' -SessionKey $Key -LocalAppDataRoot 'local' -AppDataRoot 'roaming' -Now ([DateTimeOffset]'2026-11-01T20:00:03Z')
}
function Reset-RAPSV010([string]$Mode){$script:RAPSMode=$Mode;$script:RAPSLedgerCalls=0;$script:RAPSGenericCalls=0}
function Assert-RAPSNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['decision']-and$null-ne$R.decision){$R.decision}else{$R};foreach($p in @('session_key_persisted','session_key_exposed','admission_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAPSFalse ([bool]$x.$p) "$Label escaped $p"}}

$count=0;$f=New-RAPSFixtureV010
Reset-RAPSV010 'valid';$r=Invoke-RAPSV010 $f;Assert-RAPSTrue ([bool]$r.ok) ('valid denied: '+[string]$r.reason);Assert-RAPSEq $script:RAPSGenericCalls 1 'valid generic call count';Assert-RAPSEq $script:RAPSLedgerCalls 2 'valid ledger call count';Assert-RAPSTrue ([bool]$r.apply_eligible -and [bool]$r.session_key_accepted) 'valid eligibility/key flags';Assert-RAPSNoAuthorityV010 $r 'valid';$check=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 $r.decision;Assert-RAPSTrue ([bool]$check.ok) ('valid decision check failed: '+[string]$check.reason);Assert-RAPSEq $r.decision.historical_consumption_envelope_sha256 $f.historical 'valid historical envelope';Assert-RAPSEq $r.decision.current_consumption_envelope_sha256 $f.current 'valid current envelope';$count++
$auth=Copy-RAPS $r.decision;$auth.production_mutation_authorized=$true;$auth.admission_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionMaterialV010 $auth);$ac=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 $auth;Assert-RAPSFalse ([bool]$ac.ok) 'rehashed authority escape accepted';$count++
$fp=Copy-RAPS $r.decision;$fp.admission_fingerprint=('0'*64);$fc=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 $fp;Assert-RAPSFalse ([bool]$fc.ok) 'decision fingerprint tamper accepted';$count++

foreach($case in @('finalization-invalid','atomic-invalid','prepared-invalid','stage-invalid','pre-ledger-denied','pre-regression','pre-envelope-drift','same-app-newer','generic-denied','post-ledger-denied','post-regression','post-envelope-drift','ledger-race','historical-drift','generic-envelope-mismatch')){
    Reset-RAPSV010 $case;$x=Invoke-RAPSV010 $f;Assert-RAPSFalse ([bool]$x.ok) "$case unexpectedly succeeded";Assert-RAPSNoAuthorityV010 $x $case
    if($case -in @('finalization-invalid','atomic-invalid','prepared-invalid','stage-invalid','pre-ledger-denied','pre-regression','pre-envelope-drift','same-app-newer')){Assert-RAPSEq $script:RAPSGenericCalls 0 "$case invoked generic admission"}else{Assert-RAPSEq $script:RAPSGenericCalls 1 "$case generic call count"}
    $count++
}

Reset-RAPSV010 'valid';$bad=Copy-RAPS $f.final;$bad.source_identity='other/repo';$x=Invoke-RAPSV010 -F $f -Final $bad;Assert-RAPSFalse ([bool]$x.ok) 'identity drift accepted';Assert-RAPSEq $script:RAPSGenericCalls 0 'identity drift invoked generic';$count++
Reset-RAPSV010 'valid';$bad=Copy-RAPS $f.final;$bad.recovery_atomic_result_fingerprint=('0'*64);$x=Invoke-RAPSV010 -F $f -Final $bad;Assert-RAPSFalse ([bool]$x.ok) 'atomic fingerprint continuity drift accepted';Assert-RAPSEq $script:RAPSGenericCalls 0 'fingerprint drift invoked generic';$count++
Reset-RAPSV010 'valid';$bad=Copy-RAPS $f.stage;$bad.historical_consumption_envelope_sha256=('0'*64);$x=Invoke-RAPSV010 -F $f -Stage $bad;Assert-RAPSFalse ([bool]$x.ok) 'historical envelope continuity drift accepted';Assert-RAPSEq $script:RAPSGenericCalls 0 'historical drift invoked generic';$count++
Reset-RAPSV010 'unrelated-newer-before';$x=Invoke-RAPSV010 $f;Assert-RAPSTrue ([bool]$x.ok) ('unrelated newer before generic denied: '+[string]$x.reason);Assert-RAPSEq $x.decision.current_consumption_revision 2 'unrelated newer revision';Assert-RAPSEq $x.decision.current_consumption_envelope_sha256 ('e'*64) 'unrelated newer envelope';Assert-RAPSNoAuthorityV010 $x 'unrelated-newer-before';$count++
Reset-RAPSV010 'valid';$x=Invoke-RAPSV010 -F $f -Key ([byte[]](1..31));Assert-RAPSFalse ([bool]$x.ok) 'short key accepted';Assert-RAPSEq $script:RAPSGenericCalls 0 'short key invoked generic';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_POST_SWAP_APPLY_ADMISSION_MATRIX_PASS total=$count generic_single_call=true ledger_double_read=true zero_authority=true"
