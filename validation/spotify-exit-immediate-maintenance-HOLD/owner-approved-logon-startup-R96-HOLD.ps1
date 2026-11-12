# R96 HOLD: standalone owner-only logon startup registration for exact
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
$out.Add('DIAGNOSTIC=SPOTIFY_R96_OWNER_LOGON_REGISTRATION_HOLD')
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
function OwnerReceipt([string]$linkHash,[string]$sid){
  $obj=[ordered]@{
    schema='SPOTIFY_R96_OWNER_EXACT_STARTUP_LINK_V1'
    owner_sid=$sid
    link_sha256=$linkHash
    installed_main_sha256='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
    installed_agent_sha256='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
  }
  return ($obj|ConvertTo-Json -Compress)
}
function OwnedLink([string]$path,[string]$agent,[string]$wscript,[string]$root){
  if(-not (PlainFile $path)){return $false}
  try{
    $sh=New-Object -ComObject WScript.Shell -ErrorAction Stop
    $lk=$sh.CreateShortcut($path)
    return (
      [string]::Equals([string]$lk.TargetPath,$wscript,[StringComparison]::OrdinalIgnoreCase) -and
      (R95IsExactWScriptArgs ([string]$lk.Arguments) $agent) -and
      [string]::Equals([string]$lk.WorkingDirectory,$root,[StringComparison]::OrdinalIgnoreCase)
    )
  }catch{return $false}
}
try{
  if($Commit -and $Remove){Deny 'R96_MUTATION_MODES_MUTUALLY_EXCLUSIVE'}
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE'){
    Deny 'R96_CREATE_EXPLICIT_APPROVAL_REQUIRED'
  }
  if($Remove -and $ApprovalPhrase -cne 'APPROVE_REMOVE_ONLY_R96_OWNED_LOGON_SHORTCUT_ONCE'){
    Deny 'R96_REMOVE_EXPLICIT_APPROVAL_REQUIRED'
  }
  if(-not ($Commit -or $Remove) -and $ApprovalPhrase -cne ''){
    Deny 'R96_PLAN_WITH_APPROVAL_NOT_ALLOWED'
  }
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    Deny 'R96_WIN64_PS51_REQUIRED'
  }
  $user=[Security.Principal.WindowsIdentity]::GetCurrent()
  $sid=$user.User.Value
  $hosted=(-not [string]::IsNullOrEmpty($HostedFixtureRoot))
  if($hosted){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      Deny 'R96_TEST_FIXTURE_NOT_GITHUB_HOSTED'
    }
    $root=[IO.Path]::GetFullPath($HostedFixtureRoot).TrimEnd('\','/')
    $tmp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $root.StartsWith(($tmp+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -cne 'SpotifyControl'){
      Deny 'R96_FIXTURE_OUTSIDE_EXCLUSIVE_RUNNER_TEMP'
    }
    $startup=Join-Path ([IO.Path]::GetDirectoryName($root)) 'R96UserStartup'
    $common=Join-Path ([IO.Path]::GetDirectoryName($root)) 'R96CommonStartup'
    $scope='HOSTED_SYNTHETIC_ONLY'
  }else{
    if(([Security.Principal.WindowsPrincipal]::new($user)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Deny 'R96_OWNER_MUST_NOT_RUN_ELEVATED'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $startup=[Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
    $scope='OWNER_CURRENT_USER_ONLY'
  }
  $out.Add('R96_SCOPE='+$scope)
  $phase='OWNER_EXACT_PRIVATE_RELEASE'
  $bin=Join-Path $root 'bin'
  if(-not(PlainDir $root) -or -not(PlainDir $bin) -or
     -not(PlainDir $startup) -or -not(PlainDir $common)){
    Deny 'R96_OWNER_ROOT_OR_STARTUP_DIRECTORY_UNVERIFIED'
  }
  $main=Join-Path $bin 'spotify-control.ps1'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $addon=Join-Path $bin 'addon-manager.ps1'
  $boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  if(-not(MatchPinned $main 294101 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d') -or
     -not(MatchPinned $agent 13308 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5') -or
     -not(MatchPinned $addon 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
     -not(MatchPinned $boot 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6') -or
     -not(PlainFile $wscript)){
    Deny 'R96_EXACT_NEW_MAIN_VBS_ADDON_BOOTSTRAP_REQUIRED'
  }
  $journal=Join-Path $root 'self-update-last-transaction.json'
  if(-not(PlainFile $journal) -or (Get-Item -LiteralPath $journal).Length -gt 1048576){
    Deny 'R96_OWNER_COMMIT_JOURNAL_NOT_VERIFIABLE'
  }
  $transaction=Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json -ErrorAction Stop
  if([string]$transaction.status -cne 'committed'){
    Deny 'R96_R90_OWNER_COMMITTED_RELEASE_REQUIRED'
  }
  $resident=ReadOnlyResident $agent
  $out.Add('R96_RESIDENT='+$resident)
  if($resident -cnotin @('ONE_OWNER_PATH_OBSERVED_CODE_NOT_ATTESTED','NO_MATCH')){
    Deny 'R96_CURRENT_RESIDENT_AMBIGUOUS'
  }
  $phase='READONLY_EXISTING_REGISTRATION_INVENTORY'
  $link=Join-Path $startup 'Spotify Control Resident (R96 Managed).lnk'
  $receiptPath=Join-Path $root 'startup-owner-r96.json'
  $linkExists=Test-Path -LiteralPath $link
  $receiptExists=Test-Path -LiteralPath $receiptPath
  if($hosted){
    $startupCount=R95Shortcuts @($startup,$common) $agent $wscript
    $registryCount='NONE_IN_EXAMINED_SCOPE'
    $taskCount='NONE_IN_EXAMINED_SCOPE'
  }else{
    $startupCount=R95Shortcuts @($startup,$common) $agent $wscript
    $registryCount=R95RunRegistry $agent $wscript
    $taskCount=R95ScheduledLogon $agent $wscript
  }
  $out.Add('R96_EXISTING_STARTUP='+$startupCount)
  $out.Add('R96_EXISTING_RUN='+$registryCount)
  $out.Add('R96_EXISTING_LOGON_TASKS='+$taskCount)
  $ownRecord=$false
  $receiptSha=''
  if($receiptExists){
    if(-not(PlainFile $receiptPath)){Deny 'R96_EXISTING_OWNER_RECEIPT_NOT_REGULAR'}
    $rec=Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $receiptSha=Hash $receiptPath
    if($rec.schema -cne 'SPOTIFY_R96_OWNER_EXACT_STARTUP_LINK_V1' -or
       [string]$rec.owner_sid -cne $sid -or
       [string]$rec.installed_main_sha256 -cne 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d' -or
       [string]$rec.installed_agent_sha256 -cne 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5' -or
       [string]$rec.link_sha256 -cnotmatch '^[0-9a-f]{64}$'){
      Deny 'R96_EXISTING_OWNER_RECEIPT_INVALID'
    }
    $ownRecord=$true
  }
  $ownedPresent=$false
  if($linkExists -and $ownRecord){
    $ownedPresent= (OwnedLink $link $agent $wscript $root) -and
      ((Hash $link) -ceq [string]$rec.link_sha256)
  }
  if($Remove){
    $phase='EXPLICIT_OWNER_RECEIPT_ONLY_REVOKE'
    if(-not $ownRecord -or -not $ownedPresent){
      Deny 'R96_OWNED_RECEIPT_AND_UNMODIFIED_LINK_REQUIRED'
    }
    # Ensure that the only exact observed auto-start route is the owned link.
    if($startupCount -cne 'ONE_EXACT_REGISTERED_NOT_EXECUTION_PROOF' -or
       -not(ExaminedNone $registryCount) -or
       -not(ExaminedNone $taskCount)){
      Deny 'R96_FOREIGN_OR_DUPLICATE_REGISTRATION_NOT_MUTATED'
    }
    if((Hash $receiptPath) -cne $receiptSha -or
       (Hash $link) -cne [string]$rec.link_sha256){
      Deny 'R96_REVOKE_CONCURRENT_OWNER_MUTATION'
    }
    [IO.File]::Delete($link)
    if(Test-Path -LiteralPath $link){Deny 'R96_EXACT_LINK_DELETE_NOT_VERIFIED'}
    if((Hash $receiptPath) -cne $receiptSha){
      Deny 'R96_RECEIPT_CHANGED_DURING_REVOKE'
    }
    [IO.File]::Delete($receiptPath)
    $out.Add('R96_REMOVE_RESULT=ONLY_ORIGINALLY_OWNED_EXACT_LINK_AND_RECEIPT_REMOVED')
    $out.Add('RESULT=R96_EXPLICIT_OWNED_LOGON_LINK_REVOKED')
  }elseif($Commit){
    $phase='EXPLICIT_OWNER_CREATE_ONLY_ONE_LINK'
    if($linkExists -or $receiptExists){Deny 'R96_NEVER_OVERWRITE_EXISTING_LINK_OR_RECEIPT'}
    if(-not(ExaminedNone $startupCount) -or
       -not(ExaminedNone $registryCount) -or
       -not(ExaminedNone $taskCount)){
      Deny 'R96_EXISTING_OR_UNVERIFIED_AUTO_START_ROUTE_HOLD'
    }
    # Prepare COM shortcut outside the active Startup folder, then move
    # exactly once into Startup. Never write any other startup destination.
    $working=[IO.Path]::GetDirectoryName($startup)
    if(-not(PlainDir $working)){Deny 'R96_STARTUP_PARENT_NOT_VERIFIED'}
    $stage=Join-Path $working ('.spotify-r96-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    $stagedLink=Join-Path $stage 'staged.lnk'
    $receiptCreated=$false
    $linkMoved=$false
    $sha=''
    try{
      $sh=New-Object -ComObject WScript.Shell -ErrorAction Stop
      $lnk=$sh.CreateShortcut($stagedLink)
      $lnk.TargetPath=$wscript
      $lnk.Arguments='//B //NoLogo "'+$agent+'"'
      $lnk.WorkingDirectory=$root
      $lnk.Description='Spotify Control resident (owner-managed R96)'
      $lnk.Save()
      if(-not(OwnedLink $stagedLink $agent $wscript $root)){
        Deny 'R96_STAGED_COM_SHORTCUT_NOT_EXACT'
      }
      $sha=Hash $stagedLink
      $json=OwnerReceipt $sha $sid
      $bytes=[Text.Encoding]::UTF8.GetBytes($json)
      # FileMode.CreateNew prevents overwriting any user-owned receipt.
      $fs=[IO.FileStream]::new($receiptPath,[IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,[IO.FileShare]::None)
      try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}
      finally{$fs.Dispose()}
      $receiptCreated=$true
      if(Test-Path -LiteralPath $link){Deny 'R96_LINK_APPEARED_DURING_PREPARE'}
      if(-not (ExaminedNone (R95Shortcuts @($startup,$common) $agent $wscript))){
        Deny 'R96_STARTUP_CHANGED_DURING_PREPARE'
      }
      [IO.File]::Move($stagedLink,$link)
      $linkMoved=$true
      if(-not(OwnedLink $link $agent $wscript $root) -or
         (Hash $link) -cne $sha -or
         (Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop) -cne $json){
        Deny 'R96_OWNER_LINK_READBACK_FAILED'
      }
      $out.Add('R96_COMMIT_RESULT=ONE_EXACT_USER_STARTUP_LINK_CREATED_NOT_LAUNCHED')
      $out.Add('RESULT=R96_EXPLICIT_OWNER_LOGON_LINK_REGISTERED')
    }catch{
      # Roll back ONLY exact artifacts created during this call. Preserve any
      # concurrently modified link or receipt instead of deleting user data.
      if($linkMoved -and (PlainFile $link) -and
         (Hash $link) -ceq $sha){
        try{[IO.File]::Delete($link)}catch{}
      }
      if($receiptCreated -and (PlainFile $receiptPath)){
        try{
          $got=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
          if([string]$got.owner_sid -ceq $sid -and
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
      $assessment='OWNED_EXACT_LOGON_LINK_PRESENT_EXECUTION_UNVERIFIED'
    }elseif($linkExists -or $receiptExists){
      $assessment='EXISTING_LINK_OR_RECEIPT_NOT_OWNED_HOLD'
    }elseif((ExaminedNone $startupCount) -and
            (ExaminedNone $registryCount) -and
            (ExaminedNone $taskCount)){
      $assessment='READY_FOR_EXACT_OWNER_APPROVAL_NOT_EXECUTION_PROOF'
    }
    $out.Add('R96_PLAN='+$assessment)
    $out.Add('RESULT=R96_READONLY_OWNER_LOGON_PLAN')
  }
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^R96_[A-Z0-9_]{5,100}$'){
    $reason='R96_OWNER_ENVIRONMENT_OR_STARTUP_UNVERIFIED'
  }
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$reason)
  $out.Add('RESULT=R96_HOLD_NO_RETRY')
}finally{
  $out.Add('R96_USER_APPROVAL_REQUIRED_FOR_CHANGES=YES;AUTO_RETRY=NO')
  $out.Add('R96_REAL_LOGON_AFTER_REBOOT=NOT_PROVEN')
  $out.Add('RAW_OWNER_PATHS_SECRETS_AND_PID_OUTPUT=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}
