# Spotify Control Bootstrap 1.0.6 exact incident triage; no actions invoked.
# READ ONLY: no network, no directories created, no program or task run,
# no config edits, no private paths, raw errors or transaction contents printed.
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Path-IsPlainDirectory([string]$Path) {
  try {
    $it=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return ($it.PSIsContainer -and (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0))
  }catch{return $false}
}
function Read-PrivateJson {
  param([string]$Path)
  $unknown=[pscustomobject]@{state='MISSING_OR_UNSAFE';object=$null;age='UNKNOWN'}
  try {
    $entry=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       [int64]$entry.Length -lt 2 -or [int64]$entry.Length -gt 4194304){return $unknown}
    $hours=([datetime]::UtcNow-$entry.LastWriteTimeUtc).TotalHours
    $age=if($hours -lt -1){'FUTURE_OR_CLOCK_DRIFT'}elseif($hours -lt 24){'LT24H'}elseif($hours -lt 168){'D1_TO_D7'}elseif($hours -lt 720){'D8_TO_D30'}else{'OLDER_THAN_D30'}
    $obj=([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
    if($null -eq $obj -or $obj -isnot [psobject]){return [pscustomobject]@{state='INVALID_JSON';object=$null;age=$age}}
    return [pscustomobject]@{state='READABLE';object=$obj;age=$age}
  }catch{return $unknown}
}
function Typed-Bool($Obj,[string]$Key){
  if($null -eq $Obj){return 'UNKNOWN'}
  $prop=$Obj.PSObject.Properties[$Key]
  if($null -eq $prop -or $prop.Value -isnot [bool]){return 'UNKNOWN'}
  if([bool]$prop.Value){return 'TRUE'}
  return 'FALSE'
}
function Safe-Status($Obj,[string]$Key){
  if($null -eq $Obj){return 'UNKNOWN'}
  $prop=$Obj.PSObject.Properties[$Key]
  if($null -eq $prop -or $prop.Value -isnot [string]){return 'UNKNOWN'}
  $status=$prop.Value.ToLowerInvariant()
  $known=@('prepared','swapped','post-verified','committed','rolled-back','failed',
           'rolling-back','rollback-failed','pending','never','blocked','unknown',
           'already-current','success','error')
  if($status -cin $known){return $status.ToUpperInvariant().Replace('-','_')}
  return 'OTHER_REDACTED'
}
function Error-Category($Obj){
  if($null -eq $Obj){return 'UNKNOWN'}
  $p=$Obj.PSObject.Properties['error']
  if($null -eq $p -or $null -eq $p.Value){return 'NO_RECORDED_ERROR'}
  if($p.Value -isnot [string]){return 'UNSTRUCTURED_REDACTED'}
  $s=$p.Value
  if($s.Length -gt 32000){$s=$s.Substring(0,32000)}
  if($s.Trim().Length -eq 0){return 'NO_RECORDED_ERROR'}
  if($s -match '(?i)rollback also failed|rollback backup.*(missing|failed)|rollback live tree|exact-tree verification failed'){return 'ROLLBACK_OR_BACKUP_FAILURE'}
  if($s -match '(?i)incomplete self-update|recovering incomplete|transaction.+(prepared|swapped|post-verified)'){return 'INCOMPLETE_TRANSACTION'}
  if($s -match '(?i)candidate main selftest|candidate addon manager selftest|candidate.*self.?test'){return 'CANDIDATE_SELFTEST'}
  if($s -match '(?i)access.+denied|unauthorizedaccess|used by another process|sharing violation|cannot access the file|permission|file.+lock|mutex|directory is not empty'){return 'FILE_LOCK_OR_ACCESS'}
  if($s -match '(?i)installed main sha|trusted edge source|changed during self-update|live bin changed|sha256 does not match'){return 'SOURCE_DRIFT'}
  if($s -match '(?i)no unique trusted|edge chain|staged main version mismatch|edge is not strictly'){return 'UPDATE_EDGE_CONTRACT'}
  if($s -match '(?i)manifest.+(pin|schema|channel|version|invalid|missing|does not match)|bootstrap.*(pin|older)|source_repository|payload_set_sha256'){return 'MANIFEST_TRUST_CONTRACT'}
  if($s -match '(?i)chunk mismatch|decoded.+mismatch|encoded.+mismatch|gzip mismatch|decompress|invalid base64|patch document|compressed_size|patch.+digest|hash mismatch'){return 'PATCH_INTEGRITY'}
  if($s -match '(?i)webexception|name resolution|dns|tls|ssl|timed out|timeout|remote server|unable to connect|429|rate limit|forbidden|http.*(403|404|5[0-9][0-9])|network|proxy'){return 'NETWORK_OR_REMOTE'}
  if($s -match '(?i)spicetify|spotify.*(running|open|locked)'){return 'SPOTIFY_OR_SPICETIFY_STATE'}
  return 'OTHER_REDACTED'
}
function Safe-Action($Obj){
  if($null -eq $Obj){return 'UNKNOWN'}
  $p=$Obj.PSObject.Properties['action']
  if($null -eq $p -or $p.Value -isnot [string]){return 'UNKNOWN'}
  if($p.Value -cin @('Check','Update','RollbackTest','Rollback','SelfTest','Status')){return $p.Value.ToUpperInvariant()}
  return 'OTHER_REDACTED'
}
function Valid-BackupState($Root,$Txn){
  if($null -eq $Txn){return 'UNKNOWN'}
  $p=$Txn.PSObject.Properties['backup_bin']
  if($null -eq $p -or $p.Value -isnot [string] -or $p.Value.Trim().Length -lt 5){return 'NOT_RECORDED'}
  try{
    $base=[IO.Path]::GetFullPath((Join-Path $Root 'backups\self-update-transactions')).TrimEnd('\','/')
    $path=[IO.Path]::GetFullPath([string]$p.Value)
    if(-not $path.StartsWith(($base+'\'),[StringComparison]::OrdinalIgnoreCase)){
      return 'OUTSIDE_EXPECTED_BACKUP_ROOT'
    }
    if(Path-IsPlainDirectory $path){return 'EXPECTED_BACKUP_DIRECTORY_PRESENT'}
    return 'MISSING_OR_NOT_PLAIN_DIRECTORY'
  }catch{return 'UNKNOWN'}
}
$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('DIAGNOSTIC=SPOTIFY_CONTROL_BOOTSTRAP_INCIDENT_R3')
$lines.Add('READ_ONLY=YES;NO_NETWORK;NO_BOOTSTRAP_RUN;NO_INSTALL;NO_RECOVERY;NO_TASK_EDIT;NO_FILE_WRITE')
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_ONLY'}
  $hosted= -not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
  if($hosted){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_OVERRIDE_FORBIDDEN'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $specified=[IO.Path]::GetFullPath($HostedFixtureRoot)
    if(-not $specified.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'HOSTED_OVERRIDE_OUTSIDE_RUNNER'
    }
    $root=Join-Path $specified 'LocalAppData\SpotifyControl'
  }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){throw 'LOCALAPPDATA_NOT_RESOLVED'}
    $root=Join-Path $local 'SpotifyControl'
  }
  if(-not(Path-IsPlainDirectory $root)){throw 'LOCAL_ROOT_NOT_PLAIN_DIR'}
  $boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
  $bootOk='UNKNOWN'
  try{
    $it=Get-Item -LiteralPath $boot -Force -ErrorAction Stop
    if(-not $it.PSIsContainer -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
       [int64]$it.Length -eq 42963){
      $sha=(Get-FileHash -LiteralPath $boot -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
      if($sha -ceq 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
        $bootOk='EXACT_V106'
      }else{$bootOk='NOT_CANONICAL'}
    }else{$bootOk='NOT_CANONICAL'}
  }catch{$bootOk='MISSING_OR_UNREADABLE'}
  $lines.Add('BOOTSTRAP='+$bootOk)
  $txn=Read-PrivateJson -Path (Join-Path $root 'self-update-last-transaction.json')
  $report=Read-PrivateJson -Path (Join-Path $root 'reports\self-update-latest.json')
  $state=Read-PrivateJson -Path (Join-Path $root 'state.json')
  $lines.Add('BOOTSTRAP_TRANSACTION='+$txn.state+';AGE='+$txn.age)
  $lines.Add('TRANSACTION_STATUS='+ (Safe-Status $txn.object 'status'))
  $lines.Add('TRANSACTION_ERROR_CLASS='+ (Error-Category $txn.object))
  $lines.Add('BACKUP_DIRECTORY='+ (Valid-BackupState $root $txn.object))
  $lines.Add('BOOTSTRAP_REPORT='+$report.state+';AGE='+$report.age)
  $lines.Add('LAST_BOOTSTRAP_ACTION='+ (Safe-Action $report.object))
  $lines.Add('LAST_BOOTSTRAP_SUCCESS='+ (Typed-Bool $report.object 'success'))
  $lines.Add('REPORT_TRANSACTION_STATUS='+ (Safe-Status $report.object 'transaction_status'))
  $lines.Add('LAST_BOOTSTRAP_ERROR_CLASS='+ (Error-Category $report.object))
  $latest='UNKNOWN'
  if($null -ne $report.object -and
     $null -ne $report.object.PSObject.Properties['result'] -and
     $null -ne $report.object.result -and
     $null -ne $report.object.result.PSObject.Properties['edge_count']){
     $edge=$report.object.result.edge_count
     if($edge -is [int] -and [int]$edge -ge 0 -and [int]$edge -le 32){
       $latest=[string]$edge
     }
  }
  $lines.Add('LAST_REPORT_EDGE_COUNT='+$latest)
  $lines.Add('STATE_SELF_UPDATE='+ (Safe-Status $state.object 'self_update_last_transaction_status'))
  $lines.Add('STATE_PENDING_SELF_UPDATE='+ (Typed-Bool $state.object 'pending_self_update'))
  $lines.Add('STATE_MAINTENANCE_HEALTH='+ (Typed-Bool $state.object 'maintenance_check_healthy'))
  $status=Safe-Status $txn.object 'status'
  $pending=$status -cin @('PREPARED','SWAPPED','POST_VERIFIED','ROLLING_BACK','PENDING')
  $lines.Add('POSSIBLE_UNFINISHED_BOOTSTRAP_TRANSACTION='+$(if($pending){'YES_DO_NOT_AUTOREPAIR'}elseif($status -cin @('COMMITTED','ROLLED_BACK')){'NO_TERMINAL_RECORDED'}else{'UNKNOWN'}))
  $lines.Add('RESULT=BOOTSTRAP_INCIDENT_READ_ONLY_CLASSIFIED_NO_MUTATION_AUTHORITY')
}catch{
  $lines.Add('RESULT=HOLD_READONLY_INPUTS_UNVERIFIED')
}
$lines.Add('CHECK_ACTION_NOT_EXECUTED=YES;USER_SOURCE_UNMODIFIED=YES;ORIGINALS_DELETE=NO')
$lines.Add('PRIVATE_PATHS_ERROR_TEXT_TRANSACTION_IDS_EXPORTED=NO')
$hostedOutput= -not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
if(-not $hostedOutput){
  try{Set-Clipboard -Value ($lines -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$lines|ForEach-Object{Write-Output $_}
