# Bootstrap v1.0.6 PREPARED incident forensic: READ ONLY.
# Never execute existing Bootstrap Check (it auto-recovers pending transactions).
# No file changes, network access, process execution, task edits, or raw paths/errors.
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function PlainDir([string]$p) {
  try{$i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      return ($i.PSIsContainer -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)}
  catch{return $false}
}
function ReadJson([string]$p) {
  try{
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $i.Length -lt 2 -or $i.Length -gt 4194304){return $null}
    return ([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop)
  }catch{return $null}
}
function Field($obj,[string]$key) {
  if($null -eq $obj){return $null}
  $p=$obj.PSObject.Properties[$key]
  if($null -eq $p){return $null}
  return $p.Value
}
function SafeErrorCategory($obj) {
  $s=Field $obj 'error'
  if($s -isnot [string]){return 'ABSENT_OR_UNSTRUCTURED'}
  if([string]::IsNullOrWhiteSpace($s)){return 'NO_ERROR'}
  if($s.Length -gt 32768){$s=$s.Substring(0,32768)}
  if($s -match '(?i)rollback also failed|rollback backup.*(missing|failed)|rollback.*tree.*mismatch'){return 'ROLLBACK_FAILURE'}
  if($s -match '(?i)access.*denied|unauthorized|sharing.violation|used.by.another.process|process.cannot.access|mutex|file.*lock|permission.denied'){return 'LOCK_OR_ACCESS'}
  if($s -match '(?i)already.exists|cannot.create.a.file.when.that.file.already.exists|destination.path'){return 'MOVE_DESTINATION_EXISTS'}
  if($s -match '(?i)cannot.find.path|path.*does.not.exist|cannot.find.a.part.of.the.path|itemnotfound|directorynotfound'){return 'MISSING_PATH'}
  if($s -match '(?i)SelfTest|self.test|parser.rejected'){return 'CANDIDATE_SELFTEST'}
  if($s -match '(?i)exact.tree|live.bin.changed|backup.changed|source.sha|hash.mismatch'){return 'SOURCE_OR_TREE_CONFLICT'}
  if($s -match '(?i)webexception|dns|tls|timed.out|remote.server|unable.to.connect|429|proxy|network|http.*(403|404|500|502|503)'){return 'NETWORK_OR_REMOTE'}
  if($s -match '(?i)patch|payload|manifest|commit|trust.pin|gzip|base64|chunk'){return 'PACKAGE_OR_TRUST'}
  if($s -match '(?i)cannot.bind|parameter|cannot.convert|method.invocation'){return 'PS_INVOCATION'}
  return 'OTHER_REDACTED'
}
function ExactPath([string]$actual,[string]$expected) {
  if([string]::IsNullOrWhiteSpace($actual)){return $false}
  try{return ([IO.Path]::GetFullPath($actual).TrimEnd('\','/')).Equals(
        [IO.Path]::GetFullPath($expected).TrimEnd('\','/'),
        [StringComparison]::OrdinalIgnoreCase)}
  catch{return $false}
}
# Identical to v1.0.6 Get-TreeManifest canonicalization, but reject
# symlinks/reparse, escape, collision, and overlarge trees before claiming a SHA.
function TreeProof([string]$dir) {
  if(-not(PlainDir $dir)){return [pscustomobject]@{kind='MISSING_OR_UNSAFE';hash=''}}
  try{
    $base=[IO.Path]::GetFullPath($dir).TrimEnd('\','/')
    $rows=New-Object 'System.Collections.Generic.List[string]'
    $seen=@{}
    [int64]$sum=0
    foreach($f in @(Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction Stop)){
      if($rows.Count -ge 20000){throw 'LIMIT'}
      if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'LINK'}
      $full=[IO.Path]::GetFullPath($f.FullName)
      if(-not $full.StartsWith(($base+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'ESCAPE'}
      $rel=$full.Substring($base.Length).TrimStart('\','/').Replace('\','/').ToLowerInvariant()
      if($rel.Length -eq 0 -or $seen.ContainsKey($rel)){throw 'COLLISION'}
      $seen[$rel]=$true
      if($f.PSIsContainer){
        $rows.Add('D|'+$rel)
      }else{
        [int64]$len=$f.Length
        $sum+=$len
        if($len -lt 0 -or $sum -gt 4294967296){throw 'LIMIT'}
        $digest=(Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $f2=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if($f2.PSIsContainer -or ($f2.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           [int64]$f2.Length -ne $len){throw 'RACE'}
        $rows.Add(('F|{0}|{1}|{2}' -f $rel,$len,$digest))
      }
    }
    [string[]]$ordered=$rows.ToArray()
    [Array]::Sort($ordered,[StringComparer]::Ordinal)
    $canonical=([string]::Join([string][char]10,$ordered)+[char]10)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
    return [pscustomobject]@{kind='READABLE';hash=$hash}
  }catch{return [pscustomobject]@{kind='UNVERIFIED_OR_UNSAFE';hash=''}}
}
function ClassifyTree($proof,[string]$before,[string]$after){
  if($proof.kind -cne 'READABLE'){return $proof.kind}
  if($proof.hash -ceq $before){return 'EXACT_BEFORE'}
  if($proof.hash -ceq $after){return 'EXACT_AFTER'}
  return 'DIFFERENT_FROM_TRANSACTION'
}
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_CONTROL_PREPARED_TXN_TREE_R4')
$out.Add('READ_ONLY=YES;NETWORK=NO;BOOTSTRAP_EXEC=NO;AUTORESTORE=NO;FILE_WRITE=NO')
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_ONLY'}
  if(-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOST_OVERRIDE_DENIED'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
    if(-not $fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'OUTSIDE_RUNNER'}
    $root=Join-Path $fixture 'LocalAppData\SpotifyControl'
  }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($local)){throw 'LOCALAPPDATA_MISSING'}
    $root=Join-Path $local 'SpotifyControl'
  }
  if(-not(PlainDir $root)){throw 'ROOT_UNSAFE'}
  $txn=ReadJson (Join-Path $root 'self-update-last-transaction.json')
  $report=ReadJson (Join-Path $root 'reports\self-update-latest.json')
  if($null -eq $txn){throw 'TRANSACTION_UNREADABLE'}
  $status=[string](Field $txn 'status')
  $out.Add('TRANSACTION_STATUS='+$(if($status -cin @('prepared','swapped','post-verified','rolled-back','committed')){$status.ToUpperInvariant().Replace('-','_')}else{'OTHER'}))
  $out.Add('TRANSACTION_ERROR_CLASS='+(SafeErrorCategory $txn))
  $out.Add('LAST_REPORT_ERROR_CLASS='+(SafeErrorCategory $report))
  $id=Field $txn 'id'
  $validId=($id -is [string] -and $id -cmatch '^\d{8}-\d{6}-[a-f0-9]{8}$')
  $before=[string](Field $txn 'before_tree_sha256')
  $after=[string](Field $txn 'after_tree_sha256')
  $pins=($before -cmatch '^[a-f0-9]{64}$' -and $after -cmatch '^[a-f0-9]{64}$')
  $versionPair=([string](Field $txn 'before_version') -ceq '0.6.20' -and [string](Field $txn 'after_version') -ceq '0.6.28')
  $out.Add('ID_FORMAT='+$(if($validId){'VALID_V106'}else{'UNVERIFIED'}))
  $out.Add('BEFORE_AFTER_SHA_FORMAT='+$(if($pins){'VALID'}else{'UNVERIFIED'}))
  $out.Add('VERSION_PAIR='+$(if($versionPair){'V0620_TO_V0628'}else{'UNEXPECTED_OR_UNKNOWN'}))
  if(-not $validId -or -not $pins){throw 'PIN_OR_ID_UNSAFE'}
  $backupPath=Join-Path $root ('backups\self-update-transactions\'+$id+'\bin')
  $oldPath=Join-Path $root ('bin.spotifycontrol-old-'+$id)
  $newPath=Join-Path $root ('bin.spotifycontrol-new-'+$id)
  $paths=(ExactPath ([string](Field $txn 'backup_bin')) $backupPath) -and
         (ExactPath ([string](Field $txn 'same_dir_old')) $oldPath) -and
         (ExactPath ([string](Field $txn 'same_dir_new')) $newPath)
  $out.Add('TRANSACTION_PATH_PINS='+$(if($paths){'EXACT_V106'}else{'INVALID_OR_UNVERIFIED'}))
  if(-not $paths){throw 'TRANSACTION_PATHS_UNSAFE'}
  $live=ClassifyTree (TreeProof (Join-Path $root 'bin')) $before $after
  $backup=ClassifyTree (TreeProof $backupPath) $before $after
  $old=ClassifyTree (TreeProof $oldPath) $before $after
  $new=ClassifyTree (TreeProof $newPath) $before $after
  $out.Add('LIVE_BIN_TREE='+$live)
  $out.Add('BACKUP_BIN_TREE='+$backup)
  $out.Add('SAME_VOLUME_OLD_TREE='+$old)
  $out.Add('SAME_VOLUME_NEW_TREE='+$new)
  $consistent=($status -ceq 'prepared' -and $versionPair -and
      $live -ceq 'EXACT_BEFORE' -and $backup -ceq 'EXACT_BEFORE' -and
      $old -ceq 'MISSING_OR_UNSAFE' -and
      $new -cin @('MISSING_OR_UNSAFE','EXACT_AFTER'))
  $out.Add('PREPARED_BACKUP_AND_LIVE_COHERENT='+$(if($consistent){'YES'}else{'NOT_PROVEN'}))
  $out.Add('RESULT='+$(if($consistent){'PREPARED_ORPHAN_COHERENT_HOLD_NO_CHANGES'}else{'HOLD_UNRESOLVED_TREE_OR_TRANSACTION'}))
}catch{$out.Add('RESULT=HOLD_READONLY_UNVERIFIED')}
$out.Add('BOOTSTRAP_CHECK_ALLOWED=NO;ROLLBACK_ALLOWED=NO;DELETE_AUTHORIZED=NO')
$out.Add('RAW_PATHS_IDS_ERRORS_SECRETS_EXPORTED=NO')
if([string]::IsNullOrWhiteSpace($HostedFixtureRoot)){
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$out | ForEach-Object {Write-Output $_}
