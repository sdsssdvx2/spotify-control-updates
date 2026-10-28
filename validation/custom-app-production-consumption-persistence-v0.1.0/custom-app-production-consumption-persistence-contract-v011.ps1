# v0.1.1 hardening overlay for the v0.1.0 durable store.
# PowerShell resolves functions at invocation time, so these exact-name definitions
# intentionally strengthen the envelope functions used by Initialize/Read/Save V010.
$CustomAppProductionConsumptionPersistenceContractSchema = 1
$CustomAppProductionConsumptionPersistenceContractManagedBy = 'custom-app-production-consumption-persistence-contract-v1.1'

function Get-CustomAppProductionConsumptionEnvelopeMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_consumption_head,
        [string]$Envelope.revision,[string]$Envelope.state_sha256,[string]$Envelope.previous_envelope_sha256,
        [string]$Envelope.written_at,[string]$Envelope.append_only,
        [string]$Envelope.requires_persisted_consumption_before_executor,[string]$Envelope.persistence_is_authority,
        [string]$Envelope.production_execution_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppProductionConsumptionEnvelopeV010 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$PreviousEnvelopeSha256,[DateTimeOffset]$WrittenAt=[DateTimeOffset]::UtcNow)
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $State
    if(-not [bool]$stateCheck.ok){throw ('cannot envelope invalid consumption state: '+[string]$stateCheck.reason)}
    $prev=$PreviousEnvelopeSha256.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $prev)){throw 'previous envelope sha256 invalid'}
    $stateJson=Get-CustomAppProductionConsumptionStateJsonV010 -State $State
    $e=[pscustomobject]@{
        schema=$CustomAppProductionConsumptionPersistenceSchema
        managed_by=$CustomAppProductionConsumptionPersistenceManagedBy
        qualified_consumption_head=$CustomAppProductionConsumptionPersistenceQualifiedConsumptionHead
        revision=[int64]$State.revision
        state_sha256=(Get-CustomAppProductionConsumptionPersistenceSha256V010 $stateJson)
        previous_envelope_sha256=$prev
        written_at=$WrittenAt.ToUniversalTime().ToString('o')
        append_only=$true
        requires_persisted_consumption_before_executor=$true
        persistence_is_authority=$false
        production_execution_authorized=$false
        production_mutation_authorized=$false
        state=$State
        envelope_sha256=$null
    }
    $e.envelope_sha256=Get-CustomAppProductionConsumptionPersistenceSha256V010 (Get-CustomAppProductionConsumptionEnvelopeMaterialV010 -Envelope $e)
    return $e
}

function Test-CustomAppProductionConsumptionEnvelopeV010 {
    param([AllowNull()]$Envelope)
    if($null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='envelope-null'}}
    foreach($required in @('schema','managed_by','qualified_consumption_head','revision','state_sha256','previous_envelope_sha256','written_at','append_only','requires_persisted_consumption_before_executor','persistence_is_authority','production_execution_authorized','production_mutation_authorized','state','envelope_sha256')){
        if(-not $Envelope.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('envelope-required-field-missing-'+$required)}}
    }
    if([int]$Envelope.schema -ne $CustomAppProductionConsumptionPersistenceSchema -or [string]$Envelope.managed_by -cne $CustomAppProductionConsumptionPersistenceManagedBy -or [string]$Envelope.qualified_consumption_head -cne $CustomAppProductionConsumptionPersistenceQualifiedConsumptionHead){return [pscustomobject]@{ok=$false;reason='envelope-owner-schema-parent-mismatch'}}
    if(-not [bool]$Envelope.append_only -or -not [bool]$Envelope.requires_persisted_consumption_before_executor -or [bool]$Envelope.persistence_is_authority -or [bool]$Envelope.production_execution_authorized -or [bool]$Envelope.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason='envelope-authority-or-persist-before-executor-contract-invalid'}}
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $Envelope.state
    if(-not [bool]$stateCheck.ok){return [pscustomobject]@{ok=$false;reason=('envelope-state-invalid:'+[string]$stateCheck.reason)}}
    try{$revision=[int64]$Envelope.revision}catch{return [pscustomobject]@{ok=$false;reason='envelope-revision-invalid'}}
    if($revision -ne [int64]$stateCheck.revision){return [pscustomobject]@{ok=$false;reason='envelope-state-revision-mismatch'}}
    $stateJson=Get-CustomAppProductionConsumptionStateJsonV010 -State $Envelope.state
    $expectedState=Get-CustomAppProductionConsumptionPersistenceSha256V010 $stateJson
    if(([string]$Envelope.state_sha256).Trim().ToLowerInvariant() -cne $expectedState){return [pscustomobject]@{ok=$false;reason='envelope-state-sha256-mismatch'}}
    $prev=([string]$Envelope.previous_envelope_sha256).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $prev)){return [pscustomobject]@{ok=$false;reason='envelope-previous-sha256-invalid'}}
    $actual=([string]$Envelope.envelope_sha256).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $actual)){return [pscustomobject]@{ok=$false;reason='envelope-sha256-invalid'}}
    $expected=Get-CustomAppProductionConsumptionPersistenceSha256V010 (Get-CustomAppProductionConsumptionEnvelopeMaterialV010 -Envelope $Envelope)
    if($actual -cne $expected){return [pscustomobject]@{ok=$false;reason='envelope-sha256-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='envelope-valid-persist-before-executor-bound';revision=$revision;state_sha256=$expectedState;envelope_sha256=$actual;requires_persisted_consumption_before_executor=$true;persistence_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}

function Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 {
    param([AllowNull()]$StoreRead,[AllowNull()][string]$ExpectedConsumptionId=$null)
    if($null -eq $StoreRead -or -not [bool]$StoreRead.ok){return [pscustomobject]@{ok=$false;reason='persisted-store-read-not-ok';executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if(-not $StoreRead.PSObject.Properties['reloaded_from_persistent_store'] -or -not [bool]$StoreRead.reloaded_from_persistent_store){return [pscustomobject]@{ok=$false;reason='persisted-store-not-reloaded';executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $envelopeCheck=Test-CustomAppProductionConsumptionEnvelopeV010 -Envelope $StoreRead.envelope
    if(-not [bool]$envelopeCheck.ok){return [pscustomobject]@{ok=$false;reason=('persisted-envelope-invalid:'+[string]$envelopeCheck.reason);executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if(-not [bool]$StoreRead.envelope.requires_persisted_consumption_before_executor){return [pscustomobject]@{ok=$false;reason='persist-before-executor-flag-missing';executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $rows=@($StoreRead.state.consumptions)
    if($rows.Count -lt 1){return [pscustomobject]@{ok=$false;reason='persisted-consumption-row-missing';executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $last=$rows[-1]
    if(-not [string]::IsNullOrWhiteSpace($ExpectedConsumptionId) -and ([string]$last.consumption_id).Trim().ToLowerInvariant() -cne $ExpectedConsumptionId.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='persisted-consumption-id-mismatch';executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    return [pscustomobject]@{ok=$true;reason='persisted-consumption-barrier-attested';consumption_id=[string]$last.consumption_id;revision=[int64]$StoreRead.revision;requires_persisted_consumption_before_executor=$true;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
