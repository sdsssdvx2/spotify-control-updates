function Get-AddonUserStateTargets {
    $targets=New-Object System.Collections.Generic.List[object]
    $localSpotify=Join-Path $env:LOCALAPPDATA "Spotify"
    $roamingSpotify=Join-Path $env:APPDATA "Spotify"
    foreach($profileName in @("Browser","Default")){
        $profile=Join-Path $localSpotify $profileName
        foreach($storageName in @("IndexedDB","Local Storage","Session Storage","WebStorage")){
            $label=("local-{0}-{1}" -f $profileName,$storageName).ToLowerInvariant().Replace(' ','-')
            $targets.Add([pscustomobject]@{label=$label;path=(Join-Path $profile $storageName)})
        }
        foreach($fileName in @("Local State","Preferences")){
            $label=("local-{0}-{1}" -f $profileName,$fileName).ToLowerInvariant().Replace(' ','-')
            $targets.Add([pscustomobject]@{label=$label;path=(Join-Path $profile $fileName)})
        }
    }
    foreach($storageName in @("IndexedDB","Local Storage")){
        $label=("local-root-{0}" -f $storageName).ToLowerInvariant().Replace(' ','-')
        $targets.Add([pscustomobject]@{label=$label;path=(Join-Path $localSpotify $storageName)})
    }
    $targets.Add([pscustomobject]@{label='local-users';path=(Join-Path $localSpotify 'Users')})
    $targets.Add([pscustomobject]@{label='roaming-users';path=(Join-Path $roamingSpotify 'Users')})
    $targets.Add([pscustomobject]@{label='roaming-prefs';path=(Join-Path $roamingSpotify 'prefs')})
    $targets.Add([pscustomobject]@{label='spicetify-config';path=(Join-Path $env:APPDATA 'spicetify\config-xpui.ini')})
    return @($targets.ToArray())
}

function Get-AddonUserStateEntrySnapshot {
    param([string]$Label,[string]$Path)
    if([string]::IsNullOrWhiteSpace($Label) -or [string]::IsNullOrWhiteSpace($Path)){throw 'User-state snapshot target label/path is empty.'}
    if(-not(Test-PathSafe $Path)){
        return [pscustomobject]@{label=$Label;path=$Path;exists=$false;kind='absent';count=0;bytes=[int64]0;fingerprint=(Get-TextSha256 ("ABSENT`t"+$Label+"`n"))}
    }
    $root=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "User-state root is a reparse point: $Path"}
    if(-not $root.PSIsContainer){
        $h=(Get-FileHash -LiteralPath $root.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $fp=Get-TextSha256 ("FILE`t$Label`t$($root.Length)`t$h`n")
        return [pscustomobject]@{label=$Label;path=$root.FullName;exists=$true;kind='file';count=1;bytes=[int64]$root.Length;fingerprint=$fp}
    }
    $full=[System.IO.Path]::GetFullPath($root.FullName).TrimEnd([char[]]@([char]92,[char]47))
    $rows=New-Object System.Collections.Generic.List[string]
    $fileCount=0;$total=[int64]0
    foreach($entry in @(Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction Stop)){
        if(($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){throw "User-state tree contains a reparse point: $($entry.FullName)"}
        $rel=$entry.FullName.Substring($full.Length).TrimStart([char[]]@([char]92,[char]47)).Replace([char]92,[char]47)
        if([string]::IsNullOrWhiteSpace($rel) -or $rel.StartsWith('../') -or $rel.Contains('/../')){throw "Unsafe user-state relative path: $rel"}
        if($entry.PSIsContainer){$rows.Add("D`t$rel");continue}
        $h=(Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add(("F`t{0}`t{1}`t{2}" -f $rel,[int64]$entry.Length,$h));$fileCount++;$total+=[int64]$entry.Length
    }
    $ordered=@($rows.ToArray()|Sort-Object)
    $fp=Get-TextSha256 (("DIR`t$Label`n")+(($ordered -join "`n")+"`n"))
    return [pscustomobject]@{label=$Label;path=$full;exists=$true;kind='directory';count=$fileCount;bytes=$total;fingerprint=$fp}
}

function Get-AddonUserStateSnapshot {
    param($Targets=$null)
    if($null -eq $Targets){$Targets=Get-AddonUserStateTargets}
    $entries=New-Object System.Collections.Generic.List[object]
    foreach($target in @($Targets)){
        $entries.Add((Get-AddonUserStateEntrySnapshot -Label ([string]$target.label) -Path ([string]$target.path)))
    }
    $ordered=@($entries.ToArray()|Sort-Object label)
    $lines=@($ordered|ForEach-Object{"{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $_.label,$_.exists,$_.kind,$_.count,$_.bytes,$_.fingerprint})
    return [pscustomobject]@{schema=1;created_at=(Get-Date).ToString('o');fingerprint=(Get-TextSha256 (($lines -join "`n")+"`n"));entries=$ordered}
}

function New-AddonUserStateTransactionBackup {
    param([Parameter(Mandatory=$true)][string]$TxId)
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing transaction-coupled user-state backup.'}
    if([string]::IsNullOrWhiteSpace($TxId)){throw 'Transaction id is empty for user-state backup.'}
    $dest=Join-Path (Join-Path $AddonUserStateBackupRoot $TxId) 'before'
    if(Test-PathSafe $dest){throw "User-state transaction backup already exists: $dest"}
    New-Item -ItemType Directory -Force -Path $dest|Out-Null
    $before=Get-AddonUserStateSnapshot
    $guardEntries=New-Object System.Collections.Generic.List[object]
    try{
        foreach($entry in @($before.entries)){
            $backupPath=Join-Path $dest ([string]$entry.label)
            if([bool]$entry.exists){
                if([string]$entry.kind -ceq 'directory'){
                    Copy-DirectoryContentsExact -Source ([string]$entry.path) -Destination $backupPath
                }elseif([string]$entry.kind -ceq 'file'){
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath)|Out-Null
                    Copy-Item -LiteralPath ([string]$entry.path) -Destination $backupPath -Force -ErrorAction Stop
                }else{throw "Unsupported user-state entry kind: $($entry.kind)"}
                $copy=Get-AddonUserStateEntrySnapshot -Label ([string]$entry.label) -Path $backupPath
                if(-not[bool]$copy.exists -or [string]$copy.kind -cne [string]$entry.kind -or [string]$copy.fingerprint -cne [string]$entry.fingerprint){throw "User-state backup verification failed: $($entry.label)"}
            }
            $guardEntries.Add([pscustomobject]@{label=[string]$entry.label;target=[string]$entry.path;exists=[bool]$entry.exists;kind=[string]$entry.kind;count=[int]$entry.count;bytes=[int64]$entry.bytes;fingerprint=[string]$entry.fingerprint;backup_path=$backupPath})
        }
        $guard=[pscustomobject]@{schema=1;transaction_id=$TxId;created_at=(Get-Date).ToString('o');backup_root=$dest;before_fingerprint=[string]$before.fingerprint;entries=$guardEntries.ToArray()}
        $guard|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $dest 'user-state-guard.json') -Encoding UTF8
        return $guard
    }catch{
        Remove-Item -LiteralPath (Split-Path -Parent $dest) -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Test-AddonUserStateSnapshotUnchanged {
    param([Parameter(Mandatory=$true)]$Guard)
    if($null -eq $Guard -or [int]$Guard.schema -ne 1){throw 'Unsupported/missing user-state guard schema.'}
    $targets=@($Guard.entries|ForEach-Object{[pscustomobject]@{label=[string]$_.label;path=[string]$_.target}})
    $current=Get-AddonUserStateSnapshot -Targets $targets
    return [pscustomobject]@{unchanged=([string]$current.fingerprint -ceq [string]$Guard.before_fingerprint);before_fingerprint=[string]$Guard.before_fingerprint;current_fingerprint=[string]$current.fingerprint;current=$current}
}

function Restore-AddonUserStateTransactionBackup {
    param([Parameter(Mandatory=$true)]$Guard,[switch]$AllowOverwriteCurrent)
    if(-not$AllowOverwriteCurrent){throw 'User-state restore requires explicit AllowOverwriteCurrent authorization.'}
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing user-state restore.'}
    if($null -eq $Guard -or [int]$Guard.schema -ne 1){throw 'Unsupported/missing user-state guard schema.'}
    foreach($entry in @($Guard.entries)){
        $target=[string]$entry.target;$backup=[string]$entry.backup_path
        if([bool]$entry.exists){
            if(-not(Test-PathSafe $backup)){throw "User-state restore backup missing: $($entry.label)"}
            $bs=Get-AddonUserStateEntrySnapshot -Label ([string]$entry.label) -Path $backup
            if([string]$bs.fingerprint -cne [string]$entry.fingerprint -or [string]$bs.kind -cne [string]$entry.kind){throw "User-state restore backup verification failed: $($entry.label)"}
            if(Test-PathSafe $target){Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop}
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
            if([string]$entry.kind -ceq 'directory'){
                New-Item -ItemType Directory -Force -Path $target|Out-Null
                Copy-DirectoryContentsExact -Source $backup -Destination $target
            }else{Copy-Item -LiteralPath $backup -Destination $target -Force -ErrorAction Stop}
        }else{
            if(Test-PathSafe $target){Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop}
        }
        $post=Get-AddonUserStateEntrySnapshot -Label ([string]$entry.label) -Path $target
        if([bool]$post.exists -ne [bool]$entry.exists -or [string]$post.kind -cne [string]$entry.kind -or [string]$post.fingerprint -cne [string]$entry.fingerprint){throw "User-state restore post-verification failed: $($entry.label)"}
    }
    $check=Test-AddonUserStateSnapshotUnchanged -Guard $Guard
    if(-not[bool]$check.unchanged){throw 'User-state restore did not recover the exact pre-update fingerprint.'}
    return $check
}

function Invoke-AddonUserStateGuardSelfTest {
    $oldLocal=$env:LOCALAPPDATA;$oldRoaming=$env:APPDATA;$oldGuardRoot=$script:AddonUserStateBackupRoot;$fixture=$null
    try{
        $fixture=Join-Path $env:TEMP ('SpotifyControl-UserStateGuard-'+[guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA=Join-Path $fixture 'Local';$env:APPDATA=Join-Path $fixture 'Roaming';$script:AddonUserStateBackupRoot=Join-Path $fixture 'GuardBackups';New-Item -ItemType Directory -Force -Path $script:AddonUserStateBackupRoot|Out-Null
        $localSpotify=Join-Path $env:LOCALAPPDATA 'Spotify';$roamingSpotify=Join-Path $env:APPDATA 'Spotify'
        foreach($d in @(
            (Join-Path $localSpotify 'Browser\IndexedDB\db'),(Join-Path $localSpotify 'Browser\Local Storage\leveldb'),
            (Join-Path $localSpotify 'Default\IndexedDB\db'),(Join-Path $localSpotify 'Default\Local Storage\leveldb'),
            (Join-Path $localSpotify 'IndexedDB\root'),(Join-Path $localSpotify 'Local Storage\root'),
            (Join-Path $localSpotify 'Users\local-user'),(Join-Path $roamingSpotify 'Users\roaming-user'),
            (Join-Path $env:APPDATA 'spicetify'))){New-Item -ItemType Directory -Force -Path $d|Out-Null}
        [IO.File]::WriteAllText((Join-Path $localSpotify 'Browser\IndexedDB\db\tagify.db'),'tagify-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $localSpotify 'Browser\Local Storage\leveldb\marketplace.ldb'),'marketplace-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $localSpotify 'Default\IndexedDB\db\ivlyrics.db'),'ivlyrics-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $localSpotify 'Users\local-user\state.dat'),'local-user-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $roamingSpotify 'Users\roaming-user\state.dat'),'roaming-user-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $roamingSpotify 'prefs'),'prefs-sentinel',[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $env:APPDATA 'spicetify\config-xpui.ini'),'config-sentinel',[Text.UTF8Encoding]::new($false))
        $tx='fixture-'+[guid]::NewGuid().ToString('N');$guard=New-AddonUserStateTransactionBackup -TxId $tx
        if(-not(@($guard.entries|Where-Object{$_.label -ceq 'local-users' -and $_.exists}).Count -eq 1)){throw 'LOCALAPPDATA Spotify Users was not protected.'}
        if(-not(@($guard.entries|Where-Object{$_.label -ceq 'roaming-users' -and $_.exists}).Count -eq 1)){throw 'APPDATA Spotify Users was not protected.'}
        if(-not(Test-AddonUserStateSnapshotUnchanged -Guard $guard).unchanged){throw 'Fresh transaction user-state guard was not unchanged.'}
        [IO.File]::WriteAllText((Join-Path $localSpotify 'Browser\Local Storage\leveldb\marketplace.ldb'),'corrupted-reset-state',[Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath (Join-Path $roamingSpotify 'Users\roaming-user\state.dat') -Force
        if((Test-AddonUserStateSnapshotUnchanged -Guard $guard).unchanged){throw 'User-state drift was not detected.'}
        [void](Restore-AddonUserStateTransactionBackup -Guard $guard -AllowOverwriteCurrent)
        if(-not(Test-AddonUserStateSnapshotUnchanged -Guard $guard).unchanged){throw 'Exact user-state restore failed.'}
        $tx2='fixture-'+[guid]::NewGuid().ToString('N');$guard2=New-AddonUserStateTransactionBackup -TxId $tx2
        if([string]$guard2.before_fingerprint -cne [string]$guard.before_fingerprint){throw 'Second unconditional transaction backup fingerprint drifted.'}
        Write-AddonLog 'Transaction-coupled user-state guard self-test passed: Browser/Default/root storage, local+roaming Users, prefs/config, drift detection, exact restore, and no 168-hour backup gate.'
    }finally{
        $env:LOCALAPPDATA=$oldLocal;$env:APPDATA=$oldRoaming;$script:AddonUserStateBackupRoot=$oldGuardRoot
        if($fixture -and (Test-PathSafe $fixture 'Container')){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
