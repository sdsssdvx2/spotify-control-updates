$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Reuse and replay the exact validated durable-completion bridge fixture chain.
. (Join-Path $root 'validation/custom-app-production-recovery-completion-retirement-admission-integration-v0.1.0/test_custom_app_production_recovery_completion_retirement_admission_integration.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-artifact-retirement-resume-executor.ps1')

function Assert-RRTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RRFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RREq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RR($x){return(($x|ConvertTo-Json -Depth 90)|ConvertFrom-Json)}
function Assert-RRZeroAuthority($R,[string]$Label){$x=if($R.PSObject.Properties['result']){$R.result}else{$R};foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RRFalse ([bool]$x.$f) "$Label authority escaped $f"}}

$script:RRHookMode='none'
function Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:RRHookMode-ceq'crash-after-transaction' -and $Checkpoint-ceq'before-stage-retirement'){$script:RRHookMode='none';throw 'fixture-simulated-crash-after-transaction-retirement'}
}

function Invoke-RRResumeV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$F.ce.q.f.f.identity.transaction_id}
    return Invoke-CustomAppProductionRecoveryArtifactRetirementResumeExecutorV010 -AllowedRoot $F.ce.q.f.f.allowed -StoreDirectory $F.ce.q.f.f.store -ExpectedTransactionId $Tx -LocalAppDataRoot $F.ce.q.f.f.q.persistence.local -AppDataRoot $F.ce.q.f.f.q.persistence.roaming -Now $At
}
function Invoke-RRResumeProbeV010 {
    param([Parameter(Mandatory=$true)]$F)
    $probe=Join-Path $PSScriptRoot 'probe_custom_app_production_recovery_artifact_retirement_resume_executor.ps1'
    $raw=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -AllowedRoot $F.ce.q.f.f.allowed -StoreDirectory $F.ce.q.f.f.store -ExpectedTransactionId $F.ce.q.f.f.identity.transaction_id -LocalAppDataRoot $F.ce.q.f.f.q.persistence.local -AppDataRoot $F.ce.q.f.f.q.persistence.roaming)
    if($LASTEXITCODE){throw 'retirement resume separate-process probe failed'}
    return (($raw|Select-Object -Last 1)|ConvertFrom-Json)
}
function Assert-RRFinalAbsentV010($F,[string]$Label){$b=Invoke-CRBridgeV010 -F $F;Assert-RRTrue ([bool]$b.ok) "$Label final bridge denied: $([string]$b.reason)";Assert-RRFalse ([bool]$b.receipt.retirement_needed) "$Label retirement still needed";Assert-RRTrue ([bool]$b.receipt.retirement_already_complete) "$Label retirement not complete";foreach($f in @('transaction_status','stage_status','app_backup_status','persistence_backup_status')){Assert-RREq $b.receipt.$f 'already-absent' "$Label $f"}}

$count=0
$valid=New-CRFixtureV010 -Label 'resume-valid' -Nonce ('1'*32);$r=Invoke-RRResumeV010 $valid;Assert-RRTrue ([bool]$r.ok) ('valid resume denied: '+[string]$r.reason);$c=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $r.result;Assert-RRTrue ([bool]$c.ok) ('valid resume result invalid: '+[string]$c.reason);Assert-RRZeroAuthority $r 'valid';foreach($f in @('transaction_action','stage_action','app_backup_action','persistence_backup_action')){Assert-RREq $r.result.$f 'deleted-now' "valid $f"};Assert-RRTrue ([bool]$r.result.retirement_performed) 'valid retirement not performed';Assert-RRFalse ([bool]$r.result.initially_already_complete) 'valid incorrectly initially complete';Assert-RRTrue ([bool]$r.result.completion_evidence_retained) 'valid completion evidence not retained';Assert-RRTrue ([bool]$r.result.requires_new_update_permit) 'valid new permit contract missing';Assert-RRFinalAbsentV010 $valid 'valid';$count++

$probeCase=New-CRFixtureV010 -Label 'resume-probe' -Nonce ('2'*32);$probe=Invoke-RRResumeProbeV010 $probeCase;Assert-RRTrue ([bool]$probe.ok) 'separate-process resume probe denied';Assert-RRTrue ([bool]$probe.artifact_retirement_complete) 'separate-process retirement incomplete';Assert-RRTrue ([bool]$probe.durable_completion_reloaded_before) 'separate-process did not durable reload before';Assert-RRTrue ([bool]$probe.durable_completion_reloaded_after) 'separate-process did not durable reload after';Assert-RRTrue ([bool]$probe.completion_evidence_retained) 'separate-process completion evidence not retained';Assert-RRTrue ([bool]$probe.requires_new_update_permit) 'separate-process new permit contract missing';foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RRFalse ([bool]$probe.$f) "separate-process authority escaped $f"};Assert-RRFinalAbsentV010 $probeCase 'separate-process';$count++

$future=New-CRFixtureV010 -Label 'resume-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('3'*32);$r=Invoke-RRResumeV010 $future;Assert-RRTrue ([bool]$r.ok) ('future app resume denied: '+[string]$r.reason);Assert-RREq $r.result.name 'future-app' 'future app identity';Assert-RRFinalAbsentV010 $future 'future';$count++

$already=New-CRFixtureV010 -Label 'resume-already-complete' -Nonce ('4'*32);$pre=Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010 -AllowedRoot $already.ce.q.f.f.allowed -StoreDirectory $already.ce.q.f.f.store -ExpectedTransactionId $already.ce.q.f.f.identity.transaction_id -RestoreExecutorResult $already.ce.executor -LocalAppDataRoot $already.ce.q.f.f.q.persistence.local -AppDataRoot $already.ce.q.f.f.q.persistence.roaming -Now ([DateTimeOffset]::UtcNow);Assert-RRTrue ([bool]$pre.ok) ('already-complete setup failed: '+[string]$pre.reason);$r=Invoke-RRResumeV010 $already;Assert-RRTrue ([bool]$r.ok) ('already-complete resume denied: '+[string]$r.reason);Assert-RRTrue ([bool]$r.result.initially_already_complete) 'already-complete flag missing';Assert-RRFalse ([bool]$r.result.retirement_performed) 'already-complete resume mutated';foreach($f in @('transaction_action','stage_action','app_backup_action','persistence_backup_action')){Assert-RREq $r.result.$f 'already-absent' "already-complete $f"};$count++

$crash=New-CRFixtureV010 -Label 'resume-crash' -Nonce ('5'*32);$script:RRHookMode='crash-after-transaction';$first=Invoke-RRResumeV010 $crash;Assert-RRFalse ([bool]$first.ok) 'simulated retirement crash unexpectedly succeeded';Assert-RRTrue ([string]$first.reason-like'*bounded-executor-denied:*before-hook-failed-stage:*fixture-simulated-crash-after-transaction-retirement*') ('simulated crash reason '+[string]$first.reason);$partial=Invoke-CRBridgeV010 -F $crash;Assert-RRTrue ([bool]$partial.ok) ('partial restart bridge denied: '+[string]$partial.reason);Assert-RREq $partial.receipt.transaction_status 'already-absent' 'partial restart transaction status';Assert-RREq $partial.receipt.stage_status 'present-verified' 'partial restart stage status';$second=Invoke-RRResumeV010 $crash;Assert-RRTrue ([bool]$second.ok) ('partial restart resume denied: '+[string]$second.reason);Assert-RREq $second.result.transaction_action 'already-absent' 'partial restart transaction action';Assert-RREq $second.result.stage_action 'deleted-now' 'partial restart stage action';Assert-RRFinalAbsentV010 $crash 'partial-restart';$count++

$lockCase=New-CRFixtureV010 -Label 'resume-lock' -Nonce ('6'*32);$held=Open-CustomAppProductionRecoveryArtifactRetirementExecutorLockV010 -AllowedRoot $lockCase.ce.q.f.f.allowed -StoreDirectory $lockCase.ce.q.f.f.store;try{$r=Invoke-RRResumeV010 $lockCase}finally{$held.Dispose()};Assert-RRFalse ([bool]$r.ok) 'retirement executor lock contention accepted';Assert-RRTrue ([string]$r.reason-like'*bounded-executor-denied:*lock-busy*') ('lock reason '+[string]$r.reason);$afterLock=Invoke-RRResumeV010 $lockCase;Assert-RRTrue ([bool]$afterLock.ok) ('resume after lock release denied: '+[string]$afterLock.reason);$count++

$missing=New-CRFixtureV010 -Label 'resume-missing-completion' -Nonce ('7'*32) -WriteCompletion:$false;$r=Invoke-RRResumeV010 $missing;Assert-RRFalse ([bool]$r.ok) 'missing durable completion accepted by resume executor';Assert-RRTrue ([string]$r.reason-like'*initial-bridge-denied:*completion-read-denied:*file-missing*') ('missing completion reason '+[string]$r.reason);$count++

$drift=New-CRFixtureV010 -Label 'resume-live-drift' -Nonce ('8'*32);[IO.File]::AppendAllText((Join-Path $drift.ce.q.f.f.q.x.live 'index.js'),"// retirement resume live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-RRResumeV010 $drift;Assert-RRFalse ([bool]$r.ok) 'live drift accepted by resume executor';Assert-RRTrue ([string]$r.reason-like'*initial-bridge-denied:*fresh-admission-denied:*live-*') ('live drift reason '+[string]$r.reason);$count++

$wrong=New-CRFixtureV010 -Label 'resume-wrong-tx' -Nonce ('9'*32);$r=Invoke-RRResumeV010 -F $wrong -Tx ('f'*64);Assert-RRFalse ([bool]$r.ok) 'wrong transaction accepted by resume executor';Assert-RRTrue ([string]$r.reason-like'*initial-bridge-denied:*') ('wrong transaction reason '+[string]$r.reason);$count++

$tamper=Copy-RR $valid.result;$tamper.cleanup_authorized=$true;$tamper.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultMaterialV010 -Result $tamper);$c=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $tamper;Assert-RRFalse ([bool]$c.ok) 'authority-tampered resume result accepted';Assert-RRTrue ([string]$c.reason-like'*authority-escaped-cleanup_authorized*') ('authority tamper reason '+[string]$c.reason);$tamper=Copy-RR $valid.result;$tamper.result_fingerprint=('0'*64);$c=Test-CustomAppProductionRecoveryArtifactRetirementResumeExecutorResultV010 -Result $tamper;Assert-RRFalse ([bool]$c.ok) 'fingerprint-tampered resume result accepted';Assert-RREq $c.reason 'recovery-artifact-retirement-resume-executor-result-fingerprint-mismatch' 'fingerprint tamper reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ARTIFACT_RETIREMENT_RESUME_EXECUTOR_MATRIX_PASS total=$count"
