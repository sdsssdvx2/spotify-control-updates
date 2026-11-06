param([ValidateSet('bootstrap','fresh-readback')][string]$Phase='bootstrap')
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
    throw 'DURABLE_RECOVERY_INVENTORY_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $repo 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $repo 'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1')
. (Join-Path $repo 'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1')
. (Join-Path $repo 'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1')
. (Join-Path $repo 'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1')
. (Join-Path $PSScriptRoot 'durable-recovery-inventory.ps1')
function Assert-Throw([scriptblock]$Call,[string]$Label){
    $blocked=$false
    try{& $Call|Out-Null}catch{$blocked=$true}
    if(-not $blocked){throw ('DURABLE_DISCOVERY_FAIL_OPEN_'+$Label)}
}
$root=Join-Path $env:RUNNER_TEMP ('durable-inventory-'+$env:GITHUB_RUN_ID)
$store=Join-Path $root 'private'
$live=Join-Path $root 'live-tagify'
$old=Join-Path $root 'renamed-live'
$cid=('d'*64);$tid=('e'*64);$nonce=('b'*32)
if($Phase -ceq 'bootstrap'){
    if([IO.Directory]::Exists($root)){throw 'DURABLE_INVENTORY_TEST_ROOT_ALREADY_PRESENT'}
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory($store)
    [void][IO.Directory]::CreateDirectory($live)
    $no=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store
    if(-not[bool]$no.ok -or [bool]$no.enrollment_found -or
       [IO.Directory]::Exists((Join-Path $store 'SpotifyControlUpdates-CustomApp-State'))){
        throw 'INVENTORY_BOOTSTRAPPED_STATE_WHILE_IDLE'
    }
    # Already-locked inventory has to reuse the owner's actual FileStream;
    # never acquire the same FileShare.None lock recursively.
    $owned=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
    try {
        $inside=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store -HeldCrossEngineSession $owned
        if(-not[bool]$inside.ok -or [bool]$inside.enrollment_found) {
            throw 'DURABLE_HELD_OWNER_INVENTORY_FAILED'
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $owned)
        Assert-Throw {
            Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot (Join-Path $root 'different') -HeldCrossEngineSession $owned
        } 'held_ci_root_mismatch'
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $owned)
    } finally {
        $owned.lock_handle.Dispose()
    }
    # A claimed "held" object pointing to a different, freely shared
    # FileStream is not authority to inspect registered user transactions.
    $fakePath=Join-Path $store 'fake-exclusive.lock'
    $fakeStream=[IO.File]::Open($fakePath,[IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    try {
        $fake=[pscustomobject]@{
            ok=$true;exclusive_cross_engine=$true;root=$store
            hosted_test_root=$true
            lock_path=(Join-Path (Join-Path $store 'SpotifyControlUpdates-CrossEngineLock') 'current-user-exclusive.lock')
            lock_handle=$fakeStream
        }
        Assert-Throw { Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store -HeldCrossEngineSession $fake } 'forged_lock_handle'
    }finally{$fakeStream.Dispose()}
    Write-Host 'DURABLE_HELD_OWNER_GLOBAL_LOCK_MATRIX_PASS owner_retained=true ci_root_mismatch_denied=true fake_handle_denied=true'
    $l=Join-Path $store 'SpotifyControl'
    [void][IO.Directory]::CreateDirectory($l)
    $oldLedger=Join-Path $l 'addon-last-transaction.json'
    [IO.File]::WriteAllText($oldLedger,'{"phase":"awaiting-apply"}')
    Assert-Throw {Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store} 'legacy_pending'
    [IO.File]::Delete($oldLedger)
    $session=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store -Initialize
    try{
        if([long]$session.state.revision -ne 0){throw 'EMPTY_STATE_WRONG_REVISION'}
    }finally{$session.lock_handle.Dispose()}
    $p=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $live -HostedCiRoot $store
    $canonicalHash=(Get-FileHash -LiteralPath $p.state -Algorithm SHA256).Hash
    [IO.File]::WriteAllBytes([string]$p.pending,[byte[]](1,2,3,4,5))
    $inventory=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store
    if(-not[bool]$inventory.ok -or [int]$inventory.inspected_count -ne 1 -or
       [int]$inventory.active_count -ne 0 -or [bool]$inventory.needs_recovery -or
       -not[bool]$inventory.items[0].pending_preserved -or
       [bool]$inventory.production_mutation_authorized){
        throw 'DURABLE_IDLE_INVENTORY_INVALID_OR_REMOVED_PENDING'
    }
    if((Get-FileHash -LiteralPath $p.state -Algorithm SHA256).Hash -cne $canonicalHash -or
       -not[IO.File]::Exists([string]$p.pending)){
        throw 'DURABLE_INVENTORY_MUTATED_PENDING_OR_ENCRYPTED_STATE'
    }
    Move-Item -LiteralPath $live -Destination $old
    $missing=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store
    if(-not[bool]$missing.items[0].live_missing -or
       [IO.Directory]::Exists($live)){throw 'MISSING_LIVE_INVENTORY_RECREATED_APP'}
    Assert-Throw {Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store} 'original_opener_during_rename'
    Write-Host 'DURABLE_RECOVERY_INVENTORY_BOOTSTRAP_PASS no_enrollment=true old_ledger_denied=true pending_unchanged=true absent_live_detected=true no_mutation=true'
}else{
    if([IO.Directory]::Exists($live) -or -not[IO.Directory]::Exists($old)){
        throw 'DURABLE_INVENTORY_FRESH_PROCESS_RENAME_STATE_ABSENT'
    }
    $n=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store
    if(-not[bool]$n.ok -or [int]$n.inspected_count -ne 1 -or
       [bool]$n.items[0].active -or -not[bool]$n.items[0].live_missing -or
       -not[bool]$n.items[0].pending_preserved){
        throw 'DURABLE_INVENTORY_FRESH_PROCESS_DPAPI_RESTART_DRIFT'
    }
    $entryPath=Join-Path $store 'SpotifyControlUpdates-CustomApp-State'
    $first=Get-ChildItem $entryPath -Directory
    if(@($first).Count -ne 1){throw 'ENROLLED_DIRECTORY_NOT_ONE'}
    $statePath=Join-Path $first[0].FullName 'state.dpapi'
    $locked=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
    try{
        Assert-Throw {Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store} 'global_mutex_held'
    }finally{$locked.lock_handle.Dispose()}
    [IO.File]::WriteAllBytes((Join-Path $entryPath 'unexpected-artifact'),[byte[]](1,2,3))
    Assert-Throw {Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store} 'unexpected_enrollment_child'
    [IO.File]::Delete((Join-Path $entryPath 'unexpected-artifact'))
    $before=(Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    Move-Item -LiteralPath $old -Destination $live
    $session=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store
    try{
        [void](Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $cid -TransactionId $tid -Nonce $nonce)
    }finally{$session.lock_handle.Dispose()}
    # The active ID is real, but no immutable journal locator exists yet.
    # Refuse to call this 'recovered' or to perform any app mutation.
    Assert-Throw {Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store} 'active_without_locator'
    $session=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store
    try{
        [void](Bind-CustomAppUserTxnJournalLocatorV010 -Session $session -AllowedRoot $root -JournalStoreDirectory (Join-Path $root 'unfinished-journal'))
    }finally{$session.lock_handle.Dispose()}
    Assert-Throw {Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $store} 'no_signed_journal'
    $after=(Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    if($before -ceq $after){throw 'SETUP_DID_NOT_PERSIST_RESERVATION'}
    Write-Host 'DURABLE_RECOVERY_INVENTORY_FRESH_PROCESS_PASS read_only_same_identity=true missing_live=true global_mutex=true malformed_entry_denied=true locator_missing_denied=true unverified_journal_denied=true'
}
