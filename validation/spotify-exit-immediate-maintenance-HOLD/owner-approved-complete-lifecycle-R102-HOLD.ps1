# R102 HOLD: One explicitly approved owner transaction for the already verified
# private v0.6.30 R90 cutover followed by R99 guarded logon registration.
# Never invokes public releases, replaces the installed official Bootstrap,
# changes user settings itself, or auto-retries uncertain mutations.
# R90 and R99 own their respective writes; R102 refuses to auto-rollback an
# already committed release if logon registration subsequently fails.
[CmdletBinding()]
param([switch]$Prepare,[switch]$Commit,[string]$ApprovalPhrase='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$phase='AUTHORIZATION'
$releaseCommitted=$false
$guardRegistered=$false
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R102_APPROVED_PRIVATE_RELEASE_AND_GUARDED_LOGON_HOLD')
$out.Add('PUBLIC_MAIN_RELEASE=UNCHANGED;AUTO_RETRY=NO;ORIGINAL_USER_DELETE=NO')
function Deny([string]$reason){throw [InvalidOperationException]::new($reason)}
function GitBlob([byte[]]$data){
  [byte[]]$prefix=[Text.Encoding]::ASCII.GetBytes('blob '+$data.Length)
  [byte[]]$bytes=New-Object byte[] ($prefix.Length+1+$data.Length)
  [Array]::Copy($prefix,0,$bytes,0,$prefix.Length)
  [Array]::Copy($data,0,$bytes,$prefix.Length+1,$data.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function Frozen([string]$commit,[string]$filename,[string]$object,[int]$limit){
  if($commit -cnotmatch '^[a-f0-9]{40}$' -or $object -cnotmatch '^[a-f0-9]{40}$' -or
     $filename -cnotmatch '^owner-[a-z0-9-]+-R(?:90|99|101)-HOLD[.]ps1$' -or
     $limit -lt 10000 -or $limit -gt 80000){Deny 'R102_SOURCE_ALLOWLIST_HOLD'}
  $url='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$commit+
       '/validation/spotify-exit-immediate-maintenance-HOLD/'+$filename
  $request=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $request.Method='GET'
  $request.Timeout=35000
  $request.ReadWriteTimeout=35000
  $request.AllowAutoRedirect=$false
  $request.KeepAlive=$false
  $response=$null
  try{
    $response=[Net.HttpWebResponse]$request.GetResponse()
    if($response.StatusCode -ne [Net.HttpStatusCode]::OK -or
       $response.ContentLength -gt $limit){Deny 'R102_SOURCE_RESPONSE_HOLD'}
    $stream=$response.GetResponseStream()
    $memory=[IO.MemoryStream]::new()
    try{
      [byte[]]$buffer=New-Object byte[] 8192
      while(($n=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
        if($memory.Length+$n -gt $limit){Deny 'R102_SOURCE_TOO_LARGE'}
        $memory.Write($buffer,0,$n)
      }
      [byte[]]$actual=$memory.ToArray()
      if((GitBlob $actual) -cne $object){Deny 'R102_SOURCE_GIT_OBJECT_MISMATCH'}
      return ,$actual
    }finally{$memory.Dispose();$stream.Dispose()}
  }finally{if($null -ne $response){$response.Dispose()}}
}
function RequireOnce([object[]]$rows,[string]$value){
  if(@($rows | Where-Object {[string]$_ -ceq $value}).Count -ne 1){
    Deny 'R102_REQUIRED_RESULT_NOT_EXACT'
  }
}
function RequireOneResult([object[]]$rows){
  if(@($rows | Where-Object {[string]$_ -cmatch '^RESULT='}).Count -ne 1){
    Deny 'R102_RESULT_RECEIPT_COUNT_INVALID'
  }
}
try{
  if($Prepare -and $Commit){Deny 'R102_MODES_MUTUALLY_EXCLUSIVE'}
  if($Commit){
    if($ApprovalPhrase -cne 'APPROVE_PRIVATE_V0630_AND_GUARDED_LOGON_ONCE'){
      Deny 'R102_EXPLICIT_DUAL_SCOPE_OWNER_APPROVAL_REQUIRED'
    }
  }elseif($ApprovalPhrase -cne ''){Deny 'R102_APPROVAL_WITHOUT_COMMIT_FORBIDDEN'}
  if(-not($Prepare -or $Commit)){
    $out.Add('NETWORK=NO;FILE_WRITE=NO;PROCESS_CHANGE=NO;STARTUP_CHANGE=NO')
    $out.Add('RESULT=R102_INERT_DEFAULT_REQUIRES_EXPLICIT_MODE')
  }else{
    $phase='OWNER_ENVIRONMENT'
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $PSVersionTable.PSEdition -cne 'Desktop' -or
       $PSVersionTable.PSVersion.Major -ne 5 -or
       -not [Environment]::Is64BitProcess){Deny 'R102_WINDOWS_PS51_X64_REQUIRED'}
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
         [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Deny 'R102_ELEVATED_OWNER_NOT_ALLOWED'
    }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $phase='IMMUTABLE_SOURCE_ADMISSION'
    $ref='504b96e90902cab5b11b5943921a5802b13d1e43'
    [byte[]]$r101=Frozen $ref 'owner-unified-readonly-preflight-R101-HOLD.ps1' 'f3e36f05979f8cd5987b5ca8c9de0774b07b3a8d' 70000
    [byte[]]$r90=Frozen $ref 'owner-single-command-offline-R90-HOLD.ps1' '52d97d536fe60c3833022e1d3e88a6b26eacddb3' 32000
    [byte[]]$r99=$null
    if($Commit){
      $r99=Frozen $ref 'owner-approved-guarded-logon-R99-HOLD.ps1' '7e78129d598bd11c273b5855f4059393767c5f85' 28000
    }
    $out.Add('R102_FROZEN_R101_R90'+$(if($Commit){'_R99'}else{''})+'=GIT_OBJECTS_EXACT')
    $phase='LIVE_BASELINE_R101_READONLY'
    $before=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r101))))
    RequireOneResult $before
    RequireOnce $before 'RESULT=R101_OFFLINE_READONLY_EVIDENCE_COLLECTED'
    RequireOnce $before 'R101_OVERALL=BASELINE_CONSISTENT_OWNER_REVIEW_NOT_DEPLOY_AUTHORITY'
    RequireOnce $before 'R101_INSTALLED_STAGE=BASELINE_V0628_FILES_EXACT'
    RequireOnce $before 'R101_R100_R99_GUARDED_LOGON=NONE'
    RequireOnce $before 'R101_DEPLOY_AUTHORIZED=NO;AUTO_REPAIR=NO;AUTO_RETRY=NO'
    $out.Add('R102_CURRENT_OWNER_BASELINE=READONLY_CONSISTENT_NOT_DEPLOY_AUTHORITY')
    if($Prepare){
      $phase='R90_PREPARE_PRIVATE_STAGE'
      $staged=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r90))) -Prepare)
      RequireOneResult $staged
      RequireOnce $staged 'RESULT=R90_PREPARED_WITHOUT_OPERATING_UPDATE'
      $out.Add('R102_PRIVATE_STAGE=R90_PREPARED_NOT_INSTALLED')
      $out.Add('RESULT=R102_PREPARED_NO_RELEASE_OR_LOGON_CHANGE')
    }else{
      $phase='R90_EXPLICIT_RELEASE_COMMIT'
      $updated=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r90))) -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')
      RequireOneResult $updated
      RequireOnce $updated 'RESULT=R90_EXACT_PRIVATE_OWNER_CUTOVER_COMMITTED'
      RequireOnce $updated 'R90_R88_SINGLE_OWNER_RESIDENT_AND_BOOTSTRAP_ORIGINAL=VERIFIED'
      $releaseCommitted=$true
      $out.Add('R102_RELEASE=R90_COMMITTED_REPORTED_ONLY')
      # Check the installed version before adding any logon startup entry.
      $phase='R90_CANDIDATE_POSTFLIGHT'
      $status=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r90))) -Status)
      RequireOneResult $status
      RequireOnce $status 'RESULT=R93_READONLY_POSTFLIGHT_COLLECTED'
      RequireOnce $status 'R93_CLASSIFICATION=CANDIDATE_FILES_COMMITTED_RESIDENT_CODE_UNATTESTED'
      RequireOnce $status 'R100_R99_GUARDED_LOGON=NONE'
      $phase='R99_APPROVED_GUARDED_LOGON_REGISTRATION'
      $startup=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r99))) -Commit -ApprovalPhrase 'APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE')
      RequireOneResult $startup
      RequireOnce $startup 'RESULT=R99_EXPLICIT_OWNER_LOGON_LINK_REGISTERED'
      RequireOnce $startup 'R99_COMMIT_RESULT=ONE_GUARDED_USER_STARTUP_LINK_CREATED_NOT_LAUNCHED'
      $guardRegistered=$true
      $out.Add('R102_GUARDED_LOGON=R99_OWNER_LINK_CREATED_NOT_LOGON_PROVEN')
      $phase='R101_FINAL_INDEPENDENT_READONLY_POSTFLIGHT'
      $after=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r101))))
      RequireOneResult $after
      RequireOnce $after 'RESULT=R101_OFFLINE_READONLY_EVIDENCE_COLLECTED'
      RequireOnce $after 'R101_INSTALLED_STAGE=CANDIDATE_V0630_FILES_EXACT'
      RequireOnce $after 'R101_R100_R99_GUARDED_LOGON=ONE_OWNED_GUARDED_REGISTERED_NOT_LOGON_PROOF'
      RequireOnce $after 'R101_OVERALL=CANDIDATE_FILES_GUARDED_LINK_CONSISTENT_REAL_LOGON_UNTESTED'
      $out.Add('R102_FINAL_OWNER_FILE_AND_GUARDED_LINK=READONLY_CONSISTENT')
      $out.Add('RESULT=R102_RELEASE_AND_GUARDED_LOGON_COMMITTED_REAL_REBOOT_UNTESTED')
    }
  }
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^R102_[A-Z0-9_]{5,100}$'){
    $reason='R102_OWNER_ENVIRONMENT_OR_NESTED_OPERATION_HOLD'
  }
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$reason)
  if($releaseCommitted){
    $out.Add('R102_RELEASE=COMMITTED_REPORTED_POSTCOMMIT_REVIEW_REQUIRED')
    $out.Add('R102_GUARDED_LOGON='+$(if($guardRegistered){'REGISTERED_REPORTED_READBACK_UNCERTAIN'}else{'NOT_CONFIRMED'}))
    $out.Add('RESULT=R102_PARTIAL_POSTCOMMIT_HOLD_NO_AUTOROLLBACK')
  }else{
    $out.Add('RESULT=R102_HOLD_NO_AUTO_RETRY')
  }
}finally{
  $out.Add('R102_REAL_WINDOWS_REBOOT_AND_LOGON=NOT_TESTED')
  $out.Add('R102_AUTO_ROLLBACK=NO;AUTO_RETRY=NO;DEPLOY=EXPLICIT_APPROVAL_ONLY')
  $out.Add('RAW_PATHS_SECRETS_PID_AND_PROCESS_ARGS_OUTPUT=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}