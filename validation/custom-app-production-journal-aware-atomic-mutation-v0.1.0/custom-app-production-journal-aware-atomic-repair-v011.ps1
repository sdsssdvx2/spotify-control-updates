$CustomAppProductionJournalAwareAtomicRepairV011ManagedBy = 'custom-app-production-journal-aware-atomic-repair-v1.1'
$CustomAppProductionJournalAwareAtomicRepairV011QualifiedCoreBlob = '79580da78443a18bd281d4fce61c4a57d958a196'
$CustomAppProductionJournalAwareAtomicRepairV011QualifiedJournalBlob = 'a3df7e5d89c594083c10e240e13029ca5640b8ae'

function Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,[Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedStageRuntimeTreeSha256,
        [Parameter(Mandatory=$true)][string]$ExpectedAppBackupTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedAppBackupFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedAppBackupTotalBytes,[Parameter(Mandatory=$true)][string]$ExpectedPersistenceFingerprint,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;repair_is_authority=$false;restore_authorized=$false;apply_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Name $Name -ExpectedLiveFullTreeSha256 $ExpectedLiveFullTreeSha256 -ExpectedLiveFullFileCount $ExpectedLiveFullFileCount -ExpectedLiveFullTotalBytes $ExpectedLiveFullTotalBytes -ExpectedStageRuntimeTreeSha256 $ExpectedStageRuntimeTreeSha256 -ExpectedAppBackupTreeSha256 $ExpectedAppBackupTreeSha256 -ExpectedAppBackupFileCount $ExpectedAppBackupFileCount -ExpectedAppBackupTotalBytes $ExpectedAppBackupTotalBytes -ExpectedPersistenceFingerprint $ExpectedPersistenceFingerprint -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if($null -eq $i -or -not [bool]$i.ok -or $null -eq $i.receipt){return & $deny ('journal-aware-atomic-starting-repair-inspection-denied:'+[string]$i.reason)}
    $r=$i.receipt

    # Fresh durable reread binds the timestamp clamp to the same CAS head that inspection attested.
    try{$head=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory}catch{return & $deny ('journal-aware-atomic-starting-repair-head-reread-failed:'+[string]$_.Exception.Message)}
    if($null -eq $head -or -not [bool]$head.ok -or -not [bool]$head.reloaded_from_persistent_store -or $null -eq $head.entry){return & $deny 'journal-aware-atomic-starting-repair-head-not-durable'}
    if(([string]$head.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant() -or [int64]$head.revision -ne [int64]$r.journal_revision -or ([string]$head.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$r.journal_entry_sha256).Trim().ToLowerInvariant()){return & $deny 'journal-aware-atomic-starting-repair-head-changed-after-inspection'}
    if([string]$head.entry.phase -cne 'atomic-mutation-starting'){return & $deny 'journal-aware-atomic-starting-repair-head-phase-changed'}
    $recorded=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$head.entry.recorded_at,[ref]$recorded)){return & $deny 'journal-aware-atomic-starting-repair-head-time-invalid'}
    $effectiveNow=$Now
    if($effectiveNow -lt $recorded){$effectiveNow=$recorded}

    $append=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$r.journal_revision) -ExpectedEntrySha256 ([string]$r.journal_entry_sha256) -Phase ([string]$r.repair_phase) -Now $effectiveNow
    if($null -eq $append -or -not [bool]$append.ok -or -not [bool]$append.read_after_write_verified){return & $deny ('journal-aware-atomic-starting-repair-append-denied:'+[string]$append.reason)}
    return [pscustomobject]@{ok=$true;reason='journal-aware-atomic-starting-phase-repaired-from-exact-filesystem-evidence';prior_state=[string]$r.state;phase=[string]$append.entry.phase;transaction_id=[string]$append.transaction_id;revision=[int64]$append.revision;entry_sha256=[string]$append.entry.entry_sha256;repair_is_authority=$false;restore_authorized=$false;apply_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
