# R90 HOLD: one native PowerShell 5.1 owner entry, exact v0.6.28 -> v0.6.30.
# Default inert. -Prepare verifies live owner and stages only; -Commit requires
# explicit approval, revalidates all R86 and R88 sources then executes once.
# Never publishes main, retries uncertain updates, or deletes originals.
[CmdletBinding()]
param([switch]$Prepare,[switch]$Commit,[switch]$Status,[string]$ApprovalPhrase='',
      [string]$HostedReadOnlyRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R90_SINGLE_COMMAND_PRIVATE_PREPUBLICATION_HOLD')
$out.Add('GITHUB_RELEASE=NO;AUTOMATIC_RETRY=NO;ORIGINAL_DELETE=NO')
$phase='PRE_AUTHORIZATION'
function Fail([string]$code){throw [InvalidOperationException]::new($code)}
function GitBlob([byte[]]$data){
  $hdr=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length))
  $all=New-Object byte[] ($hdr.Length+1+$data.Length)
  [Array]::Copy($hdr,0,$all,0,$hdr.Length)
  [Array]::Copy($data,0,$all,$hdr.Length+1,$data.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function FrozenSource([string]$commit,[string]$file,[string]$blob,[int]$limit){
  if($commit -cnotmatch '^[0-9a-f]{40}$' -or $blob -cnotmatch '^[0-9a-f]{40}$' -or
     $file -cnotmatch '^owner-[a-z0-9-]+-R[0-9]+-HOLD[.]ps1$' -or
     $limit -gt 100000 -or $limit -lt 1000){Fail 'R90_FROZEN_SOURCE_OUTSIDE_ALLOWLIST'}
  $url='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$commit+
    '/validation/spotify-exit-immediate-maintenance-HOLD/'+$file
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET';$req.Timeout=35000;$req.ReadWriteTimeout=35000
  $req.AllowAutoRedirect=$false;$req.KeepAlive=$false
  $response=$null
  try{
    $response=[Net.HttpWebResponse]$req.GetResponse()
    if($response.StatusCode -ne [Net.HttpStatusCode]::OK -or
       $response.ContentLength -gt $limit){Fail 'R90_REMOTE_SOURCE_NOT_PINNED_OK'}
    $stream=$response.GetResponseStream()
    $buffer=[IO.MemoryStream]::new()
    try{
      [byte[]]$chunk=New-Object byte[] 8192
      while(($n=$stream.Read($chunk,0,$chunk.Length)) -gt 0){
        if($buffer.Length+$n -gt $limit){Fail 'R90_REMOTE_SOURCE_LENGTH_EXCEEDED'}
        $buffer.Write($chunk,0,$n)
      }
      [byte[]]$bytes=$buffer.ToArray()
      if((GitBlob $bytes) -cne $blob){Fail 'R90_SOURCE_GIT_BLOB_IDENTITY_INVALID'}
      return ,$bytes
    }finally{$stream.Dispose();$buffer.Dispose()}
  }finally{if($null -ne $response){$response.Dispose()}}
}
# R93 status is observation only. No model, HTTP, child installer, process
# mutation, or recovery action runs from this branch.
function ReadOnlyFileClass([string]$p,[long]$oldLen,[string]$oldHash,
                           [long]$newLen,[string]$newHash){
  try{
    $entry=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if($entry.PSIsContainer -or
       ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      return 'NONREGULAR_OR_REPARSE'
    }
    $size=[long]$entry.Length
    if($size -ne $oldLen -and $size -ne $newLen){return 'OTHER'}
    $sha=(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($size -eq $oldLen -and $sha -ceq $oldHash){return 'BASELINE'}
    if($size -eq $newLen -and $sha -ceq $newHash){return 'CANDIDATE'}
    return 'OTHER'
  }catch [System.Management.Automation.ItemNotFoundException]{return 'ABSENT'}
   catch [System.IO.FileNotFoundException]{return 'ABSENT'}
   catch{return 'UNKNOWN'}
}
function ReadOnlyTransaction([string]$root){
  $p=Join-Path $root 'self-update-last-transaction.json'
  try{
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if($f.PSIsContainer -or
       ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       [long]$f.Length -lt 5 -or [long]$f.Length -gt 1048576){return 'UNVERIFIED'}
    $tx=(Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    if([string]$tx.status -ceq 'committed'){return 'COMMITTED_REPORTED_ONLY'}
    if([string]$tx.status -ceq 'rolled_back'){return 'ROLLED_BACK_REPORTED_ONLY'}
    return 'OTHER_OR_UNCERTAIN'
  }catch [System.Management.Automation.ItemNotFoundException]{return 'ABSENT'}
   catch [System.IO.FileNotFoundException]{return 'ABSENT'}
   catch{return 'UNKNOWN'}
}
function ReadOnlyResident([string]$scriptPath){
  try{
    $watch=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
    $quoted=[regex]::Escape($scriptPath)
    $exact=@($watch | Where-Object {
      [string]$_.CommandLine -match ('(?i)(^|[\s"])'+$quoted+'(?=$|[\s"])')
    })
    if($exact.Count -eq 0){return 'NO_MATCH'}
    if($exact.Count -ne 1){return 'MULTIPLE_MATCH'}
    $p=$exact[0]
    $expected=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\wscript.exe'))
    if(-not [string]::Equals([IO.Path]::GetFullPath([string]$p.ExecutablePath),
            $expected,[StringComparison]::OrdinalIgnoreCase)){
      return 'ONE_PATH_IMAGE_UNVERIFIED'
    }
    $owner=(Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop)
    if([int]$owner.ReturnValue -ne 0 -or
       [string]$owner.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
      return 'ONE_PATH_OWNER_UNVERIFIED'
    }
    return 'ONE_OWNER_PATH_OBSERVED_CODE_NOT_ATTESTED'
  }catch{return 'UNKNOWN'}
}
try{
  if($Status){
    $phase='R93_READONLY_POSTFLIGHT'
    if($Prepare -or $Commit -or $ApprovalPhrase -cne ''){
      Fail 'R93_STATUS_CANNOT_AUTHORIZE_OR_PREPARE'
    }
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $PSVersionTable.PSEdition -cne 'Desktop' -or
       $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
      Fail 'R93_STATUS_WINDOWS_PS51_X64_REQUIRED'
    }
    $scope='ACTUAL_USER_READONLY'
    if(-not [string]::IsNullOrWhiteSpace($HostedReadOnlyRoot)){
      if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
         $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
         [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        Fail 'R93_HOSTED_ROOT_NOT_ALLOWED'
      }
      $root=[IO.Path]::GetFullPath($HostedReadOnlyRoot).TrimEnd('\','/')
      $tmp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
      if(-not $root.StartsWith(($tmp+'\'),[StringComparison]::OrdinalIgnoreCase) -or
         [IO.Path]::GetFileName($root) -cne 'SpotifyControl'){
        Fail 'R93_HOSTED_ROOT_OUTSIDE_RUNNER_SCRATCH'
      }
      $scope='HOSTED_SCRATCH_ONLY'
    }else{
      $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData)).TrimEnd('\','/')
      $root=Join-Path $local 'SpotifyControl'
    }
    $out.Add('R93_OBSERVATION_SCOPE='+$scope)
    $out.Add('R93_NETWORK=NO;FILE_WRITE=NO;PROCESS_CHANGE=NO;RETRY=NO')
    $appRoot=Get-Item -LiteralPath $root -Force -ErrorAction Stop
    $bin=Join-Path $root 'bin'
    $binItem=Get-Item -LiteralPath $bin -Force -ErrorAction Stop
    if(-not $appRoot.PSIsContainer -or -not $binItem.PSIsContainer -or
       ($appRoot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       ($binItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      Fail 'R93_ROOT_NONREGULAR_OR_REPARSE'
    }
    $mainClass=ReadOnlyFileClass (Join-Path $bin 'spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0' 294101 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
    $agentClass=ReadOnlyFileClass (Join-Path $bin 'spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278' 13308 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
    $addonClass=ReadOnlyFileClass (Join-Path $bin 'addon-manager.ps1') 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285' 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
    $bootClass=ReadOnlyFileClass (Join-Path $root 'bootstrap\spotify-control-self-updater.ps1') 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6' 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
    $resident=ReadOnlyResident (Join-Path $bin 'spotify-control-agent.vbs')
    $journal=ReadOnlyTransaction $root
    $out.Add('R93_MAIN_HASH_CLASS='+$mainClass)
    $out.Add('R93_AGENT_HASH_CLASS='+$agentClass)
    $out.Add('R93_ADDON_HASH_CLASS='+$addonClass)
    $out.Add('R93_OFFICIAL_BOOTSTRAP_HASH_CLASS='+$bootClass)
    $out.Add('R93_RESIDENT='+$resident)
    $out.Add('R93_TRANSACTION='+$journal)
    $ready='UNKNOWN'
    try{
      $localParent=[IO.Path]::GetDirectoryName($root)
      $stages=@(Get-ChildItem -LiteralPath $localParent -Directory -Force -Filter 'SpotifyControlCanary-offline-ready-*' -ErrorAction Stop)
      $ready=if($stages.Count -eq 0){'NONE'}elseif($stages.Count -eq 1){'ONE'}else{'MULTIPLE'}
    }catch{}
    $out.Add('R93_PRIVATE_STAGE_COUNT='+$ready)
    $classification='HOLD_INDETERMINATE_NO_RETRY'
    if($addonClass -ceq 'BASELINE' -and $bootClass -ceq 'BASELINE'){
      if($mainClass -ceq 'BASELINE' -and $agentClass -ceq 'BASELINE'){
        $classification='BASELINE_FILES_EXACT_RESIDENT_UNATTESTED'
      }elseif($mainClass -ceq 'CANDIDATE' -and $agentClass -ceq 'CANDIDATE'){
        if($journal -ceq 'COMMITTED_REPORTED_ONLY' -and
           $resident -ceq 'ONE_OWNER_PATH_OBSERVED_CODE_NOT_ATTESTED'){
          $classification='CANDIDATE_FILES_COMMITTED_RESIDENT_CODE_UNATTESTED'
        }else{
          $classification='HOLD_CANDIDATE_FILES_JOURNAL_OR_RESIDENT_UNVERIFIED'
        }
      }elseif($mainClass -cin @('BASELINE','CANDIDATE') -and
               $agentClass -cin @('BASELINE','CANDIDATE')){
        $classification='HOLD_MIXED_VERSIONS_NO_RETRY'
      }
    }
    $out.Add('R93_CLASSIFICATION='+$classification)
    $out.Add('R93_AGENT_IN_MEMORY_VERSION=NOT_PROVEN')
    $out.Add('R93_RECOVERY_APPLY=NO;AUTO_REPAIR=NO')
    $out.Add('RESULT=R93_READONLY_POSTFLIGHT_COLLECTED')
  }else{
    if(-not [string]::IsNullOrWhiteSpace($HostedReadOnlyRoot)){
      Fail 'R93_HOSTED_READONLY_ROOT_FORBIDDEN_OUTSIDE_STATUS'
    }
    if($Prepare -and $Commit){Fail 'R90_PREPARE_COMMIT_MUST_BE_SEPARATE'}
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE'){
    Fail 'R90_EXACT_OWNER_APPROVAL_REQUIRED'
  }
  if(-not $Commit -and -not $Prepare){
    $out.Add('NETWORK=NO;FILES_CHANGED=NO;PROCESSES_CHANGED=NO')
    $out.Add('RESULT=R90_INERT_DEFAULT_REQUIRES_APPROVED_MODE')
  }else{
    $phase='REAL_OWNER_PREFLIGHT'
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $PSVersionTable.PSEdition -cne 'Desktop' -or
       $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
      Fail 'R90_OWNER_WINDOWS_PS51_X64_REQUIRED'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
       [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'R90_NON_ELEVATED_OWNER_REQUIRED'
    }
    $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)).TrimEnd('\','/')
    if([string]::IsNullOrWhiteSpace($local) -or -not [IO.Directory]::Exists($local)){
      Fail 'R90_ACTUAL_LOCALAPPDATA_NOT_VERIFIED'
    }
    $installed=Join-Path $local 'SpotifyControl\bin\spotify-control.ps1'
    try{
      $file=Get-Item -LiteralPath $installed -Force -ErrorAction Stop
      if($file.PSIsContainer -or
         ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         [long]$file.Length -ne 284321 -or
         (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash.ToLowerInvariant() -cne
           'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'){
        Fail 'R90_OWNER_CURRENT_STABLE_MAIN_NOT_EXACT'
      }
    }catch [System.Management.Automation.ItemNotFoundException]{
      Fail 'R90_OWNER_STABLE_MAIN_ABSENT'
    }
    if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
      Fail 'R90_SPOTIFY_MUST_BE_CLOSED'
    }
    # Reuse one private stage instead of accumulating fresh GUID folders.
    $phase='PRIVATE_STAGE_DISCOVERY'
    $existing=@(Get-ChildItem -LiteralPath $local -Directory -Filter 'SpotifyControlCanary-offline-ready-*' -Force -ErrorAction Stop)
    if($existing.Count -gt 1){Fail 'R90_MULTIPLE_PRIVATE_READY_CANDIDATES_HOLD'}
    $reuse=($existing.Count -eq 1)
    $phase='PINNED_SOURCE_RETRIEVAL'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    [byte[]]$r88=$null
    if($Commit -or $reuse){
      $r88=FrozenSource '4e8a4d7b0d85d43de373baddb3fbb9495d26a534' 'owner-approved-private-offline-R88-HOLD.ps1' '761dcd5a94c70af7b9defe5051df7ecfcd00fde9' 90000
    }
    if($reuse){
      $stage=$existing[0].FullName
      if($existing[0].Name -cnotmatch '^SpotifyControlCanary-offline-ready-[0-9a-f]{32}$'){
        Fail 'R90_EXISTING_PRIVATE_STAGE_NAME_UNVERIFIED'
      }
      $stageId=$existing[0].Name.Substring('SpotifyControlCanary-offline-ready-'.Length)
      $out.Add('R90_EXISTING_PRIVATE_STAGE=ONE_EXACT_CANDIDATE_REUSED')
      if($Prepare){
        $phase='R88_REUSED_STAGE_READONLY_VERIFICATION'
        $plan=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r88))) -PrivateOfflineReadyPath $stage)
        if($plan -cnotcontains 'RESULT=READY_FOR_PRIVATE_OFFLINE_ONESHOT_NO_MUTATION' -or
           $plan -cnotcontains 'R88_IMMUTABLE_PRIVATE_LOCAL_21_CHUNKS_AND_BOOTSTRAP=VERIFIED'){
          Fail 'R90_REUSED_PRIVATE_STAGE_NOT_ADMITTED'
        }
        $out.Add('R90_REUSED_STAGE_R88_READONLY_ADMISSION=PASS')
      }
    }else{
      [byte[]]$r86=FrozenSource '0285fdfd018d926d7cd8115b72767b384e17da9c' 'owner-onepass-offline-stage-R86-HOLD.ps1' '4b6f86bb85a6ce7e3cc1309e723b7a8edc21d078' 20000
      $phase='R86_VERIFIED_STAGE'
      $r86Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r86))))
      if($r86Result -cnotcontains 'RESULT=R86_ONEPASS_STAGED_NOT_OWNER_DEPLOYED' -or
         $r86Result -cnotcontains 'R86_R85_DISPOSABLE_BOOTSTRAP_AND_LOCAL_CHUNKS=READY_NO_INSTALL'){
        Fail 'R90_R86_OWNER_PREPARATION_HOLD'
      }
      $ids=@($r86Result|Where-Object {$_ -cmatch '^R86_OFFLINE_PRIVATE_STAGE_ID=[0-9a-f]{32}$'})
      if($ids.Count -ne 1){Fail 'R90_OWNER_OFFLINE_STAGE_ID_NOT_UNIQUE'}
      $stageId=([string]$ids[0]).Split('=')[1]
      $stage=Join-Path $local ('SpotifyControlCanary-offline-ready-'+$stageId)
      $out.Add('R90_R86_NEW_PRIVATE_STAGE=VERIFIED')
    }
    $stageInfo=Get-Item -LiteralPath $stage -Force -ErrorAction Stop
    if(-not $stageInfo.PSIsContainer -or
       ($stageInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      Fail 'R90_STAGE_NOT_OWNED_DIRECTORY'
    }
    $out.Add('R90_IMMUTABLE_PRIVATE_STAGE_SELECTED=ONE')
    if($Prepare){
      $out.Add('R90_PRIVATE_STAGE_ID='+$stageId)
      $out.Add('RESULT=R90_PREPARED_WITHOUT_OPERATING_UPDATE')
    }else{
      $phase='R88_ACTUAL_OWNER_ONESHOT'
      $r88Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r88))) -PrivateOfflineReadyPath $stage -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')
      if($r88Result -cnotcontains 'RESULT=OWNER_APPROVED_PRIVATE_OFFLINE_ONESHOT_COMMITTED' -or
         $r88Result -cnotcontains 'R88_OFFICIAL_INSTALLED_BOOTSTRAP=UNCHANGED_PINNED' -or
         $r88Result -cnotcontains 'NEW_RELEASE_VBS=ONE_EXACT_OWNER_RESIDENT_RUNNING' -or
         $r88Result -cnotcontains 'USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL'){
        Fail 'R90_R88_OWNER_ONESHOT_NOT_PROVEN'
      }
      $out.Add('R90_R88_SINGLE_OWNER_RESIDENT_AND_BOOTSTRAP_ORIGINAL=VERIFIED')
      $out.Add('RESULT=R90_EXACT_PRIVATE_OWNER_CUTOVER_COMMITTED')
    }
  }
  }
}catch{
  $why=[string]$_.Exception.Message
  if($Status){
    if($why -cnotmatch '^R93_[A-Z0-9_]{5,90}$'){
      $why='R93_READONLY_OBSERVATION_UNVERIFIED'
    }
  }elseif($why -cnotmatch '^R90_[A-Z0-9_]{5,90}$'){
    $why='R90_OWNER_ENVIRONMENT_OR_REMOTE_UNVERIFIED'
  }
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$why)
  $out.Add($(if($Status){'RESULT=R93_HOLD_READONLY_NO_CHANGES'}else{'RESULT=R90_HOLD_NO_AUTO_RETRY'}))
}finally{
  $out.Add('PUBLIC_MAIN_RELEASE_UNCHANGED=YES')
  $out.Add('OWNER_ORIGINAL_DELETE=NO;AUTO_RETRY=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}
