$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-bridge-aware-post-swap-apply-admission-v0.1.0/test_custom_app_production_dual_id_bridge_aware_post_swap_apply_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-bridge-aware-spicetify-apply-executor.ps1')

function Assert-DBAXTrue([bool]$Value,[string]$Message){if(-not$Value){throw$Message}}
function Assert-DBAXFalse([bool]$Value,[string]$Message){if($Value){throw$Message}}
function Assert-DBAXEq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw"$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-DBAX($Value){return(($Value|ConvertTo-Json -Depth 80)|ConvertFrom-Json)}
function Assert-DBAXNoAuthority($Value,[string]$Label){foreach($f in @('result_is_authority','apply_execution_authorized','spicetify_apply_authorized','cleanup_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-DBAXFalse([bool]$Value.$f)("$Label escaped $f")}}}

$fakeDir=Join-Path $env:RUNNER_TEMP ('dbax-fake-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($fakeDir)|Out-Null
$fakeExe=Join-Path $fakeDir 'spicetify.exe'
$fakeSource=@"
using System;
using System.IO;
public static class DualIdApplyFake {
    public static int Main(string[] args) {
        if (args == null || args.Length != 1 || !String.Equals(args[0], "apply", StringComparison.Ordinal)) return 91;
        var p=Environment.GetEnvironmentVariable("DBAX_COUNT"); if (String.IsNullOrWhiteSpace(p)) return 92;
        int n=0; if (File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(), out n); File.WriteAllText(p,(n+1).ToString());
        var mode=Environment.GetEnvironmentVariable("DBAX_MODE") ?? "success";
        if (String.Equals(mode,"fail-first",StringComparison.OrdinalIgnoreCase) && n==0) return 7;
        if (String.Equals(mode,"fail-always",StringComparison.OrdinalIgnoreCase)) return 8;
        return 0;
    }
}
"@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
Assert-DBAXTrue(Test-Path -LiteralPath $fakeExe -PathType Leaf)'fake spicetify.exe missing'
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()

$script:DBAXFault=$null
function Invoke-CustomAppProductionDualIdBridgeAwareSpicetifyApplyExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if(-not[string]::IsNullOrWhiteSpace([string]$script:DBAXFault)-and$Checkpoint-ceq$script:DBAXFault){throw('DBAX_SIMULATED_PROCESS_DEATH_'+$Checkpoint)}
}
function New-DBAXFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    $q=New-DBAPFixtureV010 ('dbax-'+$Label)
    $prior=Invoke-DBAPV010 $q
    Assert-DBAXTrue($null-ne$prior-and[bool]$prior.ok)("prior dual-ID admission denied $Label: $([string]$prior.reason)")
    return[pscustomobject]@{q=$q;prior=$prior}
}
function Invoke-DBAXV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)][string]$CountPath,[string]$Mode='success',[string]$ExpectedSha=$fakeSha,[AllowNull()]$Prior=$null)
    $q=$X.q;$f=$q.f;if($null-eq$Prior){$Prior=$X.prior.decision}
    $env:DBAX_COUNT=$CountPath;$env:DBAX_MODE=$Mode
    try{
        return Invoke-CustomAppProductionDualIdBridgeAwareSpicetifyApplyExecutorV010 -PriorAdmissionDecision $Prior -DualIdFinalizationResult $q.final.result -DurableBridgeIntegrationResult $f.bridge.result -EvidenceBoundAtomicResult $f.atomic -RecoveryAwarePreparedResult $f.x.carrier -RecoveryAwareStageExecutorResult $f.x.stage -GenericPreparedResult $f.x.generic -GenericStageExecutorResult $f.x.fixture.q.stage.result -Permit $f.x.fixture.q.x.permit -Name $f.name -LifecycleRow $f.x.fixture.q.x.f.lifecycle -ProvenanceRow $f.x.fixture.q.x.f.provenance -BindingRow $f.x.fixture.q.x.f.binding -AllowedRoot $f.trust -JournalStoreDirectory $f.store -ConsumptionStoreDirectory $f.x.fixture.q.x.store.store -SessionKey $script:DBAPSessionKey -LocalAppDataRoot ([string]$f.x.fixture.q.persistence.local) -AppDataRoot ([string]$f.x.fixture.q.persistence.roaming) -SpicetifyExecutablePath $fakeExe -ExpectedSpicetifySha256 $ExpectedSha -Now ([DateTimeOffset]::UtcNow) -TimeoutSeconds 15
    } finally {Remove-Item Env:DBAX_COUNT -ErrorAction SilentlyContinue;Remove-Item Env:DBAX_MODE -ErrorAction SilentlyContinue}
}
function Get-DBAXCountV010([string]$Path){$n=0;if(Test-Path -LiteralPath $Path -PathType Leaf){[void][int]::TryParse(([IO.File]::ReadAllText($Path)).Trim(),[ref]$n)};return$n}
function Read-DBAXJournalV010($X){return Read-CustomAppProductionCrashJournalV010 -AllowedRoot $X.q.f.trust -StoreDirectory $X.q.f.store}
function Assert-DBAXCrashPhaseV010($X,[string]$Expected,[int]$ExpectedCount,[string]$CountPath){$j=Read-DBAXJournalV010 $X;Assert-DBAXTrue($null-ne$j-and[bool]$j.ok)"$Expected journal unreadable";Assert-DBAXEq([string]$j.entry.phase)$Expected "$Expected journal phase";Assert-DBAXEq([string]$j.transaction_id).Trim().ToLowerInvariant()([string]$X.q.final.result.journal_transaction_id).Trim().ToLowerInvariant() "$Expected journal id";Assert-DBAXTrue(Test-CustomAppProductionCrashJournalTransitionV010 -From $Expected -To 'rollback-required')"$Expected cannot transition to rollback-required";Assert-DBAXTrue((Get-DBAXCountV010 $CountPath)-eq$ExpectedCount)"$Expected fake apply count drift"}

$count=0

# 1. Success: exactly one primary apply and durable apply-verified evidence.
$script:DBAXFault=$null;$x=New-DBAXFixtureV010 'success';$c=Join-Path $fakeDir 'success-count.txt';$r=Invoke-DBAXV010 -X $x -CountPath $c
Assert-DBAXTrue([bool]$r.ok)('success apply denied: '+[string]$r.reason);Assert-DBAXTrue((Get-DBAXCountV010 $c)-eq1)'success apply count not exactly one';Assert-DBAXNoAuthority $r 'success wrapper';Assert-DBAXNoAuthority $r.result 'success result'
$rc=Test-CustomAppProductionDualIdBridgeAwareSpicetifyApplyResultV010 $r.result;Assert-DBAXTrue([bool]$rc.ok)('success result validator denied: '+[string]$rc.reason)
Assert-DBAXFalse(([string]$r.result.permit_transaction_id)-ceq([string]$r.result.journal_transaction_id))'success transaction namespaces conflated'
$j=Read-DBAXJournalV010 $x;Assert-DBAXEq([string]$j.entry.phase)'apply-verified' 'success journal phase';Assert-DBAXEq([string]$j.entry.apply_result_fingerprint).Trim().ToLowerInvariant()([string]$r.result.apply_evidence_fingerprint).Trim().ToLowerInvariant() 'success journal apply evidence'
Assert-DBAXEq([string]$j.entry.finalization_fingerprint).Trim().ToLowerInvariant()([string]$x.q.final.result.result_fingerprint).Trim().ToLowerInvariant() 'success finalization fingerprint'
$count++

# 2. Crash after apply-starting barrier, before process: process never ran; journal is recoverable.
$script:DBAXFault='after-apply-starting-barrier-before-process';$x2=New-DBAXFixtureV010 'crash-after-start';$c2=Join-Path $fakeDir 'crash-start-count.txt';$r2=Invoke-DBAXV010 -X $x2 -CountPath $c2
Assert-DBAXFalse([bool]$r2.ok)'crash-after-start unexpectedly succeeded';Assert-DBAXTrue([bool]$r2.requires_recovery)'crash-after-start missing recovery requirement';Assert-DBAXCrashPhaseV010 $x2 'apply-starting' 0 $c2;$count++

# 3. Crash after process returned success but before pending barrier: one apply happened, journal remains apply-starting so recovery rolls back conservatively.
$script:DBAXFault='after-primary-success-before-pending-barrier';$x3=New-DBAXFixtureV010 'crash-after-primary';$c3=Join-Path $fakeDir 'crash-primary-count.txt';$r3=Invoke-DBAXV010 -X $x3 -CountPath $c3
Assert-DBAXFalse([bool]$r3.ok)'crash-after-primary unexpectedly succeeded';Assert-DBAXTrue([bool]$r3.requires_recovery)'crash-after-primary missing recovery requirement';Assert-DBAXCrashPhaseV010 $x3 'apply-starting' 1 $c3;$count++

# 4. Crash after durable pending barrier: one apply happened and journal explicitly says success returned but verification was incomplete.
$script:DBAXFault='after-pending-barrier-before-verification';$x4=New-DBAXFixtureV010 'crash-pending';$c4=Join-Path $fakeDir 'crash-pending-count.txt';$r4=Invoke-DBAXV010 -X $x4 -CountPath $c4
Assert-DBAXFalse([bool]$r4.ok)'crash-pending unexpectedly succeeded';Assert-DBAXTrue([bool]$r4.requires_recovery)'crash-pending missing recovery requirement';Assert-DBAXCrashPhaseV010 $x4 'apply-returned-success-pending-verification' 1 $c4;$count++

# 5. First apply fails. rollback-required is durable before restore; recovery apply is the second process; terminal rollback-complete is durable.
$script:DBAXFault=$null;$x5=New-DBAXFixtureV010 'fail-first-rollback';$c5=Join-Path $fakeDir 'fail-first-count.txt';$r5=Invoke-DBAXV010 -X $x5 -CountPath $c5 -Mode 'fail-first'
Assert-DBAXFalse([bool]$r5.ok)'fail-first unexpectedly reported success';Assert-DBAXTrue([bool]$r5.rollback_attempted)'fail-first did not attempt rollback';Assert-DBAXTrue([bool]$r5.rollback_ok)'fail-first rollback failed';Assert-DBAXTrue([bool]$r5.rollback_complete_persisted)'fail-first rollback-complete not persisted';Assert-DBAXTrue((Get-DBAXCountV010 $c5)-eq2)'fail-first expected primary failure + one recovery apply'
$j5=Read-DBAXJournalV010 $x5;Assert-DBAXEq([string]$j5.entry.phase)'rollback-complete' 'fail-first terminal journal phase'
$live5=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$x5.q.f.x.fixture.q.x.live);Assert-DBAXEq([string]$live5.tree_sha256).Trim().ToLowerInvariant()([string]$x5.q.final.result.old_live_tree_sha256).Trim().ToLowerInvariant() 'fail-first old app not restored'
$p5=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$x5.q.f.x.fixture.q.persistence.local) -AppDataRoot ([string]$x5.q.f.x.fixture.q.persistence.roaming);Assert-DBAXEq([string]$p5.fingerprint).Trim().ToLowerInvariant()([string]$x5.q.f.x.generic.persistence_fingerprint).Trim().ToLowerInvariant() 'fail-first protected persistence not restored';Assert-DBAXNoAuthority $r5 'fail-first wrapper';$count++

# 6. Wrong executable hash is rejected before apply-starting barrier, so no new recovery obligation is created.
$script:DBAXFault=$null;$x6=New-DBAXFixtureV010 'wrong-exe-hash';$c6=Join-Path $fakeDir 'wrong-hash-count.txt';$wrong=('0'*64);if($wrong-ceq$fakeSha){$wrong=('1'*64)};$r6=Invoke-DBAXV010 -X $x6 -CountPath $c6 -ExpectedSha $wrong
Assert-DBAXFalse([bool]$r6.ok)'wrong executable hash accepted';Assert-DBAXFalse([bool]$r6.requires_recovery)'wrong executable hash created recovery obligation';Assert-DBAXTrue((Get-DBAXCountV010 $c6)-eq0)'wrong executable hash launched process';$j6=Read-DBAXJournalV010 $x6;Assert-DBAXEq([string]$j6.entry.phase)'transaction-finalized' 'wrong executable hash changed journal phase';$count++

# 7. Rehashed prior admission ID substitution is rejected before any journal/process side effect.
$x7=New-DBAXFixtureV010 'prior-id-drift';$bad=Copy-DBAX $x7.prior.decision;$bad.permit_transaction_id=('0'*64);if([string]$bad.permit_transaction_id-ceq[string]$bad.journal_transaction_id){$bad.permit_transaction_id=('1'*64)};$bad.admission_fingerprint=Get-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionSha256V010(Get-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionMaterialV010 $bad);$bc=Test-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionDecisionV010 $bad;Assert-DBAXTrue([bool]$bc.ok)('prior drift fixture no longer structurally valid: '+[string]$bc.reason)
$c7=Join-Path $fakeDir 'prior-drift-count.txt';$r7=Invoke-DBAXV010 -X $x7 -CountPath $c7 -Prior $bad;Assert-DBAXFalse([bool]$r7.ok)'prior ID drift accepted';Assert-DBAXTrue([string]$r7.reason-like'*admission-continuity-mismatch-permit_transaction_id*')('prior drift reason changed: '+[string]$r7.reason);Assert-DBAXTrue((Get-DBAXCountV010 $c7)-eq0)'prior drift launched process';$j7=Read-DBAXJournalV010 $x7;Assert-DBAXEq([string]$j7.entry.phase)'transaction-finalized' 'prior drift changed journal phase';$count++

$script:DBAXFault=$null
if($count-ne7){throw"dual-ID journal-aware apply executor matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_DUAL_ID_BRIDGE_AWARE_SPICETIFY_APPLY_EXECUTOR_PASS cases=$count exact_fake_apply=true success_count_one=true apply_starting_barrier=true pending_barrier=true apply_verified_barrier=true crash_windows_recoverable=true rollback_required_before_restore=true rollback_complete_after_recovery_apply=true permit_id_forward_only=true journal_id_recovery_only=true zero_authority=true"
