# V040. The same protected CurrentUser DPAPI single-use ledger as the normal
# Addon Manager candidate, retired ONLY after V039 non-destructive terminal.
# Hosted synthetic Spotify fixture only; not wired into production Update.
# Lock order: user ledger FileShare.None -> V032 transaction lease; never invert.
function Commit-ApprovedNativeRetainedUserLedgerV040 {
 param(
  [Parameter(Mandatory=$true)]$Session,
  [Parameter(Mandatory=$true)][string]$WorkRoot,
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][string]$TokenId,
  [Parameter(Mandatory=$true)][string]$ReceiptStore,
  [Parameter(Mandatory=$true)][string]$TransactionId,
  [Parameter(Mandatory=$true)][string]$VendorPrivateRoot,
  [Parameter(Mandatory=$true)][string]$OfficialExecutable,
  [ValidateSet('none','before-ledger-replace','after-ledger-replace-before-return')]
  [string]$FailurePoint='none'
 )
 $lease=$null
 $deny={param([string]$code)
   [pscustomobject]@{
     ok=$false;reason=$code
     claim_retired=$false;consumption_durable=$false
     rollback_backup_deleted=$false;real_spotify_mutated=$false
     production_mutation_authorized=$false
   }
 }
 try {
   Assert-ApprovedNativeSagaHostedV032
   Assert-CustomAppUserTxnSessionV010 -Session $Session
   if([string]$Name -notin @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker') -or
     $TokenId -cnotmatch '^[a-f0-9]{64}$' -or
     $TransactionId -cnotmatch '^[a-f0-9]{64}$' -or
     $TokenId -ceq ('0'*64) -or $TransactionId -ceq ('0'*64)){
      throw 'V040_UNQUALIFIED_APP_OR_TRANSACTION_ID'
   }
   $userPaths=$Session.paths
   if([string]$userPaths.name -cne $Name.ToLowerInvariant() -or
      [string]$userPaths.live -cne [IO.Path]::GetFullPath((Join-Path (Join-Path $WorkRoot 'CustomApps') $Name)).TrimEnd('\','/')){
      throw 'V040_USER_LEDGER_LIVE_OR_OWNER_MISMATCH'
   }
   $stored=Read-CustomAppUserTxnStateV010 -Paths $userPaths
   if(($stored|ConvertTo-Json -Depth 8 -Compress) -cne
      ($Session.state|ConvertTo-Json -Depth 8 -Compress)){
      throw 'V040_LEDGER_SESSION_NOT_CURRENT'
   }
   if($null-eq$stored.active -or
      [string]$stored.active.consumption_id -cne $TokenId -or
      [string]$stored.active.transaction_id -cne $TransactionId -or
      [string]$stored.active.state -cne 'reserved' -or
      @($stored.consumed) -ccontains $TokenId){
      throw 'V040_NO_MATCHING_ACTIVE_SINGLE_USE_RESERVATION'
   }
   if(@($stored.consumed).Count -ge 4096){
      throw 'V040_USER_LEDGER_CAPACITY_EXCEEDED'
   }
   $p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId
   # Before touching the ledger: only a real V039 fully-verified terminal,
   # never caller-supplied success, apply-verified, rollback-complete or a
   # legacy destructive committed-clean phase.
   $j0=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$p.runner) -StoreDirectory ([string]$p.journal)
   if(-not[bool]$j0.ok -or [string]$j0.entry.phase -cne 'committed-retained' -or
      [int64]$j0.revision -ne 9 -or
      [string]$j0.entry.consumption_id -cne $TokenId -or
      [string]$j0.entry.transaction_id -cne $TransactionId){
      throw 'V040_NOT_VERIFIED_V039_RETAINED_TERMINAL'
   }
   $retained=Invoke-ApprovedNativeRetainedTerminalV039 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
   if(-not[bool]$retained.ok -or
      [string]$retained.phase -cne 'committed-retained' -or
      -not[bool]$retained.terminal_replay_no_mutation -or
      -not[bool]$retained.all_backups_preserved -or
      [bool]$retained.production_mutation_authorized -or
      [string]$retained.terminal_entry_sha256 -cne [string]$j0.entry.entry_sha256){
      throw 'V040_RETENTION_REVALIDATION_NOT_AUTHORIZED'
   }
   $proof=Read-ApprovedNativeFullOutputReceiptV037 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
   if(-not[bool]$proof.ok -or
      [string]$proof.phase -cne 'committed-retained' -or
      -not[bool]$proof.entire_official_output_verified -or
      -not[bool]$proof.manifest_scoped_output_verified -or
      [int]$proof.exact_official_owned_files -lt 3 -or
      [string]$proof.manifest_owned_set_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
      [bool]$proof.final_commit_authorized -or
      [bool]$proof.production_mutation_authorized){
      throw 'V040_INDEPENDENT_NATIVE_DPAPI_OUTPUT_NOT_VERIFIED'
   }
   # Native lease remains held across final FS verification and DPAPI
   # ledger File.Replace. Independent native transactions cannot race this.
   $lease=Open-ApprovedNativeSagaLeaseV032 -Paths $p
   $e=Read-ApprovedNativeSagaRecoveryEvidenceV032 -Paths $p -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
   if([string]$e.journal.entry.phase -cne 'committed-retained' -or
      [int64]$e.journal.revision -ne 9 -or
      [string]$e.journal.entry.entry_sha256 -cne [string]$j0.entry.entry_sha256 -or
      [string]$e.journal.entry.consumption_id -cne $TokenId){
      throw 'V040_NATIVE_TERMINAL_CAS_CHANGED_UNDER_LEDGER_LOCK'
   }
   $escrow=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $TransactionId
   $intent=Assert-ApprovedNativeSagaSealedIntentV038 -Paths $p -TransactionId $TransactionId
   $xpui=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.xpui_path) -RunnerRoot ([string]$p.runner)
   $original=Assert-ApprovedCustomAppHostedPathV026 -Path ([string]$escrow.preimage_path) -RunnerRoot ([string]$p.runner)
   $after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
   $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $original
   $runtime=Get-ApprovedNativeSagaLiveStateV032 -Paths $p -Evidence $e
   if([string]$after.tree_sha256 -cne [string]$proof.after_xpui_sha256 -or
      [string]$before.tree_sha256 -cne [string]$proof.original_xpui_sha256 -or
      [string]$before.tree_sha256 -cne [string]$escrow.original_xpui_tree_sha256 -or
      [string]$runtime.live_state -cne 'candidate' -or
      [string]$runtime.old_state -cne 'original' -or
      [string]$e.persist.fingerprint -cne [string]$e.proof.persistence_fingerprint -or
      [string]$e.backup.tree_sha256 -cne [string]$e.proof.original_tree_sha256 -or
      [string]$intent.escrow_sha256 -cnotmatch '^[a-f0-9]{64}$'){
      throw 'V040_PRE_CONSUME_APP_NATIVE_SPOTIFY_STATE_CHANGED'
   }
   # Revalidate canonical ledger state under its lock; direct mutation of
   # Session.state by a caller is never trusted to bypass current DPAPI.
   $current=Read-CustomAppUserTxnStateV010 -Paths $userPaths
   if(($current|ConvertTo-Json -Depth 8 -Compress) -cne
     ($stored|ConvertTo-Json -Depth 8 -Compress) -or
     $null-eq$current.active -or
     [string]$current.active.consumption_id -cne $TokenId -or
     [string]$current.active.transaction_id -cne $TransactionId -or
     @($current.consumed) -ccontains $TokenId){
      throw 'V040_USER_LEDGER_RACED_BEFORE_ATOMIC_REPLACE'
   }
   if([IO.File]::Exists([string]$userPaths.pending)){
      throw 'V040_UNRESOLVED_LEDGER_PENDING_STATE'
   }
   Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$userPaths.backup)
   $next=($current|ConvertTo-Json -Depth 8|ConvertFrom-Json)
   $next.revision=[long]$current.revision+1
   $next.updated_utc=[DateTimeOffset]::UtcNow.ToString('o')
   $next.consumed=@(@($current.consumed)+@($TokenId))
   $next.active=$null
   [void](Test-CustomAppUserTxnStateV010 -State $next -Paths $userPaths)
   if($next.revision -ne ([long]$current.revision+1) -or
     $null-ne$next.active -or @($next.consumed).Count -ne (@($current.consumed).Count+1)){
      throw 'V040_USER_LEDGER_INVALID_CONSUME_TRANSITION'
   }
   $encrypted=Protect-CustomAppUserTxnStateV010 -State $next -Paths $userPaths
   Write-CustomAppUserTxnBytesV010 -Path ([string]$userPaths.pending) -Bytes $encrypted
   if($FailurePoint -ceq 'before-ledger-replace'){
      throw 'V040_TEST_INTERRUPTED_BEFORE_ATOMIC_CONSUMPTION'
   }
   [IO.File]::Replace([string]$userPaths.pending,[string]$userPaths.state,[string]$userPaths.backup)
   if($FailurePoint -ceq 'after-ledger-replace-before-return'){
      throw 'V040_TEST_INTERRUPTED_AFTER_ATOMIC_CONSUMPTION'
   }
   $confirmed=Read-CustomAppUserTxnStateV010 -Paths $userPaths
   if([long]$confirmed.revision -ne [long]$next.revision -or
     $null-ne$confirmed.active -or
     @($confirmed.consumed) -cnotcontains $TokenId){
      throw 'V040_DURABLE_LEDGER_CONSUMPTION_NOT_READABLE'
   }
   $Session.state=$confirmed
   return [pscustomobject]@{
     ok=$true;reason='retained-terminal-and-dpapi-single-use-ledger-atomically-retired'
     transaction_id=$TransactionId;consumption_id=$TokenId
     terminal_entry_sha256=[string]$j0.entry.entry_sha256
     claim_retired=$true;consumption_durable=$true
     consumed_ledger_revision=[long]$confirmed.revision
     backup_objects_retained=$true;rollback_backup_deleted=$false
     native_terminal_unchanged=$true
     real_spotify_mutated=$false;production_mutation_authorized=$false
   }
 }catch{
   # Never expose original user paths, exceptions or private values.
   $why=[string]$_.Exception.Message
   if($why -cnotmatch '^V040_[A-Z0-9_]+$'){$why='V040_NOT_QUALIFIED_FOR_LEDGER_RETIREMENT'}
   return & $deny $why
 }finally{
   if($null-ne$lease){$lease.Dispose()}
 }
}
