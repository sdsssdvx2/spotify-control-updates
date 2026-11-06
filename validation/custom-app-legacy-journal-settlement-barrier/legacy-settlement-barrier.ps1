# Validation-only legacy-vs-new-journal settlement boundary.
# Previous normal Update-AutoApps already refuses to start legacy mutation
# when the per-user DPAPI journal engine enrollment exists. CommitLast and
# RollbackLast are INDEPENDENT external actions: they must refuse the same
# conflict, before reading/normalizing or mutating the old ledger.
#
# The complementary NEW-engine pre-enrollment inspector denies any unresolved
# legacy addon-last-transaction.json, regardless of its schema, contents or
# phase. This is read-only; preflight alone does not solve concurrent races
# or authorize a future normal new-engine update.
function Assert-CustomAppLegacySettlementExclusiveV011 {
    [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)
    return [pscustomobject]@{
        ok=$true;legacy_settlement_preflight=$true
        checked_new_engine_enrollment=$true
        result_is_authority=$false
        production_mutation_authorized=$false
        production_execution_authorized=$false
    }
}

function Assert-CustomAppNewJournalLegacyLedgerClosedV011 {
    param(
        [string]$LocalAppDataRoot,
        [string]$TransactionPath
    )
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        throw 'new-journal-legacy-preflight-windows-only'
    }
    if([string]::IsNullOrWhiteSpace($LocalAppDataRoot)){
        $LocalAppDataRoot=[string]$env:LOCALAPPDATA
    }else{
        # Caller-supplied roots are only for isolated hosted Windows CI. In
        # production the canonical root is the current user's LocalAppData.
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
            throw 'new-journal-legacy-preflight-root-override-not-hosted'
        }
        $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $rootCandidate=[IO.Path]::GetFullPath($LocalAppDataRoot).TrimEnd('\','/')
        if(-not $rootCandidate.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'new-journal-legacy-preflight-root-outside-hosted-runner'
        }
    }
    if([string]::IsNullOrWhiteSpace($LocalAppDataRoot) -or
       -not[IO.Path]::IsPathRooted($LocalAppDataRoot) -or
       $LocalAppDataRoot.StartsWith('\\')){
        throw 'new-journal-legacy-preflight-root-invalid'
    }
    $root=Assert-CustomAppUserTxnJournalLocalPathV010 -Path $LocalAppDataRoot -RequireDirectory
    $legacyRoot=Join-Path $root 'SpotifyControl'
    $expected=Join-Path $legacyRoot 'addon-last-transaction.json'
    if([string]::IsNullOrWhiteSpace($TransactionPath)){
        $TransactionPath=$expected
    }
    if(-not[IO.Path]::IsPathRooted($TransactionPath) -or
       $TransactionPath.StartsWith('\\') -or
       -not[IO.Path]::GetFullPath($TransactionPath).Equals(
          [IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'new-journal-legacy-preflight-ledger-path-not-canonical'
    }
    [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $TransactionPath)
    # Presence of a file, directory, inaccessible object or reparse point
    # means the legacy engine may have uncommitted after-apply code. NEVER
    # parse or erase it, and NEVER re-enroll or infer it is already terminal.
    $present=@()
    if([IO.Directory]::Exists($legacyRoot)){
        $present=@(Get-ChildItem -LiteralPath $legacyRoot -Force -ErrorAction Stop |
                   Where-Object { $_.Name -ieq 'addon-last-transaction.json' })
    }elseif([IO.File]::Exists($legacyRoot) -or
           (Test-Path -LiteralPath $legacyRoot -ErrorAction SilentlyContinue)){
        throw 'new-journal-legacy-preflight-legacy-root-not-directory'
    }
    if($present.Count -gt 0 -or
       [IO.File]::Exists($TransactionPath) -or
       [IO.Directory]::Exists($TransactionPath) -or
       (Test-Path -LiteralPath $TransactionPath -ErrorAction SilentlyContinue)){
        throw 'new-journal-legacy-preflight-unresolved-legacy-transaction-must-finish-first'
    }
    return [pscustomobject]@{
        ok=$true;unresolved_legacy_ledger_detected=$false
        safe_to_enroll=$false
        requires_cross_engine_lock_before_enrollment=$true
        legacy_transaction_not_mutated=$true
        result_is_authority=$false
        production_mutation_authorized=$false
        production_execution_authorized=$false
    }
}

function Test-CustomAppLegacySettlementBarrierSelfTestV011 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'unqualified production FullChain enabled by legacy barrier'
    }
    foreach($n in @('Assert-CustomAppNormalUpdateEngineExclusivityV010',
                    'Assert-CustomAppLegacySettlementExclusiveV011',
                    'Assert-CustomAppNewJournalLegacyLedgerClosedV011')){
        if(-not(Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('missing two-way legacy barrier '+$n)
        }
    }
    Write-Host 'CUSTOM_APP_LEGACY_SETTLEMENT_BARRIER_SELFTEST_PASS old_CommitLast_RollbackLast_prechecked=true new_enrollment_requires_cross_engine_lock=true'
}
