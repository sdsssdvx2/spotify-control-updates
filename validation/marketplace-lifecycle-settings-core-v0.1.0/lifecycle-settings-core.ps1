function Get-AddonLifecycleKey {
    param([string]$Kind,[string]$Name)
    if ([string]::IsNullOrWhiteSpace($Kind) -or [string]::IsNullOrWhiteSpace($Name)) { throw 'Lifecycle kind/name cannot be empty.' }
    $k=$Kind.Trim().ToLowerInvariant();$n=$Name.Trim().ToLowerInvariant()
    if($k -notin @('custom-app','extension')){throw "Unsupported lifecycle kind: $Kind"}
    return ($k+':' + $n)
}

function Ensure-AddonLifecycleState {
    param($State,[string]$Key)
    $State=Normalize-AddonStateObject $State
    if([string]::IsNullOrWhiteSpace($Key)){throw 'Lifecycle key cannot be empty.'}
    if(-not $State.lifecycle.PSObject.Properties[$Key]){$State.lifecycle|Add-Member -NotePropertyName $Key -NotePropertyValue ([pscustomobject]@{})}
    $row=$State.lifecycle.PSObject.Properties[$Key].Value
    if($null -eq $row){$row=[pscustomobject]@{};$State.lifecycle.PSObject.Properties[$Key].Value=$row}
    foreach($entry in @(
        @('key',$Key),@('managed_by','dynamic-spicetify-v1'),@('kind',$null),@('name',$null),@('present',$false),
        @('first_seen',$null),@('last_seen',$null),@('last_absent',$null),@('user_removed',$false),@('removed_at',$null),
        @('reinstalled_at',$null),@('ownership','local-spicetify-observed'),@('source_identity',$null),
        @('mutation_mode','deny'),@('locations',@()),@('ambiguous',$false),@('safe_local_identity',$false)
    )){[void](Ensure-ObjectNoteProperty -Object $row -Name ([string]$entry[0]) -DefaultValue $entry[1])}
    return $row
}

function Update-AddonLifecycleObservations {
    param($State,[object[]]$Observations,[string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')),[string[]]$TransactionOwnedAbsenceKeys=@())
    $State=Normalize-AddonStateObject $State
    $seen=@{};$added=0;$removed=0;$reinstalled=0
    foreach($obs in @($Observations)){
        if($null -eq $obs){continue}
        $key=Get-AddonLifecycleKey -Kind ([string]$obs.kind) -Name ([string]$obs.name)
        if($seen.ContainsKey($key)){throw "Duplicate lifecycle observation: $key"};$seen[$key]=$true
        $isNew=(-not $State.lifecycle.PSObject.Properties[$key])
        $row=Ensure-AddonLifecycleState -State $State -Key $key
        if($isNew){$added++}
        $wasRemoved=[bool]$row.user_removed
        $wasPresent=[bool]$row.present
        $row.kind=[string]$obs.kind;$row.name=[string]$obs.name;$row.present=$true
        if(-not $row.first_seen){$row.first_seen=$ObservedAt};$row.last_seen=$ObservedAt
        $row.ownership=$(if($obs.PSObject.Properties['ownership']){[string]$obs.ownership}else{'local-spicetify-observed'})
        $row.source_identity=$(if($obs.PSObject.Properties['source_identity']){[string]$obs.source_identity}else{$null})
        $row.locations=@($(if($obs.PSObject.Properties['locations']){@($obs.locations)}else{@()}))
        $row.ambiguous=$(if($obs.PSObject.Properties['ambiguous']){[bool]$obs.ambiguous}else{$false})
        $row.safe_local_identity=$(if($obs.PSObject.Properties['safe_local_identity']){[bool]$obs.safe_local_identity}else{$false})
        $row.mutation_mode='deny'
        if($wasRemoved){$row.user_removed=$false;$row.reinstalled_at=$ObservedAt;$reinstalled++}
        if(-not $wasPresent -and -not $isNew){$row.last_absent=$row.last_absent}
    }
    $owned=@{};foreach($k in @($TransactionOwnedAbsenceKeys)){if(-not [string]::IsNullOrWhiteSpace($k)){$owned[$k.ToLowerInvariant()]=$true}}
    foreach($prop in @($State.lifecycle.PSObject.Properties)){
        $key=[string]$prop.Name;$row=$prop.Value
        if([string]$row.managed_by -cne 'dynamic-spicetify-v1' -or $seen.ContainsKey($key)){continue}
        if([bool]$row.present){
            $row.present=$false;$row.last_absent=$ObservedAt
            if(-not $owned.ContainsKey($key.ToLowerInvariant())){$row.user_removed=$true;$row.removed_at=$ObservedAt;$removed++}
        }
    }
    return [pscustomobject]@{schema=1;observed_at=$ObservedAt;present_count=$seen.Count;new_count=$added;removed_count=$removed;reinstalled_count=$reinstalled;entries=@($State.lifecycle.PSObject.Properties).Count}
}

function Test-AddonLifecycleAutoInstallAllowed {
    param($State,[string]$Kind,[string]$Name)
    $State=Normalize-AddonStateObject $State;$key=Get-AddonLifecycleKey -Kind $Kind -Name $Name
    if(-not $State.lifecycle.PSObject.Properties[$key]){return $false}
    $row=Ensure-AddonLifecycleState -State $State -Key $key
    return ([bool]$row.present -and -not [bool]$row.user_removed)
}

function Get-DynamicSpicetifyAssetObservations {
    param([string[]]$CustomAppRoots=$(Get-SpicetifyAssetRoots -Kind 'CustomApp'),[string[]]$ExtensionRoots=$(Get-SpicetifyAssetRoots -Kind 'Extension'))
    $buckets=@{}
    foreach($spec in @([pscustomobject]@{kind='custom-app';roots=@($CustomAppRoots)},[pscustomobject]@{kind='extension';roots=@($ExtensionRoots)})){
        foreach($root in @($spec.roots)){
            if([string]::IsNullOrWhiteSpace([string]$root) -or -not (Test-PathSafe $root 'Container')){continue}
            $entries=if($spec.kind -ceq 'custom-app'){@(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)}else{@(Get-ChildItem -LiteralPath $root -File -Filter '*.js' -Force -ErrorAction Stop)}
            foreach($entry in $entries){
                $name=[string]$entry.Name;$key=Get-AddonLifecycleKey -Kind $spec.kind -Name $name
                if(-not $buckets.ContainsKey($key)){$buckets[$key]=New-Object System.Collections.Generic.List[object]}
                $buckets[$key].Add($entry)
            }
        }
    }
    $result=New-Object System.Collections.Generic.List[object]
    foreach($key in @($buckets.Keys|Sort-Object)){
        $entries=@($buckets[$key]);$first=$entries[0];$kind=$key.Substring(0,$key.IndexOf(':'))
        $reparse=@($entries|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count -gt 0
        $result.Add([pscustomobject]@{kind=$kind;name=[string]$first.Name;ownership='local-spicetify-observed';source_identity=$null;locations=@($entries|ForEach-Object{$_.FullName});ambiguous=($entries.Count -gt 1);safe_local_identity=(-not $reparse -and $entries.Count -eq 1)})
    }
    return $result.ToArray()
}

function Get-StringSha256Lower {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
}

function Get-PathContentFingerprint {
    param([string]$Path,[ValidateSet('File','Directory')][string]$Kind)
    $exists=if($Kind -ceq 'File'){Test-PathSafe $Path 'Leaf'}else{Test-PathSafe $Path 'Container'}
    if(-not $exists){return [pscustomobject]@{exists=$false;kind=$Kind;file_count=0;byte_count=[int64]0;fingerprint=(Get-StringSha256Lower ('absent|'+$Kind))}}
    $root=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Protected persistence root is a reparse point: $Path"}
    if($Kind -ceq 'File'){
        $h=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant();$len=[int64]$root.Length
        return [pscustomobject]@{exists=$true;kind=$Kind;file_count=1;byte_count=$len;fingerprint=(Get-StringSha256Lower ("F|$len|$h"))}
    }
    $base=[IO.Path]::GetFullPath($Path).TrimEnd([char]92);$lines=New-Object System.Collections.Generic.List[string];$bytes=[int64]0;$count=0
    foreach($entry in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop)){
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Protected persistence tree contains a reparse point: $($entry.FullName)"}
        if($entry.PSIsContainer){continue}
        $rel=$entry.FullName.Substring($base.Length).TrimStart([char]92).Replace('\\','/')
        $h=(Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$len=[int64]$entry.Length
        $lines.Add(("F|{0}|{1}|{2}" -f $rel,$len,$h));$bytes+=$len;$count++
    }
    $arr=@($lines.ToArray());[Array]::Sort($arr,[StringComparer]::Ordinal)
    $canon=if($arr.Count -gt 0){$arr -join "`n"}else{'EMPTY-DIRECTORY'}
    return [pscustomobject]@{exists=$true;kind=$Kind;file_count=$count;byte_count=$bytes;fingerprint=(Get-StringSha256Lower $canon)}
}

function Get-SpotifyPersistenceSurfaceDefinitions {
    param([string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA)
    if([string]::IsNullOrWhiteSpace($LocalAppDataRoot) -or [string]::IsNullOrWhiteSpace($AppDataRoot)){throw 'Persistence roots are unavailable.'}
    $spotify=Join-Path $LocalAppDataRoot 'Spotify';$rows=New-Object System.Collections.Generic.List[object]
    foreach($profile in @('Browser','Default')){
        foreach($name in @('IndexedDB','Local Storage','Session Storage','WebStorage')){$rows.Add([pscustomobject]@{id=(($profile+'-'+$name).ToLowerInvariant().Replace(' ', '-'));kind='Directory';path=(Join-Path (Join-Path $spotify $profile) $name)})}
        foreach($name in @('Local State','Preferences')){$rows.Add([pscustomobject]@{id=(($profile+'-'+$name).ToLowerInvariant().Replace(' ', '-'));kind='File';path=(Join-Path (Join-Path $spotify $profile) $name)})}
    }
    foreach($name in @('IndexedDB','Local Storage')){$rows.Add([pscustomobject]@{id=(('root-'+$name).ToLowerInvariant().Replace(' ', '-'));kind='Directory';path=(Join-Path $spotify $name)})}
    $rows.Add([pscustomobject]@{id='spicetify-config';kind='File';path=(Join-Path $AppDataRoot 'spicetify\config-xpui.ini')})
    return $rows.ToArray()
}

function Get-SpotifyPersistenceSnapshot {
    param([string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA)
    $rows=New-Object System.Collections.Generic.List[object];$canon=New-Object System.Collections.Generic.List[string]
    foreach($def in @(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot)){
        $fp=Get-PathContentFingerprint -Path ([string]$def.path) -Kind ([string]$def.kind)
        $row=[pscustomobject]@{id=[string]$def.id;kind=[string]$def.kind;exists=[bool]$fp.exists;file_count=[int]$fp.file_count;byte_count=[int64]$fp.byte_count;fingerprint=[string]$fp.fingerprint}
        $rows.Add($row);$canon.Add(("{0}|{1}|{2}|{3}|{4}|{5}" -f $row.id,$row.kind,$row.exists,$row.file_count,$row.byte_count,$row.fingerprint))
    }
    $arr=@($canon.ToArray());[Array]::Sort($arr,[StringComparer]::Ordinal)
    return [pscustomobject]@{schema=1;fingerprint=(Get-StringSha256Lower ($arr -join "`n"));surface_count=$rows.Count;surfaces=$rows.ToArray()}
}

function New-RequiredSpotifyPersistenceBackup {
    param([string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA,[string]$BackupRootOverride=$DataBackupRoot)
    $live=([string]$LocalAppDataRoot -ceq [string]$env:LOCALAPPDATA -and [string]$AppDataRoot -ceq [string]$env:APPDATA)
    if($live -and (Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1)){throw 'Spotify is running; refusing required persistence backup.'}
    $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    $id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8);$dest=Join-Path $BackupRootOverride ('txn-'+$id)
    New-Item -ItemType Directory -Force -Path (Join-Path $dest 'surfaces')|Out-Null
    $defs=@{};foreach($d in @(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot)){$defs[[string]$d.id]=$d}
    foreach($surface in @($before.surfaces)){
        if(-not [bool]$surface.exists){continue};$def=$defs[[string]$surface.id];$target=Join-Path (Join-Path $dest 'surfaces') ([string]$surface.id)
        if([string]$surface.kind -ceq 'Directory'){Copy-TreeSafe -Source ([string]$def.path) -Destination $target|Out-Null}else{New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null;Copy-Item -LiteralPath ([string]$def.path) -Destination $target -Force}
        $copyFp=Get-PathContentFingerprint -Path $target -Kind ([string]$surface.kind)
        if([string]$copyFp.fingerprint -cne [string]$surface.fingerprint){throw "Required persistence backup verification failed: $($surface.id)"}
    }
    $manifest=[pscustomobject]@{schema=1;created_at=(Get-Date).ToString('o');manager_version=$Version;before=$before}
    $manifest|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $dest 'guard-manifest.json') -Encoding UTF8
    return [pscustomobject]@{schema=1;path=$dest;fingerprint=[string]$before.fingerprint;surface_count=[int]$before.surface_count}
}

function Restore-SpotifyPersistenceBackup {
    param([string]$BackupPath,[string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA)
    if(Get-Process Spotify -ErrorAction SilentlyContinue|Select-Object -First 1){throw 'Spotify is running; refusing persistence restore.'}
    $manifestPath=Join-Path $BackupPath 'guard-manifest.json';if(-not(Test-PathSafe $manifestPath 'Leaf')){throw 'Persistence guard manifest missing.'}
    $m=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json;if([int]$m.schema -ne 1){throw 'Unsupported persistence guard schema.'}
    $defs=@{};foreach($d in @(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot)){$defs[[string]$d.id]=$d}
    foreach($surface in @($m.before.surfaces)){
        $id=[string]$surface.id;if(-not $defs.ContainsKey($id)){throw "Unknown persistence surface in backup: $id"};$def=$defs[$id]
        $current=Get-PathContentFingerprint -Path ([string]$def.path) -Kind ([string]$def.kind)
        if([bool]$current.exists){Remove-Item -LiteralPath ([string]$def.path) -Recurse -Force -ErrorAction Stop}
        if([bool]$surface.exists){
            $source=Join-Path (Join-Path $BackupPath 'surfaces') $id;$copyFp=Get-PathContentFingerprint -Path $source -Kind ([string]$surface.kind)
            if([string]$copyFp.fingerprint -cne [string]$surface.fingerprint){throw "Persistence backup copy drifted: $id"}
            if([string]$surface.kind -ceq 'Directory'){Copy-TreeSafe -Source $source -Destination ([string]$def.path)|Out-Null}else{New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([string]$def.path))|Out-Null;Copy-Item -LiteralPath $source -Destination ([string]$def.path) -Force}
        }
    }
    $after=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    if([string]$after.fingerprint -cne [string]$m.before.fingerprint){throw 'Persistence restore post-verification fingerprint mismatch.'}
    return $after
}

function Invoke-LifecycleSettingsCoreSelfTest {
    try {
        $lcState=Normalize-AddonStateObject ([pscustomobject]@{})
        $t0='2026-01-01T00:00:00.0000000+00:00';$t1='2026-01-02T00:00:00.0000000+00:00';$t2='2026-01-03T00:00:00.0000000+00:00'
        $obs=[pscustomobject]@{kind='custom-app';name='future-addon';ownership='local-spicetify-observed';locations=@('C:\fixture\future-addon');ambiguous=$false;safe_local_identity=$true}
        $s1=Update-AddonLifecycleObservations -State $lcState -Observations @($obs) -ObservedAt $t0
        $row=Ensure-AddonLifecycleState -State $lcState -Key 'custom-app:future-addon'
        if(-not $row.present -or $row.user_removed -or (Test-AddonLifecycleAutoInstallAllowed -State $lcState -Kind 'custom-app' -Name 'future-addon') -ne $true){throw 'Lifecycle first-seen fixture failed.'}
        $s2=Update-AddonLifecycleObservations -State $lcState -Observations @() -ObservedAt $t1
        if($row.present -or -not $row.user_removed -or (Test-AddonLifecycleAutoInstallAllowed -State $lcState -Kind 'custom-app' -Name 'future-addon')){throw 'Lifecycle user-delete tombstone fixture failed.'}
        $s3=Update-AddonLifecycleObservations -State $lcState -Observations @($obs) -ObservedAt $t2
        if(-not $row.present -or $row.user_removed -or [string]$row.reinstalled_at -cne $t2){throw 'Lifecycle reinstall clears tombstone fixture failed.'}
        if([string]$row.mutation_mode -cne 'deny'){throw 'New lifecycle asset gained mutation authority.'}

        $fixtureRoot=Join-Path $env:TEMP ('SpotifyControl-PersistenceGuardFixture-'+[guid]::NewGuid().ToString('N'))
        $localRoot=Join-Path $fixtureRoot 'Local';$appRoot=Join-Path $fixtureRoot 'Roaming';$guardRoot=Join-Path $fixtureRoot 'Backups'
        $ls=Join-Path $localRoot 'Spotify\Browser\Local Storage\leveldb';New-Item -ItemType Directory -Force -Path $ls|Out-Null
        [IO.File]::WriteAllBytes((Join-Path $ls '000001.ldb'),[Text.Encoding]::UTF8.GetBytes('marketplace:installed:fixture'))
        $cfg=Join-Path $appRoot 'spicetify\config-xpui.ini';New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg)|Out-Null
        [IO.File]::WriteAllText($cfg,"[AdditionalOptions]`nextensions = fixture.js",[Text.UTF8Encoding]::new($false))
        $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
        $guard=New-RequiredSpotifyPersistenceBackup -LocalAppDataRoot $localRoot -AppDataRoot $appRoot -BackupRootOverride $guardRoot
        if([string]$guard.fingerprint -cne [string]$before.fingerprint){throw 'Required persistence backup did not pin the exact pre-update fingerprint.'}
        [IO.File]::AppendAllText((Join-Path $ls '000001.ldb'),'drift',[Text.UTF8Encoding]::new($false))
        $drift=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
        if([string]$drift.fingerprint -ceq [string]$before.fingerprint){throw 'Persistence drift fixture was not detected.'}
        $restored=Restore-SpotifyPersistenceBackup -BackupPath ([string]$guard.path) -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
        if([string]$restored.fingerprint -cne [string]$before.fingerprint){throw 'Persistence rollback fixture failed exact restoration.'}
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-AddonLog 'Settings-preserving lifecycle core self-test passed: first-seen/delete tombstone/reinstall semantics plus exact persistence drift detection and verified restore.'
    } catch {
        if($fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
        throw "Settings-preserving lifecycle core self-test failed: $($_.Exception.Message)"
    }
}
