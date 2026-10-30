$CustomAppProductionJournaledFixtureOrchestratorSchema = 1
$CustomAppProductionJournaledFixtureOrchestratorManagedBy = 'custom-app-production-journaled-orchestrator-fixture-v1'
$CustomAppProductionJournaledFixtureOrchestratorQualifiedJournalIntegrationHead = 'f870ee7df375284a98af5870fe4a51cf1b4ed69c'

function Test-CustomAppProductionJournaledFixtureSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 {
    param([AllowNull()]$Value,[string]$Label='value')
    if($null -eq $Value){ throw "$Label null" }
    foreach($field in @('result_is_authority','journal_is_authority','callback_result_is_authority','production_execution_authorized','production_mutation_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized')){
        $p=$Value.PSObject.Properties[$field]
        if($null -ne $p -and [bool]$p.Value){ throw "$Label authority escaped through $field" }
    }
}

function Invoke-CustomAppProductionJournaledFixtureValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function to inject fixture-only faults.
}

function Invoke-CustomAppProductionJournaledFixtureCrashPointV010 {
    param([Parameter(Mandatory=$true)][string]$Requested,[Parameter(Mandatory=$true)][string]$Point)
    if($Requested -ceq $Point){ throw ('fixture-crash:'+ $Point) }
}

function Read-CustomAppProductionJournaledFixtureDurablePhaseV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$ExpectedPhase
    )
    $r=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    if($null -eq $r -or -not [bool]$r.ok){ throw ('fixture durable journal read denied: '+[string]$r.reason) }
    if(-not [bool]$r.reloaded_from_persistent_store){ throw 'fixture durable journal read was not reloaded from persistent store' }
    if(([string]$r.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){ throw 'fixture durable journal transaction id mismatch' }
    if([string]$r.entry.phase -cne $ExpectedPhase){ throw ("fixture durable journal phase mismatch actual=$([string]$r.entry.phase) expected=$ExpectedPhase") }
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $r -Label ('durable-read-'+$ExpectedPhase)
    return $r
}

function Add-CustomAppProductionJournaledFixturePhaseV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)]$Current,
        [Parameter(Mandatory=$true)][string]$Phase,
        [AllowNull()][string]$FinalizationFingerprint=$null,
        [AllowNull()][string]$ApplyResultFingerprint=$null,
        [AllowNull()][string]$CleanupResultFingerprint=$null,
        [Parameter(Mandatory=$true)][DateTimeOffset]$Now
    )
    $r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$Current.revision) -ExpectedEntrySha256 ([string]$Current.entry.entry_sha256) -Phase $Phase -FinalizationFingerprint $FinalizationFingerprint -ApplyResultFingerprint $ApplyResultFingerprint -CleanupResultFingerprint $CleanupResultFingerprint -Now $Now
    if($null -eq $r -or -not [bool]$r.ok){ throw ('fixture journal phase append denied '+$Phase+': '+[string]$r.reason) }
    if(-not [bool]$r.persisted -or -not [bool]$r.read_after_write_verified){ throw ('fixture journal phase not durably readback verified: '+$Phase) }
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $r -Label ('phase-append-'+$Phase)
    return $r
}

function Invoke-CustomAppProductionJournaledFixtureCallbackV010 {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Callback,
        [Parameter(Mandatory=$true)][string]$Action,
        [Parameter(Mandatory=$true)]$FixtureContext,
        [Parameter(Mandatory=$true)]$DurableRead,
        [bool]$RequireFingerprint=$false
    )
    if($null -eq $DurableRead -or -not [bool]$DurableRead.ok -or -not [bool]$DurableRead.reloaded_from_persistent_store){ throw ('fixture callback '+$Action+' missing durable journal prerequisite') }
    $ctx=[pscustomobject]@{
        schema=$CustomAppProductionJournaledFixtureOrchestratorSchema
        managed_by=$CustomAppProductionJournaledFixtureOrchestratorManagedBy
        action=$Action
        durable_phase=[string]$DurableRead.entry.phase
        transaction_id=[string]$DurableRead.entry.transaction_id
        revision=[int64]$DurableRead.revision
        fixture_context=$FixtureContext
        fixture_only=$true
        production_execution_authorized=$false
        production_mutation_authorized=$false
    }
    $r=& $Callback $ctx
    if($null -eq $r -or -not $r.PSObject.Properties['ok'] -or -not [bool]$r.ok){ throw ('fixture callback denied '+$Action+': '+[string]$r.reason) }
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $r -Label ('callback-'+$Action)
    if($RequireFingerprint){
        if(-not $r.PSObject.Properties['fingerprint'] -or -not (Test-CustomAppProductionJournaledFixtureSha256V010 (([string]$r.fingerprint).Trim().ToLowerInvariant()))){ throw ('fixture callback fingerprint invalid: '+$Action) }
    }
    return $r
}

function Get-CustomAppProductionJournaledFixtureRecoveryV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
    )
    try { $read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory }
    catch {
        return [pscustomobject]@{ok=$false;reason=('fixture-recovery-journal-read-failed:'+[string]$_.Exception.Message);classification='fail-closed';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;orchestrator_is_authority=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }
    $c=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $read -ExpectedTransactionId $ExpectedTransactionId
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $c -Label 'fixture-recovery-classification'
    return [pscustomobject]@{
        ok=[bool]$c.ok;reason=[string]$c.reason;classification=[string]$c.classification
        phase=$(if($null -ne $read -and $null -ne $read.entry){[string]$read.entry.phase}else{$null})
        transaction_id=$(if($null -ne $read){[string]$read.transaction_id}else{$null})
        requires_fresh_filesystem_revalidation=[bool]$c.requires_fresh_filesystem_revalidation
        requires_recovery_executor=[bool]$c.requires_recovery_executor
        housekeeping_only=[bool]$c.housekeeping_only;no_action=[bool]$c.no_action
        orchestrator_is_authority=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Invoke-CustomAppProductionJournaledFixtureOrchestratorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)]$Identity,
        [Parameter(Mandatory=$true)]$FixtureContext,
        [Parameter(Mandatory=$true)][scriptblock]$MoveLiveToOldCallback,
        [Parameter(Mandatory=$true)][scriptblock]$MoveCandidateLiveCallback,
        [Parameter(Mandatory=$true)][scriptblock]$FinalizeTransactionCallback,
        [Parameter(Mandatory=$true)][scriptblock]$ApplyCallback,
        [Parameter(Mandatory=$true)][scriptblock]$VerifyApplyCallback,
        [Parameter(Mandatory=$true)][scriptblock]$CleanupCallback,
        [ValidateSet('none','after-atomic-starting-before-live-move','after-live-move-before-journal','after-live-moved-before-candidate','after-candidate-before-journal','after-candidate-live-before-finalize','after-finalize-before-journal','after-transaction-finalized-before-apply-starting','after-apply-starting-before-apply','after-apply-before-returned','after-apply-returned-before-verify','after-verify-before-verified','after-apply-verified-before-cleanup-starting','after-cleanup-starting-before-cleanup','after-cleanup-before-committed')][string]$CrashPoint='none',
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $id=Test-CustomAppProductionCrashJournalIdentityV010 -Identity $Identity -AllowedRoot $AllowedRoot
    if(-not [bool]$id.ok){ throw ('fixture orchestrator identity denied: '+[string]$id.reason) }
    $tx=[string]$id.transaction_id
    $init=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Identity $Identity -Now $Now
    if($null -eq $init -or -not [bool]$init.ok -or -not [bool]$init.persisted -or -not [bool]$init.read_after_write_verified){ throw ('fixture orchestrator journal init denied: '+[string]$init.reason) }
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $init -Label 'fixture-init'
    $current=$init;$step=0

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'atomic-mutation-starting' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-atomic-mutation-starting' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'atomic-mutation-starting'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-atomic-starting-before-live-move'
    [void](Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $MoveLiveToOldCallback -Action 'move-live-to-old' -FixtureContext $FixtureContext -DurableRead $durable)
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-live-move-before-journal'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'live-moved-to-old' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-live-moved-to-old' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'live-moved-to-old'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-live-moved-before-candidate'
    [void](Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $MoveCandidateLiveCallback -Action 'move-candidate-live' -FixtureContext $FixtureContext -DurableRead $durable)
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-candidate-before-journal'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'candidate-live' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-candidate-live' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'candidate-live'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-candidate-live-before-finalize'
    $final=Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $FinalizeTransactionCallback -Action 'finalize-transaction' -FixtureContext $FixtureContext -DurableRead $durable -RequireFingerprint:$true
    $finalFp=([string]$final.fingerprint).Trim().ToLowerInvariant()
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-finalize-before-journal'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'transaction-finalized' -FinalizationFingerprint $finalFp -Now $Now.AddSeconds($step)
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'transaction-finalized'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-transaction-finalized-before-apply-starting'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'apply-starting' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-apply-starting' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'apply-starting'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-apply-starting-before-apply'
    [void](Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $ApplyCallback -Action 'apply' -FixtureContext $FixtureContext -DurableRead $durable)
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-apply-before-returned'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'apply-returned-success-pending-verification' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-apply-returned-success-pending-verification' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'apply-returned-success-pending-verification'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-apply-returned-before-verify'
    $verified=Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $VerifyApplyCallback -Action 'verify-apply' -FixtureContext $FixtureContext -DurableRead $durable -RequireFingerprint:$true
    $applyFp=([string]$verified.fingerprint).Trim().ToLowerInvariant()
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-verify-before-verified'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'apply-verified' -ApplyResultFingerprint $applyFp -Now $Now.AddSeconds($step)
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'apply-verified'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-apply-verified-before-cleanup-starting'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'cleanup-starting' -Now $Now.AddSeconds($step)
    Invoke-CustomAppProductionJournaledFixtureValidationHookV010 -Checkpoint 'after-phase-persisted-cleanup-starting' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store=$StoreDirectory;transaction_id=$tx;fixture_context=$FixtureContext})
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'cleanup-starting'
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-cleanup-starting-before-cleanup'
    $clean=Invoke-CustomAppProductionJournaledFixtureCallbackV010 -Callback $CleanupCallback -Action 'cleanup' -FixtureContext $FixtureContext -DurableRead $durable -RequireFingerprint:$true
    $cleanupFp=([string]$clean.fingerprint).Trim().ToLowerInvariant()
    Invoke-CustomAppProductionJournaledFixtureCrashPointV010 -Requested $CrashPoint -Point 'after-cleanup-before-committed'

    $step++;$current=Add-CustomAppProductionJournaledFixturePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Current $current -Phase 'committed-clean' -CleanupResultFingerprint $cleanupFp -Now $Now.AddSeconds($step)
    $durable=Read-CustomAppProductionJournaledFixtureDurablePhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -ExpectedPhase 'committed-clean'
    $recovery=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $durable -ExpectedTransactionId $tx
    if($null -eq $recovery -or -not [bool]$recovery.ok -or -not [bool]$recovery.no_action -or [string]$recovery.classification -cne 'no-action-new-permit-required-for-future-update'){ throw 'fixture orchestrator terminal recovery classification invalid' }
    Assert-CustomAppProductionJournaledFixtureZeroAuthorityV010 -Value $recovery -Label 'fixture-terminal-recovery'

    return [pscustomobject]@{
        schema=$CustomAppProductionJournaledFixtureOrchestratorSchema;managed_by=$CustomAppProductionJournaledFixtureOrchestratorManagedBy
        qualified_journal_integration_head=$CustomAppProductionJournaledFixtureOrchestratorQualifiedJournalIntegrationHead
        ok=$true;reason='fixture-journaled-orchestration-committed-clean';fixture_only=$true
        transaction_id=$tx;phase='committed-clean';revision=[int64]$durable.revision
        finalization_fingerprint=$finalFp;apply_result_fingerprint=$applyFp;cleanup_result_fingerprint=$cleanupFp
        recovery_classification=[string]$recovery.classification
        callbacks_are_dependency_injected=$true;durable_phase_reloaded_before_each_callback=$true
        orchestrator_is_authority=$false;result_is_authority=$false;journal_is_authority=$false
        production_execution_authorized=$false;production_mutation_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false
    }
}
