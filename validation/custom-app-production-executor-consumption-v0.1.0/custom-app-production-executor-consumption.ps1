$CustomAppProductionExecutorConsumptionStateSchema = 1
$CustomAppProductionExecutorConsumptionStateManagedBy = 'custom-app-production-executor-consumption-state-v1'
$CustomAppProductionExecutorConsumptionRowManagedBy = 'custom-app-production-executor-consumption-v1'
$CustomAppProductionExecutorConsumptionQualifiedReservationHead = 'edb8a34c61abb28838ba6ca89cf539bdf28bec2a'

function Get-CustomAppProductionExecutorConsumptionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionExecutorConsumptionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionExecutorConsumptionNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}

function Test-CustomAppProductionExecutorConsumptionCommitV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')
}

function Test-CustomAppProductionExecutorConsumptionDeniedAuthorityV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_execution_authorized','production_mutation_authorized')){
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-authority-denied')}
}

function New-CustomAppProductionExecutorConsumptionStateV010 {
    return [pscustomobject]@{
        schema=$CustomAppProductionExecutorConsumptionStateSchema;managed_by=$CustomAppProductionExecutorConsumptionStateManagedBy;revision=[int64]0;consumptions=@()
        append_only=$true;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionExecutorConsumptionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Row)
    return @(
        [string]$Row.schema,[string]$Row.managed_by,[string]$Row.qualified_reservation_head,[string]$Row.status,
        [string]$Row.reservation_id,[string]$Row.token_id,[string]$Row.permit_nonce,[string]$Row.permit_hmac_sha256,
        [string]$Row.name,[string]$Row.source_identity,[string]$Row.github_repo_id,[string]$Row.surface_kind,
        [string]$Row.current_tree_sha256,[string]$Row.remote_tree_sha256,[string]$Row.remote_commit_sha,
        [string]$Row.current_eligibility_fingerprint,[string]$Row.live_attested_qualification_fingerprint,[string]$Row.admission_fingerprint,
        [string]$Row.reservation_state_revision,[string]$Row.reservation_state_revision_before,[string]$Row.reservation_state_revision_after,
        [string]$Row.permit_issued_at,[string]$Row.permit_expires_at,[string]$Row.reserved_at,[string]$Row.consumed_at,
        [string]$Row.state_revision_before,[string]$Row.state_revision_after,[string]$Row.single_use,[string]$Row.consumption_is_authority,
        [string]$Row.requires_persisted_consumption_before_executor,[string]$Row.requires_fresh_permit_revalidation_at_executor_start,
        [string]$Row.requires_fresh_revalidation_after_stage,[string]$Row.requires_fresh_revalidation_before_apply
    ) -join "`n"
}

function Test-CustomAppProductionExecutorConsumptionStateV010 {
    param([AllowNull()]$State)
    if($null -eq $State){return [pscustomobject]@{ok=$false;reason='consumption-state-null'}}
    if([int]$State.schema -ne $CustomAppProductionExecutorConsumptionStateSchema -or [string]$State.managed_by -cne $CustomAppProductionExecutorConsumptionStateManagedBy){return [pscustomobject]@{ok=$false;reason='consumption-state-owner-or-schema-mismatch'}}
    $authority=Test-CustomAppProductionExecutorConsumptionDeniedAuthorityV010 -Object $State -Label 'consumption-state'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason}}
    if(-not [bool]$State.append_only -or -not [bool]$State.requires_atomic_compare_and_swap_persistence -or -not [bool]$State.requires_persisted_consumption_before_executor){return [pscustomobject]@{ok=$false;reason='consumption-state-persistence-contract-invalid'}}
    try{$revision=[int64]$State.revision}catch{return [pscustomobject]@{ok=$false;reason='consumption-state-revision-invalid'}}
    if($revision -lt 0){return [pscustomobject]@{ok=$false;reason='consumption-state-revision-invalid'}}
    $rows=@($State.consumptions)
    if($rows.Count -ne $revision){return [pscustomobject]@{ok=$false;reason='consumption-state-revision-count-mismatch'}}
    $reservations=@{};$tokens=@{};$nonces=@{};$ids=@{};$expectedBefore=[int64]0
    foreach($row in $rows){
        if($null -eq $row -or [int]$row.schema -ne 1 -or [string]$row.managed_by -cne $CustomAppProductionExecutorConsumptionRowManagedBy -or [string]$row.qualified_reservation_head -cne $CustomAppProductionExecutorConsumptionQualifiedReservationHead -or [string]$row.status -cne 'executor-consumption-recorded'){return [pscustomobject]@{ok=$false;reason='consumption-row-owner-schema-parent-or-status-invalid'}}
        $rowAuthority=Test-CustomAppProductionExecutorConsumptionDeniedAuthorityV010 -Object $row -Label 'consumption-row'
        if(-not [bool]$rowAuthority.ok){return [pscustomobject]@{ok=$false;reason=[string]$rowAuthority.reason}}
        if(-not [bool]$row.single_use -or [bool]$row.consumption_is_authority -or -not [bool]$row.requires_persisted_consumption_before_executor -or -not [bool]$row.requires_fresh_permit_revalidation_at_executor_start -or -not [bool]$row.requires_fresh_revalidation_after_stage -or -not [bool]$row.requires_fresh_revalidation_before_apply){return [pscustomobject]@{ok=$false;reason='consumption-row-executor-contract-invalid'}}
        foreach($field in @('consumption_id','reservation_id','token_id','permit_hmac_sha256','current_tree_sha256','remote_tree_sha256','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint')){if(-not (Test-CustomAppProductionExecutorConsumptionSha256V010 (([string]$row.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('consumption-row-invalid-'+$field)}}}
        if(-not (Test-CustomAppProductionExecutorConsumptionNonceV010 ([string]$row.permit_nonce))){return [pscustomobject]@{ok=$false;reason='consumption-row-invalid-permit-nonce'}}
        if(-not (Test-CustomAppProductionExecutorConsumptionCommitV010 ([string]$row.remote_commit_sha))){return [pscustomobject]@{ok=$false;reason='consumption-row-invalid-remote-commit'}}
        try{$reservationRevision=[int64]$row.reservation_state_revision;$reservationBefore=[int64]$row.reservation_state_revision_before;$reservationAfter=[int64]$row.reservation_state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='consumption-row-reservation-revision-invalid'}}
        if($reservationRevision -lt 1 -or $reservationAfter -ne $reservationRevision -or $reservationBefore -ne ($reservationAfter-1)){return [pscustomobject]@{ok=$false;reason='consumption-row-reservation-revision-invalid'}}
        $reservationKey=([string]$row.reservation_id).Trim().ToLowerInvariant();$tokenKey=([string]$row.token_id).Trim().ToLowerInvariant();$nonceKey=([string]$row.permit_nonce).Trim().ToLowerInvariant();$idKey=([string]$row.consumption_id).Trim().ToLowerInvariant()
        if($reservations.ContainsKey($reservationKey)){return [pscustomobject]@{ok=$false;reason='consumption-state-duplicate-reservation'}};$reservations[$reservationKey]=$true
        if($tokens.ContainsKey($tokenKey)){return [pscustomobject]@{ok=$false;reason='consumption-state-duplicate-token'}};$tokens[$tokenKey]=$true
        if($nonces.ContainsKey($nonceKey)){return [pscustomobject]@{ok=$false;reason='consumption-state-duplicate-nonce'}};$nonces[$nonceKey]=$true
        if($ids.ContainsKey($idKey)){return [pscustomobject]@{ok=$false;reason='consumption-state-duplicate-consumption-id'}};$ids[$idKey]=$true
        try{$before=[int64]$row.state_revision_before;$after=[int64]$row.state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='consumption-row-revision-invalid'}}
        if($before -ne $expectedBefore -or $after -ne ($before+1)){return [pscustomobject]@{ok=$false;reason='consumption-row-revision-chain-invalid'}}
        $expectedId=Get-CustomAppProductionExecutorConsumptionSha256V010 -Text (Get-CustomAppProductionExecutorConsumptionMaterialV010 -Row $row)
        if(([string]$row.consumption_id).Trim().ToLowerInvariant() -cne $expectedId){return [pscustomobject]@{ok=$false;reason='consumption-row-id-mismatch'}}
        $expectedBefore=$after
    }
    return [pscustomobject]@{ok=$true;reason='consumption-state-valid';revision=$revision;reservation_ids=@($reservations.Keys);token_ids=@($tokens.Keys);nonces=@($nonces.Keys)}
}

function Test-CustomAppProductionReservationPermitContinuityV010 {
    param([AllowNull()]$ReservationRow,[AllowNull()]$Permit)
    if($null -eq $ReservationRow -or $null -eq $Permit){return [pscustomobject]@{ok=$false;reason='reservation-permit-null'}}
    $pairs=@(
        @('token_id','token_id'),@('permit_nonce','nonce'),@('permit_hmac_sha256','hmac_sha256'),@('name','name'),@('source_identity','source_identity'),
        @('surface_kind','surface_kind'),@('current_tree_sha256','current_tree_sha256'),@('remote_tree_sha256','remote_tree_sha256'),@('remote_commit_sha','remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','admission_fingerprint'),
        @('permit_issued_at','issued_at'),@('permit_expires_at','expires_at')
    )
    foreach($pair in $pairs){$left=([string]$ReservationRow.($pair[0])).Trim().ToLowerInvariant();$right=([string]$Permit.($pair[1])).Trim().ToLowerInvariant();if($left -cne $right){return [pscustomobject]@{ok=$false;reason=('reservation-permit-mismatch-'+$pair[0])}}}
    try{if([int64]$ReservationRow.github_repo_id -ne [int64]$Permit.github_repo_id){return [pscustomobject]@{ok=$false;reason='reservation-permit-mismatch-github_repo_id'}}}catch{return [pscustomobject]@{ok=$false;reason='reservation-permit-github_repo_id-invalid'}}
    return [pscustomobject]@{ok=$true;reason='reservation-permit-continuity-valid'}
}

function Invoke-CustomAppProductionExecutorConsumptionV010 {
    param(
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$ReservationId,[Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)]$ReservationState,[Parameter(Mandatory=$true)][int64]$ExpectedReservationRevision,
        [Parameter(Mandatory=$true)]$ConsumptionState,[Parameter(Mandatory=$true)][int64]$ExpectedConsumptionRevision,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[AllowNull()]$State=$ConsumptionState)[pscustomobject]@{ok=$false;reason=$Reason;next_state=$State;consumption_created=$false;executor_handoff_recorded=$false;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}

    $reservationCheck=Test-CustomAppProductionPermitReservationStateV010 -State $ReservationState
    if(-not [bool]$reservationCheck.ok){return & $deny ('reservation-state-invalid:'+[string]$reservationCheck.reason)}
    if($ExpectedReservationRevision -ne [int64]$reservationCheck.revision){return & $deny 'reservation-state-revision-conflict'}
    $reservationKey=([string]$ReservationId).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionExecutorConsumptionSha256V010 $reservationKey)){return & $deny 'reservation-id-invalid'}
    $matches=@($ReservationState.reservations|Where-Object{([string]$_.reservation_id).Trim().ToLowerInvariant() -ceq $reservationKey})
    if($matches.Count -ne 1){return & $deny 'reservation-not-found-or-ambiguous'}
    $reservation=$matches[0]

    $verified=Test-CustomAppProductionPermitV010 -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if(-not [bool]$verified.ok){return & $deny ('permit-revalidation-denied:'+[string]$verified.reason)}
    $continuity=Test-CustomAppProductionReservationPermitContinuityV010 -ReservationRow $reservation -Permit $Permit
    if(-not [bool]$continuity.ok){return & $deny ([string]$continuity.reason)}

    $consumptionCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $ConsumptionState
    if(-not [bool]$consumptionCheck.ok){return & $deny ([string]$consumptionCheck.reason)}
    if($ExpectedConsumptionRevision -ne [int64]$consumptionCheck.revision){return & $deny 'consumption-state-revision-conflict'}
    $token=([string]$Permit.token_id).Trim().ToLowerInvariant();$nonce=([string]$Permit.nonce).Trim().ToLowerInvariant()
    foreach($row in @($ConsumptionState.consumptions)){
        if(([string]$row.reservation_id).Trim().ToLowerInvariant() -ceq $reservationKey){return & $deny 'reservation-already-consumed'}
        if(([string]$row.token_id).Trim().ToLowerInvariant() -ceq $token){return & $deny 'permit-token-already-consumed'}
        if(([string]$row.permit_nonce).Trim().ToLowerInvariant() -ceq $nonce){return & $deny 'permit-nonce-already-consumed'}
    }

    $before=[int64]$consumptionCheck.revision;$after=$before+1
    $row=[pscustomobject]@{
        schema=1;managed_by=$CustomAppProductionExecutorConsumptionRowManagedBy;qualified_reservation_head=$CustomAppProductionExecutorConsumptionQualifiedReservationHead;status='executor-consumption-recorded'
        consumption_id=$null;reservation_id=$reservationKey;token_id=$token;permit_nonce=$nonce;permit_hmac_sha256=([string]$Permit.hmac_sha256).Trim().ToLowerInvariant()
        name=[string]$Permit.name;source_identity=([string]$Permit.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$Permit.github_repo_id;surface_kind=([string]$Permit.surface_kind).Trim().ToLowerInvariant()
        current_tree_sha256=([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant()
        current_eligibility_fingerprint=([string]$Permit.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$Permit.live_attested_qualification_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$Permit.admission_fingerprint).Trim().ToLowerInvariant()
        reservation_state_revision=[int64]$reservationCheck.revision;reservation_state_revision_before=[int64]$reservation.state_revision_before;reservation_state_revision_after=[int64]$reservation.state_revision_after
        permit_issued_at=[string]$Permit.issued_at;permit_expires_at=[string]$Permit.expires_at;reserved_at=[string]$reservation.reserved_at;consumed_at=$Now.ToUniversalTime().ToString('o')
        state_revision_before=$before;state_revision_after=$after;single_use=$true;consumption_is_authority=$false
        requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $row.consumption_id=Get-CustomAppProductionExecutorConsumptionSha256V010 -Text (Get-CustomAppProductionExecutorConsumptionMaterialV010 -Row $row)
    $nextRows=@();foreach($existing in @($ConsumptionState.consumptions)){$nextRows += $existing};$nextRows += $row
    $next=[pscustomobject]@{
        schema=$CustomAppProductionExecutorConsumptionStateSchema;managed_by=$CustomAppProductionExecutorConsumptionStateManagedBy;revision=$after;consumptions=@($nextRows)
        append_only=$true;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $nextCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $next
    if(-not [bool]$nextCheck.ok){return & $deny ('consumption-next-state-invalid:'+[string]$nextCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='production-reservation-consumption-recorded-persist-before-executor';next_state=$next;consumption_created=$true;consumption_id=[string]$row.consumption_id;reservation_id=$reservationKey;token_id=$token
        state_revision_before=$before;state_revision_after=$after;executor_handoff_recorded=$true;requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
