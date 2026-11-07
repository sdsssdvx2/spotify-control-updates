# V039. Genuine official native apply => verified NON-DESTRUCTIVE
# terminal state, with all original app/Spotify-guard/XPUI recovery objects
# retained. Hosted synthetic XPUI only. No cleanup, deletion or real Spotify.
# Reuses V010 CAS, V032 full protected-state evidence, V033/V037 independent
# authenticated whole-native proof, V038 anchored pre-vendor intent.
function Invoke-ApprovedNativeRetainedTerminalV039 {
 param(
  [Parameter(Mandatory=$true)][string]$WorkRoot,
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][string]$TokenId,
  [Parameter(Mandatory=$true)][string]$ReceiptStore,
  [Parameter(Mandatory=$true)][string]$TransactionId,
  [Parameter(Mandatory=$true)][string]$VendorPrivateRoot,
  [Parameter(Mandatory=$true)][string]$OfficialExecutable,
  [ValidateSet('none','before-terminal-cas','after-terminal-cas-before-return')]
  [string]$FailurePoint='none'
 )
 $lease=$null
 try{
  Assert-ApprovedNativeSagaHostedV032
  if($TransactionId -cnotmatch '^[a-f0-9]{64}$' -or
    $TokenId -cnotmatch '^[a-f0-9]{64}$' -or
    $Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){
    throw 'V039_UNAPPROVED_TRANSACTION_OR_APP'
  }
  # Both existing readers acquire & release their own lease. Do NOT
  # nest the same lease: verify first, then revalidate ALL byte-critical
  # values inside an exclusive V032 transaction lease before central CAS.
  $proof=Read-ApprovedNativeFullOutputReceiptV037 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
  if(-not[bool]$proof.ok -or -not[bool]$proof.entire_official_output_verified -or
    [string]$proof.phase -notin @('apply-verified','committed-retained') -or
    [bool]$proof.final_commit_authorized -or [bool]$proof.production_mutation_authorized){
    throw 'V039_WHOLE_NATIVE_OUTPUT_DPAPI_READBACK_REJECTED'
  }
  $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
  $nativeProofFile=Get-ApprovedNativeOutputProofPathV037 -Paths $p -TransactionId $TransactionId
  $proofFile=Get-Item -LiteralPath $nativeProofFile -Force -ErrorAction Stop
  if($proofFile.PSIsContainer -or ($proofFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'V039_COMPLETE_NATIVE_RECEIPT_UNTRUSTED'
  }
  $postVendorSealSha=(Get-FileHash -LiteralPath $nativeProofFile -Algorithm SHA256).Hash.ToLowerInvariant()
  $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
  $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
  $phase=[string]$e.journal.entry.phase
  if($phase -notin @('apply-verified','committed-retained')){
    throw 'V039_ONLY_SUCCESSFUL_NATIVE_CAN_TERMINATE'
  }
  $revision=[int64]$e.journal.revision
  if(($phase -ceq 'apply-verified' -and $revision -ne 8) -or
     ($phase -ceq 'committed-retained' -and $revision -ne 9)){
    throw 'V039_JOURNAL_REVISION_NOT_CENTRALLY_ANCHORED'
  }
  $originalVerified=[string]$proof.journal_entry_sha256
  if($originalVerified -cnotmatch '^[a-f0-9]{64}$' -or
     (($phase -ceq 'apply-verified') -and [string]$e.journal.entry.entry_sha256 -cne $originalVerified) -or
     (($phase -ceq 'committed-retained') -and [string]$e.journal.entry.previous_entry_sha256 -cne $originalVerified)){
    throw 'V039_ORIGINAL_APPLY_VERIFIED_HEAD_DISAGREES'
  }
  $intent=Assert-ApprovedNativeSagaSealedIntentV038 -Paths $p -TransactionId $TransactionId
  $escrow=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $TransactionId
  $vendor=Assert-ApprovedCustomAppHostedPathV026 -Path $VendorPrivateRoot -RunnerRoot ([string]$p.runner)
  $xpui=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.xpui_path) -RunnerRoot ([string]$p.runner)
  $preimage=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.preimage_path) -RunnerRoot ([string]$p.runner)
  if([string]$escrow.native_root -cne $vendor -or
     $xpui -cne (Join-Path $vendor 'FakeSpotify\Apps\xpui') -or
     $preimage -cne (Join-Path ([string]$p.transaction) 'native-xpui-preimage') -or
     [string]$escrow.name -cne $Name -or
     [string]$escrow.token_id -cne $TokenId -or
     [string]$escrow.transaction_id -cne $TransactionId){
    throw 'V039_ESCROW_NATIVE_PROFILE_NOT_EXACTLY_BOUND'
  }
  # Full V010 tree snapshots include foreign files as well as all vendor
  # output. No unknown concurrent modification is silently accepted.
  $xpuiState=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
  $preimageState=Get-CustomAppUpdateTreeSnapshotV010 -Root $preimage
  $appState=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
  if([string]$xpuiState.tree_sha256 -cne [string]$proof.after_xpui_sha256 -or
     [string]$preimageState.tree_sha256 -cne [string]$proof.original_xpui_sha256 -or
     [string]$preimageState.tree_sha256 -cne [string]$escrow.original_xpui_tree_sha256 -or
     [string]$appState.live_state -cne 'candidate' -or
     [string]$appState.old_state -cne 'original' -or
     [string]$e.backup.tree_sha256 -cne [string]$e.proof.original_tree_sha256 -or
     [string]$e.persist.fingerprint -cne [string]$e.proof.persistence_fingerprint){
    throw 'V039_APP_XPUI_OR_PERSISTENCE_CHANGED_BEFORE_TERMINAL'
  }
  $sealNow=(Get-FileHash -LiteralPath $nativeProofFile -Algorithm SHA256).Hash.ToLowerInvariant()
  if($sealNow -cne $postVendorSealSha){
    throw 'V039_COMPLETE_NATIVE_RECEIPT_RACED_BEFORE_TERMINAL'
  }
  # Reuse the original V010 cleanup-fingerprint *slot*, but domain-separate
  # the digest as non-deletion RETENTION proof; never claim committed-clean.
  # Inputs are all SHA-bound to the same complete V010 transaction proof.
  $retention=Get-CustomAppProductionCrashJournalSha256V010 (@(
    'v039-retained-terminal-no-cleanup-no-delete',
    $TransactionId,$Name,$TokenId,$originalVerified,
    [string]$e.journal.entry.finalization_fingerprint,
    [string]$e.journal.entry.apply_result_fingerprint,
    [string]$postVendorSealSha,[string]$intent.escrow_sha256,
    [string]$xpuiState.tree_sha256,[string]$preimageState.tree_sha256,
    [string]$e.proof.original_tree_sha256,[string]$e.proof.stage_tree_sha256,
    [string]$e.proof.persistence_fingerprint
  ) -join ([char]10))
  if($retention -cnotmatch '^[a-f0-9]{64}$' -or $retention -ceq ('0'*64)){
    throw 'V039_RETAINED_EVIDENCE_INVALID'
  }
  if($phase -ceq 'committed-retained'){
    if([string]$e.journal.entry.cleanup_result_fingerprint -cne $retention){
      throw 'V039_TERMINAL_RETENTION_PROOF_MISMATCH'
    }
    return [pscustomobject]@{
      ok=$true;phase='committed-retained';reason='retained-terminal-idempotently-revalidated'
      terminal_revision=9;terminal_entry_sha256=[string]$e.journal.entry.entry_sha256
      terminal_replay_no_mutation=$true;all_backups_preserved=$true
      original_xpui_retained=$true;original_spotify_guard_retained=$true
      original_custom_app_retained=$true;user_profile_modified=$false
      cleanup_performed=$false;production_mutation_authorized=$false
    }
  }
  if($FailurePoint -ceq 'before-terminal-cas'){
    throw 'V039_INJECTED_STOP_BEFORE_TERMINAL_CAS'
  }
  $written=Append-ApprovedNativeSagaPhaseV032 -Paths $p -Current $e.journal -Phase 'committed-retained' -CleanupResultFingerprint $retention
  if([string]$written.entry.phase -cne 'committed-retained' -or
     [int64]$written.revision -ne 9 -or
     [string]$written.entry.cleanup_result_fingerprint -cne $retention -or
     [string]$written.entry.apply_result_fingerprint -cne [string]$e.journal.entry.apply_result_fingerprint){
    throw 'V039_CENTRAL_TERMINAL_CAS_MISMATCH'
  }
  if($FailurePoint -ceq 'after-terminal-cas-before-return'){
    throw 'V039_INJECTED_STOP_AFTER_DURABLE_TERMINAL'
  }
  return [pscustomobject]@{
    ok=$true;phase='committed-retained';reason='non-destructive-terminal-verified-all-backups-retained'
    terminal_revision=9;terminal_entry_sha256=[string]$written.entry.entry_sha256
    terminal_replay_no_mutation=$false;all_backups_preserved=$true
    original_xpui_retained=$true;original_spotify_guard_retained=$true
    original_custom_app_retained=$true;user_profile_modified=$false
    cleanup_performed=$false;production_mutation_authorized=$false
  }
 }catch{
  # Never emit raw underlying paths, filenames, usernames or API data.
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^V039_[A-Z0-9_]+$'){
    $reason='V039_AUTHENTICATED_EVIDENCE_NOT_AVAILABLE'
  }
  return [pscustomobject]@{
    ok=$false;phase='unverified';reason=$reason;revalidation_required=$true
    user_profile_modified=$false;cleanup_performed=$false
    production_mutation_authorized=$false
  }
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
