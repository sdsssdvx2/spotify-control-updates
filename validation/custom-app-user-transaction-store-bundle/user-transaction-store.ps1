# Candidate-only durable user transaction registry. NO live mutation, no permit issuance,
# no Spicetify execution and no implicit authorization. Promotion requires an independently
# verified terminal-journal adapter, retained evidence and full-chain integration.
# Windows PowerShell 5.1 / .NET Framework, per-user DPAPI, fail-closed on corruption.

function Get-CustomAppUserTxnSha256V010 {
    param([Parameter(Mandatory=$true)][string]$Text)
    $h=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Assert-CustomAppUserTxnNoReparseV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(Test-Path -LiteralPath $Path) {
        $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'user-store-reparse-denied' }
    }
}
function Get-CustomAppUserTxnPathsV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$LivePath,[string]$HostedCiRoot)
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'user-store-windows-only' }
    if($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{1,63}$') { throw 'user-store-invalid-name' }
    if(-not[IO.Path]::IsPathRooted($LivePath) -or $LivePath.StartsWith('\\')) { throw 'user-store-nonlocal-live-path' }
    $live=[IO.Path]::GetFullPath($LivePath).TrimEnd('\','/')
    if(-not[IO.Directory]::Exists($live)) { throw 'user-store-live-folder-missing' }
    Assert-CustomAppUserTxnNoReparseV010 -Path $live
    if([string]::IsNullOrWhiteSpace($HostedCiRoot)) {
        $root=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    } else {
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted') { throw 'user-store-test-override-not-hosted-ci' }
        $hostRoot=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $root=[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')
        if(-not $root.StartsWith(($hostRoot+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'user-store-test-root-not-under-runner-temp' }
    }
    if([string]::IsNullOrWhiteSpace($root) -or -not[IO.Path]::IsPathRooted($root) -or $root.StartsWith('\\')) { throw 'user-store-invalid-local-root' }
    $root=[IO.Path]::GetFullPath($root).TrimEnd('\','/')
    if(-not[IO.Directory]::Exists($root)) { throw 'user-store-local-root-missing' }
    Assert-CustomAppUserTxnNoReparseV010 -Path $root
    $container=Join-Path $root 'SpotifyControlUpdates-CustomApp-State'
    $key=Get-CustomAppUserTxnSha256V010 ($live.ToLowerInvariant())
    $dir=Join-Path $container $key
    if($live.StartsWith(($container+'\'),[StringComparison]::OrdinalIgnoreCase) -or $container.StartsWith(($live+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'user-store-live-overlaps-registry' }
    return [pscustomobject]@{name=$Name.ToLowerInvariant();live=$live;root=$root;container=$container;directory=$dir;key=$key;lock=(Join-Path $dir 'exclusive.lock');state=(Join-Path $dir 'state.dpapi');pending=(Join-Path $dir 'state.pending');backup=(Join-Path $dir 'state.backup')}
}
function Assert-CustomAppUserTxnPrivateDirectoryV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$Create)
    Assert-CustomAppUserTxnNoReparseV010 $Path
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $system=New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
    $created=$false
    if(-not[IO.Directory]::Exists($Path)) {
        if(-not $Create) { throw 'user-store-private-directory-missing' }
        $dacl=New-Object Security.AccessControl.DirectorySecurity
        $dacl.SetOwner($sid)
        $dacl.SetAccessRuleProtection($true,$false)
        $inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach($who in @($sid,$system)) {
            $rule=[Security.AccessControl.FileSystemAccessRule]::new($who,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
            $dacl.AddAccessRule($rule)
        }
        [IO.Directory]::CreateDirectory($Path,$dacl) | Out-Null
        $created=$true
    }
    Assert-CustomAppUserTxnNoReparseV010 $Path
    $acl=[IO.Directory]::GetAccessControl($Path)
    if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid.Value) { throw 'user-store-private-directory-owner-or-inheritance-invalid' }
    $allowed=@($sid.Value,$system.Value)
    $hasCurrent=$false
    foreach($entry in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($entry.IsInherited -or $entry.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $entry.IdentityReference.Value -notin $allowed) { throw 'user-store-private-directory-unexpected-ace' }
        if($entry.IdentityReference.Value -ceq $sid.Value) { $hasCurrent=$true }
    }
    if(-not $hasCurrent) { throw 'user-store-private-directory-current-user-access-missing' }
    return $created
}
function Get-CustomAppUserTxnEntropyV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    return [Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|UserTxn|v1|'+[string]$Paths.key))
}
function Test-CustomAppUserTxnStateV010 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Paths)
    if($null -eq $State -or [int]$State.schema -ne 1 -or [string]$State.name -cne [string]$Paths.name -or
       [string]$State.live -cne [string]$Paths.live -or [string]$State.key -cne [string]$Paths.key -or [long]$State.revision -lt 0) { throw 'user-store-state-identity-invalid' }
    $props=@($State.PSObject.Properties.Name|Sort-Object)
    $expected=@('active','consumed','created_utc','key','live','name','revision','schema','updated_utc'|Sort-Object)
    if(($props -join '|') -cne ($expected -join '|')) { throw 'user-store-state-fields-invalid' }
    if($null -eq $State.consumed -or @($State.consumed).Count -gt 4096) { throw 'user-store-consumed-list-invalid' }
    $unique=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($id in @($State.consumed)) {
        if([string]$id -cnotmatch '^[0-9a-f]{64}$' -or -not $unique.Add([string]$id)) { throw 'user-store-consumed-identity-invalid' }
    }
    if($null -ne $State.active) {
        $a=$State.active
        if([string]$a.consumption_id -cnotmatch '^[0-9a-f]{64}$' -or [string]$a.transaction_id -cnotmatch '^[0-9a-f]{64}$' -or
           [string]$a.nonce -cnotmatch '^[0-9a-f]{32}$' -or [string]$a.state -cne 'reserved' -or
           $unique.Contains([string]$a.consumption_id)) { throw 'user-store-active-identity-invalid' }
    }
    return $true
}
function Protect-CustomAppUserTxnStateV010 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Paths)
    [void](Test-CustomAppUserTxnStateV010 -State $State -Paths $Paths)
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=[Text.Encoding]::UTF8.GetBytes(($State|ConvertTo-Json -Compress -Depth 8))
    try { return [Security.Cryptography.ProtectedData]::Protect($plain,(Get-CustomAppUserTxnEntropyV010 $Paths),[Security.Cryptography.DataProtectionScope]::CurrentUser) }
    finally { [Array]::Clear($plain,0,$plain.Length) }
}
function Read-CustomAppUserTxnStateV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    Assert-CustomAppUserTxnNoReparseV010 $Paths.state
    if(-not[IO.File]::Exists($Paths.state)) { throw 'user-store-canonical-state-missing' }
    $sealed=[IO.File]::ReadAllBytes([string]$Paths.state)
    if($sealed.Length -lt 64 -or $sealed.Length -gt 262144) { throw 'user-store-canonical-state-size-invalid' }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=$null
    try {
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($sealed,(Get-CustomAppUserTxnEntropyV010 $Paths),[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $data=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
        [void](Test-CustomAppUserTxnStateV010 -State $data -Paths $Paths)
        return $data
    } finally { if($null -ne $plain) { [Array]::Clear($plain,0,$plain.Length) } }
}
function Write-CustomAppUserTxnBytesV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][byte[]]$Bytes)
    Assert-CustomAppUserTxnNoReparseV010 $Path
    $s=$null
    try {
        $s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $s.Write($Bytes,0,$Bytes.Length)
        $s.Flush($true)
    } finally { if($null -ne $s) { $s.Dispose() } }
}
function Open-CustomAppUserTxnStoreV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$LivePath,[string]$HostedCiRoot,[switch]$Initialize)
    $lockHandle=$null
    try {
        $p=Get-CustomAppUserTxnPathsV010 -Name $Name -LivePath $LivePath -HostedCiRoot $HostedCiRoot
        $newContainer=Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $p.container -Create:$Initialize
        $newDirectory=Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $p.directory -Create:$Initialize
        foreach($file in @($p.lock,$p.state,$p.pending,$p.backup)) { Assert-CustomAppUserTxnNoReparseV010 $file }
        $lockHandle=[IO.File]::Open([string]$p.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Assert-CustomAppUserTxnNoReparseV010 $p.lock
        if(-not[IO.File]::Exists($p.state)) {
            if(-not $Initialize -or -not $newDirectory -or [IO.File]::Exists($p.pending) -or [IO.File]::Exists($p.backup)) { throw 'user-store-missing-state-refuses-reenrollment' }
            $now=[DateTimeOffset]::UtcNow.ToString('o')
            $initial=[pscustomobject]@{schema=1;name=$p.name;live=$p.live;key=$p.key;revision=[long]0;created_utc=$now;updated_utc=$now;active=$null;consumed=@()}
            $sealed=Protect-CustomAppUserTxnStateV010 -State $initial -Paths $p
            Write-CustomAppUserTxnBytesV010 -Path $p.state -Bytes $sealed
        }
        $state=Read-CustomAppUserTxnStateV010 -Paths $p
        if([IO.File]::Exists($p.pending)) {
            # A pending write that was NOT promoted by File.Replace cannot be authoritative.
            # The existing DPAPI-authenticated canonical state must validate first.
            Assert-CustomAppUserTxnNoReparseV010 $p.pending
            [IO.File]::Delete($p.pending)
            if([IO.File]::Exists($p.pending)) { throw 'user-store-pending-discard-failed' }
        }
        $session=[pscustomobject]@{ok=$true;paths=$p;state=$state;lock_handle=$lockHandle;production_mutation_authorized=$false;production_execution_authorized=$false}
        return $session
    } catch {
        if($null -ne $lockHandle) { $lockHandle.Dispose() }
        throw
    }
}
function Assert-CustomAppUserTxnSessionV010 {
    param([Parameter(Mandatory=$true)]$Session)
    if($null -eq $Session -or -not[bool]$Session.ok -or $null -eq $Session.lock_handle -or
       -not[bool]$Session.lock_handle.CanRead -or -not[bool]$Session.lock_handle.CanWrite) { throw 'user-store-lock-not-held' }
    [void](Test-CustomAppUserTxnStateV010 -State $Session.state -Paths $Session.paths)
}
function Save-CustomAppUserTxnStoreV010 {
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)]$NextState,[switch]$HostedCiInterruptBeforeReplace)
    Assert-CustomAppUserTxnSessionV010 $Session
    $p=$Session.paths
    [void](Test-CustomAppUserTxnStateV010 -State $NextState -Paths $p)
    if([long]$NextState.revision -ne ([long]$Session.state.revision+1)) { throw 'user-store-nonmonotonic-revision' }
    $current=Read-CustomAppUserTxnStateV010 $p
    if([long]$current.revision -ne [long]$Session.state.revision) { throw 'user-store-canonical-revision-drift' }
    if([IO.File]::Exists($p.pending)) { throw 'user-store-unresolved-pending' }
    Assert-CustomAppUserTxnNoReparseV010 $p.backup
    $sealed=Protect-CustomAppUserTxnStateV010 -State $NextState -Paths $p
    Write-CustomAppUserTxnBytesV010 -Path $p.pending -Bytes $sealed
    if($HostedCiInterruptBeforeReplace) {
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted') { throw 'user-store-fault-injection-not-hosted-ci' }
        throw 'user-store-injected-crash-before-atomic-replace'
    }
    [IO.File]::Replace([string]$p.pending,[string]$p.state,[string]$p.backup)
    $reloaded=Read-CustomAppUserTxnStateV010 $p
    if([long]$reloaded.revision -ne [long]$NextState.revision -or [string]$reloaded.updated_utc -cne [string]$NextState.updated_utc) { throw 'user-store-atomic-write-readback-invalid' }
    $Session.state=$reloaded
    return [pscustomobject]@{ok=$true;revision=[long]$reloaded.revision;active=($null -ne $reloaded.active);production_mutation_authorized=$false}
}
function Reserve-CustomAppUserTxnIdV010 {
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)][string]$ConsumptionId,[Parameter(Mandatory=$true)][string]$TransactionId,[Parameter(Mandatory=$true)][string]$Nonce,[switch]$HostedCiInterruptBeforeReplace)
    Assert-CustomAppUserTxnSessionV010 $Session
    if($ConsumptionId -cnotmatch '^[0-9a-f]{64}$' -or $TransactionId -cnotmatch '^[0-9a-f]{64}$' -or $Nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'user-store-reservation-ids-invalid' }
    if($null -ne $Session.state.active) { throw 'user-store-existing-active-transaction-requires-recovery' }
    if(@($Session.state.consumed) -ccontains $ConsumptionId) { throw 'user-store-consumption-replay-denied' }
    $next=($Session.state|ConvertTo-Json -Depth 8|ConvertFrom-Json)
    $next.revision=[long]$next.revision+1
    $next.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
    $next.active=[pscustomobject]@{consumption_id=$ConsumptionId;transaction_id=$TransactionId;nonce=$Nonce;state='reserved';created_utc=$next.updated_utc}
    return Save-CustomAppUserTxnStoreV010 -Session $Session -NextState $next -HostedCiInterruptBeforeReplace:$HostedCiInterruptBeforeReplace
}
# Deliberately NO terminal retirement/consumption function here. An immutable
# authenticated journal and verified terminal evidence MUST be integrated first.
# No caller-supplied boolean/phase alone may erase the active marker.
