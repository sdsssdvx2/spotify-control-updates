# Normal -Action Update compatibility barrier for the previously qualified
# hard-disabled journal/DPAPI transaction candidate.
# Existing legacy Pithaya/ivLyrics/Tagify transaction engine uses
# addon-last-transaction.json with "awaiting-apply"/CommitLast/RollbackLast.
# The new journal engine uses an encrypted per-user active/consumed ledger.
# Do NOT allow old multi-app swaps when any new engine enrollment exists,
# even if the new engine has no current active claim. Mixed two-engine
# recovery/retirement is NOT qualified.
#
# This preflight is read-only and does NOT authorize, stage or execute updates.
# It is deliberately before old journal rollback, persistence backups, network
# inventory, ZIP staging and first live rename. Rollback can only be resumed
# via the qualified new journal when enrolled.
function Assert-CustomAppNormalUpdateEngineExclusivityV010 {
    param([string]$HostedCiRoot)
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        throw 'normal-update-engine-gate-windows-only'
    }
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot)){
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
            throw 'normal-update-engine-gate-test-override-not-hosted'
        }
        $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $local=[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')
        if(-not$local.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'normal-update-engine-gate-test-root-outside-runner'
        }
    }
    if([string]::IsNullOrWhiteSpace($local) -or
       -not [IO.Path]::IsPathRooted($local) -or $local.StartsWith('\\') -or
       -not [IO.Directory]::Exists($local)){
        throw 'normal-update-engine-gate-local-profile-invalid'
    }
    $local=[IO.Path]::GetFullPath($local).TrimEnd('\','/')
    $base=Get-Item -LiteralPath $local -Force -ErrorAction Stop
    if(($base.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'normal-update-engine-gate-local-profile-reparse'
    }
    $enrollment=Join-Path $local 'SpotifyControlUpdates-CustomApp-State'
    # Presence of any *kind* of object blocks legacy mutation. It may be an
    # active claim, retired history, an incomplete private store enrollment,
    # inaccessible ACL or a malicious reparse point. No read or bypass.
    $present=@(Get-ChildItem -LiteralPath $local -Force -ErrorAction Stop |
        Where-Object { $_.Name -ceq 'SpotifyControlUpdates-CustomApp-State' })
    if($present.Count -gt 0 -or [IO.File]::Exists($enrollment) -or
       [IO.Directory]::Exists($enrollment) -or
       (Test-Path -LiteralPath $enrollment -ErrorAction SilentlyContinue)){
        throw 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
    }
    return [pscustomobject]@{
        ok=$true;engine='legacy';read_only_preflight=$true
        journal_engine_enrollment_seen=$false;production_mutation_authorized=$false
        result_is_authority=$false
    }
}
function Test-CustomAppNormalUpdateEngineExclusivitySelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'normal-update-engine-preflight-must-not-activate-fullchain'
    }
    if(-not(Get-Command Assert-CustomAppNormalUpdateEngineExclusivityV010 -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'normal-update-engine-gate-missing'
    }
    if(Get-Command Invoke-CustomAppNormalLegacyTransactionMigrationV010 -ErrorAction SilentlyContinue){
        throw 'unsafe-implicit-two-engine-migration-present'
    }
    Write-Host 'CUSTOM_APP_NORMAL_UPDATE_ENGINE_EXCLUSIVITY_SELFTEST_PASS no_implicit_migration=true fullchain_disabled=true'
}
