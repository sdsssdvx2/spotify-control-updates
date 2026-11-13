# R128 HOLD: lightweight offline cause classification for one unresolved
# Spicetify root transaction. Never execute agent/Spicetify/Spotify or repair.
# Read ONLY known owner local report/ledger, recent bounded logs and
# backup-version metadata; do not output raw paths, errors, IDs, tokens.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$report=[System.Collections.Generic.List[string]]::new()
function AddClass([string]$k,[string]$v) {
  [void]$report.Add($k+'='+$v)
}
function Field($obj,[string]$name) {
  if($null -eq $obj){return $null}
  $p=$obj.PSObject.Properties[$name]
  if($null -eq $p){return $null}
  return $p.Value
}
function ReadSafeJson([string]$file) {
  $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
  if($item.PSIsContainer -or $item.Length -gt 2097152 -or $item.Length -le 0 -or
     ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R128_JSON_UNTRUSTED'
  }
  $h1=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
  $obj=Get-Content -LiteralPath $file -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $h1){
    throw 'R128_JSON_CHANGED_DURING_READ'
  }
  return $obj
}
function ClassifyApplyText([string]$message) {
  if([string]::IsNullOrWhiteSpace($message)){return 'NO_ERROR_TEXT'}
  if($message -match '(?i)(access.{0,20}denied|permission denied|unauthori[sz]ed|EACCES|EPERM|file.{0,25}locked|sharing violation)'){
    return 'FILE_ACCESS_OR_LOCK'
  }
  if($message -match '(?i)(backups?|backup\.spa|backup version).{0,55}(missing|mismatch|not found|invalid|corrupt|empty|failed)'){
    return 'BACKUP_NOT_ACCEPTED'
  }
  if($message -match '(?i)(spotify.{0,24}(version|unsupported|not supported)|version.{0,24}not supported|compatib)'){
    return 'VERSION_OR_COMPATIBILITY'
  }
  if($message -match '(?i)(xpui|apps?|resource|patch).{0,35}(missing|not found|invalid|unavailable|fail)'){
    return 'SPOTIFY_RESOURCES_OR_PATCH'
  }
  if($message -match '(?i)(could not find|cannot find|no such file|path does not exist|not found)'){
    return 'FILE_OR_PATH_MISSING'
  }
  if($message -match '(?i)(parse|invalid json|syntax error|malformed|unexpected token)'){
    return 'INPUT_OR_PARSER'
  }
  return 'OTHER_REDACTED_ERROR'
}
function ClassifyBackupVersion([string]$config,[string]$prefs) {
  $b=$null;$p=$null
  try {
    if(Test-Path -LiteralPath $config -PathType Leaf){
      $fi=Get-Item -LiteralPath $config -Force -ErrorAction Stop
      if($fi.Length -gt 1048576 -or
         ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'R128_CONFIG_NOT_REGULAR'
      }
      $inBackup=$false
      foreach($line in @(Get-Content -LiteralPath $config -ErrorAction Stop)){
        if($line -match '^\s*\[(?<section>[^\]]+)\]\s*$'){
          $inBackup=($Matches.section -ceq 'Backup'); continue
        }
        if($inBackup -and $line -match '^\s*version\s*=\s*(?<value>[^;\r\n#]*)'){
          $b=$Matches.value.Trim().Trim('"'); break
        }
      }
    }
  }catch{return 'CONFIG_UNREADABLE'}
  try {
    if(Test-Path -LiteralPath $prefs -PathType Leaf){
      $fi=Get-Item -LiteralPath $prefs -Force -ErrorAction Stop
      if($fi.Length -gt 4194304 -or
         ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'R128_PREFS_NOT_REGULAR'
      }
      foreach($line in @(Get-Content -LiteralPath $prefs -ErrorAction Stop)){
        if($line -match '^\s*app\.last-launched-version\s*=\s*"?(?<value>[^"\r\n]+)"?\s*$'){
          $p=$Matches.value.Trim().Trim('"'); break
        }
      }
    }
  }catch{return 'PREFS_UNREADABLE'}
  if([string]::IsNullOrWhiteSpace($b) -or [string]::IsNullOrWhiteSpace($p)){
    return 'METADATA_INCOMPLETE'
  }
  if($b -cnotmatch '^\d{1,3}(?:\.\d{1,5}){3}$' -or
     $p -cnotmatch '^\d{1,3}(?:\.\d{1,5}){3}$'){
    return 'VERSION_FORMAT_UNVERIFIED'
  }
  if($b -ceq $p){return 'BACKUP_AND_PREFS_VERSION_MATCH'}
  return 'BACKUP_AND_PREFS_VERSION_DIFFER'
}
function ParseApply([string]$line) {
  if($line -notmatch '(?i)spicetify\s+apply\s+--no-restart\s+\[exit=(?<code>-?\d+)\]'){
    return $null
  }
  $exitNum=0
  if(-not [int]::TryParse([string]$Matches.code,[ref]$exitNum)){
    return $null
  }
  $isFailure=$exitNum -ne 0
  return [pscustomobject]@{
    Nonzero=$isFailure
    Class=$(if($isFailure){ClassifyApplyText $line}else{'NO_ERROR'})
  }
}
function ReadRecentApplyClasses([string]$dir) {
  $items=@()
  if(Test-Path -LiteralPath $dir -PathType Container) {
    $d=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
    if(($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'R128_LOG_DIR_REPARSE'
    }
    $items=@(Get-ChildItem -LiteralPath $dir -File -Force -Filter 'spotify-control-*.log' -ErrorAction Stop |
       Where-Object {
         $_.Name -match '^spotify-control-\d{4}-\d{2}-\d{2}\.log$' -and
         $_.Length -le 6291456 -and
         ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
       }|Sort-Object Name -Descending|Select-Object -First 3)
  }
  $attempts=0;$nonzero=0;$latest='NOT_SEEN';$latestFailure='NOT_SEEN'
  $hasOldRollback=$false;$hasRollbackFailed=$false
  foreach($f in $items){
    foreach($line in @(Get-Content -LiteralPath $f.FullName -Tail 600 -ErrorAction Stop)){
      $v=ParseApply $line
      if($null -ne $v){
        $attempts++
        if($latest -ceq 'NOT_SEEN'){
          # Log list is descending by DATE but lines within each file ascend.
          $latest='SEEN'
        }
        $latest=$(if($v.Nonzero){'EXIT_NONZERO'}else{'EXIT_ZERO'})
        if($v.Nonzero){$nonzero++;$latestFailure=$v.Class}
      }
      if($line -match '(?i)Rolled back and verified full Spicetify root transaction'){
        $hasOldRollback=$true
      }
      if($line -match '(?i)(rollback.{0,40}apply failed|restore apply failed)'){
        $hasRollbackFailed=$true
      }
    }
  }
  return [pscustomobject]@{
    Files=$items.Count;Attempts=$attempts;Nonzero=$nonzero;Latest=$latest
    ErrorClass=$latestFailure;RollbackVerifiedLog=$hasOldRollback
    RollbackApplyFailureLog=$hasRollbackFailed
  }
}
AddClass 'DIAGNOSTIC' 'SPOTIFY_R128_APPLY_CAUSE_READONLY'
AddClass 'NETWORK_DOWNLOAD' 'NO'
AddClass 'FILES_SETTINGS_PROCESSES_WRITTEN' 'NO'
AddClass 'SPOTIFY_OR_SPICETIFY_INVOKED' 'NO'
AddClass 'AUTO_RETRY' 'NO'
$phase='PREFLIGHT'
try{
  $root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $t=ReadSafeJson (Join-Path $root 'spicetify-last-transaction.json')
  $s=ReadSafeJson (Join-Path $root 'state.json')
  $rep=$null
  try{$rep=ReadSafeJson (Join-Path $root 'reports\spicetify-transaction-latest.json')}catch{}
  $tId=[string](Field $t 'id');$sId=[string](Field $s 'spicetify_last_transaction_id')
  AddClass 'TRANSACTION_ID_RELATION' $(if($tId -and $sId -and $tId -ceq $sId){'MATCH'}elseif(
    $tId -and $sId){'DIFFERENT'}else{'UNVERIFIED'})
  $stateStatus=[string](Field $s 'spicetify_last_transaction_status')
  $ledgerStatus=[string](Field $t 'status')
  AddClass 'STATE_ROLLBACK_APPLY_FAILURE' $(if($stateStatus -ceq 'rolled-back-apply-failure'){'YES'}else{'OTHER'})
  AddClass 'LEDGER_AWAITING_GUARD' $(if($ledgerStatus -ceq 'awaiting-guard'){'YES'}else{'OTHER'})
  $tid=[string](Field $rep 'id')
  AddClass 'REPORT_LEDGER_ID' $(if(-not $rep){'REPORT_ABSENT'}elseif($tId -and $tid -ceq $tId){'MATCH'}else{'DIFFERENT_OR_UNVERIFIED'})
  $phase='LOCAL_PREFS_AND_BACKUP_METADATA'
  AddClass 'BACKUP_VERSION_RELATION' (ClassifyBackupVersion (Join-Path $env:APPDATA 'spicetify\config-xpui.ini') (Join-Path $env:APPDATA 'Spotify\prefs'))
  $phase='BOUNDED_LOCAL_LOG_READ'
  $log=ReadRecentApplyClasses (Join-Path $root 'logs')
  AddClass 'LOG_FILES_SCANNED' ([string]$log.Files)
  AddClass 'APPLY_LOG_ENTRIES_OBSERVED' ([string]$log.Attempts)
  AddClass 'APPLY_LOG_NONZERO_ENTRIES' ([string]$log.Nonzero)
  AddClass 'LATEST_APPLY_LOG_CLASS' $log.Latest
  AddClass 'LAST_NONZERO_APPLY_ERROR_CLASS' $log.ErrorClass
  AddClass 'HISTORICAL_ROOT_ROLLBACK_MESSAGE' $(if($log.RollbackVerifiedLog){'PRESENT_UNCORRELATED'}else{'NOT_OBSERVED'})
  AddClass 'HISTORICAL_ROLLBACK_APPLY_FAILURE' $(if($log.RollbackApplyFailureLog){'PRESENT_UNCORRELATED'}else{'NOT_OBSERVED'})
  AddClass 'RESULT' 'READONLY_APPLY_CAUSE_CLASSIFIED_NO_RECOVERY'
}catch{
  AddClass 'FAILED_PHASE' $phase
  AddClass 'RESULT' 'HOLD_READONLY_CAUSE_NOT_ESTABLISHED'
}finally{
  AddClass 'OPERATING_SPICETIFY_UNCHANGED_BY_THIS_TOOL' 'YES'
  $out=$report -join [Environment]::NewLine
  try{Set-Clipboard -Value $out -ErrorAction Stop}catch{}
  Write-Output $out
}
