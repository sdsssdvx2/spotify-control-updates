$CustomAppProductionRecoveryAwarePermitConsumptionSchema = 1
$CustomAppProductionRecoveryAwarePermitConsumptionManagedBy = 'custom-app-production-recovery-aware-permit-consumption-v1'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceHead = '5ec59cf7ca2a3c0e3ebded2614bfe567cfd02490'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceCoreBlob = '2830a3cd6d69fee378a15505251bd92d4d91f944'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionHead = 'ed7fa27fc9bfaa78858e130743a2de508a3c0bf9'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionCoreBlob = 'ac1459254ce060806a338a443c755bbc9f65c9a2'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'

function Get-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function New-CustomAppProductionRecoveryAwarePermitConsumptionDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()]$OriginalConsumptionState=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;next_state=$OriginalConsumptionState
        reservation_persistence_attested=$false;historical_reservation_envelope_attested=$false;fresh_recovery_admission_revalidated=$false
        consumption_created=$false;single_use_consumption_candidate_created=$false;consumption_persisted=$false;session_key_accepted=$false;session_key_persisted=$false;session_key_exposed=$false
        requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceContinuityV010 {
    param([AllowNull()]$PersistenceReceipt,[AllowNull()]$Envelope)
    if($null -eq $PersistenceReceipt -or $null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-continuity-null'}}
    $envelopeCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 -Envelope $Envelope
    if(-not [bool]$envelopeCheck.ok){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-historical-envelope-invalid:'+[string]$envelopeCheck.reason)}}
    try{$receiptRevision=[int64]$PersistenceReceipt.persisted_revision;$envelopeRevision=[int64]$Envelope.revision}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-revision-invalid'}}
    if($receiptRevision -ne $envelopeRevision){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-revision-mismatch'}}
    foreach($pair in @(
        @('reservation_id','reservation_id'),
        @('reservation_fingerprint','reservation_fingerprint'),
        @('persistence_envelope_sha256','envelope_sha256')
    )){
        $a=([string]$PersistenceReceipt.($pair[0])).Trim().ToLowerInvariant();$b=([string]$Envelope.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-'+$pair[0]+'-mismatch')}}
    }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-consumption-persistence-continuity-exact';revision=$receiptRevision}
}

function Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedReservationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory,
        [Parameter(Mandatory=$true)]$PersistenceReceipt
    )
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $PersistenceReceipt
    if(-not [bool]$receiptCheck.ok){throw ('recovery-aware-consumption-persistence-receipt-invalid:'+[string]$receiptCheck.reason)}
    $paths=Get-CustomAppProductionRecoveryAwarePermitReservationPersistencePathsV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory
    if(-not (Test-Path -LiteralPath ([string]$paths.lock) -PathType Leaf)){throw 'recovery-aware-consumption-reservation-lock-missing'}
    $lock=$null
    try{
        try{$lock=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}catch{throw 'recovery-aware-consumption-reservation-store-lock-busy'}
        $store=Read-CustomAppProductionRecoveryAwarePermitReservationStoreUnlockedV010 -Paths $paths
        if($null -eq $store -or -not [bool]$store.ok){throw 'recovery-aware-consumption-reservation-store-invalid'}
        $revision=[int64]$PersistenceReceipt.persisted_revision
        if($revision -lt 1 -or [int64]$store.revision -lt $revision){throw 'recovery-aware-consumption-persisted-revision-not-present'}
        $pattern=('{0:D20}-*.json' -f $revision)
        $matches=@(Get-ChildItem -LiteralPath ([string]$paths.history) -File -Filter $pattern -Force)
        if($matches.Count -ne 1){throw 'recovery-aware-consumption-historical-envelope-not-unique'}
        $historical=(ConvertFrom-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeFileV010 -Path $matches[0].FullName).envelope
        $continuity=Test-CustomAppProductionRecoveryAwarePermitConsumptionPersistenceContinuityV010 -PersistenceReceipt $PersistenceReceipt -Envelope $historical
        if(-not [bool]$continuity.ok){throw [string]$continuity.reason}
        $historicalRows=@($historical.state.reservations)
        $currentRows=@($store.state.reservations)
        if($historicalRows.Count -ne $revision -or $currentRows.Count -lt $revision){throw 'recovery-aware-consumption-reservation-row-count-invalid'}
        $historicalRow=$historicalRows[$revision-1]
        $currentRow=$currentRows[$revision-1]
        if(($historicalRow|ConvertTo-Json -Depth 60 -Compress) -cne ($currentRow|ConvertTo-Json -Depth 60 -Compress)){throw 'recovery-aware-consumption-historical-reservation-rewritten'}
        if(([string]$historicalRow.reservation_id).Trim().ToLowerInvariant() -cne ([string]$PersistenceReceipt.reservation_id).Trim().ToLowerInvariant()){throw 'recovery-aware-consumption-historical-reservation-id-mismatch'}
        return [pscustomobject]@{
            ok=$true;reason='recovery-aware-consumption-durable-reservation-attested'
            persisted_revision=$revision;current_revision=[int64]$store.revision;reservation=$historicalRow;historical_envelope=$historical
            state=$store.state;current_envelope=$store.envelope;history_count=[int]$store.history_count
            reservation_persistence_attested=$true;historical_reservation_envelope_attested=$true
            persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        }
    } finally {if($null -ne $lock){$lock.Dispose()}}
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionAdmissionContinuityV010 {
    param([AllowNull()]$PersistenceReceipt,[AllowNull()]$ReservationRow,[AllowNull()]$FreshAdmission)
    if($null -eq $PersistenceReceipt -or $null -eq $ReservationRow -or $null -eq $FreshAdmission){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-admission-continuity-null'}}
    foreach($pair in @(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind')
    )){
        $a=([string]$PersistenceReceipt.($pair[0])).Trim().ToLowerInvariant();$b=([string]$FreshAdmission.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-persistence-fresh-'+$pair[0]+'-mismatch')}}
    }
    foreach($pair in @(
        @('name','name'),@('source_identity','source_identity'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('current_tree_sha256','stable_live_tree_sha256'),@('remote_tree_sha256','current_remote_tree_sha256'),@('remote_commit_sha','current_remote_commit_sha'),
        @('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint'),@('admission_fingerprint','live_admission_fingerprint')
    )){
        $a=([string]$ReservationRow.($pair[0])).Trim().ToLowerInvariant();$b=([string]$FreshAdmission.($pair[1])).Trim().ToLowerInvariant()
        if($a -cne $b){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-reservation-fresh-'+$pair[0]+'-mismatch')}}
    }
    if(([string]$PersistenceReceipt.reservation_id).Trim().ToLowerInvariant() -cne ([string]$ReservationRow.reservation_id).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-persistence-reservation-id-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-consumption-fresh-admission-continuity-exact'}
}

function Get-CustomAppProductionRecoveryAwarePermitConsumptionReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,
        [string]$Receipt.qualified_reservation_persistence_head,[string]$Receipt.qualified_reservation_persistence_core_blob,
        [string]$Receipt.qualified_executor_consumption_head,[string]$Receipt.qualified_executor_consumption_core_blob,
        [string]$Receipt.qualified_issuance_admission_head,[string]$Receipt.qualified_issuance_admission_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,
        [string]$Receipt.reservation_id,[string]$Receipt.reservation_fingerprint,[string]$Receipt.reservation_persistence_envelope_sha256,[string]$Receipt.persisted_reservation_revision,[string]$Receipt.current_reservation_store_revision,
        [string]$Receipt.permit_token_id,[string]$Receipt.permit_nonce,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.permit_issued_at,[string]$Receipt.permit_expires_at,
        [string]$Receipt.current_tree_sha256,[string]$Receipt.remote_tree_sha256,[string]$Receipt.remote_commit_sha,[string]$Receipt.current_eligibility_fingerprint,[string]$Receipt.live_attested_qualification_fingerprint,[string]$Receipt.admission_fingerprint,
        [string]$Receipt.pre_consume_issuance_admission_fingerprint,[string]$Receipt.post_consume_issuance_admission_fingerprint,
        [string]$Receipt.consumption_id,[string]$Receipt.consumption_state_revision_before,[string]$Receipt.consumption_state_revision_after,
        [string]$Receipt.reservation_persistence_attested,[string]$Receipt.historical_reservation_envelope_attested,[string]$Receipt.fresh_recovery_admission_revalidated,
        [string]$Receipt.single_use_consumption_candidate_created,[string]$Receipt.consumption_persisted,[string]$Receipt.session_key_accepted,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,
        [string]$Receipt.requires_atomic_compare_and_swap_persistence,[string]$Receipt.requires_persisted_consumption_before_executor,
        [string]$Receipt.requires_fresh_permit_revalidation_at_executor_start,[string]$Receipt.requires_fresh_revalidation_after_stage,[string]$Receipt.requires_fresh_revalidation_before_apply,
        [string]$Receipt.consumption_is_authority,[string]$Receipt.executor_may_start,[string]$Receipt.executor_may_stage,[string]$Receipt.executor_may_apply,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized,[string]$Receipt.checked_at
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_reservation_persistence_head','qualified_reservation_persistence_core_blob','qualified_executor_consumption_head','qualified_executor_consumption_core_blob','qualified_issuance_admission_head','qualified_issuance_admission_core_blob',
        'name','source_identity','transaction_id','github_repo_id','surface_kind','reservation_id','reservation_fingerprint','reservation_persistence_envelope_sha256','persisted_reservation_revision','current_reservation_store_revision',
        'permit_token_id','permit_nonce','permit_hmac_sha256','permit_issued_at','permit_expires_at','current_tree_sha256','remote_tree_sha256','remote_commit_sha','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint',
        'pre_consume_issuance_admission_fingerprint','post_consume_issuance_admission_fingerprint','consumption_id','consumption_state_revision_before','consumption_state_revision_after',
        'reservation_persistence_attested','historical_reservation_envelope_attested','fresh_recovery_admission_revalidated','single_use_consumption_candidate_created','consumption_persisted','session_key_accepted','session_key_persisted','session_key_exposed',
        'requires_atomic_compare_and_swap_persistence','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply',
        'consumption_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized','checked_at','consumption_fingerprint'
    )){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-receipt-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitConsumptionSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitConsumptionManagedBy){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-owner-schema-mismatch'}}
    if([string]$Receipt.qualified_reservation_persistence_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceHead -or [string]$Receipt.qualified_reservation_persistence_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceCoreBlob -or [string]$Receipt.qualified_executor_consumption_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionHead -or [string]$Receipt.qualified_executor_consumption_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionCoreBlob -or [string]$Receipt.qualified_issuance_admission_head -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionHead -or [string]$Receipt.qualified_issuance_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionCoreBlob){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-lineage-mismatch'}}
    foreach($f in @('transaction_id','reservation_id','reservation_fingerprint','reservation_persistence_envelope_sha256','permit_token_id','permit_hmac_sha256','current_tree_sha256','remote_tree_sha256','current_eligibility_fingerprint','live_attested_qualification_fingerprint','admission_fingerprint','pre_consume_issuance_admission_fingerprint','post_consume_issuance_admission_fingerprint','consumption_id','consumption_fingerprint')){if(-not (Test-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-receipt-invalid-'+$f)}}}
    if([string]$Receipt.permit_nonce -notmatch '^[0-9a-f]{32}$' -or [string]$Receipt.remote_commit_sha -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-nonce-or-commit-invalid'}}
    foreach($f in @('reservation_persistence_attested','historical_reservation_envelope_attested','fresh_recovery_admission_revalidated','single_use_consumption_candidate_created','session_key_accepted','requires_atomic_compare_and_swap_persistence','requires_persisted_consumption_before_executor','requires_fresh_permit_revalidation_at_executor_start','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply')){if(-not [bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-receipt-required-flag-false-'+$f)}}}
    foreach($f in @('consumption_persisted','session_key_persisted','session_key_exposed','consumption_is_authority','executor_may_start','executor_may_stage','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-aware-consumption-receipt-authority-or-persistence-escaped-'+$f)}}}
    try{$persisted=[int64]$Receipt.persisted_reservation_revision;$current=[int64]$Receipt.current_reservation_store_revision;$before=[int64]$Receipt.consumption_state_revision_before;$after=[int64]$Receipt.consumption_state_revision_after}catch{return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-revision-invalid'}}
    if($persisted -lt 1 -or $current -lt $persisted -or $before -lt 0 -or $after -ne ($before+1)){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-revision-chain-invalid'}}
    if(([string]$Receipt.pre_consume_issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_consume_issuance_admission_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-admission-drift'}}
    $checked=[DateTimeOffset]::MinValue;$issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Receipt.checked_at,[ref]$checked) -or -not [DateTimeOffset]::TryParse([string]$Receipt.permit_issued_at,[ref]$issued) -or -not [DateTimeOffset]::TryParse([string]$Receipt.permit_expires_at,[ref]$expires)){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-time-invalid'}}
    if($expires -le $issued -or $checked -ge $expires){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-permit-expired-or-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionReceiptMaterialV010 -Receipt $Receipt)
    if(([string]$Receipt.consumption_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-aware-consumption-receipt-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-single-use-consumption-candidate-valid-zero-authority';consumption_id=([string]$Receipt.consumption_id).Trim().ToLowerInvariant();requires_persisted_consumption_before_executor=$true;executor_may_start=$false;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitConsumptionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$ReservationPersistenceStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)]$ReservationPersistenceResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)]$ConsumptionState,[Parameter(Mandatory=$true)][int64]$ExpectedConsumptionRevision,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason) New-CustomAppProductionRecoveryAwarePermitConsumptionDeniedV010 -Reason $Reason -OriginalConsumptionState $ConsumptionState}
    if($SessionKey.Length -lt 32){return & $deny 'recovery-aware-consumption-session-key-too-short'}
    if($null -eq $ReservationPersistenceResult -or -not [bool]$ReservationPersistenceResult.ok -or $null -eq $ReservationPersistenceResult.receipt){return & $deny 'recovery-aware-consumption-persistence-result-invalid'}
    $pr=$ReservationPersistenceResult.receipt
    $prCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $pr
    if(-not [bool]$prCheck.ok){return & $deny ('recovery-aware-consumption-persistence-receipt-invalid:'+[string]$prCheck.reason)}
    $nameKey=$Name.Trim().ToLowerInvariant();$tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey) -or ([string]$pr.name).Trim().ToLowerInvariant() -cne $nameKey){return & $deny 'recovery-aware-consumption-name-mismatch'}
    if(-not (Test-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 $tx) -or ([string]$pr.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-aware-consumption-transaction-mismatch'}
    try{$persisted=Get-CustomAppProductionRecoveryAwarePermitConsumptionPersistedReservationV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $ReservationPersistenceStoreDirectory -PersistenceReceipt $pr}catch{return & $deny ('recovery-aware-consumption-durable-reservation-denied:'+[string]$_.Exception.Message)}
    $reservation=$persisted.reservation
    $pre=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $pre -or -not [bool]$pre.ok){return & $deny ('recovery-aware-consumption-pre-admission-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if(-not [bool]$preCheck.ok){return & $deny ('recovery-aware-consumption-pre-admission-invalid:'+[string]$preCheck.reason)}
    $preContinuity=Test-CustomAppProductionRecoveryAwarePermitConsumptionAdmissionContinuityV010 -PersistenceReceipt $pr -ReservationRow $reservation -FreshAdmission $pre.receipt
    if(-not [bool]$preContinuity.ok){return & $deny ([string]$preContinuity.reason)}
    $permitCheck=Test-CustomAppProductionPermitV010 -Permit $Permit -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if(-not [bool]$permitCheck.ok){return & $deny ('recovery-aware-consumption-permit-invalid:'+[string]$permitCheck.reason)}
    $permitContinuity=Test-CustomAppProductionReservationPermitContinuityV010 -ReservationRow $reservation -Permit $Permit
    if(-not [bool]$permitContinuity.ok){return & $deny ('recovery-aware-consumption-'+[string]$permitContinuity.reason)}
    $consumed=Invoke-CustomAppProductionExecutorConsumptionV010 -Permit $Permit -ReservationId ([string]$pr.reservation_id) -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -ReservationState $persisted.state -ExpectedReservationRevision ([int64]$persisted.current_revision) -ConsumptionState $ConsumptionState -ExpectedConsumptionRevision $ExpectedConsumptionRevision -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $consumed -or -not [bool]$consumed.ok){return & $deny ('recovery-aware-consumption-core-denied:'+[string]$consumed.reason)}
    $post=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $nameKey -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $tx -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $post -or -not [bool]$post.ok){return & $deny ('recovery-aware-consumption-post-admission-denied:'+[string]$post.reason)}
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if(-not [bool]$postCheck.ok){return & $deny ('recovery-aware-consumption-post-admission-invalid:'+[string]$postCheck.reason)}
    $postContinuity=Test-CustomAppProductionRecoveryAwarePermitConsumptionAdmissionContinuityV010 -PersistenceReceipt $pr -ReservationRow $reservation -FreshAdmission $post.receipt
    if(-not [bool]$postContinuity.ok){return & $deny ('recovery-aware-consumption-post-'+[string]$postContinuity.reason)}
    if(([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-aware-consumption-admission-drift-during-consumption'}
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitConsumptionSchema;managed_by=$CustomAppProductionRecoveryAwarePermitConsumptionManagedBy
        qualified_reservation_persistence_head=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceHead;qualified_reservation_persistence_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedPersistenceCoreBlob
        qualified_executor_consumption_head=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionHead;qualified_executor_consumption_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedConsumptionCoreBlob
        qualified_issuance_admission_head=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionHead;qualified_issuance_admission_core_blob=$CustomAppProductionRecoveryAwarePermitConsumptionQualifiedAdmissionCoreBlob
        name=$nameKey;source_identity=([string]$pr.source_identity).Trim().ToLowerInvariant();transaction_id=$tx;github_repo_id=[int64]$pr.github_repo_id;surface_kind=([string]$pr.surface_kind).Trim().ToLowerInvariant()
        reservation_id=([string]$pr.reservation_id).Trim().ToLowerInvariant();reservation_fingerprint=([string]$pr.reservation_fingerprint).Trim().ToLowerInvariant();reservation_persistence_envelope_sha256=([string]$pr.persistence_envelope_sha256).Trim().ToLowerInvariant();persisted_reservation_revision=[int64]$persisted.persisted_revision;current_reservation_store_revision=[int64]$persisted.current_revision
        permit_token_id=([string]$Permit.token_id).Trim().ToLowerInvariant();permit_nonce=([string]$Permit.nonce).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$Permit.hmac_sha256).Trim().ToLowerInvariant();permit_issued_at=[string]$Permit.issued_at;permit_expires_at=[string]$Permit.expires_at
        current_tree_sha256=([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant();current_eligibility_fingerprint=([string]$Permit.current_eligibility_fingerprint).Trim().ToLowerInvariant();live_attested_qualification_fingerprint=([string]$Permit.live_attested_qualification_fingerprint).Trim().ToLowerInvariant();admission_fingerprint=([string]$Permit.admission_fingerprint).Trim().ToLowerInvariant()
        pre_consume_issuance_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_consume_issuance_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        consumption_id=([string]$consumed.consumption_id).Trim().ToLowerInvariant();consumption_state_revision_before=[int64]$consumed.state_revision_before;consumption_state_revision_after=[int64]$consumed.state_revision_after
        reservation_persistence_attested=$true;historical_reservation_envelope_attested=$true;fresh_recovery_admission_revalidated=$true;single_use_consumption_candidate_created=$true;consumption_persisted=$false;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true;requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        checked_at=$Now.ToUniversalTime().ToString('o');consumption_fingerprint=$null
    }
    $receipt.consumption_fingerprint=Get-CustomAppProductionRecoveryAwarePermitConsumptionSha256V010 (Get-CustomAppProductionRecoveryAwarePermitConsumptionReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitConsumptionReceiptV010 -Receipt $receipt
    if(-not [bool]$receiptCheck.ok){return & $deny ('recovery-aware-consumption-output-invalid:'+[string]$receiptCheck.reason)}
    return [pscustomobject]@{
        ok=$true;reason='recovery-aware-single-use-consumption-created-requires-atomic-persistence-before-executor';receipt=$receipt;next_state=$consumed.next_state
        reservation_persistence_attested=$true;historical_reservation_envelope_attested=$true;fresh_recovery_admission_revalidated=$true
        consumption_created=$true;single_use_consumption_candidate_created=$true;consumption_id=[string]$consumed.consumption_id;consumption_persisted=$false;session_key_accepted=$true;session_key_persisted=$false;session_key_exposed=$false
        requires_atomic_compare_and_swap_persistence=$true;requires_persisted_consumption_before_executor=$true
        requires_fresh_permit_revalidation_at_executor_start=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        consumption_is_authority=$false;executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
