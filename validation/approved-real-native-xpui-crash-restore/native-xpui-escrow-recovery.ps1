# Hosted-only V034/V035: durable native XPUI preimage before genuine CLI side effect
# and independent post-crash byte-exact XPUI restoration. NO production authority.
function Get-ApprovedNativeXpuiEscrowPathV034 {
 param($Paths,[string]$TransactionId)
 if($TransactionId -cnotmatch '^[a-f0-9]{64}$'){throw 'V034_ESCROW_TRANSACTION_ID_INVALID'}
 return Join-Path ([string]$Paths.journal) ('scoped-xpui-preimage-'+$TransactionId+'.dpapi')
}
function Read-ApprovedNativeXpuiEscrowV034 {
 param($Paths,[string]$TransactionId)
 Assert-ApprovedNativeSagaHostedV032
 $path=Get-ApprovedNativeXpuiEscrowPathV034 -Paths $Paths -TransactionId $TransactionId
 $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
   $file.Length -lt 160 -or $file.Length -gt 32768){throw 'V034_UNTRUSTED_SEALED_PREIMAGE_FILE'}
 $all=[IO.File]::ReadAllBytes($path)
 if($all.Length -ne $file.Length){throw 'V034_SEAL_CHANGED_DURING_READ'}
 $cipher=New-Object byte[] ($all.Length-32)
 [Array]::Copy($all,32,$cipher,0,$cipher.Length)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$hash=$sha.ComputeHash($cipher)}finally{$sha.Dispose()}
 for($i=0;$i -lt 32;$i++){
   if($hash[$i] -ne $all[$i]){throw 'V034_SEAL_CIPHERTEXT_HEADER_TAMPERED'}
 }
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 $plain=$null
 try{
  $entropy=[Text.Encoding]::UTF8.GetBytes('approved-native-xpui-preimage-v034|'+$TransactionId)
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $record=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
 }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
 if([int]$record.schema -ne 1 -or
   [string]$record.managed_by -cne 'approved-hosted-xpui-preimage-v034' -or
   [string]$record.transaction_id -cne $TransactionId -or
   [bool]$record.production_mutation_authorized){
   throw 'V034_SEALED_PREIMAGE_SCHEMA_OR_AUTHORITY_INVALID'
 }
 return $record
}
function Save-ApprovedNativeXpuiPrelaunchV034 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,[string]$ReceiptStore,
       [string]$TransactionId,[string]$VendorPrivateRoot,
       [string]$ActualRoot,[string]$XpuiPath,[string]$TargetPath)
 Assert-ApprovedNativeSagaHostedV032
 $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
 $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
 if([string]$e.journal.entry.phase -cne 'apply-starting' -or [int64]$e.journal.revision -ne 5){
   throw 'V034_NATIVE_PREIMAGE_NOT_BEFORE_CLI_IN_SAME_CAS'
 }
 $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
 if([string]$state.live_state -cne 'candidate' -or [string]$state.old_state -cne 'original'){
   throw 'V034_PRELAUNCH_SOURCE_NOT_MUTATION_SAFE'
 }
 $runner=[string]$p.runner
 $v=Assert-ApprovedCustomAppHostedPathV026 -Path $VendorPrivateRoot -RunnerRoot $runner
 $actual=Assert-ApprovedCustomAppHostedPathV026 -Path $ActualRoot -RunnerRoot $runner
 $xpui=Assert-ApprovedCustomAppHostedPathV026 -Path $XpuiPath -RunnerRoot $runner
 $target=Assert-ApprovedCustomAppHostedPathV026 -Path $TargetPath -RunnerRoot $runner
 if($v -cne $actual -or
   [IO.Path]::GetFileName($v) -cnotmatch '^v032-official-[a-f0-9]{8}$' -or
   $xpui -cne (Join-Path $v 'FakeSpotify\Apps\xpui') -or
   $target -cne (Join-Path $xpui ('spicetify-routes-'+$Name+'.js')) -or
   (Test-CustomAppAtomicPathsOverlapV010 -A $v -B ([string]$p.work)) -or
   (Test-CustomAppAtomicPathsOverlapV010 -A $v -B ([string]$e.stage_path))){
   throw 'V034_NATIVE_PREIMAGE_NOT_EXACT_OWNED_HOSTED_ROOT'
 }
 $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 if([int]$before.file_count -ne 3 -or
   -not[IO.File]::Exists($target) -or
   [IO.File]::ReadAllText($target) -cne 'V026_BEFORE_TARGET'){
   throw 'V034_PRELAUNCH_XPUI_NOT_VERIFIED_ORIGINAL'
 }
 $original=Join-Path ([string]$p.transaction) 'native-xpui-preimage'
 if([IO.Directory]::Exists($original) -or [IO.File]::Exists($original)){
   throw 'V034_PREIMAGE_ALREADY_RESERVED'
 }
 $copied=Copy-CustomAppAtomicTreeV010 -Source $xpui -Destination $original
 $saved=Get-CustomAppUpdateTreeSnapshotV010 -Root $original
 if([string]$saved.tree_sha256 -cne [string]$before.tree_sha256 -or
   [string]$copied.tree_sha256 -cne [string]$before.tree_sha256){
   throw 'V034_ORIGINAL_XPUI_COPY_NOT_BYTE_EXACT'
 }
 $r=[pscustomobject]@{
  schema=1;managed_by='approved-hosted-xpui-preimage-v034'
  transaction_id=$TransactionId;token_id=$TokenId;name=$Name
  journal_start_entry_sha256=[string]$e.journal.entry.entry_sha256
  native_root=$v;xpui_path=$xpui;preimage_path=$original
  original_xpui_tree_sha256=[string]$before.tree_sha256
  original_xpui_file_count=[int]$before.file_count
  stage_tree_sha256=[string]$e.proof.stage_tree_sha256
  production_mutation_authorized=$false
 }
 $raw=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Compress -Depth 5))
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 try{
  $entropy=[Text.Encoding]::UTF8.GetBytes('approved-native-xpui-preimage-v034|'+$TransactionId)
  $cipher=[Security.Cryptography.ProtectedData]::Protect($raw,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 }finally{[Array]::Clear($raw,0,$raw.Length)}
 $hashObj=[Security.Cryptography.SHA256]::Create()
 try{$digest=$hashObj.ComputeHash($cipher)}finally{$hashObj.Dispose()}
 $packed=New-Object byte[] ($cipher.Length+32)
 [Array]::Copy($digest,0,$packed,0,32)
 [Array]::Copy($cipher,0,$packed,32,$cipher.Length)
 $sealPath=Get-ApprovedNativeXpuiEscrowPathV034 -Paths $p -TransactionId $TransactionId
 $stream=[IO.FileStream]::new($sealPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($packed,0,$packed.Length);$stream.Flush($true)}
 finally{$stream.Dispose()}
 $check=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $TransactionId
 if([string]$check.original_xpui_tree_sha256 -cne [string]$r.original_xpui_tree_sha256 -or
   [string]$check.native_root -cne $v -or
   [string]$check.journal_start_entry_sha256 -cne [string]$r.journal_start_entry_sha256){
   throw 'V034_DURABLE_DPAPI_XPUI_SEAL_READBACK_FAILED'
 }
 return [pscustomobject]@{ok=$true;preimage_sha256=[string]$before.tree_sha256;sealed_before_vendor=$true;production_mutation_authorized=$false}
}
function Invoke-ApprovedNativeXpuiEscrowApplyV034 {
 param($Item,$Acquired,$Prepared,[string]$ReceiptStore,[string]$OfficialExecutable,
       [string]$VendorPrivateRoot,
       [ValidateSet('none','after-official-cli-before-pending')][string]$FailurePoint='none')
 Assert-ApprovedNativeSagaHostedV032
 $name=[string]$Item.name;$token=[string]$Prepared.token_id;$tx=[string]$Prepared.transaction_id
 $work=[string]$Prepared.work_root
 $paths=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $work -Name $name -TokenId $token
 $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $paths -Name $name -TokenId $token -ReceiptStore $ReceiptStore -TransactionId $tx
 if([string]$e.journal.entry.phase -cne 'prepared' -or [int64]$e.journal.revision -ne 0){
   throw 'V034_ESCROW_EXECUTOR_REQUIRES_FRESH_PREPARED_CAS'
 }
 $callerRoot=$VendorPrivateRoot
 $callerStore=$ReceiptStore
 $callerWork=$work;$callerName=$name;$callerToken=$token;$callerTx=$tx
 $hook={
  param($root,$xpui,$target)
  $sealed=Save-ApprovedNativeXpuiPrelaunchV034 -WorkRoot $callerWork -Name $callerName -TokenId $callerToken -ReceiptStore $callerStore -TransactionId $callerTx -VendorPrivateRoot $callerRoot -ActualRoot $root -XpuiPath $xpui -TargetPath $target
  if(-not[bool]$sealed.ok -or -not[bool]$sealed.sealed_before_vendor){
   throw 'V034_PRELAUNCH_BACKUP_AUTHORITY_NOT_DURABLE'
  }
 }.GetNewClosure()
 return Invoke-ApprovedNativeJournalApplyV032 -Item $Item -Acquired $Acquired -Prepared $Prepared -ReceiptStore $ReceiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $VendorPrivateRoot -NativePreLaunchGuard $hook -FailurePoint $FailurePoint
}
function Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 {
 param($Before,$After,[string]$Name)
 # Official v2.46.4 refresh -a can create *four precisely scoped files*
 # and two parent directories for the one approved installed app:
 # spicetify-routes-<app>.{js,css,json}, extensions/<app>/extension.js.
 # No other post-vendor file/directory may appear, disappear or drift.
 if($Name -cnotmatch '^[a-z][a-z0-9-]{1,63}$'){
   throw 'V035_UNSAFE_OWNED_APP_NAME_FOR_XPUI'
 }
 $prefix=('spicetify-routes-'+$Name).ToLowerInvariant()
 $extension=('extensions/'+$Name).ToLowerInvariant()
 $owned=@{}
 foreach($f in @($prefix+'.js',$prefix+'.css',$prefix+'.json',$extension+'/extension.js')){
   $owned[$f]=$true
 }
 $createdDirs=@{'extensions'=$true}
 $createdDirs[$extension]=$true
 $expected=@{}
 foreach($entry in @($Before.entries)){
   $rel=([string]$entry.path).ToLowerInvariant()
   if($expected.ContainsKey($rel)){throw 'V035_DUPLICATE_XPUI_PREIMAGE_PATH'}
   if(-not$owned.ContainsKey($rel)){
      $expected[$rel]=([string]$entry.type+'|'+[string]$entry.size+'|'+[string]$entry.sha256)
   }
 }
 $actual=@{}
 foreach($entry in @($After.entries)){
   $rel=([string]$entry.path).ToLowerInvariant()
   if($actual.ContainsKey($rel)){throw 'V035_DUPLICATE_XPUI_CURRENT_PATH'}
   if($owned.ContainsKey($rel)){
      if([string]$entry.type -cne 'file'){
        throw 'V035_OFFICIAL_OWNED_ROUTE_NOT_FILE'
      }
   }else{
      $actual[$rel]=([string]$entry.type+'|'+[string]$entry.size+'|'+[string]$entry.sha256)
   }
 }
 # New parent directory *only* where it was absent in preimage.
 # If it already existed, all foreign children remain independently pinned.
 foreach($dir in @($createdDirs.Keys)){
   if(-not$expected.ContainsKey($dir) -and $actual.ContainsKey($dir)){
     if([string]$actual[$dir] -cne 'dir|0|'){
       throw 'V035_OFFICIAL_EXTRA_PARENT_IS_NOT_DIRECTORY'
     }
     [void]$actual.Remove($dir)
   }
 }
 if($expected.Count -ne $actual.Count){
    throw 'V035_FOREIGN_XPUI_FILE_COUNT_CHANGED'
 }
 foreach($key in @($expected.Keys)){
   if(-not$actual.ContainsKey($key) -or [string]$actual[$key] -cne [string]$expected[$key]){
     throw 'V035_FOREIGN_XPUI_FILE_OR_BYTES_CHANGED'
   }
 }
 return $true
}
function Invoke-ApprovedNativeXpuiEscrowRecoveryV034 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,
       [string]$ReceiptStore,[string]$TransactionId,[string]$VendorPrivateRoot,
       [ValidateSet('none','after-app-before-xpui','after-xpui-quarantine-before-copy',
                    'after-xpui-copy-before-journal')][string]$FailurePoint='none')
 $lease=$null
 $deny={param([string]$why)
  return [pscustomobject]@{ok=$false;reason=('V034_DENIED_'+$why)
   actual_spotify_profile_touched=$false;production_mutation_authorized=$false}}
 try{
  Assert-ApprovedNativeSagaHostedV032
  $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
  $escrow=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $TransactionId
  $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
  $vendor=Assert-ApprovedCustomAppHostedPathV026 -Path $VendorPrivateRoot -RunnerRoot ([string]$p.runner)
  $xpui=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.xpui_path) -RunnerRoot ([string]$p.runner)
  $preimage=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.preimage_path) -RunnerRoot ([string]$p.runner)
  if([string]$escrow.transaction_id -cne $TransactionId -or
    [string]$escrow.token_id -cne $TokenId -or
    [string]$escrow.name -cne $Name -or
    [string]$escrow.native_root -cne $vendor -or
    $xpui -cne (Join-Path $vendor 'FakeSpotify\Apps\xpui') -or
    $preimage -cne (Join-Path ([string]$p.transaction) 'native-xpui-preimage') -or
    [string]$escrow.stage_tree_sha256 -cne [string]$e.proof.stage_tree_sha256 -or
    [string]$escrow.journal_start_entry_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    $vendor -cne (Assert-ApprovedCustomAppHostedPathV026 -Path $vendor -RunnerRoot ([string]$p.runner))){
    throw 'V034_DPAPI_XPUI_OWNER_JOURNAL_OR_LOCATION_DRIFT'
  }
  $startFile=Join-Path (Join-Path ([string]$p.journal) 'history') ('{0:D20}-{1}.json' -f 5,[string]$escrow.journal_start_entry_sha256)
  if(-not[IO.File]::Exists($startFile) -or [int64]$e.journal.revision -lt 5){
    throw 'V034_PRE_VENDOR_JOURNAL_BARRIER_NOT_PRESERVED'
  }
  $original=Get-CustomAppUpdateTreeSnapshotV010 -Root $preimage
  if([string]$original.tree_sha256 -cne [string]$escrow.original_xpui_tree_sha256 -or
    [int]$original.file_count -ne [int]$escrow.original_xpui_file_count){
    throw 'V034_ORIGINAL_XPUI_RECOVERY_IMAGE_TAMPERED'
  }
  $phase=[string]$e.journal.entry.phase
  if($phase -cne 'rollback-complete'){
    if($phase -notin @('apply-starting','apply-returned-success-pending-verification','rollback-required')){
      throw ('V034_ROLLBACK_NOT_AUTHORIZED_FROM_'+$phase)
    }
    $app=Invoke-ApprovedNativeJournalRecoveryV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -DeferRollbackComplete
    if(-not[bool]$app.ok -or [string]$app.phase -cne 'rollback-required' -or
      -not[bool]$app.xpui_recovery_still_required){
      throw ('V035_DEFERRED_APP_RECOVERY_FAILED_'+[string]$app.reason)
    }
  }
  $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
  $j=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
  if([string]$j.journal.entry.phase -notin @('rollback-required','rollback-complete')){
    throw 'V035_EXPECTED_COMPOSITE_ROLLBACK_REQUIRED'
  }
  $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $j
  if([string]$state.live_state -cne 'original'){
    throw 'V034_APP_NOT_RESTORED_BEFORE_XPUI'
  }
  if($FailurePoint -ceq 'after-app-before-xpui'){
    throw 'V035_INJECTED_CRASH_AFTER_APP_BEFORE_XPUI'
  }
  $quarantine=Join-Path ([string]$p.transaction) 'native-xpui-after-crash-retained'
  $hasQ=([IO.Directory]::Exists($quarantine) -or [IO.File]::Exists($quarantine))
  $hasLive=[IO.Directory]::Exists($xpui)
  if(-not$hasLive -and (Test-Path -LiteralPath $xpui)){throw 'V034_XPUI_REPLACED_WITH_FILE'}
  if(-not$hasLive -and -not$hasQ){throw 'V034_XPUI_MISSING_WITHOUT_RECOVERY_CHECKPOINT'}
  $same=$false
  if($hasLive){
   $current=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
   $same=([string]$current.tree_sha256 -ceq [string]$original.tree_sha256)
  }
  # Do not overwrite any concurrent user/Marketplace/foreign XPUI change.
  if(-not$same -and $hasLive){
   [void](Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 -Before $original -After $current -Name $Name)
  }
  if($hasQ){
   $kept=Get-CustomAppUpdateTreeSnapshotV010 -Root $quarantine
   [void](Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 -Before $original -After $kept -Name $Name)
  }
  if([string]$j.journal.entry.phase -ceq 'rollback-complete' -and -not$same){
     throw 'V035_LEGACY_PREMATURE_TERMINAL_JOURNAL_NOT_RESTORED_MANUAL_REVIEW'
  }
  if(-not$same -and $hasLive){
   if($hasQ){throw 'V034_NEW_UNTRUSTED_XPUI_AFTER_QUARANTINE'}
   [IO.Directory]::Move($xpui,$quarantine)
   $hasQ=$true
   $kept=Get-CustomAppUpdateTreeSnapshotV010 -Root $quarantine
   if([string]$kept.tree_sha256 -cne [string]$current.tree_sha256){
      throw 'V035_QUARANTINE_RENAME_NOT_BYTE_EXACT'
   }
   if($FailurePoint -ceq 'after-xpui-quarantine-before-copy'){
      throw 'V035_INJECTED_CRASH_AFTER_XPUI_QUARANTINE'
   }
  }
  if(-not$same){
   $restored=Copy-CustomAppAtomicTreeV010 -Source $preimage -Destination $xpui
   if([string]$restored.tree_sha256 -cne [string]$original.tree_sha256){
     throw 'V034_RESTORED_XPUI_COPY_DIFFERENT'
   }
  }
  $after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
  if([string]$after.tree_sha256 -cne [string]$original.tree_sha256){
   throw 'V034_XPUI_BYTE_EXACT_RECOVERY_NOT_PROVEN'
  }
  if($FailurePoint -ceq 'after-xpui-copy-before-journal'){
     throw 'V035_INJECTED_CRASH_AFTER_XPUI_RESTORE_BEFORE_COMMIT'
  }
  # First prove both restores under the same transaction lease, THEN publish
  # V010 terminal rollback-complete with a durable CAS. No early completion.
  $again=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
  $fresh=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $again
  if([string]$fresh.live_state -cne 'original' -or
     (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -cne [string]$original.tree_sha256){
     throw 'V035_FINAL_COMPOSITE_RECOVERY_CHANGED_BEFORE_CAS'
  }
  if([string]$again.journal.entry.phase -ceq 'rollback-required'){
     $final=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $again.journal -Phase 'rollback-complete'
  }elseif([string]$again.journal.entry.phase -ceq 'rollback-complete'){
     $final=$again.journal
  }else{
     throw 'V035_FINAL_JOURNAL_PHASE_RACED'
  }
  if([string]$final.entry.phase -cne 'rollback-complete'){
     throw 'V035_COMPOSITE_ROLLBACK_TERMINAL_NOT_PERSISTED'
  }
  return [pscustomobject]@{
   ok=$true;phase='rollback-complete';reason='keyless-original-app-and-exact-isolated-xpui-recovered'
   native_xpui_restored_byte_exact=$true
   original_app_restored_byte_exact=$true
   untrusted_post_crash_native_output_retained=$hasQ
   original_backups_deleted=$false;current_user_profile_changed=$false
   actual_spotify_profile_touched=$false;production_mutation_authorized=$false
  }
 }catch{return & $deny ([string]$_.Exception.Message)}
 finally{if($null-ne$lease){$lease.Dispose()}}
}
