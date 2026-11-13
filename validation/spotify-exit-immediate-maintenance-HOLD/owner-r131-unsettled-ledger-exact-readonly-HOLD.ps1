param([switch]$NoClipboard)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
# Owner R131 HOLD: exact read-only status, never repair or execute any CLI.
function HFile([string]$p){
  $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'UNSAFE'}
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function HText([string]$v){
  $h=[Security.Cryptography.SHA256]::Create()
  try{
    $bytes=([Text.UTF8Encoding]::new($false)).GetBytes($v)
    return ([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  }finally{$h.Dispose()}
}
function F($obj,[string]$n){
  if($null -eq $obj){return $null}
  $p=$obj.PSObject.Properties[$n]
  if($null -eq $p){return $null}
  return $p.Value
}
function Tree([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){return 'ABSENT'}
  $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'UNSAFE'}
  $base=$f.FullName.TrimEnd([char[]]@('\','/'))
  $rows=New-Object 'System.Collections.Generic.List[object]'
  foreach($x in @(Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction Stop | Sort-Object FullName)){
    if($rows.Count -ge 50000){throw 'ENTRY_LIMIT'}
    if(($x.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'UNSAFE'}
    $name=$x.FullName.Substring($base.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
    if([string]::IsNullOrWhiteSpace($name)){continue}
    if($x.PSIsContainer){
      $rows.Add([pscustomobject]@{path=$name;type='dir';size=[int64]0;sha256=$null})
    }else{
      $rows.Add([pscustomobject]@{path=$name;type='file';size=[int64]$x.Length;sha256=(HFile $x.FullName)})
    }
  }
  $ordered=@($rows.ToArray() | Sort-Object path,type)
  return (HText ([string]($ordered | ConvertTo-Json -Depth 5 -Compress)))
}
function Compare-TreePin([string]$actual,[string]$before,[string]$after){
  if($actual -ceq 'ABSENT'){return 'ABSENT'}
  if($actual -cnotmatch '^[a-f0-9]{64}\z'){return 'UNVERIFIED'}
  if($before -cmatch '^[a-f0-9]{64}\z' -and $actual -ceq $before){return 'BEFORE'}
  if($after -cmatch '^[a-f0-9]{64}\z' -and $actual -ceq $after){return 'AFTER'}
  return 'OTHER'
}
function ConfigWith([string]$ini,[string]$before,[string]$after){
  if(-not(Test-Path -LiteralPath $ini -PathType Leaf)){return 'ABSENT'}
  [void](HFile $ini);$section='';$value=$null
  foreach($line in @(Get-Content -LiteralPath $ini -ErrorAction Stop)){
    if($line -match '^\s*\[([^\]]+)\]\s*$'){$section=$Matches[1];continue}
    if($section -ieq 'Backup' -and $line -match '^\s*with\s*=\s*(.*?)\s*$'){$value=$Matches[1];break}
  }
  if($null -eq $value){return 'ABSENT'}
  if($value -ceq $before){return 'BEFORE'}
  if($value -ceq $after){return 'AFTER'}
  return 'OTHER'
}
$map=[ordered]@{
  DIAGNOSTIC='SPOTIFY_R131_UNSETTLED_OWNER_EXACT_READONLY'
  NETWORK='NO';PROGRAM_EXEC='NO';FILE_WRITES='NO';AUTO_RETRY='NO'
  LEDGER='UNKNOWN';LEDGER_STABLE='UNKNOWN';ROOT='UNKNOWN';EXE='UNKNOWN'
  BACKUP_ROOT='UNKNOWN';BACKUP_WITH='UNKNOWN';STATE_LINK='UNKNOWN'
  RESULT='HOLD_NOT_RECOVERED'
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_ONLY'}
  $ctrl=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $ledger=Join-Path $ctrl 'spicetify-last-transaction.json'
  if(-not(Test-Path -LiteralPath $ledger -PathType Leaf)){throw 'LEDGER_ABSENT'}
  $beforeLedger=HFile $ledger
  $txn=Get-Content -LiteralPath $ledger -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  $s=[string](F $txn 'status')
  $map.LEDGER=$(if($s -cin @('committed','rolled-back')){'SETTLED'}elseif($s -cin @('awaiting-guard','prepared','rollback-root-restored-apply-failed')){'UNSETTLED'}else{'UNCLASSIFIED'})
  $id=[string](F $txn 'id')
  $old=[string](F $txn 'before_tree_sha256');$new=[string](F $txn 'after_tree_sha256')
  $live=Join-Path $env:LOCALAPPDATA 'spicetify'
  $map.ROOT=Compare-TreePin (Tree $live) $old $new
  $exe=Join-Path $live 'spicetify.exe'
  $exehash=$(if(Test-Path -LiteralPath $exe -PathType Leaf){HFile $exe}else{'ABSENT'})
  $map.EXE=Compare-TreePin $exehash ([string](F $txn 'before_sha256')) ([string](F $txn 'after_sha256'))
  $expected=$(if($id -cmatch '^\d{8}-\d{6}-[a-f0-9]{8}\z'){
    Join-Path $ctrl ('backups\spicetify-transactions\'+$id+'\root-before')
  }else{''})
  $back=[string](F $txn 'backup_root')
  if($expected -and $back -and
     [IO.Path]::GetFullPath($back) -ieq [IO.Path]::GetFullPath($expected)){
    $map.BACKUP_ROOT=Compare-TreePin (Tree $back) $old ''
  }else{$map.BACKUP_ROOT='UNTRUSTED_PATH'}
  $map.BACKUP_WITH=ConfigWith (Join-Path $env:APPDATA 'spicetify\config-xpui.ini') ([string](F $txn 'before_version')) ([string](F $txn 'after_version'))
  $state=Join-Path $ctrl 'state.json'
  if(Test-Path -LiteralPath $state -PathType Leaf){
    $sh=HFile $state
    $sv=Get-Content -LiteralPath $state -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $map.STATE_LINK=$(if([string](F $sv 'spicetify_last_transaction_id') -ceq $id){'SAME'}else{'DIFFERENT'})
    if((HFile $state) -cne $sh){$map.STATE_LINK='CHANGED'}
  }else{$map.STATE_LINK='ABSENT'}
  $map.LEDGER_STABLE=$(if((HFile $ledger) -ceq $beforeLedger){'YES'}else{'NO'})
  if($map.LEDGER_STABLE -eq 'YES' -and $map.BACKUP_ROOT -eq 'BEFORE' -and
     $map.ROOT -cin @('BEFORE','AFTER') -and $map.EXE -cin @('BEFORE','AFTER')){
    $map.RESULT='EXACT_PREIMAGE_EVIDENCE_OWNER_REVIEW_ONLY'
  }
}catch{
  $map.RESULT='HOLD_READONLY_INCOMPLETE'
}
$receipt=(@($map.GetEnumerator() | ForEach-Object{[string]$_.Key+'='+[string]$_.Value}) -join [Environment]::NewLine)
if(-not $NoClipboard){try{Set-Clipboard -Value $receipt -ErrorAction Stop}catch{}}
Write-Output $receipt
