# Candidate-only immutable CurrentUser Spicetify provenance. Not execution authority.
# This module never invokes spicetify.exe, starts Spotify, or enables FullChain.
function Assert-CustomAppSpicetifyPinLocksV016 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [string]$HostedCiRoot)
    [void](Assert-CustomAppUserTxnSessionV010 -Session $Session)
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $HeldCrossEngineSession)
    $root=[IO.Path]::GetFullPath([string]$Session.paths.root).TrimEnd('\','/')
    $global=[IO.Path]::GetFullPath([string]$HeldCrossEngineSession.root).TrimEnd('\','/')
    if(-not $root.Equals($global,[StringComparison]::OrdinalIgnoreCase)){
        throw 'spicetify-pin-global-session-root-mismatch'
    }
    if([bool]$HeldCrossEngineSession.hosted_test_root){
        if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
           [string]::IsNullOrWhiteSpace($HostedCiRoot) -or
           -not $root.Equals([IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/'),
                [StringComparison]::OrdinalIgnoreCase) -or
           -not $root.StartsWith(([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')+'\'),
                [StringComparison]::OrdinalIgnoreCase)){
            throw 'spicetify-pin-hosted-root-not-qualified'
        }
    }else{
        $expected=[IO.Path]::GetFullPath(
            [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        ).TrimEnd('\','/')
        if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot) -or
           -not $root.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){
            throw 'spicetify-pin-profile-not-current-user'
        }
    }
    foreach($pair in @(
        [pscustomobject]@{handle=$HeldCrossEngineSession.lock_handle;path=(Join-Path (Join-Path $root 'SpotifyControlUpdates-CrossEngineLock') 'current-user-exclusive.lock')},
        [pscustomobject]@{handle=$Session.lock_handle;path=([string]$Session.paths.lock)}
    )){
        if($pair.handle -isnot [IO.FileStream] -or
           -not[IO.Path]::GetFullPath([string]$pair.handle.Name).Equals(
                [IO.Path]::GetFullPath([string]$pair.path),[StringComparison]::OrdinalIgnoreCase)){
            throw 'spicetify-pin-lock-file-handle-identity-invalid'
        }
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$pair.path)
        $probe=$null;$blocked=$false
        try{$probe=[IO.File]::Open([string]$pair.path,[IO.FileMode]::Open,
            [IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)}
        catch [IO.IOException]{$blocked=$true}
        finally{if($null-ne$probe){$probe.Dispose()}}
        if(-not$blocked){throw 'spicetify-pin-lock-not-exclusive'}
    }
    [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $Session.paths.directory)
    $current=Read-CustomAppUserTxnStateV010 -Paths $Session.paths
    if(($current|ConvertTo-Json -Compress -Depth 8) -cne
       ($Session.state|ConvertTo-Json -Compress -Depth 8)){
        throw 'spicetify-pin-canonical-state-changed'
    }
    return $true
}
function Get-CustomAppSpicetifyPinFileV016 {
    param([Parameter(Mandatory=$true)]$Session)
    [void](Test-CustomAppUserTxnStateV010 -State $Session.state -Paths $Session.paths)
    if($null-eq$Session.state.active){throw 'spicetify-pin-active-transaction-required'}
    $id=[string]$Session.state.active.consumption_id
    if($id -cnotmatch '^[0-9a-f]{64}$'){throw 'spicetify-pin-invalid-consumption'}
    return Join-Path ([string]$Session.paths.directory) ('spicetify-pin-'+$id+'.dpapi')
}


function Read-CustomAppSpicetifySealedPinV016 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [string]$HostedCiRoot,[string]$HostedCiLocalAppDataRoot,
          [string]$HostedCiAppDataRoot)
    [void](Assert-CustomAppSpicetifyPinLocksV016 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot)
    $file=Get-CustomAppSpicetifyPinFileV016 -Session $Session
    Assert-CustomAppUserTxnNoReparseV010 -Path $file
    if(-not[IO.File]::Exists($file)){
        return [pscustomobject]@{
            ok=$false;reason='spicetify-pin-not-enrolled';pin_found=$false
            unchanged=$false;known_official_executable=$false
            production_execution_authorized=$false;production_mutation_authorized=$false
            result_is_authority=$false
        }
    }
    $wrapped=[IO.File]::ReadAllBytes($file)
    if($wrapped.Length -lt 96 -or $wrapped.Length -gt 32768){
        throw 'spicetify-pin-encrypted-size-invalid'
    }
    $sealed=New-Object byte[] ($wrapped.Length-32)
    [Array]::Copy($wrapped,32,$sealed,0,$sealed.Length)
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$checksum=$hasher.ComputeHash($sealed)}finally{$hasher.Dispose()}
    for($i=0;$i -lt 32;$i++){
        if($checksum[$i] -ne $wrapped[$i]){throw 'spicetify-pin-whole-ciphertext-hash-invalid'}
    }
    $state=$Session.state
    $key=[string]$Session.paths.key
    $cid=[string]$state.active.consumption_id
    $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|SpicetifyPin|v1|'+$key+'|'+$cid))
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=$null
    try{
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($sealed,$entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $pin=([Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop)
    }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
    $required=@('schema','name','live','key','consumption_id','transaction_id',
        'nonce','state_revision','allowed_root','store_directory',
        'prepared_entry_sha256','prepared_revision','exe_sha256','config_sha256',
        'exe_bytes','config_bytes','executable_path','config_path',
        'observation_fingerprint','official_release','recorded_utc')
    if((@($pin.PSObject.Properties.Name|Sort-Object) -join '|') -cne
       (@($required|Sort-Object) -join '|') -or [int]$pin.schema -ne 1){
        throw 'spicetify-pin-exact-schema-invalid'
    }
    if([string]$pin.name -cne [string]$Session.paths.name -or
       [string]$pin.live -cne [string]$Session.paths.live -or
       [string]$pin.key -cne $key -or
       [string]$pin.consumption_id -cne $cid -or
       [string]$pin.transaction_id -cne [string]$state.active.transaction_id -or
       [string]$pin.nonce -cne [string]$state.active.nonce -or
       [long]$pin.state_revision -ne [long]$state.revision -or
       [long]$pin.prepared_revision -ne 0 -or
       [string]$pin.official_release -cne 'spicetify/cli-v2.46.4-windows-x64' -or
       [string]$pin.exe_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db' -or
       [string]$pin.config_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
       [string]$pin.prepared_entry_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
       [string]$pin.observation_fingerprint -cnotmatch '^[0-9a-f]{64}$'){
        throw 'spicetify-pin-triple-identity-revision-or-official-sha-invalid'
    }
    $locator=Read-CustomAppUserTxnJournalLocatorV010 -Session $Session
    if(-not[bool]$locator.ok -or
       [string]$pin.allowed_root -cne [string]$locator.record.allowed_root -or
       [string]$pin.store_directory -cne [string]$locator.record.store_directory -or
       [string]$pin.transaction_id -cne [string]$locator.record.transaction_id -or
       [string]$pin.consumption_id -cne [string]$locator.record.consumption_id -or
       [string]$pin.nonce -cne [string]$locator.record.nonce){
        throw 'spicetify-pin-durable-locator-drift'
    }
    $journal=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$pin.allowed_root) -StoreDirectory ([string]$pin.store_directory)
    if(-not[bool]$journal.ok -or
       [string]$journal.transaction_id -cne [string]$pin.transaction_id -or
       [string]$journal.entry.consumption_id -cne [string]$pin.consumption_id -or
       [string]$journal.entry.name -cne [string]$pin.name -or
       [string]$journal.entry.live_path -cne [string]$pin.live -or
       [long]$journal.history_count -lt 1){
        throw 'spicetify-pin-append-only-journal-identity-drift'
    }
    $jpaths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot ([string]$pin.allowed_root) -StoreDirectory ([string]$pin.store_directory)
    $zeroFile=Join-Path ([string]$jpaths.history) ('{0:D20}-{1}.json' -f 0,[string]$pin.prepared_entry_sha256)
    if(-not[IO.File]::Exists($zeroFile)){throw 'spicetify-pin-prepared-history-absent'}
    $zero=ConvertFrom-CustomAppProductionCrashJournalFileV010 -AllowedRoot ([string]$pin.allowed_root) -Path $zeroFile
    if([long]$zero.entry.revision -ne 0 -or
       [string]$zero.entry.phase -cne 'prepared' -or
       [string]$zero.entry.entry_sha256 -cne [string]$pin.prepared_entry_sha256 -or
       [string]$zero.entry.transaction_id -cne [string]$journal.transaction_id){
        throw 'spicetify-pin-prepared-history-anchor-drift'
    }
    $obs=Get-CustomAppSpicetifyPassiveObservationV015 -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot -HeldCrossEngineSession $HeldCrossEngineSession
    if(-not[bool]$obs.ok -or
       [string]$obs.exe_sha256 -cne [string]$pin.exe_sha256 -or
       [string]$obs.config_sha256 -cne [string]$pin.config_sha256 -or
       [string]$obs.executable_path -cne [string]$pin.executable_path -or
       [string]$obs.config_path -cne [string]$pin.config_path -or
       [long]$obs.exe_bytes -ne [long]$pin.exe_bytes -or
       [long]$obs.config_bytes -ne [long]$pin.config_bytes -or
       [string]$obs.observation_fingerprint -cne [string]$pin.observation_fingerprint){
        throw 'spicetify-pin-executable-config-or-path-changed'
    }
    $again=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$pin.allowed_root) -StoreDirectory ([string]$pin.store_directory)
    if(-not[bool]$again.ok -or
       [long]$again.revision -ne [long]$journal.revision -or
       [string]$again.entry.entry_sha256 -cne [string]$journal.entry.entry_sha256){
        throw 'spicetify-pin-journal-changed-during-observation'
    }
    [void](Assert-CustomAppSpicetifyPinLocksV016 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot)
    return [pscustomobject]@{
        ok=$true;reason='sealed-official-exe-and-config-unchanged'
        pin_found=$true;unchanged=$true;known_official_executable=$true
        transaction_id=[string]$pin.transaction_id
        consumption_id=[string]$pin.consumption_id
        state_revision=[long]$pin.state_revision
        journal_revision=[long]$journal.revision
        journal_entry_sha256=[string]$journal.entry.entry_sha256
        exe_sha256=[string]$pin.exe_sha256;config_sha256=[string]$pin.config_sha256
        observation_fingerprint=[string]$pin.observation_fingerprint
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}


function Save-CustomAppSpicetifyPreMutationPinV016 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [string]$HostedCiRoot,[string]$HostedCiLocalAppDataRoot,
          [string]$HostedCiAppDataRoot)
    [void](Assert-CustomAppSpicetifyPinLocksV016 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot)
    if($null-eq$Session.state.active -or
       [IO.File]::Exists([string]$Session.paths.pending)){
        throw 'spicetify-pin-enrollment-requires-reserved-state-no-pending'
    }
    $loc=Read-CustomAppUserTxnJournalLocatorV010 -Session $Session
    if(-not[bool]$loc.ok -or
       [long]$loc.record.state_revision -ne [long]$Session.state.revision){
        throw 'spicetify-pin-current-sealed-locator-required'
    }
    $rec=$loc.record
    $jr=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$rec.allowed_root) -StoreDirectory ([string]$rec.store_directory)
    if(-not[bool]$jr.ok -or [long]$jr.revision -ne 0 -or
       [long]$jr.history_count -ne 1 -or
       [string]$jr.entry.phase -cne 'prepared' -or
       [string]$jr.entry.transaction_id -cne [string]$Session.state.active.transaction_id -or
       [string]$jr.entry.consumption_id -cne [string]$Session.state.active.consumption_id -or
       [string]$jr.entry.name -cne [string]$Session.paths.name -or
       [string]$jr.entry.live_path -cne [string]$Session.paths.live){
        throw 'spicetify-pin-enrollment-only-before-first-atomic-mutation'
    }
    $file=Get-CustomAppSpicetifyPinFileV016 -Session $Session
    Assert-CustomAppUserTxnNoReparseV010 -Path $file
    if([IO.File]::Exists($file)){throw 'spicetify-pin-immutable-duplicate-denied'}
    $obs=Get-CustomAppSpicetifyPassiveObservationV015 -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot -HeldCrossEngineSession $HeldCrossEngineSession
    if(-not[bool]$obs.ok -or
       [string]$obs.exe_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
        throw 'spicetify-pin-unverified-executable-not-official-v2.46.4-x64'
    }
    $pin=[ordered]@{
        schema=1;name=[string]$Session.paths.name
        live=[string]$Session.paths.live;key=[string]$Session.paths.key
        consumption_id=[string]$Session.state.active.consumption_id
        transaction_id=[string]$Session.state.active.transaction_id
        nonce=[string]$Session.state.active.nonce
        state_revision=[long]$Session.state.revision
        allowed_root=[string]$rec.allowed_root
        store_directory=[string]$rec.store_directory
        prepared_entry_sha256=[string]$jr.entry.entry_sha256
        prepared_revision=[long]0
        exe_sha256=[string]$obs.exe_sha256
        config_sha256=[string]$obs.config_sha256
        exe_bytes=[long]$obs.exe_bytes;config_bytes=[long]$obs.config_bytes
        executable_path=[string]$obs.executable_path
        config_path=[string]$obs.config_path
        observation_fingerprint=[string]$obs.observation_fingerprint
        official_release='spicetify/cli-v2.46.4-windows-x64'
        recorded_utc=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plain=[Text.Encoding]::UTF8.GetBytes(($pin|ConvertTo-Json -Compress -Depth 7))
    try{
        $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|SpicetifyPin|v1|'+
            [string]$pin.key+'|'+[string]$pin.consumption_id))
        $sealed=[Security.Cryptography.ProtectedData]::Protect($plain,$entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($plain,0,$plain.Length)}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$checksum=$sha.ComputeHash($sealed)}finally{$sha.Dispose()}
    $wrapped=New-Object byte[] ($sealed.Length+32)
    [Array]::Copy($checksum,0,$wrapped,0,32)
    [Array]::Copy($sealed,0,$wrapped,32,$sealed.Length)
    # Exactly ONE CreateNew+durable flush. No over-write, auto-repair, or
    # cleanup if a power cut leaves an ambiguous sealed record.
    Write-CustomAppUserTxnBytesV010 -Path $file -Bytes $wrapped
    $bound=Read-CustomAppSpicetifySealedPinV016 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    if(-not[bool]$bound.ok -or
       [string]$bound.transaction_id -cne [string]$pin.transaction_id){
        throw 'spicetify-pin-durable-postwrite-readback-failed'
    }
    return [pscustomobject]@{
        ok=$true;reason='immutable-prepared-official-executable-pin-enrolled'
        read_after_write_verified=$true;immutable_create_new=$true
        pin_is_not_execution_authority=$true
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}


function Get-CustomAppSpicetifySealedPinReadinessV016 {
    param([string]$HostedCiRoot,[string]$HostedCiLocalAppDataRoot,
          [string]$HostedCiAppDataRoot,$HeldCrossEngineSession)
    $global=$null;$owns=$false
    try{
        if($null-ne$HeldCrossEngineSession){$global=$HeldCrossEngineSession}
        else{
            $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
            $owns=$true
        }
        $audit=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $HostedCiRoot -HeldCrossEngineSession $global
        if(-not[bool]$audit.ok -or [bool]$audit.production_mutation_authorized){
            throw 'spicetify-pin-restart-unqualified-dpapi-audit'
        }
        $items=New-Object 'System.Collections.Generic.List[object]'
        foreach($item in @($audit.items)){
            if(-not[bool]$item.active){
                $items.Add([pscustomobject]@{
                    name=[string]$item.name;active=$false
                    pin_found=$false;unchanged=$false;known_official_executable=$false
                    reason='idle-or-terminal-no-active-pin'
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
                continue
            }
            $src=$item.source;$name=[string]$src.name;$live=[string]$src.live
            $paths=if([IO.Directory]::Exists($live)){
                Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
            }else{
                Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
            }
            if([string]$paths.key -cne [string]$src.key){
                throw 'spicetify-pin-restart-path-identity-mismatch'
            }
            Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
            if(-not[IO.File]::Exists([string]$paths.lock)){
                throw 'spicetify-pin-restart-app-lock-absent'
            }
            $handle=$null
            try{
                $handle=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,
                    [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                $state=Read-CustomAppUserTxnStateV010 -Paths $paths
                if($null-eq$state.active -or
                   [string]$state.active.transaction_id -cne [string]$src.transaction_id -or
                   [string]$state.active.consumption_id -cne [string]$src.consumption_id -or
                   [string]$state.active.nonce -cne [string]$src.nonce -or
                   [long]$state.revision -ne [long]$src.state_revision){
                    throw 'spicetify-pin-restart-triple-id-drift'
                }
                $session=[pscustomobject]@{
                    ok=$true;paths=$paths;state=$state;lock_handle=$handle
                    production_execution_authorized=$false;production_mutation_authorized=$false
                }
                $bound=Read-CustomAppSpicetifySealedPinV016 -Session $session -HeldCrossEngineSession $global -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
                if(-not[bool]$bound.ok -and [bool]$bound.pin_found){
                    throw 'spicetify-pin-restart-inconsistent-seal'
                }
                $items.Add([pscustomobject]@{
                    name=$name;active=$true;pin_found=[bool]$bound.pin_found
                    unchanged=[bool]$bound.unchanged
                    known_official_executable=[bool]$bound.known_official_executable
                    reason=[string]$bound.reason
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
            }finally{if($null-ne$handle){$handle.Dispose()}}
            [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $global)
        }
        return [pscustomobject]@{
            schema=1;ok=$true;enrollment_found=[bool]$audit.enrollment_found
            inspected_count=[int]$audit.inspected_count
            active_count=[int]$audit.active_count
            items=@($items.ToArray());read_only_restart=$true
            pin_is_not_execution_authority=$true;result_is_authority=$false
            production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }finally{
        if($owns -and $null-ne$global -and $null-ne$global.lock_handle){
            $global.lock_handle.Dispose()
        }
    }
}
function Test-CustomAppSpicetifySealedPinSelfTestV016 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'spicetify-pin-fullchain-must-remain-disabled'
    }
    foreach($name in @('Assert-CustomAppSpicetifyPinLocksV016',
        'Get-CustomAppSpicetifyPinFileV016','Read-CustomAppSpicetifySealedPinV016',
        'Save-CustomAppSpicetifyPreMutationPinV016',
        'Get-CustomAppSpicetifySealedPinReadinessV016')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('spicetify-pin-required-function-missing-'+$name)
        }
    }
    Write-Host 'SPICETIFY_SEALED_PIN_SELFTEST_PASS dpapi_currentuser=true official_exe_sha_pinned=true prepared_only_enrollment=true zero_execution_authority=true'
}
