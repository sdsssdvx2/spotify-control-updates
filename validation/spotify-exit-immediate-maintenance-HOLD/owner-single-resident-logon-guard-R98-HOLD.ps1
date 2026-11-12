# R98 HOLD: one-shot PowerShell 5.1 guarded WScript startup.
# Does not register a login entry and does not update Spotify.
# Existing v0.6.30 owner resident remains unchanged. R96 direct VBS
# auto-start is blocked because R97 proved two residents can coexist.
# Host testing is strictly GitHub Windows runner scratch, never owner PC.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$phase='AUTHORIZATION'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R98_OWNER_GUARDED_SINGLE_RESIDENT')
$out.Add('UPDATE=NO;FILES_WRITE=NO;REGISTRY_WRITE=NO;TASK_WRITE=NO;PROCESS_KILL=NO')
$lock=$null
$locked=$false
$launchAttempted=$false
function Fail([string]$code){throw [InvalidOperationException]::new($code)}
function Plain([string]$path,[bool]$dir){
  try{
    $f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return ($f.PSIsContainer -eq $dir -and
      ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function ExactResident([string]$agent,[string]$wscript,[string]$sid){
  $list=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
  $quoted=[regex]::Escape($agent)
  $found=@()
  foreach($p in $list){
    # Unknown command lines cannot establish safe absence. Fail closed.
    if([string]::IsNullOrWhiteSpace([string]$p.CommandLine)){
      Fail 'R98_WMI_COMMAND_LINE_UNVERIFIED'
    }
    if(([string]$p.CommandLine) -match ('(?i)(^|[\s"])'+$quoted+'(?=$|[\s"])')){
      $found+=,$p
    }
  }
  if($found.Count -gt 1){return 'MULTIPLE_PRESENT_HOLD'}
  if($found.Count -eq 0){return 'NONE'}
  $item=$found[0]
  if(-not [string]::Equals([string]$item.ExecutablePath,$wscript,
          [StringComparison]::OrdinalIgnoreCase)){
    return 'OTHER_IMAGE_PRESENT_HOLD'
  }
  $owner=Invoke-CimMethod -InputObject $item -MethodName GetOwnerSid -ErrorAction Stop
  if([int]$owner.ReturnValue -ne 0 -or [string]$owner.Sid -cne $sid){
    return 'OTHER_OWNER_PRESENT_HOLD'
  }
  return 'ONE_EXACT_OWNER_PRESENT'
}
try{
  $phase='WINDOWS_OWNER'
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){
    Fail 'R98_WINDOWS_PS51_X64_REQUIRED'
  }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $sid=$identity.User.Value
  if(-not $sid.StartsWith('S-1-', [StringComparison]::Ordinal)){
    Fail 'R98_OWNER_SID_UNVERIFIED'
  }
  if([string]::IsNullOrEmpty($HostedFixtureRoot)){
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'R98_OWNER_ELEVATED_FORBIDDEN'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $scope='REAL_OWNER_CANDIDATE'
  }else{
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      Fail 'R98_HOSTED_FIXTURE_NOT_AUTHORIZED'
    }
    $root=[IO.Path]::GetFullPath($HostedFixtureRoot).TrimEnd('\','/')
    $tmp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $root.StartsWith(($tmp+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -cne 'SpotifyControl'){
      Fail 'R98_HOSTED_FIXTURE_OUTSIDE_RUNNER_TEMP'
    }
    $scope='HOSTED_OWNER_SCRATCH'
  }
  $out.Add('R98_SCOPE='+$scope)
  $bin=Join-Path $root 'bin'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $main=Join-Path $bin 'spotify-control.ps1'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  if(-not (Plain $root $true) -or -not (Plain $bin $true) -or
     -not (Plain $agent $false) -or -not (Plain $main $false) -or
     -not (Plain $wscript $false)){
    Fail 'R98_OWNER_INSTALLED_FILES_NOT_REGULAR'
  }
  $phase='PIN_EXACT_NEW_CANDIDATE'
  if([long](Get-Item -LiteralPath $agent).Length -ne 13308 -or
     (Get-FileHash -LiteralPath $agent -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
       'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5' -or
     [long](Get-Item -LiteralPath $main).Length -ne 294101 -or
     (Get-FileHash -LiteralPath $main -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
       'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'){
    Fail 'R98_OWNER_RELEASE_HASH_NOT_PINNED'
  }
  $phase='LOCK_OWNER_ONESHOT'
  $lock=[Threading.Mutex]::new($false,('Local\SpotifyControlR98OwnerLogon-'+$sid))
  try{$locked=$lock.WaitOne([TimeSpan]::FromSeconds(75))}
  catch [Threading.AbandonedMutexException]{$locked=$true}
  if(-not $locked){Fail 'R98_OWNER_MUTEX_NOT_ACQUIRED'}
  $phase='OBSERVE_CURRENT_OWNER_RESIDENT'
  $state='UNKNOWN'
  $wmiOK=$false
  for($try=0;$try -lt 30;$try++){
    try{
      $state=ExactResident $agent $wscript $sid
      $wmiOK=$true
      break
    }catch{
      # Only temporary WMI transport errors can be retried. Unknown process
      # identity must never be reinterpreted as an empty process list.
      if([string]$_.Exception.Message -match '^R98_'){throw}
      Start-Sleep -Seconds 2
    }
  }
  if(-not $wmiOK){Fail 'R98_WMI_NOT_READY_WITHIN_BOUNDED_RETRY'}
  $out.Add('R98_BEFORE='+$state)
  if($state -eq 'ONE_EXACT_OWNER_PRESENT'){
    $out.Add('RESULT=R98_ALREADY_RUNNING_NO_SECOND_PROCESS')
  }elseif($state -ne 'NONE'){
    Fail 'R98_ALREADY_PRESENT_AMBIGUOUS_NO_LAUNCH'
  }else{
    $phase='START_ONE_EXACT_CANDIDATE'
    if((Get-FileHash -LiteralPath $agent -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
       'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'){
      Fail 'R98_PRESTART_AGENT_PIN_DRIFT'
    }
    $launchAttempted=$true
    $created=Start-Process -FilePath $wscript -WorkingDirectory $root -WindowStyle Hidden -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru -ErrorAction Stop
    Start-Sleep -Milliseconds 1500
    $created.Refresh()
    if($created.HasExited){Fail 'R98_FRESH_OWNER_RESIDENT_EXITED_EARLY'}
    $after=ExactResident $agent $wscript $sid
    if($after -cne 'ONE_EXACT_OWNER_PRESENT'){
      Fail 'R98_AFTER_LAUNCH_NOT_ONE_EXACT_OWNER'
    }
    $out.Add('RESULT=R98_ONE_EXACT_OWNER_RESIDENT_STARTED')
  }
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^R98_[A-Z0-9_]{5,95}$'){
    $reason='R98_OBSERVATION_OR_STARTUP_UNVERIFIED'
  }
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('HOLD_REASON='+$reason)
  $out.Add($(if($launchAttempted){'RESULT=R98_POST_LAUNCH_UNCERTAIN_NO_RETRY'}else{'RESULT=R98_HOLD_NO_NEW_PROCESS_ON_UNCERTAINTY'}))
}finally{
  if($locked){try{$lock.ReleaseMutex()}catch{}}
  if($null -ne $lock){$lock.Dispose()}
  $out.Add('R98_NO_AUTO_RETRY=YES;NO_USER_FILES_CHANGED=YES')
  $out.Add('R98_REAL_REBOOT_LOGON_EXECUTION=UNVERIFIED')
  $out|ForEach-Object{Write-Output $_}
}
