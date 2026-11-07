# V051: explicit private detached reconstruction from V050 sealed backup.
# This module has no in-place Spotify/Spicetify/Addon Manager mutation entry.
# Its only output is one fresh, owner-private recovery directory UNDER the
# existing V050 vault. Original backup bytes are never moved or replaced.
# For current-user Windows DPAPI only; NOT off-device disaster recovery.
# Prerequisites: V010, V036 and guarded-profile-escrow-v050.ps1.
function Assert-CustomAppV051Vault {
 param([string]$HostedEscrowRoot=$null)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
   throw 'V051_WINDOWS_ONLY'
 }
 if([string]::IsNullOrWhiteSpace($HostedEscrowRoot)){
   if($env:GITHUB_ACTIONS -ceq 'true'){
     throw 'V051_PRODUCTION_PROFILE_FORBIDDEN_ON_CI'
   }
   $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
   $vault=Assert-CustomAppV050Path -Path (Join-Path $local 'SpotifyControlUpdates-NativeEscrows')
 }else{
   if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
      $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
      [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      throw 'V051_HOSTED_OVERRIDE_NOT_GITHUB_RUNNER'
   }
   $vault=Assert-CustomAppV050Path -Path $HostedEscrowRoot -FixtureRoot $HostedEscrowRoot
 }
 return Assert-CustomAppV050PrivateVault -Path $vault
}
function Get-CustomAppV051Receipt {
 param([string]$EscrowId,[string]$ReceiptSha256,[string]$Vault)
 if($EscrowId -cnotmatch '^[a-f0-9]{32}$' -or
    $ReceiptSha256 -cnotmatch '^[a-f0-9]{64}$'){
   throw 'V051_BACKUP_ID_OR_PIN_INVALID'
 }
 $readArgs=@{EscrowId=$EscrowId;ExpectedReceiptSha256=$ReceiptSha256}
 if($env:GITHUB_ACTIONS -ceq 'true'){$readArgs.HostedEscrowRoot=$Vault}
 $checked=Test-CustomAppV050Escrow @readArgs
 if(-not[bool]$checked.ok -or [bool]$checked.live_update_authorized){
   throw 'V051_V050_SEALED_PREIMAGE_NOT_VERIFIED'
 }
 $source=Assert-CustomAppV050Path -Path (Join-Path $Vault ('verified-'+$EscrowId))
 $receipt=Assert-CustomAppV050Path -Path (Join-Path $source 'receipt.dpapi')
 $blob=[IO.File]::ReadAllBytes($receipt)
 if((Get-CustomAppV050BytesHash -Data $blob) -cne $ReceiptSha256){
   throw 'V051_RECEIPT_FULL_CIPHERTEXT_CHANGED'
 }
 $plain=ConvertFrom-CustomAppV050Sealed -Cipher $blob -Purpose ('receipt|'+$EscrowId)
 try{
   $r=[Text.UTF8Encoding]::new($false,$true).GetString($plain)|ConvertFrom-Json -ErrorAction Stop
 }finally{
   [Array]::Clear($blob,0,$blob.Length)
   [Array]::Clear($plain,0,$plain.Length)
 }
 $names=@($r.approved_names)
 if([int]$r.schema -ne 2 -or
    [string]$r.owner -cne 'spotify-profile-preimage-v050' -or
    [string]$r.escrow_id -cne $EscrowId -or
    [bool]$r.production_mutation_authorized -or
    $names.Count -lt 1 -or $names.Count -gt 4 -or
    @($names|Where-Object{$_ -notin @('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')}).Count -ne 0 -or
    @($names|Sort-Object -Unique).Count -ne $names.Count){
   throw 'V051_RECEIPT_SCOPE_OR_OWNERSHIP_UNVERIFIED'
 }
 foreach($k in @('xpui')+$names){
    if([string]$r.tree_sha256.$k -cnotmatch '^[a-f0-9]{64}$'){
      throw 'V051_TREE_SHA_MISSING'
    }
 }
 foreach($k in @('config','state','prefs')){
    if([string]$r.protected_sha256.$k -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.protected_cipher_sha256.$k -cnotmatch '^[a-f0-9]{64}$'){
       throw 'V051_PROTECTED_SHA_MISSING'
    }
 }
 return [pscustomobject]@{source=$source;receipt=$r;names=$names}
}
function Test-CustomAppV051DetachedRecovery {
 param([Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$ReceiptSha256,
       [string]$HostedEscrowRoot=$null)
 try{
   $vault=Assert-CustomAppV051Vault -HostedEscrowRoot $HostedEscrowRoot
   $p=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 $ReceiptSha256 -Vault $vault
   $target=Assert-CustomAppV050Path -Path (Join-Path $vault ('reconstructed-v051-'+$EscrowId))
   if(-not[IO.Directory]::Exists($target)){throw 'V051_VERIFIED_DETACHED_DIRECTORY_ABSENT'}
   $entries=@(Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   if(($entries -join '|') -cne 'guard|trees'){throw 'V051_UNEXPECTED_DETACHED_ROOT_MEMBERS'}
   $treeFolder=Assert-CustomAppV050Path -Path (Join-Path $target 'trees')
   $actual=@(Get-ChildItem -LiteralPath $treeFolder -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   $expected=@(@('xpui')+$p.names|Sort-Object)
   if(($actual -join '|') -cne ($expected -join '|')){throw 'V051_DETACHED_TREE_SET_CHANGED'}
   [int]$xpuiFiles=0
   foreach($n in @('xpui')+$p.names){
     $tree=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $treeFolder $n)
     if([string]$tree.tree_sha256 -cne [string]$p.receipt.tree_sha256.$n){
       throw 'V051_RECONSTRUCTED_TREE_TAMPER'
     }
     if($n -ceq 'xpui'){$xpuiFiles=[int]$tree.file_count}
   }
   $guards=Assert-CustomAppV050Path -Path (Join-Path $target 'guard')
   $guardNames=@(Get-ChildItem -LiteralPath $guards -Force -ErrorAction Stop|ForEach-Object{$_.Name}|Sort-Object)
   if(($guardNames -join '|') -cne 'config.ini|legacy-state.json|prefs'){
     throw 'V051_UNEXPECTED_GUARD_FILES'
   }
   $map=@{config='config.ini';prefs='prefs';state='legacy-state.json'}
   foreach($key in @('config','prefs','state')){
     $item=Assert-CustomAppV050Path -Path (Join-Path $guards $map[$key])
     $info=Get-Item -LiteralPath $item -Force -ErrorAction Stop
     if($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        [int64]$info.Length -gt 4194304 -or [int64]$info.Length -lt 1){
       throw 'V051_RECOVERED_PROTECTED_FILE_INVALID'
     }
     if((Get-FileHash -LiteralPath $item -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$p.receipt.protected_sha256.$key){
        throw 'V051_RECOVERED_GUARD_HASH_CHANGED'
     }
   }
   return [pscustomobject]@{
      ok=$true;status='detached-private-recovery-verified'
      xpui_file_count=$xpuiFiles;approved_app_count=$p.names.Count
      protected_file_count=3;source_backup_unchanged=$true
      no_spotify_write=$true;no_operating_rollback=$true
      production_mutation_authorized=$false;live_update_authorized=$false
   }
 }catch{
   return [pscustomobject]@{
      ok=$false;status='blocked';reason='V051_PRIVATE_RECOVERY_NOT_VERIFIED'
      production_mutation_authorized=$false;live_update_authorized=$false
   }
 }
}
function Invoke-CustomAppV051PrivateDetachedRecovery {
 param([Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$ReceiptSha256,
       [switch]$ExplicitDetachedRecoveryAuthorization,
       [string]$HostedEscrowRoot=$null)
 if(-not[bool]$ExplicitDetachedRecoveryAuthorization){
   throw 'V051_EXPLICIT_DETACHED_RECOVERY_AUTHORIZATION_REQUIRED'
 }
 $vault=Assert-CustomAppV051Vault -HostedEscrowRoot $HostedEscrowRoot
 $p=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 $ReceiptSha256 -Vault $vault
 # One recovery per bound receipt, no pre-existing directory overwrite.
 $stage=Assert-CustomAppV050Path -Path (Join-Path $vault ('pending-recovery-v051-'+$EscrowId))
 $target=Assert-CustomAppV050Path -Path (Join-Path $vault ('reconstructed-v051-'+$EscrowId))
 $lockName=Join-Path $vault '.private-recovery-v051.lock'
 $lease=$null
 try{
   $lease=[IO.File]::Open($lockName,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   foreach($d in @($stage,$target)){
     if([IO.File]::Exists($d) -or [IO.Directory]::Exists($d)){
       throw 'V051_RECONSTRUCTION_STAGE_OR_TARGET_ALREADY_EXISTS'
     }
   }
   $bytes=[int64]0
   foreach($n in @('xpui')+$p.names){
     $s=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $p.source ('preimage\trees\'+$n))
     if([string]$s.tree_sha256 -cne [string]$p.receipt.tree_sha256.$n){
       throw 'V051_PREIMAGE_CHANGED_BEFORE_RECONSTRUCT'
     }
     $bytes += [int64]$s.total_bytes
   }
   $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($vault))
   if($bytes -lt 1 -or $bytes -gt 805306368 -or
      [int64]$drive.AvailableFreeSpace -lt ($bytes+134217728)){
       throw 'V051_INSUFFICIENT_SAFE_RECOVERY_DISK'
   }
   [IO.Directory]::CreateDirectory((Join-Path $stage 'trees'))|Out-Null
   [IO.Directory]::CreateDirectory((Join-Path $stage 'guard'))|Out-Null
   foreach($n in @('xpui')+$p.names){
      $src=Join-Path $p.source ('preimage\trees\'+$n)
      $dst=Join-Path $stage ('trees\'+$n)
      $out=Copy-CustomAppV050BoundTree -Source $src -Destination $dst
      if([string]$out.tree_sha256 -cne [string]$p.receipt.tree_sha256.$n){
         throw 'V051_RECONSTRUCTED_TREE_HASH_MISMATCH'
      }
   }
   $mapping=@{config='config.ini';prefs='prefs';state='legacy-state.json'}
   foreach($key in @('config','state','prefs')){
     $src=Assert-CustomAppV050Path -Path (Join-Path $p.source ('preimage\protected\'+$key+'.dpapi'))
     $cipher=[IO.File]::ReadAllBytes($src)
     try{
       if((Get-CustomAppV050BytesHash -Data $cipher) -cne [string]$p.receipt.protected_cipher_sha256.$key){
         throw 'V051_CIPHERTEXT_CHANGED_DURING_RESTORE'
       }
       $plain=ConvertFrom-CustomAppV050Sealed -Cipher $cipher -Purpose ($EscrowId+'|'+$key)
       try{
         if((Get-CustomAppV050BytesHash -Data $plain) -cne [string]$p.receipt.protected_sha256.$key){
           throw 'V051_DECRYPTED_GUARD_NOT_AUTHENTIC'
         }
         $dest=Join-Path $stage ('guard\'+$mapping[$key])
         Write-CustomAppV050NewBytes -Path $dest -Bytes $plain
         if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$p.receipt.protected_sha256.$key){
           throw 'V051_GUARD_RECOVERY_HASH_CHANGED'
         }
       }finally{[Array]::Clear($plain,0,$plain.Length)}
     }finally{[Array]::Clear($cipher,0,$cipher.Length)}
   }
   # Reject a raced or tampered V050 source before publishing any recovery.
   $now=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 $ReceiptSha256 -Vault $vault
   if(($now.names -join '|') -cne ($p.names -join '|')){
     throw 'V051_RECEIPT_CHANGED_BEFORE_RECOVERY_PUBLICATION'
   }
   foreach($n in @('xpui')+$p.names){
     if((Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $stage ('trees\'+$n))).tree_sha256 -cne [string]$p.receipt.tree_sha256.$n){
       throw 'V051_FINAL_STAGED_TREE_VERIFICATION_FAILED'
     }
   }
   foreach($key in @('config','prefs','state')){
     if((Get-FileHash -LiteralPath (Join-Path $stage ('guard\'+$mapping[$key])) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$p.receipt.protected_sha256.$key){
       throw 'V051_FINAL_STAGED_GUARD_VERIFICATION_FAILED'
     }
   }
   if([IO.Directory]::Exists($target) -or [IO.File]::Exists($target)){
     throw 'V051_RECOVERY_TARGET_CONCURRENTLY_CREATED'
   }
   [IO.Directory]::Move($stage,$target)
   $finalArgs=@{EscrowId=$EscrowId;ReceiptSha256=$ReceiptSha256}
   if(-not[string]::IsNullOrWhiteSpace($HostedEscrowRoot)){$finalArgs.HostedEscrowRoot=$HostedEscrowRoot}
   $verified=Test-CustomAppV051DetachedRecovery @finalArgs
   if(-not[bool]$verified.ok){throw 'V051_PUBLISHED_PRIVATE_RECOVERY_NOT_VERIFIED'}
   return [pscustomobject]@{
     ok=$true;status='detached-private-recovery-created'
     xpui_file_count=$verified.xpui_file_count;approved_app_count=$verified.approved_app_count
     protected_file_count=$verified.protected_file_count
     original_spotify_unchanged=$true;original_backup_retained=$true
     current_user_dpapi_only=$true;no_operating_restore=$true
     production_mutation_authorized=$false;live_update_authorized=$false
   }
 }finally{
   if($null-ne$lease){$lease.Dispose()}
 }
}
