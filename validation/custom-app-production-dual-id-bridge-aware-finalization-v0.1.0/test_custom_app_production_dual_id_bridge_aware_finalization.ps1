$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-lightweight-dual-id-restart-bridge-v0.1.0/test_custom_app_production_lightweight_dual_id_restart_bridge.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/custom-app-production-recovery-aware-permit-transaction-finalization.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-dual-id-bridge-aware-finalization.ps1')

function Assert-DBAFV010 {param([bool]$Condition,[string]$Message)if(-not$Condition){throw$Message}}
$script:DBAFFault=$null
$script:DBAFConsumptionMode='stable'
$script:DBAFCurrentName='test-app'
function Invoke-CustomAppProductionDualIdBridgeAwareFinalizationValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:DBAFFault-ceq$Checkpoint){throw('dbaf-fixture-fault:'+$Checkpoint)}
}
function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedTargetV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$TargetState,[Parameter(Mandatory=$true)][int64]$TargetRevision,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId)
    $hist=Get-CustomAppProductionDualIdBridgeAwareFinalizationSha256V010 ('historical|'+$ExpectedConsumptionId)
    $cur=Get-CustomAppProductionDualIdBridgeAwareFinalizationSha256V010 ('current|'+$ExpectedConsumptionId+'|'+$script:DBAFConsumptionMode)
    $rows=@([pscustomobject]@{name=$script:DBAFCurrentName;consumption_id=$ExpectedConsumptionId})
    if($script:DBAFConsumptionMode-ceq'same-app-newer'){$rows+=,[pscustomobject]@{name=$script:DBAFCurrentName;consumption_id=('9'*64)}}
    elseif($script:DBAFConsumptionMode-ceq'other-app-newer'){$rows+=,[pscustomobject]@{name='other-app';consumption_id=('8'*64)}}
    $rev=[int64]$rows.Count
    return[pscustomobject]@{ok=$true;reason='dbaf-fixture-persisted-target';target_envelope=[pscustomobject]@{envelope_sha256=$hist};current_envelope=[pscustomobject]@{envelope_sha256=$cur};current_state=[pscustomobject]@{consumptions=$rows};current_revision=$rev}
}
function New-DBAFFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label)
    $x=New-LDFixtureV010 -Label $Label -FixtureNonce ([Guid]::NewGuid().ToString('N')) -PermitSeed ('permit-'+$Label)
    $name=([string]$x.fixture.q.x.f.name).Trim().ToLowerInvariant()
    $script:DBAFCurrentName=$name
    $hist=Get-CustomAppProductionDualIdBridgeAwareFinalizationSha256V010 ('historical|'+[string]$x.generic.consumption_id)
    $x.carrier|Add-Member -NotePropertyName historical_consumption_envelope_sha256 -NotePropertyValue $hist -Force
    $x.stage|Add-Member -NotePropertyName historical_consumption_envelope_sha256 -NotePropertyValue $hist -Force
    $store=Get-EBStoreV010 $x.fixture ('dbaf-'+$Label)
    $bridge=Invoke-CustomAppProductionDurableDualTransactionIdBridgeIntegrationV010 -RecoveryAwarePreparedResult $x.carrier -RecoveryAwareStageExecutorResult $x.stage -Name $name -AllowedRoot (Get-EBTrustRootV010) -JournalStoreDirectory $store -TransactionNonce ([Guid]::NewGuid().ToString('N')) -LivePath ([string]$x.fixture.q.x.live) -ExpectedLiveFullTreeSha256 ([string]$x.fixture.full_before.tree_sha256) -ExpectedLiveFullFileCount ([int]$x.fixture.full_before.file_count) -ExpectedLiveFullTotalBytes ([int64]$x.fixture.full_before.total_bytes) -LocalAppDataRoot ([string]$x.fixture.q.persistence.local) -AppDataRoot ([string]$x.fixture.q.persistence.roaming) -Now ([DateTimeOffset]::UtcNow)
    Assert-DBAFV010 ($null-ne$bridge-and[bool]$bridge.ok) ('bridge setup denied '+$Label+': '+[string]$bridge.reason)
    $consStore=Join-Path (Get-EBTrustRootV010) ('dbaf-consumption-'+$Label+'-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $consStore|Out-Null
    $cons=[pscustomobject]@{receipt=[pscustomobject]@{persisted_revision=1};persisted_snapshot=[pscustomobject]@{state=[pscustomobject]@{consumptions=@([pscustomobject]@{name=$name;consumption_id=[string]$x.generic.consumption_id})}}}
    $life=[pscustomobject]@{managed_by='dynamic-spicetify-v1';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@([string]$x.fixture.q.x.live)}
    return[pscustomobject]@{x=$x;name=$name;store=$store;bridge=$bridge;atomic=$bridge.atomic.result;consumption_store=$consStore;consumption=$cons;lifecycle=$life;trust=(Get-EBTrustRootV010)}
}
function Invoke-DBAFFinalizeV010 {
    param([Parameter(Mandatory=$true)]$F,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $script:DBAFCurrentName=[string]$F.name
    return Invoke-CustomAppProductionDualIdBridgeAwareFinalizationV010 -DurableBridgeIntegrationResult $F.bridge.result -EvidenceBoundAtomicResult $F.atomic -RecoveryAwarePreparedResult $F.x.carrier -RecoveryAwareStageExecutorResult $F.x.stage -Name $F.name -LifecycleRow $F.lifecycle -AllowedRoot $F.trust -JournalStoreDirectory $F.store -ConsumptionStoreDirectory $F.consumption_store -ConsumptionPersistenceResult $F.consumption -LocalAppDataRoot ([string]$F.x.fixture.q.persistence.local) -AppDataRoot ([string]$F.x.fixture.q.persistence.roaming) -Now $Now
}
function Assert-DBAFZeroAuthorityV010 {param([Parameter(Mandatory=$true)]$Value)foreach($f in @('result_is_authority','execution_authorized','finalization_authorized','apply_execution_authorized','spicetify_apply_authorized','cleanup_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-DBAFV010 (-not[bool]$Value.$f) ('authority escaped '+$f)}}}

# 1. Byte-real success: permit identity remains forward-only, journal identity remains crash-only.
$script:DBAFConsumptionMode='stable';$script:DBAFFault=$null
$f1=New-DBAFFixtureV010 'success'
$jr1=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f1.trust -StoreDirectory $f1.store
Assert-DBAFV010 ([string]$jr1.entry.phase-ceq'candidate-live') 'success prerequisite journal phase drift'
$r1=Invoke-DBAFFinalizeV010 -F $f1 -Now ([DateTimeOffset]::UtcNow.AddMinutes(-5))
Assert-DBAFV010 ([bool]$r1.ok) ('success finalization denied: '+[string]$r1.reason)
Assert-DBAFZeroAuthorityV010 $r1;Assert-DBAFZeroAuthorityV010 $r1.result
Assert-DBAFV010 ([string]$r1.result.permit_transaction_id-ceq[string]$f1.bridge.result.permit_transaction_id) 'success permit id drift'
Assert-DBAFV010 ([string]$r1.result.journal_transaction_id-ceq[string]$f1.bridge.result.journal_transaction_id) 'success journal id drift'
Assert-DBAFV010 ([string]$r1.result.permit_transaction_id-cne[string]$r1.result.journal_transaction_id) 'success id namespaces conflated'
Assert-DBAFV010 (-not(Test-Path -LiteralPath ([string]$f1.atomic.transaction_root))) 'success transaction root not deleted'
foreach($p in @([string]$f1.x.generic.stage_workspace_path,[string]$f1.x.generic.app_backup_path,[string]$f1.x.generic.persistence_backup_path)){Assert-DBAFV010 (Test-Path -LiteralPath $p -PathType Container) ('success preserved evidence missing '+$p)}
$jr1a=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f1.trust -StoreDirectory $f1.store
Assert-DBAFV010 ([string]$jr1a.entry.phase-ceq'transaction-finalized') 'success journal not transaction-finalized'
Assert-DBAFV010 (([string]$jr1a.entry.finalization_fingerprint).Trim().ToLowerInvariant()-ceq([string]$r1.result.result_fingerprint).Trim().ToLowerInvariant()) 'success journal finalization fingerprint drift'
Assert-DBAFV010 ([bool]$r1.result.forward_continuity_uses_permit_id-and[bool]$r1.result.crash_recovery_uses_journal_id) 'success dual namespace role flags missing'
Write-Output 'DBAF_CASE_1_BYTE_REAL_SUCCESS_PASS'

# 2. Durable bridge result tamper is denied before cleanup.
$f2=New-DBAFFixtureV010 'bridge-tamper';$f2.bridge.result.bridge_fingerprint=('a'*64)
$r2=Invoke-DBAFFinalizeV010 -F $f2
Assert-DBAFV010 (-not[bool]$r2.ok) 'bridge tamper unexpectedly accepted'
Assert-DBAFV010 (Test-Path -LiteralPath ([string]$f2.atomic.transaction_root) -PathType Container) 'bridge tamper touched transaction root'
Write-Output 'DBAF_CASE_2_BRIDGE_TAMPER_DENIED_PASS'

# 3. Atomic journal ID substitution is denied before cleanup even when result fingerprint is recomputed.
$f3=New-DBAFFixtureV010 'journal-id-tamper'
$f3.atomic.transaction_id=[string]$f3.bridge.result.permit_transaction_id
$f3.atomic.result_fingerprint=Get-CustomAppProductionEvidenceBoundJournalAtomicMutationSha256V010 (Get-CustomAppProductionEvidenceBoundJournalAtomicMutationResultMaterialV010 -Result $f3.atomic)
$r3=Invoke-DBAFFinalizeV010 -F $f3
Assert-DBAFV010 (-not[bool]$r3.ok) 'journal id tamper unexpectedly accepted'
Assert-DBAFV010 (Test-Path -LiteralPath ([string]$f3.atomic.transaction_root) -PathType Container) 'journal id tamper touched transaction root'
Write-Output 'DBAF_CASE_3_JOURNAL_ID_TAMPER_DENIED_PASS'

# 4. Same-app newer consumption denies cleanup; unrelated newer consumption is allowed.
$f4=New-DBAFFixtureV010 'same-app-newer';$script:DBAFConsumptionMode='same-app-newer'
$r4=Invoke-DBAFFinalizeV010 -F $f4
Assert-DBAFV010 (-not[bool]$r4.ok-and([string]$r4.reason)-match'same-app-newer') 'same-app newer consumption not denied'
Assert-DBAFV010 (Test-Path -LiteralPath ([string]$f4.atomic.transaction_root) -PathType Container) 'same-app newer touched transaction root'
$f4b=New-DBAFFixtureV010 'other-app-newer';$script:DBAFConsumptionMode='other-app-newer'
$r4b=Invoke-DBAFFinalizeV010 -F $f4b
Assert-DBAFV010 ([bool]$r4b.ok) ('unrelated newer consumption denied: '+[string]$r4b.reason)
Write-Output 'DBAF_CASE_4_CONSUMPTION_ORDERING_PASS'

# 5. Journal phase drift denies cleanup before side effect.
$script:DBAFConsumptionMode='stable';$f5=New-DBAFFixtureV010 'phase-drift'
$jr5=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f5.trust -StoreDirectory $f5.store
$at=[DateTimeOffset]::Parse([string]$jr5.entry.recorded_at).AddMilliseconds(1)
$adv=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $f5.trust -StoreDirectory $f5.store -ExpectedRevision ([int64]$jr5.revision) -ExpectedEntrySha256 ([string]$jr5.entry.entry_sha256) -Phase 'rollback-required' -Now $at
Assert-DBAFV010 ([bool]$adv.ok) 'phase drift setup failed'
$r5=Invoke-DBAFFinalizeV010 -F $f5
Assert-DBAFV010 (-not[bool]$r5.ok-and([string]$r5.reason)-match'journal-state-invalid') 'journal phase drift not denied'
Assert-DBAFV010 (Test-Path -LiteralPath ([string]$f5.atomic.transaction_root) -PathType Container) 'journal phase drift touched transaction root'
Write-Output 'DBAF_CASE_5_JOURNAL_PHASE_DRIFT_DENIED_PASS'

# 6. Crash/fault after cleanup but before journal append leaves candidate-live and explicitly requires recovery.
$f6=New-DBAFFixtureV010 'post-cleanup-crash';$script:DBAFFault='after-cleanup'
$r6=Invoke-DBAFFinalizeV010 -F $f6
$script:DBAFFault=$null
Assert-DBAFV010 (-not[bool]$r6.ok-and[bool]$r6.transaction_workspace_deleted-and[bool]$r6.requires_recovery) 'post-cleanup fault did not fail closed into recovery'
Assert-DBAFV010 (-not(Test-Path -LiteralPath ([string]$f6.atomic.transaction_root))) 'post-cleanup fault transaction root still exists'
$jr6=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f6.trust -StoreDirectory $f6.store
Assert-DBAFV010 ([string]$jr6.entry.phase-ceq'candidate-live') 'post-cleanup fault journal phase unexpectedly advanced'
$class6=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $jr6 -ExpectedTransactionId ([string]$f6.bridge.result.journal_transaction_id)
Assert-DBAFV010 ([bool]$class6.ok-and[bool]$class6.requires_recovery_executor) 'post-cleanup fault not classified for recovery executor'
foreach($p in @([string]$f6.x.generic.app_backup_path,[string]$f6.x.generic.persistence_backup_path)){Assert-DBAFV010 (Test-Path -LiteralPath $p -PathType Container) 'post-cleanup recovery backup missing'}
Write-Output 'DBAF_CASE_6_POST_CLEANUP_CRASH_RECOVERY_PASS'

# 7. Result tamper is fingerprint-detectable and carries no authority.
$t=[pscustomobject]@{};foreach($p in $r1.result.PSObject.Properties){$t|Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value};$t.forward_continuity_uses_permit_id=$false
$tc=Test-CustomAppProductionDualIdBridgeAwareFinalizationResultV010 -Result $t
Assert-DBAFV010 (-not[bool]$tc.ok) 'result tamper unexpectedly validated'
Write-Output 'DBAF_CASE_7_RESULT_TAMPER_DENIED_PASS'

Write-Output 'CUSTOM_APP_PRODUCTION_DUAL_ID_BRIDGE_AWARE_FINALIZATION_PASS cases=7 byte_real=true journal_bound=true permit_forward=true journal_recovery=true'
