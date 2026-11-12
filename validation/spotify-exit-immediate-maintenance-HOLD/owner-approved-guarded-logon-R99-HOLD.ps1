# R99 HOLD: standalone owner-only logon startup registration for exact
# private v0.6.30 WScript resident AFTER the separately approved R90 cutover.
# Default = read-only plan. The only mutating actions are explicit,
# single-use owner-approved Create/Remove with exact-owned receipt verification.
# Never changes Spotify, Spicetify, state.json, updater/guard ACL, registry,
# scheduled tasks, other programs/shortcuts, or launches/kills a process.
[CmdletBinding()]
param([switch]$Commit,[switch]$Remove,[string]$ApprovalPhrase='',
      [string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R99_OWNER_LOGON_REGISTRATION_HOLD')
$out.Add('SPOTIFY_PROCESS_CHANGE=NO;UPDATE=NO;REGISTRY_WRITE=NO;SCHEDULED_TASK_WRITE=NO')
$out.Add('AUTO_START_EXECUTION=NOT_TESTED;ORIGINAL_USER_LINKS=UNCHANGED')
$phase='AUTHORIZATION'
function Deny([string]$reason){throw [InvalidOperationException]::new($reason)}
function Hash([string]$path){
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function PlainFile([string]$path){
  try{
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return (-not $item.PSIsContainer -and
      ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function PlainDir([string]$path){
  try{
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return ($item.PSIsContainer -and
      ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function MatchPinned([string]$path,[long]$length,[string]$sha){
  if(-not(PlainFile $path)){return $false}
  if([long](Get-Item -LiteralPath $path -Force).Length -ne $length){return $false}
  return (Hash $path) -ceq $sha
}
function ExaminedNone([string]$value){
  return $value -ceq 'NONE_IN_EXAMINED_SCOPE'
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
function R95IsExactWScriptArgs([string]$arguments,[string]$agent){
  $v=[string]$arguments
  $v=$v.Trim()
  $quoted='"'+$agent+'"'
  return ($v -ceq $quoted -or
          $v -ceq ('//B //NoLogo '+$quoted) -or
          $v -ceq ('//NoLogo //B '+$quoted))
}
function R95Class([int]$count,[bool]$unverified){
  if($count -gt 1){return 'MULTIPLE_EXACT_ROUTES'}
  if($count -eq 1 -and $unverified){return 'ONE_EXACT_PLUS_UNVERIFIED'}
  if($count -eq 1){return 'ONE_EXACT_REGISTERED_NOT_EXECUTION_PROOF'}
  if($unverified){return 'UNVERIFIED'}
  return 'NONE_IN_EXAMINED_SCOPE'
}
function R95Shortcuts([string[]]$folders,[string]$agent,[string]$wscript){
  $count=0
  $unverified=$false
  $shell=$null
  try{
    $shell=New-Object -ComObject WScript.Shell -ErrorAction Stop
    foreach($folder in $folders){
      if([string]::IsNullOrWhiteSpace($folder)){$unverified=$true;continue}
      if(-not(Test-Path -LiteralPath $folder -PathType Container)){
        $unverified=$true;continue
      }
      $d=Get-Item -LiteralPath $folder -Force -ErrorAction Stop
      if(($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        $unverified=$true;continue
      }
      foreach($f in @(Get-ChildItem -LiteralPath $folder -File -Force -Filter '*.lnk' -ErrorAction Stop)){
        if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
          $unverified=$true;continue
        }
        try{
          $link=$shell.CreateShortcut($f.FullName)
          if([string]::Equals([string]$link.TargetPath,$wscript,[StringComparison]::OrdinalIgnoreCase) -and
             (R95IsExactWScriptArgs ([string]$link.Arguments) $agent)){
            $count++
          }elseif(([string]$link.Arguments).IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -ge 0){
            $unverified=$true
          }
        }catch{$unverified=$true}
      }
    }
    return (R95Class $count $unverified)
  }catch{return 'UNKNOWN'}
}
function R95RunRegistry([string]$agent,[string]$wscript){
  $count=0;$unverified=$false
  $keys=@('Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run',
          'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run',
          'Registry::HKEY_LOCAL_MACHINE\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run')
  foreach($key in $keys){
    try{
      if(-not(Test-Path -LiteralPath $key)){$unverified=$true;continue}
      $values=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
      foreach($property in $values.PSObject.Properties){
        if(-not($property.Value -is [string])){continue}
        $v=[string]$property.Value
        if($v.IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        # The target can also be enclosed in double quotes; require exact
        # WScript + script only, not a wrapper or altered command.
        $cmd=$v.Trim()
        $exact=$false
        foreach($exe in @($wscript,('"'+$wscript+'"'))){
          if($cmd.StartsWith(($exe+' '),[StringComparison]::OrdinalIgnoreCase) -and
             (R95IsExactWScriptArgs ($cmd.Substring($exe.Length).Trim()) $agent)){
            $exact=$true;break
          }
        }
        if($exact){$count++}else{$unverified=$true}
      }
    }catch{$unverified=$true}
  }
  return (R95Class $count $unverified)
}
function R95ScheduledLogon([string]$agent,[string]$wscript){
  $count=0;$unverified=$false
  try{
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $name=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $tasks=@(Get-ScheduledTask -ErrorAction Stop)
    foreach($t in $tasks){
      if([string]$t.State -ceq 'Disabled'){continue}
      $validTriggers=@($t.Triggers | Where-Object {
        $null -ne $_ -and [string]$_.CimClass.CimClassName -ceq 'MSFT_TaskLogonTrigger' -and
        $_.Enabled -ne $false
      })
      if($validTriggers.Count -eq 0){continue}
      $user=[string]$t.Principal.UserId
      $actions=@($t.Actions)
      foreach($a in $actions){
        if($null -eq $a){continue}
        $arguments=[string]$a.Arguments
        if($arguments.IndexOf($agent,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        if($actions.Count -ne 1 -or
           -not [string]::Equals([string]$a.Execute,$wscript,[StringComparison]::OrdinalIgnoreCase) -or
           -not(R95IsExactWScriptArgs $arguments $agent) -or
           ($user -cne $sid -and
            -not [string]::Equals($user,$name,[StringComparison]::OrdinalIgnoreCase))){
          $unverified=$true;continue
        }
        $count++
      }
    }
    return (R95Class $count $unverified)
  }catch{return 'UNKNOWN'}
}
# R99 one-time owner-approved installation of the *exact* audited R98
# guarded launcher, pinned to immutable Git commit and Git blob object ID.
# The real Windows logon has no network dependency: guard is local.
function GitBlob([byte[]]$data){
  $hdr=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length))
  $all=New-Object byte[] ($hdr.Length+1+$data.Length)
  [Array]::Copy($hdr,0,$all,0,$hdr.Length)
  [Array]::Copy($data,0,$all,$hdr.Length+1,$data.Length)
  $sha=[Security.Cryptography.SHA1]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function R99ImmutableGuard(){
  $url='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+
       '6af4c396e05343c6e34c1ffd3104a22675be9943'+
       '/validation/spotify-exit-immediate-maintenance-HOLD/owner-single-resident-logon-guard-R98-HOLD.ps1'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET';$req.Timeout=35000;$req.ReadWriteTimeout=35000
  $req.AllowAutoRedirect=$false;$req.KeepAlive=$false
  $response=$null
  try{
    $response=[Net.HttpWebResponse]$req.GetResponse()
    if($response.StatusCode -ne [Net.HttpStatusCode]::OK -or
       $response.ContentLength -gt 12000){Deny 'R99_IMMUTABLE_GUARD_HTTP_UNVERIFIED'}
    $stream=$response.GetResponseStream()
    $bytes=[IO.MemoryStream]::new()
    try{
      [byte[]]$buf=New-Object byte[] 4096
      while(($n=$stream.Read($buf,0,$buf.Length)) -gt 0){
        if($bytes.Length+$n -gt 12000){Deny 'R99_GUARD_TOO_LARGE'}
        $bytes.Write($buf,0,$n)
      }
      [byte[]]$got=$bytes.ToArray()
      if($got.Length -lt 6000 -or (GitBlob $got) -cne
         '08e5bf6631f8d2e8e1374619557d1ee4463c2b5c'){
        Deny 'R99_PINNED_R98_GUARD_GIT_OBJECT_CHANGED'
      }
      return ,$got
    }finally{$stream.Dispose();$bytes.Dispose()}
  }finally{if($null -ne $response){$response.Dispose()}}
}
function R99GuardArgs([string]$guard,[string]$root,[bool]$hosted){
  $guardArguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$guard+'"'
  if($hosted){$guardArguments+=' -HostedFixtureRoot "'+$root+'"'}
  return $guardArguments
}
function R99GuardRoutes([string[]]$folders,[string]$guard,[string]$own){
  $match=0;$foreign=$false
  try{
    $shell=New-Object -ComObject WScript.Shell -ErrorAction Stop
    foreach($d in $folders){
      foreach($f in @(Get-ChildItem -LiteralPath $d -File -Force -Filter '*.lnk' -ErrorAction Stop)){
        if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$foreign=$true;continue}
        try{
          $lnk=$shell.CreateShortcut($f.FullName)
          if(([string]$lnk.Arguments).IndexOf($guard,[StringComparison]::OrdinalIgnoreCase) -ge 0){
            if([string]::Equals($f.FullName,$own,[StringComparison]::OrdinalIgnoreCase)){$match++}
            else{$foreign=$true}
          }
        }catch{$foreign=$true}
      }
    }
  }catch{return 'UNKNOWN'}
  if($match -eq 0 -and -not $foreign){return 'NONE'}
  if($match -eq 1 -and -not $foreign){return 'ONE_OWNED'}
  return 'AMBIGUOUS'
}
function OwnerReceipt([string]$linkHash,[string]$sid,[string]$guardHash){
  $obj=[ordered]@{
    schema='SPOTIFY_R99_OWNER_EXACT_STARTUP_LINK_V1'
    owner_sid=$sid
    link_sha256=$linkHash
    guard_sha256=$guardHash
    installed_main_sha256='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
    installed_agent_sha256='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
  }
  return ($obj|ConvertTo-Json -Compress)
}
function OwnedLink([string]$path,[string]$guard,[string]$powershell,[string]$guardArguments,[string]$root){
  if(-not (PlainFile $path)){return $false}
  try{
    $sh=New-Object -ComObject WScript.Shell -ErrorAction Stop
    $lk=$sh.CreateShortcut($path)
    return (
      [string]::Equals([string]$lk.TargetPath,$powershell,[StringComparison]::OrdinalIgnoreCase) -and
      [string]$lk.Arguments -ceq $guardArguments -and
      [string]::Equals([string]$lk.WorkingDirectory,$root,[StringComparison]::OrdinalIgnoreCase)
    )
  }catch{return $false}
}
try{
  if($Commit -and $Remove){Deny 'R99_MUTATION_MODES_MUTUALLY_EXCLUSIVE'}
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE'){
    Deny 'R99_CREATE_EXPLICIT_APPROVAL_REQUIRED'
  }
  if($Remove -and $ApprovalPhrase -cne 'APPROVE_REMOVE_ONLY_R99_OWNED_LOGON_SHORTCUT_ONCE'){
    Deny 'R99_REMOVE_EXPLICIT_APPROVAL_REQUIRED'
  }
  if(-not ($Commit -or $Remove) -and $ApprovalPhrase -cne ''){
    Deny 'R99_PLAN_WITH_APPROVAL_NOT_ALLOWED'
  }
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    Deny 'R99_WIN64_PS51_REQUIRED'
  }
  $user=[Security.Principal.WindowsIdentity]::GetCurrent()
  $sid=$user.User.Value
  $hosted=(-not [string]::IsNullOrEmpty($HostedFixtureRoot))
  if($hosted){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      Deny 'R99_TEST_FIXTURE_NOT_GITHUB_HOSTED'
    }
    $root=[IO.Path]::GetFullPath($HostedFixtureRoot).TrimEnd('\','/')
    $tmp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $root.StartsWith(($tmp+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -cne 'SpotifyControl'){
      Deny 'R99_FIXTURE_OUTSIDE_EXCLUSIVE_RUNNER_TEMP'
    }
    $startup=Join-Path ([IO.Path]::GetDirectoryName($root)) 'R99UserStartup'
    $common=Join-Path ([IO.Path]::GetDirectoryName($root)) 'R99CommonStartup'
    $scope='HOSTED_SYNTHETIC_ONLY'
  }else{
    if(([Security.Principal.WindowsPrincipal]::new($user)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Deny 'R99_OWNER_MUST_NOT_RUN_ELEVATED'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $startup=[Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
    $scope='OWNER_CURRENT_USER_ONLY'
  }
  $out.Add('R99_SCOPE='+$scope)
  $phase='OWNER_EXACT_PRIVATE_RELEASE'
  $bin=Join-Path $root 'bin'
  if(-not(PlainDir $root) -or -not(PlainDir $bin) -or
     -not(PlainDir $startup) -or -not(PlainDir $common)){
    Deny 'R99_OWNER_ROOT_OR_STARTUP_DIRECTORY_UNVERIFIED'
  }
  $main=Join-Path $bin 'spotify-control.ps1'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $addon=Join-Path $bin 'addon-manager.ps1'
  $boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $guard=Join-Path $root 'owner-guard-r99.ps1'
  if(-not(MatchPinned $main 294101 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d') -or
     -not(MatchPinned $agent 13308 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5') -or
     -not(MatchPinned $addon 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
     -not(MatchPinned $boot 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6') -or
     -not(PlainFile $wscript) -or -not(PlainFile $powershell)){
    Deny 'R99_EXACT_NEW_MAIN_VBS_ADDON_BOOTSTRAP_REQUIRED'
  }
  $journal=Join-Path $root 'self-update-last-transaction.json'
  if(-not(PlainFile $journal) -or (Get-Item -LiteralPath $journal).Length -gt 1048576){
    Deny 'R99_OWNER_COMMIT_JOURNAL_NOT_VERIFIABLE'
  }
  $transaction=Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json -ErrorAction Stop
  if([string]$transaction.status -cne 'committed'){
    Deny 'R99_R90_OWNER_COMMITTED_RELEASE_REQUIRED'
  }
  $resident=ReadOnlyResident $agent
  $out.Add('R99_RESIDENT='+$resident)
  if($resident -cnotin @('ONE_OWNER_PATH_OBSERVED_CODE_NOT_ATTESTED','NO_MATCH')){
    Deny 'R99_CURRENT_RESIDENT_AMBIGUOUS'
  }
  $phase='READONLY_EXISTING_REGISTRATION_INVENTORY'
  $link=Join-Path $startup 'Spotify Control Resident (R99 Guarded).lnk'
  $receiptPath=Join-Path $root 'startup-owner-r99.json'
  $linkExists=Test-Path -LiteralPath $link
  $receiptExists=Test-Path -LiteralPath $receiptPath
  $guardExists=Test-Path -LiteralPath $guard
  $guardArguments=R99GuardArgs $guard $root $hosted
  $route=R99GuardRoutes @($startup,$common) $guard $link
  $out.Add('R99_GUARDED_ROUTE='+$route)
  if($hosted){
    $startupCount=R95Shortcuts @($startup,$common) $agent $wscript
    $registryCount='NONE_IN_EXAMINED_SCOPE'
    $taskCount='NONE_IN_EXAMINED_SCOPE'
  }else{
    $startupCount=R95Shortcuts @($startup,$common) $agent $wscript
    $registryCount=R95RunRegistry $agent $wscript
    $taskCount=R95ScheduledLogon $agent $wscript
  }
  $out.Add('R99_EXISTING_STARTUP='+$startupCount)
  $out.Add('R99_EXISTING_RUN='+$registryCount)
  $out.Add('R99_EXISTING_LOGON_TASKS='+$taskCount)
  $ownRecord=$false
  $receiptSha=''
  if($receiptExists){
    if(-not(PlainFile $receiptPath)){Deny 'R99_EXISTING_OWNER_RECEIPT_NOT_REGULAR'}
    $rec=Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $receiptSha=Hash $receiptPath
    if($rec.schema -cne 'SPOTIFY_R99_OWNER_EXACT_STARTUP_LINK_V1' -or
       [string]$rec.owner_sid -cne $sid -or
       [string]$rec.installed_main_sha256 -cne 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d' -or
       [string]$rec.installed_agent_sha256 -cne 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5' -or
       [string]$rec.link_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
       [string]$rec.guard_sha256 -cnotmatch '^[0-9a-f]{64}$'){
      Deny 'R99_EXISTING_OWNER_RECEIPT_INVALID'
    }
    $ownRecord=$true
  }
  $ownedPresent=$false
  if($linkExists -and $ownRecord){
    $ownedPresent=(OwnedLink $link $guard $powershell $guardArguments $root) -and
      (PlainFile $guard) -and
      ((Hash $guard) -ceq [string]$rec.guard_sha256) -and
      ((Hash $link) -ceq [string]$rec.link_sha256)
  }
  if($Remove){
    $phase='EXPLICIT_OWNER_RECEIPT_ONLY_REVOKE'
    if(-not $ownRecord -or -not $ownedPresent){
      Deny 'R99_OWNED_RECEIPT_AND_UNMODIFIED_LINK_REQUIRED'
    }
    # Ensure that the only exact observed auto-start route is the owned link.
    if(-not(ExaminedNone $startupCount) -or
       -not(ExaminedNone $registryCount) -or
       -not(ExaminedNone $taskCount) -or $route -cne 'ONE_OWNED'){
      Deny 'R99_FOREIGN_OR_DUPLICATE_REGISTRATION_NOT_MUTATED'
    }
    if((Hash $receiptPath) -cne $receiptSha -or
       (Hash $link) -cne [string]$rec.link_sha256){
      Deny 'R99_REVOKE_CONCURRENT_OWNER_MUTATION'
    }
    [IO.File]::Delete($link)
    if(Test-Path -LiteralPath $link){Deny 'R99_EXACT_LINK_DELETE_NOT_VERIFIED'}
    if((Hash $receiptPath) -cne $receiptSha){
      Deny 'R99_RECEIPT_CHANGED_DURING_REVOKE'
    }
    if((Hash $guard) -cne [string]$rec.guard_sha256){Deny 'R99_GUARD_CHANGED_DURING_REVOKE'}
    [IO.File]::Delete($guard)
    [IO.File]::Delete($receiptPath)
    $out.Add('R99_REMOVE_RESULT=ONLY_ORIGINALLY_OWNED_EXACT_LINK_AND_RECEIPT_REMOVED')
    $out.Add('RESULT=R99_EXPLICIT_OWNED_LOGON_LINK_REVOKED')
  }elseif($Commit){
    $phase='EXPLICIT_OWNER_CREATE_ONLY_ONE_LINK'
    if($linkExists -or $receiptExists -or $guardExists){Deny 'R99_NEVER_OVERWRITE_EXISTING_LINK_OR_RECEIPT'}
    if(-not(ExaminedNone $startupCount) -or
       -not(ExaminedNone $registryCount) -or
       -not(ExaminedNone $taskCount) -or $route -cne 'NONE'){
      Deny 'R99_EXISTING_OR_UNVERIFIED_AUTO_START_ROUTE_HOLD'
    }
    # Prepare COM shortcut outside the active Startup folder, then move
    # exactly once into Startup. Never write any other startup destination.
    $working=[IO.Path]::GetDirectoryName($startup)
    if(-not(PlainDir $working)){Deny 'R99_STARTUP_PARENT_NOT_VERIFIED'}
    $stage=Join-Path $working ('.spotify-r99-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $stagedLink=Join-Path $stage 'staged.lnk'
    $stagedGuard=Join-Path $stage 'guard.ps1'
    $guardMoved=$false
    $receiptCreated=$false
    $linkMoved=$false
    $sha=''
    try{
      $sh=New-Object -ComObject WScript.Shell -ErrorAction Stop
      $lnk=$sh.CreateShortcut($stagedLink)
      [IO.File]::WriteAllBytes($stagedGuard,(R99ImmutableGuard))
      $guardHash=Hash $stagedGuard
      $lnk.TargetPath=$powershell
      $lnk.Arguments=$guardArguments
      $lnk.WorkingDirectory=$root
      $lnk.Description='Spotify Control guarded resident (owner-managed R99)'
      $lnk.Save()
      if(-not(OwnedLink $stagedLink $guard $powershell $guardArguments $root)){
        Deny 'R99_STAGED_COM_SHORTCUT_NOT_EXACT'
      }
      $sha=Hash $stagedLink
      $json=OwnerReceipt $sha $sid $guardHash
      $bytes=[Text.Encoding]::UTF8.GetBytes($json)
      # FileMode.CreateNew prevents overwriting any user-owned receipt.
      $fs=[IO.FileStream]::new($receiptPath,[IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,[IO.FileShare]::None)
      try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}
      finally{$fs.Dispose()}
      $receiptCreated=$true
      if(Test-Path -LiteralPath $guard){Deny 'R99_GUARD_APPEARED_DURING_PREPARE'}
      [IO.File]::Move($stagedGuard,$guard)
      $guardMoved=$true
      if(Test-Path -LiteralPath $link){Deny 'R99_LINK_APPEARED_DURING_PREPARE'}
      if(-not (ExaminedNone (R95Shortcuts @($startup,$common) $agent $wscript))){
        Deny 'R99_STARTUP_CHANGED_DURING_PREPARE'
      }
      [IO.File]::Move($stagedLink,$link)
      $linkMoved=$true
      if(-not(OwnedLink $link $guard $powershell $guardArguments $root) -or
         (Hash $guard) -cne $guardHash -or
         (Hash $link) -cne $sha -or
         (Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop) -cne $json){
        Deny 'R99_OWNER_LINK_READBACK_FAILED'
      }
      $out.Add('R99_COMMIT_RESULT=ONE_GUARDED_USER_STARTUP_LINK_CREATED_NOT_LAUNCHED')
      $out.Add('RESULT=R99_EXPLICIT_OWNER_LOGON_LINK_REGISTERED')
    }catch{
      # Roll back ONLY exact artifacts created during this call. Preserve any
      # concurrently modified link or receipt instead of deleting user data.
      if($linkMoved -and (PlainFile $link) -and
         (Hash $link) -ceq $sha){
        try{[IO.File]::Delete($link)}catch{}
      }
      if($guardMoved -and (PlainFile $guard) -and (Hash $guard) -ceq $guardHash){
        try{[IO.File]::Delete($guard)}catch{}
      }
      if($receiptCreated -and (PlainFile $receiptPath)){
        try{
          $got=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
          if([string]$got.owner_sid -ceq $sid -and
             [string]$got.guard_sha256 -ceq $guardHash -and
             [string]$got.link_sha256 -ceq $sha){
            [IO.File]::Delete($receiptPath)
          }
        }catch{}
      }
      throw
    }finally{
      if(PlainDir $stage){
        try{[IO.Directory]::Delete($stage,$true)}catch{}
      }
    }
  }else{
    $assessment='HOLD_NOT_READY'
    if($ownedPresent){
      $assessment='OWNED_GUARDED_LOGON_LINK_PRESENT_EXECUTION_UNVERIFIED'
    }elseif($linkExists -or $receiptExists -or $guardExists){
      $assessment='EXISTING_LINK_OR_RECEIPT_NOT_OWNED_HOLD'
    }elseif((ExaminedNone $startupCount) -and
            (ExaminedNone $registryCount) -and
            (ExaminedNone $taskCount)){
      $assessment='READY_FOR_EXACT_OWNER_APPROVAL_NOT_EXECUTION_PROOF'
    }
    $out.Add('R99_PLAN='+$assessment)
    $out.Add('RESULT=R99_READONLY_OWNER_LOGON_PLAN')
  }
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^R99_[A-Z0-9_]{5,100}$'){
    $reason='R99_OWNER_ENVIRONMENT_OR_STARTUP_UNVERIFIED'
  }
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$reason)
  $out.Add('RESULT=R99_HOLD_NO_RETRY')
}finally{
  $out.Add('R99_USER_APPROVAL_REQUIRED_FOR_CHANGES=YES;AUTO_RETRY=NO')
  $out.Add('R99_REAL_LOGON_AFTER_REBOOT=NOT_PROVEN')
  $out.Add('RAW_OWNER_PATHS_SECRETS_AND_PID_OUTPUT=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}
