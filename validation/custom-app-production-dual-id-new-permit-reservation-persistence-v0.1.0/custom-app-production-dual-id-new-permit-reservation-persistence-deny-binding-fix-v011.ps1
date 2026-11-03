$CustomAppProductionDualIdNewPermitReservationPersistenceDenyBindingFixSchema = 1
$CustomAppProductionDualIdNewPermitReservationPersistenceDenyBindingFixManagedBy = 'custom-app-production-dual-id-new-permit-reservation-persistence-deny-binding-fix-v1.1'
$CustomAppProductionDualIdNewPermitReservationPersistenceDenyBindingFixQualifiedHead = 'a0644906a954dd0f487d1177a3ab0fe4b01d3f9a'
$CustomAppProductionDualIdNewPermitReservationPersistenceDenyBindingFixQualifiedCoreBlob = '629c09384ac13d2fe148566deffcc413f91cdc5d'

# PowerShell 5.1 can bind adjacent positional expressions such as
#   & $deny('reason')$true $envelope
# ambiguously.  This exact-function overlay keeps the validated persistence
# algorithm unchanged while making every deny call use explicit named
# parameters.  The parent core blob above remains immutable and separately
# pinned by CI.
function Save-CustomAppProductionDualIdNewPermitReservationStateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory,
        [Parameter(Mandatory=$true)]$NextState,
        [Parameter(Mandatory=$true)]$ReservationReceipt,
        [Parameter(Mandatory=$true)][int64]$ExpectedCurrentRevision,
        [Parameter(Mandatory=$true)][string]$PersistenceAdmissionFingerprint,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={
        param([string]$Reason,[bool]$Persisted=$false,[AllowNull()]$Envelope=$null)
        [pscustomobject]@{
            ok=$false;reason=$Reason;persisted=$Persisted;read_after_write_verified=$false;write_performed=$false
            recovered_existing_persistence=$false;repaired_current_pointer=$false;envelope=$Envelope
            persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }
    try {
        $paths=Get-CustomAppProductionDualIdNewPermitReservationPersistencePathsV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory
    } catch {
        return (& $deny -Reason ('dual-id-reservation-persistence-path-denied:'+[string]$_.Exception.Message))
    }
    $lock=$null
    try {
        try {
            $lock=Open-CustomAppProductionDualIdNewPermitReservationPersistenceLockV010 -Paths $paths
        } catch {
            return (& $deny -Reason ([string]$_.Exception.Message))
        }
        try {
            $current=Read-CustomAppProductionDualIdNewPermitReservationStoreUnlockedV010 -Paths $paths -AllowRecoverableCurrentLag $true
        } catch {
            return (& $deny -Reason ('dual-id-reservation-persistence-read-denied:'+[string]$_.Exception.Message))
        }

        $targetCheck=Test-CustomAppProductionPermitReservationStateV010 -State $NextState
        if(-not[bool]$targetCheck.ok){
            return (& $deny -Reason ('dual-id-reservation-persistence-next-state-invalid:'+[string]$targetCheck.reason))
        }
        $targetLast=@($NextState.reservations)[-1]

        if([int64]$current.revision -eq [int64]$NextState.revision){
            $currentJson=Get-CustomAppProductionDualIdNewPermitReservationPersistenceStateJsonV010 -State $current.state
            $targetJson=Get-CustomAppProductionDualIdNewPermitReservationPersistenceStateJsonV010 -State $NextState
            if($currentJson -cne $targetJson -or $null -eq $current.envelope -or ([string]$current.envelope.reservation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$ReservationReceipt.reservation_fingerprint).Trim().ToLowerInvariant()){
                return (& $deny -Reason 'dual-id-reservation-persistence-existing-revision-conflict')
            }
            $repaired=$false
            if([string]$current.current_status -cne 'matches-latest'){
                try {
                    Repair-CustomAppProductionDualIdNewPermitReservationCurrentV010 -Paths $paths -Envelope $current.envelope
                    $repaired=$true
                } catch {
                    return (& $deny -Reason ('dual-id-reservation-persistence-current-repair-failed:'+[string]$_.Exception.Message) -Persisted $true -Envelope $current.envelope)
                }
            }
            try {
                $verify=Read-CustomAppProductionDualIdNewPermitReservationStoreUnlockedV010 -Paths $paths
            } catch {
                return (& $deny -Reason ('dual-id-reservation-persistence-recovery-readback-denied:'+[string]$_.Exception.Message) -Persisted $true -Envelope $current.envelope)
            }
            return [pscustomobject]@{
                ok=$true;reason='dual-id-reservation-state-already-durably-persisted-and-reloaded';persisted=$true;read_after_write_verified=$true
                write_performed=$false;recovered_existing_persistence=$true;repaired_current_pointer=$repaired;revision=[int64]$verify.revision
                state=$verify.state;envelope=$verify.envelope;reservation_id=[string]$targetLast.reservation_id;reloaded_from_persistent_store=$true
                persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
            }
        }

        if([int64]$current.revision -ne $ExpectedCurrentRevision){
            return (& $deny -Reason 'dual-id-reservation-persistence-revision-conflict')
        }
        if([string]$current.current_status -cne 'matches-latest' -and [int64]$current.revision -gt 0){
            return (& $deny -Reason 'dual-id-reservation-persistence-current-lag-not-target-recovery')
        }
        $extend=Test-CustomAppProductionDualIdNewPermitReservationStateExtendsExactlyOneV010 -Current $current.state -Next $NextState
        if(-not[bool]$extend.ok){
            return (& $deny -Reason ([string]$extend.reason))
        }
        $previous=if($null -eq $current.envelope){$CustomAppProductionDualIdNewPermitReservationPersistenceZeroHash}else{([string]$current.envelope.envelope_sha256).Trim().ToLowerInvariant()}
        try {
            $e=New-CustomAppProductionDualIdNewPermitReservationPersistenceEnvelopeV010 -State $NextState -ReservationReceipt $ReservationReceipt -PreviousEnvelopeSha256 $previous -PersistenceAdmissionFingerprint $PersistenceAdmissionFingerprint -WrittenAt $Now
        } catch {
            return (& $deny -Reason ('dual-id-reservation-persistence-envelope-create-failed:'+[string]$_.Exception.Message))
        }
        $json=$e|ConvertTo-Json -Depth 100 -Compress
        $historyPath=Join-Path ([string]$paths.history)('{0:D20}-{1}.json' -f [int64]$e.revision,[string]$e.envelope_sha256)
        try {
            Write-CustomAppProductionDualIdNewPermitReservationDurableFileV010 -Path $historyPath -Text $json -Mode ([IO.FileMode]::CreateNew)
        } catch {
            return (& $deny -Reason ('dual-id-reservation-persistence-history-create-failed:'+[string]$_.Exception.Message))
        }
        if($FailurePoint -ceq 'after-history-before-current'){
            return (& $deny -Reason 'simulated-crash-after-history-before-current' -Persisted $true -Envelope $e)
        }
        try {
            Repair-CustomAppProductionDualIdNewPermitReservationCurrentV010 -Paths $paths -Envelope $e
        } catch {
            return (& $deny -Reason ('dual-id-reservation-persistence-current-write-failed:'+[string]$_.Exception.Message) -Persisted $true -Envelope $e)
        }
        try {
            $verify=Read-CustomAppProductionDualIdNewPermitReservationStoreUnlockedV010 -Paths $paths
        } catch {
            return (& $deny -Reason ('dual-id-reservation-persistence-readback-denied:'+[string]$_.Exception.Message) -Persisted $true -Envelope $e)
        }
        if([int64]$verify.revision -ne [int64]$NextState.revision -or ([string]$verify.envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$e.envelope_sha256).Trim().ToLowerInvariant()){
            return (& $deny -Reason 'dual-id-reservation-persistence-readback-mismatch' -Persisted $true -Envelope $e)
        }
        return [pscustomobject]@{
            ok=$true;reason='dual-id-reservation-state-durably-persisted-and-readback-verified';persisted=$true;read_after_write_verified=$true
            write_performed=$true;recovered_existing_persistence=$false;repaired_current_pointer=$false;revision=[int64]$verify.revision
            state=$verify.state;envelope=$verify.envelope;reservation_id=[string]$targetLast.reservation_id;reloaded_from_persistent_store=$true
            persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false
        }
    } finally {
        if($null -ne $lock){$lock.Dispose()}
    }
}
