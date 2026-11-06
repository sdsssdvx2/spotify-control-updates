# GitHub-hosted-Windows ONLY native scoped-refresh crash-recovery candidate.
# Requires enrolled V016 exact official Spicetify binary + config and two
# held cross-process exclusive locks. No live Spotify or production authority.
# Only the plain-index.js custom-app subset is implemented in this prototype.
function Get-CustomAppScopedLabShaV017 {
    param([AllowEmptyCollection()][byte[]]$Bytes)
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$h.Dispose()}
}
function Assert-CustomAppScopedLabHostedV017 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'native-scoped-lab-hosted-windows-only-not-production'
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $p=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if(-not $p.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       $p.StartsWith('\\') -or -not[IO.Directory]::Exists($p)){
        throw 'native-scoped-lab-root-not-runner-isolated'
    }
    [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $p -RequireDirectory)
    return $p
}
function Get-CustomAppScopedLabContextV017 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiRoot)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiLocalAppDataRoot)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiAppDataRoot)
    $proof=Read-CustomAppSpicetifySealedPinV016 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    if(-not[bool]$proof.ok -or -not[bool]$proof.unchanged -or
       -not[bool]$proof.known_official_executable -or
       [bool]$proof.production_execution_authorized){
        throw 'native-scoped-lab-official-pin-not-qualified'
    }
    $obs=Get-CustomAppSpicetifyPassiveObservationV015 -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot -HeldCrossEngineSession $HeldCrossEngineSession
    if(-not[bool]$obs.ok -or
       [string]$obs.exe_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db' -or
       [string]$obs.config_sha256 -cne [string]$proof.config_sha256){
        throw 'native-scoped-lab-spicetify-file-observation-drift'
    }
    $target=[string]$Session.paths.name
    if($target -cnotmatch '^[a-z][a-z0-9_-]{1,63}$'){throw 'native-scoped-lab-target-unqualified'}
    $expectedLive=[IO.Path]::GetFullPath((Join-Path (Join-Path $HostedCiAppDataRoot 'spicetify\CustomApps') $target)).TrimEnd('\','/')
    if(-not[IO.Path]::GetFullPath([string]$Session.paths.live).TrimEnd('\','/').Equals($expectedLive,[StringComparison]::OrdinalIgnoreCase)){
        throw 'native-scoped-lab-target-live-not-canonical-spicetify-customapps'
    }
    [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $expectedLive -RequireDirectory)
    $sourceEntries=@(Get-ChildItem -LiteralPath $expectedLive -Force)
    if($sourceEntries.Count -ne 1 -or
       [string]$sourceEntries[0].Name -cne 'index.js' -or
       [bool]$sourceEntries[0].PSIsContainer -or
       ($sourceEntries[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $sourceEntries[0].Length -lt 1 -or $sourceEntries[0].Length -gt 2097152){
        throw 'native-scoped-lab-only-plain-single-indexjs-sources-supported'
    }
    $lines=[IO.File]::ReadAllLines([string]$obs.config_path)
    $section='';$values=@{};$customLine=-1
    for($i=0;$i -lt $lines.Length;$i++){
        $line=$lines[$i].Trim()
        if($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
        if($line -cmatch '^\[([A-Za-z][A-Za-z0-9]*)\]$'){$section=$matches[1].ToLowerInvariant();continue}
        if($line -notmatch '^([a-zA-Z][a-zA-Z0-9_]*)\s*=\s*(.*?)\s*$'){
            throw 'native-scoped-lab-config-unparsed-or-ambiguous-line'
        }
        $name=$matches[1].ToLowerInvariant();$val=$matches[2]
        $key=$section+'/'+$name
        if($values.ContainsKey($key)){throw 'native-scoped-lab-config-duplicate-key'}
        $values[$key]=[string]$val
        if($key -ceq 'additionaloptions/custom_apps'){$customLine=$i}
    }
    if($customLine -lt 0 -or -not$values.ContainsKey('setting/spotify_path') -or
       -not$values.ContainsKey('setting/prefs_path') -or
       -not$values.ContainsKey('backup/version') -or
       -not$values.ContainsKey('backup/with') -or
       [string]$values['backup/with'] -cne '2.46.4'){
        throw 'native-scoped-lab-backup-or-config-fields-unqualified'
    }
    $configured=@(([string]$values['additionaloptions/custom_apps']).Split('|')|ForEach-Object{$_.Trim()})
    if(@($configured|Where-Object{$_ -ceq $target}).Count -ne 1 -or
       @($configured|Where-Object{$_ -cnotmatch '^[a-z][a-z0-9_-]{1,63}$'}).Count){
        throw 'native-scoped-lab-target-not-uniquely-enrolled'
    }
    $spotify=[string]$values['setting/spotify_path']
    $prefs=[string]$values['setting/prefs_path']
    if(-not[IO.Path]::IsPathRooted($spotify) -or $spotify.StartsWith('\\') -or
       -not[IO.Path]::IsPathRooted($prefs) -or $prefs.StartsWith('\\') -or
       $spotify.Contains('%') -or $prefs.Contains('%')){
        throw 'native-scoped-lab-config-path-not-literal-absolute'
    }
    $spotify=[IO.Path]::GetFullPath($spotify)
    $prefs=[IO.Path]::GetFullPath($prefs)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $spotify)
    if(-not $prefs.StartsWith(([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       -not[IO.File]::Exists($prefs)){
        throw 'native-scoped-lab-prefs-unqualified'
    }
    Assert-CustomAppUserTxnNoReparseV010 -Path $prefs
    $xpui=Join-Path $spotify 'Apps\xpui'
    [void](Assert-CustomAppScopedLabHostedV017 -Path $xpui)
    $originalBackup=Join-Path $HostedCiAppDataRoot 'spicetify\Backup\xpui.spa'
    Assert-CustomAppUserTxnNoReparseV010 -Path $originalBackup
    if(-not[IO.File]::Exists($originalBackup) -or
       (Get-Item -LiteralPath $originalBackup).Length -gt 2097152){
        throw 'native-scoped-lab-original-backup-absent-or-unbounded'
    }
    $sha=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$obs.executable_path)
    if($sha -cne [string]$proof.exe_sha256){throw 'native-scoped-lab-executable-pin-drift'}
    return [pscustomobject]@{
        target=$target;source=$expectedLive;source_index=[string]$sourceEntries[0].FullName
        xpui=$xpui;config_path=[string]$obs.config_path
        config_lines=$lines;custom_line=$customLine
        executable_path=[string]$obs.executable_path
        original_backup=$originalBackup
        config_sha256=[string]$proof.config_sha256
        exe_sha256=[string]$proof.exe_sha256
        transaction_id=[string]$Session.state.active.transaction_id
        consumption_id=[string]$Session.state.active.consumption_id
        nonce=[string]$Session.state.active.nonce
        state_revision=[long]$Session.state.revision
        scope_root=(Join-Path ([string]$Session.paths.directory) ('native-scoped-'+[string]$Session.state.active.consumption_id))
        sealed_path=(Join-Path ([string]$Session.paths.directory) ('native-scoped-'+[string]$Session.state.active.consumption_id+'.dpapi'))
        intent_path=(Join-Path ([string]$Session.paths.directory) ('native-scoped-'+[string]$Session.state.active.consumption_id+'.intent'))
        recovered_path=(Join-Path ([string]$Session.paths.directory) ('native-scoped-'+[string]$Session.state.active.consumption_id+'.recovered'))
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}


function Read-CustomAppScopedLabSnapshotV017 {
    param([Parameter(Mandatory=$true)]$Context,[Parameter(Mandatory=$true)]$Session)
    [void](Assert-CustomAppUserTxnSessionV010 -Session $Session)
    $path=[string]$Context.sealed_path
    Assert-CustomAppUserTxnNoReparseV010 -Path $path
    if(-not[IO.File]::Exists($path)){throw 'native-scoped-lab-snapshot-not-enrolled'}
    $wrapped=[IO.File]::ReadAllBytes($path)
    if($wrapped.Length -lt 128 -or $wrapped.Length -gt 12582912){
        throw 'native-scoped-lab-snapshot-encrypted-size-invalid'
    }
    $sealed=New-Object byte[] ($wrapped.Length-32)
    [Array]::Copy($wrapped,32,$sealed,0,$sealed.Length)
    $digest=Get-CustomAppScopedLabShaV017 -Bytes $sealed
    $full=([BitConverter]::ToString($wrapped,0,32)).Replace('-','').ToLowerInvariant()
    if($full -cne $digest){throw 'native-scoped-lab-snapshot-ciphertext-tampered'}
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|NativeScopedSnapshot|v017|'+
        [string]$Session.paths.key+'|'+[string]$Context.consumption_id))
    $plain=$null
    try{
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($sealed,$entropy,
             [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $snap=([Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop)
    }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
    if([int]$snap.schema -ne 1 -or
       [string]$snap.target -cne [string]$Context.target -or
       [string]$snap.consumption_id -cne [string]$Context.consumption_id -or
       [string]$snap.transaction_id -cne [string]$Context.transaction_id -or
       [string]$snap.nonce -cne [string]$Context.nonce -or
       [long]$snap.state_revision -ne [long]$Context.state_revision -or
       [string]$snap.xpui -cne [string]$Context.xpui -or
       [string]$snap.exe_sha256 -cne [string]$Context.exe_sha256 -or
       [string]$snap.config_sha256 -cne [string]$Context.config_sha256 -or
       [string]$snap.source_sha256 -cnotmatch '^[0-9a-f]{64}$'){
        throw 'native-scoped-lab-sealed-snapshot-identity-invalid'
    }
    $expected=@(('spicetify-routes-{0}.css' -f [string]$Context.target),
                ('spicetify-routes-{0}.js' -f [string]$Context.target),
                ('spicetify-routes-{0}.json' -f [string]$Context.target))
    $targetRecords=@($snap.targets)
    if($targetRecords.Count -ne 3 -or
       ((@($targetRecords|ForEach-Object{[string]$_.rel}|Sort-Object) -join '|') -cne
        (@($expected|Sort-Object) -join '|'))){
        $actualNames=(@($targetRecords|ForEach-Object{[string]$_.rel}|Sort-Object) -join '|')
        $expectedNames=(@($expected|Sort-Object) -join '|')
        throw ('native-scoped-lab-snapshot-target-list-invalid count='+$targetRecords.Count+' expected='+$expectedNames+' actual='+$actualNames)
    }
    foreach($item in $targetRecords){
        if([string]$item.rel -cnotmatch ('^spicetify-routes-'+[regex]::Escape([string]$Context.target)+'\.(js|json|css)$') -or
           [string]$item.sha -cnotmatch '^[0-9a-f]{64}$' -or
           [long]$item.bytes -lt 0 -or [long]$item.bytes -gt 4194304){
            throw 'native-scoped-lab-snapshot-target-metadata-invalid'
        }
        if([bool]$item.existed){
            $b=[Convert]::FromBase64String([string]$item.base64)
            if($b.Length -ne [long]$item.bytes -or
               (Get-CustomAppScopedLabShaV017 -Bytes $b) -cne [string]$item.sha){
                throw 'native-scoped-lab-snapshot-target-backup-bytes-tampered'
            }
        }elseif([long]$item.bytes -ne 0 -or [string]$item.base64 -cne '' -or
                [string]$item.sha -cne (Get-CustomAppScopedLabShaV017 -Bytes ([byte[]]@()))){
            throw 'native-scoped-lab-snapshot-absent-target-metadata-invalid'
        }
    }
    $others=@($snap.others)
    if($others.Count -gt 512){throw 'native-scoped-lab-outside-snapshot-unbounded'}
    $seen=@{}
    foreach($item in $others){
        $rel=[string]$item.rel
        if([string]::IsNullOrWhiteSpace($rel) -or $rel.StartsWith('\') -or
           $rel.Contains('..') -or $rel.Contains(':') -or
           [IO.Path]::IsPathRooted($rel) -or $rel -ceq '.' -or
           @($expected|Where-Object{$_ -ceq $rel}).Count -or
           $seen.ContainsKey($rel.ToLowerInvariant()) -or
           [string]$item.sha -cnotmatch '^[0-9a-f]{64}$' -or
           [long]$item.bytes -lt 0 -or [long]$item.bytes -gt 67108864){
            throw 'native-scoped-lab-untrusted-outside-inventory-record'
        }
        $seen[$rel.ToLowerInvariant()]=$true
    }
    return $snap
}
function Get-CustomAppScopedLabInventoryV017 {
    param([Parameter(Mandatory=$true)]$Context)
    $xpui=[string]$Context.xpui
    [void](Assert-CustomAppScopedLabHostedV017 -Path $xpui)
    $prefix=$xpui.TrimEnd('\','/')+'\'
    $items=@(Get-ChildItem -LiteralPath $xpui -Recurse -Force -ErrorAction Stop)
    if($items.Count -gt 600){throw 'native-scoped-lab-xpui-inventory-too-large'}
    $files=New-Object 'System.Collections.Generic.List[object]'
    foreach($item in $items){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'native-scoped-lab-symlink-or-junction-in-xpui'
        }
        if($item.PSIsContainer){continue}
        $path=[IO.Path]::GetFullPath([string]$item.FullName)
        if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
           $item.Length -gt 67108864){
            throw 'native-scoped-lab-outside-or-huge-output'
        }
        $rel=$path.Substring($prefix.Length)
        if($rel.Contains('..') -or $rel.Contains(':')){throw 'native-scoped-lab-unsafe-relative-file'}
        $data=[IO.File]::ReadAllBytes($path)
        if($data.Length -ne [long]$item.Length){throw 'native-scoped-lab-xpui-modified-during-snapshot'}
        $files.Add([pscustomobject]@{
            rel=$rel;full=$path;bytes=[long]$data.Length
            sha=(Get-CustomAppScopedLabShaV017 -Bytes $data)
        })
    }
    return @($files.ToArray())
}
function Assert-CustomAppScopedLabOutsideUnchangedV017 {
    param([Parameter(Mandatory=$true)]$Context,
          [Parameter(Mandatory=$true)]$Snapshot)
    $current=@(Get-CustomAppScopedLabInventoryV017 -Context $Context)
    $allowed=@(('spicetify-routes-{0}.css' -f [string]$Context.target),
               ('spicetify-routes-{0}.js' -f [string]$Context.target),
               ('spicetify-routes-{0}.json' -f [string]$Context.target))
    $outside=@($current|Where-Object{$_.rel -notin $allowed})
    $saved=@($Snapshot.others)
    if($outside.Count -ne $saved.Count){throw 'native-scoped-lab-outside-inventory-count-changed'}
    $map=@{}
    foreach($item in $saved){$map[[string]$item.rel]=$item}
    foreach($item in $outside){
        if(-not$map.ContainsKey([string]$item.rel) -or
           [string]$map[[string]$item.rel].sha -cne [string]$item.sha -or
           [long]$map[[string]$item.rel].bytes -ne [long]$item.bytes){
            throw 'native-scoped-lab-outside-inventory-mutated-deny-recovery'
        }
    }
    return $true
}


function Save-CustomAppScopedLabSnapshotV017 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    foreach($file in @($ctx.sealed_path,$ctx.intent_path,$ctx.recovered_path)){
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$file)
        if([IO.File]::Exists($file)){throw 'native-scoped-lab-already-prepared-or-consumed'}
    }
    if([IO.Directory]::Exists([string]$ctx.scope_root)){
        throw 'native-scoped-lab-existing-ephemeral-profile-denied'
    }
    $inventory=@(Get-CustomAppScopedLabInventoryV017 -Context $ctx)
    $allowed=@(('spicetify-routes-{0}.css' -f [string]$ctx.target),
               ('spicetify-routes-{0}.js' -f [string]$ctx.target),
               ('spicetify-routes-{0}.json' -f [string]$ctx.target))
    $targets=New-Object 'System.Collections.Generic.List[object]'
    $outside=New-Object 'System.Collections.Generic.List[object]'
    foreach($name in $allowed){
        $matching=@($inventory|Where-Object{[string]$_.rel -ceq $name})
        if($matching.Count -gt 1){throw 'native-scoped-lab-ambiguous-target-output'}
        $path=Join-Path ([string]$ctx.xpui) $name
        Assert-CustomAppUserTxnNoReparseV010 -Path $path
        if($matching.Count -eq 0){
            $targets.Add([ordered]@{
                rel=$name;existed=$false;sha=(Get-CustomAppScopedLabShaV017 -Bytes ([byte[]]@()))
                bytes=[long]0;base64=''
            })
        }else{
            $data=[IO.File]::ReadAllBytes($path)
            if($data.Length -gt 4194304 -or $data.Length -ne [long]$matching[0].bytes -or
               (Get-CustomAppScopedLabShaV017 -Bytes $data) -cne [string]$matching[0].sha){
                throw 'native-scoped-lab-preexisting-target-drift'
            }
            $targets.Add([ordered]@{
                rel=$name;existed=$true;sha=[string]$matching[0].sha
                bytes=[long]$data.Length;base64=[Convert]::ToBase64String($data)
            })
        }
    }
    foreach($item in $inventory){
        if([string]$item.rel -notin $allowed){
            $outside.Add([ordered]@{
                rel=[string]$item.rel;bytes=[long]$item.bytes;sha=[string]$item.sha
            })
        }
    }
    $sourceSha=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)
    $snap=[ordered]@{
        schema=1;target=[string]$ctx.target
        consumption_id=[string]$ctx.consumption_id
        transaction_id=[string]$ctx.transaction_id
        nonce=[string]$ctx.nonce
        state_revision=[long]$ctx.state_revision
        config_sha256=[string]$ctx.config_sha256
        exe_sha256=[string]$ctx.exe_sha256
        source_sha256=[string]$sourceSha
        xpui=[string]$ctx.xpui
        targets=@($targets.ToArray())
        others=@($outside.ToArray())
    }
    # The scoped CLI will read a separate config and separate app source.
    # Neither the user's pinned config nor source is edited. Directory and
    # clone are created before the durable mutation-intent marker.
    $scope=[string]$ctx.scope_root
    $dirs=@($scope,(Join-Path $scope 'CustomApps'),
        (Join-Path $scope ('CustomApps\'+$ctx.target)),(Join-Path $scope 'Backup'))
    foreach($dir in $dirs){
        if([IO.Directory]::Exists($dir)){throw 'native-scoped-lab-private-clone-existed'}
        [void][IO.Directory]::CreateDirectory($dir)
    }
    $clonedSource=Join-Path $scope ('CustomApps\'+$ctx.target+'\index.js')
    $clonedBackup=Join-Path $scope 'Backup\xpui.spa'
    $clonedConfig=Join-Path $scope 'config-xpui.ini'
    [IO.File]::Copy([string]$ctx.source_index,$clonedSource,$false)
    [IO.File]::Copy([string]$ctx.original_backup,$clonedBackup,$false)
    $lines=[string[]]$ctx.config_lines.Clone()
    $lines[[int]$ctx.custom_line]='custom_apps = '+[string]$ctx.target
    # Check exact original Setting to avoid a check-for-updates network call.
    $setting=@($lines|Where-Object{$_ -match '^\s*check_spicetify_update\s*=\s*false\s*$'})
    if($setting.Count -ne 1){throw 'native-scoped-lab-upstream-auto-network-setting-not-explicitly-disabled'}
    [IO.File]::WriteAllLines($clonedConfig,$lines,([Text.UTF8Encoding]::new($false)))
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $clonedSource) -cne $sourceSha){
        throw 'native-scoped-lab-source-clone-drift'
    }
    $plain=[Text.Encoding]::UTF8.GetBytes(($snap|ConvertTo-Json -Compress -Depth 9))
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $encrypted=$null
    try{
        $entropy=[Text.Encoding]::UTF8.GetBytes(('SpotifyControlUpdates|NativeScopedSnapshot|v017|'+
            [string]$Session.paths.key+'|'+[string]$ctx.consumption_id))
        $encrypted=[Security.Cryptography.ProtectedData]::Protect($plain,$entropy,
           [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($plain,0,$plain.Length)}
    $digest=Get-CustomAppScopedLabShaV017 -Bytes $encrypted
    $binary=New-Object byte[] ($encrypted.Length+32)
    $sum=[Security.Cryptography.SHA256]::Create()
    try{$hash=$sum.ComputeHash($encrypted)}finally{$sum.Dispose()}
    [Array]::Copy($hash,0,$binary,0,32)
    [Array]::Copy($encrypted,0,$binary,32,$encrypted.Length)
    Write-CustomAppUserTxnBytesV010 -Path ([string]$ctx.sealed_path) -Bytes $binary
    $read=Read-CustomAppScopedLabSnapshotV017 -Context $ctx -Session $Session
    if([string]$read.transaction_id -cne [string]$ctx.transaction_id){
        throw 'native-scoped-lab-durable-snapshot-readback-failed'
    }
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $read)
    return [pscustomobject]@{
        ok=$true;context=$ctx;sha256=(Get-CustomAppScopedLabShaV017 -Bytes $binary)
        intent_written=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}


function Invoke-CustomAppScopedLabNativeV017 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiAppDataRoot -HeldCrossEngineSession $HeldCrossEngineSession
    $snap=Read-CustomAppScopedLabSnapshotV017 -Context $ctx -Session $Session
    if([IO.File]::Exists([string]$ctx.intent_path) -or
       [IO.File]::Exists([string]$ctx.recovered_path)){
        throw 'native-scoped-lab-nonreentrant-execution-after-intent'
    }
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $snap)
    $clone=[string]$ctx.scope_root
    [void](Assert-CustomAppScopedLabHostedV017 -Path $clone)
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path (Join-Path $clone ('CustomApps\'+$ctx.target+'\index.js'))) -cne
       [string]$snap.source_sha256){
        throw 'native-scoped-lab-source-stage-drift'
    }
    $clonedConfig=Join-Path $clone 'config-xpui.ini'
    if(-not[IO.File]::Exists($clonedConfig) -or
       -not[IO.File]::ReadAllText($clonedConfig).Contains(('custom_apps = '+$ctx.target))){
        throw 'native-scoped-lab-staged-config-drift'
    }
    $sealed=[IO.File]::ReadAllBytes([string]$ctx.sealed_path)
    $sealSha=Get-CustomAppScopedLabShaV017 -Bytes $sealed
    $intent=[Text.Encoding]::ASCII.GetBytes(('V017_INTENT_SHA256='+$sealSha+[Environment]::NewLine))
    # The durable marker is the last state write before executing native code.
    Write-CustomAppUserTxnBytesV010 -Path ([string]$ctx.intent_path) -Bytes $intent
    $p=New-Object Diagnostics.ProcessStartInfo
    $p.FileName=[string]$ctx.executable_path
    # --bypass-admin is hosted-only in this mandatory sandbox guard.
    $p.Arguments='--bypass-admin -n -a refresh'
    $p.WorkingDirectory=$clone
    $p.UseShellExecute=$false
    $p.CreateNoWindow=$true
    $p.RedirectStandardOutput=$false
    $p.RedirectStandardError=$false
    $p.EnvironmentVariables['SPICETIFY_CONFIG']=$clone
    $p.EnvironmentVariables['SPICETIFY_STATE']=$clone
    $p.EnvironmentVariables['APPDATA']=[string]$HostedCiAppDataRoot
    $p.EnvironmentVariables['LOCALAPPDATA']=[string]$HostedCiLocalAppDataRoot
    $child=New-Object Diagnostics.Process
    try{
        $child.StartInfo=$p
        if(-not$child.Start()){throw 'native-scoped-lab-official-process-refused-to-start'}
        if(-not$child.WaitForExit(60000)){
            $child.Kill()
            [void]$child.WaitForExit()
            throw 'native-scoped-lab-official-process-timeout-recovery-required'
        }
        $code=[int]$child.ExitCode
    }finally{$child.Dispose()}
    if($code -ne 0){throw ('native-scoped-lab-real-cli-error-recovery-required-'+$code)}
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $snap)
    $out=Join-Path ([string]$ctx.xpui) (('spicetify-routes-{0}.js' -f [string]$ctx.target))
    if(-not[IO.File]::Exists($out) -or
       -not[IO.File]::ReadAllText($out).Contains([IO.File]::ReadAllText([string]$ctx.source_index))){
        throw 'native-scoped-lab-exit-zero-without-target-output-postcondition'
    }
    $again=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    if([string]$again.transaction_id -cne [string]$ctx.transaction_id){
        throw 'native-scoped-lab-after-apply-seal-drift'
    }
    return [pscustomobject]@{
        ok=$true;reason='official-native-refresh-applied-in-synthetic-hosted-lab'
        must_recover_or_finalize=$true;crash_restart_restore_ready=$true
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}


function Restore-CustomAppScopedLabNativeV017 {
    param([Parameter(Mandatory=$true)]$Session,
          [Parameter(Mandatory=$true)]$HeldCrossEngineSession,
          [Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    $ctx=Get-CustomAppScopedLabContextV017 -Session $Session -HeldCrossEngineSession $HeldCrossEngineSession -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
    $path=[string]$ctx.sealed_path
    if(-not[IO.File]::Exists($path)){
        return [pscustomobject]@{
            ok=$true;status='no-durable-native-refresh-snapshot'
            restored=$false;result_is_authority=$false
            production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }
    $snapshot=Read-CustomAppScopedLabSnapshotV017 -Context $ctx -Session $Session
    Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$ctx.intent_path)
    Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$ctx.recovered_path)
    if(-not[IO.File]::Exists([string]$ctx.intent_path)){
        return [pscustomobject]@{
            ok=$true;status='snapshot-prepared-no-mutation-intent'
            restored=$false;result_is_authority=$false
            production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }
    $sealed=[IO.File]::ReadAllBytes($path)
    $expected='V017_INTENT_SHA256='+(Get-CustomAppScopedLabShaV017 -Bytes $sealed)+[Environment]::NewLine
    $actual=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$ctx.intent_path))
    if($actual -cne $expected){throw 'native-scoped-lab-intent-not-bound-to-sealed-snapshot'}
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $snapshot)
    if((Get-CustomAppSpicetifyPassiveFileSha256V015 -Path ([string]$ctx.source_index)) -cne
       [string]$snapshot.source_sha256){
        throw 'native-scoped-lab-source-changed-after-intent'
    }
    $recovered=[IO.File]::Exists([string]$ctx.recovered_path)
    foreach($saved in @($snapshot.targets)){
        $targetPath=Join-Path ([string]$ctx.xpui) ([string]$saved.rel)
        Assert-CustomAppUserTxnNoReparseV010 -Path $targetPath
        if($recovered){continue}
        # Retryable even if the previous restore process crashed mid-write:
        # marker is only created AFTER complete byte-exact revalidation.
        if([bool]$saved.existed){
            $data=[Convert]::FromBase64String([string]$saved.base64)
            $handle=$null
            try{
                $handle=[IO.File]::Open($targetPath,[IO.FileMode]::Create,
                    [IO.FileAccess]::Write,[IO.FileShare]::None)
                $handle.Write($data,0,$data.Length)
                $handle.Flush($true)
            }finally{if($null-ne$handle){$handle.Dispose()}}
        }elseif([IO.File]::Exists($targetPath)){
            [IO.File]::Delete($targetPath)
        }
    }
    [void](Assert-CustomAppScopedLabOutsideUnchangedV017 -Context $ctx -Snapshot $snapshot)
    foreach($saved in @($snapshot.targets)){
        $targetPath=Join-Path ([string]$ctx.xpui) ([string]$saved.rel)
        if([bool]$saved.existed){
            if(-not[IO.File]::Exists($targetPath) -or
               (Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $targetPath) -cne
                   [string]$saved.sha){
                throw 'native-scoped-lab-restore-exact-target-mismatch'
            }
        }elseif([IO.File]::Exists($targetPath)){
            throw 'native-scoped-lab-restore-created-target-persisted'
        }
    }
    if(-not$recovered){
        Write-CustomAppUserTxnBytesV010 -Path ([string]$ctx.recovered_path) -Bytes (
            [Text.Encoding]::ASCII.GetBytes(('V017_RECOVERED='+[string]$ctx.transaction_id+[Environment]::NewLine)))
    }else{
        $terminal='V017_RECOVERED='+[string]$ctx.transaction_id+[Environment]::NewLine
        if([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$ctx.recovered_path)) -cne
           $terminal){throw 'native-scoped-lab-terminal-marker-corrupt'}
    }
    return [pscustomobject]@{
        ok=$true;status=$(if($recovered){'already-recovered-verified'}else{'restored-exact-before-image'})
        restored=(-not$recovered);replay_idempotent=$recovered
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }
}
function Invoke-CustomAppScopedLabIndependentRecoveryV017 {
    param([Parameter(Mandatory=$true)][string]$HostedCiRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiLocalAppDataRoot,
          [Parameter(Mandatory=$true)][string]$HostedCiAppDataRoot)
    [void](Assert-CustomAppScopedLabHostedV017 -Path $HostedCiRoot)
    $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
    try{
        # Identity comes from the DPAPI registry only. Never from a supplied
        # app name, journal path or transaction ID.
        $audit=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $HostedCiRoot -HeldCrossEngineSession $global
        if(-not[bool]$audit.ok -or [int]$audit.inspected_count -ne 1 -or
           [int]$audit.active_count -ne 1 -or @($audit.items).Count -ne 1){
            throw 'native-scoped-lab-recovery-ambiguous-dpapi-discovery'
        }
        $src=$audit.items[0].source
        $name=[string]$src.name;$live=[string]$src.live
        $paths=if([IO.Directory]::Exists($live)){
            Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
        }else{
            Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
        }
        $handle=$null
        try{
            Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
            if(-not[IO.File]::Exists([string]$paths.lock)){
                throw 'native-scoped-lab-recovery-existing-app-lock-required'
            }
            $handle=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,
                [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            $state=Read-CustomAppUserTxnStateV010 -Paths $paths
            if($null-eq$state.active -or
               [string]$state.active.consumption_id -cne [string]$src.consumption_id -or
               [string]$state.active.transaction_id -cne [string]$src.transaction_id -or
               [string]$state.active.nonce -cne [string]$src.nonce -or
               [long]$state.revision -ne [long]$src.state_revision){
                throw 'native-scoped-lab-recovery-current-state-drift'
            }
            $session=[pscustomobject]@{
                ok=$true;paths=$paths;state=$state;lock_handle=$handle
                production_execution_authorized=$false;production_mutation_authorized=$false
            }
            return Restore-CustomAppScopedLabNativeV017 -Session $session -HeldCrossEngineSession $global -HostedCiRoot $HostedCiRoot -HostedCiLocalAppDataRoot $HostedCiLocalAppDataRoot -HostedCiAppDataRoot $HostedCiAppDataRoot
        }finally{if($null-ne$handle){$handle.Dispose()}}
    }finally{
        if($null-ne$global -and $null-ne$global.lock_handle){$global.lock_handle.Dispose()}
    }
}
function Test-CustomAppScopedLabSelfTestV017 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'native-scoped-lab-must-never-enable-production-pipeline'
    }
    foreach($name in @('Get-CustomAppScopedLabContextV017',
        'Save-CustomAppScopedLabSnapshotV017','Read-CustomAppScopedLabSnapshotV017',
        'Invoke-CustomAppScopedLabNativeV017','Restore-CustomAppScopedLabNativeV017',
        'Invoke-CustomAppScopedLabIndependentRecoveryV017')){
        if(-not(Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('native-scoped-lab-function-missing-'+$name)
        }
    }
    Write-Host 'NATIVE_SCOPED_CRASH_RESTORE_LAB_SELFTEST_PASS hosted_only=true dpapi_snapshot=true real_binary_with_crash=true no_production_dispatch=true'
}
