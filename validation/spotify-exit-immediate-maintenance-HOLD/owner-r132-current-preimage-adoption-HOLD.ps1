[CmdletBinding()]
param(
  [ValidateSet('Plan','Adopt')][string]$Mode='Plan',
  [string]$ApprovalPhrase='',
  [switch]$SyntheticHostTest,
  [string]$PreSwapMainSha='',
  [switch]$NoClipboard
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Phase='PRECHECK'
$Ready=$false
$Touched=$false
$Report=New-Object 'System.Collections.Generic.List[string]'
function Emit([string]$Key,[string]$Value){[void]$Report.Add($Key+'='+$Value)}
function HFile([string]$Path){
  $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'UNSAFE_FILE'}
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function HText([string]$Text){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{
    $bytes=([Text.UTF8Encoding]::new($false)).GetBytes($Text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  }finally{$sha.Dispose()}
}
function Tree([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Container)){throw 'ROOT_MISSING'}
  $parent=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if(($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ROOT_REPARSE'}
  $full=$parent.FullName.TrimEnd([char[]]@('\','/'))
  $rows=New-Object 'System.Collections.Generic.List[object]'
  foreach($item in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop | Sort-Object FullName)){
    if($rows.Count -ge 50000){throw 'TOO_MANY_FILES'}
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ENTRY_REPARSE'}
    $name=$item.FullName.Substring($full.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
    if([string]::IsNullOrWhiteSpace($name)){continue}
    if($item.PSIsContainer){
      $rows.Add([pscustomobject]@{path=$name;type='dir';size=[int64]0;sha256=$null})
    }else{
      $rows.Add([pscustomobject]@{path=$name;type='file';size=[int64]$item.Length;sha256=(HFile $item.FullName)})
    }
  }
  $rowsSorted=@($rows.ToArray() | Sort-Object path,type)
  return (HText ([string]($rowsSorted | ConvertTo-Json -Compress -Depth 5)))
}
function F($Obj,[string]$Name){
  if($null -eq $Obj){return $null}
  $p=$Obj.PSObject.Properties[$Name]
  if($null -eq $p){return $null}
  return $p.Value
}
function Strict-PathEquals([string]$A,[string]$B){
  if([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)){return $false}
  return [string]::Equals([IO.Path]::GetFullPath($A),[IO.Path]::GetFullPath($B),
                          [StringComparison]::OrdinalIgnoreCase)
}
function Backup-With([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'CONFIG_MISSING'}
  [void](HFile $Path)
  $section='';$found=$null
  foreach($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)){
    if($line -match '^\s*\[([^\]]+)\]\s*$'){$section=$Matches[1];continue}
    if($section -ieq 'Backup' -and $line -match '^\s*with\s*=\s*(.*?)\s*$'){$found=$Matches[1];break}
  }
  return $found
}
function Sample-Current{
  $p=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $ledger=Join-Path $p 'spicetify-last-transaction.json'
  $state=Join-Path $p 'state.json'
  $live=Join-Path $env:LOCALAPPDATA 'spicetify'
  $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify\Apps'
  $main=Join-Path $p 'bin\spotify-control.ps1'
  $mainSHA=HFile $main
  $ledgerSHA=HFile $ledger
  $stateSHA=HFile $state
  $txn=Get-Content -LiteralPath $ledger -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if([string](F $txn 'schema') -cne '3' -or (F $txn 'root_transaction') -cne $true -or
     [string](F $txn 'status') -cne 'awaiting-guard'){throw 'NOT_EXACT_PENDING_ROOT_TRANSACTION'}
  $id=[string](F $txn 'id')
  if($id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){throw 'TRANSACTION_ID_INVALID'}
  $oldRoot=Join-Path $p ('backups\spicetify-transactions\'+$id+'\root-before')
  if(-not (Strict-PathEquals ([string](F $txn 'target_root')) $live) -or
     -not (Strict-PathEquals ([string](F $txn 'backup_root')) $oldRoot)){
    throw 'TRANSACTION_OWNER_PATH_MISMATCH'
  }
  $siblingOld=Join-Path (Split-Path -Parent $live) ('.spotifycontrol-spicetify-old-'+$id)
  $siblingNew=Join-Path (Split-Path -Parent $live) ('.spotifycontrol-spicetify-new-'+$id)
  if(-not (Strict-PathEquals ([string](F $txn 'same_dir_old_root')) $siblingOld) -or
     -not (Strict-PathEquals ([string](F $txn 'same_dir_new_root')) $siblingNew)){
    throw 'TRANSACTION_SWAP_PATH_MISMATCH'
  }
  if(Test-Path -LiteralPath $siblingOld){throw 'UNCLEARED_OLD_SWAP_FOLDER'}
  if(Test-Path -LiteralPath $siblingNew){throw 'UNCLEARED_NEW_SWAP_FOLDER'}
  if([string](F $txn 'before_version') -cne '2.46.4'){throw 'UNKNOWN_PREIMAGE_CLI_VERSION'}
  $rootSHA=Tree $live
  $backupSHA=Tree $oldRoot
  $exeSHA=HFile (Join-Path $live 'spicetify.exe')
  if($rootSHA -cne [string](F $txn 'before_tree_sha256') -or
     $backupSHA -cne $rootSHA -or
     $exeSHA -cne [string](F $txn 'before_sha256') -or
     $exeSHA -cne $script:ExpectedOldCliSHA){
    throw 'CLI_OR_BACKUP_NOT_EXACT_PREIMAGE'
  }
  if((Backup-With $config) -cne '2.46.4'){throw 'EXTERNAL_BACKUP_WITH_NOT_PREIMAGE'}
  $stateObj=Get-Content -LiteralPath $state -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if([string](F $stateObj 'spicetify_last_transaction_id') -ceq $id){
    throw 'STATE_ALREADY_LINKED_REVIEW_REQUIRED'
  }
  $roamSHA=Tree $spice
  $appsSHA=Tree $apps
  if((HFile $ledger) -cne $ledgerSHA -or (HFile $state) -cne $stateSHA){
    throw 'SOURCES_CHANGED_DURING_READ'
  }
  return [pscustomobject]@{
    Root=$p;Main=$main;MainSHA=$mainSHA;Ledger=$ledger;LedgerSHA=$ledgerSHA
    State=$state;StateSHA=$stateSHA;Live=$live;LiveSHA=$rootSHA
    Backup=$oldRoot;BackupSHA=$backupSHA;Txn=$txn;Id=$id
    Config=$config;ConfigSHA=(HFile $config)
    Roaming=$spice;RoamingSHA=$roamSHA;Apps=$apps;AppsSHA=$appsSHA
  }
}
function Write-NewFile([string]$Path,[byte[]]$Bytes){
  $fs=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$fs.Write($Bytes,0,$Bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
}
function Write-NewJson([string]$Path,$Object){
  $json=$Object | ConvertTo-Json -Depth 12
  Write-NewFile -Path $Path -Bytes ([Text.UTF8Encoding]::new($false)).GetBytes($json)
  return (HFile $Path)
}
function Acquire([string]$Purpose,[string]$Sid){
  # Exactly match the product's Enter-SpotifyControlMutex naming contract.
  # User SID hyphens MUST become underscores for a shared cross-process lock.
  $safeSid=([string]$Sid -replace '[^A-Za-z0-9]','_')
  $name="Local\SpotifyControl-{0}-{1}" -f $Purpose,$safeSid
  $mutex=[Threading.Mutex]::new($false,$name)
  try{
    $acquired=$false
    try{$acquired=$mutex.WaitOne(0,$false)}
    catch [Threading.AbandonedMutexException]{$acquired=$true}
    if(-not $acquired){throw 'AGENT_MUTEX_BUSY'}
    return $mutex
  }catch{$mutex.Dispose();throw}
}
Emit 'DIAGNOSTIC' 'SPOTIFY_R132_OWNER_APPROVED_CURRENT_PREIMAGE_ADOPTION'
Emit 'MODE' $Mode
Emit 'NETWORK' 'NO'
Emit 'NATIVE_SPICETIFY' 'NOT_EXECUTED'
Emit 'AUTOMATIC_RETRY' 'NO'
Emit 'MAIN_OR_AGENT_UPDATE' 'NO'
$mutex1=$null;$mutex2=$null
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     $PSVersionTable.PSEdition -cne 'Desktop'){throw 'WIN_PS51_REQUIRED'}
  $script:ExpectedMainSHA='4ac4e4ccb48c57b59b9fe87d688df76dd823998e5e791f4ed877c289175e7d99'
  $script:ExpectedOldCliSHA='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
  if($SyntheticHostTest){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       -not $env:LOCALAPPDATA.StartsWith([string]$env:RUNNER_TEMP,[StringComparison]::OrdinalIgnoreCase)){
      throw 'SYNTHETIC_HOST_REJECTED'
    }
    $script:ExpectedMainSHA=[string]$env:R132_TEST_MAIN_SHA
    $script:ExpectedOldCliSHA=[string]$env:R132_TEST_CLI_SHA
  }
  if(-not [string]::IsNullOrEmpty($PreSwapMainSha)){
    if($Mode -cne 'Plan'){throw 'PRESWAP_PIN_ALLOWED_ONLY_IN_READONLY_PLAN'}
    if(-not $SyntheticHostTest -and
       $PreSwapMainSha -cnotin @(
         'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d',
         'beb850064670c078a679585ace25f8071daa88c0b264185c03ef3364329b431b'
       )){throw 'PRESWAP_MAIN_NOT_APPROVED_SOURCE'}
    if($PreSwapMainSha -cnotmatch '^[a-f0-9]{64}$'){
      throw 'PRESWAP_PIN_FORMAT_INVALID'
    }
    $script:ExpectedMainSHA=$PreSwapMainSha
  }
  if($Mode -ceq 'Adopt'){
    if($ApprovalPhrase -cne 'APPROVE_R132_CURRENT_PREIMAGE_ONCE'){
      throw 'OWNER_APPROVAL_REQUIRED'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $SyntheticHostTest -and
       ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ADMIN_USER_REJECTED'}
    $sid=$identity.User.Value
    $mutex1=Acquire 'Maintenance' $sid
    $mutex2=Acquire 'AgentTick' $sid
    if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
      throw 'SPOTIFY_STILL_RUNNING'
    }
  }
  $Phase='READ_EXACT_PREIMAGE'
  $o=Sample-Current
  Emit 'CLI_ROOT' 'PREIMAGE_MATCH'
  Emit 'CLI_BACKUP' 'PREIMAGE_MATCH'
  Emit 'EXTERNAL_SNAPSHOT_READY' 'YES'
  Emit 'STATE_LINK' 'DIFFERENT'
  if($o.MainSHA -cne $script:ExpectedMainSHA){
    throw 'R132_AWARE_MAIN_NOT_YET_DEPLOYED'
  }
  Emit 'CURRENT_MAIN' $(if([string]::IsNullOrEmpty($PreSwapMainSha)){'R132_AWARE_HOLD_CANDIDATE_PINNED'}else{'EXACT_PRE_SWAP_MAIN_PINNED'})
  if($Mode -ceq 'Plan'){
    Emit 'RESULT' 'OWNER_ADOPTION_PLAN_READY_NOT_APPLIED'
  }else{
    $Phase='CREATE_OWNER_SNAPSHOT'
    $dest=Join-Path $o.Root ('owner-recovery\R132-'+$o.Id)
    if(Test-Path -LiteralPath $dest){throw 'OWNER_SNAPSHOT_ALREADY_EXISTS_NO_RETRY'}
    [void][IO.Directory]::CreateDirectory($dest)
    [IO.File]::Copy($o.Ledger,(Join-Path $dest 'original-ledger.json'),$false)
    [IO.File]::Copy($o.State,(Join-Path $dest 'original-state.json'),$false)
    if((HFile (Join-Path $dest 'original-ledger.json')) -cne $o.LedgerSHA -or
       (HFile (Join-Path $dest 'original-state.json')) -cne $o.StateSHA){throw 'JOURNAL_OR_STATE_COPY_FAILED'}
    foreach($pair in @(@($o.Live,'cli-root',$o.LiveSHA),
                       @($o.Roaming,'spicetify-roaming',$o.RoamingSHA),
                       @($o.Apps,'spotify-apps',$o.AppsSHA))){
      $to=Join-Path $dest ([string]$pair[1])
      Copy-Item -LiteralPath ([string]$pair[0]) -Destination $to -Recurse -Force -ErrorAction Stop
      if((Tree $to) -cne [string]$pair[2]){throw 'EXTERNAL_OR_CLI_SNAPSHOT_CHANGED'}
    }
    $Phase='CERTIFY_ADOPTION_EVIDENCE'
    $evidence=[ordered]@{
      schema=1;transaction_id=$o.Id
      evidence_kind='CURRENT_PREIMAGE_ADOPTED_NOT_HISTORICAL_EXTERNAL_ROLLBACK'
      ledger_sha256=$o.LedgerSHA;state_sha256=$o.StateSHA
      root_tree_sha256=$o.LiveSHA;roaming_tree_sha256=$o.RoamingSHA
      apps_tree_sha256=$o.AppsSHA;config_sha256=$o.ConfigSHA
      main_sha256=$o.MainSHA;created_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    $proof=Join-Path $dest 'adoption-evidence.json'
    $evidenceSHA=Write-NewJson $proof $evidence
    if((HFile $o.Ledger) -cne $o.LedgerSHA -or
       (HFile $o.State) -cne $o.StateSHA -or
       (Tree $o.Live) -cne $o.LiveSHA -or
       (Tree $o.Roaming) -cne $o.RoamingSHA -or
       (Tree $o.Apps) -cne $o.AppsSHA -or
       (HFile $o.Config) -cne $o.ConfigSHA -or
       (HFile $o.Main) -cne $o.MainSHA){throw 'PREIMAGE_CHANGED_BEFORE_PUBLICATION'}
    if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
      throw 'SPOTIFY_STARTED_BEFORE_PUBLICATION'
    }
    $Phase='ATOMIC_JOURNAL_TRANSITION'
    $newLedger=$o.Txn | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $newLedger.status='owner-reviewed-preimage'
    $newLedger | Add-Member -NotePropertyName owner_reconciliation -NotePropertyValue (
       [pscustomobject]@{
         schema=1;kind='OWNER_APPROVED_CURRENT_PREIMAGE_NOT_EXTERNAL_ROLLBACK'
         snapshot_root=$dest;evidence_sha256=$evidenceSHA
       }) -ErrorAction Stop
    $stage=Join-Path $o.Root ('.r132-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $tempSha=Write-NewJson $stage $newLedger
    $previous=$o.Ledger+'.r132-previous'
    if(Test-Path -LiteralPath $previous){throw 'PREVIOUS_SNAPSHOT_COLLISION'}
    if((HFile $o.Ledger) -cne $o.LedgerSHA){throw 'LEDGER_CHANGED_BEFORE_ATOMIC_SWAP'}
    [IO.File]::Replace($stage,$o.Ledger,$previous,$true)
    $Touched=$true
    if((HFile $o.Ledger) -cne $tempSha -or
       (HFile $previous) -cne $o.LedgerSHA){
      throw 'JOURNAL_PUBLICATION_READBACK_FAILED'
    }
    Emit 'NEW_LEDGER' 'OWNER_REVIEWED_PREIMAGE_NOT_ROLLBACK'
    Emit 'ORIGINAL_LEDGER_AND_EXTERNAL_SNAPSHOTS' 'SHA_VERIFIED_AND_RETAINED'
    Emit 'STATE' 'UNCHANGED_ID_DIFFERENCE_RETAINED'
    Emit 'RESULT' 'OWNER_ADOPTION_RECEIPTED_NOT_SPOTIFY_APPLY_PROOF'
  }
}catch{
  Emit 'FAILED_PHASE' $Phase
  Emit 'RESULT' $(if($Touched){'HOLD_OWNER_REVIEW_AFTER_LEDGER_WRITE'}else{'HOLD_NO_OPERATING_MUTATION'})
}finally{
  foreach($m in @($mutex2,$mutex1)){
    if($null -ne $m){try{$m.ReleaseMutex()}finally{$m.Dispose()}}
  }
}
$receipt=@($Report.ToArray()) -join [Environment]::NewLine
if(-not $NoClipboard){try{Set-Clipboard -Value $receipt -ErrorAction Stop}catch{}}
Write-Output $receipt
