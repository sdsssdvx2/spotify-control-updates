# HOLD R13: exact PREPARED orphan reconciliation, explicit rollback resume,
# and read-only already-committed stable v0.6.28 recognition.
# Does NOT execute Bootstrap, change bin, settings, Spotify, or Spicetify.
# Default read-only. -Commit -ApprovalPhrase EXACT_PREPARED_NO_BIN_SWAP required.
# Only for exact v0.6.20/r9 -> v0.6.28 transaction, exact source tree
# and backup tree, no old/new/restore/failed intermediate roots.
# Permanent original journal escrow is made O_EXCL before any replacement.
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$ApprovalPhrase='',
  [switch]$ContinueOfficialStableUpdate,
  [string]$OfficialUpdateApprovalPhrase='',
  [string]$HostedFixtureRoot=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Fail([string]$Category){throw $Category}
function IsPlainDirectory([string]$Path){
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
  if(-not(IsPlainDirectory $r)){return $false}
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
  if(-not(IsPlainDirectory $Root)){return ''}
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
  if(-not(IsPlainDirectory $Root)){Fail 'ROOT_UNSAFE'}
  if(-not(ReparseFreePath $Root (Join-Path $Root 'bin'))){Fail 'BIN_PATH_UNSAFE'}
  if(-not(ReparseFreePath $Root (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1'))){Fail 'BOOTSTRAP_PATH_UNSAFE'}
  $bin=Join-Path $Root 'bin'
  if(SourcePin (Join-Path $bin 'spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'){
    return (ProbeCommittedStable $Root)
  }
  if(-not(SourcePin (Join-Path $bin 'spotify-control.ps1') 281585 'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')){Fail 'MAIN_NOT_ORIGINAL_V0620'}
  if(-not(SourcePin (Join-Path $bin 'addon-manager.ps1') 225044 '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')){Fail 'ADDON_NOT_ORIGINAL_R9'}
  if(-not(SourcePin (Join-Path $bin 'spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')){Fail 'AGENT_NOT_ORIGINAL'}
  if(-not(SourcePin (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1') 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')){Fail 'BOOTSTRAP_NOT_ORIGINAL'}
  $transaction=Join-Path $Root 'self-update-last-transaction.json'
  if(-not(ReparseFreePath $Root $transaction)){Fail 'TRANSACTION_PATH_UNSAFE'}
  if($null -eq (FileInfo $transaction 1048576)){Fail 'TRANSACTION_UNREADABLE'}
  [byte[]]$original=[IO.File]::ReadAllBytes($transaction)
  $doc=([Text.Encoding]::UTF8.GetString($original)|ConvertFrom-Json -ErrorAction Stop)
  # R11 replay-admission recognizes our OWN previously reconciled journal
  # only when the exact original PREPARED bytes are still in immutable escrow.
  # This lets a user explicitly resume a failed *pre-update* Check, without
  # re-terminalizing or overwriting an already preserved original.
  $status=[string](Field $doc 'status')
  $reconciled=($status -ceq 'rolled-back' -and
      (Field $doc 'prepared_orphan_reconciled_without_bin_swap') -eq $true)
  $officialRollback=($status -ceq 'rolled-back' -and -not $reconciled)
  if($status -cne 'prepared' -and -not $reconciled -and -not $officialRollback){
    Fail 'TRANSACTION_NOT_PREPARED_OR_OWN_RECONCILED'
  }
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
  if(-not(IsPlainDirectory $base) -or -not(IsPlainDirectory $backup)){Fail 'BACKUP_MISSING'}
  $liveSha=ExactTree $bin
  $backupSha=ExactTree $backup
  if($liveSha -cne $before -or $backupSha -cne $before){Fail 'TREE_MISMATCH_REFUSE_JOURNAL_CHANGE'}
  if($reconciled){
    $escrow=Join-Path $base 'original-prepared-transaction-before-reconcile.json'
    if(-not(ReparseFreePath $Root $escrow)){Fail 'PREVIOUS_ESCROW_PATH_UNSAFE'}
    if($null -eq (FileInfo $escrow 1048576)){Fail 'PREVIOUS_ESCROW_NOT_FOUND'}
    [byte[]]$prevBytes=[IO.File]::ReadAllBytes($escrow)
    try{$prev=([Text.Encoding]::UTF8.GetString($prevBytes)|ConvertFrom-Json -ErrorAction Stop)}
    catch{Fail 'PREVIOUS_ESCROW_UNREADABLE'}
    if([string](Field $prev 'status') -cne 'prepared' -or
       [string](Field $prev 'id') -cne $id -or
       [string](Field $prev 'before_tree_sha256') -cne $before -or
       [string](Field $prev 'after_tree_sha256') -cne $after -or
       [string](Field $prev 'source_commit') -cne [string](Field $doc 'source_commit') -or
       [string](Field $prev 'payload_set_sha256') -cne [string](Field $doc 'payload_set_sha256') -or
       (Field $prev 'prepared_orphan_reconciled_without_bin_swap') -eq $true){
      Fail 'PREVIOUS_ESCROW_PROVENANCE_INVALID'
    }
    # Rebuild the EXACT JSON bytes the current tool would have published
    # from the archived original, including its recorded timestamp, rather
    # than accepting a manually edited rolled-back marker as provenance.
    $stamp=Field $doc 'rolled_back_at'
    if($stamp -isnot [string] -or $stamp -cnotmatch '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'){
      Fail 'RECONCILIATION_TIMESTAMP_INVALID'
    }
    $prev.status='rolled-back'
    if($null -eq $prev.PSObject.Properties['rolled_back_at']){
      $prev|Add-Member -MemberType NoteProperty -Name 'rolled_back_at' -Value $stamp
    }else{$prev.rolled_back_at=$stamp}
    $prev|Add-Member -MemberType NoteProperty -Name 'prepared_orphan_reconciled_without_bin_swap' -Value $true -Force
    [byte[]]$expected=[Text.Encoding]::UTF8.GetBytes(($prev|ConvertTo-Json -Depth 12))
    if((HashBytes $expected) -cne (HashBytes $original)){Fail 'RECONCILED_JOURNAL_NOT_OWN_EXACT_BYTES'}
  }
  if($officialRollback){
    $prior=FindVerifiedPriorPreparedEscrow -Root $Root -CurrentId $id -Before $before -After $after -Commit ([string](Field $doc 'source_commit')) -Payload ([string](Field $doc 'payload_set_sha256'))
    if($null -eq $prior){Fail 'OFFICIAL_ROLLBACK_WITHOUT_ORIGINAL_ESCROW'}
  }
  return [pscustomobject]@{
    id=$id;doc=$doc;original=$original;digest=(HashBytes $original);
    txn=$transaction;base=$base;live=$bin;backup=$backup;
    before=$before;reconciled=$reconciled;officialRollback=$officialRollback;stableCommitted=$false
  }
}
function FindVerifiedPriorPreparedEscrow([string]$Root,[string]$CurrentId,
    [string]$Before,[string]$After,[string]$Commit,[string]$Payload,
    [bool]$AllowCommittedAfterMismatch=$false) {
  # A later official Bootstrap rollback can replace our terminal journal ID.
  # Require exactly one authentic earlier PREPARED escrow and two old trees.
  $parent=Join-Path $Root 'backups\self-update-transactions'
  if(-not(IsPlainDirectory $parent) -or -not(ReparseFreePath $Root $parent)){
    Fail 'PRIOR_BACKUP_ROOT_UNSAFE'
  }
  $dirs=@(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop)
  if($dirs.Count -gt 4096){Fail 'PRIOR_BACKUP_SEARCH_LIMIT'}
  $found=0;$accepted=$null
  foreach($d in $dirs){
    if($d.Name -cnotmatch '^\d{8}-\d{6}-[0-9a-f]{8}$' -or
       $d.Name -ceq $CurrentId){continue}
    $candidate=Join-Path $d.FullName 'original-prepared-transaction-before-reconcile.json'
    if(-not(Test-Path -LiteralPath $candidate)){continue}
    if(-not(ReparseFreePath $Root $candidate) -or
       $null -eq (FileInfo $candidate 1048576)){
      Fail 'PREVIOUS_ORIGINAL_ESCROW_UNSAFE'
    }
    [byte[]]$bytes=[IO.File]::ReadAllBytes($candidate)
    try{$archived=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -ErrorAction Stop}
    catch{Fail 'PREVIOUS_ORIGINAL_ESCROW_UNREADABLE'}
    if([string](Field $archived 'id') -cne $d.Name -or
       [string](Field $archived 'status') -cne 'prepared' -or
       [string](Field $archived 'before_version') -cne '0.6.20' -or
       [string](Field $archived 'after_version') -cne '0.6.28' -or
       [string](Field $archived 'before_tree_sha256') -cne $Before -or
       (-not $AllowCommittedAfterMismatch -and
         [string](Field $archived 'after_tree_sha256') -cne $After) -or
       [string](Field $archived 'source_commit') -cne $Commit -or
       [string](Field $archived 'payload_set_sha256') -cne $Payload -or
       (Field $archived 'prepared_orphan_reconciled_without_bin_swap') -eq $true){
      Fail 'PREVIOUS_ORIGINAL_ESCROW_SOURCE_MISMATCH'
    }
    $oldBin=Join-Path $d.FullName 'bin'
    $new=Join-Path $Root ('bin.spotifycontrol-new-'+$d.Name)
    $old=Join-Path $Root ('bin.spotifycontrol-old-'+$d.Name)
    if(-not(ExactPath ([string](Field $archived 'backup_bin')) $oldBin) -or
       -not(ExactPath ([string](Field $archived 'same_dir_new')) $new) -or
       -not(ExactPath ([string](Field $archived 'same_dir_old')) $old) -or
       (ExactTree $oldBin) -cne $Before -or
       (Test-Path -LiteralPath $new) -or
       (Test-Path -LiteralPath $old)){
      Fail 'PREVIOUS_ORIGINAL_ESCROW_TREE_OR_PATH_MISMATCH'
    }
    $found++
    $accepted=[pscustomobject]@{path=$candidate;id=$d.Name;digest=(HashBytes $bytes)}
    if($found -gt 1){Fail 'PREVIOUS_ORIGINAL_ESCROW_AMBIGUOUS'}
  }
  if($found -ne 1){Fail 'PREVIOUS_ORIGINAL_ESCROW_MISSING_OR_MULTIPLE'}
  return $accepted
}
function ProbeCommittedStable([string]$Root) {
  # A late POST-Check network/error must not turn a genuinely committed
  # verified v0.6.28/r17 into an invitation to update it a second time.
  # This path is READ-ONLY even if both user approvals were supplied.
  $bin=Join-Path $Root 'bin'
  if(-not(SourcePin (Join-Path $bin 'spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0') -or
     -not(SourcePin (Join-Path $bin 'addon-manager.ps1') 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
     -not(SourcePin (Join-Path $bin 'spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278') -or
     -not(SourcePin (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1') 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')){
    Fail 'COMMITTED_SOURCE_SET_NOT_EXACT_STABLE'
  }
  $txn=Join-Path $Root 'self-update-last-transaction.json'
  if(-not(ReparseFreePath $Root $txn) -or $null -eq (FileInfo $txn 1048576)){
    Fail 'COMMITTED_JOURNAL_UNREADABLE_OR_UNSAFE'
  }
  $json=([IO.File]::ReadAllText($txn,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop)
  if([string](Field $json 'status') -cne 'committed' -or
     [string](Field $json 'before_version') -cne '0.6.20' -or
     [string](Field $json 'after_version') -cne '0.6.28' -or
     [string](Field $json 'source_commit') -cne 'bb6d90146f20b73d36fbf8cb813f1b190f403c48' -or
     [string](Field $json 'payload_set_sha256') -cne '4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'){
    Fail 'COMMITTED_JOURNAL_NOT_EXACT_OFFICIAL_STABLE'
  }
  $id=Field $json 'id'
  if($id -isnot [string] -or $id -cnotmatch '^\d{8}-\d{6}-[0-9a-f]{8}$'){
    Fail 'COMMITTED_JOURNAL_ID_INVALID'
  }
  $before=[string](Field $json 'before_tree_sha256')
  $after=[string](Field $json 'after_tree_sha256')
  if($before -cnotmatch '^[a-f0-9]{64}$' -or $after -cnotmatch '^[a-f0-9]{64}$' -or $before -ceq $after){
    Fail 'COMMITTED_JOURNAL_HASH_PINS_INVALID'
  }
  $backup=Join-Path $Root ('backups\self-update-transactions\'+$id+'\bin')
  $new=Join-Path $Root ('bin.spotifycontrol-new-'+$id)
  $old=Join-Path $Root ('bin.spotifycontrol-old-'+$id)
  $restore=Join-Path $Root ('bin.spotifycontrol-restore-'+$id)
  $failed=Join-Path $Root ('bin.spotifycontrol-failed-'+$id)
  if(-not(ExactPath ([string](Field $json 'backup_bin')) $backup) -or
     -not(ExactPath ([string](Field $json 'same_dir_new')) $new) -or
     -not(ExactPath ([string](Field $json 'same_dir_old')) $old)){
    Fail 'COMMITTED_JOURNAL_PATH_BINDINGS_INVALID'
  }
  foreach($path in @($backup,$new,$old,$restore,$failed)){
    if(-not(ReparseFreePath $Root $path)){Fail 'COMMITTED_JOURNAL_REPARSE_OR_PATH_UNSAFE'}
  }
  foreach($path in @($new,$old,$restore,$failed)){
    if(Test-Path -LiteralPath $path){Fail 'COMMITTED_TRANSACTION_STAGING_STILL_PRESENT'}
  }
  if((ExactTree $backup) -cne $before -or (ExactTree $bin) -cne $after){
    Fail 'COMMITTED_BIN_OR_BACKUP_TREE_NOT_EXACT'
  }
  # Synthetic R7/R8 original PREPARED escrow can have a placeholder
  # after-tree pin, but the ACTUAL committed transaction authenticates its
  # complete after-tree independently. This mismatch allowance is strictly
  # for read-only COMPLETED classification, never an authorization to retry.
  $prior=FindVerifiedPriorPreparedEscrow -Root $Root -CurrentId $id -Before $before -After $after -Commit ([string](Field $json 'source_commit')) -Payload ([string](Field $json 'payload_set_sha256')) -AllowCommittedAfterMismatch $true
  if($null -eq $prior){Fail 'COMMITTED_STABLE_MISSING_PREPARED_ESCROW'}
  return [pscustomobject]@{stableCommitted=$true;status='committed'}
}
# R14: When CIM suppresses another same-user PowerShell command line, try
# an additional bounded read-only OS query. This is NOT a whitelist: if
# native observation, ownership, or process identity cannot be proved,
# the original opaque-process admission denial remains unchanged.
function RecoverOpaquePowerShellCommandLine($Observed) {
  try {
    $processId=[int]$Observed.ProcessId
    if($processId -le 0 -or $processId -eq $PID -or
       $null -eq $Observed.CreationDate){return ''}
    $owner=Invoke-CimMethod -InputObject $Observed -MethodName GetOwnerSid -ErrorAction Stop
    $ownSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([int]$owner.ReturnValue -ne 0 -or
       [string]$owner.Sid -cne $ownSid){return ''}
    if(-not ('SpotifyR14NativeCommandLine' -as [type])){
      Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SpotifyR14NativeCommandLine {
  [DllImport("kernel32.dll", SetLastError=true)]
  private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
  [DllImport("kernel32.dll", SetLastError=true)]
  private static extern bool CloseHandle(IntPtr handle);
  [DllImport("ntdll.dll", ExactSpelling=true)]
  private static extern int NtQueryInformationProcess(
    IntPtr handle, int informationClass, IntPtr info,
    int infoSize, out int returned);
  public static string Read(int processId) {
    if(processId <= 0) return null;
    IntPtr handle=OpenProcess(0x1000u, false, processId);
    if(handle==IntPtr.Zero) return null;
    IntPtr buffer=IntPtr.Zero;
    try {
      const int cap=65536;
      buffer=Marshal.AllocHGlobal(cap);
      int written=0;
      // Windows ProcessCommandLineInformation = 60. No memory writes to
      // the observed process and no PROCESS_VM_READ privilege requested.
      int status=NtQueryInformationProcess(handle,60,buffer,cap,out written);
      if(status!=0 || written<0 || written>cap) return null;
      int header=(IntPtr.Size==8)?16:8;
      int bytes=(ushort)Marshal.ReadInt16(buffer,0);
      int maximum=(ushort)Marshal.ReadInt16(buffer,2);
      if(bytes<2 || bytes>maximum || bytes>32768 || (bytes&1)!=0) return null;
      IntPtr ptr=Marshal.ReadIntPtr(buffer,(IntPtr.Size==8)?8:4);
      long offset=ptr.ToInt64()-buffer.ToInt64();
      if(offset<header || offset>cap-bytes) return null;
      if(written!=0 && (written<header || offset>written-bytes)) return null;
      string value=Marshal.PtrToStringUni(ptr,bytes/2);
      if(String.IsNullOrWhiteSpace(value) || value.IndexOf('\0')>=0) return null;
      return value;
    } catch { return null; }
    finally {
      if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer);
      CloseHandle(handle);
    }
  }
}
'@
    }
    $command=[SpotifyR14NativeCommandLine]::Read($processId)
    if([string]::IsNullOrWhiteSpace($command)){return ''}
    # Recheck PID, creation time and executable after the native read;
    # PID reuse or a changed/opaque identity is not a safe observation.
    $now=@(Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId="+$processId) -ErrorAction Stop)
    if($now.Count -ne 1 -or
       [int]$now[0].ProcessId -ne $processId -or
       [datetime]$now[0].CreationDate -ne [datetime]$Observed.CreationDate -or
       [string]$now[0].Name -cne [string]$Observed.Name){return ''}
    return $command
  }catch{return ''}
}
function WriterAdmission([string]$Root,[bool]$LegacyMutexesHeld=$false) {
  $powershell=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='powershell_ise.exe'" -ErrorAction Stop)
  $scriptHosts=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
  if(($powershell.Count+$scriptHosts.Count) -gt 4096){Fail 'PROCESS_INVENTORY_TOO_LARGE'}
  $active=0;$opaque=0;$resident=0;$nativeRecovered=0
  $agentPath=[IO.Path]::GetFullPath((Join-Path $Root 'bin\spotify-control-agent.vbs'))
  $systemHosts=@(
    [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\wscript.exe')),
    [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\cscript.exe')),
    [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'SysWOW64\wscript.exe')),
    [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'SysWOW64\cscript.exe'))
  )
  foreach($p in $powershell){
    $cmd=[string]$p.CommandLine
    if([string]::IsNullOrWhiteSpace($cmd)){
      $cmd=RecoverOpaquePowerShellCommandLine $p
      if([string]::IsNullOrWhiteSpace($cmd)){$opaque++;continue}
      $nativeRecovered++
    }
    if($cmd -match '(?i)spotify-control-self-updater\.ps1|spotify-control\.ps1\s+.*-Action\s+(Maintain|AgentTick)|addon-manager\.ps1\s+.*-Action'){
      $active++
    }
  }
  foreach($p in $scriptHosts){
    $cmd=[string]$p.CommandLine
    if([string]::IsNullOrWhiteSpace($cmd)){$opaque++;continue}
    # Only one VBS entrypoint is accepted. A harmless script that merely
    # cites the pinned agent path as an argument is NOT the real resident.
    $scripts=[regex]::Matches($cmd,'(?i)(?:"([^"]+\.vbs)"|(?<=\s)([^\s"]+\.vbs)(?=\s|$))')
    if($scripts.Count -ne 1){
      if($cmd -match '(?i)spotify.?control|spicetify|addon.?manager'){$opaque++}
      continue
    }
    $raw=if($scripts[0].Groups[1].Success){$scripts[0].Groups[1].Value}else{$scripts[0].Groups[2].Value}
    $resolved=''
    try{$resolved=[IO.Path]::GetFullPath($raw)}catch{}
    $exe=''
    try{$exe=[IO.Path]::GetFullPath([string]$p.ExecutablePath)}catch{}
    $hostTrusted=$false
    foreach($known in $systemHosts){
      if($exe.Equals($known,[StringComparison]::OrdinalIgnoreCase)){$hostTrusted=$true;break}
    }
    if($resolved.Equals($agentPath,[StringComparison]::OrdinalIgnoreCase) -and $hostTrusted){
      $resident++
    }elseif($cmd -match '(?i)spotify.?control|spicetify|addon.?manager' -or
           $resolved.Equals($agentPath,[StringComparison]::OrdinalIgnoreCase)){
      $opaque++
    }
  }
  # The pinned resident VBS does not acquire either mutex itself; its
  # child AgentTick acquires Local\SpotifyControl-AgentTick-<SID> before
  # doing any state work. A LIVE resident may be left running ONLY with
  # both exact named legacy mutexes held by THIS thread.
  return [pscustomobject]@{
    active=$active;opaque=$opaque;resident=$resident;nativeRecovered=$nativeRecovered
    safe=($active -eq 0 -and $opaque -eq 0 -and $resident -le 1 -and
      ($resident -eq 0 -or $LegacyMutexesHeld))
  }
}
function EnterLegacyMutexPair {
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if([string]::IsNullOrWhiteSpace($sid)){Fail 'CURRENT_USER_SID_UNAVAILABLE'}
  $safeSid=([string]$sid -replace '[^A-Za-z0-9]','_')
  $owned=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
  try{
    foreach($purpose in @('Maintenance','AgentTick')){
      $name=('Local\SpotifyControl-{0}-{1}' -f $purpose,$safeSid)
      $mutex=New-Object System.Threading.Mutex($false,$name)
      $got=$false
      try {
        try {$got=$mutex.WaitOne(0,$false)}
        catch [System.Threading.AbandonedMutexException] {
          # Abandonment grants ownership, but indicates an uncertain
          # earlier writer. Release it and ABORT instead of proceeding.
          try{$mutex.ReleaseMutex()}catch{}
          Fail 'ABANDONED_LEGACY_MUTEX'
        }
        if(-not $got){Fail 'LEGACY_WRITER_MUTEX_BUSY'}
        $owned.Add($mutex)
      }catch{
        if(-not $got){$mutex.Dispose()}
        throw
      }
    }
    return $owned
  }catch{
    for($i=$owned.Count-1;$i -ge 0;$i--){
      try{$owned[$i].ReleaseMutex()}catch{}
      try{$owned[$i].Dispose()}catch{}
    }
    throw
  }
}
function ExitLegacyMutexPair($Pair) {
  if($null -eq $Pair){return}
  for($i=$Pair.Count-1;$i -ge 0;$i--){
    try{$Pair[$i].ReleaseMutex()}catch{}
    try{$Pair[$i].Dispose()}catch{}
  }
}
function HoldExactBootstrapFile([string]$Root) {
  # Exact original Bootstrap 1.0.6 cannot be started via -File while
  # its original source is opened with FileShare.None. We acquire the
  # handle AFTER every source proof, immediately before atomic Replace.
  # This does not prevent a malicious same-user copy launched manually.
  $path=Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1'
  $f=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{
    if([int64]$f.Length -ne 42963){Fail 'BOOTSTRAP_FENCE_SOURCE_SIZE_CHANGED'}
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$sha=[BitConverter]::ToString($hasher.ComputeHash($f)).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose()}
    if($sha -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      Fail 'BOOTSTRAP_FENCE_SOURCE_SHA_CHANGED'
    }
    return $f
  }catch{$f.Dispose();throw}
}
function InvokeControlledOfficialStableUpdate {
  param([string]$Root,[IO.FileStream]$BootstrapFileHandle,[bool]$Hosted,$Messages)
  # A single trusted process owns both old legacy mutexes AND the exclusive
  # original Bootstrap file handle. A byte-identical copy runs its authentic
  # self-hash/manifest checks while original-path -File launches are denied.
  if($null -eq $BootstrapFileHandle){Fail 'ORIGINAL_BOOTSTRAP_EXCLUSIVE_HANDLE_MISSING'}
  $dir=Join-Path $Root ('controlled-bootstrap-once-'+[guid]::NewGuid().ToString('N'))
  $originalLocal=$env:LOCALAPPDATA;$originalRoaming=$env:APPDATA
  $oldStatePath=Join-Path $Root 'state.json'
  $oldStateHash=''
  if($null -ne (FileInfo $oldStatePath 4194304)){$oldStateHash=HashFile $oldStatePath}
  $created=$false;$script=''
  $readSharingFence=$null
  try{
    if(-not(ReparseFreePath $Root $dir) -or (Test-Path -LiteralPath $dir)){
      Fail 'CONTROLLED_COPY_DESTINATION_NOT_NEW'
    }
    [void][IO.Directory]::CreateDirectory($dir)
    $created=$true
    if(-not(IsPlainDirectory $dir)){Fail 'CONTROLLED_COPY_DIRECTORY_UNSAFE'}
    $script=Join-Path $dir 'spotify-control-self-updater.ps1'
    $BootstrapFileHandle.Position=0
    $buffer=New-Object byte[] ([int]$BootstrapFileHandle.Length)
    $read=0
    while($read -lt $buffer.Length){
      $n=$BootstrapFileHandle.Read($buffer,$read,$buffer.Length-$read)
      if($n -le 0){Fail 'ORIGINAL_BOOTSTRAP_READ_INCOMPLETE'}
      $read+=$n
    }
    if((HashBytes $buffer) -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      Fail 'COPIED_BOOTSTRAP_SOURCE_NOT_TRUSTED'
    }
    UniqueFile $script $buffer
    if((HashFile $script) -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      Fail 'CONTROLLED_BOOTSTRAP_COPY_HASH_MISMATCH'
    }
    # The actual v0.6.28 SelfTest reads the installed Bootstrap trust
    # root. FileShare.None would block this legitimate read and cause a
    # candidate SelfTest failure, as proven by the R7 hosted integration.
    # Keep FileShare.None strictly for the preceding journal CAS. During
    # the genuine Bootstrap update, downgrade to FileShare.Read (no writes
    # or deletion) under BOTH still-held named legacy writer mutexes.
    $BootstrapFileHandle.Dispose()
    $readSharingFence=[IO.File]::Open(
       (Join-Path $Root 'bootstrap\spotify-control-self-updater.ps1'),
       [IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    if([int64]$readSharingFence.Length -ne 42963){Fail 'SHARED_BOOTSTRAP_TRUST_ROOT_SIZE_CHANGED'}
    $h=[Security.Cryptography.SHA256]::Create()
    try{$check=[BitConverter]::ToString($h.ComputeHash($readSharingFence)).Replace('-','').ToLowerInvariant()}
    finally{$h.Dispose()}
    if($check -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      Fail 'SHARED_BOOTSTRAP_TRUST_ROOT_SHA_CHANGED'
    }
    $Messages.Add('BOOTSTRAP_ORIGINAL_READ_SHARE_NO_WRITE=HELD')
    if(-not (WriterAdmission $Root $true).safe){Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'}
    if($Hosted){
      $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
      $env:LOCALAPPDATA=Join-Path $fixture 'LocalAppData'
      $env:APPDATA=Join-Path $fixture 'Roaming'
      [void][IO.Directory]::CreateDirectory($env:APPDATA)
    }
    # Do not trust an existing scheduled updater, stale report, or caller's
    # version claim; the real original bootstrap is the sole update engine.
    # Capture raw child output only IN MEMORY; never echo remote error text
    # containing private paths, tokens or usernames.
    $check=InvokeControlledBootstrapAction -Script $script -Action 'Check'
    if([string]$check.installed_version -cne '0.6.20' -or
       [string]$check.result.latest_version -cne '0.6.28' -or
       [int]$check.result.edge_count -ne 8){Fail 'OFFICIAL_EIGHT_EDGE_PREFLIGHT_NOT_EXACT'}
    $Messages.Add('OFFICIAL_BOOTSTRAP_EIGHT_EDGE_PLAN=EXACT')
    if(-not (WriterAdmission $Root $true).safe){Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'}
    $changed=InvokeControlledBootstrapAction -Script $script -Action 'Update'
    if([string]$changed.transaction_status -cne 'committed' -or
       [string]$changed.result.Status -cne 'committed'){
      Fail 'OFFICIAL_UPDATE_NOT_COMMITTED'
    }
    if(-not(SourcePin (Join-Path $Root 'bin\spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0') -or
       -not(SourcePin (Join-Path $Root 'bin\addon-manager.ps1') 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
       -not(SourcePin (Join-Path $Root 'bin\spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')){
      Fail 'OFFICIAL_UPDATED_BIN_IDENTITY_NOT_EXACT'
    }
    $post=InvokeControlledBootstrapAction -Script $script -Action 'Check'
    if([string]$post.installed_version -cne '0.6.28' -or
       $post.result.already_current -ne $true -or
       [int]$post.result.edge_count -ne 0){
      Fail 'OFFICIAL_POSTCHECK_NOT_CURRENT'
    }
    if($oldStateHash.Length -gt 0 -and
       (HashFile $oldStatePath) -cne $oldStateHash){
      Fail 'CONTROLLED_UPDATE_CHANGED_OWNER_STATE'
    }
    $Messages.Add('OFFICIAL_BOOTSTRAP_EXACT_V0628_R17=COMMITTED')
    $Messages.Add('STABLE_POSTCHECK_ALREADY_CURRENT=TRUE')
    $Messages.Add('USER_STATE_JSON=UNCHANGED')
  }finally{
    if($null -ne $readSharingFence){try{$readSharingFence.Dispose()}catch{}}
    if($Hosted){$env:LOCALAPPDATA=$originalLocal;$env:APPDATA=$originalRoaming}
    if($created -and $script.Length -gt 0 -and
       (FileInfo $script 2097152) -and
       (HashFile $script) -ceq 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      try{[IO.File]::Delete($script)}catch{}
    }
    if($created -and (IsPlainDirectory $dir)){
      try{
        if(@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0){
          [IO.Directory]::Delete($dir,$false)
        }
      }catch{}
    }
  }
}
function InvokeControlledBootstrapAction {
  param([string]$Script,[string]$Action)
  if($Action -cnotin @('Check','Update')){Fail 'UNSUPPORTED_BOOTSTRAP_ACTION'}
  if($Action -ceq 'Check'){$script:originalBootstrapCheckAttempted=$true}
  if($Action -ceq 'Update'){$script:originalBootstrapUpdateAttempted=$true}
  $out=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -Action $Action -Json 2>&1)
  $code=$LASTEXITCODE
  if($code -ne 0){Fail ('OFFICIAL_BOOTSTRAP_'+$Action.ToUpperInvariant()+'_FAILED_NO_AUTORETRY')}
  $last=@($out|Where-Object{[string]$_ -match '^\s*\{' }|Select-Object -Last 1)
  if($last.Count -ne 1){Fail 'OFFICIAL_BOOTSTRAP_JSON_RECEIPT_MISSING'}
  try{$obj=$last[0]|ConvertFrom-Json -ErrorAction Stop}
  catch{Fail 'OFFICIAL_BOOTSTRAP_JSON_RECEIPT_INVALID'}
  if($obj.success -ne $true -or [string]$obj.action -cne $Action){Fail 'OFFICIAL_BOOTSTRAP_ACTION_NOT_SUCCESS'}
  return $obj
}
$messages=New-Object System.Collections.Generic.List[string]
$messages.Add('DIAGNOSTIC=SPOTIFY_BOOTSTRAP_PREPARED_ORPHAN_TERMINALIZER_HOLD_R5')
$messages.Add($(if($ContinueOfficialStableUpdate){'CORE_UPDATE=OPT_IN_ONLY;NETWORK=BOOTSTRAP_PINNED_OFFICIAL;SETTINGS_WRITE=NO;SCHEDULE_WRITE=NO'}else{'APP_BIN_WRITE=NO;SPOTIFY_EXEC=NO;NETWORK=NO;SETTINGS_WRITE=NO;SCHEDULE_WRITE=NO'}))
$hosted= -not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
$staging=$null
$stagingOwned=$false
$legacyMutexes=$null
$exclusiveBootstrap=$null
$stage='INITIAL_PREFLIGHT'
$script:originalBootstrapCheckAttempted=$false
$script:originalBootstrapUpdateAttempted=$false
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
  if($ContinueOfficialStableUpdate -and (-not $Commit -or $OfficialUpdateApprovalPhrase -cne 'APPROVE_OFFICIAL_V0628_CORE_UPGRADE')){Fail 'OFFICIAL_STABLE_UPDATE_EXPLICIT_APPROVAL_MISSING'}
  # R6: coordinate with the exact OLD stable v0.6.20/r9 legacy engine.
  # The VBS resident stays running; its spawned AgentTick must acquire
  # AgentTick mutex, and normal Maintain must acquire Maintenance mutex.
  # These OS handles are held on this thread throughout journal repair.
  # No task disable, agent termination, source replacement or config edit.
  if($Commit){
    $stage='LEGACY_DOUBLE_MUTEX_ACQUIRE'
    $legacyMutexes=EnterLegacyMutexPair
    $messages.Add('LEGACY_MAINTENANCE_AND_AGENTTICK_MUTEX=HELD')
  }
  $obs=WriterAdmission $root ([bool]($null -ne $legacyMutexes))
  $messages.Add('POSSIBLE_CONCURRENT_WRITERS='+$(if($obs.active -gt 0){'DETECTED'}elseif($obs.opaque -gt 0){'UNKNOWN'}else{'NONE_OBSERVED'}))
  $messages.Add('NATIVE_POWERSHELL_COMMANDLINE_RECOVERED='+[string]$obs.nativeRecovered)
  $messages.Add('RESIDENT_AGENT='+$(if($obs.resident -gt 1){'MULTIPLE_BLOCKED'}elseif($obs.resident -eq 1 -and $Commit){'RUNNING_TICKS_MUTEX_FENCED'}elseif($obs.resident -eq 1){'RUNNING_DRYRUN_ONLY'}elseif($obs.opaque -gt 0){'UNKNOWN'}else{'NOT_OBSERVED'}))
  if($Commit -and -not $obs.safe){Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'}
  $stage='FIRST_SOURCE_PROOF'
  $pre=Probe $root
  if($pre.stableCommitted){
    $messages.Add('OFFICIAL_STABLE_V0628_R17=EXACT_BIN_AND_COMMITTED_JOURNAL')
    $messages.Add('ORIGINAL_PREPARED_ESCROW_AND_PREVIOUS_BACKUP=EXACT')
    $messages.Add('RESULT=ALREADY_COMMITTED_STABLE_V0628_VERIFIED_NO_ACTION')
  }else{
  $messages.Add('SOURCE_AND_FULL_TREES=EXACT_PREPARED_BEFORE')
  $messages.Add('BACKUP_AND_STAGING=NO_CONFLICT')
  $messages.Add('TRANSACTION_ORIGINAL_SHA_PIN=YES')
  if(-not $Commit){
     $messages.Add('RESULT='+$(if($pre.reconciled){
        'EXACT_PRIOR_RECONCILIATION_VERIFIED_EXPLICIT_UPDATE_APPROVAL_REQUIRED'
     }elseif($pre.officialRollback){
        'EXACT_PRIOR_ESCROW_AND_OFFICIAL_ROLLBACK_VERIFIED_EXPLICIT_APPROVAL_REQUIRED'
     }else{'READY_FOR_EXPLICIT_AUTHORIZED_JOURNAL_ONLY_RECONCILIATION'}))
  }else{
    if($pre.officialRollback){
      # This source- and tree-verified official rollback is a NEW journal.
      # An unattended retry is never authorized.
      if(-not $ContinueOfficialStableUpdate){
        $messages.Add('RESULT=OFFICIAL_ROLLBACK_RECONCILED_NO_MUTATION')
      }else{
        $stage='RESUME_OFFICIAL_ROLLBACK_WITH_PRIOR_ESCROW'
        $check=Probe $root $pre.id
        if(-not $check.officialRollback -or $check.digest -cne $pre.digest){
          Fail 'RESUME_JOURNAL_OR_BASELINE_CHANGED'
        }
        if(-not (WriterAdmission $root $true).safe){
          Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'
        }
        $exclusiveBootstrap=HoldExactBootstrapFile $root
        $messages.Add('PRIOR_PREPARED_ORIGINAL_ESCROW=EXACT_UNCHANGED')
        $messages.Add('CURRENT_OFFICIAL_ROLLBACK_AND_OLD_BIN=EXACT')
        $messages.Add('RESUME_NO_JOURNAL_CAS=YES')
        $stage='RETRY_EXPLICIT_OFFICIAL_V0628_STABLE_UPDATE'
        InvokeControlledOfficialStableUpdate -Root $root -BootstrapFileHandle $exclusiveBootstrap -Hosted $hosted -Messages $messages
        $messages.Add('RESULT=RESUMED_AFTER_OFFICIAL_ROLLBACK_STABLE_V0628_R17_VERIFIED')
      }
    }elseif($pre.reconciled){
      # Only a second *explicitly approved* stable update can resume a
      # terminalized journal. No new escrow and no second transaction CAS.
      if(-not $ContinueOfficialStableUpdate){
        $messages.Add('RESULT=ALREADY_RECONCILED_JOURNAL_UNCHANGED')
      }else{
        $stage='RESUME_OWN_EXACT_RECONCILED_JOURNAL'
        $check=Probe $root $pre.id
        if(-not $check.reconciled -or $check.digest -cne $pre.digest){
          Fail 'RESUME_JOURNAL_OR_BASELINE_CHANGED'
        }
        if(-not (WriterAdmission $root $true).safe){
          Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'
        }
        $exclusiveBootstrap=HoldExactBootstrapFile $root
        $messages.Add('PREVIOUS_ORIGINAL_ESCROW=EXACT_UNCHANGED')
        $messages.Add('RESUME_RECONCILIATION_CAS=SKIPPED_ALREADY_TERMINAL')
        $stage='RESUME_OFFICIAL_V0628_STABLE_UPDATE'
        InvokeControlledOfficialStableUpdate -Root $root -BootstrapFileHandle $exclusiveBootstrap -Hosted $hosted -Messages $messages
        $messages.Add('RESULT=RESUMED_OFFICIAL_STABLE_V0628_R17_COMMITTED_VERIFIED')
      }
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
    # Only this invocation's successfully created staging file may be cleaned.
    # A pre-existing file that made CreateNew fail must never be deleted.
    $stagingOwned=$true
    $stage='THIRD_SOURCE_PROOF'
    $third=Probe $root $pre.id
    if($third.digest -cne $pre.digest -or (Test-Path -LiteralPath $escrow)){
      Fail 'RACE_OR_ESCROW_CHANGED_BEFORE_REPLACE'
    }
    # File.Replace atomically archives old journal into a *new* escrow file
    # while replacing the transaction. No original bin files are touched.
    # Do NOT invoke the installed Bootstrap, including -Action Check.
    $finalAdmission=WriterAdmission $root $true
    if(-not $finalAdmission.safe){Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'}
    # An uncooperative original Bootstrap -File launch is fenced at the
    # OS file-sharing layer during the critical journal CAS. Before this,
    # every manifest/source/transaction/backup hash has been rechecked.
    $stage='EXCLUSIVE_BOOTSTRAP_FENCE'
    $exclusiveBootstrap=HoldExactBootstrapFile $root
    $afterFenceAdmission=WriterAdmission $root $true
    if(-not $afterFenceAdmission.safe){Fail 'ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE'}
    if((HashFile $pre.txn) -cne $pre.digest){Fail 'TRANSACTION_CHANGED_BEFORE_ATOMIC_REPLACE'}
    $messages.Add('EXACT_BOOTSTRAP_FILESHARE_NONE=HELD')
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
    $messages.Add('JOURNAL_ORPHAN_TERMINALIZED_WITHOUT_BIN_SWAP=YES')
    if($ContinueOfficialStableUpdate){
      $stage='OFFICIAL_V0628_STABLE_UPDATE'
      InvokeControlledOfficialStableUpdate -Root $root -BootstrapFileHandle $exclusiveBootstrap -Hosted $hosted -Messages $messages
      $messages.Add('RESULT=OFFICIAL_STABLE_V0628_R17_COMMITTED_VERIFIED')
    }else{
      $messages.Add('RESULT=JOURNAL_ONLY_RECONCILED_REQUIRES_FRESH_UPDATE_ACCEPTANCE')
    }
    }
  }
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
    'EXPLICIT_APPROVAL_MISSING','OFFICIAL_STABLE_UPDATE_EXPLICIT_APPROVAL_MISSING','PROCESS_INVENTORY_TOO_LARGE','ACTIVE_OR_OPAQUE_PROCESS_REQUIRES_QUIESCENCE',
    'CURRENT_USER_SID_UNAVAILABLE','LEGACY_WRITER_MUTEX_BUSY','ABANDONED_LEGACY_MUTEX',
    'BOOTSTRAP_FENCE_SOURCE_SIZE_CHANGED','BOOTSTRAP_FENCE_SOURCE_SHA_CHANGED',
    'TRANSACTION_CHANGED_BEFORE_ATOMIC_REPLACE','ORIGINAL_BOOTSTRAP_EXCLUSIVE_HANDLE_MISSING',
    'CONTROLLED_COPY_DESTINATION_NOT_NEW','CONTROLLED_COPY_DIRECTORY_UNSAFE',
    'ORIGINAL_BOOTSTRAP_READ_INCOMPLETE','COPIED_BOOTSTRAP_SOURCE_NOT_TRUSTED',
    'CONTROLLED_BOOTSTRAP_COPY_HASH_MISMATCH','SHARED_BOOTSTRAP_TRUST_ROOT_SIZE_CHANGED',
    'SHARED_BOOTSTRAP_TRUST_ROOT_SHA_CHANGED','OFFICIAL_EIGHT_EDGE_PREFLIGHT_NOT_EXACT',
    'OFFICIAL_UPDATE_NOT_COMMITTED','OFFICIAL_UPDATED_BIN_IDENTITY_NOT_EXACT',
    'OFFICIAL_POSTCHECK_NOT_CURRENT','CONTROLLED_UPDATE_CHANGED_OWNER_STATE',
    'OFFICIAL_BOOTSTRAP_CHECK_FAILED_NO_AUTORETRY','OFFICIAL_BOOTSTRAP_UPDATE_FAILED_NO_AUTORETRY',
    'OFFICIAL_BOOTSTRAP_JSON_RECEIPT_MISSING','OFFICIAL_BOOTSTRAP_JSON_RECEIPT_INVALID',
    'OFFICIAL_BOOTSTRAP_ACTION_NOT_SUCCESS','UNSUPPORTED_BOOTSTRAP_ACTION',
    'TRANSACTION_RACE_BETWEEN_PREFLIGHTS','EXISTING_ESCROW_NO_OVERWRITE','ESCROW_PATH_UNSAFE',
    'TRANSACTION_NOT_PREPARED_OR_OWN_RECONCILED','PRIOR_BACKUP_ROOT_UNSAFE',
    'PRIOR_BACKUP_SEARCH_LIMIT','PREVIOUS_ORIGINAL_ESCROW_UNSAFE',
    'PREVIOUS_ORIGINAL_ESCROW_UNREADABLE','PREVIOUS_ORIGINAL_ESCROW_SOURCE_MISMATCH',
    'PREVIOUS_ORIGINAL_ESCROW_TREE_OR_PATH_MISMATCH',
    'PREVIOUS_ORIGINAL_ESCROW_AMBIGUOUS','PREVIOUS_ORIGINAL_ESCROW_MISSING_OR_MULTIPLE',
    'COMMITTED_SOURCE_SET_NOT_EXACT_STABLE','COMMITTED_JOURNAL_UNREADABLE_OR_UNSAFE',
    'COMMITTED_JOURNAL_NOT_EXACT_OFFICIAL_STABLE','COMMITTED_JOURNAL_ID_INVALID',
    'COMMITTED_JOURNAL_HASH_PINS_INVALID','COMMITTED_JOURNAL_PATH_BINDINGS_INVALID',
    'COMMITTED_JOURNAL_REPARSE_OR_PATH_UNSAFE',
    'COMMITTED_TRANSACTION_STAGING_STILL_PRESENT','COMMITTED_BIN_OR_BACKUP_TREE_NOT_EXACT',
    'COMMITTED_STABLE_MISSING_PREPARED_ESCROW',
    'OFFICIAL_ROLLBACK_WITHOUT_ORIGINAL_ESCROW','PREVIOUS_ESCROW_PATH_UNSAFE',
    'PREVIOUS_ESCROW_NOT_FOUND','PREVIOUS_ESCROW_UNREADABLE',
    'PREVIOUS_ESCROW_PROVENANCE_INVALID','RECONCILIATION_TIMESTAMP_INVALID',
    'RECONCILED_JOURNAL_NOT_OWN_EXACT_BYTES','RESUME_JOURNAL_OR_BASELINE_CHANGED',
    'ESCROW_HASH_MISMATCH','STAGING_PATH_UNSAFE','RACE_OR_ESCROW_CHANGED_BEFORE_REPLACE',
    'POST_RECONCILIATION_INDETERMINATE_DO_NOT_RETRY','POST_RECONCILIATION_TREE_CHANGED_DO_NOT_RETRY')
  if($kind -cnotin $allowed){$kind='UNVERIFIED_FAIL_CLOSED'}
  $messages.Add('HOLD_REASON='+$kind)
  $messages.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  if($null -ne $exclusiveBootstrap){try{$exclusiveBootstrap.Dispose()}catch{}}
  if($stagingOwned -and $null -ne $staging -and [IO.File]::Exists($staging)){
    try{[IO.File]::Delete($staging)}catch{}
  }
  if($null -ne $legacyMutexes){ExitLegacyMutexPair $legacyMutexes}
}
$messages.Add('BOOTSTRAP_CHECK_ATTEMPTED='+$(if($script:originalBootstrapCheckAttempted){'YES'}else{'NO'})+
  ';BOOTSTRAP_UPDATE_ATTEMPTED='+$(if($script:originalBootstrapUpdateAttempted){'YES'}else{'NO'})+
  ';CORE_UPDATE_APPROVAL='+$(if($ContinueOfficialStableUpdate){'OPT_IN_REQUESTED'}else{'NOT_REQUESTED'})+
  ';USER_DATA_DELETE=NO')
$messages.Add('PRIVATE_PATHS_TRANSACTION_IDS_ERRORS_EXPORTED=NO')
if(-not $hosted){
  try{Set-Clipboard -Value ($messages -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$messages|ForEach-Object {Write-Output $_}
