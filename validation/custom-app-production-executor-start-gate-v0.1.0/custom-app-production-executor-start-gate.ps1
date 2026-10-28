$CustomAppProductionExecutorStartGateSchema = 1
$CustomAppProductionExecutorStartGateManagedBy = 'custom-app-production-executor-start-gate-v1'
$CustomAppProductionExecutorStartGateQualifiedPersistenceHead = '1b680f0fc637b393aa7571690c8aa40adda59800'

function Get-CustomAppProductionExecutorStartGateSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionExecutorStartGateSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionExecutorStartConsumptionPermitContinuityV010 {
    param([AllowNull()]$ConsumptionRow,[AllowNull()]$Permit)
    if($null -eq $ConsumptionRow -or $null -eq $Permit){return [pscustomobject]@{ok=$false;reason='consumption-permit-null'}}
    $pairs=@(
        @('token_id','token_id'),@('permit_nonce','nonce'),@('permit_hmac_sha256','hmac_sha256'),@('name','name'),@('source_identity','source_identity'),
        @('surface_kind','surface_kind'),@('current_tree_sha256','current_tree_sha256'),@('remote_tree_sha256','remote_tree_sha256'),@('remote_commit_sha','remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','admission_fingerprint'),
        @('permit_issued_at','issued_at'),@('permit_expires_at','expires_at')
    )
    foreach($pair in $pairs){
        $left=([string]$ConsumptionRow.($pair[0])).Trim().ToLowerInvariant();$right=([string]$Permit.($pair[1])).Trim().ToLowerInvariant()
        if($left -cne $right){return [pscustomobject]@{ok=$false;reason=('consumption-permit-mismatch-'+$pair[0])}}
    }
    try{if([int64]$ConsumptionRow.github_repo_id -ne [int64]$Permit.github_repo_id){return [pscustomobject]@{ok=$false;reason='consumption-permit-mismatch-github_repo_id'}}}catch{return [pscustomobject]@{ok=$false;reason='consumption-permit-github_repo_id-invalid'}}
    if(-not [bool]$ConsumptionRow.single_use -or [bool]$ConsumptionRow.consumption_is_authority -or -not [bool]$ConsumptionRow.requires_persisted_consumption_before_executor -or -not [bool]$ConsumptionRow.requires_fresh_permit_revalidation_at_executor_start -or -not [bool]$ConsumptionRow.requires_fresh_revalidation_after_stage -or -not [bool]$ConsumptionRow.requires_fresh_revalidation_before_apply){return [pscustomobject]@{ok=$false;reason='consumption-executor-contract-invalid'}}
    return [pscustomobject]@{ok=$true;reason='consumption-permit-continuity-valid'}
}

function Get-CustomAppProductionExecutorStartEligibilityMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @(
        [string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_persistence_head,[string]$Decision.reason,
        [string]$Decision.consumption_id,[string]$Decision.consumption_store_revision,[string]$Decision.persistence_envelope_sha256,
        [string]$Decision.token_id,[string]$Decision.name,[string]$Decision.source_identity,[string]$Decision.github_repo_id,[string]$Decision.surface_kind,
        [string]$Decision.current_tree_sha256,[string]$Decision.remote_tree_sha256,[string]$Decision.remote_commit_sha,
        [string]$Decision.current_eligibility_fingerprint,[string]$Decision.live_attested_qualification_fingerprint,[string]$Decision.admission_fingerprint,
        [string]$Decision.evaluated_at,[string]$Decision.staging_eligibility_expires_at,[string]$Decision.staging_eligible,
        [string]$Decision.eligibility_is_authority,[string]$Decision.requires_fresh_revalidation_before_stage_acquisition,
        [string]$Decision.requires_fresh_revalidation_after_stage,[string]$Decision.requires_fresh_revalidation_before_apply,
        [string]$Decision.stage_acquisition_authorized,[string]$Decision.executor_may_stage,[string]$Decision.executor_may_apply,
        [string]$Decision.production_execution_authorized,[string]$Decision.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionExecutorStartEligibilityV010 {
    param([AllowNull()]$Decision)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='start-eligibility-null'}}
    foreach($required in @('schema','managed_by','qualified_persistence_head','reason','consumption_id','consumption_store_revision','persistence_envelope_sha256','token_id','name','source_identity','github_repo_id','surface_kind','current_tree_sha256','remote_tree_sha256','remote_commit_sha','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint','evaluated_at','staging_eligibility_expires_at','staging_eligible','eligibility_fingerprint','eligibility_is_authority','requires_fresh_revalidation_before_stage_acquisition','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','stage_acquisition_authorized','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if(-not $Decision.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('start-eligibility-required-field-missing-'+$required)}}}
    if([int]$Decision.schema -ne 1 -or [string]$Decision.managed_by -cne $CustomAppProductionExecutorStartGateManagedBy -or [string]$Decision.qualified_persistence_head -cne $CustomAppProductionExecutorStartGateQualifiedPersistenceHead -or [string]$Decision.reason -cne 'persisted-consumption-freshly-revalidated-staging-eligible'){return [pscustomobject]@{ok=$false;reason='start-eligibility-owner-schema-parent-or-reason-invalid'}}
    if(-not [bool]$Decision.staging_eligible -or [bool]$Decision.eligibility_is_authority -or -not [bool]$Decision.requires_fresh_revalidation_before_stage_acquisition -or -not [bool]$Decision.requires_fresh_revalidation_after_stage -or -not [bool]$Decision.requires_fresh_revalidation_before_apply){return [pscustomobject]@{ok=$false;reason='start-eligibility-separation-contract-invalid'}}
    foreach($field in @('stage_acquisition_authorized','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$field){return [pscustomobject]@{ok=$false;reason=('start-eligibility-'+$field+'-true')}}}
    foreach($field in @('consumption_id','persistence_envelope_sha256','token_id','current_tree_sha256','remote_tree_sha256','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint','eligibility_fingerprint')){if(-not (Test-CustomAppProductionExecutorStartGateSha256V010 (([string]$Decision.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('start-eligibility-invalid-'+$field)}}}
    if(([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='start-eligibility-invalid-remote-commit'}}
    $evaluated=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Decision.evaluated_at,[ref]$evaluated) -or -not [DateTimeOffset]::TryParse([string]$Decision.staging_eligibility_expires_at,[ref]$expires) -or $expires -le $evaluated -or $expires -gt $evaluated.AddSeconds(60)){return [pscustomobject]@{ok=$false;reason='start-eligibility-time-window-invalid'}}
    $expected=Get-CustomAppProductionExecutorStartGateSha256V010 (Get-CustomAppProductionExecutorStartEligibilityMaterialV010 -Decision $Decision)
    if(([string]$Decision.eligibility_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='start-eligibility-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='start-eligibility-valid-no-authority';eligibility_fingerprint=$expected}
}

function Resolve-CustomAppProductionExecutorStartGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;staging_eligible=$false;eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true;stage_acquisition_authorized=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $id=$ExpectedConsumptionId.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionExecutorStartGateSha256V010 $id)){return & $deny 'expected-consumption-id-invalid'}
    try{$store=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('persisted-consumption-read-denied:'+[string]$_.Exception.Message)}
    if($null -eq $store -or -not [bool]$store.ok -or -not $store.PSObject.Properties['reloaded_from_persistent_store'] -or -not [bool]$store.reloaded_from_persistent_store){return & $deny 'persisted-consumption-store-not-reloaded'}
    $envelopeCheck=Test-CustomAppProductionConsumptionEnvelopeV010 -Envelope $store.envelope
    if(-not [bool]$envelopeCheck.ok -or -not [bool]$store.envelope.requires_persisted_consumption_before_executor){return & $deny ('persisted-consumption-envelope-invalid:'+[string]$envelopeCheck.reason)}
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $store.state
    if(-not [bool]$stateCheck.ok){return & $deny ('persisted-consumption-state-invalid:'+[string]$stateCheck.reason)}
    $rows=@($store.state.consumptions);$matches=@($rows|Where-Object{([string]$_.consumption_id).Trim().ToLowerInvariant() -ceq $id})
    if($matches.Count -ne 1){return & $deny 'persisted-consumption-id-not-found-or-ambiguous'}
    $row=$matches[0]
    $newerSameName=@($rows|Where-Object{[int64]$_.state_revision_after -gt [int64]$row.state_revision_after -and ([string]$_.name).Trim().ToLowerInvariant() -ceq ([string]$row.name).Trim().ToLowerInvariant()})
    if($newerSameName.Count -gt 0){return & $deny 'persisted-consumption-superseded-by-newer-same-app'}
    $permitCheck=Test-CustomAppProductionPermitV010 -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if(-not [bool]$permitCheck.ok){return & $deny ('executor-start-permit-revalidation-denied:'+[string]$permitCheck.reason)}
    $continuity=Test-CustomAppProductionExecutorStartConsumptionPermitContinuityV010 -ConsumptionRow $row -Permit $Permit
    if(-not [bool]$continuity.ok){return & $deny ([string]$continuity.reason)}
    $consumed=[DateTimeOffset]::MinValue;$permitExpires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$row.consumed_at,[ref]$consumed) -or -not [DateTimeOffset]::TryParse([string]$Permit.expires_at,[ref]$permitExpires)){return & $deny 'executor-start-time-evidence-invalid'}
    if($Now -lt $consumed.AddSeconds(-30)){return & $deny 'executor-start-before-persisted-consumption-time'}
    $eligibilityExpires=$Now.AddSeconds(60);if($permitExpires -lt $eligibilityExpires){$eligibilityExpires=$permitExpires}
    if($eligibilityExpires -le $Now){return & $deny 'executor-start-eligibility-window-empty'}
    $decision=[pscustomobject]@{
        schema=$CustomAppProductionExecutorStartGateSchema;managed_by=$CustomAppProductionExecutorStartGateManagedBy;qualified_persistence_head=$CustomAppProductionExecutorStartGateQualifiedPersistenceHead
        reason='persisted-consumption-freshly-revalidated-staging-eligible';consumption_id=$id;consumption_store_revision=[int64]$store.revision;persistence_envelope_sha256=([string]$store.envelope.envelope_sha256).Trim().ToLowerInvariant();token_id=([string]$Permit.token_id).Trim().ToLowerInvariant()
        name=[string]$Permit.name;source_identity=([string]$Permit.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$Permit.github_repo_id;surface_kind=([string]$Permit.surface_kind).Trim().ToLowerInvariant()
        current_tree_sha256=([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant()
        current_eligibility_fingerprint=([string]$Permit.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$Permit.live_attested_qualification_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$Permit.admission_fingerprint).Trim().ToLowerInvariant()
        evaluated_at=$Now.ToUniversalTime().ToString('o');staging_eligibility_expires_at=$eligibilityExpires.ToUniversalTime().ToString('o');staging_eligible=$true;eligibility_fingerprint=$null;eligibility_is_authority=$false
        requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $decision.eligibility_fingerprint=Get-CustomAppProductionExecutorStartGateSha256V010 (Get-CustomAppProductionExecutorStartEligibilityMaterialV010 -Decision $decision)
    $decisionCheck=Test-CustomAppProductionExecutorStartEligibilityV010 -Decision $decision
    if(-not [bool]$decisionCheck.ok){return & $deny ('executor-start-eligibility-self-validation-failed:'+[string]$decisionCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason=[string]$decision.reason;decision=$decision;consumption_id=$id;staging_eligible=$true;eligibility_fingerprint=[string]$decision.eligibility_fingerprint
        eligibility_is_authority=$false;requires_fresh_revalidation_before_stage_acquisition=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
