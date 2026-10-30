$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$journalCore=Join-Path $repo 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1'
$orchestratorCore=Join-Path $PSScriptRoot 'custom-app-production-journaled-orchestrator-fixture.ps1'
$probe=Join-Path $PSScriptRoot 'probe_custom_app_production_journaled_orchestrator_fixture.ps1'
. $journalCore
. $orchestratorCore

function Assert-TrueJOFV010 { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-FalseJOFV010 { param([bool]$Condition,[string]$Message) if($Condition){throw $Message} }
function Assert-EqualJOFV010 { param($Actual,$Expected,[string]$Message) if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"} }
function Repeat-JOFV010 { param([string]$C,[int]$N) return (($C*$N)-join '') }

$script:Roots=New-Object System.Collections.Generic.List[string]
$script:CaseCount=0
$script:HookMode='none'
$baseNow=[DateTimeOffset]::UtcNow.AddMinutes(-3)

function Invoke-CustomAppProductionJournaledFixtureValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:HookMode -ceq 'tamper-current-after-atomic' -and $Checkpoint -ceq 'after-phase-persisted-atomic-mutation-starting'){
        [IO.File]::WriteAllText((Join-Path ([string]$Context.store) 'current.json'),'{not-json',(New-Object Text.UTF8Encoding($false)))
    }
}

function New-JOFV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$CallbackMode='normal')
    $root=Join-Path $env:TEMP ('spotify-control-journaled-orchestrator-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root)|Out-Null;$script:Roots.Add($root)
    $live=Join-Path $root 'live-app';$txn=Join-Path $root '.spotify-control-txn-0123456789abcdef0123456789abcdef';$stage=Join-Path $root 'stage-workspace';$app=Join-Path $root 'app-backup';$persist=Join-Path $root 'persistence-backup';$mock=Join-Path $root 'mock-side-effects'
    foreach($p in @($live,$txn,$stage,$app,$persist,$mock)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $store=Join-Path $root 'journal-store';$log=Join-Path $mock 'callback.log'
    $cid=Get-CustomAppProductionCrashJournalSha256V010 ('cid-'+$Label);$stageFp=Get-CustomAppProductionCrashJournalSha256V010 ('stage-'+$Label);$prepFp=Get-CustomAppProductionCrashJournalSha256V010 ('prep-'+$Label)
    $identity=New-CustomAppProductionCrashJournalIdentityV010 -Name $Name -ConsumptionId $cid -SourceIdentity $Source -RemoteCommitSha (Repeat-JOFV010 'a' 40) -StageResultFingerprint $stageFp -PreparationFingerprint $prepFp -AllowedRoot $root -LivePath $live -TransactionRoot $txn -StageWorkspacePath $stage -AppBackupPath $app -PersistenceBackupPath $persist
    $ctx=[pscustomobject]@{root=$root;mock_root=$mock;log_path=$log;callback_mode=$CallbackMode}
    $at=$baseNow.AddSeconds($script:Roots.Count*20)
    return [pscustomobject]@{label=$Label;root=$root;store=$store;identity=$identity;ctx=$ctx;at=$at;log=$log}
}

function New-CallbacksJOFV010 {
    $moveLive={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("move-live-to-old|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        if([string]$ctx.fixture_context.callback_mode -ceq 'authority-move'){return [pscustomobject]@{ok=$true;production_mutation_authorized=$true}}
        if([string]$ctx.fixture_context.callback_mode -ceq 'fail-move'){return [pscustomobject]@{ok=$false;reason='fixture-move-denied'}}
        return [pscustomobject]@{ok=$true;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $moveCandidate={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("move-candidate-live|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{ok=$true;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $finalize={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("finalize-transaction|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        $fp=if([string]$ctx.fixture_context.callback_mode -ceq 'invalid-final'){'bad'}else{Get-CustomAppProductionCrashJournalSha256V010 ('final-'+[string]$ctx.transaction_id)}
        return [pscustomobject]@{ok=$true;fingerprint=$fp;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $apply={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("apply|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        if([string]$ctx.fixture_context.callback_mode -ceq 'fail-apply'){return [pscustomobject]@{ok=$false;reason='fixture-apply-denied'}}
        return [pscustomobject]@{ok=$true;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $verify={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("verify-apply|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        $fp=if([string]$ctx.fixture_context.callback_mode -ceq 'invalid-verify'){'bad'}else{Get-CustomAppProductionCrashJournalSha256V010 ('apply-'+[string]$ctx.transaction_id)}
        return [pscustomobject]@{ok=$true;fingerprint=$fp;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $cleanup={param($ctx)
        [IO.File]::AppendAllText([string]$ctx.fixture_context.log_path,("cleanup|{0}|{1}`n" -f $ctx.durable_phase,$ctx.revision),(New-Object Text.UTF8Encoding($false)))
        $fp=if([string]$ctx.fixture_context.callback_mode -ceq 'invalid-cleanup'){'bad'}else{Get-CustomAppProductionCrashJournalSha256V010 ('cleanup-'+[string]$ctx.transaction_id)}
        return [pscustomobject]@{ok=$true;fingerprint=$fp;callback_result_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    return [pscustomobject]@{move_live=$moveLive;move_candidate=$moveCandidate;finalize=$finalize;apply=$apply;verify=$verify;cleanup=$cleanup}
}

function Invoke-JOFV010 {
    param($F,[string]$CrashPoint='none')
    $c=New-CallbacksJOFV010
    return Invoke-CustomAppProductionJournaledFixtureOrchestratorV010 -AllowedRoot $F.root -StoreDirectory $F.store -Identity $F.identity -FixtureContext $F.ctx -MoveLiveToOldCallback $c.move_live -MoveCandidateLiveCallback $c.move_candidate -FinalizeTransactionCallback $c.finalize -ApplyCallback $c.apply -VerifyApplyCallback $c.verify -CleanupCallback $c.cleanup -CrashPoint $CrashPoint -Now $F.at
}

function Get-LogLinesJOFV010 { param($F) if(-not (Test-Path -LiteralPath $F.log)){return @()};return @(Get-Content -LiteralPath $F.log) }
function Assert-RecoveryJOFV010 { param($F,[string]$Phase,[string]$Classification)
    $r=Get-CustomAppProductionJournaledFixtureRecoveryV010 -AllowedRoot $F.root -StoreDirectory $F.store -ExpectedTransactionId $F.identity.transaction_id
    Assert-TrueJOFV010 ([bool]$r.ok) ($F.label+' recovery denied: '+[string]$r.reason);Assert-EqualJOFV010 $r.phase $Phase ($F.label+' recovery phase');Assert-EqualJOFV010 $r.classification $Classification ($F.label+' recovery classification')
    foreach($x in @('orchestrator_is_authority','journal_is_authority','production_execution_authorized','production_mutation_authorized')){Assert-FalseJOFV010 ([bool]$r.$x) ($F.label+' recovery authority '+$x)}
    return $r
}
function Invoke-RestartProbeJOFV010 { param($F,[string]$Phase,[string]$Classification)
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -JournalCore $journalCore -OrchestratorCore $orchestratorCore -AllowedRoot $F.root -StoreDirectory $F.store -ExpectedTransactionId $F.identity.transaction_id -ExpectedPhase $Phase -ExpectedClassification $Classification
    if($LASTEXITCODE){throw ($F.label+' separate-process restart probe failed')}
}

try {
    # Happy path proves every callback sees the exact durable phase immediately preceding its mock side effect.
    $f=New-JOFV010 'happy';$r=Invoke-JOFV010 $f;Assert-TrueJOFV010 ([bool]$r.ok) ('happy path denied: '+[string]$r.reason);Assert-EqualJOFV010 $r.phase 'committed-clean' 'happy terminal phase';Assert-EqualJOFV010 $r.recovery_classification 'no-action-new-permit-required-for-future-update' 'happy terminal recovery';foreach($x in @('orchestrator_is_authority','result_is_authority','journal_is_authority','production_execution_authorized','production_mutation_authorized','spicetify_apply_authorized','additional_mutation_authorized')){Assert-FalseJOFV010 ([bool]$r.$x) ('happy authority '+$x)}
    $lines=Get-LogLinesJOFV010 $f;$expected=@('move-live-to-old|atomic-mutation-starting|1','move-candidate-live|live-moved-to-old|2','finalize-transaction|candidate-live|3','apply|apply-starting|5','verify-apply|apply-returned-success-pending-verification|6','cleanup|cleanup-starting|8');Assert-EqualJOFV010 ($lines -join ';') ($expected -join ';') 'happy callback durable-phase order';$history=@(Get-ChildItem (Join-Path $f.store 'history') -File -Filter '*.json');Assert-EqualJOFV010 $history.Count 10 'happy history entry count';$script:CaseCount++

    $f=New-JOFV010 'future' -Name 'future-app' -Source 'owner/future-app';$r=Invoke-JOFV010 $f;Assert-TrueJOFV010 ([bool]$r.ok) ('future app fixture denied: '+[string]$r.reason);Assert-EqualJOFV010 $r.phase 'committed-clean' 'future terminal phase';$script:CaseCount++

    # Crash windows: classification must reflect the last durable phase, never inferred callback success.
    $crashes=@(
        [pscustomobject]@{point='after-atomic-starting-before-live-move';phase='atomic-mutation-starting';class='filesystem-recovery-inspection-required';callbacks=0},
        [pscustomobject]@{point='after-live-move-before-journal';phase='atomic-mutation-starting';class='filesystem-recovery-inspection-required';callbacks=1},
        [pscustomobject]@{point='after-live-moved-before-candidate';phase='live-moved-to-old';class='exact-app-and-persistence-recovery-required';callbacks=1},
        [pscustomobject]@{point='after-candidate-before-journal';phase='live-moved-to-old';class='exact-app-and-persistence-recovery-required';callbacks=2},
        [pscustomobject]@{point='after-candidate-live-before-finalize';phase='candidate-live';class='exact-app-and-persistence-recovery-required';callbacks=2},
        [pscustomobject]@{point='after-finalize-before-journal';phase='candidate-live';class='exact-app-and-persistence-recovery-required';callbacks=3},
        [pscustomobject]@{point='after-transaction-finalized-before-apply-starting';phase='transaction-finalized';class='exact-app-and-persistence-recovery-required';callbacks=3},
        [pscustomobject]@{point='after-apply-starting-before-apply';phase='apply-starting';class='rollback-and-recovery-apply-required';callbacks=3},
        [pscustomobject]@{point='after-apply-before-returned';phase='apply-starting';class='rollback-and-recovery-apply-required';callbacks=4},
        [pscustomobject]@{point='after-apply-returned-before-verify';phase='apply-returned-success-pending-verification';class='rollback-and-recovery-apply-required';callbacks=4},
        [pscustomobject]@{point='after-verify-before-verified';phase='apply-returned-success-pending-verification';class='rollback-and-recovery-apply-required';callbacks=5},
        [pscustomobject]@{point='after-apply-verified-before-cleanup-starting';phase='apply-verified';class='fresh-revalidate-then-housekeeping-only';callbacks=5},
        [pscustomobject]@{point='after-cleanup-starting-before-cleanup';phase='cleanup-starting';class='fresh-revalidate-then-idempotent-housekeeping-only';callbacks=5},
        [pscustomobject]@{point='after-cleanup-before-committed';phase='cleanup-starting';class='fresh-revalidate-then-idempotent-housekeeping-only';callbacks=6}
    )
    foreach($x in $crashes){
        $f=New-JOFV010 ('crash-'+$x.point);$threw=$false
        try{[void](Invoke-JOFV010 -F $f -CrashPoint $x.point)}catch{$threw=$true;Assert-EqualJOFV010 ([string]$_.Exception.Message) ('fixture-crash:'+$x.point) ('crash reason '+$x.point)}
        Assert-TrueJOFV010 $threw ('crash point did not stop '+$x.point);$lines=Get-LogLinesJOFV010 $f;Assert-EqualJOFV010 $lines.Count $x.callbacks ('crash callback count '+$x.point);[void](Assert-RecoveryJOFV010 -F $f -Phase $x.phase -Classification $x.class);Invoke-RestartProbeJOFV010 -F $f -Phase $x.phase -Classification $x.class;$script:CaseCount++
    }

    # Corrupting durable current state after the barrier but before reread must stop before the first callback.
    $f=New-JOFV010 'durable-reread-tamper';$script:HookMode='tamper-current-after-atomic';$threw=$false
    try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};$script:HookMode='none';Assert-TrueJOFV010 $threw 'tampered durable reread did not stop orchestrator';Assert-EqualJOFV010 (Get-LogLinesJOFV010 $f).Count 0 'callback ran without valid durable reread';$recovery=Get-CustomAppProductionJournaledFixtureRecoveryV010 -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedTransactionId $f.identity.transaction_id;Assert-FalseJOFV010 ([bool]$recovery.ok) 'tampered journal recovery unexpectedly ok';Assert-EqualJOFV010 $recovery.classification 'fail-closed' 'tampered journal classification';$script:CaseCount++

    # Callback authority, callback denial, and fingerprint corruption are fail-closed at the last durable phase.
    $f=New-JOFV010 'authority-callback' -CallbackMode 'authority-move';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'authority callback accepted';[void](Assert-RecoveryJOFV010 $f 'atomic-mutation-starting' 'filesystem-recovery-inspection-required');$script:CaseCount++
    $f=New-JOFV010 'denied-callback' -CallbackMode 'fail-move';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'denied callback accepted';[void](Assert-RecoveryJOFV010 $f 'atomic-mutation-starting' 'filesystem-recovery-inspection-required');$script:CaseCount++
    $f=New-JOFV010 'invalid-final' -CallbackMode 'invalid-final';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'invalid finalization fingerprint accepted';[void](Assert-RecoveryJOFV010 $f 'candidate-live' 'exact-app-and-persistence-recovery-required');$script:CaseCount++
    $f=New-JOFV010 'failed-apply' -CallbackMode 'fail-apply';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'failed apply callback accepted';[void](Assert-RecoveryJOFV010 $f 'apply-starting' 'rollback-and-recovery-apply-required');$script:CaseCount++
    $f=New-JOFV010 'invalid-verify' -CallbackMode 'invalid-verify';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'invalid apply verification fingerprint accepted';[void](Assert-RecoveryJOFV010 $f 'apply-returned-success-pending-verification' 'rollback-and-recovery-apply-required');$script:CaseCount++
    $f=New-JOFV010 'invalid-cleanup' -CallbackMode 'invalid-cleanup';$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'invalid cleanup fingerprint accepted';[void](Assert-RecoveryJOFV010 $f 'cleanup-starting' 'fresh-revalidate-then-idempotent-housekeeping-only');$script:CaseCount++

    # A committed transaction cannot be replayed through the same store/identity.
    $f=New-JOFV010 'replay';[void](Invoke-JOFV010 $f);$before=(Get-LogLinesJOFV010 $f).Count;$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'completed transaction replay accepted';Assert-EqualJOFV010 (Get-LogLinesJOFV010 $f).Count $before 'replay executed extra callback';$script:CaseCount++

    # Wrong transaction identity can never turn the durable journal into authority.
    $f=New-JOFV010 'wrong-transaction';[void](Invoke-JOFV010 $f);$wrong=Get-CustomAppProductionJournaledFixtureRecoveryV010 -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedTransactionId (Repeat-JOFV010 'f' 64);Assert-FalseJOFV010 ([bool]$wrong.ok) 'wrong transaction recovery accepted';Assert-EqualJOFV010 $wrong.classification 'fail-closed' 'wrong transaction classification';Assert-FalseJOFV010 ([bool]$wrong.production_mutation_authorized) 'wrong transaction gained mutation authority';$script:CaseCount++

    # Competing writer lock blocks initialization before any callback can run.
    $f=New-JOFV010 'lock-contention';$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $f.root -StoreDirectory $f.store -Create:$true;$held=Open-CustomAppProductionCrashJournalLockV010 $paths
    try{$threw=$false;try{[void](Invoke-JOFV010 $f)}catch{$threw=$true};Assert-TrueJOFV010 $threw 'lock contention orchestrator accepted';Assert-EqualJOFV010 (Get-LogLinesJOFV010 $f).Count 0 'lock contention executed callback'}finally{$held.Dispose()};$script:CaseCount++

    Write-Host ("CUSTOM_APP_PRODUCTION_JOURNALED_ORCHESTRATOR_FIXTURE_MATRIX_PASS total={0}" -f $script:CaseCount)
}
finally {
    $script:HookMode='none'
    foreach($r in $script:Roots){try{if(Test-Path -LiteralPath $r){Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction Stop}}catch{}}
}
