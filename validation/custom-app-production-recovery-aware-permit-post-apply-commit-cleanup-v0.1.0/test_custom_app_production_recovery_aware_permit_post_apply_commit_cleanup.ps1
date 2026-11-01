$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-post-apply-commit-cleanup.ps1')

function Assert-RACTrue([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Assert-RACFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RACEq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function New-RACSha([char]$C){return ([string]$C)*64}

$script:RACGenericCalls=0;$script:RACConsumptionCalls=0;$script:RACMode='success';$script:RACPostMode='same';$script:RACGenericResultValid=$true
$script:RACHistorical=New-RACSha 'a';$script:RACCurrent=New-RACSha 'b'
$script:RACApply=[pscustomobject]@{
    name='sample-app';source_identity='owner/sample-app';transaction_id=(New-RACSha '1');github_repo_id=[int64]42;surface_kind='custom-app';remote_commit_sha=('c'*40);binding_fingerprint=(New-RACSha '2');consumption_id=(New-RACSha '3')
    historical_consumption_envelope_sha256=$script:RACHistorical;current_consumption_envelope_sha256=$script:RACCurrent;current_consumption_revision=[int64]7
    recovery_finalization_result_fingerprint=(New-RACSha '4');recovery_atomic_result_fingerprint=(New-RACSha '5');recovery_pre_apply_result_fingerprint=(New-RACSha '6');recovery_stage_result_fingerprint=(New-RACSha '7')
    generic_apply_result_fingerprint=(New-RACSha '8');generic_apply_admission_fingerprint=(New-RACSha '9');live_tree_sha256=(New-RACSha 'c');remote_tree_sha256=(New-RACSha 'd');preserved_git_tree_sha256=(New-RACSha 'e');persistence_fingerprint=(New-RACSha 'f');spicetify_executable_sha256=(New-RACSha '1')
    primary_exit_code=0;primary_timed_out=$false;apply_started_at='2026-11-01T23:00:00.0000000+00:00';apply_finished_at='2026-11-01T23:00:01.0000000+00:00';result_fingerprint=(New-RACSha 'a')
}
$script:RACFinal=[pscustomobject]@{result_fingerprint=(New-RACSha '4')};$script:RACAtomic=[pscustomobject]@{result_fingerprint=(New-RACSha '5')};$script:RACPrepared=[pscustomobject]@{result_fingerprint=(New-RACSha '6')};$script:RACStage=[pscustomobject]@{result_fingerprint=(New-RACSha '7')}
$script:RACGenericStage=[pscustomobject]@{result_fingerprint=(New-RACSha '1')}
$script:RACGenericPrepared=[pscustomobject]@{preparation_fingerprint=(New-RACSha '2')}
$script:RACGenericFinal=[pscustomobject]@{finalization_fingerprint=(New-RACSha '3')}
$script:RACGenericApply=[pscustomobject]@{result_fingerprint=(New-RACSha '8')}

function Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupLineageV010 {
    param($ApplyResult,$FinalizationResult,$AtomicResult,$PreparedResult,$StageResult,[string]$Name)
    if($script:RACMode-ceq'lineage-denied'){return [pscustomobject]@{ok=$false;reason='synthetic-lineage-denied'}}
    return [pscustomobject]@{ok=$true;reason='synthetic-lineage-ok';generic_stage=$script:RACGenericStage;generic_prepared=$script:RACGenericPrepared;generic_finalization=$script:RACGenericFinal;generic_apply=$script:RACGenericApply}
}
function Get-CustomAppProductionRecoveryAwarePermitTransactionFinalizationConsumptionV010 {
    param($AtomicResult,$PreparedResult,$StageExecutorResult,$ConsumptionPersistenceResult,[string]$AllowedRoot,[string]$ConsumptionStoreDirectory,[string]$Name)
    $script:RACConsumptionCalls++
    $isPost=($script:RACConsumptionCalls -gt 1)
    $mode=$(if($isPost){$script:RACPostMode}else{$script:RACMode})
    if($mode-ceq'consumption-null'){return $null}
    if($mode-ceq'consumption-denied'){return [pscustomobject]@{ok=$false;reason='synthetic-consumption-denied'}}
    $revision=[int64]7;$envelope=$script:RACCurrent;$historical=$script:RACHistorical
    if(-not$isPost){
        if($mode-ceq'pre-historical-drift'){$historical=New-RACSha 'd'}
        if($mode-ceq'pre-revision-regressed'){$revision=6}
        if($mode-ceq'pre-envelope-drift'){$envelope=New-RACSha 'e'}
    } else {
        if($mode-ceq'post-historical-drift'){$historical=New-RACSha 'd'}
        if($mode-ceq'post-revision-regressed'){$revision=6}
        if($mode-ceq'post-envelope-drift'){$envelope=New-RACSha 'e'}
        if($mode-ceq'unrelated-newer'){$revision=8;$envelope=New-RACSha 'd'}
    }
    return [pscustomobject]@{ok=$true;reason='synthetic-consumption-ok';historical_envelope_sha256=$historical;current_revision=$revision;current_envelope_sha256=$envelope;same_app_newer_consumption_absent=$true}
}
function New-RACGenericCleanupResult {
    return [pscustomobject]@{stage_cleanup_status='deleted-now';app_backup_cleanup_status='deleted-now';persistence_backup_cleanup_status='deleted-now';cleanup_completed_at='2026-11-01T23:00:02.0000000+00:00';cleanup_fingerprint=(New-RACSha '4')}
}
function Invoke-CustomAppProductionPostApplyCommitCleanupV010 {
    param($AllowedRoot,$StoreDirectory,$ExpectedConsumptionId,$Permit,$ApplyResult,$FinalizationResult,$PreparedResult,$StageExecutorResult,$Name,$LifecycleRow,$ProvenanceRow,$BindingRow,$SessionKey,$LocalAppDataRoot,$AppDataRoot,$Now)
    $script:RACGenericCalls++
    switch($script:RACMode){
        'generic-null' { return $null }
        'generic-denied-before' { return [pscustomobject]@{ok=$false;reason='synthetic-generic-denied-before';cleanup_attempted=$false;stage_cleanup_status='not-attempted';app_backup_cleanup_status='not-attempted';persistence_backup_cleanup_status='not-attempted'} }
        'partial-stage' { return [pscustomobject]@{ok=$false;reason='synthetic-fault-after-stage';cleanup_attempted=$true;stage_cleanup_status='deleted-now';app_backup_cleanup_status='present-verified';persistence_backup_cleanup_status='present-verified'} }
        'partial-app' { return [pscustomobject]@{ok=$false;reason='synthetic-fault-after-app';cleanup_attempted=$true;stage_cleanup_status='deleted-now';app_backup_cleanup_status='deleted-now';persistence_backup_cleanup_status='present-verified'} }
        'partial-persistence' { return [pscustomobject]@{ok=$false;reason='synthetic-fault-after-persistence';cleanup_attempted=$true;stage_cleanup_status='deleted-now';app_backup_cleanup_status='deleted-now';persistence_backup_cleanup_status='deleted-now'} }
        default { return [pscustomobject]@{ok=$true;reason='synthetic-cleanup-ok';cleanup_attempted=$true;result=(New-RACGenericCleanupResult)} }
    }
}
function Test-CustomAppProductionPostApplyCommitCleanupResultV010 {param($Result);if($script:RACGenericResultValid){return [pscustomobject]@{ok=$true;reason='synthetic-generic-result-valid'}};return [pscustomobject]@{ok=$false;reason='synthetic-generic-result-invalid'}}

function Invoke-RACTest([string]$Mode,[string]$PostMode='same',[int]$KeyLength=32){
    $script:RACMode=$Mode;$script:RACPostMode=$PostMode;$script:RACGenericCalls=0;$script:RACConsumptionCalls=0;$script:RACGenericResultValid=($Mode-cne'generic-result-invalid')
    $key=New-Object byte[] $KeyLength
    return Invoke-CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupV010 -RecoveryAwareApplyResult $script:RACApply -RecoveryAwareFinalizationResult $script:RACFinal -RecoveryAwareAtomicResult $script:RACAtomic -RecoveryAwarePreparedResult $script:RACPrepared -RecoveryAwareStageExecutorResult $script:RACStage -ConsumptionPersistenceResult ([pscustomobject]@{}) -Permit $null -Name 'sample-app' -LifecycleRow $null -ProvenanceRow $null -BindingRow $null -AllowedRoot 'C:\synthetic' -ConsumptionStoreDirectory 'C:\synthetic\ledger' -SessionKey $key -LocalAppDataRoot 'C:\synthetic\local' -AppDataRoot 'C:\synthetic\roaming' -Now ([DateTimeOffset]::Parse('2026-11-01T23:00:02Z'))
}

$count=0
$r=Invoke-RACTest 'success';Assert-RACTrue ([bool]$r.ok) ('valid denied '+[string]$r.reason);Assert-RACEq $script:RACGenericCalls 1 'valid generic cleanup count';Assert-RACEq $script:RACConsumptionCalls 2 'valid ledger read count';Assert-RACFalse ([bool]$r.rollback_attempted) 'valid rollback escaped';Assert-RACFalse ([bool]$r.spicetify_apply_executed) 'cleanup launched apply';Assert-RACTrue ([bool]$r.requires_new_permit_for_future_update) 'valid missing new-permit requirement';$vc=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 -Result $r.result;Assert-RACTrue ([bool]$vc.ok) ('valid result validator denied '+[string]$vc.reason);$count++
$r=Invoke-RACTest 'success' 'same' 31;Assert-RACFalse ([bool]$r.ok) 'short-key accepted';Assert-RACEq $script:RACGenericCalls 0 'short-key reached generic cleanup';$count++
$r=Invoke-RACTest 'lineage-denied';Assert-RACFalse ([bool]$r.ok) 'lineage denied accepted';Assert-RACEq $script:RACGenericCalls 0 'lineage denied reached generic cleanup';$count++
foreach($m in @('consumption-null','consumption-denied','pre-historical-drift','pre-revision-regressed','pre-envelope-drift')){$r=Invoke-RACTest $m;Assert-RACFalse ([bool]$r.ok) "$m accepted";Assert-RACEq $script:RACGenericCalls 0 "$m reached generic cleanup";$count++}
$r=Invoke-RACTest 'generic-null';Assert-RACFalse ([bool]$r.ok) 'generic-null accepted';Assert-RACEq $script:RACGenericCalls 1 'generic-null call count';Assert-RACFalse ([bool]$r.cleanup_attempted) 'generic-null marked attempted';$count++
$r=Invoke-RACTest 'generic-denied-before';Assert-RACFalse ([bool]$r.ok) 'generic-denied-before accepted';Assert-RACFalse ([bool]$r.requires_idempotent_cleanup_resume) 'pre-mutation deny requires resume';Assert-RACFalse ([bool]$r.rollback_attempted) 'pre-mutation deny rollback escaped';$count++
foreach($m in @('partial-stage','partial-app','partial-persistence')){$r=Invoke-RACTest $m;Assert-RACFalse ([bool]$r.ok) "$m accepted";Assert-RACTrue ([bool]$r.cleanup_attempted) "$m lost attempted flag";Assert-RACTrue ([bool]$r.partial_cleanup_possible) "$m lost partial flag";Assert-RACTrue ([bool]$r.requires_idempotent_cleanup_resume) "$m lost resume flag";Assert-RACFalse ([bool]$r.rollback_attempted) "$m attempted rollback";Assert-RACEq $script:RACConsumptionCalls 2 "$m did not re-read ledger after partial cleanup";$count++}
$r=Invoke-RACTest 'generic-result-invalid';Assert-RACFalse ([bool]$r.ok) 'generic-result-invalid accepted';Assert-RACTrue ([bool]$r.requires_idempotent_cleanup_resume) 'generic result invalid after cleanup lost resume flag';$count++
foreach($m in @('consumption-null','consumption-denied','post-historical-drift','post-revision-regressed','post-envelope-drift')){$r=Invoke-RACTest 'success' $m;Assert-RACFalse ([bool]$r.ok) "post $m accepted";Assert-RACTrue ([bool]$r.cleanup_attempted) "post $m lost attempted flag";Assert-RACTrue ([bool]$r.requires_idempotent_cleanup_resume) "post $m lost resume flag";Assert-RACFalse ([bool]$r.rollback_attempted) "post $m attempted rollback";$count++}
$r=Invoke-RACTest 'success' 'unrelated-newer';Assert-RACTrue ([bool]$r.ok) ('unrelated-newer denied '+[string]$r.reason);Assert-RACEq $r.result.current_consumption_revision 8 'unrelated-newer revision not preserved';$count++
$good=Invoke-RACTest 'success';$tamper=$good.result.PSObject.Copy();$tamper.production_mutation_authorized=$true;$tc=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 -Result $tamper;Assert-RACFalse ([bool]$tc.ok) 'rehashed authority tamper accepted';$count++
$tamper=$good.result.PSObject.Copy();$tamper.result_fingerprint=New-RACSha 'd';$tc=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 -Result $tamper;Assert-RACFalse ([bool]$tc.ok) 'fingerprint tamper accepted';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_POST_APPLY_COMMIT_CLEANUP_MATRIX_PASS total=$count generic_cleanup_exactly_once=true partial_cleanup_never_rolls_back=true partial_resume_required=true unrelated_newer_allowed=true same_revision_drift_denied=true cleanup_launched_no_apply=true zero_authority=true"
