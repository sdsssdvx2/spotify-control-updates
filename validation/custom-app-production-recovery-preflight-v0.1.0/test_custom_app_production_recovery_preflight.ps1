$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-preflight.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-False([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function N([string]$c){return ($c*64)}
function Copy-Obj($x){return (($x|ConvertTo-Json -Depth 40)|ConvertFrom-Json)}

$script:Now=[DateTimeOffset]::UtcNow.AddMinutes(-2)
$script:FinalFp=N 'f';$script:ApplyFp=N 'a';$script:CleanupFp=N 'c'
$script:NormalChain=@('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')

function Write-FixtureFile([string]$Path,[string]$Text){$parent=[IO.Path]::GetDirectoryName($Path);if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}

function New-PreflightFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$TargetPhase)
    $base=Join-Path $env:RUNNER_TEMP ('recovery-preflight-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($base)|Out-Null
    $paths=[ordered]@{live=(Join-Path $base 'CustomApps\demo');txn=(Join-Path $base '.spotify-control-txn-11111111111111111111111111111111');stage=(Join-Path $base 'stage-workspace');app=(Join-Path $base 'backups\app-code');persist=(Join-Path $base 'backups\persistence');store=(Join-Path $base 'journal');exeRoot=(Join-Path $base 'bin');exe=(Join-Path $base 'bin\spicetify.exe')}
    foreach($p in @($paths.live,$paths.txn,$paths.stage,$paths.app,$paths.persist,$paths.exeRoot)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    Write-FixtureFile (Join-Path $paths.live 'index.js') "console.log('live');`n"
    Write-FixtureFile (Join-Path $paths.txn 'old-live\index.js') "console.log('old');`n"
    Write-FixtureFile (Join-Path $paths.stage 'stage\index.js') "console.log('stage');`n"
    Write-FixtureFile (Join-Path $paths.app 'index.js') "console.log('backup');`n"
    Write-FixtureFile (Join-Path $paths.persist 'guard-manifest.json') '{"schema":1}'
    Write-FixtureFile $paths.exe 'fake-spicetify-binary-v1'
    $exeSha=Get-CustomAppProductionRecoveryPreflightFileSha256V010 $paths.exe
    $id=New-CustomAppProductionCrashJournalIdentityV010 -Name 'demo' -ConsumptionId (N '1') -SourceIdentity 'owner/demo' -RemoteCommitSha ('2'*40) -StageResultFingerprint (N '3') -PreparationFingerprint (N '4') -AllowedRoot $base -LivePath $paths.live -TransactionRoot $paths.txn -StageWorkspacePath $paths.stage -AppBackupPath $paths.app -PersistenceBackupPath $paths.persist
    $cur=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $base -StoreDirectory $paths.store -Identity $id -Now $script:Now
    if(-not [bool]$cur.ok){throw ('fixture init failed: '+[string]$cur.reason)}
    if($TargetPhase -in @('rollback-required','rollback-complete')){
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-required' -Now $script:Now.AddSeconds(1)
        if(-not [bool]$cur.ok){throw ('rollback append failed: '+[string]$cur.reason)}
        if($TargetPhase -ceq 'rollback-complete'){$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-complete' -Now $script:Now.AddSeconds(2);if(-not [bool]$cur.ok){throw ('rollback complete append failed: '+[string]$cur.reason)}}
    } elseif($TargetPhase -cne 'prepared') {
        $index=[array]::IndexOf($script:NormalChain,$TargetPhase);if($index -lt 1){throw ('unsupported phase '+$TargetPhase)}
        for($i=1;$i -le $index;$i++){
            $phase=[string]$script:NormalChain[$i];$args=@{AllowedRoot=$base;StoreDirectory=$paths.store;ExpectedRevision=[int64]$cur.revision;ExpectedEntrySha256=[string]$cur.entry.entry_sha256;Phase=$phase;Now=$script:Now.AddSeconds($i)}
            if($phase -in @('transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')){$args.FinalizationFingerprint=$script:FinalFp}
            if($phase -in @('apply-verified','cleanup-starting','committed-clean')){$args.ApplyResultFingerprint=$script:ApplyFp}
            if($phase -ceq 'committed-clean'){$args.CleanupResultFingerprint=$script:CleanupFp}
            $cur=Append-CustomAppProductionCrashJournalPhaseV010 @args;if(-not [bool]$cur.ok){throw ("append failed phase=$phase reason=$([string]$cur.reason)")}
        }
    }
    $plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $base -StoreDirectory $paths.store -ExpectedTransactionId ([string]$id.transaction_id)
    $pc=Test-CustomAppProductionRecoveryPlanV010 $plan;if(-not [bool]$pc.ok){throw ('plan invalid: '+[string]$pc.reason)}
    return [pscustomobject]@{root=$base;paths=$paths;identity=$id;current=$cur;plan=$plan;exe_sha=$exeSha}
}

function Invoke-PreflightFixtureV010($F,[AllowNull()]$Plan=$null,[AllowNull()][string]$ExpectedTx=$null,[AllowNull()][string]$ExeSha=$null){
    if($null -eq $Plan){$Plan=$F.plan};if([string]::IsNullOrWhiteSpace($ExpectedTx)){$ExpectedTx=[string]$F.identity.transaction_id};if([string]::IsNullOrWhiteSpace($ExeSha)){$ExeSha=[string]$F.exe_sha}
    return Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $F.root -StoreDirectory $F.paths.store -ExpectedTransactionId $ExpectedTx -Plan $Plan -SpicetifyAllowedRoot $F.root -SpicetifyPath $F.paths.exe -ExpectedSpicetifySha256 $ExeSha
}
function Assert-ZeroAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R};foreach($f in @('preflight_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-False ([bool]$x.$f) "$Label authority escaped $f"}}

$count=0
$phases=@('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean','rollback-required','rollback-complete')
foreach($phase in $phases){
    $f=New-PreflightFixtureV010 -Label $phase.Replace('-','') -TargetPhase $phase;$r=Invoke-PreflightFixtureV010 $f
    Assert-True ([bool]$r.ok) "$phase preflight denied: $([string]$r.reason)";Assert-ZeroAuthorityV010 $r $phase
    $check=Test-CustomAppProductionRecoveryPreflightReceiptV010 $r.receipt;Assert-True ([bool]$check.ok) "$phase receipt invalid: $([string]$check.reason)";Assert-Eq $r.receipt.phase $phase "$phase receipt phase"
    if([bool]$f.plan.requires_live_path){Assert-True (Test-CustomAppProductionRecoveryPreflightSha256V010 ([string]$r.receipt.live_evidence_fingerprint)) "$phase live evidence missing"}
    if([bool]$f.plan.requires_transaction_root){Assert-True (Test-CustomAppProductionRecoveryPreflightSha256V010 ([string]$r.receipt.transaction_evidence_fingerprint)) "$phase txn evidence missing"}else{Assert-Eq $r.receipt.transaction_evidence_fingerprint '' "$phase unexpected txn evidence"}
    if([bool]$f.plan.requires_stage_workspace){Assert-True (Test-CustomAppProductionRecoveryPreflightSha256V010 ([string]$r.receipt.stage_evidence_fingerprint)) "$phase stage evidence missing"}
    if([bool]$f.plan.requires_exact_spicetify_executable_pin){Assert-Eq $r.receipt.spicetify_executable_sha256 $f.exe_sha "$phase spicetify pin"}else{Assert-Eq $r.receipt.spicetify_executable_sha256 '' "$phase unexpected spicetify evidence"}
    if($phase -ceq 'atomic-mutation-starting'){Assert-True ([bool]$r.receipt.manual_inspection_required) 'atomic-start manual inspection lost'}
    $count++
}

$missing=New-PreflightFixtureV010 'missingstage' 'prepared';[IO.Directory]::Delete($missing.paths.stage,$true);$r=Invoke-PreflightFixtureV010 $missing;Assert-False ([bool]$r.ok) 'missing required stage accepted';Assert-True ([string]$r.reason -like '*stage-workspace*missing*') 'missing stage reason drifted';Assert-ZeroAuthorityV010 $r 'missing-stage';$count++

$noAction=New-PreflightFixtureV010 'committedmissingartifacts' 'committed-clean';foreach($p in @($noAction.paths.stage,$noAction.paths.app,$noAction.paths.persist,$noAction.paths.txn)){if(Test-Path $p){[IO.Directory]::Delete($p,$true)}};$r=Invoke-PreflightFixtureV010 $noAction;Assert-True ([bool]$r.ok) ('committed-clean incorrectly required retired artifacts: '+[string]$r.reason);Assert-True ([bool]$r.receipt.no_action) 'committed-clean no-action missing';$count++

$badExe=New-PreflightFixtureV010 'badexe' 'apply-starting';$r=Invoke-PreflightFixtureV010 -F $badExe -ExeSha (N '9');Assert-False ([bool]$r.ok) 'wrong spicetify hash accepted';Assert-True ([string]$r.reason -like '*spicetify executable sha256 mismatch*') 'wrong spicetify reason drifted';$count++

$missingExe=New-PreflightFixtureV010 'missingexe' 'rollback-required';[IO.File]::Delete($missingExe.paths.exe);$r=Invoke-PreflightFixtureV010 $missingExe;Assert-False ([bool]$r.ok) 'missing spicetify pin accepted';Assert-True ([string]$r.reason -like '*spicetify executable*missing*') 'missing exe reason drifted';$count++

$planTamper=New-PreflightFixtureV010 'plantamper' 'apply-verified';$bad=Copy-Obj $planTamper.plan;$bad.cleanup_authorized=$true;$bad.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $bad);$r=Invoke-PreflightFixtureV010 -F $planTamper -Plan $bad;Assert-False ([bool]$r.ok) 'authority-tampered plan accepted';Assert-True ([string]$r.reason -like '*recovery-plan-invalid:*authority-escaped*') 'plan tamper reason drifted';$count++

$phaseDrift=New-PreflightFixtureV010 'phasedrift' 'prepared';$oldPlan=Copy-Obj $phaseDrift.plan;$cur=$phaseDrift.current;$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $phaseDrift.root -StoreDirectory $phaseDrift.paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'atomic-mutation-starting' -Now $script:Now.AddSeconds(10);$r=Invoke-PreflightFixtureV010 -F $phaseDrift -Plan $oldPlan;Assert-False ([bool]$r.ok) 'stale plan after journal phase drift accepted';Assert-Eq $r.reason 'recovery-journal-phase-changed-since-plan' 'phase drift reason';$count++

$wrongTx=New-PreflightFixtureV010 'wrongtx' 'candidate-live';$r=Invoke-PreflightFixtureV010 -F $wrongTx -ExpectedTx (N '9');Assert-False ([bool]$r.ok) 'wrong expected transaction accepted';Assert-Eq $r.reason 'recovery-plan-transaction-mismatch' 'wrong tx reason';$count++

$receiptFixture=New-PreflightFixtureV010 'receipttamper' 'apply-verified';$good=Invoke-PreflightFixtureV010 $receiptFixture;Assert-True ([bool]$good.ok) 'receipt fixture preflight failed';$badReceipt=Copy-Obj $good.receipt;$badReceipt.apply_authorized=$true;$badReceipt.preflight_fingerprint=Get-CustomAppProductionRecoveryPreflightSha256V010 (Get-CustomAppProductionRecoveryPreflightMaterialV010 $badReceipt);$rc=Test-CustomAppProductionRecoveryPreflightReceiptV010 $badReceipt;Assert-False ([bool]$rc.ok) 'authority-tampered receipt accepted';Assert-True ([string]$rc.reason -like '*authority-escaped-apply_authorized*') 'receipt authority reason drifted';$count++
$badReceipt=Copy-Obj $good.receipt;$badReceipt.preflight_fingerprint=('0'*64);$rc=Test-CustomAppProductionRecoveryPreflightReceiptV010 $badReceipt;Assert-False ([bool]$rc.ok) 'fingerprint-tampered receipt accepted';Assert-Eq $rc.reason 'recovery-preflight-fingerprint-mismatch' 'receipt fingerprint reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_PREFLIGHT_MATRIX_PASS total=$count"