$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-dual-id-bridge-aware-finalization-v0.1.0/test_custom_app_production_dual_id_bridge_aware_finalization.ps1')
. (Join-Path $root 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-bridge-aware-post-swap-apply-admission.ps1')

function Assert-DBAPTrue([bool]$Value,[string]$Message){if(-not$Value){throw $Message}}
function Assert-DBAPFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-DBAPEq($Actual,$Expected,[string]$Message){if([string]$Actual-cne[string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-DBAP($Value){return (($Value|ConvertTo-Json -Depth 80)|ConvertFrom-Json)}
function Assert-DBAPNoAuthority($Value,[string]$Label){foreach($f in @('session_key_persisted','session_key_exposed','admission_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-DBAPFalse ([bool]$Value.$f) "$Label escaped $f"}}}

function New-DBAPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    # Upstream fixture harness intentionally keeps a shared logical clock. Refresh it here
    # so the byte-real 5-minute permit TTL measures this admission stage, not prior matrix replay time.
    $script:now=[DateTimeOffset]::UtcNow
    $f=New-DBAFFixtureV010 ('dbap-'+$Label)
    $final=Invoke-DBAFFinalizeV010 -F $f -Now ([DateTimeOffset]::UtcNow)
    Assert-DBAPTrue ($null-ne$final-and[bool]$final.ok) ('fixture finalization denied '+$Label+': '+[string]$final.reason)
    return [pscustomobject]@{f=$f;final=$final;now=[DateTimeOffset]::UtcNow}
}
function Invoke-DBAPV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()]$Final=$null,[AllowNull()]$Bridge=$null,[AllowNull()]$Atomic=$null,[AllowNull()][byte[]]$Key=$null,[AllowNull()]$Lifecycle=$null,[AllowNull()]$Provenance=$null,[AllowNull()]$Binding=$null,[DateTimeOffset]$At=[DateTimeOffset]::MinValue)
    $f=$Q.f;if($null-eq$Final){$Final=$Q.final.result};if($null-eq$Bridge){$Bridge=$f.bridge.result};if($null-eq$Atomic){$Atomic=$f.atomic};if($null-eq$Key){$Key=$key};if($null-eq$Lifecycle){$Lifecycle=$f.x.fixture.q.x.f.lifecycle};if($null-eq$Provenance){$Provenance=$f.x.fixture.q.x.f.provenance};if($null-eq$Binding){$Binding=$f.x.fixture.q.x.f.binding};if($At-eq[DateTimeOffset]::MinValue){$At=$Q.now}
    Resolve-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionV010 -DualIdFinalizationResult $Final -DurableBridgeIntegrationResult $Bridge -EvidenceBoundAtomicResult $Atomic -RecoveryAwarePreparedResult $f.x.carrier -RecoveryAwareStageExecutorResult $f.x.stage -GenericPreparedResult $f.x.generic -GenericStageExecutorResult $f.x.fixture.q.stage.result -Permit $f.x.fixture.q.x.permit -Name $f.name -LifecycleRow $Lifecycle -ProvenanceRow $Provenance -BindingRow $Binding -AllowedRoot $f.trust -JournalStoreDirectory $f.store -ConsumptionStoreDirectory $f.x.fixture.q.x.store.store -SessionKey $Key -LocalAppDataRoot ([string]$f.x.fixture.q.persistence.local) -AppDataRoot ([string]$f.x.fixture.q.persistence.roaming) -Now $At
}

$count=0

# 1. Byte-real success: exact finalized journal, recovery evidence, real permit/HMAC,
# real persisted consumption ledger, live tree, retained stage/backups, persistence and binding.
$q=New-DBAPFixtureV010 'success'
$r=Invoke-DBAPV010 $q
Assert-DBAPTrue ([bool]$r.ok) ('byte-real admission denied: '+[string]$r.reason)
Assert-DBAPNoAuthority $r 'success wrapper';Assert-DBAPNoAuthority $r.decision 'success decision'
$c=Test-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionDecisionV010 $r.decision;Assert-DBAPTrue ([bool]$c.ok) ('success decision invalid: '+[string]$c.reason)
Assert-DBAPEq $r.decision.permit_transaction_id $q.f.bridge.result.permit_transaction_id 'success permit transaction id'
Assert-DBAPEq $r.decision.journal_transaction_id $q.f.bridge.result.journal_transaction_id 'success journal transaction id'
Assert-DBAPFalse ([string]$r.decision.permit_transaction_id-ceq[string]$r.decision.journal_transaction_id) 'success transaction namespaces conflated'
Assert-DBAPTrue ([bool]$r.decision.forward_continuity_uses_permit_id-and[bool]$r.decision.crash_recovery_uses_journal_id) 'success ID role flags missing'
Assert-DBAPTrue ([bool]$r.decision.journal_transaction_finalized_reverified-and[bool]$r.decision.recovery_evidence_reverified) 'success durable recovery proofs missing'
Assert-DBAPTrue ([bool]$r.decision.consumption_reverified_before_state_checks-and[bool]$r.decision.consumption_reverified_after_state_checks) 'success ledger double-read flags missing'
$count++

# 2. Rehashed authority escape is still rejected by the decision validator.
$badDecision=Copy-DBAP $r.decision;$badDecision.production_mutation_authorized=$true;$badDecision.admission_fingerprint=Get-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionSha256V010(Get-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionMaterialV010 $badDecision)
$dc=Test-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionDecisionV010 $badDecision;Assert-DBAPFalse ([bool]$dc.ok) 'rehash authority escape accepted';$count++

# 3. Conflating permit ID with crash-journal ID is rejected even with a recomputed finalization fingerprint.
$badFinal=Copy-DBAP $q.final.result;$badFinal.permit_transaction_id=[string]$badFinal.journal_transaction_id;$badFinal.result_fingerprint=Get-CustomAppProductionDualIdBridgeAwareFinalizationSha256V010(Get-CustomAppProductionDualIdBridgeAwareFinalizationResultMaterialV010 $badFinal)
$x=Invoke-DBAPV010 -Q $q -Final $badFinal;Assert-DBAPFalse ([bool]$x.ok) 'conflated finalization IDs accepted';Assert-DBAPNoAuthority $x 'conflated IDs';$count++

# 4. A distinct but substituted journal ID is rejected before any apply authority exists.
$badFinal=Copy-DBAP $q.final.result;$badFinal.journal_transaction_id=('0'*64);if([string]$badFinal.journal_transaction_id-ceq[string]$badFinal.permit_transaction_id){$badFinal.journal_transaction_id=('1'*64)};$badFinal.result_fingerprint=Get-CustomAppProductionDualIdBridgeAwareFinalizationSha256V010(Get-CustomAppProductionDualIdBridgeAwareFinalizationResultMaterialV010 $badFinal)
$x=Invoke-DBAPV010 -Q $q -Final $badFinal;Assert-DBAPFalse ([bool]$x.ok) 'journal ID substitution accepted';Assert-DBAPTrue ([string]$x.reason-like'*journal-id-drift*') ('journal ID substitution reason drift: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'journal ID substitution';$count++

# 5. Wrong ephemeral session key fails the real permit HMAC path.
$x=Invoke-DBAPV010 -Q $q -Key ([byte[]](33..64));Assert-DBAPFalse ([bool]$x.ok) 'wrong session key accepted';Assert-DBAPTrue ([string]$x.reason-like'*permit-integrity-denied:*hmac*') ('wrong key reason drift: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'wrong key';$count++

# 6. Journal phase drift after finalization fails closed on the journal namespace.
$q6=New-DBAPFixtureV010 'journal-phase-drift';$jr=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q6.f.trust -StoreDirectory $q6.f.store;$at=[DateTimeOffset]::Parse([string]$jr.entry.recorded_at).AddMilliseconds(1)
$adv=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $q6.f.trust -StoreDirectory $q6.f.store -ExpectedRevision ([int64]$jr.revision) -ExpectedEntrySha256 ([string]$jr.entry.entry_sha256) -Phase 'rollback-required' -Now $at
Assert-DBAPTrue ([bool]$adv.ok) ('journal drift setup failed: '+[string]$adv.reason)
$x=Invoke-DBAPV010 $q6;Assert-DBAPFalse ([bool]$x.ok) 'post-finalization journal phase drift accepted';Assert-DBAPTrue ([string]$x.reason-like'*journal-not-exact-transaction-finalized*') ('journal drift reason changed: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'journal drift';$count++

# 7. Byte-real live runtime drift after finalization is rejected.
$q7=New-DBAPFixtureV010 'live-drift';[IO.File]::AppendAllText((Join-Path ([string]$q7.f.x.fixture.q.x.live) 'index.js'),"// dbap-live-drift`n",[Text.UTF8Encoding]::new($false))
$x=Invoke-DBAPV010 $q7;Assert-DBAPFalse ([bool]$x.ok) 'post-finalization live drift accepted';Assert-DBAPTrue ([string]$x.reason-like'*live-runtime-not-exact-remote-stage*') ('live drift reason changed: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'live drift';$count++

# 8. Corrupted durable consumption store is rejected before apply eligibility.
$q8=New-DBAPFixtureV010 'ledger-corrupt';[IO.File]::WriteAllText((Join-Path ([string]$q8.f.x.fixture.q.x.store.store) 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false))
$x=Invoke-DBAPV010 $q8;Assert-DBAPFalse ([bool]$x.ok) 'corrupted consumption store accepted';Assert-DBAPTrue ([string]$x.reason-like'*consumption-before-denied:*') ('consumption corrupt reason changed: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'ledger corrupt';$count++

# 9. A finalized transaction workspace that reappears is rejected.
$q9=New-DBAPFixtureV010 'transaction-reappeared';$txn=[string]$q9.final.result.transaction_root;[IO.Directory]::CreateDirectory($txn)|Out-Null
try{$x=Invoke-DBAPV010 $q9;Assert-DBAPFalse ([bool]$x.ok) 'reappeared transaction workspace accepted';Assert-DBAPTrue ([string]$x.reason-like'*transaction-workspace-reappeared*') ('transaction reappear reason changed: '+[string]$x.reason);Assert-DBAPNoAuthority $x 'transaction reappeared'}finally{if(Test-Path -LiteralPath $txn){Remove-Item -LiteralPath $txn -Recurse -Force}}
$count++

# 10. Fingerprint-only tamper is detectable without recomputation.
$fp=Copy-DBAP $r.decision;$fp.admission_fingerprint=('f'*64);$fc=Test-CustomAppProductionDualIdBridgeAwarePostSwapApplyAdmissionDecisionV010 $fp;Assert-DBAPFalse ([bool]$fc.ok) 'decision fingerprint tamper accepted';$count++

if($count-ne10){throw "dual-ID post-swap admission matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_DUAL_ID_BRIDGE_AWARE_POST_SWAP_APPLY_ADMISSION_PASS cases=$count byte_real=true real_permit_hmac=true durable_ledger=true journal_id_separate=true zero_authority=true"
