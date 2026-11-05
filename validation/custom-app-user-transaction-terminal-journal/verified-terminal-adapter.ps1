# Candidate-only terminal retirement bridge. The regular Save function remains
# PRE-TERMINAL and cannot clear an active claim. This explicit path independently
# reloads the qualified append-only journal and recovery evidence from disk,
# rechecks exact live bytes/runtime and Spotify persistence, then writes the
# used-ID ledger and clears the active claim IN ONE DPAPI-atomic state replacement.
# No caller-supplied success/terminal boolean, no Spicetify call, no auto update.

function Test-CustomAppUserTxnTerminalJournalEvidenceV010 {
    param(
        [Parameter(Mandatory=$true)]$Session,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot
    )
    Assert-CustomAppUserTxnSessionV010 -Session $Session
    $p=$Session.paths
    if($ExpectedConsumptionId -cnotmatch '^[0-9a-f]{64}$' -or $ExpectedTransactionId -cnotmatch '^[0-9a-f]{64}$'){
        throw 'user-terminal-input-identifiers-invalid'
    }
    $s=Read-CustomAppUserTxnStateV010 -Paths $p
    if(($s|ConvertTo-Json -Compress -Depth 8) -cne ($Session.state|ConvertTo-Json -Compress -Depth 8)){
        throw 'user-terminal-session-state-not-current'
    }
    if($null -eq $s.active -or
        [string]$s.active.consumption_id -cne $ExpectedConsumptionId -or
        [string]$s.active.transaction_id -cne $ExpectedTransactionId){
        throw 'user-terminal-active-reservation-missing-or-mismatched'
    }
    $root=[IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\','/')
    $journal=[IO.Path]::GetFullPath($JournalStoreDirectory).TrimEnd('\','/')
    if(-not $journal.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'user-terminal-journal-outside-allowed-root'
    }
    if(-not(Get-Command Read-CustomAppProductionCrashJournalV010 -CommandType Function -ErrorAction SilentlyContinue) -or
       -not(Get-Command Read-CustomAppProductionRecoveryEvidenceV010 -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'user-terminal-qualified-durable-verifiers-unavailable'
    }
    $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $root -StoreDirectory $journal
    if($null -eq $j -or -not[bool]$j.ok -or -not[bool]$j.reloaded_from_persistent_store -or
        [string]$j.transaction_id -cne $ExpectedTransactionId -or
        [string]$j.entry.transaction_id -cne $ExpectedTransactionId -or
        [string]$j.entry.consumption_id -cne $ExpectedConsumptionId -or
        [string]$j.entry.name -cne [string]$p.name -or
        -not ([IO.Path]::GetFullPath([string]$j.entry.live_path).TrimEnd('\','/').Equals([string]$p.live,[StringComparison]::OrdinalIgnoreCase)) -or
        [string]$j.entry.phase -notin @('rollback-complete','committed-clean') -or
        [bool]$j.journal_is_authority -or [bool]$j.production_mutation_authorized){
        throw 'user-terminal-durable-journal-identity-or-terminal-phase-invalid'
    }
    $e=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $root -StoreDirectory $journal -ExpectedTransactionId $ExpectedTransactionId
    if($null -eq $e -or -not[bool]$e.ok -or -not[bool]$e.reloaded_from_persistent_store -or
        [bool]$e.evidence_is_authority -or [bool]$e.production_mutation_authorized -or
        [string]$e.transaction_id -cne $ExpectedTransactionId -or
        [string]$e.envelope.transaction_id -cne $ExpectedTransactionId -or
        [string]$e.envelope.consumption_id -cne $ExpectedConsumptionId -or
        [string]$e.envelope.name -cne [string]$p.name -or
        [string]$e.envelope.preparation_fingerprint -cne [string]$j.entry.preparation_fingerprint -or
        [string]$e.envelope.stage_result_fingerprint -cne [string]$j.entry.stage_result_fingerprint -or
        [string]$e.journal_phase -cne [string]$j.entry.phase -or
        [int64]$e.journal_revision -ne [int64]$j.revision){
        throw 'user-terminal-durable-recovery-evidence-identity-invalid'
    }
    if(-not(Get-Command Get-CustomAppUpdateTreeSnapshotV010 -CommandType Function -ErrorAction SilentlyContinue) -or
       -not(Get-Command Get-CustomAppLocalRuntimeBaseline -CommandType Function -ErrorAction SilentlyContinue) -or
       -not(Get-Command Get-SpotifyPersistenceSnapshot -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'user-terminal-filesystem-verifiers-unavailable'
    }
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if($null -eq $persist -or [string]$persist.fingerprint -cne [string]$e.envelope.persistence_fingerprint){
        throw 'user-terminal-spotify-persistence-not-restored-or-consistent'
    }
    $phase=[string]$j.entry.phase
    if($phase -ceq 'rollback-complete'){
        $live=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live)
        if($null -eq $live -or [string]$live.tree_sha256 -cne [string]$e.envelope.live_tree_sha256){
            throw 'user-terminal-rollback-live-tree-not-original'
        }
    }else{
        $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$p.name) -AppPath ([string]$p.live)
        if($null -eq $runtime -or -not[bool]$runtime.safe -or -not[bool]$runtime.installable -or
           [string]$runtime.tree_sha256 -cne [string]$e.envelope.stage_tree_sha256){
            throw 'user-terminal-committed-live-not-verified-stage'
        }
    }
    return [pscustomobject]@{
        ok=$true;phase=$phase;transaction_id=$ExpectedTransactionId
        consumption_id=$ExpectedConsumptionId;revision=[int64]$j.revision
        journal_entry_sha256=[string]$j.entry.entry_sha256
        recovery_evidence_fingerprint=[string]$e.evidence_fingerprint
        persistent_journal_readback=$true;persisted_evidence_readback=$true
        live_and_spotify_persistence_revalidated=$true
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}

function Commit-CustomAppUserTxnVerifiedTerminalV011 {
    param(
        [Parameter(Mandatory=$true)]$Session,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [switch]$HostedCiInterruptBeforeReplace
    )
    $args=@{
        Session=$Session;AllowedRoot=$AllowedRoot;JournalStoreDirectory=$JournalStoreDirectory
        ExpectedConsumptionId=$ExpectedConsumptionId;ExpectedTransactionId=$ExpectedTransactionId
        LocalAppDataRoot=$LocalAppDataRoot;AppDataRoot=$AppDataRoot
    }
    # Confirm the exact externally qualified journal/evidence and the real
    # restored or committed live state BEFORE any durable ledger mutation.
    $verified=Test-CustomAppUserTxnTerminalJournalEvidenceV010 @args
    if(-not[bool]$verified.ok){throw 'user-terminal-evidence-not-verified'}
    Assert-CustomAppUserTxnSessionV010 $Session
    $p=$Session.paths
    $current=Read-CustomAppUserTxnStateV010 $p
    if($null -eq $current.active -or [string]$current.active.consumption_id -cne $ExpectedConsumptionId -or
       [string]$current.active.transaction_id -cne $ExpectedTransactionId){
        throw 'user-terminal-active-claim-drift-before-durable-retirement'
    }
    if(@($current.consumed) -ccontains $ExpectedConsumptionId){throw 'user-terminal-consumption-already-retired-in-inconsistent-active-state'}
    if(@($current.consumed).Count -ge 4096){throw 'user-terminal-consumption-ledger-full-fail-closed'}
    $next=$current|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $next.revision=[long]$current.revision+1
    $next.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
    $next.consumed=@(@($current.consumed)+@($ExpectedConsumptionId))
    $next.active=$null
    [void](Test-CustomAppUserTxnStateV010 -State $next -Paths $p)
    if([long]$next.revision -ne [long]$current.revision+1 -or
        ($next.consumed | Select-Object -Last 1) -cne $ExpectedConsumptionId -or
        $null -ne $next.active){throw 'user-terminal-invalid-retirement-delta'}
    if([IO.File]::Exists($p.pending)){throw 'user-terminal-unresolved-pending-write'}
    Assert-CustomAppUserTxnNoReparseV010 $p.backup
    $sealed=Protect-CustomAppUserTxnStateV010 -State $next -Paths $p
    Write-CustomAppUserTxnBytesV010 -Path $p.pending -Bytes $sealed
    if($HostedCiInterruptBeforeReplace){
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
            throw 'user-terminal-fault-injection-hosted-Windows-only'
        }
        throw 'user-terminal-ci-interrupted-before-atomic-ledger-replacement'
    }
    [IO.File]::Replace([string]$p.pending,[string]$p.state,[string]$p.backup)
    $reloaded=Read-CustomAppUserTxnStateV010 $p
    if([long]$reloaded.revision -ne [long]$next.revision -or $null -ne $reloaded.active -or
        @($reloaded.consumed) -cnotcontains $ExpectedConsumptionId){
        throw 'user-terminal-retirement-readback-invalid'
    }
    $Session.state=$reloaded
    return [pscustomobject]@{
        ok=$true;phase=[string]$verified.phase
        reason='verified-terminal-journal-and-physical-state-id-retired-atomically'
        revision=[long]$reloaded.revision;consumption_id=$ExpectedConsumptionId
        transaction_id=$ExpectedTransactionId
        journal_entry_sha256=[string]$verified.journal_entry_sha256
        recovery_evidence_fingerprint=[string]$verified.recovery_evidence_fingerprint
        active_claim_retired=$true;single_use_consumption_durable=$true
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
