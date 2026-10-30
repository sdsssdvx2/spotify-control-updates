$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-plan.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function N([string]$c){return ($c*64)}
function Copy-Plan($x){return (($x|ConvertTo-Json -Depth 30)|ConvertFrom-Json)}

$script:Now=[DateTimeOffset]::UtcNow.AddMinutes(-1)
$script:FinalFp=N 'f';$script:ApplyFp=N 'a';$script:CleanupFp=N 'c'
$script:NormalChain=@('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')

function New-RecoveryPlanFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$TargetPhase)
    $base=Join-Path $env:RUNNER_TEMP ('recovery-plan-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($base)|Out-Null
    $paths=[ordered]@{live=(Join-Path $base 'CustomApps\demo');txn=(Join-Path $base '.spotify-control-txn-11111111111111111111111111111111');stage=(Join-Path $base 'stage-workspace');app=(Join-Path $base 'backups\app-code');persist=(Join-Path $base 'backups\persistence');store=(Join-Path $base 'journal')}
    foreach($p in @($paths.live,$paths.txn,$paths.stage,$paths.app,$paths.persist)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $id=New-CustomAppProductionCrashJournalIdentityV010 -Name 'demo' -ConsumptionId (N '1') -SourceIdentity 'owner/demo' -RemoteCommitSha ('2'*40) -StageResultFingerprint (N '3') -PreparationFingerprint (N '4') -AllowedRoot $base -LivePath $paths.live -TransactionRoot $paths.txn -StageWorkspacePath $paths.stage -AppBackupPath $paths.app -PersistenceBackupPath $paths.persist
    $cur=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $base -StoreDirectory $paths.store -Identity $id -Now $script:Now
    if(-not [bool]$cur.ok){throw ('fixture init failed: '+[string]$cur.reason)}
    if($TargetPhase -ceq 'prepared'){return [pscustomobject]@{root=$base;store=$paths.store;identity=$id;current=$cur}}
    if($TargetPhase -in @('rollback-required','rollback-complete')){
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-required' -Now $script:Now.AddSeconds(1)
        if(-not [bool]$cur.ok){throw ('rollback fixture append failed: '+[string]$cur.reason)}
        if($TargetPhase -ceq 'rollback-complete'){$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-complete' -Now $script:Now.AddSeconds(2);if(-not [bool]$cur.ok){throw ('rollback-complete append failed: '+[string]$cur.reason)}}
        return [pscustomobject]@{root=$base;store=$paths.store;identity=$id;current=$cur}
    }
    $index=[array]::IndexOf($script:NormalChain,$TargetPhase);if($index -lt 1){throw ('unsupported target phase '+$TargetPhase)}
    for($i=1;$i -le $index;$i++){
        $phase=[string]$script:NormalChain[$i]
        $args=@{AllowedRoot=$base;StoreDirectory=$paths.store;ExpectedRevision=[int64]$cur.revision;ExpectedEntrySha256=[string]$cur.entry.entry_sha256;Phase=$phase;Now=$script:Now.AddSeconds($i)}
        if($phase -in @('transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')){$args.FinalizationFingerprint=$script:FinalFp}
        if($phase -in @('apply-verified','cleanup-starting','committed-clean')){$args.ApplyResultFingerprint=$script:ApplyFp}
        if($phase -ceq 'committed-clean'){$args.CleanupResultFingerprint=$script:CleanupFp}
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 @args
        if(-not [bool]$cur.ok){throw ("fixture append failed phase=$phase reason=$([string]$cur.reason)")}
    }
    return [pscustomobject]@{root=$base;store=$paths.store;identity=$id;current=$cur}
}

$expect=@{
'prepared'=@('safe-abandon-or-restart-only-after-fresh-admission','abandon-or-restart-after-fresh-admission');
'atomic-mutation-starting'=@('filesystem-recovery-inspection-required','inspect-filesystem-before-any-recovery');
'live-moved-to-old'=@('exact-app-and-persistence-recovery-required','restore-exact-app-and-persistence');
'candidate-live'=@('exact-app-and-persistence-recovery-required','restore-exact-app-and-persistence');
'transaction-finalized'=@('exact-app-and-persistence-recovery-required','restore-exact-app-and-persistence');
'apply-starting'=@('rollback-and-recovery-apply-required','restore-exact-app-and-persistence-then-recovery-apply');
'apply-returned-success-pending-verification'=@('rollback-and-recovery-apply-required','restore-exact-app-and-persistence-then-recovery-apply');
'apply-verified'=@('fresh-revalidate-then-housekeeping-only','fresh-revalidate-then-housekeeping');
'cleanup-starting'=@('fresh-revalidate-then-idempotent-housekeeping-only','fresh-revalidate-then-idempotent-housekeeping');
'committed-clean'=@('no-action-new-permit-required-for-future-update','no-action-new-permit-required');
'rollback-required'=@('rollback-and-recovery-apply-required','restore-exact-app-and-persistence-then-recovery-apply');
'rollback-complete'=@('no-action-fresh-permit-required','no-action-fresh-permit-required')
}

$count=0;$fixtures=@{}
foreach($phase in @($expect.Keys|Sort-Object)){
    $f=New-RecoveryPlanFixtureV010 -Label ($phase.Replace('-','')) -TargetPhase $phase;$fixtures[$phase]=$f
    $plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedTransactionId ([string]$f.identity.transaction_id)
    $check=Test-CustomAppProductionRecoveryPlanV010 $plan
    Assert-True ([bool]$check.ok) "$phase plan invalid: $([string]$check.reason)"
    Assert-Eq $plan.phase $phase "$phase phase"
    Assert-Eq $plan.classification $expect[$phase][0] "$phase classification"
    Assert-Eq $plan.recovery_verb $expect[$phase][1] "$phase recovery verb"
    Assert-False ([bool]$plan.plan_is_authority) "$phase plan authority"
    Assert-False ([bool]$plan.execution_authorized) "$phase execution authority"
    Assert-False ([bool]$plan.restore_authorized) "$phase restore authority"
    Assert-False ([bool]$plan.apply_authorized) "$phase apply authority"
    Assert-False ([bool]$plan.cleanup_authorized) "$phase cleanup authority"
    Assert-False ([bool]$plan.production_mutation_authorized) "$phase production mutation authority"
    if($phase -in @('live-moved-to-old','candidate-live')){Assert-True ([bool]$plan.requires_transaction_root) "$phase transaction root prerequisite missing"}
    if($phase -ceq 'transaction-finalized'){Assert-False ([bool]$plan.requires_transaction_root) 'transaction-finalized incorrectly requires deleted transaction root'}
    if($phase -in @('apply-starting','apply-returned-success-pending-verification','rollback-required')){Assert-True ([bool]$plan.requires_recovery_apply) "$phase recovery apply prerequisite missing";Assert-True ([bool]$plan.requires_exact_spicetify_executable_pin) "$phase exact spicetify pin prerequisite missing"}
    if($phase -in @('apply-verified','cleanup-starting')){Assert-True ([bool]$plan.requires_idempotent_cleanup) "$phase cleanup prerequisite missing";Assert-False ([bool]$plan.requires_recovery_apply) "$phase recovery apply should be false"}
    if($phase -in @('committed-clean','rollback-complete')){Assert-True ([bool]$plan.no_action) "$phase no-action missing";Assert-True ([bool]$plan.requires_new_permit) "$phase new permit missing"}
    $count++
}

$basePlan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $fixtures['apply-starting'].root -StoreDirectory $fixtures['apply-starting'].store -ExpectedTransactionId ([string]$fixtures['apply-starting'].identity.transaction_id)
$bad=Copy-Plan $basePlan;$bad.recovery_verb='fresh-revalidate-then-housekeeping';$bad.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryPlanV010 $bad;Assert-False ([bool]$c.ok) 'verb remap tamper accepted';Assert-True ([string]$c.reason -like '*mapping-drift-recovery_verb*') 'verb remap reason drifted';$count++
$bad=Copy-Plan $basePlan;$bad.apply_authorized=$true;$bad.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryPlanV010 $bad;Assert-False ([bool]$c.ok) 'authority tamper accepted';Assert-True ([string]$c.reason -like '*authority-escaped-apply_authorized*') 'authority tamper reason drifted';$count++
$bad=Copy-Plan $basePlan;$bad.phase='apply-verified';$bad.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryPlanV010 $bad;Assert-False ([bool]$c.ok) 'phase/classification mismatch accepted';Assert-True ([string]$c.reason -like '*mapping-invalid*') 'phase/classification reason drifted';$count++
$bad=Copy-Plan $basePlan;$bad.plan_fingerprint=('0'*64);$c=Test-CustomAppProductionRecoveryPlanV010 $bad;Assert-False ([bool]$c.ok) 'fingerprint tamper accepted';Assert-Eq $c.reason 'recovery-plan-fingerprint-mismatch' 'fingerprint tamper reason';$count++

$wrong=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $fixtures['candidate-live'].root -StoreDirectory $fixtures['candidate-live'].store -ExpectedTransactionId (N '9');$wc=Test-CustomAppProductionRecoveryPlanV010 $wrong;Assert-True ([bool]$wc.ok) ('wrong-tx fail-closed plan invalid: '+[string]$wc.reason);Assert-Eq $wrong.classification 'fail-closed' 'wrong tx classification';Assert-Eq $wrong.recovery_verb 'manual-inspection-fail-closed' 'wrong tx verb';Assert-True ([bool]$wrong.requires_manual_inspection) 'wrong tx manual inspection missing';$count++

$corrupt=New-RecoveryPlanFixtureV010 -Label 'corrupt' -TargetPhase 'candidate-live';[IO.File]::WriteAllText((Join-Path $corrupt.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false));$cp=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $corrupt.root -StoreDirectory $corrupt.store -ExpectedTransactionId ([string]$corrupt.identity.transaction_id);$cc=Test-CustomAppProductionRecoveryPlanV010 $cp;Assert-True ([bool]$cc.ok) ('corrupt-store fail-closed plan invalid: '+[string]$cc.reason);Assert-Eq $cp.classification 'fail-closed' 'corrupt store classification';Assert-True ([bool]$cp.requires_manual_inspection) 'corrupt store manual inspection missing';$count++

$lockFixture=New-RecoveryPlanFixtureV010 -Label 'lock' -TargetPhase 'apply-verified';$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $lockFixture.root -StoreDirectory $lockFixture.store;$held=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{$lp=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $lockFixture.root -StoreDirectory $lockFixture.store -ExpectedTransactionId ([string]$lockFixture.identity.transaction_id)}finally{$held.Dispose()};$lc=Test-CustomAppProductionRecoveryPlanV010 $lp;Assert-True ([bool]$lc.ok) 'lock fail-closed plan invalid';Assert-Eq $lp.classification 'fail-closed' 'lock classification';$count++

$probeFixture=$fixtures['apply-starting'];$probe=Join-Path $PSScriptRoot 'probe_custom_app_production_recovery_plan.ps1';$raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -AllowedRoot $probeFixture.root -StoreDirectory $probeFixture.store -ExpectedTransactionId ([string]$probeFixture.identity.transaction_id);if($LASTEXITCODE){throw 'separate-process recovery plan probe failed'};$pj=($raw|Select-Object -Last 1)|ConvertFrom-Json;Assert-Eq $pj.classification 'rollback-and-recovery-apply-required' 'probe classification';Assert-Eq $pj.recovery_verb 'restore-exact-app-and-persistence-then-recovery-apply' 'probe verb';Assert-True ([bool]$pj.valid) 'probe validator failed';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_PLAN_MATRIX_PASS total=$count"
