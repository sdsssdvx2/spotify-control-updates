# V050 HOLD: real-profile-capable, BACKUP-ONLY preimage capture.
# Schema 2 binds entire DPAPI ciphertext bytes; trailing data is forbidden.
# No auto-update entrypoint, Spotify launch/kill, rollback, apply, release
# provenance, new-engine enrollment or production mutation permit is included.
# Manual opt-in is mandatory for a real-profile backup. The only real writes
# this function can make are to a NEW private LocalAppData escrow vault.
# Existing Addon Manager, CustomApps, XPUI, config, preferences and old state
# are inputs only. No originals are deleted, renamed, or written.
# Dot-source after V010, V036/V041/V042, V044, V046, V047, V048.
function Assert-CustomAppV050Path {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$FixtureRoot=$null)
 $p=Assert-XpuiReadOnlyCanonicalV036 -Path $Path -Label 'V050_PATH'
 if(-not[string]::IsNullOrWhiteSpace($FixtureRoot)){
   $fixture=Assert-XpuiReadOnlyCanonicalV036 -Path $FixtureRoot -Label 'V050_FIXTURE_ROOT'
   $runner=Assert-XpuiReadOnlyCanonicalV036 -Path $env:RUNNER_TEMP -Label 'V050_RUNNER'
   if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
      $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
      -not$fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'V050_HOSTED_FIXTURE_OUTSIDE_RUNNER'
   }
 }
 return $p
}
function Get-CustomAppV050BytesHash {
 param([Parameter(Mandatory=$true)][byte[]]$Data)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Dispose()}
}
function ConvertTo-CustomAppV050Sealed {
 param([Parameter(Mandatory=$true)][byte[]]$Plain,[Parameter(Mandatory=$true)][string]$Purpose)
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 $salt=[Text.Encoding]::UTF8.GetBytes('spotify-profile-escrow-v050|'+$Purpose)
 $cipher=[Security.Cryptography.ProtectedData]::Protect($Plain,$salt,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 return ,$cipher
}
function ConvertFrom-CustomAppV050Sealed {
 param([Parameter(Mandatory=$true)][byte[]]$Cipher,[Parameter(Mandatory=$true)][string]$Purpose)
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 $salt=[Text.Encoding]::UTF8.GetBytes('spotify-profile-escrow-v050|'+$Purpose)
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($Cipher,$salt,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 return ,$plain
}
function Write-CustomAppV050NewBytes {
 param([string]$Path,[byte[]]$Bytes)
 $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}
 finally{$stream.Dispose()}
}
function Assert-CustomAppV050PrivateVault {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Initialize)
 $p=Assert-CustomAppV050Path -Path $Path
 if($Initialize){
   if([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)){
     throw 'V050_VAULT_ALREADY_EXISTS'
   }
   $parent=Assert-CustomAppV050Path -Path (Split-Path -Parent $p)
   if(-not[IO.Directory]::Exists($parent)){throw 'V050_VAULT_PARENT_MISSING'}
   # Build the private DACL BEFORE creation; avoid even a transient
   # inherited-ACL window around sensitive Spotify prefs.
   $acl=New-Object Security.AccessControl.DirectorySecurity
   $acl.SetAccessRuleProtection($true,$false)
   $inherit=[Security.AccessControl.InheritanceFlags] 'ContainerInherit, ObjectInherit'
   $propagate=[Security.AccessControl.PropagationFlags]::None
   $right=[Security.AccessControl.FileSystemRights]::FullControl
   $allow=[Security.AccessControl.AccessControlType]::Allow
   foreach($sidText in @(
     [Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
     'S-1-5-18','S-1-5-32-544')){
     $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
     $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,$right,$inherit,$propagate,$allow)))
   }
   [IO.Directory]::CreateDirectory($p,$acl)|Out-Null
 }
 if(-not[IO.Directory]::Exists($p)){throw 'V050_PRIVATE_VAULT_MISSING'}
 $acl=(Get-Item -LiteralPath $p -Force).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
 if(-not$acl.AreAccessRulesProtected){throw 'V050_VAULT_ACL_INHERITANCE_UNSAFE'}
 $allowed=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
 $mine=$false
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
    if([string]$rule.IdentityReference.Value -notin $allowed -or
       $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
       $rule.IsInherited){throw 'V050_VAULT_UNEXPECTED_ACE'}
    if([string]$rule.IdentityReference.Value -ceq $allowed[0] -and
       (([int]$rule.FileSystemRights -band [int][Security.AccessControl.FileSystemRights]::FullControl) -eq
         [int][Security.AccessControl.FileSystemRights]::FullControl)){$mine=$true}
 }
 if(-not$mine){throw 'V050_VAULT_OWNER_FULL_CONTROL_MISSING'}
 return $p
}
function Copy-CustomAppV050BoundTree {
 param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
 $source=Assert-CustomAppV050Path -Path $Source
 $destination=Assert-CustomAppV050Path -Path $Destination
 if(Test-CustomAppUpdatePathsOverlapV010 -A $source -B $destination){throw 'V050_SOURCE_BACKUP_PATH_OVERLAP'}
 if(-not[IO.Directory]::Exists($source) -or [IO.Directory]::Exists($destination) -or [IO.File]::Exists($destination)){
   throw 'V050_TREE_SOURCE_OR_NEW_TARGET_INVALID'
 }
 $snapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 [IO.Directory]::CreateDirectory($destination)|Out-Null
 foreach($entry in @($snapshot.entries)){
   $rel=([string]$entry.path).Replace('/',[IO.Path]::DirectorySeparatorChar)
   $target=Join-Path $destination $rel
   if([string]$entry.type -ceq 'dir'){
     [IO.Directory]::CreateDirectory($target)|Out-Null
   }elseif([string]$entry.type -ceq 'file'){
     [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
     [IO.File]::Copy((Join-Path $source $rel),$target,$false)
   }else{throw 'V050_UNSUPPORTED_TREE_MEMBER'}
 }
 $inputNow=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 $copied=Get-CustomAppUpdateTreeSnapshotV010 -Root $destination
 if([string]$inputNow.tree_sha256 -cne [string]$snapshot.tree_sha256 -or
    [string]$copied.tree_sha256 -cne [string]$snapshot.tree_sha256){
    throw 'V050_SOURCE_RACED_OR_PREIMAGE_COPY_DRIFT'
 }
 return $snapshot
}
function Protect-CustomAppV050GuardFile {
 param([string]$Source,[string]$Destination,[string]$Purpose)
 $src=Assert-CustomAppV050Path -Path $Source
 $dst=Assert-CustomAppV050Path -Path $Destination
 $item=Get-Item -LiteralPath $src -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    [int64]$item.Length -gt 4194304 -or [int64]$item.Length -lt 1){
    throw 'V050_UNSAFE_PROTECTED_SOURCE_FILE'
 }
 $original=[IO.File]::ReadAllBytes($src)
 try{
   if($original.Length -ne [int64]$item.Length){throw 'V050_GUARD_SOURCE_RACED'}
   $pin=Get-CustomAppV050BytesHash -Data $original
   $cipher=ConvertTo-CustomAppV050Sealed -Plain $original -Purpose $Purpose
   try{
      $cipherPin=Get-CustomAppV050BytesHash -Data $cipher
      Write-CustomAppV050NewBytes -Path $dst -Bytes $cipher
   }finally{[Array]::Clear($cipher,0,$cipher.Length)}
   if((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin -or
      (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant() -cne $cipherPin){
     throw 'V050_GUARD_SOURCE_OR_CIPHERTEXT_CHANGED_AFTER_SEAL'
   }
   return [pscustomobject]@{plain_sha256=$pin;cipher_sha256=$cipherPin}
 }finally{[Array]::Clear($original,0,$original.Length)}
}
function Test-CustomAppV050Escrow {
 param([Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$ExpectedReceiptSha256,
       [string]$HostedEscrowRoot=$null)
 try{
   if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
      $EscrowId -cnotmatch '^[a-f0-9]{32}$' -or
      $ExpectedReceiptSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'V050_READER_ARGUMENTS_INVALID'}
   $fixture=-not[string]::IsNullOrWhiteSpace($HostedEscrowRoot)
   if($fixture){
      $runner=Assert-CustomAppV050Path -Path $env:RUNNER_TEMP
      $vault=Assert-CustomAppV050Path -Path $HostedEscrowRoot -FixtureRoot $HostedEscrowRoot
      if(-not$vault.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
         throw 'V050_BACKUP_READER_TEST_PATH_NOT_RUNNER'
      }
   }else{
      if($env:GITHUB_ACTIONS -ceq 'true'){throw 'V050_CI_REAL_PROFILE_READER_FORBIDDEN'}
      $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
      $vault=Assert-CustomAppV050Path -Path (Join-Path $local 'SpotifyControlUpdates-NativeEscrows')
   }
   $vault=Assert-CustomAppV050PrivateVault -Path $vault
   $dir=Assert-CustomAppV050Path -Path (Join-Path $vault ('verified-'+$EscrowId))
   $record=Join-Path $dir 'receipt.dpapi'
   if(-not[IO.Directory]::Exists($dir) -or -not[IO.File]::Exists($record)){
      throw 'V050_READER_VERIFIED_DIRECTORY_MISSING'
   }
   $info=Get-Item -LiteralPath $record -Force -ErrorAction Stop
   if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      [int64]$info.Length -lt 64 -or [int64]$info.Length -gt 65536){
      throw 'V050_RECEIPT_FILE_NOT_TRUSTED'
   }
   $cipher=[IO.File]::ReadAllBytes($record)
   if((Get-CustomAppV050BytesHash -Data $cipher) -cne $ExpectedReceiptSha256){
      throw 'V050_RECEIPT_PIN_CHANGED'
   }
   $plain=ConvertFrom-CustomAppV050Sealed -Cipher $cipher -Purpose ('receipt|'+$EscrowId)
   try{$r=([Text.UTF8Encoding]::new($false,$true).GetString($plain))|ConvertFrom-Json -ErrorAction Stop}
   finally{[Array]::Clear($plain,0,$plain.Length);[Array]::Clear($cipher,0,$cipher.Length)}
   $allowed=@('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')
   $names=@($r.approved_names)
   if([int]$r.schema -ne 2 -or [string]$r.owner -cne 'spotify-profile-preimage-v050' -or
      [string]$r.escrow_id -cne $EscrowId -or
      [bool]$r.production_mutation_authorized -or
      [string]$r.profile_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
      [string]$r.manifest_footprint_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
      $names.Count -lt 1 -or $names.Count -gt 4 -or
      @($names|Where-Object{$_ -notin $allowed}).Count -gt 0 -or
      @($names|Sort-Object -Unique).Count -ne $names.Count){
      throw 'V050_RECEIPT_SCHEMA_OR_SCOPE_UNVERIFIED'
   }
   $entries=@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   if(($entries -join '|') -cne 'preimage|receipt.dpapi'){throw 'V050_EXTRA_BACKUP_ROOT_MEMBER'}
   $pre=Join-Path $dir 'preimage'
   $entries=@(Get-ChildItem -LiteralPath $pre -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   if(($entries -join '|') -cne 'protected|trees'){throw 'V050_EXTRA_PREIMAGE_MEMBER'}
   $trees=Join-Path $pre 'trees'
   $treeNames=@(Get-ChildItem -LiteralPath $trees -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   $expected=@(@('xpui')+$names|Sort-Object)
   if(($treeNames -join '|') -cne ($expected -join '|')){throw 'V050_PREIMAGE_TREE_SET_CHANGED'}
   foreach($key in @('xpui')+$names){
      $s=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $trees $key)
      if([string]$s.tree_sha256 -cne [string]$r.tree_sha256.$key){
        throw 'V050_BACKUP_TREE_HASH_MISMATCH'
      }
   }
   $protected=Join-Path $pre 'protected'
   $protectNames=@(Get-ChildItem -LiteralPath $protected -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   if(($protectNames -join '|') -cne 'config.dpapi|prefs.dpapi|state.dpapi'){
      throw 'V050_PROTECTED_SET_CHANGED'
   }
   foreach($key in @('config','state','prefs')){
     $p=Join-Path $protected ($key+'.dpapi')
     $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
     if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        [int64]$item.Length -lt 16 -or [int64]$item.Length -gt 4198400){
       throw 'V050_PROTECTED_CIPHER_NOT_TRUSTED'
     }
     $enc=[IO.File]::ReadAllBytes($p)
     if([string]$r.protected_cipher_sha256.$key -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-CustomAppV050BytesHash -Data $enc) -cne [string]$r.protected_cipher_sha256.$key){
        throw 'V050_PROTECTED_CIPHERTEXT_FULL_BYTES_CHANGED'
     }
     $value=ConvertFrom-CustomAppV050Sealed -Cipher $enc -Purpose ($EscrowId+'|'+$key)
     try{
       if((Get-CustomAppV050BytesHash -Data $value) -cne [string]$r.protected_sha256.$key){
         throw 'V050_PROTECTED_FILE_SHA_CHANGED'
       }
     }finally{[Array]::Clear($enc,0,$enc.Length);[Array]::Clear($value,0,$value.Length)}
   }
   return [pscustomobject]@{
     ok=$true;status='verified-detached-preimage';escrow_id=$EscrowId
     approved_count=$names.Count;xpui_preimage_sha256=[string]$r.tree_sha256.xpui
     independent_keyless_readback=$true;user_profile_modified=$false
     release_provenance_verified=$false;rollback_authorized=$false
     live_update_authorized=$false;production_mutation_authorized=$false
   }
 }catch{
   return [pscustomobject]@{
     ok=$false;status='blocked';reason='V050_BACKUP_OR_RECEIPT_UNVERIFIED'
     rollback_authorized=$false;live_update_authorized=$false
     production_mutation_authorized=$false
   }
 }
}
function New-CustomAppProfilePreimageEscrowV050 {
 param([Parameter(Mandatory=$true)]$CutoverLease,
       [Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [switch]$ExplicitBackupAuthorization,
       [string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null,
       [string]$HostedEscrowRoot=$null)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    -not$ExplicitBackupAuthorization -or
    $ExpectedProfileSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V050_EXPLICIT_BACKUP_APPROVAL_OR_WINDOWS_REQUIRED'
 }
 $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
 if($fixture){
   if([string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
      [string]::IsNullOrWhiteSpace($HostedEscrowRoot)){
     throw 'V050_HOSTED_FIXTURE_ARGUMENTS_INCOMPLETE'
   }
   $base=Assert-CustomAppV050Path -Path $HostedFixtureRoot -FixtureRoot $HostedFixtureRoot
   $cli=Assert-CustomAppV050Path -Path $HostedFixtureCliPath -FixtureRoot $HostedFixtureRoot
   $local=Assert-CustomAppV050Path -Path (Join-Path $base 'Local')
   $config=Assert-CustomAppV050Path -Path (Join-Path $base 'Roaming\spicetify\config-xpui.ini')
   $vault=Assert-CustomAppV050Path -Path $HostedEscrowRoot -FixtureRoot $HostedEscrowRoot
 }else{
   if(-not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
      -not[string]::IsNullOrWhiteSpace($HostedEscrowRoot) -or
      $env:GITHUB_ACTIONS -ceq 'true'){
      throw 'V050_REAL_PROFILE_PATH_OVERRIDES_FORBIDDEN'
   }
   $local=Assert-CustomAppV050Path -Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
   $config=Assert-CustomAppV050Path -Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'spicetify\config-xpui.ini')
   $cliList=@(Get-Command spicetify -CommandType Application -All -ErrorAction Stop|ForEach-Object{[string]$_.Source}|Sort-Object -Unique)
   if($cliList.Count -ne 1){throw 'V050_OFFICIAL_CLI_NOT_UNIQUE'}
   $cli=Assert-CustomAppV050Path -Path $cliList[0]
   if((Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant() -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
      throw 'V050_OFFICIAL_CLI_PIN_CHANGED'
   }
   $vault=Assert-CustomAppV050Path -Path (Join-Path $local 'SpotifyControlUpdates-NativeEscrows')
 }
 # Before any write: immutable installed profile, manifest and OS lease.
 $args=@{}
 if($fixture){$args=@{HostedFixtureRoot=$base;HostedFixtureCliPath=$cli}}
 $qualified=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 @args
 if([string]$qualified.status -cne 'observed-readonly' -or
    [int]$qualified.approved_manifest_count -lt 1 -or
    [int]$qualified.approved_manifest_count -gt 4 -or
    -not[bool]$qualified.os_turnstile_held_during_audit -or
    [bool]$qualified.production_mutation_authorized){
    throw 'V050_INSTALLED_MANIFEST_OR_SHARED_LOCK_NOT_QUALIFIED'
 }
 $ini=Read-XpuiReadOnlyIniV036 -Path $config
 $spotify=Assert-CustomAppV050Path -Path ([string]$ini['setting.spotify_path'])
 $prefs=Assert-CustomAppV050Path -Path ([string]$ini['setting.prefs_path'])
 $xpui=Assert-CustomAppV050Path -Path (Join-Path $spotify 'Apps\xpui')
 $state=Assert-CustomAppV050Path -Path (Join-Path $local 'SpotifyControl\addons-state.json')
 $userApps=Assert-CustomAppV050Path -Path (Join-Path (Split-Path -Parent $config) 'CustomApps')
 $cliApps=Assert-CustomAppV050Path -Path (Join-Path (Split-Path -Parent $cli) 'CustomApps')
 if(-not[IO.Directory]::Exists($xpui)){throw 'V050_EXTRACTED_XPUI_REQUIRED'}
 $names=@()
 $roots=@{}
 $all=@(([string]$ini['additionaloptions.custom_apps']) -split '\|'|Where-Object{$_})
 foreach($item in $all){
   $n=$item.Trim().ToLowerInvariant()
   if($n -notin @('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')){continue}
   if($roots.ContainsKey($n)){throw 'V050_APPROVED_NAME_DUPLICATE'}
   $p=Assert-CustomAppV050Path -Path (Join-Path $userApps $n)
   $q=Assert-CustomAppV050Path -Path (Join-Path $cliApps $n)
   $a=[IO.Directory]::Exists($p);$b=[IO.Directory]::Exists($q)
   if($a -eq $b){throw 'V050_APPROVED_SOURCE_ORIGIN_AMBIGUOUS'}
   $root=if($a){$p}else{$q}
   $selected=Get-ApprovedAppOriginNestedV041 -Root $root
   if([bool]$selected.nested){throw 'V050_NESTED_UNQUALIFIED'}
   $root=Assert-CustomAppV050Path -Path ([string]$selected.path)
   $manifest=Get-ApprovedNativeManifestOwnedScopeV044 -Name $n -SourceAppPath $root -InstalledReadOnlyAudit
   if([string]$manifest.source_tree_sha256 -cnotmatch '^[a-f0-9]{64}$'){
      throw 'V050_MANIFEST_SOURCE_NOT_PINNED'
   }
   $names+= $n;$roots[$n]=$root
 }
 if($names.Count -ne [int]$qualified.approved_manifest_count){
   throw 'V050_CONFIGURED_APPROVED_SET_CHANGED'
 }
 foreach($v in @($xpui,$state,$config,$prefs)+@($roots.Values)){
   if(Test-CustomAppUpdatePathsOverlapV010 -A $v -B $vault){
      throw 'V050_ESCROW_OVERLAPS_PROTECTED_INPUT'
   }
 }
 $total=[int64]0;$pre=@{}
 $pre['xpui']=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 $total += [int64]$pre['xpui'].total_bytes
 foreach($name in $names){
   $pre[$name]=Get-CustomAppUpdateTreeSnapshotV010 -Root $roots[$name]
   $total += [int64]$pre[$name].total_bytes
 }
 if($total -lt 1 -or $total -gt 805306368){throw 'V050_BACKUP_SIZE_OUT_OF_BOUNDS'}
 foreach($p in @($config,$state,$prefs)){
   $info=Get-Item -LiteralPath $p -Force -ErrorAction Stop
   if($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      [int64]$info.Length -gt 4194304 -or [int64]$info.Length -lt 1){
      throw 'V050_PROTECTED_INPUT_FILE_NOT_BOUNDED'
   }
   $total += [int64]$info.Length
 }
 $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($vault))
 if([int64]$drive.AvailableFreeSpace -lt ($total*2+134217728)){
    throw 'V050_INSUFFICIENT_DISK_FOR_SAFE_ESCROW'
 }
 if(-not[bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $ExpectedProfileSha256 @args).ok){
   throw 'V050_PROFILE_CHANGED_BEFORE_FIRST_WRITE'
 }
 # A new backup root must never double as new-engine DPAPI enrollment.
 if(-not[IO.Directory]::Exists($vault)){
    $vault=Assert-CustomAppV050PrivateVault -Path $vault -Initialize
 }else{
    $vault=Assert-CustomAppV050PrivateVault -Path $vault
 }
 $id=[Guid]::NewGuid().ToString('N')
 $stage=Join-Path $vault ('pending-'+$id)
 $final=Join-Path $vault ('verified-'+$id)
 if([IO.Directory]::Exists($stage) -or [IO.Directory]::Exists($final) -or
    [IO.File]::Exists($stage) -or [IO.File]::Exists($final)){
    throw 'V050_ESCROW_TRANSACTION_COLLISION'
 }
 [IO.Directory]::CreateDirectory($stage)|Out-Null
 $preRoot=Join-Path $stage 'preimage'
 $trees=Join-Path $preRoot 'trees'
 $protect=Join-Path $preRoot 'protected'
 [IO.Directory]::CreateDirectory($trees)|Out-Null
 [IO.Directory]::CreateDirectory($protect)|Out-Null
 $written=@{}
 $written['xpui']=Copy-CustomAppV050BoundTree -Source $xpui -Destination (Join-Path $trees 'xpui')
 foreach($name in $names){
    $written[$name]=Copy-CustomAppV050BoundTree -Source $roots[$name] -Destination (Join-Path $trees $name)
 }
 $shaGuard=@{};$cipherGuard=@{}
 foreach($key in @('config','prefs','state')){
   $src=switch($key){'config'{$config};'prefs'{$prefs};'state'{$state}}
   $result=Protect-CustomAppV050GuardFile -Source $src -Destination (Join-Path $protect ($key+'.dpapi')) -Purpose ($id+'|'+$key)
   $shaGuard[$key]=[string]$result.plain_sha256
   $cipherGuard[$key]=[string]$result.cipher_sha256
 }
 foreach($key in @('xpui')+$names){
   if([string]$pre[$key].tree_sha256 -cne [string]$written[$key].tree_sha256){
      throw 'V050_PREWRITE_SOURCE_AND_BACKUP_DIFFER'
   }
 }
 # V042/V048 don't read prefs; retain the exact protected-file preimages
 # through the actual durable receipt publication boundary.
 foreach($key in @('config','prefs','state')){
   $src=switch($key){'config'{$config};'prefs'{$prefs};'state'{$state}}
   if((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$shaGuard[$key]){
      throw 'V050_PROTECTED_INPUT_CHANGED_BEFORE_PUBLICATION'
   }
 }
 $after=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 @args
 if([string]$after.status -cne 'observed-readonly' -or
    [string]$after.manifest_footprint_sha256 -cne [string]$qualified.manifest_footprint_sha256){
   throw 'V050_PROFILE_CHANGED_DURING_COPY'
 }
 $treePins=@{}
 foreach($key in @('xpui')+$names){$treePins[$key]=[string]$pre[$key].tree_sha256}
 $sourceOrigins=@{}
 foreach($key in $names){$sourceOrigins[$key]=$roots[$key]}
 $receipt=[ordered]@{
   schema=2;owner='spotify-profile-preimage-v050';escrow_id=$id
   profile_sha256=$ExpectedProfileSha256
   manifest_footprint_sha256=[string]$qualified.manifest_footprint_sha256
   approved_names=$names;tree_sha256=$treePins
   protected_sha256=$shaGuard;protected_cipher_sha256=$cipherGuard
   original_xpui=$xpui;original_custom_apps=$sourceOrigins
   original_config=$config;original_prefs=$prefs;original_state=$state
   production_mutation_authorized=$false
 }
 $payload=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Compress -Depth 8))
 try{
   $sealed=ConvertTo-CustomAppV050Sealed -Plain $payload -Purpose ('receipt|'+$id)
   try{Write-CustomAppV050NewBytes -Path (Join-Path $stage 'receipt.dpapi') -Bytes $sealed}
   finally{[Array]::Clear($sealed,0,$sealed.Length)}
 }finally{[Array]::Clear($payload,0,$payload.Length)}
 # Directory.Move fails if another process creates the target; never merge.
 [IO.Directory]::Move($stage,$final)
 $pin=(Get-FileHash -LiteralPath (Join-Path $final 'receipt.dpapi') -Algorithm SHA256).Hash.ToLowerInvariant()
 $readArgs=@{EscrowId=$id;ExpectedReceiptSha256=$pin}
 if($fixture){$readArgs.HostedEscrowRoot=$vault}
 $checked=Test-CustomAppV050Escrow @readArgs
 if(-not[bool]$checked.ok){throw 'V050_PUBLISHED_BACKUP_FAILED_INDEPENDENT_RECHECK'}
 return [pscustomobject]@{
    status='durable-private-backup-only';escrow_id=$id;receipt_sha256=$pin
    approved_count=$names.Count;xpui_file_count=[int]$pre['xpui'].file_count
    backup_private_acl_verified=$true;guard_files_dpapi_sealed=$true
    user_originals_unchanged=$true;future_recovery_source_verified=$true
    production_restore_verified=$false;offline_other_account_recovery_proven=$false
    new_engine_enrollment_created=$false;rollback_authorized=$false
    live_update_authorized=$false;production_mutation_authorized=$false
 }
}
