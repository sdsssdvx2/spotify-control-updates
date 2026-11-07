# V033: hosted-only, keyless, read-only audit of V032 genuine native success.
# This checks current isolated XPUI bytes against the central CAS digest.
# V032 did not bind the VendorPrivateRoot path durably: NO commit authority.
function Test-ApprovedNativeAppliedReadbackV033 {
 param([string]$WorkRoot,[string]$Name,[string]$TokenId,[string]$ReceiptStore,
       [string]$TransactionId,[string]$VendorPrivateRoot,[string]$OfficialExecutable)
 $lease=$null
 try {
  Assert-ApprovedNativeSagaHostedV032
  if($Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker') -or
    $TokenId -cnotmatch '^[a-f0-9]{64}$' -or $TransactionId -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V033_UNQUALIFIED_ID'
  }
  $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
  $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
  $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
  $j=$e.journal.entry
  $phase=[string]$j.phase
  $revision=[int64]$e.journal.revision
  if(-not(($phase -ceq 'apply-verified' -and $revision -in @(7,8)) -or
           ($phase -ceq 'committed-retained' -and $revision -eq 9))){
    throw 'V039_VERIFIED_OR_RETAINED_PHASE_NOT_DURABLE'
  }
  # The complete central V010 chain is independently validated above.
  # Terminal revision 9 must be a direct child of the original proven
  # apply-verified revision 8; otherwise do not reuse V033 native evidence.
  $verifiedEntry=$j
  if($phase -ceq 'committed-retained'){
    $history=Join-Path ([string]$p.journal) 'history'
    $files=@(Get-ChildItem -LiteralPath $history -File -Force -Filter ('{0:D20}-*.json' -f 8))
    if($files.Count -ne 1){throw 'V039_VERIFIED_REV8_NOT_UNIQUE'}
    $verifiedEntry=(ConvertFrom-CustomAppProductionCrashJournalFileV010 -AllowedRoot ([string]$p.runner) -Path ([string]$files[0].FullName)).entry
    if([string]$verifiedEntry.phase -cne 'apply-verified' -or
       [int64]$verifiedEntry.revision -ne 8 -or
       [string]$verifiedEntry.transaction_id -cne $TransactionId -or
       [string]$j.previous_entry_sha256 -cne [string]$verifiedEntry.entry_sha256 -or
       [string]$verifiedEntry.apply_result_fingerprint -cne [string]$j.apply_result_fingerprint -or
       [string]$verifiedEntry.finalization_fingerprint -cne [string]$j.finalization_fingerprint -or
       [string]$j.cleanup_result_fingerprint -ceq ('0'*64)){
      throw 'V039_RETAINED_HEAD_NOT_DESCENDANT_OF_VERIFIED_NATIVE'
    }
  }
  # Rev8 is a native-intent-anchored V010 transaction. Rev7 is the older
  # app-only synthetic fixture and must NOT pretend it owns native XPUI.
  $intent=Read-ApprovedNativeSagaIntentWitnessV038 -Paths $p -TransactionId $TransactionId
  if([int64]$e.journal.revision -in @(8,9)){
    if(-not[bool]$intent.present){throw 'V038_NATIVE_VERIFIED_WITHOUT_INTENT_WITNESS'}
    [void](Assert-ApprovedNativeSagaSealedIntentV038 -Paths $p -TransactionId $TransactionId)
  }elseif([bool]$intent.present -or
    [IO.File]::Exists((Join-Path ([string]$p.journal) ('scoped-xpui-preimage-'+$TransactionId+'.dpapi')))){
    throw 'V038_LEGACY_VERIFIED_WITH_UNDECLARED_XPUI_ESCROW'
  }
  $state=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
  if([string]$state.live_state -cne 'candidate' -or [string]$state.old_state -cne 'original'){
    throw 'V033_EXACT_LIVE_AND_OLD_NOT_PRESERVED'
  }
  $vp=Assert-ApprovedCustomAppHostedPathV026 -Path $VendorPrivateRoot -RunnerRoot ([string]$p.runner)
  $exe=Assert-ApprovedCustomAppHostedPathV026 -Path $OfficialExecutable -RunnerRoot ([string]$p.runner)
  if(-not[IO.Directory]::Exists($vp) -or -not[IO.File]::Exists($exe) -or
    [IO.Path]::GetFileName($vp) -cnotmatch '^v032-official-[a-f0-9]{8}$' -or
    [IO.Path]::GetFileName($exe) -cne 'spicetify.exe' -or
    (Test-CustomAppAtomicPathsOverlapV010 -A $vp -B ([string]$p.work)) -or
    (Test-CustomAppAtomicPathsOverlapV010 -A $vp -B ([string]$e.stage_path))){
    throw 'V033_ISOLATED_VENDOR_ROOT_UNTRUSTED'
  }
  $pin='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
  if((Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin){
    throw 'V033_OFFICIAL_BINARY_CHANGED'
  }
  $xpui=Join-Path $vp 'FakeSpotify\Apps\xpui'
  $target=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path $xpui ('spicetify-routes-'+$Name+'.js')) -RunnerRoot ([string]$p.runner)
  $other=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path $xpui 'spicetify-routes-foreign.js') -RunnerRoot ([string]$p.runner)
  $sentinel=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path $xpui 'user-settings-dont-change.dat') -RunnerRoot ([string]$p.runner)
  $clone=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path (Join-Path $vp 'CustomApps') $Name) -RunnerRoot ([string]$p.runner)
  foreach($f in @($target,$other,$sentinel)){
    if(-not[IO.File]::Exists($f)){throw 'V033_OFFICIAL_TARGET_OR_SENTINEL_MISSING'}
  }
  if([IO.File]::ReadAllText($other) -cne 'V026_OTHER_APP_DO_NOT_CHANGE' -or
    [IO.File]::ReadAllText($sentinel) -cne 'V026_PROTECTED_USER_STATE'){
    throw 'V033_OTHER_APP_OR_USER_SENTINEL_DRIFT'
  }
  $copy=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $clone
  if(-not[bool]$copy.safe -or -not[bool]$copy.installable -or
    [string]$copy.tree_sha256 -cne [string]$e.proof.stage_runtime_tree_sha256){
    throw 'V033_OFFICIAL_CLONE_NOT_APPROVED_FULL_TREE'
  }
  # Journal source is normalized to lowercase, native receipt is original-case.
  $nativeSource=if($Name -ceq 'ivLyrics'){'ivLis-Studio/ivLyrics'}else{'Pithaya/spicetify-apps-dist'}
  if([string]$e.proof.source -cne $nativeSource.ToLowerInvariant()){
    throw 'V033_NATIVE_SOURCE_AND_SIGNED_JOURNAL_DISAGREE'
  }
  $th=(Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
  $expected=Get-CustomAppProductionCrashJournalSha256V010 (@(
    'v032-real-official-pinned-scoped-output',$TransactionId,$Name,
    $nativeSource,[string]$e.proof.stage_runtime_tree_sha256,
    $pin,$th,[string]$e.proof.persistence_fingerprint
  ) -join ([char]10))
  if([string]$j.apply_result_fingerprint -cne $expected){
    throw 'V033_CURRENT_XPUI_DOES_NOT_MATCH_DURABLE_APPLY_DIGEST'
  }
  $final=Get-CustomAppProductionCrashJournalSha256V010 (@(
    'v032-real-approved-staged-swap',$TransactionId,$TokenId,
    [string]$e.proof.original_tree_sha256,[string]$e.proof.stage_tree_sha256,
    [string]$e.proof.persistence_fingerprint,
    [string]$e.proof.source_provenance_sha256
  ) -join ([char]10))
  if([string]$j.finalization_fingerprint -cne $final){
    throw 'V033_FINALIZATION_IDENTITY_DRIFT'
  }
  return [pscustomobject]@{
    ok=$true;reason='V033_VENDOR_XPUI_AND_JOURNAL_READBACK_MATCH'
    phase=$phase;revision=[int64]$e.journal.revision
    entry_sha256=[string]$verifiedEntry.entry_sha256
    current_entry_sha256=[string]$j.entry_sha256
    independent_without_issuer_key=$true;read_only=$true
    vendor_root_durably_bound=$false;final_commit_authorized=$false
    real_spotify_xpui_covered=$false;production_mutation_authorized=$false
  }
 }catch{
  return [pscustomobject]@{
    ok=$false;reason=('V033_DENIED_'+[string]$_.Exception.Message)
    read_only=$true;vendor_root_durably_bound=$false
    final_commit_authorized=$false;production_mutation_authorized=$false
  }
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
