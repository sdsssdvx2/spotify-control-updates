$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Run the exact parent matrix first so all qualified recovery-aware fixture helpers are
# loaded in this process. The workflow separately runs the parent's final r4/r5 semantic
# harness; below we redefine only New-RAPPFixtureV010 so this layer never mutates live
# bytes after recovery closure merely to create VCS provenance.
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')

function Assert-RAATrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAAFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAAEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAA($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$Nonce,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $built=New-RAPPByteRealCarrierV010 -Label $Label -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $f=$built.carrier;$q=$built.ready;$at=$q.at.AddSeconds(12)
    $stage=Invoke-RASEFixtureV010 -F $f -At $at -PostAt $at.AddSeconds(1)
    if(-not [bool]$stage.ok){throw ('fixture recovery-aware stage failed: '+[string]$stage.reason)}
    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $built.bundle.binding -ExpectedName ([string]$built.bundle.lifecycle.name)
    if(-not [bool]$binding.ok){throw ('fixture binding denied: '+[string]$binding.reason)}
    Assert-RAPPEq ([string]$stage.result.local_tree_sha256).Trim().ToLowerInvariant() ([string]$built.stable_tree).Trim().ToLowerInvariant() 'fixture stable recovery stage-local tree'
    Write-ProductionStageRuntimeV010 ([string]$stage.result.stage_path) ([string]$binding.manifest_name) (([string]$built.bundle.lifecycle.name)+'-remote-v2')
    $stageBaseline=& $script:RASEOriginalLocalBaseline -Name ([string]$built.bundle.lifecycle.name) -AppPath ([string]$stage.result.stage_path)
    Assert-RAPPEq ([string]$stageBaseline.tree_sha256).Trim().ToLowerInvariant() ([string]$stage.result.remote_tree_sha256).Trim().ToLowerInvariant() 'fixture byte-real stage tree'
    Assert-RAPPEq ([string]$stageBaseline.tree_sha256).Trim().ToLowerInvariant() ([string]$built.remote_tree).Trim().ToLowerInvariant() 'fixture stage pre-permit probe'
    # Recovery closure is durable evidence. Do not add .git or any other bytes here.
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
    $base=Join-Path $env:TEMP ('raa-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    return [pscustomobject]@{f=$f;q=$q;bundle=$built.bundle;stage=$stage.result;at=([DateTimeOffset]::Parse([string]$stage.result.post_stage_revalidated_at).AddSeconds(1));rollback=(Join-Path $base 'rollback');persistence=(Join-Path $base 'persistence');base=$base;live_path=[string]$built.live_path;remote_tree=[string]$built.remote_tree;stable_tree=[string]$built.stable_tree;actual_live_tree=[string]$built.actual_live_tree;manifest_name=[string]$built.manifest_name;raw_live_snapshot=$rawLive}
}

$script:RAAAtomicFaultMode='none'
$script:RAAStoreDriftPath=$null
function Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    switch($script:RAAAtomicFaultMode){
        'throw-after-candidate-move' {if($Checkpoint -ceq 'after-candidate-move'){throw 'raa-fixture-after-candidate-move'}}
        'ledger-drift-after-atomic-verification' {if($Checkpoint -ceq 'after-post-verify' -and -not [string]::IsNullOrWhiteSpace([string]$script:RAAStoreDriftPath)){[IO.File]::WriteAllText((Join-Path $script:RAAStoreDriftPath 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false))}}
    }
}

function New-RAAFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$Nonce,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $x=New-RAPPFixtureV010 -Label ('raa-'+$Label) -Nonce $Nonce -Name $Name -Source $Source -Manifest $Manifest
    $pre=Invoke-RAPPFixtureV010 -X $x
    if(-not [bool]$pre.ok){throw ('RAA fixture pre-apply failed: '+[string]$pre.reason)}
    $liveBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root $x.live_path
    $runtimeBefore=& $script:RASEOriginalLocalBaseline -Name $Name -AppPath $x.live_path
    $persistBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $x.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $x.q.f.ce.q.f.f.q.persistence.roaming
    $storeBefore=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $x.q.f.ce.q.f.f.allowed -StoreDirectory $x.f.p.store
    if(-not [bool]$storeBefore.ok){throw ('RAA fixture consumption store unreadable: '+[string]$storeBefore.reason)}
    return [pscustomobject]@{x=$x;pre=$pre;live_before=$liveBefore;runtime_before=$runtimeBefore;persistence_before=$persistBefore;store_before=$storeBefore}
}

function Invoke-RAAFixtureV010 {
    param([Parameter(Mandatory=$true)]$F,[AllowNull()]$PreApply=$null,[AllowNull()]$Stage=$null,[AllowNull()]$Lifecycle=$null,[AllowNull()]$Binding=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,[string]$Fault='none')
    if($null -eq $PreApply){$PreApply=$F.pre.result};if($null -eq $Stage){$Stage=$F.x.stage};if($null -eq $Lifecycle){$Lifecycle=$F.x.bundle.lifecycle};if($null -eq $Binding){$Binding=$F.x.bundle.binding};if($null -eq $Permit){$Permit=$F.x.f.p.f.p.r.issuer.permit};if($null -eq $Key){$Key=$script:RAIssuerKey}
    $when=[DateTimeOffset]::Parse([string]$F.pre.result.post_backup_revalidated_at).AddSeconds(1);$ctx=New-RAIssueLiveContextV010 -Bundle $F.x.bundle
    $priorOverride=$script:RAPPFreshLiveOverride;$priorFault=$script:RAAAtomicFaultMode;$priorStore=$script:RAAStoreDriftPath
    $script:RAPPFreshLiveOverride=[pscustomobject]@{stable_tree_sha256=[string]$F.x.stable_tree;actual_tree_sha256=[string]$F.x.actual_live_tree;live_path=[string]$F.x.live_path;manifest_name=[string]$F.x.manifest_name};$script:RAAAtomicFaultMode=$Fault;$script:RAAStoreDriftPath=[string]$F.x.f.p.store
    try{
        return Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 -RecoveryAwarePreApplyResult $PreApply -RecoveryAwareStageExecutorResult $Stage -Name ([string]$F.x.bundle.lifecycle.name) -LifecycleRow $Lifecycle -ProvenanceRow $F.x.bundle.provenance -BindingRow $Binding -LifecycleStageResult $F.x.bundle.stage -ShadowResult $F.x.bundle.shadow -RetirementResumeResult $F.x.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $F.x.q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $F.x.q.f.ce.q.f.f.store -ConsumptionStoreDirectory $F.x.f.p.store -ExpectedTransactionId ([string]$F.x.q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $F.x.f.persisted -Permit $Permit -SessionKey $Key -Now $when
    } finally {$script:RAPPFreshLiveOverride=$priorOverride;$script:RAAAtomicFaultMode=$priorFault;$script:RAAStoreDriftPath=$priorStore}
}

function Assert-RAANoAuthorityV010($R,[string]$Label){$o=if($R.PSObject.Properties['result'] -and $null -ne $R.result){$R.result}else{$R};foreach($f in @('session_key_persisted','session_key_exposed','atomic_result_is_authority','apply_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAAFalse ([bool]$o.$f) "$Label escaped $f"};Assert-RAATrue ([bool]$o.requires_transaction_finalization) "$Label missing transaction finalization";Assert-RAATrue ([bool]$o.requires_fresh_post_swap_apply_admission) "$Label missing fresh post-swap admission";Assert-RAATrue ([bool]$o.requires_spicetify_apply_phase) "$Label missing apply separation"}
function Assert-RAAOriginalLiveV010($F,[string]$Label){$full=Get-CustomAppUpdateTreeSnapshotV010 -Root $F.x.live_path;Assert-RAAEq $full.tree_sha256 $F.live_before.tree_sha256 "$Label live tree";$runtime=& $script:RASEOriginalLocalBaseline -Name ([string]$F.x.bundle.lifecycle.name) -AppPath $F.x.live_path;Assert-RAAEq $runtime.tree_sha256 $F.runtime_before.tree_sha256 "$Label runtime tree";$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAAEq $persist.fingerprint $F.persistence_before.fingerprint "$Label persistence"}
function Cleanup-RAAFixtureV010($F,$R=$null){try{if($null -ne $R -and [bool]$R.ok -and $null -ne $R.result){$rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$R.result.live_path) -AppBackupPath ([string]$F.pre.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$F.pre.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$F.pre.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$F.pre.result.persistence_fingerprint) -LocalAppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $F.x.q.f.ce.q.f.f.q.persistence.roaming;if(-not [bool]$rb.ok){throw ('RAA cleanup rollback failed: '+[string]$rb.reason)}}}finally{try{$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$F.x.live_path));Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue|Where-Object{$_.Name -like '.spotify-control-txn-*'}|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue}catch{};Remove-RAPPFixtureV010 $F.x}}

$raaCount=0
$valid=New-RAAFixtureV010 -Label 'valid' -Nonce ('1'*32);$r=$null
try{$r=Invoke-RAAFixtureV010 -F $valid;Assert-RAATrue ([bool]$r.ok) ('valid RAA denied: '+[string]$r.reason);Assert-RAAEq $r.reason 'recovery-aware-atomic-live-code-swap-verified-no-spicetify-apply' 'valid reason';Assert-RAANoAuthorityV010 $r 'valid';$check=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $r.result;Assert-RAATrue ([bool]$check.ok) ('valid result '+[string]$check.reason);Assert-RAAEq $r.result.post_runtime_tree_sha256 $valid.x.remote_tree 'valid remote tree';Assert-RAAEq $r.result.old_live_tree_sha256 $valid.pre.result.app_backup_tree_sha256 'valid old-live';Assert-RAAEq $r.result.current_consumption_envelope_sha256 $valid.store_before.envelope.envelope_sha256 'valid ledger';Assert-RAAFalse ([bool]$r.result.PSObject.Properties['session_key']) 'session key leaked';$raaCount++}finally{Cleanup-RAAFixtureV010 $valid $r}

$future=New-RAAFixtureV010 -Label 'future' -Nonce ('2'*32) -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App';$r=$null
try{$r=Invoke-RAAFixtureV010 -F $future;Assert-RAATrue ([bool]$r.ok) ('future app denied: '+[string]$r.reason);Assert-RAANoAuthorityV010 $r 'future';$raaCount++}finally{Cleanup-RAAFixtureV010 $future $r}

$fp=New-RAAFixtureV010 -Label 'fingerprint' -Nonce ('3'*32)
try{$bad=Copy-RAA $fp.pre.result;$bad.result_fingerprint=('0'*64);$r=Invoke-RAAFixtureV010 -F $fp -PreApply $bad;Assert-RAAFalse ([bool]$r.ok) 'fingerprint tamper accepted';Assert-RAATrue ([string]$r.reason -like '*fingerprint-mismatch*') ('fingerprint reason '+[string]$r.reason);Assert-RAAOriginalLiveV010 $fp 'fingerprint';$raaCount++}finally{Cleanup-RAAFixtureV010 $fp}

$key=New-RAAFixtureV010 -Label 'wrong-key' -Nonce ('4'*32)
try{$badKey=New-Object byte[] 32;[Array]::Copy($script:RAIssuerKey,$badKey,32);$badKey[0]=$badKey[0] -bxor 0x42;$r=Invoke-RAAFixtureV010 -F $key -Key $badKey;Assert-RAAFalse ([bool]$r.ok) 'wrong key accepted';Assert-RAATrue ([string]$r.reason -like 'recovery-aware-atomic-pre-swap-admission-denied:*') ('wrong key reason '+[string]$r.reason);Assert-RAAOriginalLiveV010 $key 'wrong-key';$raaCount++}finally{Cleanup-RAAFixtureV010 $key}

$stage=New-RAAFixtureV010 -Label 'stage-drift' -Nonce ('5'*32)
try{[IO.File]::AppendAllText((Join-Path ([string]$stage.x.stage.stage_path) 'index.js'),"// raa-stage-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-RAAFixtureV010 -F $stage;Assert-RAAFalse ([bool]$r.ok) 'stage drift accepted';Assert-RAATrue ([bool]$r.generic_atomic_invoked) 'stage drift did not reach generic atomic';Assert-RAATrue ([string]$r.reason -like '*stage-runtime-precondition-mismatch*') ('stage drift reason '+[string]$r.reason);Assert-RAAOriginalLiveV010 $stage 'stage-drift';$raaCount++}finally{Cleanup-RAAFixtureV010 $stage}

$post=New-RAAFixtureV010 -Label 'post-mutation' -Nonce ('6'*32)
try{$r=Invoke-RAAFixtureV010 -F $post -Fault 'throw-after-candidate-move';Assert-RAAFalse ([bool]$r.ok) 'post mutation fault succeeded';Assert-RAATrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) 'generic rollback missing';Assert-RAATrue ([string]$r.reason -like '*raa-fixture-after-candidate-move*') ('post mutation reason '+[string]$r.reason);Assert-RAAOriginalLiveV010 $post 'post-mutation';Assert-RAANoAuthorityV010 $r 'post-mutation';$raaCount++}finally{Cleanup-RAAFixtureV010 $post}

$wrapper=New-RAAFixtureV010 -Label 'wrapper-postcheck' -Nonce ('7'*32)
try{$r=Invoke-RAAFixtureV010 -F $wrapper -Fault 'ledger-drift-after-atomic-verification';Assert-RAAFalse ([bool]$r.ok) 'wrapper ledger fault succeeded';Assert-RAATrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) 'wrapper postcheck rollback missing';Assert-RAATrue ([string]$r.reason -like 'recovery-aware-atomic-consumption-store-post-*') ('wrapper ledger reason '+[string]$r.reason);Assert-RAAOriginalLiveV010 $wrapper 'wrapper-postcheck';Assert-RAANoAuthorityV010 $r 'wrapper-postcheck';$raaCount++}finally{Cleanup-RAAFixtureV010 $wrapper}

if($raaCount -ne 7){throw "RAA matrix count mismatch $raaCount != 7"}
Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_LIVE_SWAP_MATRIX_PASS count=$raaCount recovery_closed_fixture=true recovery_revalidated_before_mutation=true generic_atomic_exact_once=true wrapper_postcheck_rollback=true ledger_immutable=true zero_post_swap_apply_authority=true"
