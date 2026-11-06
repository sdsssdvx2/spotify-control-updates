# Sealed startup source-to-plan bridge. A source selection is NOT a recovery
# execution admission. Never deserialize an external recovery JSON or accept
# caller supplied app identity, transaction ID, store path, or journal root.
# The cross-engine user lock covers discovery AND each fresh bound read. Each
# enrolled app also holds its preexisting FileShare.None transaction lock.
# No file created, renamed, removed, or rewritten; preserve state.pending.
function Get-CustomAppSealedStartupRecoveryAssessmentV013 {
    param([string]$HostedCiRoot,$HeldCrossEngineSession)
    $globalLock=$null;$ownGlobalLock=$false
    try {
        if($null -ne $HeldCrossEngineSession){
            # The V012 inventory validates the handle, exact canonical lock,
            # profile/test-root consistency and actual cross-process exclusion.
            $globalLock=$HeldCrossEngineSession
        }else{
            $globalLock=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
            $ownGlobalLock=$true
        }
        $inventory=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $HostedCiRoot -HeldCrossEngineSession $globalLock
        if(-not[bool]$inventory.ok -or [bool]$inventory.result_is_authority -or
           [bool]$inventory.production_mutation_authorized){
            throw 'startup-assessment-inventory-not-passive'
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $globalLock)
        if(-not[bool]$inventory.enrollment_found){
            return [pscustomobject]@{
                schema=1;ok=$true;enrollment_found=$false;inspected_count=0
                active_count=0;items=@();only_sealed_registry_sources=$true
                journal_read_only=$true;result_is_authority=$false
                production_execution_authorized=$false;production_mutation_authorized=$false
            }
        }
        $container=Join-Path ([string]$globalLock.root) 'SpotifyControlUpdates-CustomApp-State'
        [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $container)
        $entries=@(Get-ChildItem -LiteralPath $container -Force -ErrorAction Stop)
        if($entries.Count -ne [int]$inventory.inspected_count -or $entries.Count -gt 256){
            throw 'startup-assessment-enrollment-count-changed'
        }
        $out=New-Object 'System.Collections.Generic.List[object]'
        $i=0
        foreach($entry in $entries){
            if([string]$entry.Name -cnotmatch '^[0-9a-f]{64}$' -or
               -not[bool]$entry.PSIsContainer -or
               ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'startup-assessment-invalid-enrollment-entry'
            }
            [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $entry.FullName)
            $key=[string]$entry.Name
            $path=Join-Path $entry.FullName 'state.dpapi'
            $lockPath=Join-Path $entry.FullName 'exclusive.lock'
            Assert-CustomAppUserTxnNoReparseV010 -Path $path
            Assert-CustomAppUserTxnNoReparseV010 -Path $lockPath
            if(-not[IO.File]::Exists($path) -or -not[IO.File]::Exists($lockPath)){
                throw 'startup-assessment-enrolled-state-or-lock-missing'
            }
            $stream=$null;$plain=$null
            try{
                $stream=[IO.File]::Open($lockPath,[IO.FileMode]::Open,
                    [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                Assert-CustomAppUserTxnNoReparseV010 -Path $lockPath
                $sealed=[IO.File]::ReadAllBytes($path)
                if($sealed.Length -lt 64 -or $sealed.Length -gt 262144){
                    throw 'startup-assessment-invalid-encrypted-state-size'
                }
                Add-Type -AssemblyName System.Security -ErrorAction Stop
                $entropy=[Text.Encoding]::UTF8.GetBytes(
                    ('SpotifyControlUpdates|UserTxn|v1|'+$key))
                $plain=[Security.Cryptography.ProtectedData]::Unprotect(
                    $sealed,$entropy,
                    [Security.Cryptography.DataProtectionScope]::CurrentUser)
                $draft=([Text.Encoding]::UTF8.GetString($plain) |
                    ConvertFrom-Json -ErrorAction Stop)
                $name=[string]$draft.name;$live=[string]$draft.live
                if($name -cnotmatch '^[a-z][a-z0-9_-]{1,63}$' -or
                   [string]::IsNullOrWhiteSpace($live) -or
                   -not[IO.Path]::IsPathRooted($live) -or
                   $live.StartsWith('\\') -or
                   (Get-CustomAppUserTxnSha256V010 ($live.ToLowerInvariant())) -cne $key){
                    throw 'startup-assessment-encrypted-identity-invalid'
                }
                $missing=-not[IO.Directory]::Exists($live)
                $paths=if($missing){
                    Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
                }else{
                    Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
                }
                if(-not[IO.Path]::GetFullPath([string]$paths.directory).Equals(
                    [IO.Path]::GetFullPath([string]$entry.FullName),
                    [StringComparison]::OrdinalIgnoreCase)){
                    throw 'startup-assessment-sealed-registry-path-mismatch'
                }
                [void](Test-CustomAppUserTxnStateV010 -State $draft -Paths $paths)
                $canonical=Read-CustomAppUserTxnStateV010 -Paths $paths
                if(($draft|ConvertTo-Json -Compress -Depth 8) -cne
                   ($canonical|ConvertTo-Json -Compress -Depth 8)){
                    throw 'startup-assessment-state-changed-between-reads'
                }
                $matches=@($inventory.items|Where-Object { [string]$_.name -ceq $name })
                if($matches.Count -ne 1){throw 'startup-assessment-ambiguous-discovery-name'}
                $first=$matches[0]
                if([string]$first.name -cne $name -or
                   [long]$first.state_revision -ne [long]$canonical.revision -or
                   [bool]$first.live_missing -ne [bool]$missing -or
                   [bool]$first.active -ne [bool]($null -ne $canonical.active) -or
                   [bool]$first.pending_preserved -ne
                       [bool][IO.File]::Exists([string]$paths.pending)){
                    throw 'startup-assessment-discovery-to-source-drift'
                }
                $i++
                if($null -eq $canonical.active){
                    $out.Add([pscustomobject]@{
                        name=$name;active=$false;phase='none'
                        source=$null;plan=$null;result_is_authority=$false
                        production_execution_authorized=$false
                        production_mutation_authorized=$false
                    })
                    continue
                }
                $session=[pscustomobject]@{
                    ok=$true;paths=$paths;state=$canonical;lock_handle=$stream
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                }
                $locator=Read-CustomAppUserTxnJournalLocatorV010 -Session $session
                if(-not[bool]$locator.ok -or
                   [bool]$locator.journal_evidence_verified -or
                   [bool]$locator.production_mutation_authorized){
                    throw 'startup-assessment-unqualified-locator'
                }
                $rec=$locator.record
                $journal=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot (
                    [string]$rec.allowed_root) -StoreDirectory (
                    [string]$rec.store_directory)
                if($null -eq $journal -or -not[bool]$journal.ok -or
                   -not[bool]$journal.reloaded_from_persistent_store -or
                   [bool]$journal.production_mutation_authorized){
                    throw 'startup-assessment-unqualified-crash-journal'
                }
                $e=$journal.entry
                if([string]$e.name -cne $name -or
                   [string]$e.live_path -cne [string]$paths.live -or
                   [string]$e.consumption_id -cne [string]$canonical.active.consumption_id -or
                   [string]$e.transaction_id -cne [string]$canonical.active.transaction_id -or
                   [string]$journal.transaction_id -cne [string]$canonical.active.transaction_id -or
                   [string]$first.journal_phase -cne [string]$e.phase -or
                   [string]$e.entry_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
                   [long]$journal.revision -ne [long]$e.revision){
                    throw 'startup-assessment-triple-identity-or-journal-drift'
                }
                if($missing -and [string]$e.phase -in @('committed-clean','rollback-complete')){
                    throw 'startup-assessment-terminal-missing-live'
                }
                # Only the historical pure classification+plan construction:
                # neither routine performs a filesystem action or issues a
                # permit. No preflight or recovery-execution authorization.
                $classification=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $journal -ExpectedTransactionId ([string]$canonical.active.transaction_id)
                if(-not[bool]$classification.ok -or
                   [string]$classification.classification -ceq 'fail-closed'){
                    throw 'startup-assessment-manual-classification-required'
                }
                $plan=New-CustomAppProductionRecoveryPlanFromClassificationV010 -Classification $classification -StoreRead $journal -ExpectedTransactionId ([string]$canonical.active.transaction_id)
                $pc=Test-CustomAppProductionRecoveryPlanV010 $plan
                if(-not[bool]$pc.ok -or [bool]$plan.plan_is_authority -or
                   [bool]$plan.production_mutation_authorized -or
                   [string]$plan.phase -cne [string]$e.phase){
                    throw 'startup-assessment-plan-validation-failed'
                }
                # Bound fingerprint is informative, not a capability:
                # the future executor MUST reopen/recheck sources under locks.
                $sealedHash=Get-CustomAppUserTxnSha256V010 (
                    [Convert]::ToBase64String($sealed))
                $fp=Get-CustomAppUserTxnSha256V010 ((
                    @('startup-source-v1',$key,[string]$canonical.revision,
                      $sealedHash,[string]$rec.consumption_id,
                      [string]$rec.transaction_id,[string]$rec.nonce,
                      [string]$rec.store_directory,[string]$journal.revision,
                      [string]$e.entry_sha256,[string]$plan.plan_fingerprint) -join "`n"))
                # This in-process source object is produced ONLY by the sealed
                # registry, locator and append-only journal. Callers cannot
                # supply an equivalent on-disk JSON as executor authority.
                $source=[pscustomobject]@{
                    name=$name;live=[string]$paths.live
                    key=$key;state_revision=[long]$canonical.revision
                    consumption_id=[string]$canonical.active.consumption_id
                    transaction_id=[string]$canonical.active.transaction_id
                    nonce=[string]$canonical.active.nonce
                    allowed_root=[string]$rec.allowed_root
                    store_directory=[string]$rec.store_directory
                    journal_revision=[long]$journal.revision
                    journal_entry_sha256=[string]$e.entry_sha256
                    source_fingerprint=$fp
                    only_currentuser_dpapi_source=$true
                    revalidate_under_locks_before_any_execution=$true
                    result_is_authority=$false;production_execution_authorized=$false
                    production_mutation_authorized=$false
                }
                $out.Add([pscustomobject]@{
                    name=$name;active=$true;phase=[string]$e.phase
                    source=$source;plan=$plan;result_is_authority=$false
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
                # Detect mutation from non-cooperating same-user writers before
                # releasing the transaction lock; no attempted 'repair'.
                if((Get-CustomAppUserTxnSha256V010 (
                    [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)))) -cne $sealedHash){
                    throw 'startup-assessment-state-mutated-during-source-bind'
                }
            }finally{
                if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
                if($null -ne $stream){$stream.Dispose()}
            }
            [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $globalLock)
        }
        if($out.Count -ne [int]$inventory.inspected_count -or
           @($out|Where-Object{$_.active}).Count -ne [int]$inventory.active_count){
            throw 'startup-assessment-inventory-count-drift'
        }
        return [pscustomobject]@{
            schema=1;ok=$true;enrollment_found=$true
            inspected_count=$out.Count;active_count=[int]$inventory.active_count
            items=@($out.ToArray());only_sealed_registry_sources=$true
            journal_read_only=$true;result_is_authority=$false
            production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }finally{
        if($ownGlobalLock -and $null -ne $globalLock -and
           $null -ne $globalLock.lock_handle){
            $globalLock.lock_handle.Dispose()
        }
    }
}
function Test-CustomAppSealedStartupRecoveryAssessmentSelfTestV013 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'startup-assessment-cannot-activate-fullchain'
    }
    if(-not(Get-Command Get-CustomAppSealedStartupRecoveryAssessmentV013 -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'startup-assessment-source-bridge-not-in-candidate'
    }
    Write-Host 'SEALED_STARTUP_SOURCE_SELFTEST_PASS no_caller_json=true currentuser_dpapi=true read_only_plan=true global_and_app_lock=true execution_disabled=true'
}
