# R19 post-failed-official-update forensic: exact PREPARED transaction and fixed-category error separation. READ ONLY.
# No Bootstrap, repair, move, rename, cleanup, network or private path export.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# Only fixed script-authored labels leave this process. The genuine
# Bootstrap v1.0.6 reports unredacted private paths in .error; never echo.
function ErrorClass([string]$errorText) {
  if([string]::IsNullOrWhiteSpace($errorText)){return 'ABSENT'}
  if($errorText.Length -gt 131072){return 'OVERSIZED_REDACTED'}
  # Windows PowerShell reports the underlying filesystem failure in the
  # current UI language. The first R19 only recognized English "move.+cannot";
  # the actual failure may be "Cannot move item ... in use" or Korean text.
  # Regex Unicode escapes keep this helper ASCII on Windows PowerShell 5.1.
  $move=($errorText -match '(?i)cannot\s+move\s+item|cannot\s+(rename|move)\b|move[\-\s]?item|failed\s+to\s+move|move\s+failed|\uC774\uB3D9')
  $busy=($errorText -match '(?i)\bin\s+use\b|in\s+use\.\s*$|used\s+by\s+another\s+process|being\s+used|sharing\s+violation|\uC0AC\uC6A9.{0,12}\uC911|\uB2E4\uB978.{0,15}\uD504\uB85C\uC138\uC2A4')
  $denied=($errorText -match '(?i)access.{0,20}denied|permission.{0,20}denied|unauthorized|not\s+permitted|\uC561\uC138\uC2A4.{0,12}\uAC70\uBD80|\uAD8C\uD55C.{0,12}(\uC5C6|\uBD80\uC871)')
  $exists=($errorText -match '(?i)already\s+exists|cannot\s+create\s+a\s+file\s+when\s+that\s+file|\uC774\uBBF8.{0,16}\uC874\uC7AC')
  $missing=($errorText -match '(?i)cannot\s+find\s+(the\s+)?path|could\s+not\s+find\s+a\s+part\s+of\s+the\s+path|not\s+found|\uACBD\uB85C.{0,24}\uCC3E\uC744.{0,12}\uC5C6')
  if($move -and $busy){return 'MOVE_ITEM_IN_USE_OR_SHARING'}
  if($move -and $denied){return 'MOVE_ITEM_ACCESS_DENIED'}
  if($move -and $exists){return 'MOVE_ITEM_DESTINATION_EXISTS'}
  if($move -and $missing){return 'MOVE_ITEM_PATH_NOT_FOUND'}
  if($move){return 'MOVE_ITEM_OTHER_FAILURE'}
  if($busy){return 'FILE_IN_USE_OR_SHARING'}
  if($denied){return 'ACCESS_DENIED_OR_PERMISSION'}
  if($exists){return 'DESTINATION_ALREADY_EXISTS'}
  if($missing){return 'FILE_OR_PATH_NOT_FOUND'}
  if($errorText -match '(?i)Candidate main SelfTest failed'){return 'CANDIDATE_MAIN_SELFTEST'}
  if($errorText -match '(?i)Candidate Addon Manager SelfTest failed'){return 'CANDIDATE_ADDON_SELFTEST'}
  if($errorText -match '(?i)rollback backup is missing'){return 'ROLLBACK_BACKUP_MISSING'}
  if($errorText -match '(?i)rollback backup failed exact.tree verification'){return 'ROLLBACK_BACKUP_TREE_MISMATCH'}
  if($errorText -match '(?i)rollback live tree mismatch after restore'){return 'ROLLBACK_LIVE_TREE_MISMATCH'}
  if($errorText -match '(?i)Persistent self.update backup changed before swap'){return 'PRE_SWAP_BACKUP_CHANGED'}
  if($errorText -match '(?i)Live bin changed before self.update swap|Live bin changed during self.update staging'){return 'LIVE_BIN_CHANGED_PRE_SWAP'}
  if($errorText -match '(?i)Old same.volume bin root changed after swap'){return 'OLD_BIN_CHANGED_POST_SWAP'}
  if($errorText -match '(?i)New live bin tree mismatch after swap'){return 'LIVE_BIN_CHANGED_POST_SWAP'}
  if($errorText -match '(?i)candidate.+(patch|payload)|patch.+(mismatch|missing|fail)|latest managed.+(payload|manifest)'){return 'PATCH_OR_MANIFEST_CONTRACT'}
  if($errorText -match '(?i)source.+(sha|hash|pin)|tree.+(sha|hash|mismatch|verification)|exact.tree'){return 'SOURCE_OR_TREE_CONFLICT'}
  if($errorText -match '(?i)access.+denied|unauthorized|sharing.violation|used.by.another.process|process.cannot.access|locked|file.+in.use|permission'){return 'FILE_SHARING_OR_ACCESS'}
  if($errorText -match '(?i)cannot.create.a.file.when.that.file.already.exists|already.exists|destination.path|directory.not.empty'){return 'DESTINATION_CONFLICT'}
  if($errorText -match '(?i)Move.Item|Copy.Item|move.+(fail|cannot)|copy.+(fail|cannot)|directory.+not.found|cannot.find.path'){return 'FILESYSTEM_MOVE_OR_COPY'}
  if($errorText -match '(?i)network|tls|http|dns|remote.server|timed.out|connect|download|webexception|proxy'){return 'NETWORK_OR_REMOTE'}
  if($errorText -match '(?i)Parser rejected|PowerShell parser|syntax.error'){return 'SCRIPT_PARSER'}
  return 'OTHER_REDACTED'
}
function ErrorLocale([string]$errorText) {
  if([string]::IsNullOrWhiteSpace($errorText)){return 'EMPTY'}
  if($errorText.Length -gt 131072){return 'OVERSIZED'}
  if($errorText -match '[\uAC00-\uD7A3]'){return 'HANGUL_PRESENT'}
  return 'NO_HANGUL'
}
function ReadSafeReport([string]$root,[string]$target) {
  $answer=[pscustomobject]@{status='UNVERIFIED';object=$null}
  try{
    if(-not(ReparseFree $root $target)){return $answer}
    $f=Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $f.Length -lt 2 -or $f.Length -gt 2097152){return $answer}
    $doc=([IO.File]::ReadAllText($target,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop)
    if($null -eq $doc){return $answer}
    return [pscustomobject]@{status='READABLE';object=$doc}
  }catch{return $answer}
}
function PlainDirectory([string]$p) {
  try {
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return ($i.PSIsContainer -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function Field($o,[string]$name) {
  if($null -eq $o){return $null}
  $p=$o.PSObject.Properties[$name]
  if($null -eq $p){return $null}
  return $p.Value
}
function ExactPath([string]$current,[string]$expected) {
  if([string]::IsNullOrWhiteSpace($current)){return $false}
  try {
    return [IO.Path]::GetFullPath($current).TrimEnd('\','/').Equals(
      [IO.Path]::GetFullPath($expected).TrimEnd('\','/'),
      [StringComparison]::OrdinalIgnoreCase)
  }catch{return $false}
}
function ReparseFree([string]$root,[string]$target) {
  try {
    $r=[IO.Path]::GetFullPath($root).TrimEnd('\','/')
    $p=[IO.Path]::GetFullPath($target)
    if(-not $p.StartsWith(($r+'\'),[StringComparison]::OrdinalIgnoreCase)){return $false}
    if(-not(PlainDirectory $r)){return $false}
    $cursor=$r
    foreach($component in @($p.Substring($r.Length).TrimStart('\','/') -split '[\\/]')){
      if([string]::IsNullOrWhiteSpace($component)){return $false}
      $cursor=Join-Path $cursor $component
      if(Test-Path -LiteralPath $cursor) {
        $i=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
      }
    }
    return $true
  }catch{return $false}
}
function SHA([byte[]]$bytes) {
  $h=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($h.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function ClassifyTree([string]$path,[string]$before,[string]$after) {
  # Only reads paths supplied by the exact, locally verified transaction id.
  try {
    $i=$null
    try{$i=Get-Item -LiteralPath $path -Force -ErrorAction Stop}
    catch [System.Management.Automation.ItemNotFoundException] {return 'ABSENT'}
    catch{return 'UNVERIFIED_ACCESS_OR_PRESENCE'}
    if($null -eq $i){return 'UNVERIFIED_ACCESS_OR_PRESENCE'}
    if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return 'UNSAFE_REPARSE'}
    if(-not $i.PSIsContainer){return 'FILE_NOT_DIRECTORY_PRESERVE'}
    $root=[IO.Path]::GetFullPath($path).TrimEnd('\','/')
    $rows=New-Object 'System.Collections.Generic.List[string]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    [int64]$total=0;[int]$fileCount=0;[int]$dirCount=0
    foreach($item in @(Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction Stop)) {
      if($rows.Count -ge 10000){return 'UNVERIFIED_TOO_MANY_ENTRIES'}
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return 'UNSAFE_NESTED_REPARSE'}
      $full=[IO.Path]::GetFullPath($item.FullName)
      if(-not $full.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)){return 'UNSAFE_PATH_ESCAPE'}
      $rel=$full.Substring($root.Length).TrimStart('\','/').Replace('\','/').ToLowerInvariant()
      if([string]::IsNullOrWhiteSpace($rel) -or -not $seen.Add($rel)){return 'UNSAFE_COLLISION'}
      if($item.PSIsContainer){
        $dirCount++
        $rows.Add('D|'+$rel)
      }else{
        $fileCount++
        [int64]$size=$item.Length
        $total+=$size
        if($size -lt 0 -or $total -gt 4294967296){return 'UNVERIFIED_BYTES_LIMIT'}
        $digest=(Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $again=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if($again.PSIsContainer -or
           ($again.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           [int64]$again.Length -ne $size){return 'UNVERIFIED_RACE_OR_TYPE'}
        $rows.Add(('F|{0}|{1}|{2}' -f $rel,$size,$digest))
      }
    }
    if($rows.Count -eq 0){return 'EMPTY_PLAIN_DIRECTORY_PRESERVE'}
    [string[]]$sorted=$rows.ToArray()
    [Array]::Sort($sorted,[StringComparer]::Ordinal)
    $actual=SHA ([Text.Encoding]::UTF8.GetBytes(([string]::Join([string][char]10,$sorted)+[char]10)))
    if($actual -ceq $before){return 'EXACT_TRANSACTION_BEFORE_TREE'}
    if($actual -ceq $after){return 'EXACT_TRANSACTION_AFTER_TREE'}
    if($fileCount -eq 0){return 'NONEMPTY_DIRECTORIES_ONLY_DIFFERENT_PRESERVE'}
    return 'NONEMPTY_UNMATCHED_TREE_PRESERVE'
  }catch{return 'UNVERIFIED_ENUMERATION_OR_IO'}
}
$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('DIAGNOSTIC=SPOTIFY_R19_OFFICIAL_UPDATE_FAILURE_READONLY')
$lines.Add('NETWORK=NO;BOOTSTRAP=NO;UPDATE=NO;MOVE=NO;DELETE=NO')
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_ONLY'}
  if(-not [string]::IsNullOrWhiteSpace($HostedFixtureRoot)){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_OVERRIDE_NOT_AUTHORIZED'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
    if(-not $fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'HOSTED_OVERRIDE_OUTSIDE_RUNNER'
    }
    $root=Join-Path $fixture 'LocalAppData\SpotifyControl'
  }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){throw 'LOCALAPPDATA_MISSING'}
    $root=Join-Path $local 'SpotifyControl'
  }
  if(-not(PlainDirectory $root)){throw 'ROOT_UNVERIFIED'}
  $txnPath=Join-Path $root 'self-update-last-transaction.json'
  if(-not(ReparseFree $root $txnPath)){throw 'TRANSACTION_PATH_UNSAFE'}
  $i=Get-Item -LiteralPath $txnPath -Force -ErrorAction Stop
  if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
     [int64]$i.Length -lt 2 -or [int64]$i.Length -gt 1048576){throw 'TRANSACTION_FILE_UNVERIFIED'}
  [byte[]]$raw=[IO.File]::ReadAllBytes($txnPath)
  $pin=SHA $raw
  # Mirrors original R4 File.ReadAllText BOM recognition without altering bytes.
  $doc=[IO.File]::ReadAllText($txnPath,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
  $id=Field $doc 'id'
  if($id -isnot [string] -or $id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){
    throw 'TRANSACTION_ID_INVALID'
  }
  $status=[string](Field $doc 'status')
  if($status -cne 'prepared'){throw 'TRANSACTION_NOT_PREPARED'}
  if([string](Field $doc 'before_version') -cne '0.6.20' -or
     [string](Field $doc 'after_version') -cne '0.6.28' -or
     [string](Field $doc 'source_commit') -cne 'bb6d90146f20b73d36fbf8cb813f1b190f403c48' -or
     [string](Field $doc 'payload_set_sha256') -cne '4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'){
    throw 'TRANSACTION_OFFICIAL_LINEAGE_UNVERIFIED'
  }
  $before=[string](Field $doc 'before_tree_sha256')
  $after=[string](Field $doc 'after_tree_sha256')
  if($before -cnotmatch '^[a-f0-9]{64}$' -or $after -cnotmatch '^[a-f0-9]{64}$' -or
     $before -ceq $after){throw 'TRANSACTION_TREE_PINS_INVALID'}
  $backup=Join-Path $root ('backups\self-update-transactions\'+$id+'\bin')
  $new=Join-Path $root ('bin.spotifycontrol-new-'+$id)
  $old=Join-Path $root ('bin.spotifycontrol-old-'+$id)
  $restore=Join-Path $root ('bin.spotifycontrol-restore-'+$id)
  $failed=Join-Path $root ('bin.spotifycontrol-failed-'+$id)
  if(-not (ExactPath ([string](Field $doc 'backup_bin')) $backup) -or
     -not (ExactPath ([string](Field $doc 'same_dir_new')) $new) -or
     -not (ExactPath ([string](Field $doc 'same_dir_old')) $old)){
    throw 'TRANSACTION_PATHS_NOT_PINNED'
  }
  $lines.Add('TRANSACTION_STATUS=PREPARED;LINEAGE=EXACT')
  $txnError=Field $doc 'error'
  if($txnError -is [string]){
    $lines.Add('TRANSACTION_ERROR_CLASS='+(ErrorClass $txnError))
    $lines.Add('TRANSACTION_ERROR_LOCALE='+(ErrorLocale $txnError))
  }else{
    $lines.Add('TRANSACTION_ERROR_CLASS=UNVERIFIED')
  }
  $report=ReadSafeReport $root (Join-Path $root 'reports\self-update-latest.json')
  $lines.Add('OFFICIAL_REPORT='+$report.status)
  if($report.status -ceq 'READABLE'){
    $rep=$report.object
    $action=[string](Field $rep 'action')
    $lines.Add('REPORT_ACTION='+$(if($action -ceq 'Update'){'UPDATE'}else{'OTHER_OR_UNKNOWN'}))
    $success=Field $rep 'success'
    $lines.Add('REPORT_SUCCESS='+$(if($success -eq $true){'TRUE'}elseif($success -eq $false){'FALSE'}else{'UNKNOWN'}))
    $repStatus=[string](Field $rep 'transaction_status')
    $lines.Add('REPORT_TRANSACTION_STATUS='+$(if($repStatus -ceq 'prepared'){'PREPARED'}elseif($repStatus -ceq 'rolled-back'){'ROLLED_BACK'}elseif($repStatus -ceq 'committed'){'COMMITTED'}else{'OTHER_OR_UNKNOWN'}))
    $repId=Field $rep 'transaction_id'
    $lines.Add('REPORT_TRANSACTION_MATCH='+$(if($repId -is [string] -and $repId -ceq $id){'YES'}else{'NO_OR_UNVERIFIED'}))
    $rawError=Field $rep 'error'
    if($rawError -isnot [string]){
      $lines.Add('REPORT_ERROR_TEMPLATE=UNVERIFIED')
    }elseif($rawError.Length -gt 131072){
      $lines.Add('REPORT_ERROR_TEMPLATE=OVERSIZED_REDACTED')
    }else{
      $prefix='Self-update failed and rollback also failed. update_error='
      $delimiter='; rollback_error='
      $at=$rawError.LastIndexOf($delimiter,[StringComparison]::Ordinal)
      if($rawError.StartsWith($prefix,[StringComparison]::Ordinal) -and
         $at -gt $prefix.Length){
        $updateError=$rawError.Substring($prefix.Length,$at-$prefix.Length)
        $rollbackError=$rawError.Substring($at+$delimiter.Length)
        $lines.Add('REPORT_ERROR_TEMPLATE=UPDATE_AND_ROLLBACK_FAILED')
        $lines.Add('UPDATE_ERROR_CLASS='+(ErrorClass $updateError))
        $lines.Add('ROLLBACK_ERROR_CLASS='+(ErrorClass $rollbackError))
        $lines.Add('UPDATE_ERROR_LOCALE='+(ErrorLocale $updateError))
        $lines.Add('ROLLBACK_ERROR_LOCALE='+(ErrorLocale $rollbackError))
      }else{
        $lines.Add('REPORT_ERROR_TEMPLATE=OTHER_REDACTED')
        $lines.Add('UNSPLIT_REPORT_ERROR_CLASS='+(ErrorClass $rawError))
      }
    }
  }
  $lines.Add('TRANSACTION_BOM='+$(if($raw.Length -ge 3 -and $raw[0] -eq 239 -and
      $raw[1] -eq 187 -and $raw[2] -eq 191){'UTF8_PRESENT'}else{'UTF8_ABSENT_OR_OTHER'}))
  $locations=@(
    [pscustomobject]@{key='LIVE';path=(Join-Path $root 'bin')},
    [pscustomobject]@{key='BACKUP';path=$backup},
    [pscustomobject]@{key='NEW';path=$new},
    [pscustomobject]@{key='OLD';path=$old},
    [pscustomobject]@{key='RESTORE';path=$restore},
    [pscustomobject]@{key='FAILED';path=$failed}
  )
  foreach($loc in $locations){
    $result=if(-not(ReparseFree $root $loc.path)){'UNSAFE_REPARSE_OR_PATH'}
      else{ClassifyTree $loc.path $before $after}
    $lines.Add($loc.key+'='+$result)
  }
  $unchanged=$false
  try{$unchanged=((SHA ([IO.File]::ReadAllBytes($txnPath))) -ceq $pin)}catch{}
  $lines.Add('TRANSACTION_STABLE_DURING_AUDIT='+$(if($unchanged){'YES'}else{'UNVERIFIED'}))
  $lines.Add('RESULT=READONLY_POST_FAILURE_CLASSIFICATION_COMPLETE')
}catch{
  # Report only a finite, script-authored label; never a raw private path.
  $lines.Add('RESULT=HOLD_READONLY_POST_FAILURE_UNVERIFIED')
}
$lines.Add('RAW_PATHS_IDS_CONTENTS_AND_ERRORS_EXPORTED=NO')
if([string]::IsNullOrWhiteSpace($HostedFixtureRoot)){
  try{Set-Clipboard -Value ($lines -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$lines|ForEach-Object {Write-Output $_}
