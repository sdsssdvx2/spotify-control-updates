# Recovery-only per-transaction DPAPI CurrentUser journal locator.
# Immutable one-file-per-consumption-ID. No caller-supplied recovery success,
# no auto-updating, no locator-based mutation authority. Held under the existing
# FileShare.None Windows user transaction lock during all operations.
function Assert-CustomAppUserTxnJournalLocalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$RequireDirectory)
    if(-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\')){
        throw 'user-journal-locator-path-must-be-local-absolute'
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($full.Length -lt 4 -or -not [IO.Path]::IsPathRooted($full) -or $full.StartsWith('\\')){
        throw 'user-journal-locator-path-root-invalid'
    }
    $cur=$full
    while(-not [string]::IsNullOrWhiteSpace($cur)){
        $item=Get-Item -LiteralPath $cur -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'user-journal-locator-ancestor-or-target-reparse'
        }
        $parent=[IO.Path]::GetDirectoryName($cur)
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $cur){break}
        $cur=$parent
    }
    if($RequireDirectory -and -not [IO.Directory]::Exists($full)){
        throw 'user-journal-locator-allowed-root-missing'
    }
    return $full
}
function Get-CustomAppUserTxnJournalLocatorFileV010 {
    param([Parameter(Mandatory=$true)]$Session)
    Assert-CustomAppUserTxnSessionV010 $Session
    if($null -eq $Session.state.active){throw 'user-journal-locator-active-reservation-required'}
    $id=[string]$Session.state.active.consumption_id
    if($id -cnotmatch '^[0-9a-f]{64}$'){throw 'user-journal-locator-consumption-id-invalid'}
    [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $Session.paths.container)
    [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $Session.paths.directory)
    return (Join-Path ([string]$Session.paths.directory) ('journal-'+$id+'.dpapi'))
}
function Test-CustomAppUserTxnJournalLocatorRecordV010 {
    param([Parameter(Mandatory=$true)]$Record,[Parameter(Mandatory=$true)]$Session)
    Assert-CustomAppUserTxnSessionV010 $Session
    $s=$Session.state
    $p=$Session.paths
    if($null -eq $s.active){throw 'user-journal-locator-no-active-reservation'}
    $props=@($Record.PSObject.Properties.Name | Sort-Object)
    $expect=@('allowed_root','bound_utc','consumption_id','key','live','name','nonce','schema','state_revision','store_directory','transaction_id' | Sort-Object)
    if(($props -join '|') -cne ($expect -join '|')){throw 'user-journal-locator-schema-fields-invalid'}
    if([int]$Record.schema -ne 1 -or [string]$Record.name -cne [string]$p.name -or
       [string]$Record.key -cne [string]$p.key -or [string]$Record.live -cne [string]$p.live -or
       [string]$Record.consumption_id -cne [string]$s.active.consumption_id -or
       [string]$Record.transaction_id -cne [string]$s.active.transaction_id -or
       [string]$Record.nonce -cne [string]$s.active.nonce -or
       [long]$Record.state_revision -ne [long]$s.revision -or
       [string]$Record.consumption_id -cnotmatch '^[0-9a-f]{64}$' -or
       [string]$Record.transaction_id -cnotmatch '^[0-9a-f]{64}$' -or
       [string]$Record.nonce -cnotmatch '^[0-9a-f]{32}$'){
        throw 'user-journal-locator-active-triple-id-binding-invalid'
    }
    $stamp=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Record.bound_utc,[ref]$stamp) -or
       $stamp -gt [DateTimeOffset]::UtcNow.AddMinutes(2)){
        throw 'user-journal-locator-bound-time-invalid'
    }
    $root=Assert-CustomAppUserTxnJournalLocalPathV010 -Path ([string]$Record.allowed_root) -RequireDirectory
    $store=Assert-CustomAppUserTxnJournalLocalPathV010 -Path ([string]$Record.store_directory)
    if($root -cne [string]$Record.allowed_root -or $store -cne [string]$Record.store_directory -or
       -not $store.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       $store.StartsWith(([string]$p.live+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       $store.StartsWith(([string]$p.directory+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'user-journal-locator-untrusted-store-mapping'
    }
    return $true
}
function Read-CustomAppUserTxnJournalLocatorV010 {
    param([Parameter(Mandatory=$true)]$Session)
    Assert-CustomAppUserTxnSessionV010 $Session
    $canonical=Read-CustomAppUserTxnStateV010 -Paths $Session.paths
    if(($canonical|ConvertTo-Json -Compress -Depth 8) -cne
       ($Session.state|ConvertTo-Json -Compress -Depth 8)){
        throw 'user-journal-locator-canonical-state-drift'
    }
    $path=Get-CustomAppUserTxnJournalLocatorFileV010 -Session $Session
    Assert-CustomAppUserTxnNoReparseV010 $path
    if(-not [IO.File]::Exists($path)){throw 'user-journal-locator-missing-fail-closed'}
    # DPAPI blobs can include non-authenticated metadata bytes. A checksum
    # over the ENTIRE sealed object detects even unused-header modifications.
    # Not intended to resist an attacker who can write as the same user.
    $wrapped=[IO.File]::ReadAllBytes($path)
    if($wrapped.Length -lt 96 -or $wrapped.Length -gt 32800){
        throw 'user-journal-locator-encrypted-file-size-invalid'
    }
    $sealed=New-Object byte[] ($wrapped.Length-32)
    [Array]::Copy($wrapped,32,$sealed,0,$sealed.Length)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$actual=$hash.ComputeHash($sealed)}finally{$hash.Dispose()}
    for($i=0;$i -lt 32;$i++){
        if($actual[$i] -ne $wrapped[$i]){
            throw 'user-journal-locator-whole-ciphertext-sha256-invalid'
        }
    }
    $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|UserTxnJournalLocator|v1|'+
       [string]$Session.paths.key+'|'+[string]$canonical.active.consumption_id))
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=$null
    try{
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($sealed,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $record=([Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop)
        [void](Test-CustomAppUserTxnJournalLocatorRecordV010 -Record $record -Session $Session)
        return [pscustomobject]@{
            ok=$true;record=$record;locator_only=$true
            production_mutation_authorized=$false
            production_execution_authorized=$false
            result_is_authority=$false;journal_evidence_verified=$false
        }
    }finally{if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}}
}
function Bind-CustomAppUserTxnJournalLocatorV010 {
    param([Parameter(Mandatory=$true)]$Session,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory)
    Assert-CustomAppUserTxnSessionV010 $Session
    if($null -eq $Session.state.active){throw 'user-journal-locator-bind-needs-reservation'}
    $canonical=Read-CustomAppUserTxnStateV010 $Session.paths
    if(($canonical|ConvertTo-Json -Compress -Depth 8) -cne
       ($Session.state|ConvertTo-Json -Compress -Depth 8)){
        throw 'user-journal-locator-bind-state-drift'
    }
    $root=Assert-CustomAppUserTxnJournalLocalPathV010 -Path $AllowedRoot -RequireDirectory
    $store=Assert-CustomAppUserTxnJournalLocalPathV010 -Path $JournalStoreDirectory
    $record=[pscustomobject]@{
        schema=1;name=[string]$Session.paths.name;live=[string]$Session.paths.live;key=[string]$Session.paths.key
        consumption_id=[string]$canonical.active.consumption_id
        transaction_id=[string]$canonical.active.transaction_id
        nonce=[string]$canonical.active.nonce
        state_revision=[long]$canonical.revision
        allowed_root=$root;store_directory=$store;bound_utc=[DateTimeOffset]::UtcNow.ToString('o')
    }
    [void](Test-CustomAppUserTxnJournalLocatorRecordV010 -Record $record -Session $Session)
    $path=Get-CustomAppUserTxnJournalLocatorFileV010 -Session $Session
    Assert-CustomAppUserTxnNoReparseV010 $path
    if([IO.File]::Exists($path)){
        $prior=Read-CustomAppUserTxnJournalLocatorV010 -Session $Session
        if([string]$prior.record.allowed_root -cne $root -or
           [string]$prior.record.store_directory -cne $store){
            throw 'user-journal-locator-rebind-denied'
        }
        return [pscustomobject]@{
            ok=$true;first_binding=$false;already_bound=$true
            locator_only=$true;production_mutation_authorized=$false;production_execution_authorized=$false
        }
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=[Text.Encoding]::UTF8.GetBytes(($record|ConvertTo-Json -Compress -Depth 7))
    $sealed=$null
    try{
        $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|UserTxnJournalLocator|v1|'+
            [string]$Session.paths.key+'|'+[string]$canonical.active.consumption_id))
        $sealed=[Security.Cryptography.ProtectedData]::Protect($plain,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($plain,0,$plain.Length)}
    # SHA256 prefix covers complete DPAPI ciphertext including metadata, not
    # only the authenticated plaintext. Write as ONE durable CreateNew file.
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$digest=$hash.ComputeHash($sealed)}finally{$hash.Dispose()}
    $wrapped=New-Object byte[] ($sealed.Length+32)
    [Array]::Copy($digest,0,$wrapped,0,32)
    [Array]::Copy($sealed,0,$wrapped,32,$sealed.Length)
    # CreateNew + Flush(true); never overwrite or erase on exception.
    Write-CustomAppUserTxnBytesV010 -Path $path -Bytes $wrapped
    $check=Read-CustomAppUserTxnJournalLocatorV010 -Session $Session
    if(-not [bool]$check.ok -or [string]$check.record.store_directory -cne $store -or
       [string]$check.record.allowed_root -cne $root){
        throw 'user-journal-locator-post-bind-readback-invalid'
    }
    return [pscustomobject]@{
        ok=$true;first_binding=$true;already_bound=$false
        locator_only=$true;production_mutation_authorized=$false;production_execution_authorized=$false
    }
}
function Commit-CustomAppUserTxnBoundJournalTerminalV010 {
    param([Parameter(Mandatory=$true)]$Session,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [switch]$HostedCiInterruptBeforeReplace)
    # No caller-provided journal path, identity, phase or success boolean.
    $saved=Read-CustomAppUserTxnJournalLocatorV010 -Session $Session
    $rec=$saved.record
    $args=@{
        Session=$Session;AllowedRoot=[string]$rec.allowed_root
        JournalStoreDirectory=[string]$rec.store_directory
        ExpectedConsumptionId=[string]$rec.consumption_id
        ExpectedTransactionId=[string]$rec.transaction_id
        LocalAppDataRoot=$LocalAppDataRoot;AppDataRoot=$AppDataRoot
        HostedCiInterruptBeforeReplace=[bool]$HostedCiInterruptBeforeReplace
    }
    $proof=Commit-CustomAppUserTxnVerifiedTerminalV011 @args
    if(-not [bool]$proof.ok -or -not [bool]$proof.single_use_consumption_durable){
        throw 'user-journal-locator-terminal-commit-not-durable'
    }
    return $proof
}
