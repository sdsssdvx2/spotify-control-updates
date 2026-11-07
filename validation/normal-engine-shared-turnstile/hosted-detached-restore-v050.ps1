# V050 hosted Windows-only detached restoration of verified backup
# into the SAME PRIVATE VAULT. Never operates on real installed Spotify.
# Dot-source after V010, V036 and guarded-profile-escrow-v050.
function Invoke-CustomAppHostedDetachedRestoreV050 {
 param([Parameter(Mandatory=$true)][string]$HostedEscrowRoot,
       [Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$ExpectedReceiptSha256)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'V050_HOSTED_RESTORE_ONLY'
 }
 $vault=Assert-CustomAppV050Path -Path $HostedEscrowRoot -FixtureRoot $HostedEscrowRoot
 $preflight=Test-CustomAppV050Escrow -EscrowId $EscrowId -ExpectedReceiptSha256 $ExpectedReceiptSha256 -HostedEscrowRoot $vault
 if(-not[bool]$preflight.ok -or [bool]$preflight.production_mutation_authorized){
    throw 'V050_DETACHED_BACKUP_NOT_QUALIFIED'
 }
 $source=Join-Path $vault ('verified-'+$EscrowId)
 $stage=Join-Path $vault ('pending-detached-'+$EscrowId)
 $target=Join-Path $vault ('detached-'+$EscrowId)
 foreach($p in @($stage,$target)){
   if([IO.Directory]::Exists($p) -or [IO.File]::Exists($p)){
     throw 'V050_DETACHED_DESTINATION_ALREADY_EXISTS'
   }
 }
 $cipher=[IO.File]::ReadAllBytes((Join-Path $source 'receipt.dpapi'))
 if((Get-CustomAppV050BytesHash -Data $cipher) -cne $ExpectedReceiptSha256){
   throw 'V050_DETACHED_RECEIPT_SHA_DRIFT'
 }
 $plain=ConvertFrom-CustomAppV050Sealed -Cipher $cipher -Purpose ('receipt|'+$EscrowId)
 try{
   $r=([Text.UTF8Encoding]::new($false,$true).GetString($plain))|ConvertFrom-Json -ErrorAction Stop
 }finally{[Array]::Clear($cipher,0,$cipher.Length);[Array]::Clear($plain,0,$plain.Length)}
 if([int]$r.schema -ne 2 -or
    [string]$r.owner -cne 'spotify-profile-preimage-v050' -or
    [string]$r.escrow_id -cne $EscrowId -or [bool]$r.production_mutation_authorized){
    throw 'V050_DETACHED_RECEIPT_SCHEMA_MISMATCH'
 }
 $names=@($r.approved_names)
 if($names.Count -lt 1 -or $names.Count -gt 4 -or
    @($names|Where-Object{$_ -notin @('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')}).Count -gt 0){
    throw 'V050_DETACHED_APP_LIST_UNQUALIFIED'
 }
 [IO.Directory]::CreateDirectory((Join-Path $stage 'trees'))|Out-Null
 [IO.Directory]::CreateDirectory((Join-Path $stage 'guard'))|Out-Null
 foreach($n in @('xpui')+$names){
   $src=Join-Path (Join-Path $source 'preimage\trees') $n
   $dst=Join-Path (Join-Path $stage 'trees') $n
   $s=Copy-CustomAppUpdateTreeFixtureV010 -Source $src -Destination $dst -ValidationRoot $env:RUNNER_TEMP
   if([string]$s.tree_sha256 -cne [string]$r.tree_sha256.$n){
     throw 'V050_DETACHED_RECONSTRUCTED_TREE_MISMATCH'
   }
 }
 $namesGuard=@{config='config.ini';prefs='prefs';state='legacy-state.json'}
 foreach($key in @('config','prefs','state')){
   $src=Join-Path (Join-Path $source 'preimage\protected') ($key+'.dpapi')
   $blob=[IO.File]::ReadAllBytes($src)
   if((Get-CustomAppV050BytesHash -Data $blob) -cne [string]$r.protected_cipher_sha256.$key){
     throw 'V050_DETACHED_PROTECTED_CIPHERTEXT_MISMATCH'
   }
   $raw=ConvertFrom-CustomAppV050Sealed -Cipher $blob -Purpose ($EscrowId+'|'+$key)
   try{
     if((Get-CustomAppV050BytesHash -Data $raw) -cne [string]$r.protected_sha256.$key){
       throw 'V050_DETACHED_PROTECTED_PLAINTEXT_MISMATCH'
     }
     $out=Join-Path (Join-Path $stage 'guard') $namesGuard[$key]
     Write-CustomAppV050NewBytes -Path $out -Bytes $raw
     if((Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$r.protected_sha256.$key){
       throw 'V050_DETACHED_PROTECTED_WRITE_CHANGED'
     }
   }finally{[Array]::Clear($blob,0,$blob.Length);[Array]::Clear($raw,0,$raw.Length)}
 }
 # The host-only staging and final path are inside the same private vault.
 [IO.Directory]::Move($stage,$target)
 return [pscustomobject]@{
   ok=$true;status='hosted-detached-restore-verified'
   restored_xpui_files=[int](Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $target 'trees\xpui')).file_count
   approved_custom_apps_restored=$names.Count;dpapi_guard_files_restored=3
   original_spotify_unchanged=$true;production_restore_authorized=$false
   live_update_authorized=$false
 }
}
