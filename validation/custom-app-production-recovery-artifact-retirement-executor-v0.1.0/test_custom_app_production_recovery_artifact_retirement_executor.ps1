$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-artifact-retirement-admission-v0.1.0/test_custom_app_production_recovery_artifact_retirement_admission_v011.ps1')
. (Join-Path $root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-artifact-retirement-executor.ps1')

function AX-T([bool]$v,[string]$m){if(-not $v){throw $m}}
function AX-F([bool]$v,[string]$m){if($v){throw $m}}
function AX-E($a,$b,[string]$m){if([string]$a -cne [string]$b){throw "$m actual=<$a> expected=<$b>"}}
function AX-C($x){return (($x|ConvertTo-Json -Depth 70)|ConvertFrom-Json)}
function Invoke-AX($x,[AllowNull()]$restore=$null,[DateTimeOffset]$at=[DateTimeOffset]::UtcNow){
    if($null-eq $restore){$restore=$x.restore}
    return Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010 -AllowedRoot $x.q.f.f.allowed -StoreDirectory $x.q.f.f.store -ExpectedTransactionId ([string]$x.q.f.f.identity.transaction_id) -RestoreExecutorResult $restore -LocalAppDataRoot $x.q.f.f.q.persistence.local -AppDataRoot $x.q.f.f.q.persistence.roaming -Now $at
}
function Assert-AXZero($r,[string]$m){$x=if($r.PSObject.Properties['result']){$r.result}else{$r};foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){AX-F ([bool]$x.$f) "$m authority escaped $f"}}
function Assert-AXSuccess($r,[string]$m){AX-T ([bool]$r.ok) "$m denied: $([string]$r.reason)";Assert-AXZero $r $m;$c=Test-CustomAppProductionRecoveryArtifactRetirementExecutorResultV010 -Result $r.result;AX-T ([bool]$c.ok) "$m result invalid: $([string]$c.reason)";AX-T ([bool]$r.result.artifact_retirement_complete) "$m incomplete";AX-T ([bool]$r.result.journal_retained) "$m journal not retained";AX-T ([bool]$r.result.recovery_evidence_retained) "$m evidence not retained";AX-T ([bool]$r.result.requires_new_update_permit) "$m new permit contract missing"}
function Assert-AXArtifactsAbsent($x,[string]$m){
    AX-F (Test-Path -LiteralPath ([string]$x.q.f.f.txn)) "$m transaction remained"
    AX-F (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.stage_workspace_path)) "$m stage remained"
    AX-F (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$x.q.f.f.prepared.app_backup_path))) "$m app backup remained"
    AX-F (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.persistence_backup_path)) "$m persistence backup remained"
    AX-T (Test-Path -LiteralPath ([string]$x.q.f.f.store)) "$m journal store removed"
    AX-T (Test-Path -LiteralPath ([string]$x.q.f.f.q.x.live)) "$m live removed"
}

$script:AXHookMode='';$script:AXHookPath=''
function Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:AXHookMode){
        'delete-transaction-before' {if($Checkpoint -ceq 'before-transaction-retirement' -and (Test-Path -LiteralPath $script:AXHookPath)){[IO.Directory]::Delete($script:AXHookPath,$true)}}
        'mutate-stage-before' {if($Checkpoint -ceq 'before-stage-retirement'){[IO.File]::AppendAllText((Join-Path $script:AXHookPath 'stage\index.js'),"// retirement race drift`n",[Text.UTF8Encoding]::new($false))}}
        'crash-after-transaction' {if($Checkpoint -ceq 'after-transaction-retirement'){throw 'injected-crash-after-transaction'}}
        'crash-after-stage' {if($Checkpoint -ceq 'after-stage-retirement'){throw 'injected-crash-after-stage'}}
        'crash-after-app' {if($Checkpoint -ceq 'after-app_backup-retirement'){throw 'injected-crash-after-app'}}
        'crash-after-persistence' {if($Checkpoint -ceq 'after-persistence_backup-retirement'){throw 'injected-crash-after-persistence'}}
        'live-drift-after-stage' {if($Checkpoint -ceq 'after-stage-retirement'){[IO.File]::AppendAllText((Join-Path $script:AXHookPath 'index.js'),"// post-partial live drift`n",[Text.UTF8Encoding]::new($false))}}
    }
}
function Reset-AXHook {$script:AXHookMode='';$script:AXHookPath=''}

$count=0

$x=New-AR 'executor-full' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('1'*32);$r=Invoke-AX $x;Assert-AXSuccess $r 'full';Assert-AXArtifactsAbsent $x 'full';AX-T ([bool]$r.result.retirement_performed) 'full did not report retirement';$count++

$x=New-AR 'executor-partial' -nonce ('2'*32);D ([string]$x.q.f.f.txn);D ([string]$x.q.f.f.prepared.stage_workspace_path);$r=Invoke-AX $x;Assert-AXSuccess $r 'partial';Assert-AXArtifactsAbsent $x 'partial';AX-E $r.result.transaction_action 'already-absent' 'partial txn action';AX-E $r.result.stage_action 'already-absent' 'partial stage action';$count++

$x=New-AR 'executor-complete' -nonce ('3'*32);D ([string]$x.q.f.f.txn);D ([string]$x.q.f.f.prepared.stage_workspace_path);D ([IO.Path]::GetDirectoryName([string]$x.q.f.f.prepared.app_backup_path));D ([string]$x.q.f.f.prepared.persistence_backup_path);$r=Invoke-AX $x;Assert-AXSuccess $r 'already-complete';AX-T ([bool]$r.result.initially_already_complete) 'already-complete marker missing';AX-F ([bool]$r.result.retirement_performed) 'already-complete mutated';Assert-AXArtifactsAbsent $x 'already-complete';$count++

$x=New-AR 'executor-future' 'live-moved-to-old' 'live-moved-before-candidate' 'future-app' 'owner/future-app' 'Future App' ('4'*32);$r=Invoke-AX $x;Assert-AXSuccess $r 'future';AX-E $r.result.name 'future-app' 'future identity';Assert-AXArtifactsAbsent $x 'future';$count++

$x=New-AR 'executor-lock' -nonce ('5'*32);$held=Open-CustomAppProductionRecoveryArtifactRetirementExecutorLockV010 -AllowedRoot $x.q.f.f.allowed -StoreDirectory $x.q.f.f.store;try{$r=Invoke-AX $x}finally{$held.Dispose()};AX-F ([bool]$r.ok) 'lock contention accepted';AX-E $r.reason 'recovery-artifact-retirement-executor-lock-busy' 'lock reason';AX-T (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.stage_workspace_path)) 'lock contention mutated stage';$count++

$x=New-AR 'executor-result-tamper' -nonce ('6'*32);$bad=AX-C $x.restore;$bad.cleanup_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 $bad);$r=Invoke-AX $x $bad;AX-F ([bool]$r.ok) 'authority-polluted restore result accepted';AX-T ([string]$r.reason -like '*restore-result-invalid:*authority-escaped-cleanup_authorized*') ('restore result tamper reason '+[string]$r.reason);$count++

$x=New-AR 'executor-live-drift' -nonce ('7'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.q.x.live 'index.js'),"// pre-retirement live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AX $x;AX-F ([bool]$r.ok) 'pre-retirement live drift accepted';AX-T ([string]$r.reason -like '*initial-admission-denied:*live-*') ('live drift reason '+[string]$r.reason);AX-T (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.stage_workspace_path)) 'live drift deleted artifacts';$count++

$x=New-AR 'executor-race-delete' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('8'*32);$script:AXHookMode='delete-transaction-before';$script:AXHookPath=[string]$x.q.f.f.txn;$r=Invoke-AX $x;Reset-AXHook;Assert-AXSuccess $r 'race-delete';AX-E $r.result.transaction_action 'already-absent' 'race delete txn action';Assert-AXArtifactsAbsent $x 'race-delete';$count++

$x=New-AR 'executor-stage-race' -nonce ('9'*32);$script:AXHookMode='mutate-stage-before';$script:AXHookPath=[string]$x.q.f.f.prepared.stage_workspace_path;$r=Invoke-AX $x;Reset-AXHook;AX-F ([bool]$r.ok) 'stage drift race accepted';AX-T ([string]$r.reason -like '*pre-delete-admission-denied-stage:*stage-state-invalid:*') ('stage race reason '+[string]$r.reason);AX-T (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.stage_workspace_path)) 'drifted stage was deleted';$count++

foreach($case in @(
    @('crash-after-transaction','live-moved-to-old','live-moved-before-candidate','a'),
    @('crash-after-stage','transaction-finalized','finalized','b'),
    @('crash-after-app','transaction-finalized','finalized','c'),
    @('crash-after-persistence','transaction-finalized','finalized','d')
)){
    $label=[string]$case[0];$x=New-AR ('executor-'+$label) ([string]$case[1]) ([string]$case[2]) -nonce (([string]$case[3])*32);$script:AXHookMode=$label;$r=Invoke-AX $x;Reset-AXHook;AX-F ([bool]$r.ok) "$label unexpectedly succeeded";AX-T ([string]$r.reason -like '*hook-failed*') "$label reason $([string]$r.reason)";$r2=Invoke-AX $x;Assert-AXSuccess $r2 ($label+' restart');Assert-AXArtifactsAbsent $x ($label+' restart');$count++
}

$x=New-AR 'executor-live-drift-after-stage' -nonce ('e'*32);$script:AXHookMode='live-drift-after-stage';$script:AXHookPath=[string]$x.q.f.f.q.x.live;$r=Invoke-AX $x;Reset-AXHook;AX-F ([bool]$r.ok) 'post-partial live drift accepted';AX-T ([string]$r.reason -like '*post-delete-admission-denied-stage:*live-*') ('post-partial live reason '+[string]$r.reason);AX-F (Test-Path -LiteralPath ([string]$x.q.f.f.prepared.stage_workspace_path)) 'stage was not retired before injected drift';AX-T (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$x.q.f.f.prepared.app_backup_path))) 'later app backup incorrectly deleted';$count++

$x=New-AR 'executor-result' -nonce ('f'*32);$r=Invoke-AX $x;Assert-AXSuccess $r 'result';$bad=AX-C $r.result;$bad.cleanup_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementExecutorSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementExecutorResultMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryArtifactRetirementExecutorResultV010 $bad;AX-F ([bool]$c.ok) 'authority-tampered executor result accepted';AX-T ([string]$c.reason -like '*authority-escaped-cleanup_authorized') 'result authority reason';$bad=AX-C $r.result;$bad.result_fingerprint=('0'*64);$c=Test-CustomAppProductionRecoveryArtifactRetirementExecutorResultV010 $bad;AX-F ([bool]$c.ok) 'fingerprint-tampered executor result accepted';AX-E $c.reason 'recovery-artifact-retirement-executor-result-fingerprint-mismatch' 'result fingerprint reason';$r2=Invoke-AX $x;Assert-AXSuccess $r2 'repeat-complete';AX-T ([bool]$r2.result.initially_already_complete) 'repeat did not recognize complete state';AX-F ([bool]$r2.result.retirement_performed) 'repeat mutated';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ARTIFACT_RETIREMENT_EXECUTOR_MATRIX_PASS total=$count"
