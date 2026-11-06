param(
    [string]$StatePath,
    [string]$ResultPath,
    [switch]$ProbeOnly,
    [string]$LockReadyPath,
    [string]$LockReleasePath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

# The historical recovery worker remains SHA-pinned byte-for-byte. This
# hosted Windows validation adapter is the NEW fresh-process entrypoint.
# Every original admission, journal transition, filesystem restore, fake
# old-code Spicetify apply and result verification executes under exactly
# the same CurrentUser FileShare.None cross-engine lock as the real legacy
# Update / CommitLast / RollbackLast dispatcher.
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'LOCKED_RECOVERY_WORKER_HOSTED_WINDOWS_ONLY'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $root 'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1')
$lock=$null
try {
    $lock=Open-CustomAppCrossEngineTransactionLockV010
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $lock)
    if($ProbeOnly){
        Write-Host 'RECOVERY_CHILD_SHARED_LOCK_PROBE_ACQUIRED_PASS'
        return
    }
    if([string]::IsNullOrWhiteSpace($StatePath) -or
       [string]::IsNullOrWhiteSpace($ResultPath)){
        throw 'locked-recovery-worker-state-or-result-path-missing'
    }
    $runner=[IO.Path]::GetFullPath([string]$env:RUNNER_TEMP).TrimEnd('\','/')
    foreach($path in @($StatePath,$ResultPath)){
        if(-not[IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\') -or
           -not[IO.Path]::GetFullPath($path).StartsWith(
               ($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'locked-recovery-worker-path-outside-hosted-runner'
        }
    }
    $haveReady=-not[string]::IsNullOrWhiteSpace($LockReadyPath)
    $haveRelease=-not[string]::IsNullOrWhiteSpace($LockReleasePath)
    if($haveReady -ne $haveRelease){
        throw 'locked-recovery-worker-handshake-must-be-paired'
    }
    if($haveReady){
        foreach($path in @($LockReadyPath,$LockReleasePath)){
            if(-not[IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\') -or
               -not[IO.Path]::GetFullPath($path).StartsWith(
                   ($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
                throw 'locked-recovery-worker-handshake-outside-runner'
            }
            if([IO.File]::Exists($path) -or [IO.Directory]::Exists($path) -or
               (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)){
                throw 'locked-recovery-worker-handshake-path-preexists'
            }
            $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
            if(-not[IO.Directory]::Exists($parent)){
                throw 'locked-recovery-worker-handshake-parent-missing'
            }
        }
        [IO.File]::WriteAllText($LockReadyPath,'LOCK_HELD',[Text.UTF8Encoding]::new($false))
        $deadline=[DateTimeOffset]::UtcNow.AddSeconds(75)
        while(-not[IO.File]::Exists($LockReleasePath)){
            if([DateTimeOffset]::UtcNow -gt $deadline){
                throw 'locked-recovery-worker-handshake-timeout-fail-closed'
            }
            Start-Sleep -Milliseconds 120
        }
        if([IO.File]::ReadAllText($LockReleasePath).Trim() -cne 'RELEASE_TO_RECOVER'){
            throw 'locked-recovery-worker-handshake-ack-invalid'
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $lock)
        Write-Host 'RECOVERY_CHILD_SHARED_LOCK_HELD_THROUGH_HANDSHAKE_PASS'
    }
    $original=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
    if(-not[IO.File]::Exists($original)){
        throw 'locked-recovery-worker-qualified-original-not-found'
    }
    & $original -StatePath $StatePath -ResultPath $ResultPath
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $lock)
    Write-Host 'RECOVERY_CHILD_ORIGINAL_WORKER_EXECUTED_UNDER_SHARED_LOCK_PASS'
}finally{
    if($null -ne $lock -and $null -ne $lock.lock_handle){
        $lock.lock_handle.Dispose()
    }
}
