$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/test_custom_app_production_recovery_restore_resume_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-restore-executor.ps1')

function Assert-RXTrue([bool]$v,[string]$m){if(-not $v){throw $m}}
function Assert-RXFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RXEq($a,$b,[string]$m){if([string]$a -cne [string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RX($x){return (($x|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}

$fakeRoot=Join-Path $env:TEMP ('spotify-control-recovery-restore-executor-fake-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
using System.Threading;
public static class RecoveryFakeSpicetify {
    static string E(string n){ return Environment.GetEnvironmentVariable(n) ?? ""; }
    static int Next(string p){ int n=0; if(File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(),out n); n++; File.WriteAllText(p,n.ToString()); return n; }
    public static int Main(string[] args){
        if(args==null || args.Length!=1 || args[0]!="apply") return 64;
        string count=E("SC_RX_COUNT"), live=E("SC_RX_LIVE"), applied=E("SC_RX_APPLIED"), mode=E("SC_RX_MODE");
        if(String.IsNullOrEmpty(count)||String.IsNullOrEmpty(live)||String.IsNullOrEmpty(applied)) return 65;
        Next(count);
        File.WriteAllText(applied,File.Exists(live)?File.ReadAllText(live):"");
        if(mode=="timeout"){Thread.Sleep(4000);return 0;}
        if(mode=="fail"){return 7;}
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
if($fakeSha -notmatch '^[0-9a-f]{64}$'){throw 'recovery fake spicetify hash invalid'}

$script:RXFault='none'
$script:RXFixture=$null
$script:RXNow=[DateTimeOffset]::UtcNow
function Invoke-CustomAppProductionRecoveryRestoreExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:RXFault){
        'race-before-barrier' {
            if($Checkpoint -ceq 'before-rollback-required-append'){
                $r=$Context.receipt
                $x=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot ([string]$Context.allowed_root) -StoreDirectory ([string]$Context.store_directory) -ExpectedRevision ([int64]$r.journal_revision) -ExpectedEntrySha256 ([string]$r.journal_entry_sha256) -Phase 'rollback-required' -Now $script:RXNow.AddMilliseconds(0.5)
                if(-not [bool]$x.ok){throw ('race fixture failed to win barrier: '+[string]$x.reason)}
            }
        }
        'throw-after-barrier' {if($Checkpoint -ceq 'after-rollback-required-barrier'){throw 'fixture-crash-after-rollback-required-barrier'}}
        'stage-drift-after-barrier' {if($Checkpoint -ceq 'after-rollback-required-barrier'){[IO.File]::AppendAllText((Join-Path ([string]$script:RXFixture.f.f.prepared.stage_path) 'index.js'),"// fixture-stage-drift-after-barrier`n",[Text.UTF8Encoding]::new($false))}}
        'throw-after-restore' {if($Checkpoint -ceq 'after-exact-restore-before-apply-admission'){throw 'fixture-crash-after-exact-restore'}}
        'persistence-drift-after-restore' {if($Checkpoint -ceq 'after-exact-restore-before-apply-admission'){[IO.File]::AppendAllText((Join-Path ([string]$script:RXFixture.f.f.q.persistence.roaming) 'spicetify\config-xpui.ini'),"# fixture-persistence-drift-after-restore`n",[Text.UTF8Encoding]::new($false))}}
        'throw-after-apply' {if($Checkpoint -ceq 'after-recovery-apply-before-postcheck'){throw 'fixture-crash-after-recovery-apply'}}
        'live-drift-after-apply' {if($Checkpoint -ceq 'after-recovery-apply-before-postcheck'){[IO.File]::AppendAllText((Join-Path ([string]$script:RXFixture.f.f.q.x.live) 'index.js'),"// fixture-live-drift-after-apply`n",[Text.UTF8Encoding]::new($false))}}
        'throw-before-complete' {if($Checkpoint -ceq 'before-rollback-complete-append'){throw 'fixture-crash-before-rollback-complete'}}
    }
}

function New-RXFixtureV010 {
    param([string]$Label,[string]$Phase='transaction-finalized',[string]$State='finalized',[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('8'*32))
    $q=New-RRFixtureV010 -Label ('executor-'+$Label) -Phase $Phase -State $State -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $control=Join-Path $env:TEMP ('spotify-control-recovery-executor-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    return [pscustomobject]@{f=$q;control=$control;count=(Join-Path $control 'count.txt');applied=(Join-Path $control 'applied.txt')}
}
function Set-RXEnvironmentV010($Q,[string]$Mode='success'){
    $env:SC_RX_COUNT=[string]$Q.count
    $env:SC_RX_LIVE=Join-Path ([string]$Q.f.f.q.x.live) 'index.js'
    $env:SC_RX_APPLIED=[string]$Q.applied
    $env:SC_RX_MODE=$Mode
}
function Clear-RXEnvironmentV010 {
    foreach($n in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
    $script:RXFault='none';$script:RXFixture=$null
}
function Get-RXCountV010($Q){if(-not (Test-Path -LiteralPath ([string]$Q.count))){return 0};return [int]([IO.File]::ReadAllText([string]$Q.count).Trim())}
function Get-RXPhaseV010($Q){$r=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Q.f.f.allowed -StoreDirectory $Q.f.f.store;if(-not [bool]$r.ok){throw ('journal read failed: '+[string]$r.reason)};return [string]$r.entry.phase}
function Invoke-RXFixtureV010 {
    param($Q,[string]$Mode='success',[string]$Exe=$fakeExe,[string]$Sha=$fakeSha,[int]$Timeout=10,[string]$Fault='none',[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    $script:RXFault=$Fault;$script:RXFixture=$Q;$script:RXNow=$At
    Set-RXEnvironmentV010 -Q $Q -Mode $Mode
    try{return Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot $Q.f.f.allowed -StoreDirectory $Q.f.f.store -ExpectedTransactionId ([string]$Q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.f.q.persistence.local -AppDataRoot $Q.f.f.q.persistence.roaming -SpicetifyAllowedRoot $Q.f.f.allowed -SpicetifyPath $Exe -ExpectedSpicetifySha256 $Sha -Now $At -TimeoutSeconds $Timeout}
    finally{Clear-RXEnvironmentV010}
}
function Assert-RXNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['result']){$R.result}else{$R};foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RXFalse ([bool]$x.$f) "$Label authority escaped $f"}}
function Assert-RXArtifactsRetainedV010($Q,[string]$Label){
    Assert-RXTrue (Test-Path -LiteralPath ([string]$Q.f.f.prepared.stage_workspace_path) -PathType Container) "$Label stage workspace missing"
    Assert-RXTrue (Test-Path -LiteralPath ([string]$Q.f.f.prepared.app_backup_path) -PathType Container) "$Label app backup missing"
    Assert-RXTrue (Test-Path -LiteralPath ([string]$Q.f.f.prepared.persistence_backup_path) -PathType Container) "$Label persistence backup missing"
}
function Assert-RXOldStateV010($Q,[string]$Label,[bool]$RequireApplied=$false){
    $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Q.f.f.q.x.live)
    Assert-RXEq $app.tree_sha256 $Q.f.f.prepared.app_backup_tree_sha256 "$Label app tree"
    Assert-RXTrue ([int]$app.file_count -eq [int]$Q.f.f.prepared.app_backup_file_count) "$Label app file count"
    Assert-RXTrue ([int64]$app.total_bytes -eq [int64]$Q.f.f.prepared.app_backup_total_bytes) "$Label app bytes"
    $p=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Q.f.f.q.persistence.local -AppDataRoot $Q.f.f.q.persistence.roaming
    Assert-RXEq $p.fingerprint $Q.f.f.prepared.persistence_fingerprint "$Label persistence"
    Assert-RXArtifactsRetainedV010 $Q $Label
    if($RequireApplied){
        Assert-RXTrue (Test-Path -LiteralPath ([string]$Q.applied) -PathType Leaf) "$Label fake applied state missing"
        $old=[IO.File]::ReadAllText((Join-Path ([string]$Q.f.f.prepared.app_backup_path) 'index.js'))
        Assert-RXTrue ([IO.File]::ReadAllText([string]$Q.applied) -ceq $old) "$Label recovery apply did not target restored old state"
    }
}
function Assert-RXSuccessV010($Q,$R,[string]$Started,[bool]$Barrier,[string]$Label){
    Assert-RXTrue ([bool]$R.ok) "$Label denied: $([string]$R.reason)";Assert-RXNoAuthorityV010 $R $Label
    Assert-RXEq $R.result.started_phase $Started "$Label started phase";Assert-RXTrue ([bool]$R.result.rollback_required_was_appended -eq $Barrier) "$Label barrier flag"
    Assert-RXTrue ([bool]$R.result.restore_performed) "$Label restore missing";Assert-RXTrue ([bool]$R.result.recovery_apply_executed) "$Label apply missing";Assert-RXTrue ([bool]$R.result.rollback_complete_persisted) "$Label completion missing";Assert-RXTrue ([bool]$R.result.requires_recovery_artifact_retirement) "$Label retirement requirement missing"
    Assert-RXEq (Get-RXPhaseV010 $Q) 'rollback-complete' "$Label journal phase";Assert-RXTrue ((Get-RXCountV010 $Q)-eq 1) "$Label apply count";Assert-RXOldStateV010 $Q $Label $true
    $c=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $R.result;Assert-RXTrue ([bool]$c.ok) "$Label result invalid: $([string]$c.reason)"
}

$count=0
$validCases=@(
    @('live-moved-before','live-moved-to-old','live-moved-before-candidate','1'),
    @('live-moved-after','live-moved-to-old','live-moved-after-candidate','2'),
    @('candidate-after-finalize','candidate-live','candidate-after-finalize','3'),
    @('transaction-finalized','transaction-finalized','finalized','4'),
    @('apply-starting','apply-starting','finalized','5'),
    @('apply-returned','apply-returned-success-pending-verification','finalized','6'),
    @('rollback-absent','rollback-required','rollback-live-absent','7'),
    @('rollback-stage-no-txn','rollback-required','rollback-live-stage-no-txn','8')
)
foreach($c in $validCases){$q=New-RXFixtureV010 -Label $c[0] -Phase $c[1] -State $c[2] -Nonce (($c[3])*32);$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $q $r $c[1] ($c[1]-cne'rollback-required') $c[0];$count++}
$future=New-RXFixtureV010 -Label 'future' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('9'*32);$r=Invoke-RXFixtureV010 $future;Assert-RXSuccessV010 $future $r 'live-moved-to-old' $true 'future-app';Assert-RXEq $r.result.name 'future-app' 'future identity';$count++

$wrong=New-RXFixtureV010 -Label 'wrong-hash' -Nonce ('a'*32);$before=Get-RXPhaseV010 $wrong;$r=Invoke-RXFixtureV010 -Q $wrong -Sha ('0'*64);Assert-RXFalse ([bool]$r.ok) 'wrong executable hash accepted';Assert-RXTrue ([string]$r.reason -like 'recovery-restore-executor-executable-precheck-denied:*') 'wrong hash reason';Assert-RXEq (Get-RXPhaseV010 $wrong) $before 'wrong hash changed journal';Assert-RXTrue ((Get-RXCountV010 $wrong)-eq 0) 'wrong hash launched apply';Assert-RXNoAuthorityV010 $r 'wrong-hash';$count++

$lockQ=New-RXFixtureV010 -Label 'lock-contention' -Nonce ('b'*32);$held=Open-CustomAppProductionRecoveryRestoreExecutorLockV010 -AllowedRoot $lockQ.f.f.allowed -StoreDirectory $lockQ.f.f.store;try{$r=Invoke-RXFixtureV010 $lockQ}finally{$held.Dispose()};Assert-RXFalse ([bool]$r.ok) 'executor lock contention accepted';Assert-RXEq $r.reason 'recovery-restore-executor-lock-busy' 'lock reason';Assert-RXTrue ((Get-RXCountV010 $lockQ)-eq 0) 'lock contention launched apply';$count++

$race=New-RXFixtureV010 -Label 'cas-race' -Phase 'candidate-live' -State 'candidate-after-finalize' -Nonce ('c'*32);$r=Invoke-RXFixtureV010 -Q $race -Fault 'race-before-barrier';Assert-RXFalse ([bool]$r.ok) 'CAS loser accepted';Assert-RXTrue ([string]$r.reason -like 'recovery-restore-executor-rollback-required-append-denied:*conflict*') 'CAS race reason';Assert-RXEq (Get-RXPhaseV010 $race) 'rollback-required' 'CAS race winner phase';Assert-RXTrue ((Get-RXCountV010 $race)-eq 0) 'CAS loser launched apply';$r2=Invoke-RXFixtureV010 $race;Assert-RXSuccessV010 $race $r2 'rollback-required' $false 'CAS race restart';$count++

$barrierCrash=New-RXFixtureV010 -Label 'crash-after-barrier' -Nonce ('d'*32);$r=Invoke-RXFixtureV010 -Q $barrierCrash -Fault 'throw-after-barrier';Assert-RXFalse ([bool]$r.ok) 'post-barrier crash accepted';Assert-RXEq (Get-RXPhaseV010 $barrierCrash) 'rollback-required' 'post-barrier crash phase';Assert-RXTrue ((Get-RXCountV010 $barrierCrash)-eq 0) 'post-barrier crash launched apply';$r2=Invoke-RXFixtureV010 $barrierCrash;Assert-RXSuccessV010 $barrierCrash $r2 'rollback-required' $false 'post-barrier restart';$count++

$stageDrift=New-RXFixtureV010 -Label 'stage-drift-after-barrier' -Nonce ('e'*32);$r=Invoke-RXFixtureV010 -Q $stageDrift -Fault 'stage-drift-after-barrier';Assert-RXFalse ([bool]$r.ok) 'stage drift after barrier accepted';Assert-RXTrue ([string]$r.reason -like 'recovery-restore-executor-fresh-admission-denied:*stage*') 'stage drift reason';Assert-RXEq (Get-RXPhaseV010 $stageDrift) 'rollback-required' 'stage drift phase';Assert-RXTrue ((Get-RXCountV010 $stageDrift)-eq 0) 'stage drift launched apply';$count++

$restoreCrash=New-RXFixtureV010 -Label 'crash-after-restore' -Nonce ('f'*32);$r=Invoke-RXFixtureV010 -Q $restoreCrash -Fault 'throw-after-restore';Assert-RXFalse ([bool]$r.ok) 'post-restore crash accepted';Assert-RXEq (Get-RXPhaseV010 $restoreCrash) 'rollback-required' 'post-restore crash phase';Assert-RXOldStateV010 $restoreCrash 'post-restore crash' $false;Assert-RXTrue ((Get-RXCountV010 $restoreCrash)-eq 0) 'post-restore crash launched apply';$r2=Invoke-RXFixtureV010 $restoreCrash;Assert-RXSuccessV010 $restoreCrash $r2 'rollback-required' $false 'post-restore restart';$count++

$persistDrift=New-RXFixtureV010 -Label 'persistence-drift-after-restore' -Nonce ('1'*32);$r=Invoke-RXFixtureV010 -Q $persistDrift -Fault 'persistence-drift-after-restore';Assert-RXFalse ([bool]$r.ok) 'post-restore persistence drift accepted';Assert-RXEq $r.reason 'recovery-restore-executor-post-restore-state-not-exact-old-state' 'post-restore persistence drift reason';Assert-RXEq (Get-RXPhaseV010 $persistDrift) 'rollback-required' 'post-restore persistence drift phase';Assert-RXTrue ((Get-RXCountV010 $persistDrift)-eq 0) 'persistence drift launched apply';$count++

$fail=New-RXFixtureV010 -Label 'apply-fail' -Nonce ('2'*32);$r=Invoke-RXFixtureV010 -Q $fail -Mode 'fail';Assert-RXFalse ([bool]$r.ok) 'failed recovery apply accepted';Assert-RXTrue ([string]$r.reason -like 'recovery-restore-executor-recovery-apply-failed:*') 'apply fail reason';Assert-RXEq (Get-RXPhaseV010 $fail) 'rollback-required' 'apply fail phase';Assert-RXOldStateV010 $fail 'apply-fail' $true;Assert-RXTrue ((Get-RXCountV010 $fail)-eq 1) 'apply fail count';$r2=Invoke-RXFixtureV010 $fail;Assert-RXTrue ([bool]$r2.ok) 'apply fail restart denied';Assert-RXTrue ((Get-RXCountV010 $fail)-eq 2) 'apply fail restart count';$count++

$timeout=New-RXFixtureV010 -Label 'apply-timeout' -Nonce ('3'*32);$r=Invoke-RXFixtureV010 -Q $timeout -Mode 'timeout' -Timeout 1;Assert-RXFalse ([bool]$r.ok) 'timed out recovery apply accepted';Assert-RXEq (Get-RXPhaseV010 $timeout) 'rollback-required' 'timeout phase';Assert-RXOldStateV010 $timeout 'apply-timeout' $true;Assert-RXTrue ((Get-RXCountV010 $timeout)-eq 1) 'timeout count';$r2=Invoke-RXFixtureV010 $timeout;Assert-RXTrue ([bool]$r2.ok) 'timeout restart denied';Assert-RXTrue ((Get-RXCountV010 $timeout)-eq 2) 'timeout restart count';$count++

$afterApply=New-RXFixtureV010 -Label 'crash-after-apply' -Nonce ('4'*32);$r=Invoke-RXFixtureV010 -Q $afterApply -Fault 'throw-after-apply';Assert-RXFalse ([bool]$r.ok) 'post-apply crash accepted';Assert-RXEq (Get-RXPhaseV010 $afterApply) 'rollback-required' 'post-apply crash phase';Assert-RXOldStateV010 $afterApply 'post-apply crash' $true;Assert-RXTrue ((Get-RXCountV010 $afterApply)-eq 1) 'post-apply crash count';$r2=Invoke-RXFixtureV010 $afterApply;Assert-RXTrue ([bool]$r2.ok) 'post-apply restart denied';Assert-RXTrue ((Get-RXCountV010 $afterApply)-eq 2) 'post-apply restart count';$count++

$liveDrift=New-RXFixtureV010 -Label 'live-drift-after-apply' -Nonce ('5'*32);$r=Invoke-RXFixtureV010 -Q $liveDrift -Fault 'live-drift-after-apply';Assert-RXFalse ([bool]$r.ok) 'post-apply live drift accepted';Assert-RXEq $r.reason 'recovery-restore-executor-postcheck-app-tree-mismatch' 'post-apply live drift reason';Assert-RXEq (Get-RXPhaseV010 $liveDrift) 'rollback-required' 'post-apply live drift phase';$count++

$beforeComplete=New-RXFixtureV010 -Label 'crash-before-complete' -Nonce ('6'*32);$r=Invoke-RXFixtureV010 -Q $beforeComplete -Fault 'throw-before-complete';Assert-RXFalse ([bool]$r.ok) 'pre-complete crash accepted';Assert-RXEq (Get-RXPhaseV010 $beforeComplete) 'rollback-required' 'pre-complete crash phase';Assert-RXOldStateV010 $beforeComplete 'pre-complete crash' $true;$r2=Invoke-RXFixtureV010 $beforeComplete;Assert-RXTrue ([bool]$r2.ok) 'pre-complete restart denied';Assert-RXTrue ((Get-RXCountV010 $beforeComplete)-eq 2) 'pre-complete restart count';$count++

$tamperQ=New-RXFixtureV010 -Label 'result-tamper' -Nonce ('7'*32);$good=Invoke-RXFixtureV010 $tamperQ;Assert-RXTrue ([bool]$good.ok) 'result tamper setup failed';$bad=Copy-RX $good.result;$bad.restore_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $bad);$ck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $bad;Assert-RXFalse ([bool]$ck.ok) 'authority-tampered result accepted';Assert-RXTrue ([string]$ck.reason -like '*authority-escaped-restore_authorized') 'authority tamper reason';$bad=Copy-RX $good.result;$bad.result_fingerprint=('0'*64);$ck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $bad;Assert-RXFalse ([bool]$ck.ok) 'fingerprint-tampered result accepted';Assert-RXEq $ck.reason 'recovery-restore-executor-result-fingerprint-mismatch' 'fingerprint tamper reason';$before=(Get-RXCountV010 $tamperQ);$replay=Invoke-RXFixtureV010 $tamperQ;Assert-RXFalse ([bool]$replay.ok) 'rollback-complete replay accepted';Assert-RXTrue ([string]$replay.reason -like 'recovery-restore-executor-initial-admission-denied:*phase-not-auto-restorable') 'replay reason';Assert-RXTrue ((Get-RXCountV010 $tamperQ)-eq $before) 'replay launched apply';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_RESTORE_EXECUTOR_MATRIX_PASS total=$count"
