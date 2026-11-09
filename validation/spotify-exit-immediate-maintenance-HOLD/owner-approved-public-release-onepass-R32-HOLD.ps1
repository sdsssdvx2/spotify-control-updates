# R32 HOLD: verified public-release -> one owner approval -> official R28 update.
# Never publish release, auto-retry, change shortcuts, or download an installer.
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$ApprovalPhrase='',
  [string]$ApprovedPublicManifestSHA256='',
  [string]$ApprovedPublicSourceCommit=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R32_PUBLIC_NEXT_STABLE_ONE_APPROVAL_HOLD')
$log.Add('PUBLISH=NO;AUTO_RETRY=NO;SCRIPT_INSTALL=NO;SHORTCUT_WRITE_BY_WRAPPER=NO')
$stage='ADMISSION';$net='NONE';$cutover='NOT_STARTED';$updated='NOT_STARTED'
function Deny([string]$why){throw [InvalidOperationException]::new($why)}
function Hash([byte[]]$data,[string]$alg){
  $h=[Security.Cryptography.HashAlgorithm]::Create($alg)
  if($null -eq $h){Deny 'HASH_PROVIDER_UNAVAILABLE'}
  try{return [BitConverter]::ToString($h.ComputeHash($data)).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function GitBlobSha([byte[]]$data){
  $prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+[string]$data.Length)+[char]0)
  [byte[]]$all=New-Object byte[] ($prefix.Length+$data.Length)
  [Buffer]::BlockCopy($prefix,0,$all,0,$prefix.Length)
  [Buffer]::BlockCopy($data,0,$all,$prefix.Length,$data.Length)
  return (Hash $all 'SHA1')
}
function FetchPinned([string]$name,[long]$size,[string]$blob){
  $ref='aedd8219391574e910c1fae4198cff7b7db31884'
  $url='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$ref+'/validation/spotify-exit-immediate-maintenance-HOLD/'+$name
  $web=New-Object Net.WebClient
  try{[byte[]]$data=$web.DownloadData($url)}finally{$web.Dispose()}
  if($data.Length -ne $size -or (GitBlobSha $data) -cne $blob){Deny 'PINNED_SOURCE_BLOB_MISMATCH'}
  return ,$data
}
function ExistingPython{
  $choices=New-Object 'System.Collections.Generic.List[string]'
  foreach($cmd in @(Get-Command python.exe -All -CommandType Application -ErrorAction SilentlyContinue)){
    if($cmd.Source){$choices.Add([string]$cmd.Source)}
  }
  foreach($path in @(
     (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
     (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
     (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
     'D:\Utility\TelegramPCBackup\.venv\Scripts\python.exe')){
    if($path){$choices.Add($path)}
  }
  foreach($path in $choices){
    if($path -match '(?i)[\/]WindowsApps[\/]'){continue}
    try {
      $entry=Get-Item -LiteralPath $path -Force -ErrorAction Stop
      if($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
      $probe=@(& $path -I -S -B -c 'import sys; print("OK" if sys.version_info >= (3,10) else "OLD")' 2>&1)
      if($LASTEXITCODE -eq 0 -and $probe.Count -eq 1 -and [string]$probe[0] -ceq 'OK'){return $path}
    }catch{}
  }
  return ''
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    Deny 'WINDOWS_POWERSHELL_51_X64_REQUIRED'
  }
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE'){
    Deny 'ONE_SHOT_OWNER_APPROVAL_REQUIRED'
  }
  if($ApprovedPublicManifestSHA256 -cnotmatch '^[0-9a-f]{64}$' -or
     $ApprovedPublicSourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
     $ApprovedPublicSourceCommit -cin @('bb6d90146f20b73d36fbf8cb813f1b190f403c48',('f'*40),('e'*40))){
    Deny 'UNPUBLISHED_OR_UNAPPROVED_PUBLIC_RELEASE'
  }
  $stage='PYTHON'
  $python=ExistingPython
  if(-not $python){Deny 'EXISTING_PYTHON_310_REQUIRED'}
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $stage='FROZEN_SOURCES'
  $net='PINNED_PUBLIC_GITHUB_READONLY'
  [byte[]]$r27=FetchPinned 'guarded-first-update-resident-entry-R27-HOLD.ps1' 14472 '98df17ed1c4d81445bbf34cf4bfa3b2889bc2cc0'
  [byte[]]$r28=FetchPinned 'owner-approved-next-stable-upgrade-R28-HOLD.ps1' 22594 '6a9a5bfbeb9a357b14345037bbf1419fade8304d'
  [byte[]]$r29=FetchPinned 'verify-public-release-transport-R29-HOLD.py' 17328 '558f1f54a6c04afa72d013cef02b807fb3a148fd'
  if((Hash $r27 'SHA256') -cne '096a9d13d499af4057f3a40d15dc105dfe2a5de97296373f949b3e6a58dd8064'){
    Deny 'R27_SHA256_PIN_MISMATCH'
  }
  $log.Add('IMMUTABLE_R27_R28_R29_TOOL_BYTES=PINNED')
  $stage='R29_REAL_PUBLIC_RELEASE_VERIFY'
  $text=[Text.Encoding]::ASCII.GetString($r29)
  $audit=@($text | & $python -I -S -B - --mode next-stable --approved-manifest-sha $ApprovedPublicManifestSHA256 --approved-source-sha $ApprovedPublicSourceCommit --release-facts-json 2>&1)
  if($LASTEXITCODE -ne 0){Deny 'REAL_PUBLIC_RELEASE_R29_FAILED'}
  foreach($line in @(
     'PUBLIC_NEXT_STABLE_MANIFEST_INDEPENDENT_SHA_APPROVED=PASS',
     'PUBLIC_NEXT_STABLE_IMMUTABLE_SOURCE_20_CHUNKS=PASS',
     'PUBLIC_NEXT_STABLE_V0628_TO_V0630_MAIN_AND_VBS_SHA=PASS',
     'PUBLIC_NEXT_STABLE_MANIFEST=READONLY_ADMITTED_NO_UPDATE_OR_PROCESS_CHANGE')){
    if($audit -cnotcontains $line){Deny 'PUBLIC_RELEASE_FACTUAL_PROOF_MISSING'}
  }
  $prefix='PUBLIC_RELEASE_FACTS_JSON='
  $records=@($audit | Where-Object {([string]$_).StartsWith($prefix,[StringComparison]::Ordinal)})
  if($records.Count -ne 1){Deny 'PUBLIC_RELEASE_RECEIPT_COUNT_INVALID'}
  $facts=([string]$records[0]).Substring($prefix.Length)
  if($facts.Length -lt 100 -or $facts.Length -gt 2400){Deny 'PUBLIC_RELEASE_RECEIPT_SIZE_INVALID'}
  $log.Add('R29_REAL_PUBLIC_MANIFEST_AND_IMMUTABLE_CHUNKS=PASS')
  $stage='R28_OWNER_PREFLIGHT_OR_COMMIT'
  $r28Controller=[ScriptBlock]::Create([Text.Encoding]::ASCII.GetString($r28))
  $owner=@{
    PinnedR27Source=$r27
    PinnedReleaseFactsJson=$facts
    ApprovedPublicManifestSHA256=$ApprovedPublicManifestSHA256
    ApprovedPublicSourceCommit=$ApprovedPublicSourceCommit
  }
  if($Commit){
    $owner.Commit=$true
    $owner.ApprovalPhrase=$ApprovalPhrase
  }
  # Only the child can certify whether it changed owner state.
  $cutover='UNKNOWN';$updated='UNKNOWN'
  $receipt=@(& $r28Controller @owner)
  if($receipt -ccontains 'EXACT_INITIAL_CUTOVER_DONE=YES'){$cutover='YES'}
  elseif($receipt -ccontains 'EXACT_INITIAL_CUTOVER_DONE=NO'){$cutover='NO'}
  if($receipt -ccontains 'OFFICIAL_UPDATE_INVOKED_SUCCESS=YES'){$updated='YES'}
  elseif($receipt -ccontains 'OFFICIAL_UPDATE_INVOKED_SUCCESS=NO'){$updated='NO'}
  foreach($key in @('HOLD_STAGE','HOLD_REASON')){
    $values=@($receipt | Where-Object { [string]$_ -cmatch ('^'+$key+'=[A-Z0-9_]{1,100}$') })
    if($values.Count -eq 1){$log.Add('R28_'+[string]$values[0])}
  }
  if($Commit){
    foreach($line in @(
      'RESULT=PINNED_PUBLIC_STABLE_ONESHOT_COMMITTED',
      'OFFICIAL_POSTCHECK=PASS',
      'NEW_RELEASE_VBS=ONE_EXACT_OWNER_RESIDENT_RUNNING',
      'USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL')){
      if($receipt -cnotcontains $line){Deny 'R28_PUBLIC_COMMIT_NOT_CONFIRMED'}
    }
    $log.Add('R28_SINGLE_APPROVED_OFFICIAL_UPDATE_AND_NEW_VBS=PASS')
    $log.Add('RESULT=PINNED_PUBLIC_STABLE_ONESHOT_COMMITTED')
  }else{
    if($receipt -cnotcontains 'RESULT=READY_FOR_ONE_SHOT_APPROVED_STABLE_NO_MUTATION'){
      Deny 'R28_READONLY_OWNER_PREFLIGHT_NOT_READY'
    }
    $log.Add('R28_OWNER_PREFLIGHT=PASS_READONLY')
    $log.Add('RESULT=READY_FOR_EXPLICIT_OWNER_APPROVAL_NO_CHANGES')
  }
}catch{
  $reason=[string]$_.Exception.Message
  $known=@('WINDOWS_POWERSHELL_51_X64_REQUIRED','ONE_SHOT_OWNER_APPROVAL_REQUIRED',
     'UNPUBLISHED_OR_UNAPPROVED_PUBLIC_RELEASE','EXISTING_PYTHON_310_REQUIRED',
     'PINNED_SOURCE_BLOB_MISMATCH','R27_SHA256_PIN_MISMATCH',
     'REAL_PUBLIC_RELEASE_R29_FAILED','PUBLIC_RELEASE_FACTUAL_PROOF_MISSING',
     'PUBLIC_RELEASE_RECEIPT_COUNT_INVALID','PUBLIC_RELEASE_RECEIPT_SIZE_INVALID',
     'R28_PUBLIC_COMMIT_NOT_CONFIRMED','R28_READONLY_OWNER_PREFLIGHT_NOT_READY')
  if($reason -cnotin $known){$reason='UNVERIFIED_INTERNAL_OR_WINDOWS_ERROR'}
  $log.Add('HOLD_STAGE='+$stage)
  $log.Add('HOLD_REASON='+$reason)
  $log.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  $log.Add('R28_OWNER_CUTOVER_OBSERVED='+$cutover)
  $log.Add('OFFICIAL_UPDATE_SUCCESS_OBSERVED='+$updated)
  $log.Add('NETWORK='+$net)
  $log.Add('RAW_PATHS_SECRETS_AND_PROCESS_IDS_EXPORTED=NO')
  try{Set-Clipboard -Value ($log -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $log | ForEach-Object {Write-Output $_}
}
