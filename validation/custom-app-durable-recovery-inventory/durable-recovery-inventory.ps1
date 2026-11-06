# Recovery startup inventory ONLY: no enrolment, mutation or apply.
# Acquire the same global lock used by normal Update / CommitLast /
# RollbackLast. Read CurrentUser DPAPI records without user-supplied paths.
# Never call Open-CustomAppUserTxnStoreV010: it removes state.pending.
# The historical crash-journal reader opens .journal.lock with OpenOrCreate.
# An inventory must never materialize a missing journal lock: absence is
# evidence of an incomplete or altered journal, not permission to repair it.
function Read-CustomAppDurableRecoveryJournalReadOnlyV012 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    $lockPath=[string]$paths.lock
    Assert-CustomAppUserTxnNoReparseV010 -Path $lockPath
    if(-not[IO.File]::Exists($lockPath)) {
        throw 'durable-recovery-journal-lock-missing'
    }
    $stream=$null
    try {
        # Keep the original crash journal reader's exclusive FileShare.None
        # semantics, but never create or rewrite any journal artifact.
        $stream=[IO.File]::Open($lockPath,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Assert-CustomAppUserTxnNoReparseV010 -Path $lockPath
        return Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths
    } finally {
        if($null -ne $stream){$stream.Dispose()}
    }
}
function Get-CustomAppDurableRecoveryInventoryV012 {
    param([string]$HostedCiRoot,$HeldCrossEngineSession)
    $globalLock=$null
    $ownsGlobalLock=$false
    try {
        if($null -ne $HeldCrossEngineSession){
            $globalLock=$HeldCrossEngineSession
            [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $globalLock)
            if($globalLock.lock_handle -isnot [IO.FileStream]) {
                throw 'durable-recovery-shared-session-stream-type-invalid'
            }
            $root=[IO.Path]::GetFullPath([string]$globalLock.root).TrimEnd('\','/')
            if([bool]$globalLock.hosted_test_root){
                if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
                   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
                   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
                    throw 'durable-recovery-held-hosted-root-not-in-ci'
                }
                if([string]::IsNullOrWhiteSpace($HostedCiRoot) -or
                   -not $root.Equals([IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/'),
                         [StringComparison]::OrdinalIgnoreCase)){
                    throw 'durable-recovery-held-ci-root-mismatch'
                }
                $ciBase=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
                if(-not $root.StartsWith(($ciBase+'\'),[StringComparison]::OrdinalIgnoreCase)){
                    throw 'durable-recovery-held-root-outside-ci'
                }
            } else {
                if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot) -or
                   -not $root.Equals([IO.Path]::GetFullPath(
                    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
                   ).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){
                    throw 'durable-recovery-held-profile-root-mismatch'
                }
            }
            $expectedLock=Join-Path (Join-Path $root 'SpotifyControlUpdates-CrossEngineLock') 'current-user-exclusive.lock'
            if(-not[IO.Path]::GetFullPath([string]$globalLock.lock_path).Equals(
                [IO.Path]::GetFullPath($expectedLock),[StringComparison]::OrdinalIgnoreCase) -or
               -not[IO.Path]::GetFullPath([string]$globalLock.lock_handle.Name).Equals(
                [IO.Path]::GetFullPath($expectedLock),[StringComparison]::OrdinalIgnoreCase)){
                throw 'durable-recovery-held-global-lock-not-canonical'
            }
            # Prove the supplied handle actually excludes all other openers.
            # A caller-crafted session with only a readable, shared stream
            # must not claim the transaction-wide lock.
            $adversary=$null
            $denied=$false
            try {
                $adversary=[IO.File]::Open($expectedLock,[IO.FileMode]::Open,
                    [IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            }catch [IO.IOException] {$denied=$true}
            finally {if($null -ne $adversary){$adversary.Dispose()}}
            if(-not $denied){throw 'durable-recovery-held-global-lock-not-exclusive'}
        } else {
            $globalLock=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
            $ownsGlobalLock=$true
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $globalLock)
        $root=[string]$globalLock.root
        if([bool]$globalLock.hosted_test_root) {
            $legacy=Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root
        } else {
            $legacy=Assert-CustomAppNewJournalLegacyLedgerClosedV011
        }
        if(-not[bool]$legacy.ok -or [bool]$legacy.safe_to_enroll) {
            throw 'durable-recovery-legacy-transaction-not-closed'
        }
        $enrollment=Join-Path $root 'SpotifyControlUpdates-CustomApp-State'
        [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $enrollment)
        if(-not[IO.Directory]::Exists($enrollment)) {
            if([IO.File]::Exists($enrollment) -or
              (Test-Path -LiteralPath $enrollment -ErrorAction SilentlyContinue)) {
                throw 'durable-recovery-enrollment-object-invalid'
            }
            return [pscustomobject]@{
                schema=1;ok=$true;enrollment_found=$false;needs_recovery=$false
                inspected_count=0;active_count=0;items=@()
                no_app_state_modified=$true;result_is_authority=$false
                production_execution_authorized=$false;production_mutation_authorized=$false
            }
        }
        [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $enrollment)
        $entries=@(Get-ChildItem -LiteralPath $enrollment -Force -ErrorAction Stop)
        if($entries.Count -gt 256) { throw 'durable-recovery-enrollment-count-limit' }
        $items=New-Object 'System.Collections.Generic.List[object]'
        foreach($entry in $entries) {
            if([string]$entry.Name -cnotmatch '^[0-9a-f]{64}$' -or
               -not[bool]$entry.PSIsContainer -or
               ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'durable-recovery-unknown-enrollment-entry'
            }
            [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $entry.FullName)
            $key=[string]$entry.Name
            $statePath=Join-Path $entry.FullName 'state.dpapi'
            $lockPath=Join-Path $entry.FullName 'exclusive.lock'
            foreach($file in @($statePath,$lockPath,(Join-Path $entry.FullName 'state.pending'),
                                            (Join-Path $entry.FullName 'state.backup'))) {
                Assert-CustomAppUserTxnNoReparseV010 $file
            }
            if(-not[IO.File]::Exists($statePath) -or -not[IO.File]::Exists($lockPath)) {
                throw 'durable-recovery-enrolled-record-incomplete'
            }
            $lock=$null;$plain=$null
            try {
                # Open, never OpenOrCreate. Concurrent updater/recovery fails closed.
                $lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,
                            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                Assert-CustomAppUserTxnNoReparseV010 $lockPath
                $sealed=[IO.File]::ReadAllBytes($statePath)
                if($sealed.Length -lt 64 -or $sealed.Length -gt 262144) {
                    throw 'durable-recovery-state-size-invalid'
                }
                Add-Type -AssemblyName System.Security -ErrorAction Stop
                $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|UserTxn|v1|'+$key))
                $plain=[Security.Cryptography.ProtectedData]::Unprotect(
                    $sealed,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
                $state=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
                $name=[string]$state.name
                $live=[string]$state.live
                if($name -cnotmatch '^[a-z][a-z0-9_-]{1,63}$' -or
                   [string]::IsNullOrWhiteSpace($live) -or
                   -not[IO.Path]::IsPathRooted($live) -or $live.StartsWith('\\') -or
                   (Get-CustomAppUserTxnSha256V010 ($live.ToLowerInvariant())) -cne $key) {
                    throw 'durable-recovery-sealed-identity-invalid'
                }
                $missing=-not[IO.Directory]::Exists($live)
                if($missing){
                    $paths=Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
                }else{
                    $paths=Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
                }
                if(-not[IO.Path]::GetFullPath([string]$paths.directory).Equals(
                   [IO.Path]::GetFullPath([string]$entry.FullName),[StringComparison]::OrdinalIgnoreCase)) {
                    throw 'durable-recovery-enrollment-path-drift'
                }
                [void](Test-CustomAppUserTxnStateV010 -State $state -Paths $paths)
                $canonical=Read-CustomAppUserTxnStateV010 -Paths $paths
                if(($canonical|ConvertTo-Json -Compress -Depth 8) -cne
                   ($state|ConvertTo-Json -Compress -Depth 8)) {
                    throw 'durable-recovery-state-changed-during-read'
                }
                $session=[pscustomobject]@{
                    ok=$true;paths=$paths;state=$canonical;lock_handle=$lock
                    production_execution_authorized=$false;production_mutation_authorized=$false
                }
                $phase='none'
                if($null -ne $canonical.active) {
                    $locator=Read-CustomAppUserTxnJournalLocatorV010 -Session $session
                    if(-not[bool]$locator.ok -or [bool]$locator.journal_evidence_verified -or
                       [string]$locator.record.transaction_id -cne [string]$canonical.active.transaction_id) {
                        throw 'durable-recovery-locator-unqualified'
                    }
                    if(-not(Get-Command Read-CustomAppProductionCrashJournalUnlockedV010 -CommandType Function -ErrorAction SilentlyContinue)) {
                        throw 'durable-recovery-journal-reader-not-loaded'
                    }
                    $j=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$locator.record.allowed_root) -StoreDirectory ([string]$locator.record.store_directory)
                    if($null -eq $j -or -not[bool]$j.ok -or
                      [string]$j.entry.transaction_id -cne [string]$canonical.active.transaction_id) {
                        throw 'durable-recovery-journal-corrupt-or-wrong-transaction'
                    }
                    $phase=[string]$j.entry.phase
                    if($phase -cnotin @('prepared','atomic-mutation-starting',
                        'live-moved-to-old','candidate-live','transaction-finalized',
                        'apply-starting','apply-returned-success-pending-verification',
                        'apply-verified','cleanup-starting','committed-clean',
                        'rollback-required','rollback-complete')) {
                        throw 'durable-recovery-invalid-journal-phase'
                    }
                    if($missing -and $phase -in @('committed-clean','rollback-complete')) {
                        throw 'durable-recovery-terminal-journal-live-missing'
                    }
                }
                $items.Add([pscustomobject]@{
                    name=$name;active=[bool]($null -ne $canonical.active)
                    state_revision=[long]$canonical.revision
                    journal_phase=$phase;live_missing=[bool]$missing
                    pending_preserved=[bool][IO.File]::Exists([string]$paths.pending)
                    needs_recovery=[bool]($null -ne $canonical.active)
                    may_execute_recovery=$false;result_is_authority=$false
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
            }finally{
                if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
                if($null -ne $lock){$lock.Dispose()}
            }
            [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $globalLock)
        }
        return [pscustomobject]@{
            schema=1;ok=$true;enrollment_found=$true
            needs_recovery=[bool](@($items|Where-Object{$_.needs_recovery}).Count -gt 0)
            inspected_count=$items.Count
            active_count=@($items|Where-Object{$_.active}).Count
            items=@($items.ToArray());no_app_state_modified=$true
            result_is_authority=$false
            production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }finally {
        if($ownsGlobalLock -and $null -ne $globalLock -and
           $null -ne $globalLock.lock_handle){
            $globalLock.lock_handle.Dispose()
        }
    }
}
function Test-CustomAppDurableRecoveryInventorySelfTestV012 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'durable-recovery-discovery-unqualified-production-activation'
    }
    if(-not(Get-Command Get-CustomAppDurableRecoveryInventoryV012 -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'durable-recovery-discovery-export-missing'
    }
    Write-Host 'DURABLE_RECOVERY_SELF_DISCOVERY_SELFTEST_PASS passive_dpapi_scan=true sealed_identity_only=true no_pending_cleanup=true zero_mutation_authority=true'
}
