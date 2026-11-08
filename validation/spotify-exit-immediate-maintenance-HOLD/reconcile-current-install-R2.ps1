# Spotify Control exact installed-source reconciliation, versioned HOLD.
# Read-only; no network; no app/process/scheduler execution or persistent writes.
# Only sanitized status enums, exact hashes, version markers, error categories.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$knownMain = @{
  '6ecb2eb6f25a71c4fdb410f227124126d6c3b91e8f3f4591713aaa40a4afe297' = 'v0.6.10'
  '045ed3fa898453ce6563a057a31412d254f5958b75286589e8d5cc95c6782a39' = 'v0.6.11'
  'e20ed445d7a5788cde1be9861dc3b44a81777aad03e0b1d4cea1a6e5bde1a14d' = 'v0.6.13'
  '4c5a2037c90cd5ac08cb182ad97a8fc020885f7c21360725f64e0a10d91937f8' = 'v0.6.12'
  '5306acbe610b06f2c638ebbdc305db9741bbe145392933a38f648906acd302d1' = 'v0.6.14'
  '4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f' = 'v0.6.15'
  '6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad' = 'v0.6.16'
  '5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b' = 'v0.6.17'
  '27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f' = 'v0.6.18'
  '45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f' = 'v0.6.19'
  'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18' = 'v0.6.20'
  'f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828' = 'v0.6.21'
  'b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe' = 'v0.6.22'
  'bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08' = 'v0.6.23'
  'dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151' = 'v0.6.24'
  '896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f' = 'v0.6.25'
  'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1' = 'v0.6.26'
  '9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787' = 'v0.6.27'
  'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0' = 'v0.6.28'
}
$knownAddon = @{
  'e076b301ce48bc1d1d7742c9588ef088dd643b88e17012b85b795766ff5f3e7c' = 'v0.6.11'
  'a194d49bd37320a7035b2deed22faabc70d3d2e14ff7ab2d35035ba5e7f96065' = 'v0.6.13'
  '421872e2ea5ffeac14d80b9256b0fd2a45e295558df7d3ce72017761a02bb76a' = 'v0.6.12'
  'd6a11c73c561662579c9b28b59e9f2845563e8050eceeb8e5cec0f5f3618759a' = 'v0.6.14'
  '56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022' = 'v0.6.15'
  'fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686' = 'v0.6.16'
  'b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977' = 'v0.6.17'
  'df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa' = 'v0.6.19'
  '3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86' = 'v0.6.20'
  '7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2' = 'v0.6.21'
  '0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc' = 'v0.6.22'
  '23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687' = 'v0.6.23'
  '81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470' = 'v0.6.24'
  '25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c' = 'v0.6.25'
  '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f' = 'v0.6.26'
  'c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152' = 'v0.6.27'
  '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285' = 'v0.6.28'
}

function Safe-File {
  param([string]$Path,[int64]$MaxSize)
  try {
    $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $f.Length -lt 2 -or $f.Length -gt $MaxSize){return $null}
    return $f
  }catch{return $null}
}
function Safe-Folder {
  param([string]$Path)
  try {
    $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return ($f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function Fingerprint-Script {
  param([string]$Path,[hashtable]$Known,[string]$Kind)
  $f=Safe-File -Path $Path -MaxSize 2097152
  if($null -eq $f){return [pscustomobject]@{Bytes='UNKNOWN';Sha='UNKNOWN';Release='UNKNOWN';Marker='UNKNOWN';PsParse='UNKNOWN'}}
  $sha='UNKNOWN';$release='UNLISTED_HASH';$marker='UNKNOWN';$parse='UNKNOWN'
  try {
    $sha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($Known.ContainsKey($sha)){$release=[string]$Known[$sha]}
    $content=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    $pattern=if($Kind -ceq 'MAIN'){
      '(?m)^\s*\$ScriptVersion\s*=\s*["' + [char]39 + '](0\.6\.[0-9]{1,3})["' + [char]39 + ']'
    }else{
      '(?m)^\s*\$Version\s*=\s*["' + [char]39 + '](0\.6\.5-r[0-9]{1,3})["' + [char]39 + ']'
    }
    $matches=[regex]::Matches($content,$pattern)
    if($matches.Count -eq 1){$marker=[string]$matches[0].Groups[1].Value}
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    $parse=if(@($errors).Count -eq 0){'PASS'}else{'ERRORS_PRESENT'}
  }catch{
    $parse='UNKNOWN'
  }
  return [pscustomobject]@{Bytes=[string]$f.Length;Sha=$sha;Release=$release;Marker=$marker;PsParse=$parse}
}
function Safe-Status {
  param($Value)
  if($Value -isnot [string]){return 'UNKNOWN'}
  $valueLower=$Value.Trim().ToLowerInvariant()
  $recognized=@(
    'prepared','awaiting-apply','applied','committed','rolled-back',
    'rolling-back','rollback-pending','rollback-failed','failed','blocked',
    'no-change','no-op','pending','in-progress','staged',
    'completed','success','error','never','unknown','aborted',
    'verified','restored','already-current','up-to-date'
  )
  if($recognized -ccontains $valueLower){return $valueLower.ToUpperInvariant().Replace('-','_')}
  return 'OTHER_REDACTED'
}
function Age-Band {
  param([datetime]$Date)
  $hours=([datetime]::UtcNow-$Date.ToUniversalTime()).TotalHours
  if($hours -lt -1){return 'FUTURE_OR_CLOCK_DRIFT'}
  if($hours -lt 24){return 'LT_24H'}
  if($hours -lt 168){return 'D1_TO_D7'}
  if($hours -lt 720){return 'D8_TO_D30'}
  return 'OVER_30D'
}
function Read-Record {
  param([string]$Path,[int64]$MaxSize=1048576)
  $f=Safe-File -Path $Path -MaxSize $MaxSize
  if($null -eq $f){return [pscustomobject]@{Kind='ABSENT_OR_UNSAFE';Doc=$null;Age='UNKNOWN'}}
  try{
    $doc=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    if($null -eq $doc -or $doc -isnot [psobject]){
      return [pscustomobject]@{Kind='INVALID_JSON';Doc=$null;Age=(Age-Band $f.LastWriteTimeUtc)}
    }
    return [pscustomobject]@{Kind='READABLE';Doc=$doc;Age=(Age-Band $f.LastWriteTimeUtc)}
  }catch{
    return [pscustomobject]@{Kind='INVALID_JSON';Doc=$null;Age=(Age-Band $f.LastWriteTimeUtc)}
  }
}
function Field-Status {
  param($Doc,[string[]]$Keys)
  if($null -eq $Doc){return 'UNKNOWN'}
  foreach($key in $Keys){
    if($null -ne $Doc.PSObject.Properties[$key]){
      return Safe-Status $Doc.$key
    }
  }
  return 'UNKNOWN'
}
function Field-Bool {
  param($Doc,[string]$Key)
  if($null -eq $Doc -or $null -eq $Doc.PSObject.Properties[$Key]){return 'UNKNOWN'}
  if($Doc.$Key -isnot [bool]){return 'UNKNOWN'}
  return $(if([bool]$Doc.$Key){'TRUE'}else{'FALSE'})
}
function Redacted-ErrorHints {
  param($Doc)
  if($null -eq $Doc){return 'UNKNOWN'}
  $blob=New-Object System.Collections.Generic.List[string]
  foreach($key in @('errors','warnings','error','last_error','failures')){
    if($null -ne $Doc.PSObject.Properties[$key]){
      foreach($entry in @($Doc.$key)){
        if($null -eq $entry){continue}
        $value=if($entry -is [string]){$entry}else{($entry | ConvertTo-Json -Depth 4 -Compress)}
        if($value.Length -gt 12000){$value=$value.Substring(0,12000)}
        $blob.Add($value)
        if($blob.Count -ge 40){break}
      }
    }
  }
  if($blob.Count -eq 0){return 'NO_ERROR_TEXT_FIELDS'}
  $text=[string]::Join(' ',$blob)
  $hints=New-Object System.Collections.Generic.List[string]
  if($text -match '(?i)timed.?out|network|connect|dns|429|rate.?limit|github.*api|http.*(403|500|502|503)'){$hints.Add('NETWORK_OR_API')}
  if($text -match '(?i)file.*lock|denied|access|permission|unauthoriz|mutex|busy'){$hints.Add('ACCESS_OR_PROCESS')}
  if($text -match '(?i)spicetify|xpui|spotify.*version|compatib'){$hints.Add('SPOTIFY_OR_SPICETIFY')}
  if($text -match '(?i)add.?on|custom.?app|marketplace|extension|ambiguous'){$hints.Add('ADDON_OR_MARKETPLACE')}
  if($text -match '(?i)patch|transaction|backup|rollback|restore|journal|hash'){$hints.Add('TRANSACTION_OR_RECOVERY')}
  if($hints.Count -eq 0){return 'OTHER_REDACTED'}
  return ($hints -join ',')
}
$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('DIAGNOSTIC=SPOTIFY_CONTROL_CURRENT_INSTALL_RECONCILE_R2')
$lines.Add('READ_ONLY=YES;NETWORK=NO;INSTALL=NO;EXECUTABLE_RUN=NO;TASK_CHANGE=NO;DATA_WRITE=NO')
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if([string]::IsNullOrWhiteSpace($local)){throw 'LOCAL_ROOT_UNAVAILABLE'}
  $root=Join-Path $local 'SpotifyControl'
  $bin=Join-Path $root 'bin'
  if(-not (Safe-Folder $root) -or -not (Safe-Folder $bin)){throw 'INSTALL_ROOT_UNSAFE_OR_MISSING'}
  $main=Fingerprint-Script -Path (Join-Path $bin 'spotify-control.ps1') -Known $knownMain -Kind MAIN
  $addon=Fingerprint-Script -Path (Join-Path $bin 'addon-manager.ps1') -Known $knownAddon -Kind ADDON
  $lines.Add('MAIN_BYTES='+$main.Bytes+';SHA256='+$main.Sha)
  $lines.Add('MAIN_RELEASE_MATCH='+$main.Release+';MARKER='+$main.Marker+';PS51_PARSE='+$main.PsParse)
  $lines.Add('ADDON_BYTES='+$addon.Bytes+';SHA256='+$addon.Sha)
  $lines.Add('ADDON_RELEASE_MATCH='+$addon.Release+';MARKER='+$addon.Marker+';PS51_PARSE='+$addon.PsParse)
  $state=Read-Record (Join-Path $root 'state.json') 4194304
  $lines.Add('STATE_RECORD='+$state.Kind)
  if($state.Kind -ceq 'READABLE'){
    $lines.Add('STATE_SPICETIFY_LAST='+ (Field-Status $state.Doc @('spicetify_last_transaction_status','spicetify_transaction_status')))
    $lines.Add('STATE_SPOTIFY_LAST='+ (Field-Status $state.Doc @('spotify_last_transaction_status')))
    $lines.Add('STATE_SELF_UPDATE_LAST='+ (Field-Status $state.Doc @('self_update_last_transaction_status')))
    $lines.Add('STATE_PENDING='+ (Field-Bool $state.Doc 'pending_maintenance')+';MAINTENANCE_HEALTHY='+ (Field-Bool $state.Doc 'maintenance_check_healthy'))
    $reasons='UNKNOWN'
    if($null -ne $state.Doc.PSObject.Properties['pending_reasons']){
      $rs=@($state.Doc.pending_reasons)
      if($rs.Count -le 100){
        $categories=New-Object System.Collections.Generic.List[string]
        foreach($v in $rs){
          $a=[string]$v
          if($a -match '(?i)spicetify|xpui'){$categories.Add('SPICETIFY')}
          elseif($a -match '(?i)spotify'){$categories.Add('SPOTIFY')}
          elseif($a -match '(?i)marketplace'){$categories.Add('MARKETPLACE')}
          elseif($a -match '(?i)addon|autoapp'){$categories.Add('ADDON')}
          elseif($a -match '(?i)self.?update'){$categories.Add('SELF_UPDATE')}
          elseif($a -match '(?i)guard|compatib'){$categories.Add('GUARD')}
          else{$categories.Add('OTHER')}
        }
        $reasons=(($categories|Select-Object -Unique) -join ',')
        if($reasons.Length -eq 0){$reasons='NONE'}
      }
    }
    $lines.Add('PENDING_REASON_CATEGORIES='+$reasons)
  }
  foreach($entry in @(
    @('SPICETIFY_LAST','spicetify-last-transaction.json'),
    @('SPICETIFY_REPORT','spicetify-transaction-latest.json'),
    @('MAINTENANCE_CHECK','maintenance-check-latest.json'),
    @('ADDON_LAST','addon-last-transaction.json')
  )){
    $tag=[string]$entry[0]
    $record=Read-Record -Path (Join-Path $root ([string]$entry[1]))
    $lines.Add($tag+'_RECORD='+$record.Kind+';AGE='+$record.Age)
    if($record.Kind -ceq 'READABLE'){
      $status=Field-Status $record.Doc @('status','transaction_status','result_status','phase')
      $lines.Add($tag+'_STATUS='+$status+
        ';COMMITTED='+ (Field-Bool $record.Doc 'committed')+
        ';SUCCESS='+ (Field-Bool $record.Doc 'success'))
      if($tag -ceq 'MAINTENANCE_CHECK'){
        $lines.Add('CHECK_ERROR_HINTS='+ (Redacted-ErrorHints $record.Doc))
      }
    }
  }
  $bothKnown=($main.Release -like 'v0.6.*' -and $addon.Release -like 'v0.6.*' -and
              $main.PsParse -ceq 'PASS' -and $addon.PsParse -ceq 'PASS')
  $lines.Add('SOURCE_PAIR='+$(if($bothKnown){'BOTH_OFFICIAL_RELEASE_HASHES'}else{'AT_LEAST_ONE_HASH_UNIDENTIFIED'}))
  $lines.Add('RESULT=READ_ONLY_RECONCILIATION_COMPLETE_NO_INSTALL_AUTHORITY')
}catch{
  $lines.Add('RESULT=HOLD_READONLY_RECONCILIATION_INCOMPLETE')
}
$lines.Add('SPOTIFY_UPDATE_AUTHORIZED=NO;BOOTSTRAP_UPDATE_AUTHORIZED=NO;ORIGINALS_DELETE=NO')
$lines.Add('PRIVATE_PATHS_KEYS_LOG_TEXT_EXPORTED=NO')
$copyStatus='UNAVAILABLE'
try {
  Set-Clipboard -Value ($lines -join [Environment]::NewLine) -ErrorAction Stop
  $copyStatus='COPIED'
}catch{}
$lines.Add('CLIPBOARD='+$copyStatus)
$lines|ForEach-Object {Write-Output $_}
