# R17 exact PREPARED orphan leftover-root inventory. READ ONLY.
# No Bootstrap, repair, move, rename, cleanup, network or private path export.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
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
$lines.Add('DIAGNOSTIC=SPOTIFY_R17_LEFTOVER_ROOTS_READONLY')
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
  $lines.Add('RESULT=READONLY_LEFTOVER_INVENTORY_COMPLETE')
}catch{
  # Report only a finite, script-authored label; never a raw private path.
  $lines.Add('RESULT=HOLD_READONLY_INVENTORY_UNVERIFIED')
}
$lines.Add('RAW_PATHS_IDS_CONTENTS_AND_ERRORS_EXPORTED=NO')
if([string]::IsNullOrWhiteSpace($HostedFixtureRoot)){
  try{Set-Clipboard -Value ($lines -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$lines|ForEach-Object {Write-Output $_}
