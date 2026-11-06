param([ValidateSet('bootstrap','fresh-missing')][string]$Phase='bootstrap')
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
    throw 'MISSING_LIVE_RECOVERY_TEST_HOSTED_WINDOWS_ONLY'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1')
. (Join-Path $root 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $PSScriptRoot 'missing-live-recovery.ps1')
function Must-Fail([scriptblock]$Action,[string]$Label) {
    $blocked=$false
    try{& $Action|Out-Null}catch{$blocked=$true}
    if(-not $blocked){throw ('MISSING_LIVE_UNSAFE_ALLOW_'+$Label)}
}
$base=Join-Path $env:RUNNER_TEMP ('missing-live-restart-'+$env:GITHUB_RUN_ID)
$live=Join-Path $base 'live-tagify'
$aside=Join-Path $base 'displaced-live'
$storeRoot=Join-Path $base 'private'
$journal=Join-Path $base 'qualified-journal'
$cid=('e'*64);$tid=('d'*64);$nonce=('b'*32)
if($Phase -ceq 'bootstrap'){
    if(Test-Path -LiteralPath $base){throw 'TEST_WOULD_OVERWRITE_PREEXISTING_FIXTURE'}
    New-Item -ItemType Directory -Force -Path $base,$live,$storeRoot|Out-Null
    [IO.File]::WriteAllText((Join-Path $live 'index.js'),'original-custom-app-script',([Text.UTF8Encoding]::new($false)))
    $s=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $storeRoot -Initialize
    try{
        [void](Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $cid -TransactionId $tid -Nonce $nonce)
        [void](Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $base -JournalStoreDirectory $journal)
        if([long]$s.state.revision -ne 1 -or $null -eq $s.state.active){
            throw 'FIXTURE_TRANSACTION_RESERVATION_NOT_DURABLE'
        }
    }finally{$s.lock_handle.Dispose()}
    Move-Item -LiteralPath $live -Destination $aside
    if([IO.Directory]::Exists($live) -or -not[IO.File]::Exists((Join-Path $aside 'index.js'))){
        throw 'TEST_LIVE_ATOMIC_RENAME_NOT_SIMULATED'
    }
    Must-Fail {Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $storeRoot} 'normal_open_with_absent_live'
    Write-Host 'MISSING_LIVE_RECOVERY_BOOTSTRAP_PASS actual_live_renamed_away=true private_state_persisted=true signed_identity_bound=true'
}else{
    if([IO.Directory]::Exists($live) -or -not[IO.Directory]::Exists($aside)){
        throw 'RECOVERY_TEST_DOES_NOT_HAVE_MISSING_LIVE_CRASH_WINDOW'
    }
    Must-Fail {Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $storeRoot} 'original_opener_must_fail'
    Must-Fail {Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name wrongtagify -LivePath $live -HostedCiRoot $storeRoot} 'wrong_name_not_enrolled'
    Must-Fail {Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath (Join-Path $base 'unrelated-live') -HostedCiRoot $storeRoot} 'unrelated_live_not_enrolled'
    Must-Fail {Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $live -HostedCiRoot 'C:\Windows'} 'out_of_runner_hosted_override'
    $stateFile=Get-CustomAppUserTxnMissingLivePathsV011 -Name tagify -LivePath $live -HostedCiRoot $storeRoot
    $originalHash=(Get-FileHash -LiteralPath $stateFile.state -Algorithm SHA256).Hash
    $locFile=Join-Path $stateFile.directory ('journal-'+$cid+'.dpapi')
    $originalLocatorHash=(Get-FileHash -LiteralPath $locFile -Algorithm SHA256).Hash
    $r=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $live -HostedCiRoot $storeRoot
    try{
        if(-not[bool]$r.ok -or -not[bool]$r.live_missing -or -not[bool]$r.recovery_only -or
           [bool]$r.production_mutation_authorized -or [bool]$r.journal_evidence_verified -or
           [bool]$r.restored_live_verified -or [long]$r.session.state.revision -ne 1 -or
           [string]$r.session.state.active.transaction_id -cne $tid -or
           [string]$r.locator.record.store_directory -cne $journal -or
           [string]$r.locator.record.consumption_id -cne $cid){
            throw 'MISSING_LIVE_RECOVERY_TREATED_POINTER_AS_RESTORE_AUTHORITY'
        }
        Must-Fail {Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $live -HostedCiRoot $storeRoot} 'concurrent_same_app_lock'
        if((Get-FileHash -LiteralPath $stateFile.state -Algorithm SHA256).Hash -cne $originalHash -or
           (Get-FileHash -LiteralPath $locFile -Algorithm SHA256).Hash -cne $originalLocatorHash -or
           [IO.Directory]::Exists($live)){
            throw 'RECOVERY_INSPECTION_MUTATED_ENCRYPTED_RECORDS_OR_RECREATED_LIVE'
        }
    }finally{$r.session.lock_handle.Dispose()}
    [IO.File]::WriteAllBytes([string]$stateFile.pending,[byte[]](1,2,3,4))
    $r=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $live -HostedCiRoot $storeRoot
    try{
        if(-not[bool]$r.pending_unresolved -or -not[IO.File]::Exists($stateFile.pending)){
            throw 'RECOVERY_DISCARDED_UNRESOLVED_PENDING_WRITE'
        }
    }finally{$r.session.lock_handle.Dispose()}
    [IO.File]::Delete([string]$stateFile.pending)
    Move-Item -LiteralPath $aside -Destination $live
    $normal=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $storeRoot
    try{
        if($null -eq $normal.state.active -or [long]$normal.state.revision -ne 1){
            throw 'POST_RESTORE_NORMAL_OPENER_LOST_DURABLE_ACTIVE_CLAIM'
        }
        if([string]$normal.state.active.consumption_id -cne $cid){throw 'POST_RESTORE_CLAIM_IDENTITIES_CHANGED'}
    }finally{$normal.lock_handle.Dispose()}
    if((Get-FileHash -LiteralPath $stateFile.state -Algorithm SHA256).Hash -cne $originalHash -or
       (Get-FileHash -LiteralPath $locFile -Algorithm SHA256).Hash -cne $originalLocatorHash){
        throw 'MISSING_LIVE_RECOVERY_CHANGED_DURABLE_STATE_ON_SUCCESS'
    }
    Write-Host 'MISSING_LIVE_FRESH_PROCESS_RECOVERY_PASS no_live_recreation=true exact_private_DPAPI_and_locator_recovered=true exclusive_lock=true corrupt_pending_preserved=true unauthorised_roots_denied=true original_live_restorable=true no_production_authority=true'
}
