$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-spicetify-apply-executor.ps1')
function Assert-RAXTrue([bool]$v,[string]$m){if(-not$v){throw$m}}
function Assert-RAXFalse([bool]$v,[string]$m){if($v){throw$m}}
function Assert-RAXEq($a,$e,[string]$m){if([string]$a-cne[string]$e){throw"$m actual=<$a> expected=<$e>"}}
function Copy-RAX($o){return (($o|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}

$script:RAXMode='valid';$script:RAXFreshCalls=0;$script:RAXGenericCalls=0;$script:RAXPostCalls=0;$script:RAXRollbackCalls=0
function New-RAXFixtureV010 {
    $tx=('1'*64);$binding=('2'*64);$cons=('3'*64);$hist=('4'*64);$current=('5'*64);$stageFp=('6'*64);$prepFp=('7'*64);$atomicFp=('8'*64);$finalFp=('9'*64);$priorFp=('a'*64);$remote=('b'*64);$commit=('c'*40)
    $stage=[pscustomobject]@{result_fingerprint=$stageFp;historical_consumption_envelope_sha256=$hist;remote_tree_sha256=$remote}
    $prep=[pscustomobject]@{result_fingerprint=$prepFp;historical_consumption_envelope_sha256=$hist}
    $atomic=[pscustomobject]@{result_fingerprint=$atomicFp;historical_consumption_envelope_sha256=$hist;current_consumption_revision=1}
    $final=[pscustomobject]@{result_fingerprint=$finalFp;name='tagify';source_identity='owner/repo';transaction_id=$tx;github_repo_id=123;surface_kind='github';remote_commit_sha=$commit;binding_fingerprint=$binding;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;current_consumption_envelope_sha256=$current;current_consumption_revision=1}
    $prior=[pscustomobject]@{admission_fingerprint=$priorFp;name='tagify';source_identity='owner/repo';transaction_id=$tx;github_repo_id=123;surface_kind='github';remote_commit_sha=$commit;binding_fingerprint=$binding;consumption_id=$cons;historical_consumption_envelope_sha256=$hist;current_consumption_envelope_sha256=$current;current_consumption_revision=1;recovery_finalization_result_fingerprint=$finalFp;recovery_atomic_result_fingerprint=$atomicFp;recovery_pre_apply_result_fingerprint=$prepFp;recovery_stage_result_fingerprint=$stageFp}
    return [pscustomobject]@{tx=$tx;binding=$binding;cons=$cons;hist=$hist;current=$current;remote=$remote;commit=$commit;stage=$stage;prep=$prep;atomic=$atomic;final=$final;prior=$prior}
}
function Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 {param($Decision) if($script:RAXMode-ceq'prior-invalid'){[pscustomobject]@{ok=$false;reason='fixture-prior-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-prior-valid'}}}
function Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010 {
    param($RecoveryAwareFinalizationResult,$RecoveryAwareAtomicResult,$RecoveryAwarePreparedResult,$RecoveryAwareStageExecutorResult,$ConsumptionPersistenceResult,$Permit,$Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$AllowedRoot,$ConsumptionStoreDirectory,[byte[]]$SessionKey,$LocalAppDataRoot,$AppDataRoot,[DateTimeOffset]$Now,[int]$MaxRemoteObservationAgeHours)
    $script:RAXFreshCalls++;if($script:RAXMode-ceq'fresh-denied'){return [pscustomobject]@{ok=$false;reason='fixture-fresh-denied';decision=$null}}
    $d=Copy-RAX $script:RAXFixture.prior;$d.admission_fingerprint=('d'*64);if($script:RAXMode-ceq'fresh-lineage-drift'){$d.recovery_atomic_result_fingerprint=('e'*64)}
    [pscustomobject]@{ok=$true;reason='fixture-fresh-valid';decision=$d}
}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericStageResultV010 {param($RecoveryAwareResult) [pscustomobject]@{result_fingerprint=('1'*64)}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {param($Result) [pscustomobject]@{preparation_fingerprint=('2'*64)}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericFinalizationResultV010 {param($RecoveryAwareFinalizationResult,$RecoveryAwareAtomicResult,$GenericPreparedResult,$GenericStageResult) [pscustomobject]@{finalization_fingerprint=('3'*64)}}
function Test-CustomAppProductionStageExecutorResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-stage-valid'}}
function Test-CustomAppProductionPreApplyPreparedResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-prepared-valid'}}
function Test-CustomAppProductionTransactionFinalizationResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-final-valid'}}
function Invoke-CustomAppProductionSpicetifyApplyExecutorV010 {
    param($AllowedRoot,$StoreDirectory,$ExpectedConsumptionId,$Permit,$FinalizationResult,$PreparedResult,$StageExecutorResult,$Name,$LifecycleRow,$ProvenanceRow,$BindingRow,[byte[]]$SessionKey,$LocalAppDataRoot,$AppDataRoot,$SpicetifyExecutablePath,$ExpectedSpicetifySha256,[DateTimeOffset]$Now,[int]$MaxRemoteObservationAgeHours,[int]$TimeoutSeconds)
    $script:RAXGenericCalls++
    if($script:RAXMode-ceq'generic-denied'){return [pscustomobject]@{ok=$false;reason='fixture-generic-denied';spicetify_apply_executed=$false;rollback_attempted=$false;rollback_ok=$false;rollback_result=$null;result=$null}}
    if($script:RAXMode-ceq'generic-denied-after-rollback'){return [pscustomobject]@{ok=$false;reason='fixture-generic-denied-after-rollback';spicetify_apply_executed=$true;rollback_attempted=$true;rollback_ok=$true;rollback_result=[pscustomobject]@{ok=$true};result=$null}}
    $g=[pscustomobject]@{result_fingerprint=('f'*64);live_tree_sha256=('b'*64);remote_tree_sha256=('b'*64);preserved_git_tree_sha256=$null;persistence_fingerprint=('0'*64);spicetify_executable_sha256=('e'*64);primary_exit_code=0;primary_timed_out=$false;apply_started_at='2026-11-01T20:00:05Z';apply_finished_at='2026-11-01T20:00:06Z'}
    [pscustomobject]@{ok=$true;reason='fixture-generic-success';spicetify_apply_executed=$true;rollback_attempted=$false;rollback_ok=$false;rollback_result=$null;result=$g}
}
function Test-CustomAppProductionSpicetifyApplyResultV010 {param($Result) if($script:RAXMode-ceq'generic-result-invalid'){[pscustomobject]@{ok=$false;reason='fixture-generic-result-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-generic-result-valid'}}}
function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 {
    param($AtomicResult,$PreparedResult,$StageExecutorResult,$ConsumptionPersistenceResult,$AllowedRoot,$ConsumptionStoreDirectory,$Name)
    $script:RAXPostCalls++
    if($script:RAXMode-ceq'post-denied'){return [pscustomobject]@{ok=$false;reason='fixture-post-denied'}}
    $hist=$script:RAXFixture.hist;$env=$script:RAXFixture.current;$rev=1
    switch($script:RAXMode){'post-regression'{$rev=0};'post-envelope-drift'{$env=('d'*64)};'post-historical-drift'{$hist=('e'*64)};'post-unrelated-newer'{$env=('d'*64);$rev=2}}
    [pscustomobject]@{ok=$true;reason='fixture-post-valid';historical_envelope_sha256=$hist;current_envelope_sha256=$env;current_revision=$rev}
}
function Invoke-CustomAppProductionSpicetifyApplyRollbackV010 {
    param($Name,$PreparedResult,$LifecycleRow,$LocalAppDataRoot,$AppDataRoot,$SpicetifyExecutablePath,$ExpectedSpicetifySha256,[int]$TimeoutSeconds)
    $script:RAXRollbackCalls++;if($script:RAXMode-ceq'rollback-fails'){return [pscustomobject]@{ok=$false;reason='fixture-rollback-fails'}};return [pscustomobject]@{ok=$true;reason='fixture-rollback-ok'}
}
function Reset-RAX([string]$Mode,$F){$script:RAXMode=$Mode;$script:RAXFixture=$F;$script:RAXFreshCalls=0;$script:RAXGenericCalls=0;$script:RAXPostCalls=0;$script:RAXRollbackCalls=0}
function Invoke-RAX($F,[byte[]]$Key=([byte[]](1..32)),[int]$Timeout=10,[AllowNull()]$Prior=$null){if($null-eq$Prior){$Prior=$F.prior};Invoke-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorV010 -PriorRecoveryAwareAdmissionDecision $Prior -RecoveryAwareFinalizationResult $F.final -RecoveryAwareAtomicResult $F.atomic -RecoveryAwarePreparedResult $F.prep -RecoveryAwareStageExecutorResult $F.stage -ConsumptionPersistenceResult ([pscustomobject]@{}) -Permit ([pscustomobject]@{}) -Name 'tagify' -LifecycleRow ([pscustomobject]@{}) -ProvenanceRow ([pscustomobject]@{}) -BindingRow ([pscustomobject]@{}) -AllowedRoot 'allowed' -ConsumptionStoreDirectory 'store' -SessionKey $Key -LocalAppDataRoot 'local' -AppDataRoot 'roaming' -SpicetifyExecutablePath 'spicetify.exe' -ExpectedSpicetifySha256 ('e'*64) -Now ([DateTimeOffset]'2026-11-01T20:00:05Z') -TimeoutSeconds $Timeout}
function Assert-RAXNoAuthority($R,[string]$L){$x=if($R.PSObject.Properties['result']-and$null-ne$R.result){$R.result}else{$R};foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAXFalse ([bool]$x.$f) "$L escaped $f"}}

$count=0;$f=New-RAXFixtureV010
Reset-RAX 'valid' $f;$r=Invoke-RAX $f;Assert-RAXTrue ([bool]$r.ok) ('valid denied '+[string]$r.reason);Assert-RAXEq $script:RAXFreshCalls 1 'valid fresh count';Assert-RAXEq $script:RAXGenericCalls 1 'valid generic count';Assert-RAXEq $script:RAXPostCalls 1 'valid post count';Assert-RAXEq $script:RAXRollbackCalls 0 'valid rollback count';Assert-RAXTrue ([bool]$r.requires_post_apply_commit_cleanup 'valid cleanup flag');Assert-RAXNoAuthority $r 'valid';$vc=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 $r.result;Assert-RAXTrue ([bool]$vc.ok) ('valid result invalid '+[string]$vc.reason);$count++
$auth=Copy-RAX $r.result;$auth.production_mutation_authorized=$true;$auth.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultMaterialV010 $auth);$ac=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 $auth;Assert-RAXFalse ([bool]$ac.ok) 'rehashed authority tamper accepted';$count++
$fp=Copy-RAX $r.result;$fp.result_fingerprint=('0'*64);$fc=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 $fp;Assert-RAXFalse ([bool]$fc.ok) 'fingerprint tamper accepted';$count++

foreach($case in @('prior-invalid','fresh-denied','fresh-lineage-drift','generic-denied','generic-denied-after-rollback','generic-result-invalid','post-denied','post-regression','post-envelope-drift','post-historical-drift')){
    Reset-RAX $case $f;$x=Invoke-RAX $f;Assert-RAXFalse ([bool]$x.ok) "$case unexpectedly succeeded";Assert-RAXNoAuthority $x $case
    if($case-ceq'prior-invalid'){Assert-RAXEq $script:RAXFreshCalls 0 "$case fresh count";Assert-RAXEq $script:RAXGenericCalls 0 "$case generic count"}
    elseif($case-in@('fresh-denied','fresh-lineage-drift')){Assert-RAXEq $script:RAXFreshCalls 1 "$case fresh count";Assert-RAXEq $script:RAXGenericCalls 0 "$case generic count"}
    elseif($case-ceq'generic-denied'){Assert-RAXEq $script:RAXGenericCalls 1 "$case generic count";Assert-RAXEq $script:RAXRollbackCalls 0 "$case rollback count"}
    elseif($case-ceq'generic-denied-after-rollback'){Assert-RAXEq $script:RAXRollbackCalls 0 "$case wrapper duplicated rollback";Assert-RAXTrue ([bool]$x.rollback_attempted "$case rollback flag")}
    else{Assert-RAXEq $script:RAXGenericCalls 1 "$case generic count";Assert-RAXEq $script:RAXRollbackCalls 1 "$case rollback count";Assert-RAXTrue ([bool]$x.rollback_attempted "$case rollback flag")}
    $count++
}
Reset-RAX 'post-unrelated-newer' $f;$x=Invoke-RAX $f;Assert-RAXTrue ([bool]$x.ok) ('unrelated newer denied '+[string]$x.reason);Assert-RAXEq $x.result.current_consumption_revision 2 'unrelated newer revision';Assert-RAXEq $x.result.current_consumption_envelope_sha256 ('d'*64) 'unrelated newer envelope';Assert-RAXEq $script:RAXRollbackCalls 0 'unrelated newer rollback';$count++
Reset-RAX 'valid' $f;$x=Invoke-RAX -F $f -Key ([byte[]](1..31));Assert-RAXFalse ([bool]$x.ok) 'short key accepted';Assert-RAXEq $script:RAXFreshCalls 0 'short key fresh call';$count++
Reset-RAX 'valid' $f;$x=Invoke-RAX -F $f -Timeout 0;Assert-RAXFalse ([bool]$x.ok) 'invalid timeout accepted';Assert-RAXEq $script:RAXFreshCalls 0 'invalid timeout fresh call';$count++
Reset-RAX 'valid' $f;$bad=Copy-RAX $f.prior;$bad.recovery_atomic_result_fingerprint=('0'*64);$x=Invoke-RAX -F $f -Prior $bad;Assert-RAXFalse ([bool]$x.ok) 'prior continuity drift accepted';Assert-RAXEq $script:RAXFreshCalls 0 'prior drift fresh call';$count++
Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_SPICETIFY_APPLY_EXECUTOR_SYNTHETIC_PASS total=$count fresh_exactly_once=true generic_exactly_once=true post_recovery_ledger=true rollback_on_recovery_only_race=true zero_authority=true"
