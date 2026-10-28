$CustomAppProductionReservationStateSchema = 1
$CustomAppProductionReservationStateManagedBy = 'custom-app-production-permit-reservation-state-v1'
$CustomAppProductionReservationRowManagedBy = 'custom-app-production-permit-reservation-v1'
$CustomAppProductionReservationQualifiedPermitHead = 'd77f646d23652b0f066248230756d9e207a10fbd'

function Get-CustomAppProductionReservationSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionReservationSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionReservationNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}

function Test-CustomAppProductionReservationDeniedAuthorityV010 {
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

function New-CustomAppProductionPermitReservationStateV010 {
    return [pscustomobject]@{
        schema=$CustomAppProductionReservationStateSchema;managed_by=$CustomAppProductionReservationStateManagedBy;revision=[int64]0;reservations=@()
        append_only=$true;requires_atomic_compare_and_swap_persistence=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppProductionReservationMaterialV010 {
    param([Parameter(Mandatory=$true)]$Row)
    return @(
        [string]$Row.schema,[string]$Row.managed_by,[string]$Row.qualified_permit_head,[string]$Row.status,
        [string]$Row.token_id,[string]$Row.permit_nonce,[string]$Row.permit_hmac_sha256,
        [string]$Row.name,[string]$Row.source_identity,[string]$Row.github_repo_id,[string]$Row.surface_kind,
        [string]$Row.current_tree_sha256,[string]$Row.remote_tree_sha256,[string]$Row.remote_commit_sha,
        [string]$Row.current_eligibility_fingerprint,[string]$Row.live_attested_qualification_fingerprint,[string]$Row.admission_fingerprint,
        [string]$Row.permit_issued_at,[string]$Row.permit_expires_at,[string]$Row.reserved_at,
        [string]$Row.state_revision_before,[string]$Row.state_revision_after,[string]$Row.single_use,[string]$Row.reservation_is_authority
    ) -join "`n"
}

function Test-CustomAppProductionPermitReservationStateV010 {
    param([AllowNull()]$State)
    if($null -eq $State){return [pscustomobject]@{ok=$false;reason='reservation-state-null'}}
    if([int]$State.schema -ne $CustomAppProductionReservationStateSchema -or [string]$State.managed_by -cne $CustomAppProductionReservationStateManagedBy){return [pscustomobject]@{ok=$false;reason='reservation-state-owner-or-schema-mismatch'}}
    $authority=Test-CustomAppProductionReservationDeniedAuthorityV010 -Object $State -Label 'reservation-state'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason}}
    if(-not [bool]$State.append_only -or -not [bool]$State.requires_atomic_compare_and_swap_persistence){return [pscustomobject]@{ok=$false;reason='reservation-state-persistence-contract-invalid'}}
    try{$revision=[int64]$State.revision}catch{return [pscustomobject]@{ok=$false;reason='reservation-state-revision-invalid'}}
    if($revision -lt 0){return [pscustomobject]@{ok=$false;reason='reservation-state-revision-invalid'}}
    $rows=@($State.reservations)
    if($rows.Count -ne $revision){return [pscustomobject]@{ok=$false;reason='reservation-state-revision-count-mismatch'}}
    $tokens=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $nonces=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $expectedBefore=[int64]0
    foreach($row in $rows){
        if($null -eq $row -or [int]$row.schema -ne 1 -or [string]$row.managed_by -cne $CustomAppProductionReservationRowManagedBy -or [string]$row.qualified_permit_head -cne $CustomAppProductionReservationQualifiedPermitHead -or [string]$row.status -cne 'reserved'){return [pscustomobject]@{ok=$false;reason='reservation-row-owner-schema-parent-or-status-invalid'}}
        $rowAuthority=Test-CustomAppProductionReservationDeniedAuthorityV010 -Object $row -Label 'reservation-row'
        if(-not [bool]$rowAuthority.ok){return [pscustomobject]@{ok=$false;reason=[string]$rowAuthority.reason}}
        if(-not [bool]$row.single_use -or [bool]$row.reservation_is_authority -or -not [bool]$row.requires_atomic_persistence_before_executor){return [pscustomobject]@{ok=$false;reason='reservation-row-consumption-contract-invalid'}}
        foreach($field in @('reservation_id','token_id','permit_hmac_sha256','current_tree_sha256','remote_tree_sha256','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint')){if(-not (Test-CustomAppProductionReservationSha256V010 (([string]$row.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('reservation-row-invalid-'+$field)}}}
        if(-not (Test-CustomAppProductionReservationNonceV010 ([string]$row.permit_nonce)){return [pscustomobject]@{ok=$false;reason='reservation-row-invalid-permit-nonce'}}
        if(-not $tokens.Add(([string]$row.token_id).ToLowerInvariant())){return [pscustomobject]@{ok=$false;reason='reservation-state-duplicate-token'}}
        if(-not $nonces.Add(([string]$row.permit_nonce).ToLowerInvariant())){return [pscustomobject]@{ok=$false;reason='reservation-state-duplicate-nonce'}}
        if(-not $ids.Add(([string]$row.reservation_id).ToLowerInvariant())){return [pscustomobject]@{ok=$false;reason='reservation-state-duplicate-reservation-id'}}
        try{$before=[int64]$row.state_revision_before;$after=[int64]$row.state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='reservation-row-revision-invalid'}}
        if($before -ne $expectedBefore -or $after -ne ($before+1)){return [pscustomobject]@{ok=$false;reason='reservation-row-revision-chain-invalid'}}
        $material=Get-CustomAppProductionReservationMaterialV010 -Row $row;$expectedId=Get-CustomAppProductionReservationSha256V010 -Text $material
        if(([string]$row.reservation_id).Trim().ToLowerInvariant() -cne $expectedId){return [pscustomobject]@{ok=$false;reason='reservation-row-id-mismatch'}}
        $expectedBefore=$after
    }
    return [pscustomobject]@{ok=$true;reason='reservation-state-valid';revision=$revision;token_ids=@($tokens);nonces=@($nonces)}
}

function Invoke-CustomAppProductionPermitReservationV010 {
    param(
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)]$ReservationState,[Parameter(Mandatory=$true)][int64]$ExpectedRevision,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[AllowNull()]$State=$ReservationState)[pscustomobject]@{ok=$false;reason=$Reason;next_state=$State;reservation_created=$false;reservation_id=$null;requires_atomic_compare_and_swap_persistence=$true;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $stateCheck=Test-CustomAppProductionPermitReservationStateV010 -State $ReservationState
    if(-not [bool]$stateCheck.ok){return & $deny ([string]$stateCheck.reason)}
    if($ExpectedRevision -ne [int64]$stateCheck.revision){return & $deny 'reservation-state-revision-conflict'}
    $verified=Test-CustomAppProductionPermitV010 -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if(-not [bool]$verified.ok){return & $deny ([string]$verified.reason)}
    $token=([string]$Permit.token_id).Trim().ToLowerInvariant();$nonce=([string]$Permit.nonce).Trim().ToLowerInvariant()
    foreach($row in @($ReservationState.reservations)){
        if(([string]$row.token_id).Trim().ToLowerInvariant() -ceq $token){return & $deny 'permit-already-reserved-token'}
        if(([string]$row.permit_nonce).Trim().ToLowerInvariant() -ceq $nonce){return & $deny 'permit-already-reserved-nonce'}
    }
    $before=[int64]$stateCheck.revision;$after=$before+1
    $row=[pscustomobject]@{
        schema=1;managed_by=$CustomAppProductionReservationRowManagedBy;qualified_permit_head=$CustomAppProductionReservationQualifiedPermitHead;status='reserved'
        reservation_id=$null;token_id=$token;permit_nonce=$nonce;permit_hmac_sha256=([string]$Permit.hmac_sha256).Trim().ToLowerInvariant()
        name=[string]$Permit.name;source_identity=([string]$Permit.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$Permit.github_repo_id;surface_kind=([string]$Permit.surface_kind).Trim().ToLowerInvariant()
        current_tree_sha256=([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant()
        current_eligibility_fingerprint=([string]$Permit.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$Permit.live_attested_qualification_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$Permit.admission_fingerprint).Trim().ToLowerInvariant()
        permit_issued_at=[string]$Permit.issued_at;permit_expires_at=[string]$Permit.expires_at;reserved_at=$Now.ToUniversalTime().ToString('o');state_revision_before=$before;state_revision_after=$after
        single_use=$true;reservation_is_authority=$false;requires_atomic_persistence_before_executor=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $row.reservation_id=Get-CustomAppProductionReservationSha256V010 -Text (Get-CustomAppProductionReservationMaterialV010 -Row $row)
    $nextRows=New-Object System.Collections.Generic.List[object];foreach($existing in @($ReservationState.reservations)){$nextRows.Add($existing)};$nextRows.Add($row)
    $next=[pscustomobject]@{
        schema=$CustomAppProductionReservationStateSchema;managed_by=$CustomAppProductionReservationStateManagedBy;revision=$after;reservations=@($nextRows)
        append_only=$true;requires_atomic_compare_and_swap_persistence=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $nextCheck=Test-CustomAppProductionPermitReservationStateV010 -State $next
    if(-not [bool]$nextCheck.ok){return & $deny ('reservation-next-state-invalid:'+[string]$nextCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='production-permit-reserved-once';next_state=$next;reservation_created=$true;reservation_id=[string]$row.reservation_id;token_id=$token;state_revision_before=$before;state_revision_after=$after
        reservation_is_authority=$false;requires_atomic_compare_and_swap_persistence=$true;requires_atomic_persistence_before_executor=$true
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
