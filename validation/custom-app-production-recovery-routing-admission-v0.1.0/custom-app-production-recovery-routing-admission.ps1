$CustomAppProductionRecoveryRoutingAdmissionSchema = 1
$CustomAppProductionRecoveryRoutingAdmissionManagedBy = 'custom-app-production-recovery-routing-admission-v1'
$CustomAppProductionRecoveryRoutingAdmissionQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'
$CustomAppProductionRecoveryRoutingAdmissionQualifiedBoundedExecutorHead = '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'
$CustomAppProductionRecoveryRoutingAdmissionQualifiedIntegratedCandidateHead = '92a3e8ac83c8bbbe9e5d4b6f3f00469701250acc'

function Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryRoutingAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_journal_head,[string]$Receipt.qualified_bounded_executor_head,[string]$Receipt.qualified_integrated_candidate_head,
        [string]$Receipt.transaction_id,[string]$Receipt.phase,[string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,[string]$Receipt.classification,[string]$Receipt.classification_reason,
        [string]$Receipt.route,[string]$Receipt.next_validator,[string]$Receipt.requires_manual_resolution,[string]$Receipt.requires_bounded_recovery_executor,[string]$Receipt.requires_bounded_housekeeping,[string]$Receipt.requires_recovery_artifact_retirement,[string]$Receipt.requires_new_update_permit_readiness,
        [string]$Receipt.requires_future_fresh_revalidation,[string]$Receipt.checked_at,[string]$Receipt.eligible_until,
        [string]$Receipt.routing_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.permit_issued,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}
function New-CustomAppProductionRecoveryRoutingAdmissionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{ok=$false;reason=$Reason;route='fail-closed';routing_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false}
}
function Get-CustomAppProductionRecoveryRoutingExpectedV010 {
    param([Parameter(Mandatory=$true)][string]$Phase)
    switch($Phase){
        'prepared' {return [pscustomobject]@{route='prepared-transaction-resolution-required';next='explicit-prepared-transaction-resolution-not-yet-wired';manual=$true;recovery=$false;housekeeping=$false;retirement=$false;new_permit=$false}}
        'atomic-mutation-starting' {return [pscustomobject]@{route='manual-filesystem-recovery-inspection-required';next='manual-filesystem-recovery-inspection';manual=$true;recovery=$false;housekeeping=$false;retirement=$false;new_permit=$false}}
        'live-moved-to-old' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'candidate-live' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'transaction-finalized' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'apply-starting' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'apply-returned-success-pending-verification' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'rollback-required' {return [pscustomobject]@{route='bounded-recovery-executor-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$true;housekeeping=$false;retirement=$false;new_permit=$false}}
        'apply-verified' {return [pscustomobject]@{route='bounded-recovery-housekeeping-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$false;housekeeping=$true;retirement=$false;new_permit=$false}}
        'cleanup-starting' {return [pscustomobject]@{route='bounded-recovery-housekeeping-candidate';next='Invoke-CustomAppProductionBoundedRecoveryExecutorV010';manual=$false;recovery=$false;housekeeping=$true;retirement=$false;new_permit=$false}}
        'rollback-complete' {return [pscustomobject]@{route='recovery-artifact-retirement-required';next='Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010';manual=$false;recovery=$false;housekeeping=$false;retirement=$true;new_permit=$true}}
        'committed-clean' {return [pscustomobject]@{route='terminal-new-update-permit-readiness-required';next='fresh-normal-terminal-new-permit-policy-not-yet-wired';manual=$false;recovery=$false;housekeeping=$false;retirement=$false;new_permit=$true}}
        default {return $null}
    }
}
function Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 {
    param([AllowNull()]$Receipt,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Receipt){return [pscustomobject]@{ok=$false;reason='recovery-routing-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_journal_head','qualified_bounded_executor_head','qualified_integrated_candidate_head','transaction_id','phase','journal_revision','journal_entry_sha256','classification','classification_reason','route','next_validator','requires_manual_resolution','requires_bounded_recovery_executor','requires_bounded_housekeeping','requires_recovery_artifact_retirement','requires_new_update_permit_readiness','requires_future_fresh_revalidation','checked_at','eligible_until','routing_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized','routing_fingerprint')){if(-not$Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-routing-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema-ne1-or[string]$Receipt.managed_by-cne$CustomAppProductionRecoveryRoutingAdmissionManagedBy-or[string]$Receipt.qualified_journal_head-cne$CustomAppProductionRecoveryRoutingAdmissionQualifiedJournalHead-or[string]$Receipt.qualified_bounded_executor_head-cne$CustomAppProductionRecoveryRoutingAdmissionQualifiedBoundedExecutorHead-or[string]$Receipt.qualified_integrated_candidate_head-cne$CustomAppProductionRecoveryRoutingAdmissionQualifiedIntegratedCandidateHead){return [pscustomobject]@{ok=$false;reason='recovery-routing-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','journal_entry_sha256','routing_fingerprint')){if(-not(Test-CustomAppProductionRecoveryRoutingAdmissionSha256V010(([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-routing-invalid-'+$f)}}}
    if([int64]$Receipt.journal_revision-lt0){return [pscustomobject]@{ok=$false;reason='recovery-routing-journal-revision-invalid'}}
    $expected=Get-CustomAppProductionRecoveryRoutingExpectedV010 -Phase ([string]$Receipt.phase);if($null-eq$expected){return [pscustomobject]@{ok=$false;reason='recovery-routing-phase-unsupported'}}
    if([string]$Receipt.route-cne[string]$expected.route-or[string]$Receipt.next_validator-cne[string]$expected.next){return [pscustomobject]@{ok=$false;reason='recovery-routing-semantic-route-drift'}}
    $checks=@(
        @('requires_manual_resolution','manual'),@('requires_bounded_recovery_executor','recovery'),@('requires_bounded_housekeeping','housekeeping'),@('requires_recovery_artifact_retirement','retirement'),@('requires_new_update_permit_readiness','new_permit')
    )
    foreach($p in $checks){if([bool]$Receipt.($p[0])-ne[bool]$expected.($p[1])){return [pscustomobject]@{ok=$false;reason=('recovery-routing-semantic-flag-drift-'+[string]$p[0])}}}
    if(-not[bool]$Receipt.requires_future_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='recovery-routing-future-revalidation-contract-missing'}}
    foreach($f in @('routing_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-routing-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Receipt.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='recovery-routing-time-invalid'}}
    if($end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='recovery-routing-window-invalid'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-routing-not-yet-valid'}}
    if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='recovery-routing-expired'}}
    $fp=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $Receipt);if(([string]$Receipt.routing_fingerprint).Trim().ToLowerInvariant()-cne$fp){return [pscustomobject]@{ok=$false;reason='recovery-routing-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-routing-valid-zero-authority';route=[string]$Receipt.route;next_validator=[string]$Receipt.next_validator;transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant()}
}
function Resolve-CustomAppProductionRecoveryRoutingAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryRoutingAdmissionDeniedV010 -Reason $Reason}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryRoutingAdmissionSha256V010 $tx)){return & $deny 'recovery-routing-transaction-id-invalid'}
    try{$read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('recovery-routing-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$read-or-not[bool]$read.ok-or-not[bool]$read.reloaded_from_persistent_store){return & $deny ('recovery-routing-journal-not-durably-reloaded:'+[string]$read.reason)}
    if(([string]$read.transaction_id).Trim().ToLowerInvariant()-cne$tx-or([string]$read.entry.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'recovery-routing-transaction-mismatch'}
    $classification=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $read -ExpectedTransactionId $tx
    if($null-eq$classification-or-not[bool]$classification.ok){return & $deny ('recovery-routing-classification-denied:'+[string]$classification.reason)}
    if([bool]$classification.journal_is_authority-or[bool]$classification.production_execution_authorized-or[bool]$classification.production_mutation_authorized){return & $deny 'recovery-routing-classification-authority-drift'}
    $expected=Get-CustomAppProductionRecoveryRoutingExpectedV010 -Phase ([string]$read.entry.phase);if($null-eq$expected){return & $deny 'recovery-routing-phase-unsupported'}
    if([string]$read.entry.phase-ceq'prepared' -and (-not[bool]$classification.no_action-or[bool]$classification.requires_recovery_executor)){return & $deny 'recovery-routing-prepared-classification-drift'}
    if([string]$read.entry.phase-ceq'atomic-mutation-starting' -and -not[bool]$classification.requires_recovery_executor){return & $deny 'recovery-routing-atomic-classification-drift'}
    if([string]$read.entry.phase-in@('live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','rollback-required') -and -not[bool]$classification.requires_recovery_executor){return & $deny 'recovery-routing-recovery-classification-drift'}
    if([string]$read.entry.phase-in@('apply-verified','cleanup-starting') -and (-not[bool]$classification.housekeeping_only-or[bool]$classification.requires_recovery_executor)){return & $deny 'recovery-routing-housekeeping-classification-drift'}
    if([string]$read.entry.phase-in@('committed-clean','rollback-complete') -and -not[bool]$classification.no_action){return & $deny 'recovery-routing-terminal-classification-drift'}
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryRoutingAdmissionSchema;managed_by=$CustomAppProductionRecoveryRoutingAdmissionManagedBy;qualified_journal_head=$CustomAppProductionRecoveryRoutingAdmissionQualifiedJournalHead;qualified_bounded_executor_head=$CustomAppProductionRecoveryRoutingAdmissionQualifiedBoundedExecutorHead;qualified_integrated_candidate_head=$CustomAppProductionRecoveryRoutingAdmissionQualifiedIntegratedCandidateHead
        transaction_id=$tx;phase=[string]$read.entry.phase;journal_revision=[int64]$read.revision;journal_entry_sha256=([string]$read.entry.entry_sha256).Trim().ToLowerInvariant();classification=[string]$classification.classification;classification_reason=[string]$classification.reason
        route=[string]$expected.route;next_validator=[string]$expected.next;requires_manual_resolution=[bool]$expected.manual;requires_bounded_recovery_executor=[bool]$expected.recovery;requires_bounded_housekeeping=[bool]$expected.housekeeping;requires_recovery_artifact_retirement=[bool]$expected.retirement;requires_new_update_permit_readiness=[bool]$expected.new_permit;requires_future_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        routing_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false;routing_fingerprint=$null
    }
    $receipt.routing_fingerprint=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $receipt)
    $check=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $receipt -Now $Now;if(-not[bool]$check.ok){return & $deny ('recovery-routing-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='recovery-routing-read-only-zero-authority';receipt=$receipt;classification=$classification;routing_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false}
}
