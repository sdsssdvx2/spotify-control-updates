$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-routing-admission.ps1')

function Assert-RTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-REq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-R($x){return(($x|ConvertTo-Json -Depth 40)|ConvertFrom-Json)}
function N-R([string]$c,[int]$n=64){return($c*$n)}

$script:Roots=New-Object Collections.Generic.List[string]
$script:Normal=@('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')
function New-RFixture([string]$Label,[string]$Target){
    $base=Join-Path $env:TEMP ('recovery-routing-'+$Label+'-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($base)|Out-Null;$script:Roots.Add($base)
    $live=Join-Path $base 'live';$txn=Join-Path $base '.spotify-control-txn-11111111111111111111111111111111';$stage=Join-Path $base 'stage';$app=Join-Path $base 'app';$persist=Join-Path $base 'persist';foreach($p in @($live,$txn,$stage,$app,$persist)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $store=Join-Path $base 'journal';$id=New-CustomAppProductionCrashJournalIdentityV010 -Name 'tagify' -ConsumptionId (N-R '1') -SourceIdentity 'alexk218/tagify' -RemoteCommitSha (N-R '2' 40) -StageResultFingerprint (N-R '3') -PreparationFingerprint (N-R '4') -AllowedRoot $base -LivePath $live -TransactionRoot $txn -StageWorkspacePath $stage -AppBackupPath $app -PersistenceBackupPath $persist
    $at=[DateTimeOffset]::UtcNow.AddMinutes(-2);$cur=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $base -StoreDirectory $store -Identity $id -Now $at;if(-not[bool]$cur.ok){throw ('fixture init failed '+[string]$cur.reason)}
    if($Target-in@('rollback-required','rollback-complete')){
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-required' -Now $at.AddSeconds(1);if(-not[bool]$cur.ok){throw 'rollback-required fixture advance failed'}
        if($Target-ceq'rollback-complete'){$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $base -StoreDirectory $store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-complete' -Now $at.AddSeconds(2);if(-not[bool]$cur.ok){throw 'rollback-complete fixture advance failed'}}
    }elseif($Target-cne'prepared'){
        $idx=[array]::IndexOf($script:Normal,$Target);if($idx-lt1){throw ('unsupported target '+$Target)}
        for($i=1;$i-le$idx;$i++){
            $phase=[string]$script:Normal[$i];$args=@{AllowedRoot=$base;StoreDirectory=$store;ExpectedRevision=[int64]$cur.revision;ExpectedEntrySha256=[string]$cur.entry.entry_sha256;Phase=$phase;Now=$at.AddSeconds($i)}
            if($phase-ceq'transaction-finalized'){$args.FinalizationFingerprint=N-R 'f'}
            if($phase-ceq'apply-verified'){$args.ApplyResultFingerprint=N-R 'a'}
            if($phase-ceq'committed-clean'){$args.CleanupResultFingerprint=N-R 'c'}
            $cur=Append-CustomAppProductionCrashJournalPhaseV010 @args;if(-not[bool]$cur.ok){throw ('fixture advance failed '+$phase+' '+[string]$cur.reason)}
        }
    }
    return [pscustomobject]@{root=$base;store=$store;id=$id;current=$cur}
}
function Invoke-R($q,[AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow){if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$q.id.transaction_id};return Resolve-CustomAppProductionRecoveryRoutingAdmissionV010 -AllowedRoot $q.root -StoreDirectory $q.store -ExpectedTransactionId $Tx -Now $At}
function Assert-RZero($r,[string]$label){$x=if($r.PSObject.Properties['receipt']){$r.receipt}else{$r};foreach($f in @('routing_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized')){Assert-RFalse ([bool]$x.$f) "$label authority escaped $f"}}

$expected=@{
'prepared'=@('prepared-transaction-resolution-required','explicit-prepared-transaction-resolution-not-yet-wired',$true,$false,$false,$false,$false);
'atomic-mutation-starting'=@('manual-filesystem-recovery-inspection-required','manual-filesystem-recovery-inspection',$true,$false,$false,$false,$false);
'live-moved-to-old'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'candidate-live'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'transaction-finalized'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'apply-starting'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'apply-returned-success-pending-verification'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'rollback-required'=@('bounded-recovery-executor-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$true,$false,$false,$false);
'apply-verified'=@('bounded-recovery-housekeeping-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$false,$true,$false,$false);
'cleanup-starting'=@('bounded-recovery-housekeeping-candidate','Invoke-CustomAppProductionBoundedRecoveryExecutorV010',$false,$false,$true,$false,$false);
'rollback-complete'=@('recovery-artifact-retirement-required','Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010',$false,$false,$false,$true,$true);
'committed-clean'=@('terminal-new-update-permit-readiness-required','fresh-normal-terminal-new-permit-policy-not-yet-wired',$false,$false,$false,$false,$true)
}
$count=0;$i=0
foreach($phase in @('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean','rollback-required','rollback-complete')){
    $i++;$q=New-RFixture -Label ($phase.Replace('-','')) -Target $phase;$at=[DateTimeOffset]::UtcNow;$r=Invoke-R -q $q -At $at;Assert-RTrue ([bool]$r.ok) "$phase route denied: $([string]$r.reason)";Assert-RZero $r $phase
    $e=$expected[$phase];Assert-REq $r.receipt.route $e[0] "$phase route";Assert-REq $r.receipt.next_validator $e[1] "$phase next validator";Assert-RTrue ([bool]$r.receipt.requires_manual_resolution-eq[bool]$e[2]) "$phase manual";Assert-RTrue ([bool]$r.receipt.requires_bounded_recovery_executor-eq[bool]$e[3]) "$phase recovery";Assert-RTrue ([bool]$r.receipt.requires_bounded_housekeeping-eq[bool]$e[4]) "$phase housekeeping";Assert-RTrue ([bool]$r.receipt.requires_recovery_artifact_retirement-eq[bool]$e[5]) "$phase retirement";Assert-RTrue ([bool]$r.receipt.requires_new_update_permit_readiness-eq[bool]$e[6]) "$phase new permit"
    $ck=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $r.receipt -Now $at.AddSeconds(1);Assert-RTrue ([bool]$ck.ok) "$phase receipt invalid: $([string]$ck.reason)";$count++
}

$wrong=New-RFixture 'wrongtx' 'candidate-live';$r=Invoke-R -q $wrong -Tx (N-R '9');Assert-RFalse ([bool]$r.ok) 'wrong transaction accepted';Assert-REq $r.reason 'recovery-routing-transaction-mismatch' 'wrong transaction reason';Assert-RZero $r 'wrongtx';$count++

$corrupt=New-RFixture 'corrupt' 'candidate-live';[IO.File]::WriteAllText((Join-Path $corrupt.store 'current.json'),'{bad',[Text.UTF8Encoding]::new($false));$r=Invoke-R -q $corrupt;Assert-RFalse ([bool]$r.ok) 'corrupt journal accepted';Assert-RTrue ([string]$r.reason-like'recovery-routing-journal-read-failed:*') 'corrupt journal reason';Assert-RZero $r 'corrupt';$count++

$lock=New-RFixture 'lock' 'candidate-live';$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $lock.root -StoreDirectory $lock.store;$held=Open-CustomAppProductionCrashJournalLockV010 $paths;try{$r=Invoke-R -q $lock}finally{$held.Dispose()};Assert-RFalse ([bool]$r.ok) 'lock-contention route accepted';Assert-RTrue ([string]$r.reason-like'recovery-routing-journal-read-failed:*lock-busy*') 'lock reason';$count++

$tamper=New-RFixture 'receipt-route-tamper' 'candidate-live';$at=[DateTimeOffset]::UtcNow;$good=Invoke-R -q $tamper -At $at;$bad=Copy-R $good.receipt;$bad.route='bounded-recovery-housekeeping-candidate';$bad.routing_fingerprint=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-RFalse ([bool]$ck.ok) 'route tamper + rehash accepted';Assert-REq $ck.reason 'recovery-routing-semantic-route-drift' 'route tamper reason';$count++

$auth=New-RFixture 'receipt-authority-tamper' 'rollback-required';$at=[DateTimeOffset]::UtcNow;$good=Invoke-R -q $auth -At $at;$bad=Copy-R $good.receipt;$bad.execution_authorized=$true;$bad.routing_fingerprint=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-RFalse ([bool]$ck.ok) 'authority tamper + rehash accepted';Assert-REq $ck.reason 'recovery-routing-authority-escaped-execution_authorized' 'authority tamper reason';$count++

$expiry=New-RFixture 'expiry' 'cleanup-starting';$at=[DateTimeOffset]::UtcNow;$good=Invoke-R -q $expiry -At $at;$ck=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $good.receipt -Now $at.AddSeconds(11);Assert-RFalse ([bool]$ck.ok) 'expired route receipt accepted';Assert-REq $ck.reason 'recovery-routing-expired' 'expiry reason';$count++

$badTx=New-RFixture 'badtxshape' 'prepared';$r=Invoke-R -q $badTx -Tx 'not-a-sha';Assert-RFalse ([bool]$r.ok) 'invalid tx shape accepted';Assert-REq $r.reason 'recovery-routing-transaction-id-invalid' 'invalid tx reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_ADMISSION_MATRIX_PASS total=$count"

foreach($p in $script:Roots){if(Test-Path -LiteralPath $p){[IO.Directory]::Delete($p,$true)}}
