# R129 HOLD: lightweight offline cause classification for one unresolved
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
function KnownApplyWords([string]$text){
  if([string]::IsNullOrWhiteSpace($text)){return 'NONE'}
  # Only allowlisted public category labels are emitted, never source words.
  $flags=[System.Collections.Generic.List[string]]::new()
  foreach($name in @('BACKUP','VERSION','MISMATCH','PERMISSION','RESOURCE',
      'CUSTOMIZATION','REQUIRED','NETWORK','FAILURE')){
    $pattern=switch($name){
      'BACKUP'         { '(?i)backup|\.spa' }
      'VERSION'        { '(?i)version|outdated' }
      'MISMATCH'       { '(?i)mismatch|different' }
      'PERMISSION'     { '(?i)access|denied|permission|lock|sharing' }
      'RESOURCE'       { '(?i)resource|xpui|apps|snapshot|asset' }
      'CUSTOMIZATION'  { '(?i)theme|extension|custom[ -]?app|marketplace' }
      'REQUIRED'       { '(?i)required|missing|not found|cannot|unable' }
      'NETWORK'        { '(?i)http|network|connect|proxy|timeout' }
      'FAILURE'        { '(?i)error|failed|failure|panic|fatal|invalid' }
    }
    if($text -match $pattern){[void]$flags.Add($name)}
  }
  if($flags.Count -eq 0){return 'NONE'}
  return $flags -join ','
}
function ClassifyApplyText([string]$message) {
  if([string]::IsNullOrWhiteSpace($message)){return 'NO_ERROR_TEXT'}
  if($message -match '(?i)(access.{0,30}denied|permission denied|unauthori[sz]ed|EACCES|EPERM|file.{0,25}locked|sharing violation)'){
    return 'FILE_ACCESS_OR_LOCK'
  }
  if($message -match '(?i)(backups?|backup\.spa|backup version).{0,100}(missing|mismatch|not found|invalid|corrupt|empty|failed|outdated)' -or
     $message -match '(?i)(missing|invalid|corrupt|mismatch|outdated).{0,100}(backups?|backup\.spa|backup version)'){
    return 'BACKUP_NOT_ACCEPTED'
  }
  if($message -match '(?i)(spotify version mismatch|version mismatch|version outdated|does not match your backup)'){
    return 'BACKUP_OR_SPOTIFY_VERSION_MISMATCH'
  }
  if($message -match '(?i)(spotify.{0,30}(version|unsupported|not supported)|version.{0,30}not supported|compatib)'){
    return 'VERSION_OR_COMPATIBILITY'
  }
  if($message -match '(?i)(xpui|apps?|resource|patch|snapshot).{0,50}(missing|not found|invalid|unavailable|fail|corrupt)'){
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
        throw 'R129_CONFIG_NOT_REGULAR'
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
        throw 'R129_PREFS_NOT_REGULAR'
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
  # The shipped R112 product compares the whole backup/prefs strings,
  # including optional Spotify build hash suffixes. R128 falsely required
  # exactly four numeric components, returning FORMAT_UNVERIFIED for valid
  # Spotify builds such as 1.3.6.1921.gabcdef.
  $pattern='^\d{1,3}\.\d{1,3}\.\d{1,5}\.\d{1,6}(?:\.[A-Za-z0-9-]{1,40})?$'
  if($b.Length -gt 96 -or $p.Length -gt 96 -or
     $b -cnotmatch $pattern -or $p -cnotmatch $pattern){
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
  $detail=$(if($line -match '\[exit=-?\d+\]:?\s+\S'){
    'CAPTURED'
  }else{'NOT_CAPTURED'})
  return [pscustomobject]@{
    Nonzero=$isFailure
    Class=$(if($isFailure){ClassifyApplyText $line}else{'NO_ERROR'})
    Detail=$detail
    KnownWords=$(if($isFailure){KnownApplyWords $line}else{'NONE'})
  }
}
function ReadRecentApplyClasses([string]$dir) {
  $items=@()
  if(Test-Path -LiteralPath $dir -PathType Container) {
    $d=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
    if(($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'R129_LOG_DIR_REPARSE'
    }
    $items=@(Get-ChildItem -LiteralPath $dir -File -Force -Filter 'spotify-control-*.log' -ErrorAction Stop |
       Where-Object {
         $_.Name -match '^spotify-control-\d{4}-\d{2}-\d{2}\.log$' -and
         $_.Length -le 6291456 -and
         ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
       }|Sort-Object Name|Select-Object -Last 3)
  }
  $attempts=0;$nonzero=0;$latest='NOT_SEEN';$lastFailure='NOT_SEEN'
  $lastDetail='NOT_SEEN';$lastKnown='NOT_SEEN'
  $hasOldRollback=$false;$hasRollbackFailed=$false
  foreach($f in $items){
    foreach($line in @(Get-Content -LiteralPath $f.FullName -Tail 600 -ErrorAction Stop)){
      $v=ParseApply $line
      if($null -ne $v){
        $attempts++
        $latest=$(if($v.Nonzero){'EXIT_NONZERO'}else{'EXIT_ZERO'})
        if($v.Nonzero){
          $nonzero++
          $lastFailure=$v.Class
          $lastDetail=$v.Detail
          $lastKnown=$v.KnownWords
        }
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
    ErrorClass=$lastFailure;LastFailureDetail=$lastDetail;LastKnownWords=$lastKnown
    RollbackVerifiedLog=$hasOldRollback;RollbackApplyFailureLog=$hasRollbackFailed
  }
}
AddClass 'DIAGNOSTIC' 'SPOTIFY_R129_CAUSAL_READONLY'
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
  $stateAt=[DateTimeOffset]::MinValue
  $swapAt=[DateTimeOffset]::MinValue
  $stateTime=[string](Field $s 'spicetify_last_transaction_utc')
  $swapTime=[string](Field $t 'swapped_at')
  if([DateTimeOffset]::TryParse($stateTime,[ref]$stateAt) -and
     [DateTimeOffset]::TryParse($swapTime,[ref]$swapAt)){
    $seconds=($stateAt-$swapAt).TotalSeconds
    AddClass 'STATE_TIME_VS_LEDGER_SWAP' $(if($seconds -gt 60){'STATE_NEWER'}elseif(
        $seconds -lt -60){'STATE_OLDER'}else{'WITHIN_ONE_MINUTE'})
  }else{
    AddClass 'STATE_TIME_VS_LEDGER_SWAP' 'NOT_CORRELATABLE'
  }
  $phase='LOCAL_PREFS_AND_BACKUP_METADATA'
  AddClass 'BACKUP_VERSION_RELATION' (ClassifyBackupVersion (Join-Path $env:APPDATA 'spicetify\config-xpui.ini') (Join-Path $env:APPDATA 'Spotify\prefs'))
  $phase='BOUNDED_LOCAL_LOG_READ'
  $log=ReadRecentApplyClasses (Join-Path $root 'logs')
  AddClass 'LOG_FILES_SCANNED' ([string]$log.Files)
  AddClass 'APPLY_LOG_ENTRIES_OBSERVED' ([string]$log.Attempts)
  AddClass 'APPLY_LOG_NONZERO_ENTRIES' ([string]$log.Nonzero)
  AddClass 'LATEST_APPLY_LOG_CLASS' $log.Latest
  AddClass 'LAST_NONZERO_APPLY_ERROR_CLASS' $log.ErrorClass
  AddClass 'LAST_FAILED_APPLY_DETAIL' $log.LastFailureDetail
  AddClass 'LAST_FAILED_APPLY_ALLOWLIST_WORDS' $log.LastKnownWords
  AddClass 'HISTORICAL_ROOT_ROLLBACK_MESSAGE' $(if($log.RollbackVerifiedLog){'PRESENT_UNCORRELATED'}else{'NOT_OBSERVED'})
  AddClass 'HISTORICAL_ROLLBACK_APPLY_FAILURE' $(if($log.RollbackApplyFailureLog){'PRESENT_UNCORRELATED'}else{'NOT_OBSERVED'})
  AddClass 'ROLLBACK_REAPPLY_LOG_COVERAGE' 'NOT_COMPLETE_PRODUCT_INVOKES_NATIVE_CAPTURE'
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
