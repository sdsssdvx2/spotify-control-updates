# R127 HOLD: one-pass, no-network, NO-MUTATION read-only classification of
# an unsettled full-root Spicetify transaction. Do not import/live-run
# spotify-control.ps1. Never invoke Spicetify, Spotify, or recovery.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$R127=[System.Collections.Generic.List[string]]::new()
function R127Add([string]$k,[string]$v){[void]$R127.Add($k+'='+$v)}
function R127Field($obj,[string]$name) {
  if($null -eq $obj){return $null}
  $p=$obj.PSObject.Properties[$name]
  if($null -eq $p){return $null}
  return $p.Value
}
function R127Flag($obj,[string]$name) {
  $v=R127Field $obj $name
  if($v -isnot [bool]){return 'UNKNOWN'}
  return $(if($v){'TRUE'}else{'FALSE'})
}
function R127FileSHA([string]$path){
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function R127ReadJson([string]$path,[long]$max){
  $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if($item.PSIsContainer -or $item.Length -le 0 -or $item.Length -gt $max -or
      ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R127_NONREGULAR_JSON'
  }
  $start=R127FileSHA $path
  $obj=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if((R127FileSHA $path) -cne $start){throw 'R127_JSON_CHANGED_DURING_READ'}
  return $obj
}
function R127IsAllowedPath([string]$path,[string]$canonical,[switch]$Backup) {
  try {
    if([string]::IsNullOrWhiteSpace($path)){return $false}
    $actual=[IO.Path]::GetFullPath($path).TrimEnd('\','/')
    $base=[IO.Path]::GetFullPath($canonical).TrimEnd('\','/')
    if($Backup){
      if(-not $actual.StartsWith($base+'\', [StringComparison]::OrdinalIgnoreCase) -or
         -not $actual.EndsWith('\root-before',[StringComparison]::OrdinalIgnoreCase)){
        return $false
      }
    }else{
      if(-not [string]::Equals($actual,$base,[StringComparison]::OrdinalIgnoreCase)){return $false}
    }
    $node=Get-Item -LiteralPath $actual -Force -ErrorAction Stop
    if(-not $node.PSIsContainer -or
      ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    if($Backup){
      $bk=Get-Item -LiteralPath $base -Force -ErrorAction Stop
      if(-not $bk.PSIsContainer -or
        ($bk.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    }
    return $true
  }catch{return $false}
}
function R127Snapshot([string]$root) {
  # Reproduce the v0.6.30 R112 product's canonical full-root manifest:
  # sorted rows {path,type,size,sha256} -> ConvertTo-Json -Compress ->
  # SHA256 of UTF8 without BOM. Use an iterative walk to reject junctions.
  $ri=Get-Item -LiteralPath $root -Force -ErrorAction Stop
  if(-not $ri.PSIsContainer -or
      ($ri.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R127_SNAPSHOT_ROOT_INVALID'
  }
  $full=$ri.FullName.TrimEnd([char[]]@('\','/'))
  $rows=[System.Collections.Generic.List[object]]::new()
  $todo=[System.Collections.Generic.Stack[string]]::new()
  $todo.Push($full)
  [long]$bytes=0
  while($todo.Count -gt 0){
    $current=$todo.Pop()
    foreach($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)){
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'R127_SNAPSHOT_REPARSE_REFUSED'
      }
      $rel=$item.FullName.Substring($full.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
      if([string]::IsNullOrWhiteSpace($rel)){continue}
      if($rows.Count -ge 10000){throw 'R127_SNAPSHOT_TOO_MANY_OBJECTS'}
      if($item.PSIsContainer){
        [void]$rows.Add([pscustomobject]@{path=$rel;type='dir';size=[long]0;sha256=$null})
        $todo.Push($item.FullName)
      }else{
        $bytes+=[long]$item.Length
        if($bytes -gt 17179869184){throw 'R127_SNAPSHOT_TOO_LARGE'}
        [void]$rows.Add([pscustomobject]@{
          path=$rel;type='file';size=[long]$item.Length;sha256=(R127FileSHA $item.FullName)
        })
      }
    }
  }
  $ordered=@($rows.ToArray() | Sort-Object path,type)
  $json=$ordered | ConvertTo-Json -Depth 5 -Compress
  $enc=[Text.UTF8Encoding]::new($false)
  $hash=[Security.Cryptography.SHA256]::Create()
  try {
    $sha=([BitConverter]::ToString($hash.ComputeHash($enc.GetBytes($json)))).Replace('-','').ToLowerInvariant()
  }finally{$hash.Dispose()}
  return [pscustomobject]@{
    TreeSha256=$sha
    FileCount=@($ordered|Where-Object{$_.type -eq 'file'}).Count
    DirectoryCount=@($ordered|Where-Object{$_.type -eq 'dir'}).Count
  }
}
function R127TreeClass($snapshot,[string]$before,[string]$after) {
  if($null -eq $snapshot){return 'UNVERIFIED'}
  if([string]$snapshot.TreeSha256 -ceq $before){return 'EXACT_BEFORE_ROOT'}
  if([string]$snapshot.TreeSha256 -ceq $after){return 'EXACT_AFTER_ROOT'}
  return 'NEITHER_PINNED_ROOT'
}
function R127ErrorClass($obj) {
  $v=[string](R127Field $obj 'error')
  if([string]::IsNullOrWhiteSpace($v)){return 'NO_ERROR_RECORDED'}
  # Redacted fixed classes only: never print the raw error, path, ID, or log.
  if($v -match '(?i)(restore|rollback|old spicetify).{0,90}apply.{0,60}(fail|error)'){
    return 'ROLLBACK_REAPPLY_FAILURE_HINT'
  }
  if($v -match '(?i)(apply.{0,70}(fail|error)|spicetify.{0,70}apply failed)'){
    return 'NEW_APPLY_FAILURE_HINT'
  }
  if($v -match '(?i)(access.*denied|unauthori[sz]ed|permission denied)'){
    return 'FILE_ACCESS_FAILURE_HINT'
  }
  if($v -match '(?i)(tree|root|payload).{0,70}(mismatch|corrupt|unexpected)'){
    return 'ROOT_INTEGRITY_FAILURE_HINT'
  }
  if($v -match '(?i)(compatib|smart update guard)'){
    return 'COMPATIBILITY_GUARD_FAILURE_HINT'
  }
  if($v -match '(?i)Spotify (is )?(running|started)'){
    return 'SPOTIFY_STARTED_HINT'
  }
  return 'OTHER_ERROR_REDACTED'
}
function R127TxnStatus($obj) {
  if($null -eq $obj){return 'ABSENT'}
  $v=[string](R127Field $obj 'status')
  if($v -cin @('prepared','awaiting-guard','committed','rolled-back',
      'rollback-root-restored-apply-failed','rollback-binary-restored-apply-failed')){
    return $v
  }
  return 'OTHER_OR_MISSING'
}
function R127Proof($txn,$state,$report,$live,$backup,[string]$before,[string]$after){
  $t=R127TxnStatus $txn
  if($t -ceq 'ABSENT'){return 'NO_LEDGER'}
  if($t -ceq 'committed'){return 'COMMITTED_LEDGER_REVIEW_REQUIRED'}
  if($null -eq $live -or $null -eq $backup){return 'TREE_PROOF_INCOMPLETE'}
  if([string]$backup.TreeSha256 -cne $before){return 'BACKUP_NOT_PINNED_BEFORE'}
  if([string]$live.TreeSha256 -cne $before){return 'LIVE_ROOT_NOT_EXACT_BEFORE'}
  $id=[string](R127Field $txn 'id')
  $stateId=[string](R127Field $state 'spicetify_last_transaction_id')
  if([string]::IsNullOrWhiteSpace($id) -or $id -cne $stateId){
    return 'LEDGER_AND_STATE_DIFFERENT_TRANSACTION'
  }
  if($t -ceq 'rolled-back'){return 'ROOT_ROLLED_BACK_LEDGER_REPORTED'}
  if($t -ceq 'awaiting-guard'){
    return 'ROOT_BEFORE_AND_BACKUP_EXACT_LEDGER_UNSETTLED'
  }
  return 'ROOT_BEFORE_BUT_TRANSACTION_UNSETTLED'
}
R127Add 'DIAGNOSTIC' 'SPOTIFY_R127_EXACT_ROOT_AND_LEDGER_READONLY'
R127Add 'NETWORK_DOWNLOAD' 'NO'
R127Add 'FILE_PROCESS_TASK_OR_STATE_WRITE' 'NO'
R127Add 'EXE_OR_REPAIR_INVOKED' 'NO'
R127Add 'AUTO_RETRY' 'NO'
$root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
$defaultSpice=Join-Path $env:LOCALAPPDATA 'spicetify'
$backupsBase=Join-Path $root 'backups\spicetify-transactions'
$txn=$null;$state=$null;$report=$null
$live=$null;$backup=$null
$phase='READONLY_LEDGER'
try {
  $txn=R127ReadJson (Join-Path $root 'spicetify-last-transaction.json') 2097152
  $state=R127ReadJson (Join-Path $root 'state.json') 2097152
  $reportPath=Join-Path $root 'reports\spicetify-transaction-latest.json'
  try{$report=R127ReadJson $reportPath 2097152}catch{}
  R127Add 'LEDGER' 'STABLE_PARSED'
  R127Add 'LEDGER_STATUS' (R127TxnStatus $txn)
  R127Add 'REPORT_STATUS' (R127TxnStatus $report)
  $id=[string](R127Field $txn 'id')
  $sid=[string](R127Field $state 'spicetify_last_transaction_id')
  $rid=[string](R127Field $report 'id')
  R127Add 'LEDGER_STATE_ID' $(if([string]::IsNullOrWhiteSpace($id) -or
     [string]::IsNullOrWhiteSpace($sid)){'MISSING'}elseif($id -ceq $sid){'SAME'}else{'DIFFERENT'})
  R127Add 'LEDGER_REPORT_ID' $(if($null -eq $report){'REPORT_ABSENT'}elseif(
     [string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($rid)){'MISSING'}elseif(
     $id -ceq $rid){'SAME'}else{'DIFFERENT'})
  $saved=[string](R127Field $state 'spicetify_last_transaction_status')
  R127Add 'STATE_STATUS' $(if($saved -cin @('committed','rolled-back',
     'rolled-back-apply-failure','rolled-back-post-swap-verification-failure',
     'rolled-back-post-apply-guard-failure',
     'rolled-back-spotify-started-before-apply')){$saved}else{'OTHER_OR_MISSING'})
  R127Add 'APPLY_ATTEMPTED' (R127Flag $txn 'apply_attempted')
  R127Add 'APPLY_SUCCEEDED' (R127Flag $txn 'apply_succeeded')
  R127Add 'ROLLBACK_REAPPLY_SUCCEEDED' (R127Flag $txn 'rollback_reapply_succeeded')
  R127Add 'LEDGER_ERROR_PRESENT' $(if([string]::IsNullOrWhiteSpace(
    [string](R127Field $txn 'error'))){'NO'}else{'YES'})
  R127Add 'LEDGER_ERROR_CLASS' (R127ErrorClass $txn)
  R127Add 'ROLLBACK_REAPPLY_TIME_PRESENT' $(if([string]::IsNullOrWhiteSpace(
    [string](R127Field $txn 'rollback_reapply_at'))){'NO'}else{'YES'})
  R127Add 'LEDGER_REPORT_STATUS_MATCH' $(if($null -eq $report){'REPORT_ABSENT'}elseif(
    (R127TxnStatus $txn) -ceq (R127TxnStatus $report)){'SAME'}else{'DIFFERENT'})
  $before=[string](R127Field $txn 'before_tree_sha256')
  $after=[string](R127Field $txn 'after_tree_sha256')
  if($before -cnotmatch '^[a-f0-9]{64}$' -or $after -cnotmatch '^[a-f0-9]{64}$'){
    throw 'R127_TREE_PINS_MISSING_OR_INVALID'
  }
  $phase='VALIDATE_PINNED_ROOTS'
  $target=[string](R127Field $txn 'target_root')
  $backupPath=[string](R127Field $txn 'backup_root')
  if(-not (R127IsAllowedPath $target $defaultSpice)){
    R127Add 'LIVE_ROOT_PATH' 'UNVERIFIED_OR_ABSENT'
    throw 'R127_LIVE_ROOT_NOT_TRUSTED'
  }
  if(-not (R127IsAllowedPath $backupPath $backupsBase -Backup)){
    R127Add 'BACKUP_ROOT_PATH' 'UNVERIFIED_OR_ABSENT'
    throw 'R127_BACKUP_ROOT_NOT_TRUSTED'
  }
  R127Add 'LIVE_ROOT_PATH' 'EXACT_MANAGED'
  R127Add 'BACKUP_ROOT_PATH' 'UNDER_OWNER_BACKUPS'
  $phase='HASH_FULL_ROOTS_READONLY'
  $live=R127Snapshot $target
  $backup=R127Snapshot $backupPath
  R127Add 'LIVE_ROOT_TREE' (R127TreeClass $live $before $after)
  R127Add 'BACKUP_ROOT_TREE' (R127TreeClass $backup $before $after)
  R127Add 'LIVE_VS_BACKUP_TREE' $(if($live.TreeSha256 -ceq $backup.TreeSha256){'EXACT'}else{'DIFFERENT'})
  R127Add 'LIVE_FILE_COUNT' ([string]$live.FileCount)
  R127Add 'BACKUP_FILE_COUNT' ([string]$backup.FileCount)
  R127Add 'RECOVERY_CLASS' (R127Proof $txn $state $report $live $backup $before $after)
  R127Add 'RESULT' 'READONLY_FULL_ROOT_AND_LEDGER_CLASSIFIED'
}catch{
  $msg=[string]$_.Exception.Message
  $known=@('R127_TREE_PINS_MISSING_OR_INVALID','R127_LIVE_ROOT_NOT_TRUSTED',
    'R127_BACKUP_ROOT_NOT_TRUSTED','R127_SNAPSHOT_REPARSE_REFUSED',
    'R127_SNAPSHOT_TOO_MANY_OBJECTS','R127_SNAPSHOT_TOO_LARGE')
  R127Add 'HOLD_REASON' $(if($msg -cin $known){$msg}else{'R127_UNVERIFIED_READ_OR_SNAPSHOT'})
  R127Add 'FAILED_PHASE' $phase
  R127Add 'RESULT' 'HOLD_READONLY_NO_AUTO_RETRY'
}finally{
  R127Add 'OPERATING_FILES_CHANGED' 'NO_BY_THIS_PROBE'
  $out=$R127 -join [Environment]::NewLine
  try{Set-Clipboard -Value $out -ErrorAction Stop}catch{}
  Write-Output $out
}
