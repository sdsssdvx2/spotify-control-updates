$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-preflight-v0.1.0/test_custom_app_production_recovery_preflight.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-execution-admission.ps1')

function Assert-AdmissionZeroAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['decision']){$R.decision}else{$R};foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-False ([bool]$x.$f) "$Label authority escaped $f"}}
function New-AdmissionFixtureV010([string]$Label,[string]$Phase){$f=New-PreflightFixtureV010 -Label ('admission-'+$Label) -TargetPhase $Phase;$p=Invoke-PreflightFixtureV010 $f;if(-not [bool]$p.ok){throw ('preflight fixture failed: '+[string]$p.reason)};return [pscustomobject]@{f=$f;preflight=$p}}
function Invoke-AdmissionFixtureV010($Q,[AllowNull()]$Plan=$null,[AllowNull()]$Receipt=$null,[AllowNull()][string]$ExeSha=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow){if($null -eq $Plan){$Plan=$Q.f.plan};if($null -eq $Receipt){$Receipt=$Q.preflight.receipt};if([string]::IsNullOrWhiteSpace($ExeSha)){$ExeSha=[string]$Q.f.exe_sha};return Resolve-CustomAppProductionRecoveryExecutionAdmissionV010 -AllowedRoot $Q.f.root -StoreDirectory $Q.f.paths.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -Plan $Plan -PreflightReceipt $Receipt -SpicetifyAllowedRoot $Q.f.root -SpicetifyPath $Q.f.paths.exe -ExpectedSpicetifySha256 $ExeSha -Now $At}

$expect=@{
'prepared'=@('no-action',$false,$false,$false,$false);
'atomic-mutation-starting'=@('manual-inspection',$false,$false,$false,$false);
'live-moved-to-old'=@('exact-app-persistence-restore',$true,$true,$false,$false);
'candidate-live'=@('exact-app-persistence-restore',$true,$true,$false,$false);
'transaction-finalized'=@('exact-app-persistence-restore',$true,$true,$false,$false);
'apply-starting'=@('exact-app-persistence-restore-and-recovery-apply',$true,$true,$true,$false);
'apply-returned-success-pending-verification'=@('exact-app-persistence-restore-and-recovery-apply',$true,$true,$true,$false);
'apply-verified'=@('idempotent-housekeeping',$true,$false,$false,$true);
'cleanup-starting'=@('idempotent-housekeeping',$true,$false,$false,$true);
'committed-clean'=@('no-action',$false,$false,$false,$false);
'rollback-required'=@('exact-app-persistence-restore-and-recovery-apply',$true,$true,$true,$false);
'rollback-complete'=@('no-action',$false,$false,$false,$false)
}
$count=0
foreach($phase in @($expect.Keys|Sort-Object)){
    $q=New-AdmissionFixtureV010 -Label $phase.Replace('-','') -Phase $phase;$at=[DateTimeOffset]::UtcNow;$r=Invoke-AdmissionFixtureV010 -Q $q -At $at
    Assert-True ([bool]$r.ok) "$phase admission denied: $([string]$r.reason)";Assert-AdmissionZeroAuthorityV010 $r $phase
    $c=Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 -Decision $r.decision -Now $at.AddSeconds(1);Assert-True ([bool]$c.ok) "$phase decision invalid: $([string]$c.reason)"
    Assert-Eq $r.decision.executor_class $expect[$phase][0] "$phase executor class";Assert-True ([bool]$r.decision.recovery_action_eligible -eq [bool]$expect[$phase][1]) "$phase eligibility";Assert-True ([bool]$r.decision.requires_exact_restore -eq [bool]$expect[$phase][2]) "$phase restore mapping";Assert-True ([bool]$r.decision.requires_recovery_apply -eq [bool]$expect[$phase][3]) "$phase recovery apply mapping";Assert-True ([bool]$r.decision.requires_idempotent_cleanup -eq [bool]$expect[$phase][4]) "$phase cleanup mapping"
    if($phase -eq 'atomic-mutation-starting'){Assert-False ([bool]$r.decision.recovery_action_eligible) 'manual inspection became executable'}
    $count++
}

$liveDrift=New-AdmissionFixtureV010 'live-drift' 'candidate-live';[IO.File]::AppendAllText((Join-Path $liveDrift.f.paths.live 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AdmissionFixtureV010 $liveDrift;Assert-False ([bool]$r.ok) 'stale preflight after live drift accepted';Assert-Eq $r.reason 'recovery-admission-fresh-preflight-fingerprint-mismatch' 'live drift reason';Assert-AdmissionZeroAuthorityV010 $r 'live-drift';$count++

$stageDrift=New-AdmissionFixtureV010 'stage-drift' 'apply-verified';[IO.File]::AppendAllText((Join-Path $stageDrift.f.paths.stage 'stage\index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-AdmissionFixtureV010 $stageDrift;Assert-False ([bool]$r.ok) 'stale preflight after stage drift accepted';Assert-Eq $r.reason 'recovery-admission-fresh-preflight-fingerprint-mismatch' 'stage drift reason';$count++

$phaseDrift=New-AdmissionFixtureV010 'phase-drift' 'prepared';$cur=$phaseDrift.f.current;$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $phaseDrift.f.root -StoreDirectory $phaseDrift.f.paths.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'atomic-mutation-starting' -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));$r=Invoke-AdmissionFixtureV010 $phaseDrift;Assert-False ([bool]$r.ok) 'journal phase drift accepted';Assert-True ([string]$r.reason -like 'recovery-admission-fresh-preflight-denied:*phase-changed*') 'phase drift reason';$count++

$badReceiptQ=New-AdmissionFixtureV010 'receipt-authority' 'apply-verified';$badReceipt=Copy-Obj $badReceiptQ.preflight.receipt;$badReceipt.apply_authorized=$true;$badReceipt.preflight_fingerprint=Get-CustomAppProductionRecoveryPreflightSha256V010 (Get-CustomAppProductionRecoveryPreflightMaterialV010 $badReceipt);$r=Invoke-AdmissionFixtureV010 -Q $badReceiptQ -Receipt $badReceipt;Assert-False ([bool]$r.ok) 'authority-tampered preflight receipt accepted';Assert-True ([string]$r.reason -like '*authority-escaped-apply_authorized*') 'receipt authority reason';$count++

$fpReceiptQ=New-AdmissionFixtureV010 'receipt-fingerprint' 'candidate-live';$badReceipt=Copy-Obj $fpReceiptQ.preflight.receipt;$badReceipt.preflight_fingerprint=('0'*64);$r=Invoke-AdmissionFixtureV010 -Q $fpReceiptQ -Receipt $badReceipt;Assert-False ([bool]$r.ok) 'fingerprint-tampered preflight receipt accepted';Assert-True ([string]$r.reason -like '*fingerprint-mismatch*') 'receipt fingerprint reason';$count++

$planQ=New-AdmissionFixtureV010 'plan-authority' 'apply-verified';$badPlan=Copy-Obj $planQ.f.plan;$badPlan.restore_authorized=$true;$badPlan.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $badPlan);$r=Invoke-AdmissionFixtureV010 -Q $planQ -Plan $badPlan;Assert-False ([bool]$r.ok) 'authority-tampered plan accepted';Assert-True ([string]$r.reason -like '*authority-escaped-restore_authorized*') 'plan authority reason';$count++

$exeQ=New-AdmissionFixtureV010 'exe-drift' 'apply-starting';$r=Invoke-AdmissionFixtureV010 -Q $exeQ -ExeSha (N '9');Assert-False ([bool]$r.ok) 'wrong recovery executable pin accepted';Assert-True ([string]$r.reason -like '*fresh-preflight-denied:*spicetify executable sha256 mismatch*') 'exe drift reason';$count++

$decisionQ=New-AdmissionFixtureV010 'decision-tamper' 'candidate-live';$at=[DateTimeOffset]::UtcNow;$good=Invoke-AdmissionFixtureV010 -Q $decisionQ -At $at;Assert-True ([bool]$good.ok) 'decision fixture failed';$bad=Copy-Obj $good.decision;$bad.execution_authorized=$true;$bad.admission_fingerprint=Get-CustomAppProductionRecoveryExecutionAdmissionSha256V010 (Get-CustomAppProductionRecoveryExecutionAdmissionMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 -Decision $bad -Now $at.AddSeconds(1);Assert-False ([bool]$c.ok) 'authority-tampered decision accepted';Assert-True ([string]$c.reason -like '*authority-escaped-execution_authorized*') 'decision authority reason';$count++

$mapQ=New-AdmissionFixtureV010 'mapping-tamper' 'candidate-live';$at=[DateTimeOffset]::UtcNow;$good=Invoke-AdmissionFixtureV010 -Q $mapQ -At $at;$bad=Copy-Obj $good.decision;$bad.executor_class='idempotent-housekeeping';$bad.admission_fingerprint=Get-CustomAppProductionRecoveryExecutionAdmissionSha256V010 (Get-CustomAppProductionRecoveryExecutionAdmissionMaterialV010 $bad);$c=Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 -Decision $bad -Now $at.AddSeconds(1);Assert-False ([bool]$c.ok) 'semantic mapping tamper accepted';Assert-Eq $c.reason 'recovery-admission-semantic-mapping-drift' 'mapping tamper reason';$count++

$expiryQ=New-AdmissionFixtureV010 'expiry' 'candidate-live';$at=[DateTimeOffset]::UtcNow;$good=Invoke-AdmissionFixtureV010 -Q $expiryQ -At $at;$c=Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 -Decision $good.decision -Now $at.AddSeconds(16);Assert-False ([bool]$c.ok) 'expired admission accepted';Assert-Eq $c.reason 'recovery-admission-expired' 'expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_EXECUTION_ADMISSION_MATRIX_PASS total=$count"