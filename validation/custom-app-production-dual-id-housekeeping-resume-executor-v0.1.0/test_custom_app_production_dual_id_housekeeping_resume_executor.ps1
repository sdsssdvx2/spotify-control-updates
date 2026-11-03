$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

. (Join-Path $root 'validation/custom-app-production-dual-id-bridge-aware-post-apply-commit-cleanup-v0.1.0/test_custom_app_production_dual_id_bridge_aware_post_apply_commit_cleanup.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-execution-admission-v0.1.0/custom-app-production-recovery-execution-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/custom-app-production-recovery-evidence-admission-integration.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-contract.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-store.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-writer.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-housekeeping-resume-v0.1.0/custom-app-production-recovery-housekeeping-resume-gate.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-housekeeping-resume-executor.ps1')

function Assert-DIHRTrue([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Assert-DIHRFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-DIHREq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Assert-DIHRNoAuthority($Value,[string]$Label){foreach($f in @('result_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-DIHRFalse([bool]$Value.$f)("$Label escaped $f")}}}

$script:DIHRFault=$null
function Invoke-CustomAppProductionDualIdHousekeepingResumeValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if(-not[string]::IsNullOrWhiteSpace([string]$script:DIHRFault)-and$Checkpoint-ceq$script:DIHRFault){throw ('DIHR_SIMULATED_PROCESS_DEATH_'+$Checkpoint)}
}
function Initialize-DIHRV010 {
    param([Parameter(Mandatory=$true)]$X,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    return Initialize-CustomAppProductionDualIdHousekeepingResumeV010 -AllowedRoot $X.f.trust -JournalStoreDirectory $X.f.store -ExpectedJournalTransactionId ([string]$X.apply.journal_transaction_id) -LocalAppDataRoot ([string]$X.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$X.f.x.fixture.q.persistence.roaming) -Now $Now
}
function Invoke-DIHRV010 {
    param([Parameter(Mandatory=$true)]$X,[AllowNull()][string]$ExpectedJournalId=$null,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $id=if([string]::IsNullOrWhiteSpace($ExpectedJournalId)){[string]$X.apply.journal_transaction_id}else{$ExpectedJournalId}
    return Invoke-CustomAppProductionDualIdHousekeepingResumeExecutorV010 -AllowedRoot $X.f.trust -JournalStoreDirectory $X.f.store -ExpectedJournalTransactionId $id -LocalAppDataRoot ([string]$X.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$X.f.x.fixture.q.persistence.roaming) -Now $Now
}
function Read-DIHRResumeV010($X){return Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 -AllowedRoot $X.f.trust -StoreDirectory $X.f.store}
function Assert-DIHRCommittedV010($X,$R,[string]$Label){
    Assert-DIHRTrue($null-ne$R-and[bool]$R.ok)("$Label denied: $([string]$R.reason)")
    Assert-DIHRTrue((Get-DBAXCountV010 $X.count_path)-eq1)"$Label executed extra apply"
    Assert-DIHRFalse(Test-Path -LiteralPath $X.stage_workspace)"$Label stage remains"
    Assert-DIHRFalse(Test-Path -LiteralPath $X.app_container)"$Label app backup remains"
    Assert-DIHRFalse(Test-Path -LiteralPath $X.persistence_backup)"$Label persistence backup remains"
    $j=Read-DBACJournalV010 $X;Assert-DIHREq([string]$j.entry.phase)'committed-clean' "$Label journal phase"
    Assert-DIHREq([string]$j.transaction_id).Trim().ToLowerInvariant()([string]$R.result.journal_transaction_id).Trim().ToLowerInvariant() "$Label journal id"
    Assert-DIHRFalse(([string]$R.result.permit_transaction_id)-ceq([string]$R.result.journal_transaction_id))"$Label transaction IDs conflated"
    Assert-DIHREq([string]$j.entry.finalization_fingerprint).Trim().ToLowerInvariant()([string]$R.result.finalization_fingerprint).Trim().ToLowerInvariant() "$Label finalization fp"
    Assert-DIHREq([string]$j.entry.apply_result_fingerprint).Trim().ToLowerInvariant()([string]$R.result.apply_evidence_fingerprint).Trim().ToLowerInvariant() "$Label apply fp"
    Assert-DIHREq([string]$j.entry.cleanup_result_fingerprint).Trim().ToLowerInvariant()([string]$R.result.cleanup_fingerprint).Trim().ToLowerInvariant() "$Label cleanup fp"
    $rc=Test-CustomAppProductionDualIdHousekeepingResumeResultV010 $R.result;Assert-DIHRTrue([bool]$rc.ok)("$Label result validator: $([string]$rc.reason)")
    $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $X.f.trust -StoreDirectory $X.f.store -ExpectedTransactionId ([string]$R.result.journal_transaction_id);Assert-DIHRTrue($null-ne$ev-and[bool]$ev.ok)"$Label recovery evidence lost"
    $hr=Read-DIHRResumeV010 $X;Assert-DIHRTrue($null-ne$hr-and[bool]$hr.ok)"$Label resume envelope lost"
    Assert-DIHRNoAuthority $R "$Label wrapper";Assert-DIHRNoAuthority $R.result "$Label result"
}
function Invoke-DBACCrashAfterPreinitV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)][string]$Fault)
    $init=Initialize-DIHRV010 $X;Assert-DIHRTrue([bool]$init.ok)("preinit failed ${Fault}: $([string]$init.reason)")
    $script:DBACFault=$Fault;try{return Invoke-DBACV010 $X}finally{$script:DBACFault=$null}
}

$count=0

# 1. Pre-cleanup durability barrier at apply-verified.
$script:DIHRFault=$null;$x1=New-DBACFixtureV010 'dihr-preinit';$j1=Read-DBACJournalV010 $x1;Assert-DIHREq([string]$j1.entry.phase)'apply-verified' 'preinit source phase';$i1=Initialize-DIHRV010 $x1;Assert-DIHRTrue([bool]$i1.ok)('preinit denied: '+[string]$i1.reason);Assert-DIHRTrue([bool]$i1.resume_envelope_persisted)'preinit envelope not persisted';Assert-DIHRFalse(([string]$i1.permit_transaction_id)-ceq([string]$i1.journal_transaction_id))'preinit IDs conflated';Assert-DIHRTrue(Test-Path -LiteralPath $x1.stage_workspace)'preinit deleted stage';Assert-DIHRTrue(Test-Path -LiteralPath $x1.app_container)'preinit deleted app';Assert-DIHRTrue(Test-Path -LiteralPath $x1.persistence_backup)'preinit deleted persistence';Assert-DIHRTrue((Get-DBAXCountV010 $x1.count_path)-eq1)'preinit applied twice';$j1b=Read-DBACJournalV010 $x1;Assert-DIHREq([string]$j1b.entry.phase)'apply-verified' 'preinit advanced journal';Assert-DIHRNoAuthority $i1 'preinit';$count++

# 2. Cold-style entry from apply-verified auto-creates resume envelope then commits clean.
$x2=New-DBACFixtureV010 'dihr-auto';$r2=Invoke-DIHRV010 $x2;Assert-DIHRCommittedV010 $x2 $r2 'auto-resume';Assert-DIHRFalse([bool]$r2.result.resume_envelope_preexisted)'auto-resume claimed preexisting envelope';$count++

# 3. Normal #198 cleanup dies immediately after cleanup-starting; restart-only executor finishes.
$x3=New-DBACFixtureV010 'dihr-after-start';$cr3=Invoke-DBACCrashAfterPreinitV010 -X $x3 -Fault 'after-cleanup-starting-barrier';Assert-DIHRFalse([bool]$cr3.ok)'normal cleanup crash-after-start succeeded';$j3=Read-DBACJournalV010 $x3;Assert-DIHREq([string]$j3.entry.phase)'cleanup-starting' 'crash-after-start phase';$r3=Invoke-DIHRV010 $x3;Assert-DIHRCommittedV010 $x3 $r3 'resume-after-start';Assert-DIHRTrue([bool]$r3.result.resume_envelope_preexisted)'resume-after-start lost preexisting envelope';$count++

# 4. Process death after stage deletion.
$x4=New-DBACFixtureV010 'dihr-after-stage';$cr4=Invoke-DBACCrashAfterPreinitV010 -X $x4 -Fault 'after-stage-cleanup';Assert-DIHRFalse([bool]$cr4.ok)'normal cleanup crash-after-stage succeeded';Assert-DIHRFalse(Test-Path -LiteralPath $x4.stage_workspace)'stage crash did not delete stage';Assert-DIHRTrue(Test-Path -LiteralPath $x4.app_container)'stage crash deleted app early';$r4=Invoke-DIHRV010 $x4;Assert-DIHRCommittedV010 $x4 $r4 'resume-after-stage';$count++

# 5. Process death after app backup deletion.
$x5=New-DBACFixtureV010 'dihr-after-app';$cr5=Invoke-DBACCrashAfterPreinitV010 -X $x5 -Fault 'after-app-backup-cleanup';Assert-DIHRFalse([bool]$cr5.ok)'normal cleanup crash-after-app succeeded';Assert-DIHRFalse(Test-Path -LiteralPath $x5.stage_workspace)'app crash stage remains';Assert-DIHRFalse(Test-Path -LiteralPath $x5.app_container)'app crash app remains';Assert-DIHRTrue(Test-Path -LiteralPath $x5.persistence_backup)'app crash persistence removed early';$r5=Invoke-DIHRV010 $x5;Assert-DIHRCommittedV010 $x5 $r5 'resume-after-app';$count++

# 6. Process death after all three deletes but before committed-clean.
$x6=New-DBACFixtureV010 'dihr-after-persistence';$cr6=Invoke-DBACCrashAfterPreinitV010 -X $x6 -Fault 'after-persistence-backup-cleanup';Assert-DIHRFalse([bool]$cr6.ok)'normal cleanup crash-after-persistence succeeded';Assert-DIHRFalse(Test-Path -LiteralPath $x6.stage_workspace)'persistence crash stage remains';Assert-DIHRFalse(Test-Path -LiteralPath $x6.app_container)'persistence crash app remains';Assert-DIHRFalse(Test-Path -LiteralPath $x6.persistence_backup)'persistence crash backup remains';$r6=Invoke-DIHRV010 $x6;Assert-DIHRCommittedV010 $x6 $r6 'resume-after-persistence';$count++

# 7. cleanup-starting without the pre-cleanup resume envelope must fail closed.
$x7=New-DBACFixtureV010 'dihr-missing-envelope';$script:DBACFault='after-cleanup-starting-barrier';try{$cr7=Invoke-DBACV010 $x7}finally{$script:DBACFault=$null};Assert-DIHRFalse([bool]$cr7.ok)'missing-envelope setup cleanup succeeded';$j7=Read-DBACJournalV010 $x7;Assert-DIHREq([string]$j7.entry.phase)'cleanup-starting' 'missing-envelope setup phase';$r7=Invoke-DIHRV010 $x7;Assert-DIHRFalse([bool]$r7.ok)'missing resume envelope accepted';Assert-DIHREq([string]$r7.reason)'dual-id-housekeeping-resume-envelope-missing-after-cleanup-starting' 'missing envelope reason';Assert-DIHRTrue(Test-Path -LiteralPath $x7.stage_workspace)'missing envelope executor deleted stage';Assert-DIHRTrue(Test-Path -LiteralPath $x7.app_container)'missing envelope executor deleted app';Assert-DIHRTrue(Test-Path -LiteralPath $x7.persistence_backup)'missing envelope executor deleted persistence';Assert-DIHRTrue((Get-DBAXCountV010 $x7.count_path)-eq1)'missing envelope executor reapplied';$count++

# 8. Wrong journal namespace ID is rejected before durable side effects.
$x8=New-DBACFixtureV010 'dihr-wrong-journal';$wrong=('0'*64);if($wrong-ceq[string]$x8.apply.journal_transaction_id){$wrong=('1'*64)};$r8=Invoke-DIHRV010 -X $x8 -ExpectedJournalId $wrong;Assert-DIHRFalse([bool]$r8.ok)'wrong journal ID accepted';$j8=Read-DBACJournalV010 $x8;Assert-DIHREq([string]$j8.entry.phase)'apply-verified' 'wrong journal ID advanced phase';$hr8=Read-DIHRResumeV010 $x8;Assert-DIHRFalse([bool]$hr8.ok)'wrong journal ID created envelope';Assert-DIHRTrue(Test-Path -LiteralPath $x8.stage_workspace)'wrong journal ID deleted stage';$count++

# 9. Resume executor itself dies after deletes but before committed-clean; second invocation finishes from durable state only.
$x9=New-DBACFixtureV010 'dihr-before-commit';$i9=Initialize-DIHRV010 $x9;Assert-DIHRTrue([bool]$i9.ok)'before-commit init failed';$script:DIHRFault='before-committed-clean';try{$cr9=Invoke-DIHRV010 $x9}finally{$script:DIHRFault=$null};Assert-DIHRFalse([bool]$cr9.ok)'before-commit simulated crash succeeded';Assert-DIHRTrue([bool]$cr9.requires_idempotent_housekeeping_resume)'before-commit missing resume flag';$j9=Read-DBACJournalV010 $x9;Assert-DIHREq([string]$j9.entry.phase)'cleanup-starting' 'before-commit phase';Assert-DIHRFalse(Test-Path -LiteralPath $x9.stage_workspace)'before-commit stage remains';Assert-DIHRFalse(Test-Path -LiteralPath $x9.app_container)'before-commit app remains';Assert-DIHRFalse(Test-Path -LiteralPath $x9.persistence_backup)'before-commit persistence remains';$r9=Invoke-DIHRV010 $x9;Assert-DIHRCommittedV010 $x9 $r9 'resume-before-commit';$count++

$script:DIHRFault=$null;$script:DBACFault=$null
if($count-ne9){throw "dual-ID housekeeping resume matrix case count mismatch $count"}
Write-Host "CUSTOM_APP_PRODUCTION_DUAL_ID_HOUSEKEEPING_RESUME_EXECUTOR_MATRIX_PASS cases=$count no_extra_apply=true precleanup_resume_barrier=true missing_envelope_fail_closed=true transaction_namespaces_distinct=true recovery_evidence_retained=true"
