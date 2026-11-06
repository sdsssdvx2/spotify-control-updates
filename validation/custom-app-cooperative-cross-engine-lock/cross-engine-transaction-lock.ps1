# Validation-only cooperative cross-engine transaction lock.
# BOTH the normal legacy action entrypoints and future new-journal
# enrollment must use this one CurrentUser / FileShare.None lock.
# This does NOT activate the new FullChain or grant migration authority.
# Lock ownership lasts for the entire action, including crash recovery,
# persistence guard and (for CommitLast) post-apply bookkeeping.
function Open-CustomAppCrossEngineTransactionLockV010 {
    param([string]$HostedCiRoot)
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        throw 'cross-engine-lock-windows-only'
    }
    $root=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $hosted=$false
    if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot)){
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
            throw 'cross-engine-lock-root-override-not-hosted'
        }
        $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $root=[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')
        if(-not $root.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'cross-engine-lock-root-outside-runner'
        }
        $hosted=$true
    }
    if([string]::IsNullOrWhiteSpace($root) -or -not[IO.Path]::IsPathRooted($root) -or
       $root.StartsWith('\\') -or -not[IO.Directory]::Exists($root)){
        throw 'cross-engine-lock-local-profile-root-invalid'
    }
    $root=Assert-CustomAppUserTxnJournalLocalPathV010 -Path $root -RequireDirectory
    $directory=Join-Path $root 'SpotifyControlUpdates-CrossEngineLock'
    $path=Join-Path $directory 'current-user-exclusive.lock'
    $stream=$null
    try{
        [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $directory -Create)
        Assert-CustomAppUserTxnNoReparseV010 $path
        try {
            $stream=[IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        } catch [IO.IOException] {
            throw 'cross-engine-lock-busy-or-unavailable'
        }
        Assert-CustomAppUserTxnNoReparseV010 $path
        # An inherited private directory DACL ensures the newly created file
        # belongs to the current user. A preexisting altered file fails closed.
        $user=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $system='S-1-5-18'
        $acl=[IO.File]::GetAccessControl($path)
        if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $user){
            throw 'cross-engine-lock-file-owner-changed'
        }
        foreach($entry in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
            if($entry.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
               $entry.IdentityReference.Value -notin @($user,$system)){
                throw 'cross-engine-lock-file-acl-unexpected'
            }
        }
        return [pscustomobject]@{
            ok=$true;root=$root;lock_directory=$directory;lock_path=$path
            lock_handle=$stream;hosted_test_root=$hosted
            exclusive_cross_engine=$true
            production_mutation_authorized=$false
            production_execution_authorized=$false
            result_is_authority=$false
        }
    }catch{
        if($null -ne $stream){$stream.Dispose()}
        throw
    }
}

function Assert-CustomAppCrossEngineTransactionLockHeldV010 {
    param([Parameter(Mandatory=$true)]$Session)
    if($null -eq $Session -or -not[bool]$Session.ok -or
       -not[bool]$Session.exclusive_cross_engine -or
       $null -eq $Session.lock_handle -or
       -not[bool]$Session.lock_handle.CanRead -or
       -not[bool]$Session.lock_handle.CanWrite){
        throw 'cross-engine-lock-not-held'
    }
    if(-not[IO.File]::Exists([string]$Session.lock_path)){
        throw 'cross-engine-lock-file-disappeared'
    }
    Assert-CustomAppUserTxnNoReparseV010 ([string]$Session.lock_path)
    return $true
}

function Open-CustomAppNewJournalCrossEnginePreflightV010 {
    param([string]$HostedCiRoot)
    $s=$null
    try{
        $s=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $s)
        if([bool]$s.hosted_test_root){
            $proof=Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot ([string]$s.root)
        }else{
            $proof=Assert-CustomAppNewJournalLegacyLedgerClosedV011
        }
        if(-not[bool]$proof.ok -or [bool]$proof.safe_to_enroll -or
           -not[bool]$proof.requires_cross_engine_lock_before_enrollment){
            throw 'cross-engine-new-journal-legacy-not-proven-closed'
        }
        return [pscustomobject]@{
            ok=$true;session=$s;legacy_pending_absent=$true
            cross_engine_lock_held=$true
            may_start_new_engine=$false
            safe_to_enroll=$false
            production_mutation_authorized=$false
            production_execution_authorized=$false
            result_is_authority=$false
        }
    }catch{
        if($null -ne $s -and $null -ne $s.lock_handle){$s.lock_handle.Dispose()}
        throw
    }
}

function Test-CustomAppCrossEngineTransactionLockSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'cross-engine-lock-unexpectedly-enabled-production'
    }
    foreach($name in @('Open-CustomAppCrossEngineTransactionLockV010',
        'Assert-CustomAppCrossEngineTransactionLockHeldV010',
        'Open-CustomAppNewJournalCrossEnginePreflightV010')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('cross-engine-lock-missing '+$name)
        }
    }
    Write-Host 'CROSS_ENGINE_REAL_ACTION_LOCK_SELFTEST_PASS existing_legacy_actions_lock_scoped=true new_journal_preflight_locked_but_disabled=true'
}
