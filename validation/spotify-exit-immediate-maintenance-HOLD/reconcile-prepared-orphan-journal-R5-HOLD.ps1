# HOLD: one-purpose idempotent PREPARED-orphan journal reconciliation.
# Does NOT execute Bootstrap, change bin, settings, Spotify, or Spicetify.
# Default read-only. -Commit -ApprovalPhrase EXACT_PREPARED_NO_BIN_SWAP required.
# Only for exact v0.6.20/r9 -> v0.6.28 transaction, exact source tree
# and backup tree, no old/new/restore/failed intermediate roots.
# Permanent original journal escrow is made O_EXCL before any replacement.
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$ApprovalPhrase='',
  [string]$HostedFixtureRoot=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Fail([string]$Category){throw $Category}
function Dir([string]$Path){
  try{$f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return ($f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)}
  catch{return $false}
}
function FileInfo([string]$Path,[int64]$Max=2097152) {
  try{
    $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       [int64]$f.Length -lt 1 -or [int64]$f.Length -gt $Max){return $null}
    return $f
  }catch{return $null}
}
function HashBytes([byte[]]$Bytes) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function HashFile([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Field($o,[string]$name){
  if($null -eq $o){return $null}
  $p=$o.PSObject.Properties[$name]
  if($null -eq $p){return $null}
  return $p.Value
}
function ExactPath([string]$Current,[string]$Expected){
  if([string]::IsNullOrWhiteSpace($Current)){return $false}
  try{return [IO.Path]::GetFullPath($Current).TrimEnd('\','/').Equals(
      [IO.Path]::GetFullPath($Expected).TrimEnd('\','/'),
      [StringComparison]::OrdinalIgnoreCase)}
  catch{return $false}
}
function ReparseFreePath([string]$Root,[string]$Target){
  $r=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
  $p=[IO.Path]::GetFullPath($Target)
  if(-not $p.StartsWith(($r+'\'),[StringComparison]::OrdinalIgnoreCase)){return $false}
  if(-not(Dir $r)){return $false}
  $relative=$p.Substring($r.Length).TrimStart('\','/')
  $cursor=$r
  foreach($component in @($relative -split '[\\/]')){
    if([string]::IsNullOrEmpty($component)){return $false}
    $cursor=Join-Path $cursor $component
    if(Test-Path -LiteralPath $cursor){
      $i=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
      if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    }
  }
  return $true
}
# Strictly compatible with v1.0.6 Get-TreeManifest; refuses reparse points,
# unsafe traversal and unexpected concurrency before it can authorize writing.
function ExactTree([string]$Root) {
  if(-not(Dir $Root)){return ''}
  $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
  $entries=New-Object 'System.Collections.Generic.List[string]'
  $seen=@{};[int64]$total=0
  try{
    foreach($item in @(Get-ChildItem -LiteralPath $Root -Force -Recurse -ErrorAction Stop)){
      if($entries.Count -ge 10000){return ''}
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return ''}
      $full=[IO.Path]::GetFullPath($item.FullName)
      if(-not $full.StartsWith(($base+'\'),[StringComparison]::OrdinalIgnoreCase)){return ''}
      $rel=$full.Substring($base.Length).TrimStart('\','/').Replace('\','/').ToLowerInvariant()
      if($rel.Length -eq 0 -or $seen.ContainsKey($rel)){return ''}
      $seen[$rel]=$true
      if($item.PSIsContainer){$entries.Add('D|'+$rel)}
      else{
        [int64]$size=$item.Length
        $total+=$size
        if($size -lt 0 -or $total -gt 4294967296){return ''}
        $digest=HashFile $full
        $again=FileInfo $full 4294967296
        if($null -eq $again -or [int64]$again.Length -ne $size){return ''}
        $entries.Add(('F|{0}|{1}|{2}' -f $rel,$size,$digest))
      }
    }
    [string[]]$sorted=$entries.ToArray()
    [Array]::Sort($sorted,[StringComparer]::Ordinal)
    return HashBytes ([Text.Encoding]::UTF8.GetBytes(([string]::Join([string][char]10,$sorted)+[char]10)))
  }catch{return ''}
}
function UniqueFile([string]$Path,[byte[]]$Data) {
  $f=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($Data,0,$Data.Length);$f.Flush($true)}
  finally{$f.Dispose()}
}
function SourcePin([string]$Path,[int64]$Size,[string]$Sha) {
  $f=FileInfo $Path 2097152
  return ($null -ne $f -and [int64]$f.Length -eq $Size -and (HashFile $Path) -ceq $Sha)
}
function Probe([string]$Root,[string]$ExpectedId='') {
  if(-not(Dir $Root)){Fail 'ROOT_UNSAFE'}
  if(-not(ReparseFreePath $Root (Join-Path $Root 'bin'))){Fail 'BIN_PATH_UNSAFE'}
  if(-not(ReparseFreePath $Root (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1'))){Fail 'BOOTSTRAP_PATH_UNSAFE'}
  $bin=Join-Path $Root 'bin'
  if(-not(SourcePin (Join-Path $bin 'spotify-control.ps1') 281585 'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')){Fail 'MAIN_NOT_ORIGINAL_V0620'}
  if(-not(SourcePin (Join-Path $bin 'addon-manager.ps1') 225044 '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')){Fail 'ADDON_NOT_ORIGINAL_R9'}
  if(-not(SourcePin (Join-Path $bin 'spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')){Fail 'AGENT_NOT_ORIGINAL'}
  if(-not(SourcePin (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1') 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')){Fail 'BOOTSTRAP_NOT_ORIGINAL'}
  $transaction=Join-Path $Root 'self-update-last-transaction.json'
  if(-not(ReparseFreePath $Root $transaction)){Fail 'TRANSACTION_PATH_UNSAFE'}
  if($null -eq (FileInfo $transaction 1048576)){Fail 'TRANSACTION_UNREADABLE'}
  [byte[]]$original=[IO.File]::ReadAllBytes($transaction)
  $doc=([Text.Encoding]::UTF8.GetString($original)|ConvertFrom-Json -ErrorAction Stop)
  if([string](Field $doc 'status') -cne 'prepared'){Fail 'TRANSACTION_NOT_PREPARED'}
  $id=Field $doc 'id'
  if($id -isnot [string] -or $id -cnotmatch '^\d{8}-\d{6}-[0-9a-f]{8}$'){Fail 'TRANSACTION_ID_INVALID'}
  if($ExpectedId.Length -gt 0 -and $id -cne $ExpectedId){Fail 'TRANSACTION_CHANGED_DURING_APPROVAL'}
  if([string](Field $doc 'before_version') -cne '0.6.20' -or [string](Field $doc 'after_version') -cne '0.6.28'){Fail 'TRANSACTION_VERSION_MISMATCH'}
  if([string](Field $doc 'source_commit') -cne 'bb6d90146f20b73d36fbf8cb813f1b190f403c48'){Fail 'TRANSACTION_OFFICIAL_SOURCE_COMMIT_UNKNOWN'}
  if([string](Field $doc 'payload_set_sha256') -cne '4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'){Fail 'TRANSACTION_PAYLOAD_ID_UNKNOWN'}
  $before=[string](Field $doc 'before_tree_sha256');$after=[string](Field $doc 'after_tree_sha256')
  if($before -cnotmatch '^[a-f0-9]{64}$' -or $after -cnotmatch '^[a-f0-9]{64}$' -or $before -ceq $after){Fail 'TRANSACTION_HASHES_INVALID'}
  $base=Join-Path $Root ('backups\self-update-transactions\'+$id)
  $backup=Join-Path $base 'bin'
  $new=Join-Path $Root ('bin.spotifycontrol-new-'+$id)
  $old=Join-Path $Root ('bin.spotifycontrol-old-'+$id)
  $rest=Join-Path $Root ('bin.spotifycontrol-restore-'+$id)
  $failed=Join-Path $Root ('bin.spotifycontrol-failed-'+$id)
  if(-not (ExactPath ([string](Field $doc 'backup_bin')) $backup) -or
     -not (ExactPath ([string](Field $doc 'same_dir_new')) $new) -or
     -not (ExactPath ([string](Field $doc 'same_dir_old')) $old)){Fail 'TRANSACTION_PATHS_NOT_EXACT'}
  foreach($p in @($backup,$new,$old,$rest,$failed)){
    if(-not(ReparseFreePath $Root $p)){Fail 'REPARSE_OR_PATH_DRIFT'}
  }
  foreach($p in @($new,$old,$rest,$failed)){
    if(Test-Path -LiteralPath $p){Fail 'LEFTOVER_UPDATE_ROOT_EXISTS'}
  }
  if(-not(Dir $base) -or -not(Dir $backup)){Fail 'BACKUP_MISSING'}
  $liveSha=ExactTree $bin
  $backupSha=ExactTree $backup
  if($liveSha -cne $before -or $backupSha -cne $before){Fail 'TREE_MISMATCH_REFUSE_JOURNAL_CHANGE'}
  return [pscustomobject]@{
    id=$id;doc=$doc;original=$original;digest=(HashBytes $original);
    txn=$transaction;base=$base;live=$bin;backup=$backup;
    before=$before
  }
}
$messages=New-Object System.Collections.Generic.List[string]
$messages.Add('DIAGNOSTIC=SPOTIFY_BOOTSTRAP_PREPARED_ORPHAN_TERMINALIZER_HOLD_R5')
$messages.Add('APP_BIN_WRITE=NO;SPOTIFY_EXEC=NO;NETWORK=NO;SETTINGS_WRITE=NO;SCHEDULE_WRITE=NO')
$hosted= -not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
$staging=$null
$stage='INITIAL_PREFLIGHT'
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Fail 'WINDOWS_ONLY'}
  if($hosted){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){Fail 'HOSTED_OVERRIDE_DENIED'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $fx=[IO.Path]::GetFullPath($HostedFixtureRoot)
    if(-not $fx.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){Fail 'HOSTED_OVERRIDE_OUTSIDE_RUNNER'}
    $root=Join-Path $fx 'LocalAppData\SpotifyControl'
  }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){Fail 'LOCAL_ROOT_MISSING'}
    $root=Join-Path $local 'SpotifyControl'
  }
  if($Commit -and ($ApprovalPhrase -cne 'EXACT_PREPARED_NO_BIN_SWAP')){Fail 'EXPLICIT_APPROVAL_MISSING'}
  # Deny Windows processes currently executing the Bootstrap or Spotify Control
  # maintenance script. Resident VBS itself is not a writer; a spawned tick is.
  $processes=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='powershell_ise.exe'" -ErrorAction Stop)
  if($processes.Count -gt 4096){Fail 'PROCESS_INVENTORY_TOO_LARGE'}
  $busy=0;$unknown=0
  foreach($p in $processes){
    if([string]::IsNullOrWhiteSpace([string]$p.CommandLine)){$unknown++;continue}
    $cmd=[string]$p.CommandLine
    if($cmd -match '(?i)spotify-control-self-updater\.ps1|spotify-control\.ps1\s+.*-Action\s+(Maintain|AgentTick)|addon-manager\.ps1\s+.*-Action'){ $busy++ }
  }
  $messages.Add('POSSIBLE_CONCURRENT_WRITERS='+$(if($busy -gt 0){'DETECTED'}elseif($unknown -gt 0){'UNKNOWN'}else{'NONE_OBSERVED'}))
  if($Commit -and ($busy -gt 0 -or $unknown -gt 0)){Fail 'ACTIVE_OR_OPAQUE_POWERSHELL_PROCESS'}
  $stage='FIRST_SOURCE_PROOF'
  $pre=Probe $root
  $messages.Add('SOURCE_AND_FULL_TREES=EXACT_PREPARED_BEFORE')
  $messages.Add('BACKUP_AND_STAGING=NO_CONFLICT')
  $messages.Add('TRANSACTION_ORIGINAL_SHA_PIN=YES')
  if(-not $Commit){
     $messages.Add('RESULT=READY_FOR_EXPLICIT_AUTHORIZED_JOURNAL_ONLY_RECONCILIATION')
  }else{
    # Reread the full source tree immediately before write; never rely on an
    # earlier R4 user report or a pre-flight pass from another process.
    $stage='SECOND_SOURCE_PROOF'
    $second=Probe $root $pre.id
    if($second.digest -cne $pre.digest){Fail 'TRANSACTION_RACE_BETWEEN_PREFLIGHTS'}
    $escrow=Join-Path $pre.base 'original-prepared-transaction-before-reconcile.json'
    if(Test-Path -LiteralPath $escrow){Fail 'EXISTING_ESCROW_NO_OVERWRITE'}
    if(-not(ReparseFreePath $root $escrow)){Fail 'ESCROW_PATH_UNSAFE'}
    # The original journal is preserved *as part of* File.Replace's atomic
    # backup operation. No second independent escrow write is necessary.
    # Windows PowerShell 5.1 / .NET Framework rejects a null backup path in
    # the 4-argument overload, so pass this exact as-yet-absent path.
    $stage='ORIGINAL_ESCROW_RESERVATION'
    if(Test-Path -LiteralPath $escrow){Fail 'EXISTING_ESCROW_NO_OVERWRITE'}
    $stage='PREPARE_TERMINAL_JSON'
    $doc=$pre.doc
    $doc.status='rolled-back'
    $now=[datetime]::UtcNow.ToString('o')
    if($null -eq $doc.PSObject.Properties['rolled_back_at']){
      $doc|Add-Member -MemberType NoteProperty -Name 'rolled_back_at' -Value $now
    }else{$doc.rolled_back_at=$now}
    $doc|Add-Member -MemberType NoteProperty -Name 'prepared_orphan_reconciled_without_bin_swap' -Value $true -Force
    [byte[]]$newBytes=[Text.Encoding]::UTF8.GetBytes(($doc|ConvertTo-Json -Depth 12))
    $staging=Join-Path $root ('self-update-transaction-reconcile-'+$pre.id+'.staging')
    if(-not(ReparseFreePath $root $staging)){Fail 'STAGING_PATH_UNSAFE'}
    $stage='STAGING_JOURNAL_CREATE'
    UniqueFile $staging $newBytes
    $stage='THIRD_SOURCE_PROOF'
    $third=Probe $root $pre.id
    if($third.digest -cne $pre.digest -or (Test-Path -LiteralPath $escrow)){
      Fail 'RACE_OR_ESCROW_CHANGED_BEFORE_REPLACE'
    }
    # File.Replace atomically archives old journal into a *new* escrow file
    # while replacing the transaction. No original bin files are touched.
    # Do NOT invoke the installed Bootstrap, including -Action Check.
    $stage='NTFS_ATOMIC_REPLACE'
    [IO.File]::Replace($staging,$pre.txn,$escrow,$true)
    $stage='POST_COMMIT_VERIFY'
    $staging=$null
    $after=([IO.File]::ReadAllText($pre.txn,[Text.Encoding]::UTF8)|ConvertFrom-Json)
    if([string]$after.status -cne 'rolled-back' -or
       $after.prepared_orphan_reconciled_without_bin_swap -ne $true -or
       (HashFile $escrow) -cne $pre.digest){Fail 'POST_RECONCILIATION_INDETERMINATE_DO_NOT_RETRY'}
    if((ExactTree $pre.live) -cne $pre.before -or (ExactTree $pre.backup) -cne $pre.before){
      Fail 'POST_RECONCILIATION_TREE_CHANGED_DO_NOT_RETRY'
    }
    $messages.Add('ORIGINAL_TRANSACTION=ESCROWED_EXACT_NO_OVERWRITE')
    $messages.Add('TRANSACTION_TERMINAL=ROLLED_BACK_NO_BIN_SWAP')
    $messages.Add('RESULT=JOURNAL_ONLY_RECONCILED_REQUIRES_FRESH_UPDATE_ACCEPTANCE')
  }
}catch{
  if($hosted){
    $messages.Add('HOSTED_TEST_FAILURE_STAGE='+$stage)
    $messages.Add('HOSTED_TEST_FAILURE_EXCEPTION_TYPE='+$_.Exception.GetType().Name)
    if($null -ne $_.Exception.InnerException){
      $messages.Add('HOSTED_TEST_INNER_TYPE='+$_.Exception.InnerException.GetType().Name)
      $messages.Add('HOSTED_TEST_INNER_HRESULT='+[string]$_.Exception.InnerException.HResult)
    }
  }
  $kind=[string]$_.Exception.Message
  $allowed=@('WINDOWS_ONLY','HOSTED_OVERRIDE_DENIED','HOSTED_OVERRIDE_OUTSIDE_RUNNER','LOCAL_ROOT_MISSING',
    'EXPLICIT_APPROVAL_MISSING','PROCESS_INVENTORY_TOO_LARGE','ACTIVE_OR_OPAQUE_POWERSHELL_PROCESS',
    'TRANSACTION_RACE_BETWEEN_PREFLIGHTS','EXISTING_ESCROW_NO_OVERWRITE','ESCROW_PATH_UNSAFE',
    'ESCROW_HASH_MISMATCH','STAGING_PATH_UNSAFE','RACE_OR_ESCROW_CHANGED_BEFORE_REPLACE',
    'POST_RECONCILIATION_INDETERMINATE_DO_NOT_RETRY','POST_RECONCILIATION_TREE_CHANGED_DO_NOT_RETRY')
  if($kind -cnotin $allowed){$kind='UNVERIFIED_FAIL_CLOSED'}
  $messages.Add('HOLD_REASON='+$kind)
  $messages.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  if($null -ne $staging -and [IO.File]::Exists($staging)){
    try{[IO.File]::Delete($staging)}catch{}
  }
}
$messages.Add('BOOTSTRAP_CHECK_EXECUTED=NO;INSTALL_AUTHORIZED=NO;USER_DATA_DELETE=NO')
$messages.Add('PRIVATE_PATHS_TRANSACTION_IDS_ERRORS_EXPORTED=NO')
if(-not $hosted){
  try{Set-Clipboard -Value ($messages -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$messages|ForEach-Object {Write-Output $_}
