# Candidate-only PRE-TERMINAL transition guard. Harden all paths through the
# exposed Save function. Until verified terminal-journal reconciliation exists
# the only legal transition is inactive -> one immutable reserved Triple-ID.
# An ordinary caller cannot clear or rotate active, pre-consume IDs, or replace
# the consumed ledger just by supplying a fabricated NextState object.
function Test-CustomAppUserTxnPermitOnlyTransitionV010 {
    param([Parameter(Mandatory=$true)]$Current,[Parameter(Mandatory=$true)]$Next,[Parameter(Mandatory=$true)]$Paths)
    [void](Test-CustomAppUserTxnStateV010 -State $Current -Paths $Paths)
    [void](Test-CustomAppUserTxnStateV010 -State $Next -Paths $Paths)
    if($null -ne $Current.active) { throw 'user-store-active-reservation-cannot-be-modified-without-verified-terminal-journal' }
    if($null -eq $Next.active) { throw 'user-store-reservation-required-no-raw-state-mutation' }
    if([long]$Next.revision -ne ([long]$Current.revision+1)) { throw 'user-store-transition-revision-invalid' }
    foreach($field in @('schema','name','live','key','created_utc')) {
        if([string]$Current.$field -cne [string]$Next.$field) { throw ('user-store-transition-identity-changed-'+$field) }
    }
    if(@($Current.consumed).Count -ne @($Next.consumed).Count -or
        (@($Current.consumed) -join '|') -cne (@($Next.consumed) -join '|')) {
        throw 'user-store-transition-consumed-ledger-changed'
    }
    $actual=@($Next.active.PSObject.Properties.Name|Sort-Object)
    $expected=@('consumption_id','created_utc','nonce','state','transaction_id'|Sort-Object)
    if(($actual -join '|') -cne ($expected -join '|')) { throw 'user-store-transition-reservation-fields-invalid' }
    if([string]$Next.active.state -cne 'reserved' -or
        [string]$Next.active.consumption_id -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Next.active.transaction_id -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Next.active.nonce -cnotmatch '^[0-9a-f]{32}$' -or
        @($Current.consumed) -ccontains [string]$Next.active.consumption_id) {
        throw 'user-store-transition-reservation-identity-invalid'
    }
    $previous=[DateTimeOffset]::MinValue;$nextTime=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Current.updated_utc,[ref]$previous) -or
        -not [DateTimeOffset]::TryParse([string]$Next.updated_utc,[ref]$nextTime) -or
        $nextTime -lt $previous -or
        $nextTime -gt ([DateTimeOffset]::UtcNow.AddSeconds(60)) -or
        [string]$Next.active.created_utc -cne [string]$Next.updated_utc) {
        throw 'user-store-transition-reservation-timestamp-invalid'
    }
    return $true
}

function Save-CustomAppUserTxnStoreV010 {
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)]$NextState,[switch]$HostedCiInterruptBeforeReplace)
    Assert-CustomAppUserTxnSessionV010 $Session
    $p=$Session.paths
    [void](Test-CustomAppUserTxnStateV010 -State $NextState -Paths $p)
    if([long]$NextState.revision -ne ([long]$Session.state.revision+1)) { throw 'user-store-nonmonotonic-revision' }
    $current=Read-CustomAppUserTxnStateV010 $p
    if([long]$current.revision -ne [long]$Session.state.revision) { throw 'user-store-canonical-revision-drift' }
    if(($current|ConvertTo-Json -Compress -Depth 8) -cne ($Session.state|ConvertTo-Json -Compress -Depth 8)) { throw 'user-store-memory-canonical-state-drift' }
    [void](Test-CustomAppUserTxnPermitOnlyTransitionV010 -Current $current -Next $NextState -Paths $p)

    if([IO.File]::Exists($p.pending)) { throw 'user-store-unresolved-pending' }
    Assert-CustomAppUserTxnNoReparseV010 $p.backup
    $sealed=Protect-CustomAppUserTxnStateV010 -State $NextState -Paths $p
    Write-CustomAppUserTxnBytesV010 -Path $p.pending -Bytes $sealed
    if($HostedCiInterruptBeforeReplace) {
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted') { throw 'user-store-fault-injection-not-hosted-ci' }
        throw 'user-store-injected-crash-before-atomic-replace'
    }
    [IO.File]::Replace([string]$p.pending,[string]$p.state,[string]$p.backup)
    $reloaded=Read-CustomAppUserTxnStateV010 $p
    if([long]$reloaded.revision -ne [long]$NextState.revision -or [string]$reloaded.updated_utc -cne [string]$NextState.updated_utc) { throw 'user-store-atomic-write-readback-invalid' }
    $Session.state=$reloaded
    return [pscustomobject]@{ok=$true;revision=[long]$reloaded.revision;active=($null -ne $reloaded.active);production_mutation_authorized=$false}
}
