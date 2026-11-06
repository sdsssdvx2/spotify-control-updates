# Recovery-only, fail-closed opener for the narrow crash window where the
# canonical live app directory was renamed away by an in-progress atomic swap.
# It MUST NOT re-create the directory or assume that a missing live app equals
# a completed rollback. Only the qualified journal can authorize restoration.
function Get-CustomAppUserTxnMissingLivePathsV011 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LivePath,
        [string]$HostedCiRoot
    )
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        throw 'missing-live-recovery-windows-only'
    }
    if($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{1,63}$'){
        throw 'missing-live-recovery-invalid-name'
    }
    if(-not[IO.Path]::IsPathRooted($LivePath) -or $LivePath.StartsWith('\\')){
        throw 'missing-live-recovery-live-must-be-local-absolute'
    }
    $live=[IO.Path]::GetFullPath($LivePath).TrimEnd('\','/')
    if([IO.Directory]::Exists($live) -or [IO.File]::Exists($live) -or
       (Test-Path -LiteralPath $live -ErrorAction SilentlyContinue)){
        throw 'missing-live-recovery-live-path-present-use-ordinary-opener'
    }
    $parent=[IO.Path]::GetDirectoryName($live)
    if([string]::IsNullOrWhiteSpace($parent) -or -not[IO.Directory]::Exists($parent)){
        throw 'missing-live-recovery-parent-directory-missing'
    }
    [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $parent -RequireDirectory)
    if([string]::IsNullOrWhiteSpace($HostedCiRoot)){
        $root=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    }else{
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
            throw 'missing-live-recovery-override-only-hosted-ci'
        }
        $hostRoot=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $root=[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')
        if(-not $root.StartsWith(($hostRoot+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'missing-live-recovery-hosted-root-outside-runner'
        }
    }
    if([string]::IsNullOrWhiteSpace($root) -or -not[IO.Path]::IsPathRooted($root) -or
       $root.StartsWith('\\') -or -not[IO.Directory]::Exists($root)){
        throw 'missing-live-recovery-local-store-root-invalid'
    }
    $root=Assert-CustomAppUserTxnJournalLocalPathV010 -Path $root -RequireDirectory
    $container=Join-Path $root 'SpotifyControlUpdates-CustomApp-State'
    $key=Get-CustomAppUserTxnSha256V010 ($live.ToLowerInvariant())
    $directory=Join-Path $container $key
    if($live.StartsWith(($container+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       $container.StartsWith(($live+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'missing-live-recovery-live-overlaps-private-store'
    }
    return [pscustomobject]@{
        name=$Name.ToLowerInvariant();live=$live;root=$root
        container=$container;directory=$directory;key=$key
        lock=(Join-Path $directory 'exclusive.lock')
        state=(Join-Path $directory 'state.dpapi')
        pending=(Join-Path $directory 'state.pending')
        backup=(Join-Path $directory 'state.backup')
    }
}
function Open-CustomAppUserTxnMissingLiveRecoveryV011 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LivePath,
        [string]$HostedCiRoot
    )
    $handle=$null
    try {
        $p=Get-CustomAppUserTxnMissingLivePathsV011 -Name $Name -LivePath $LivePath -HostedCiRoot $HostedCiRoot
        # Neither the private store nor its lock may be enrolled by a crash
        # recovery attempt. Refuse damaged/missing enrolled state.
        [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $p.container)
        [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $p.directory)
        foreach($f in @($p.lock,$p.state,$p.pending,$p.backup)){
            Assert-CustomAppUserTxnNoReparseV010 $f
        }
        if(-not[IO.File]::Exists($p.lock) -or -not[IO.File]::Exists($p.state)){
            throw 'missing-live-recovery-private-lock-or-canonical-state-absent'
        }
        # Open (NEVER OpenOrCreate) + FileShare.None: same exclusive ownership
        # and replay rules as a normal qualified transaction session.
        $handle=[IO.File]::Open([string]$p.lock,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Assert-CustomAppUserTxnNoReparseV010 $p.lock
        $state=Read-CustomAppUserTxnStateV010 -Paths $p
        if($null -eq $state.active){
            throw 'missing-live-recovery-no-active-reservation'
        }
        $session=[pscustomobject]@{
            ok=$true;paths=$p;state=$state;lock_handle=$handle
            missing_live_recovery_only=$true
            pending_unresolved=[bool][IO.File]::Exists($p.pending)
            production_mutation_authorized=$false
            production_execution_authorized=$false
        }
        $locator=Read-CustomAppUserTxnJournalLocatorV010 -Session $session
        if(-not[bool]$locator.ok -or [bool]$locator.journal_evidence_verified -or
           [bool]$locator.production_mutation_authorized -or
           [string]$locator.record.transaction_id -cne [string]$state.active.transaction_id){
            throw 'missing-live-recovery-immutable-journal-locator-invalid'
        }
        if([IO.Directory]::Exists($p.live) -or
           [IO.File]::Exists($p.live) -or
           (Test-Path -LiteralPath $p.live -ErrorAction SilentlyContinue)){
            throw 'missing-live-recovery-live-reappeared-race'
        }
        return [pscustomobject]@{
            ok=$true;session=$session;locator=$locator
            live_missing=$true;recovery_only=$true
            pending_unresolved=[bool]$session.pending_unresolved
            journal_evidence_verified=$false
            restored_live_verified=$false
            filesystem_changes=$false
            production_mutation_authorized=$false
            production_execution_authorized=$false
        }
    }catch{
        if($null -ne $handle){$handle.Dispose()}
        throw
    }
}
