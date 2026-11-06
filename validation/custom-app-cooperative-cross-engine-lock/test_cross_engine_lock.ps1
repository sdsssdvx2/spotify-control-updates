param(
    [ValidateSet('all','probe-busy','probe-free')][string]$Mode='all',
    [string]$Sandbox,
    [string]$CandidatePath
)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'CROSS_ENGINE_LOCK_TEST_GITHUB_WINDOWS_HOSTED_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $repo 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $repo 'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1')
. (Join-Path $PSScriptRoot 'cross-engine-transaction-lock.ps1')
function Must-Block([scriptblock]$Action,[string]$Message,[string]$Label){
    $denied=$false
    try{ & $Action | Out-Null } catch {
        if([string]$_.Exception.Message -match [regex]::Escape($Message)){
            $denied=$true
        }else{ throw ('WRONG_DENIAL_'+$Label+' '+[string]$_.Exception.Message) }
    }
    if(-not $denied){throw ('CROSS_ENGINE_FAIL_OPEN_'+$Label)}
}
if($Mode -cne 'all'){
    if([string]::IsNullOrWhiteSpace($Sandbox)){throw 'CHILD_TEST_SANDBOX_MISSING'}
    if($Mode -ceq 'probe-busy'){
        Must-Block { Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $Sandbox } 'cross-engine-lock-busy-or-unavailable' 'fresh_process_lock'
        Write-Host 'CROSS_ENGINE_CHILD_BUSY_DENIED_PASS'
    }else{
        $s=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $Sandbox
        try {
            if(-not[bool](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $s)){throw 'CROSS_ENGINE_FRESH_PROCESS_DID_NOT_ACQUIRE'}
            Write-Host 'CROSS_ENGINE_CHILD_POST_RELEASE_ACQUIRED_PASS'
        }finally{$s.lock_handle.Dispose()}
    }
    exit 0
}
if([string]::IsNullOrWhiteSpace($CandidatePath)){throw 'ACTUAL_ADDON_PATH_REQUIRED'}
$root=Join-Path $env:RUNNER_TEMP ('two-engine-atomic-gate-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$script=(Resolve-Path $PSCommandPath).Path
$held=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $root
try{
    if(-not[bool](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $held)){throw 'LOCK_NOT_HELD_IMMEDIATELY'}
    Must-Block {Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $root} 'cross-engine-lock-busy-or-unavailable' 'same_process_lock'
    $output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Mode probe-busy -Sandbox $root)
    if($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch 'CROSS_ENGINE_CHILD_BUSY_DENIED_PASS'){throw 'CROSS_ENGINE_DIFFERENT_PROCESS_SHARE_NONE_BYPASS'}
    Must-Block {Open-CustomAppNewJournalCrossEnginePreflightV010 -HostedCiRoot $root} 'cross-engine-lock-busy-or-unavailable' 'new_enrollment_during_legacy_transaction'
}finally{$held.lock_handle.Dispose()}
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Mode probe-free -Sandbox $root)
if($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch 'CROSS_ENGINE_CHILD_POST_RELEASE_ACQUIRED_PASS'){throw 'CROSS_ENGINE_LOCK_NOT_RECOVERED_ACROSS_PROCESS'}
$preflight=Open-CustomAppNewJournalCrossEnginePreflightV010 -HostedCiRoot $root
try{
    if(-not[bool]$preflight.ok -or -not[bool]$preflight.cross_engine_lock_held -or [bool]$preflight.safe_to_enroll -or
       [bool]$preflight.may_start_new_engine -or [bool]$preflight.production_mutation_authorized){
        throw 'NEW_ENGINE_LOCKED_INSPECTION_GAVE_UNQUALIFIED_AUTHORITY'
    }
    Must-Block {Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $root} 'cross-engine-lock-busy-or-unavailable' 'old_engine_during_new_preflight'
}finally{$preflight.session.lock_handle.Dispose()}
$legacyDir=Join-Path $root 'SpotifyControl'
[IO.Directory]::CreateDirectory($legacyDir)|Out-Null
$legacy=Join-Path $legacyDir 'addon-last-transaction.json'
$payload=[Text.Encoding]::UTF8.GetBytes('{"status":"awaiting-apply","schema":2}')
[IO.File]::WriteAllBytes($legacy,$payload)
Must-Block {Open-CustomAppNewJournalCrossEnginePreflightV010 -HostedCiRoot $root} 'new-journal-legacy-preflight-unresolved-legacy-transaction-must-finish-first' 'legacy_unresolved'
$again=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $root
try{
    if(-not[bool]$again.ok){throw 'FAILED_PRECHECK_LEAKED_CROSS_ENGINE_LOCK'}
    if([IO.File]::ReadAllBytes($legacy).Length -ne $payload.Length){throw 'OLD_LEGACY_LEDGER_MODIFIED_BY_NEW_PREFLIGHT'}
}finally{$again.lock_handle.Dispose()}
[IO.File]::Delete($legacy)
Write-Host 'CROSS_ENGINE_LOCK_TWO_PROCESS_MATRIX_PASS held_legacy_blocks_new=true held_new_blocks_legacy=true pending_legacy_denies_new=true no_deadlocks=true'
# Execute the qualified generated Addon Manager, not a stub. Hold the
# default CurrentUser lock while its three mutating Action paths run.
$actual=Open-CustomAppCrossEngineTransactionLockV010
try{
    $source=(Resolve-Path $CandidatePath).Path
    $errorsPath=Join-Path $env:LOCALAPPDATA 'SpotifyControl\logs\addons-error.log'
    foreach($action in @('CommitLast','RollbackLast','Update')){
        $output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $source -Action $action -Force)
        if($LASTEXITCODE -eq 0){throw ('ACTUAL_LEGACY_ACTION_IGNORED_CROSS_ENGINE_LOCK_'+$action)}
        if(-not[IO.File]::Exists($errorsPath) -or
           -not[IO.File]::ReadAllText($errorsPath).Contains('cross-engine-lock-busy-or-unavailable')){
            throw ('ACTUAL_LEGACY_ACTION_DENIED_FOR_WRONG_REASON_'+$action)
        }
        Write-Host ('CROSS_ENGINE_ACTUAL_ACTION_BUSY_DENIED_PASS action='+$action)
    }
}finally{$actual.lock_handle.Dispose()}
# Free legacy no-op settlements must still work. Do not run normal Update
# unlocked here because it can access remote sources.
foreach($action in @('CommitLast','RollbackLast')){
    $output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Resolve-Path $CandidatePath).Path -Action $action)
    if($LASTEXITCODE -ne 0){throw ('LEGACY_NOOP_SETTLEMENT_REGRESSION_'+$action+' '+($output -join ' '))}
}
$probe=Open-CustomAppCrossEngineTransactionLockV010
try{if(-not[bool]$probe.ok){throw 'FAILED_TO_REACQUIRE_AFTER_REAL_ACTIONS'}}finally{$probe.lock_handle.Dispose()}
Write-Host 'CROSS_ENGINE_ACTUAL_ADDON_ACTIONS_E2E_PASS three_actions_lock_scoped=true free_legacy_noops_preserved=true no_real_user_software=true'
