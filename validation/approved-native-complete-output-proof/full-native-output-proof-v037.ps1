# V037: DPAPI-sealed complete official CLI owned-output proof, hosted only.
# Uses the original V010 central CAS, V033 independent JS proof,
# V034 pre-native escrow and V035 strict foreign file exclusion.
# This proves a *synthetic* XPUI precommit state, not installed Spotify.
function Get-ApprovedNativeOutputProofPathV037 {
 param($Paths,[string]$TransactionId)
 if($TransactionId -cnotmatch '^[a-f0-9]{64}$'){throw 'V037_INVALID_TRANSACTION_ID'}
 return Join-Path ([string]$Paths.journal) ('scoped-native-entire-output-'+$TransactionId+'.dpapi')
}
function Get-ApprovedNativeFullOutputEvidenceV037 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,
 [string]$ReceiptStore,[string]$TransactionId,[string]$VendorPrivateRoot,[string]$OfficialExecutable)
 Assert-ApprovedNativeSagaHostedV032
 if($Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){
   throw 'V037_UNAPPROVED_CUSTOMAPP_NAME'
 }
 # V033 takes and releases the same V032 transaction lease by itself.
 $base=Test-ApprovedNativeAppliedReadbackV033 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
 if(-not[bool]$base.ok -or [bool]$base.final_commit_authorized){
   throw 'V037_V033_INDEPENDENT_READBACK_REFUSED'
 }
 $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
 $lease=$null
 try{
   $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
   $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
   $j=$e.journal.entry
   $isFresh=([string]$j.phase -ceq 'apply-verified' -and [int64]$e.journal.revision -eq 8 -and
      [string]$j.entry_sha256 -ceq [string]$base.entry_sha256)
   $isRetained=([string]$j.phase -ceq 'committed-retained' -and [int64]$e.journal.revision -eq 9 -and
      [string]$j.previous_entry_sha256 -ceq [string]$base.entry_sha256)
   if(-not($isFresh -or $isRetained)){
      throw 'V039_CENTRAL_VERIFIED_OR_RETAINED_HEAD_DRIFT'
   }
   [void](Assert-ApprovedNativeSagaSealedIntentV038 -Paths $p -TransactionId $TransactionId)
   $escrow=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $TransactionId
   $vendor=Assert-ApprovedCustomAppHostedPathV026 -Path $VendorPrivateRoot -RunnerRoot ([string]$p.runner)
   $xpui=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.xpui_path) -RunnerRoot ([string]$p.runner)
   $pre=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.preimage_path) -RunnerRoot ([string]$p.runner)
   $official=Assert-ApprovedCustomAppHostedPathV026 -Path $OfficialExecutable -RunnerRoot ([string]$p.runner)
   if([string]$escrow.token_id -cne $TokenId -or
      [string]$escrow.name -cne $Name -or
      [string]$escrow.transaction_id -cne $TransactionId -or
      [string]$escrow.native_root -cne $vendor -or
      [string]$escrow.stage_tree_sha256 -cne [string]$e.proof.stage_tree_sha256 -or
      $xpui -cne (Join-Path $vendor 'FakeSpotify\Apps\xpui') -or
      $pre -cne (Join-Path ([string]$p.transaction) 'native-xpui-preimage') -or
      [IO.Path]::GetFileName($vendor) -cnotmatch '^v032-official-[a-f0-9]{8}$' -or
      (Get-FileHash -LiteralPath $official -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
      throw 'V037_XPUI_ESCROW_OFFICIAL_OWNER_OR_SOURCE_DRIFT'
   }
   $hist=Join-Path (Join-Path ([string]$p.journal) 'history') (
     ('{0:D20}-{1}.json' -f 5,[string]$escrow.journal_start_entry_sha256))
   if(-not[IO.File]::Exists($hist)){
      throw 'V037_ORIGINAL_V010_APPLY_STARTING_BARRIER_MISSING'
   }
   $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $pre
   if([string]$before.tree_sha256 -cne [string]$escrow.original_xpui_tree_sha256 -or
      [int]$before.file_count -ne [int]$escrow.original_xpui_file_count){
      throw 'V037_ORIGINAL_XPUI_ESCROW_IMAGE_TAMPERED'
   }
   $after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
   [void](Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 -Before $before -After $after -Name $Name)
   $expected=@(
     ('spicetify-routes-'+$Name+'.js'),
     ('spicetify-routes-'+$Name+'.css'),
     ('spicetify-routes-'+$Name+'.json'),
     ('extensions/'+$Name+'/extension.js')
   )
   $files=@()
   foreach($rel in $expected){
     $found=@($after.entries|Where-Object{
       [string]$_.path -ceq $rel -and [string]$_.type -ceq 'file'})
     if($found.Count -ne 1 -or
        [string]$found[0].sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [int64]$found[0].size -le 0){
       throw 'V037_EXPECTED_OFFICIAL_APP_OWNED_OUTPUT_MISSING'
     }
     $files+=([pscustomobject]@{relative=$rel;sha256=[string]$found[0].sha256;bytes=[int64]$found[0].size})
   }
   $live=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
   if([string]$live.live_state -cne 'candidate' -or [string]$live.old_state -cne 'original'){
     throw 'V037_V010_ORIGINAL_ROLLBACK_APP_NOT_RETAINED'
   }
   return [pscustomobject]@{
     transaction_id=$TransactionId;token_id=$TokenId;name=$Name
     apply_verified_entry_sha256=[string]$base.entry_sha256
     phase=[string]$j.phase
     apply_result_fingerprint=[string]$j.apply_result_fingerprint
     native_apply_start_entry_sha256=[string]$escrow.journal_start_entry_sha256
     native_root=$vendor;xpui_path=$xpui
     original_xpui_sha256=[string]$before.tree_sha256
     after_xpui_sha256=[string]$after.tree_sha256
     after_file_count=[int]$after.file_count;after_total_bytes=[int64]$after.total_bytes
     official_binary_sha256='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
     approved_files=$files
     old_app_retained=$true;spotify_guard_retained=$true
     production_mutation_authorized=$false
   }
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
function Read-ApprovedNativeFullOutputReceiptV037 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,[string]$ReceiptStore,
 [string]$TransactionId,[string]$VendorPrivateRoot,[string]$OfficialExecutable)
 $deny={param([string]$reason)
   [pscustomobject]@{ok=$false;reason=$reason;entire_official_output_verified=$false
     final_commit_authorized=$false;production_mutation_authorized=$false}
 }
 try{
   Assert-ApprovedNativeSagaHostedV032
   $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
   $file=Get-ApprovedNativeOutputProofPathV037 -Paths $p -TransactionId $TransactionId
   $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      $item.Length -lt 160 -or $item.Length -gt 32768){
      throw 'V037_SEAL_INVALID_SIZE_OR_REPARSE'
   }
   $blob=[IO.File]::ReadAllBytes($file)
   if($blob.Length -ne $item.Length){throw 'V037_SEAL_READ_RACE'}
   $cipher=New-Object byte[] ($blob.Length-32)
   [Array]::Copy($blob,32,$cipher,0,$cipher.Length)
   $sha=[Security.Cryptography.SHA256]::Create()
   try{$digest=$sha.ComputeHash($cipher)}finally{$sha.Dispose()}
   for($n=0;$n -lt 32;$n++){
     if($digest[$n] -ne $blob[$n]){throw 'V037_SEAL_HASH_CHANGED'}
   }
   Add-Type -AssemblyName System.Security -ErrorAction Stop
   $plain=$null
   try{
     $ent=[Text.Encoding]::UTF8.GetBytes('approved-entire-native-output-v037|'+$TransactionId)
     $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$ent,[Security.Cryptography.DataProtectionScope]::CurrentUser)
     $record=[Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
   }finally{if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}}
   if([int]$record.schema -ne 1 -or
     [string]$record.managed_by -cne 'approved-entire-native-output-v037' -or
     [string]$record.transaction_id -cne $TransactionId -or
     [string]$record.name -cne $Name -or
     [string]$record.token_id -cne $TokenId -or
     [bool]$record.production_mutation_authorized){
     throw 'V037_RECEIPT_SCHEMA_OR_AUTHORITY_CHANGED'
   }
   $live=Get-ApprovedNativeFullOutputEvidenceV037 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
   foreach($field in @('apply_verified_entry_sha256','apply_result_fingerprint',
     'native_apply_start_entry_sha256','native_root','xpui_path',
     'original_xpui_sha256','after_xpui_sha256','after_file_count','after_total_bytes',
     'official_binary_sha256')){
       if([string]$record.$field -cne [string]$live.$field){
         throw ('V037_DURABLE_POST_NATIVE_EVIDENCE_DRIFT_'+$field)
       }
   }
   if(@($record.approved_files).Count -ne 4 -or @($live.approved_files).Count -ne 4){
      throw 'V037_SEALED_OWNED_FILE_SET_WRONG'
   }
   for($i=0;$i -lt 4;$i++){
     foreach($key in @('relative','sha256','bytes')){
       if([string]$record.approved_files[$i].$key -cne [string]$live.approved_files[$i].$key){
         throw 'V037_COMPLETE_OFFICIAL_FILE_BYTE_OR_IDENTITY_DRIFT'
       }
     }
   }
   return [pscustomobject]@{
     ok=$true;reason='v010-v033-v034-v035-all-four-official-files-durable-keyless-readback'
     phase=[string]$live.phase;journal_entry_sha256=[string]$live.apply_verified_entry_sha256
     after_xpui_sha256=[string]$live.after_xpui_sha256
     original_xpui_sha256=[string]$live.original_xpui_sha256
     exact_official_owned_files=4;entire_official_output_verified=$true
     original_xpui_recovery_preimage_retained=$true
     original_custom_app_recovery_retained=$true
     foreign_xpui_untouched=$true
     independent_without_issuer_hmac=$true
     no_cleanup_performed=$true;final_commit_authorized=$false
     real_spotify_profile_touched=$false;production_mutation_authorized=$false
   }
 }catch{
   $s=[string]$_.Exception.Message
   $reason=if($s -cmatch '^(V037_[A-Z0-9_]+)'){$matches[1]}else{'V037_NOT_VERIFIED'}
   return & $deny $reason
 }
}
function Save-ApprovedNativeFullOutputReceiptV037 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,[string]$ReceiptStore,
 [string]$TransactionId,[string]$VendorPrivateRoot,[string]$OfficialExecutable)
 Assert-ApprovedNativeSagaHostedV032
 $data=Get-ApprovedNativeFullOutputEvidenceV037 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
 $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
 $entry=[pscustomobject]@{
  schema=1;managed_by='approved-entire-native-output-v037'
  transaction_id=$TransactionId;token_id=$TokenId;name=$Name
  apply_verified_entry_sha256=$data.apply_verified_entry_sha256
  apply_result_fingerprint=$data.apply_result_fingerprint
  native_apply_start_entry_sha256=$data.native_apply_start_entry_sha256
  native_root=$data.native_root;xpui_path=$data.xpui_path
  original_xpui_sha256=$data.original_xpui_sha256
  after_xpui_sha256=$data.after_xpui_sha256
  after_file_count=$data.after_file_count;after_total_bytes=$data.after_total_bytes
  official_binary_sha256=$data.official_binary_sha256
  approved_files=$data.approved_files;production_mutation_authorized=$false
 }
 $raw=[Text.Encoding]::UTF8.GetBytes(($entry|ConvertTo-Json -Compress -Depth 8))
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 try{
   $entropy=[Text.Encoding]::UTF8.GetBytes('approved-entire-native-output-v037|'+$TransactionId)
   $cipher=[Security.Cryptography.ProtectedData]::Protect($raw,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 }finally{[Array]::Clear($raw,0,$raw.Length)}
 $hash=[Security.Cryptography.SHA256]::Create()
 try{$digest=$hash.ComputeHash($cipher)}finally{$hash.Dispose()}
 $whole=New-Object byte[] ($cipher.Length+32)
 [Array]::Copy($digest,0,$whole,0,32)
 [Array]::Copy($cipher,0,$whole,32,$cipher.Length)
 $file=Get-ApprovedNativeOutputProofPathV037 -Paths $p -TransactionId $TransactionId
 $stream=[IO.FileStream]::new($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($whole,0,$whole.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 $again=Read-ApprovedNativeFullOutputReceiptV037 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
 if(-not[bool]$again.ok -or -not[bool]$again.entire_official_output_verified){
    throw 'V037_SEALED_COMPLETE_NATIVE_OUTPUT_NOT_DURABLE'
 }
 return $again
}
