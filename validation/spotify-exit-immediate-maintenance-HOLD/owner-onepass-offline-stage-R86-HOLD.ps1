# R86 HOLD -- single native PowerShell 5.1 owner preflight and private source preparation.
# Does NOT install, update operating files, terminate processes, publish main,
# write shortcuts, change active guard ACL, or grant a future deployment approval.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R86_OWNER_ONEPASS_PREPUBLICATION_PREPARATION_HOLD')
$out.Add('NETWORK=PINNED_GITHUB_SOURCES_AND_REVIEW_CHUNKS_ONLY')
$out.Add('OPERATING_INSTALL=NO;PROCESS_CHANGE=NO;ACL_CHANGE=NO;RELEASE_PUBLICATION=NO')
$phase='START'
function StopNow([string]$why){throw [InvalidOperationException]::new($why)}
function SHA256([byte[]]$b){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function GitBlob([byte[]]$data){
  $s=[IO.MemoryStream]::new()
  try{
    $prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length))
    $s.Write($prefix,0,$prefix.Length);$s.WriteByte(0)
    $s.Write($data,0,$data.Length)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($s.ToArray()))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
  }finally{$s.Dispose()}
}
function FetchFrozen([string]$ref,[string]$filename,[string]$blob,[int]$limit){
  if($ref -cnotmatch '^[0-9a-f]{40}$' -or
     $filename -cnotmatch '^[a-z0-9-]+[.]ps1$' -or
     $blob -cnotmatch '^[0-9a-f]{40}$' -or $limit -lt 1000 -or $limit -gt 80000){
    StopNow 'R86_FROZEN_SOURCE_IDENTITY_NOT_PINNED'
  }
  $url='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$ref+
    '/validation/spotify-exit-immediate-maintenance-HOLD/'+$filename
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET';$req.Timeout=35000;$req.ReadWriteTimeout=35000
  $req.AllowAutoRedirect=$false;$req.KeepAlive=$false
  $response=$null
  try{
    $response=[Net.HttpWebResponse]$req.GetResponse()
    if($response.StatusCode -ne [Net.HttpStatusCode]::OK -or
       $response.ContentLength -gt $limit){StopNow 'R86_REMOTE_SOURCE_TOO_LARGE_OR_NOT_OK'}
    $wire=$response.GetResponseStream()
    $mem=[IO.MemoryStream]::new()
    try{
      [byte[]]$buffer=New-Object byte[] 8192
      while(($n=$wire.Read($buffer,0,$buffer.Length)) -gt 0){
        if($mem.Length+$n -gt $limit){StopNow 'R86_REMOTE_SOURCE_EXCEEDS_LIMIT'}
        $mem.Write($buffer,0,$n)
      }
      [byte[]]$bytes=$mem.ToArray()
      if((GitBlob $bytes) -cne $blob){StopNow 'R86_REMOTE_SOURCE_GIT_BLOB_NOT_PINNED'}
      return ,$bytes
    }finally{$wire.Dispose();$mem.Dispose()}
  }finally{if($null -ne $response){$response.Dispose()}}
}
function RequireOne([string[]]$rows,[string]$line){
  if(@($rows | Where-Object {$_ -ceq $line}).Count -ne 1){
    StopNow 'R86_OWNER_PREFLIGHT_REQUIRED_FIELD_NOT_EXACT'
  }
}
function RequireUniqueKey([string[]]$rows,[string]$key){
  if(@($rows | Where-Object {([string]$_).StartsWith($key+'=',[StringComparison]::Ordinal)}).Count -ne 1){
    StopNow 'R86_OWNER_RECEIPT_FIELD_COUNT_INVALID'
  }
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){
    StopNow 'R86_OWNER_WINDOWS_PS51_X64_REQUIRED'
  }
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  if(([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
     [Security.Principal.WindowsBuiltInRole]::Administrator)){
    StopNow 'R86_OWNER_STANDARD_USER_REQUIRED'
  }
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $phase='LIVE_OWNER_READONLY_FIRST'
  [byte[]]$r77=FetchFrozen '38bb7c2c1aa90f02d920dcd23a026f64c23ef844' 'owner-acl-readonly-R77-HOLD.ps1' 'edfdce9429d4a74612b2e6b1d6996ea6bb6fd50e' 40000
  $audit=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r77))))
  if($audit.Count -lt 15 -or $audit.Count -gt 70){StopNow 'R86_OWNER_READONLY_RECEIPT_BOUNDS'}
  foreach($line in @(
    'DIAGNOSTIC=SPOTIFY_R77_OWNER_ACL_READONLY',
    'OWNER_TOKEN=STANDARD_USER',
    'STABLE_MAIN_V0628=EXACT',
    'ADDON_MANAGER_R17=EXACT',
    'RESIDENT_VBS=EXACT',
    'OFFICIAL_BOOTSTRAP=EXACT',
    'EXACT_INSTALLED_STACK=PASS',
    'SPOTIFY_SIGNATURE=VALID_SPOTIFY_AB',
    'SPICETIFY_CLI_SOURCE_PIN=OFFICIAL_2464',
    'CURRENT_COMPATIBILITY=OFFICIALLY_SUPPORTED_RANGE',
    'SPOTIFY_PROCESS=CLOSED',
    'RESIDENT_PROCESS_PATH_MATCH=ONE_MATCH',
    'STATE_FILE=PARSED_NOT_AUTHORITY',
    'SPOTIFY_UPDATE_GUARD_SAVED=BLOCKED_REPORTED_ONLY',
    'UPDATE_FOLDER_ACL_NOW=OWNER_WRITE_DELETE_DENY_ACE_PRESENT',
    'SAVED_GUARD_VS_ACL=SAVED_BLOCKED_MATCHES_LIVE_ACL',
    'ACL_PROOF_LEVEL=OWNER_DENY_ACES_ONLY_NOT_ACCESS_CHECK',
    'OWNER_ENVIRONMENT_PRECHECK=READONLY_CONSISTENT_NOT_DEPLOY_AUTHORITY',
    'AUTHORIZE_DEPLOY=NO;AUTOMATIC_RETRY=NO;OWNER_SOURCE_CHANGE=NO',
    'RESULT=READONLY_SNAPSHOT_COMPLETE')){
    RequireOne $audit $line
  }
  foreach($field in @('DIAGNOSTIC','OWNER_TOKEN','STABLE_MAIN_V0628','ADDON_MANAGER_R17',
    'RESIDENT_VBS','OFFICIAL_BOOTSTRAP','EXACT_INSTALLED_STACK','SPOTIFY_SIGNATURE',
    'SPICETIFY_CLI_SOURCE_PIN','CURRENT_COMPATIBILITY','SPOTIFY_PROCESS',
    'RESIDENT_PROCESS_PATH_MATCH','STATE_FILE','SPOTIFY_UPDATE_GUARD_SAVED',
    'UPDATE_FOLDER_ACL_NOW','SAVED_GUARD_VS_ACL','ACL_PROOF_LEVEL',
    'OWNER_ENVIRONMENT_PRECHECK','AGENT_MUTATION_SAVED','RESULT')){
    RequireUniqueKey $audit $field
  }
  if($audit -cnotcontains 'AGENT_MUTATION_SAVED=ARMED_SAVED' -and
     $audit -cnotcontains 'AGENT_MUTATION_SAVED=OFF_SAVED'){
    StopNow 'R86_AGENT_SAVED_SETTING_NOT_RECOGNIZED'
  }
  $out.Add('R86_R77_ACTUAL_ACL_COMPAT_AND_OWNER_FILES=PASS_READONLY')
  $phase='OWNER_R27_EXACT_CUTOVER_READONLY_PROOF'
  [byte[]]$r27=FetchFrozen '30e910f92207ed55f21f30c3287d8d8a59e8052e' 'guarded-first-update-resident-entry-R27-HOLD.ps1' '98df17ed1c4d81445bbf34cf4bfa3b2889bc2cc0' 30000
  if((SHA256 $r27) -cne '096a9d13d499af4057f3a40d15dc105dfe2a5de97296373f949b3e6a58dd8064'){
    StopNow 'R86_R27_SOURCE_SHA256_MISMATCH'
  }
  $readiness=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r27))))
  RequireOne $readiness 'RESULT=READY_FOR_EXACT_CUTOVER_NO_CHANGES'
  $out.Add('R86_R27_OWNER_RESIDENT_CUTOVER_PREFLIGHT=READY_NO_PROCESS_CHANGE')
  $phase='PRIVATE_REVIEW_SOURCE_ATTEST_AND_STAGE'
  [byte[]]$r84=FetchFrozen '7c97cae2c39db0944dbe87bc05b96aaa10fc9747' 'stage-immutable-review-native-R84-HOLD.ps1' '3833a7532374a21deb41c282cbd1085bb7d4a6ff' 35000
  $candidate=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r84))) -StageOwnerCandidate)
  RequireOne $candidate 'R84_RESULT=PRIVATE_CANDIDATE_STAGED_NOT_INSTALLED'
  RequireOne $candidate 'R84_OWNER_STAGED_IMMUTABLE_CHUNKS_21_OF_21=PASS'
  $items=@($candidate|Where-Object {([string]$_) -cmatch '^R84_OWNER_PRIVATE_STAGE_ID=[0-9a-f]{32}$'})
  if($items.Count -ne 1){StopNow 'R86_R84_SOURCE_STAGE_ID_UNVERIFIED'}
  $stageId=([string]$items[0]).Split('=')[1]
  $stagePath=Join-Path $env:LOCALAPPDATA ('SpotifyControlCanary-ready-'+$stageId)
  $out.Add('R86_IMMUTABLE_OWNER_PRIVATE_21_CHUNKS=STAGED_VERIFIED')
  $phase='PRIVATE_OFFLINE_BOOTSTRAP_PREPARATION'
  [byte[]]$r85=FetchFrozen '202d0b36e27e443321d1cb05e073c293f19972ef' 'compose-private-offline-bootstrap-R85-HOLD.ps1' '0f01f54703c8b3612b26ff6e505efc1ed2d1fb46' 25000
  $prepared=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r85))) -R84ReadyPath $stagePath)
  RequireOne $prepared 'RESULT=R85_OWNER_PRIVATE_OFFLINE_TRANSPORT_PREPARED_HOLD'
  RequireOne $prepared 'R85_R84_PINNED_21_CHUNKS_MIRRORED_FROM_LOCAL_DISK=PASS'
  $items=@($prepared|Where-Object {([string]$_) -cmatch '^R85_OWNER_OFFLINE_STAGE_ID=[0-9a-f]{32}$'})
  if($items.Count -ne 1){StopNow 'R86_R85_OFFLINE_STAGE_ID_UNVERIFIED'}
  $out.Add('R86_OFFLINE_PRIVATE_STAGE_ID='+([string]$items[0]).Split('=')[1])
  $out.Add('R86_R85_DISPOSABLE_BOOTSTRAP_AND_LOCAL_CHUNKS=READY_NO_INSTALL')
  $out.Add('RESULT=R86_ONEPASS_STAGED_NOT_OWNER_DEPLOYED')
}catch{
  $why=[string]$_.Exception.Message
  if($why -cnotmatch '^R86_[A-Z0-9_]{5,95}$'){$why='R86_OWNER_ENVIRONMENT_OR_REMOTE_UNVERIFIED'}
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$why)
  $out.Add('RESULT=R86_HOLD_NO_INSTALL_NO_AUTO_RETRY')
}finally{
  $out.Add('OPERATING_SPOTIFY_SPICETIFY_USER_STATE=UNCHANGED')
  $out.Add('OPERATING_BOOTSTRAP_AND_RESIDENT=UNCHANGED')
  $out.Add('PUBLIC_MAIN_VERSION_AND_GITHUB_RELEASE=UNCHANGED')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}
