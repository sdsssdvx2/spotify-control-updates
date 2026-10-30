$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-remote-binding-observer-v0.4.0/custom-app-remote-binding-state.ps1')
. (Join-Path $root 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/test_custom_app_production_post_swap_apply_admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-spicetify-apply-executor.ps1')

$fakeRoot=Join-Path $env:TEMP ('spotify-control-fake-spicetify-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fakeRoot)|Out-Null
$fakeExe=Join-Path $fakeRoot 'spicetify.exe'
$fakeSource=@'
using System;
using System.IO;
using System.Threading;
public static class FakeSpicetify {
    static string E(string n) { return Environment.GetEnvironmentVariable(n) ?? ""; }
    static int NextCount(string path) {
        int n=0;
        if(File.Exists(path)) Int32.TryParse(File.ReadAllText(path).Trim(),out n);
        n++;
        File.WriteAllText(path,n.ToString());
        return n;
    }
    public static int Main(string[] args) {
        if(args == null || args.Length != 1 || args[0] != "apply") return 64;
        string counter=E("SC_FAKE_COUNTER");
        string log=E("SC_FAKE_LOG");
        string live=E("SC_FAKE_LIVE_INDEX");
        string applied=E("SC_FAKE_APPLIED_STATE");
        string persist=E("SC_FAKE_PERSISTENCE_FILE");
        string git=E("SC_FAKE_GIT_FILE");
        string mode=E("SC_FAKE_MODE");
        if(String.IsNullOrEmpty(counter) || String.IsNullOrEmpty(live) || String.IsNullOrEmpty(applied)) return 65;
        int count=NextCount(counter);
        if(!String.IsNullOrEmpty(log)) File.AppendAllText(log,count+"|"+mode+"|apply\n");
        string current=File.Exists(live) ? File.ReadAllText(live) : "";
        File.WriteAllText(applied,current);
        if(mode=="timeout-first" && count==1) { Thread.Sleep(4000); return 0; }
        if(mode=="mutate-live-first" && count==1) File.AppendAllText(live,"\n// fake-live-drift\n");
        if(mode=="mutate-git-first" && count==1 && File.Exists(git)) File.AppendAllText(git,"\n# fake-git-drift\n");
        if(mode=="mutate-persistence-first" && count==1 && File.Exists(persist)) File.AppendAllText(persist,"\n# fake-persistence-drift\n");
        if(mode=="fail-first" && count==1) return 7;
        if(mode=="fail-both") return 7;
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$fakeSha=(Get-FileHash -LiteralPath $fakeExe -Algorithm SHA256).Hash.ToLowerInvariant()
if($fakeSha -notmatch '^[0-9a-f]{64}$'){throw 'fake spicetify hash invalid'}

$script:ApplyExecutorFaultMode='none'
$script:ApplyExecutorStoreCurrent=$null
function Invoke-CustomAppProductionSpicetifyApplyExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:ApplyExecutorFaultMode){
        'throw-after-primary' { if($Checkpoint -ceq 'after-primary-apply-before-postcheck'){throw 'fixture-post-primary-hook-failure'} }
        'corrupt-store-after-primary' { if($Checkpoint -ceq 'after-primary-apply-before-postcheck'){[IO.File]::WriteAllText([string]$script:ApplyExecutorStoreCurrent,'{not-json',[Text.UTF8Encoding]::new($false))} }
        'drift-after-recovery' { if($Checkpoint -ceq 'after-recovery-apply'){[IO.File]::AppendAllText((Join-Path ([string]$Context.live_path) 'index.js'),"// fixture-post-recovery-drift`n",[Text.UTF8Encoding]::new($false))} }
    }
}

function New-ApplyExecutorFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd')
    $q=New-PostSwapApplyAdmissionFixtureV010 -Label ('apply-executor-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $control=Join-Path $env:TEMP ('spotify-control-apply-executor-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    return [pscustomobject]@{q=$q;control=$control;counter=(Join-Path $control 'counter.txt');log=(Join-Path $control 'calls.log');applied=(Join-Path $control 'applied-state.txt')}
}

function Set-ApplyExecutorFakeEnvironmentV010 {
    param($Fixture,[string]$Mode='success')
    $env:SC_FAKE_COUNTER=[string]$Fixture.counter
    $env:SC_FAKE_LOG=[string]$Fixture.log
    $env:SC_FAKE_LIVE_INDEX=Join-Path ([string]$Fixture.q.f.atomic.q.x.live) 'index.js'
    $env:SC_FAKE_APPLIED_STATE=[string]$Fixture.applied
    $env:SC_FAKE_PERSISTENCE_FILE=Join-Path ([string]$Fixture.q.f.atomic.q.persistence.roaming) 'spicetify\config-xpui.ini'
    $env:SC_FAKE_GIT_FILE=Join-Path ([string]$Fixture.q.f.atomic.q.x.live) '.git\config'
    $env:SC_FAKE_MODE=$Mode
}

function Get-ApplyExecutorFakeCountV010 {
    param($Fixture)
    if(-not (Test-Path -LiteralPath ([string]$Fixture.counter))){return 0}
    return [int]([IO.File]::ReadAllText([string]$Fixture.counter).Trim())
}

function Clear-ApplyExecutorFakeEnvironmentV010 {
    foreach($n in @('SC_FAKE_COUNTER','SC_FAKE_LOG','SC_FAKE_LIVE_INDEX','SC_FAKE_APPLIED_STATE','SC_FAKE_PERSISTENCE_FILE','SC_FAKE_GIT_FILE','SC_FAKE_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
    $script:ApplyExecutorFaultMode='none';$script:ApplyExecutorStoreCurrent=$null
}

function Invoke-ApplyExecutorFixtureV010 {
    param($Fixture,[string]$Mode='success',[string]$Exe=$fakeExe,[string]$ExpectedSha=$fakeSha,[int]$Timeout=10,[DateTimeOffset]$At=$now.AddSeconds(6))
    Set-ApplyExecutorFakeEnvironmentV010 -Fixture $Fixture -Mode $Mode
    $script:ApplyExecutorStoreCurrent=Join-Path ([string]$Fixture.q.f.atomic.q.x.store.store) 'current.json'
    try{
        return Invoke-CustomAppProductionSpicetifyApplyExecutorV010 -AllowedRoot $Fixture.q.f.atomic.q.x.store.root -StoreDirectory $Fixture.q.f.atomic.q.x.store.store -ExpectedConsumptionId ([string]$Fixture.q.f.atomic.q.x.consumption.consumption_id) -Permit $Fixture.q.f.atomic.q.x.permit -FinalizationResult $Fixture.q.finalization -PreparedResult $Fixture.q.f.atomic.prepared.result -StageExecutorResult $Fixture.q.f.atomic.q.stage.result -Name $Fixture.q.f.atomic.q.x.f.name -LifecycleRow $Fixture.q.f.atomic.q.x.f.lifecycle -ProvenanceRow $Fixture.q.f.atomic.q.x.f.provenance -BindingRow $Fixture.q.f.atomic.q.x.f.binding -SessionKey $key -LocalAppDataRoot $Fixture.q.f.atomic.q.persistence.local -AppDataRoot $Fixture.q.f.atomic.q.persistence.roaming -SpicetifyExecutablePath $Exe -ExpectedSpicetifySha256 $ExpectedSha -Now $At -TimeoutSeconds $Timeout
    }finally{Clear-ApplyExecutorFakeEnvironmentV010}
}

function Assert-ApplyExecutorNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.result_is_authority) "$Label result authority"
    Assert-False ([bool]$Result.spicetify_apply_authorized) "$Label spicetify authority"
    Assert-False ([bool]$Result.additional_mutation_authorized) "$Label additional mutation authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function Assert-ApplyExecutorBackupsPreservedV010 {
    param($Fixture,[string]$Label)
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.q.f.atomic.prepared.result.stage_path) -PathType Container) "$Label retained stage missing"
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.q.f.atomic.prepared.result.app_backup_path) -PathType Container) "$Label app backup missing"
    Assert-True (Test-Path -LiteralPath ([string]$Fixture.q.f.atomic.prepared.result.persistence_backup_path) -PathType Container) "$Label persistence backup missing"
}

function Assert-ApplyExecutorOldStateRestoredV010 {
    param($Fixture,[string]$Label,[bool]$RequireAppliedState=$true)
    $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Fixture.q.f.atomic.q.x.live)
    Assert-True ([string]$live.tree_sha256 -ceq [string]$Fixture.q.f.atomic.prepared.result.app_backup_tree_sha256) "$Label old app tree not restored"
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Fixture.q.f.atomic.q.persistence.local -AppDataRoot $Fixture.q.f.atomic.q.persistence.roaming
    Assert-True ([string]$persist.fingerprint -ceq [string]$Fixture.q.f.atomic.prepared.result.persistence_fingerprint) "$Label protected persistence not restored"
    Assert-ApplyExecutorBackupsPreservedV010 $Fixture $Label
    if($RequireAppliedState){
        Assert-True (Test-Path -LiteralPath ([string]$Fixture.applied) -PathType Leaf) "$Label fake applied state missing"
        $oldIndex=[IO.File]::ReadAllText((Join-Path ([string]$Fixture.q.f.atomic.prepared.result.app_backup_path) 'index.js'))
        $applied=[IO.File]::ReadAllText([string]$Fixture.applied)
        Assert-True ($applied -ceq $oldIndex) "$Label recovery apply did not target restored old state"
    }
}

function Assert-ApplyExecutorRolledBackV010 {
    param($Fixture,$Result,[string]$Label,[bool]$RollbackOk=$true)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded"
    Assert-True ([bool]$Result.spicetify_apply_executed) "$Label primary apply not recorded"
    Assert-True ([bool]$Result.rollback_attempted) "$Label rollback not attempted"
    if($RollbackOk){Assert-True ([bool]$Result.rollback_ok) "$Label rollback did not verify"}else{Assert-False ([bool]$Result.rollback_ok) "$Label rollback unexpectedly verified"}
    Assert-ApplyExecutorNoAuthorityV010 $Result $Label
    Assert-ApplyExecutorOldStateRestoredV010 $Fixture $Label
}

$count=0
$valid=New-ApplyExecutorFixtureV010 'valid'
$r=Invoke-ApplyExecutorFixtureV010 $valid
Assert-True ([bool]$r.ok) ('valid apply executor denied: '+[string]$r.reason)
Assert-True ([bool]$r.spicetify_apply_executed) 'valid apply not executed'
Assert-False ([bool]$r.rollback_attempted) 'valid apply attempted rollback'
Assert-True ([bool]$r.requires_post_apply_commit_cleanup) 'valid post-apply cleanup requirement missing'
Assert-ApplyExecutorNoAuthorityV010 $r 'valid'
Assert-True ((Get-ApplyExecutorFakeCountV010 $valid) -eq 1) 'valid apply call count not exactly one'
Assert-ApplyExecutorBackupsPreservedV010 $valid 'valid'
$newIndex=[IO.File]::ReadAllText((Join-Path ([string]$valid.q.f.atomic.q.x.live) 'index.js'));Assert-True ([IO.File]::ReadAllText([string]$valid.applied) -ceq $newIndex) 'valid fake applied state not new live state'
$check=Test-CustomAppProductionSpicetifyApplyResultV010 -Result $r.result;Assert-True ([bool]$check.ok) ('valid result self-check failed: '+[string]$check.reason)
$authority=Copy-Deep $r.result;$authority.spicetify_apply_authorized=$true;$authority.result_fingerprint=Get-CustomAppProductionSpicetifyApplyExecutorSha256V010 (Get-CustomAppProductionSpicetifyApplyResultMaterialV010 -Result $authority);$authorityCheck=Test-CustomAppProductionSpicetifyApplyResultV010 $authority;Assert-False ([bool]$authorityCheck.ok) 'authority-tampered apply receipt accepted'
$fingerprint=Copy-Deep $r.result;$fingerprint.result_fingerprint=('0'*64);$fingerprintCheck=Test-CustomAppProductionSpicetifyApplyResultV010 $fingerprint;Assert-False ([bool]$fingerprintCheck.ok) 'fingerprint-tampered apply receipt accepted'
$count++

$future=New-ApplyExecutorFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N 'e')
$r=Invoke-ApplyExecutorFixtureV010 $future;Assert-True ([bool]$r.ok) ('future app apply denied: '+[string]$r.reason);Assert-ApplyExecutorNoAuthorityV010 $r 'future-app';Assert-True ((Get-ApplyExecutorFakeCountV010 $future)-eq 1) 'future apply count drifted';$count++

$wrongHash=New-ApplyExecutorFixtureV010 'wrong-hash' -Nonce (N 'd');$r=Invoke-ApplyExecutorFixtureV010 -Fixture $wrongHash -ExpectedSha ('0'*64);Assert-False ([bool]$r.ok) 'wrong executable hash accepted';Assert-False ([bool]$r.spicetify_apply_executed) 'wrong executable hash launched process';Assert-True ((Get-ApplyExecutorFakeCountV010 $wrongHash)-eq 0) 'wrong hash process count nonzero';Assert-ApplyExecutorNoAuthorityV010 $r 'wrong-hash';$count++

$wrongName=New-ApplyExecutorFixtureV010 'wrong-name' -Nonce (N 'c');$wrongExe=Join-Path $wrongName.control 'not-spicetify.exe';[IO.File]::Copy($fakeExe,$wrongExe,$false);$wrongExeSha=(Get-FileHash $wrongExe -Algorithm SHA256).Hash.ToLowerInvariant();$r=Invoke-ApplyExecutorFixtureV010 -Fixture $wrongName -Exe $wrongExe -ExpectedSha $wrongExeSha;Assert-False ([bool]$r.ok) 'wrong executable name accepted';Assert-False ([bool]$r.spicetify_apply_executed) 'wrong name launched process';Assert-True ((Get-ApplyExecutorFakeCountV010 $wrongName)-eq 0) 'wrong name process count nonzero';$count++

$preDrift=New-ApplyExecutorFixtureV010 'pre-admission-drift' -Nonce (N 'b');[IO.File]::AppendAllText((Join-Path $preDrift.q.f.atomic.q.x.live 'index.js'),"// pre-apply-final-admission-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ApplyExecutorFixtureV010 $preDrift;Assert-False ([bool]$r.ok) 'pre-admission live drift accepted';Assert-False ([bool]$r.spicetify_apply_executed) 'pre-admission drift launched process';Assert-True ([string]$r.reason -like 'apply-final-admission-denied:*') 'pre-admission drift reason changed';Assert-True ((Get-ApplyExecutorFakeCountV010 $preDrift)-eq 0) 'pre-admission drift process count nonzero';$count++

$failFirst=New-ApplyExecutorFixtureV010 'fail-first' -Nonce (N 'a');$r=Invoke-ApplyExecutorFixtureV010 -Fixture $failFirst -Mode 'fail-first';Assert-ApplyExecutorRolledBackV010 $failFirst $r 'primary-fail-first';Assert-True ((Get-ApplyExecutorFakeCountV010 $failFirst)-eq 2) 'primary fail/recovery call count not two';Assert-True ([string]$r.reason -like 'primary-spicetify-apply-failed:*') 'primary fail reason changed';$count++

$timeout=New-ApplyExecutorFixtureV010 'timeout-first' -Nonce '10101010101010101010101010101010';$r=Invoke-ApplyExecutorFixtureV010 -Fixture $timeout -Mode 'timeout-first' -Timeout 1;Assert-ApplyExecutorRolledBackV010 $timeout $r 'primary-timeout';Assert-True ((Get-ApplyExecutorFakeCountV010 $timeout)-eq 2) 'timeout/recovery call count not two';Assert-True ([string]$r.reason -like 'primary-spicetify-apply-failed:spicetify-apply-process-timeout*') 'timeout reason changed';$count++

$liveDrift=New-ApplyExecutorFixtureV010 'live-drift' -Nonce '20202020202020202020202020202020';$r=Invoke-ApplyExecutorFixtureV010 -Fixture $liveDrift -Mode 'mutate-live-first';Assert-ApplyExecutorRolledBackV010 $liveDrift $r 'post-apply-live-drift';Assert-True ((Get-ApplyExecutorFakeCountV010 $liveDrift)-eq 2) 'live drift recovery count not two';Assert-True ([string]$r.reason -like 'post-spicetify-apply-verification-failed:post-apply-live-runtime-drift*') 'live drift reason changed';$count++

$gitDrift=New-ApplyExecutorFixtureV010 'git-drift' -Nonce '30303030303030303030303030303030';$r=Invoke-ApplyExecutorFixtureV010 -Fixture $gitDrift -Mode 'mutate-git-first';Assert-ApplyExecutorRolledBackV010 $gitDrift $r 'post-apply-git-drift';Assert-True ((Get-ApplyExecutorFakeCountV010 $gitDrift)-eq 2) 'git drift recovery count not two';Assert-True ([string]$r.reason -like 'post-spicetify-apply-verification-failed:post-apply-git-drift*') 'git drift reason changed';$count++

$persistDrift=New-ApplyExecutorFixtureV010 'persistence-drift' -Nonce '40404040404040404040404040404040';$r=Invoke-ApplyExecutorFixtureV010 -Fixture $persistDrift -Mode 'mutate-persistence-first';Assert-ApplyExecutorRolledBackV010 $persistDrift $r 'post-apply-persistence-drift';Assert-True ((Get-ApplyExecutorFakeCountV010 $persistDrift)-eq 2) 'persistence drift recovery count not two';Assert-True ([string]$r.reason -like 'post-spicetify-apply-verification-failed:post-apply-protected-persistence-drift*') 'persistence drift reason changed';$count++

$hook=New-ApplyExecutorFixtureV010 'hook-throw' -Nonce '50505050505050505050505050505050';$script:ApplyExecutorFaultMode='throw-after-primary';Set-ApplyExecutorFakeEnvironmentV010 -Fixture $hook -Mode 'success';$script:ApplyExecutorStoreCurrent=Join-Path ([string]$hook.q.f.atomic.q.x.store.store) 'current.json';try{$r=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 -AllowedRoot $hook.q.f.atomic.q.x.store.root -StoreDirectory $hook.q.f.atomic.q.x.store.store -ExpectedConsumptionId ([string]$hook.q.f.atomic.q.x.consumption.consumption_id) -Permit $hook.q.f.atomic.q.x.permit -FinalizationResult $hook.q.finalization -PreparedResult $hook.q.f.atomic.prepared.result -StageExecutorResult $hook.q.f.atomic.q.stage.result -Name $hook.q.f.atomic.q.x.f.name -LifecycleRow $hook.q.f.atomic.q.x.f.lifecycle -ProvenanceRow $hook.q.f.atomic.q.x.f.provenance -BindingRow $hook.q.f.atomic.q.x.f.binding -SessionKey $key -LocalAppDataRoot $hook.q.f.atomic.q.persistence.local -AppDataRoot $hook.q.f.atomic.q.persistence.roaming -SpicetifyExecutablePath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now.AddSeconds(6) -TimeoutSeconds 10}finally{Clear-ApplyExecutorFakeEnvironmentV010};Assert-ApplyExecutorRolledBackV010 $hook $r 'post-primary-hook-throw';Assert-True ((Get-ApplyExecutorFakeCountV010 $hook)-eq 2) 'hook throw recovery count not two';$count++

$store=New-ApplyExecutorFixtureV010 'store-corrupt-after-primary' -Nonce '60606060606060606060606060606060';$script:ApplyExecutorFaultMode='corrupt-store-after-primary';Set-ApplyExecutorFakeEnvironmentV010 -Fixture $store -Mode 'success';$script:ApplyExecutorStoreCurrent=Join-Path ([string]$store.q.f.atomic.q.x.store.store) 'current.json';try{$r=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 -AllowedRoot $store.q.f.atomic.q.x.store.root -StoreDirectory $store.q.f.atomic.q.x.store.store -ExpectedConsumptionId ([string]$store.q.f.atomic.q.x.consumption.consumption_id) -Permit $store.q.f.atomic.q.x.permit -FinalizationResult $store.q.finalization -PreparedResult $store.q.f.atomic.prepared.result -StageExecutorResult $store.q.f.atomic.q.stage.result -Name $store.q.f.atomic.q.x.f.name -LifecycleRow $store.q.f.atomic.q.x.f.lifecycle -ProvenanceRow $store.q.f.atomic.q.x.f.provenance -BindingRow $store.q.f.atomic.q.x.f.binding -SessionKey $key -LocalAppDataRoot $store.q.f.atomic.q.persistence.local -AppDataRoot $store.q.f.atomic.q.persistence.roaming -SpicetifyExecutablePath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now.AddSeconds(6) -TimeoutSeconds 10}finally{Clear-ApplyExecutorFakeEnvironmentV010};Assert-ApplyExecutorRolledBackV010 $store $r 'post-primary-store-corrupt';Assert-True ((Get-ApplyExecutorFakeCountV010 $store)-eq 2) 'store corrupt recovery count not two';Assert-True ([string]$r.reason -like 'post-spicetify-apply-consumption-revalidation-failed:*') 'store corrupt reason changed';$count++

$failBoth=New-ApplyExecutorFixtureV010 'fail-both' -Nonce '70707070707070707070707070707070';$r=Invoke-ApplyExecutorFixtureV010 -Fixture $failBoth -Mode 'fail-both';Assert-ApplyExecutorRolledBackV010 $failBoth $r 'primary-and-recovery-fail' $false;Assert-True ((Get-ApplyExecutorFakeCountV010 $failBoth)-eq 2) 'fail-both call count not two';Assert-True ([string]$r.rollback_result.reason -like 'rollback-recovery-apply-failed:*') 'fail-both recovery reason changed';$count++

$postRecovery=New-ApplyExecutorFixtureV010 'post-recovery-drift' -Nonce '80808080808080808080808080808080';$script:ApplyExecutorFaultMode='drift-after-recovery';Set-ApplyExecutorFakeEnvironmentV010 -Fixture $postRecovery -Mode 'fail-first';$script:ApplyExecutorStoreCurrent=Join-Path ([string]$postRecovery.q.f.atomic.q.x.store.store) 'current.json';try{$r=Invoke-CustomAppProductionSpicetifyApplyExecutorV010 -AllowedRoot $postRecovery.q.f.atomic.q.x.store.root -StoreDirectory $postRecovery.q.f.atomic.q.x.store.store -ExpectedConsumptionId ([string]$postRecovery.q.f.atomic.q.x.consumption.consumption_id) -Permit $postRecovery.q.f.atomic.q.x.permit -FinalizationResult $postRecovery.q.finalization -PreparedResult $postRecovery.q.f.atomic.prepared.result -StageExecutorResult $postRecovery.q.f.atomic.q.stage.result -Name $postRecovery.q.f.atomic.q.x.f.name -LifecycleRow $postRecovery.q.f.atomic.q.x.f.lifecycle -ProvenanceRow $postRecovery.q.f.atomic.q.x.f.provenance -BindingRow $postRecovery.q.f.atomic.q.x.f.binding -SessionKey $key -LocalAppDataRoot $postRecovery.q.f.atomic.q.persistence.local -AppDataRoot $postRecovery.q.f.atomic.q.persistence.roaming -SpicetifyExecutablePath $fakeExe -ExpectedSpicetifySha256 $fakeSha -Now $now.AddSeconds(6) -TimeoutSeconds 10}finally{Clear-ApplyExecutorFakeEnvironmentV010};Assert-False ([bool]$r.ok) 'post-recovery drift unexpectedly succeeded';Assert-True ([bool]$r.rollback_attempted) 'post-recovery drift rollback not attempted';Assert-False ([bool]$r.rollback_ok) 'post-recovery drift incorrectly marked rollback ok';Assert-True ([string]$r.rollback_result.reason -ceq 'rollback-postcheck-app-tree-mismatch') 'post-recovery drift reason changed';Assert-ApplyExecutorBackupsPreservedV010 $postRecovery 'post-recovery-drift';$count++

Write-Host "CUSTOM_APP_PRODUCTION_SPICETIFY_APPLY_EXECUTOR_MATRIX_PASS total=$count fake_sha=$fakeSha"
