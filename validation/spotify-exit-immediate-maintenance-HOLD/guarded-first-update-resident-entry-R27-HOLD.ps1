# R27 HOLD: verified pre-update resident process cutover only.
# No Bootstrap, upgrade, rollback, shortcut edits or unattended retries.
[CmdletBinding()]
param([switch]$Commit,[string]$ApprovalPhrase='',[string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R27_EXACT_RESIDENT_INITIAL_UPDATE_ENTRY')
$log.Add('BOOTSTRAP=NO;UPDATE=NO;ROLLBACK=NO;SHORTCUT_WRITE=NO')
$log.Add('FOREIGN_PROCESS_KILL=NO;USER_ORIGINALS_DELETE=NO')
$stage='INITIAL'
$mutexes=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
$newAgent=$null
$oldEnded=$false
$linkHashes=@{}
function Fail([string]$code){throw [InvalidOperationException]::new($code)}
function Sha([byte[]]$data){
  $h=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($h.ComputeHash($data)).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function ReadHash([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function EqPath([string]$a,[string]$b){
  try{return [IO.Path]::GetFullPath($a).TrimEnd('\','/').Equals(
    [IO.Path]::GetFullPath($b).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)}
  catch{return $false}
}
function PlainFolder([string]$path){
  try{
    $f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return ($f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function PinFile([string]$file,[long]$size,[string]$digest){
  try{
    $f=Get-Item -LiteralPath $file -Force -ErrorAction Stop
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    return ([long]$f.Length -eq $size -and (ReadHash $file) -ceq $digest)
  }catch{return $false}
}
function VbsArgument([string]$line){
  if([string]::IsNullOrWhiteSpace($line)){return ''}
  $m=[regex]::Matches($line,'(?i)(?:"([^"]+\.vbs)"|(?<=\s)([^\s"]+\.vbs)(?=\s|$))')
  if($m.Count -ne 1){return ''}
  return $(if($m[0].Groups[1].Success){$m[0].Groups[1].Value}else{$m[0].Groups[2].Value})
}
function OwnProcess([int]$processId){
  try{
    if($processId -le 0){return $null}
    $p=@(Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$processId) -ErrorAction Stop)
    if($p.Count -ne 1){return $null}
    $sid=Invoke-CimMethod -InputObject $p[0] -MethodName GetOwnerSid -ErrorAction Stop
    if([int]$sid.ReturnValue -ne 0 -or
      [string]$sid.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){return $null}
    return $p[0]
  }catch{return $null}
}
function EnterOldMutexes {
  # Return the fully owned list to the immediate caller, mirroring the
  # older R18 implementation. Never refer to caller-owned mutex list from a
  # function: ScriptBlock.Create invocation does NOT necessarily install
  # an independent PS script scope as invoking a script file does.
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if([string]::IsNullOrWhiteSpace($sid)){Fail 'OWNER_SID_UNKNOWN'}
  $safeSid=([string]$sid -replace '[^A-Za-z0-9]','_')
  $owned=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
  try{
    foreach($purpose in @('Maintenance','AgentTick')){
      $name=('Local\SpotifyControl-{0}-{1}' -f $purpose,$safeSid)
      $m=New-Object System.Threading.Mutex($false,$name)
      $got=$false
      try{
        try{$got=$m.WaitOne(0,$false)}
        catch [System.Threading.AbandonedMutexException]{
          try{$m.ReleaseMutex()}catch{}
          Fail 'ABANDONED_LEGACY_MUTEX'
        }
        if(-not $got){Fail 'LEGACY_MUTEX_NOT_IDLE'}
        $owned.Add($m)
      }catch{
        if(-not $got){try{$m.Dispose()}catch{}}
        throw
      }
    }
    return $owned
  }catch{
    for($i=$owned.Count-1;$i -ge 0;$i--){
      try{$owned[$i].ReleaseMutex()}catch{}
      try{$owned[$i].Dispose()}catch{}
    }
    throw
  }
}
if(-not ('SpotifyR27VerifiedProcessEnd' -as [type])){
  Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SpotifyR27VerifiedProcessEnd {
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern IntPtr OpenProcess(uint desired,bool inherit,int id);
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern bool GetProcessTimes(IntPtr h,out long created,out long exit,out long kernel,out long user);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern bool QueryFullProcessImageName(IntPtr h,int flags,StringBuilder name,ref int count);
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern bool TerminateProcess(IntPtr h,uint code);
  [DllImport("kernel32.dll",SetLastError=true)]
  static extern uint WaitForSingleObject(IntPtr h,uint milliseconds);
  public static bool TerminateOnlyExact(int pid,long expectedCreationUtcTicks,string expectedExe){
    if(pid<=0 || String.IsNullOrWhiteSpace(expectedExe))return false;
    IntPtr h=OpenProcess(0x00100000u|0x1000u|0x0001u,false,pid);
    if(h==IntPtr.Zero)return false;
    try{
      long created,exited,kernel,user;
      if(!GetProcessTimes(h,out created,out exited,out kernel,out user))return false;
      if(Math.Abs(created-expectedCreationUtcTicks)>5000000L)return false;
      StringBuilder name=new StringBuilder(4096);int count=name.Capacity;
      if(!QueryFullProcessImageName(h,0,name,ref count))return false;
      if(!String.Equals(name.ToString(),expectedExe,StringComparison.OrdinalIgnoreCase))return false;
      if(!TerminateProcess(h,0))return false;
      return WaitForSingleObject(h,10000)==0;
    }catch{return false;}
    finally{CloseHandle(h);}
  }
}
'@
}
function LinksUnchanged {
  foreach($link in @($linkHashes.Keys)){
    $old=[string]$linkHashes[$link]
    if($old -ceq 'ABSENT'){
      if(Test-Path -LiteralPath $link){return $false}
    }else{
      if(-not(Test-Path -LiteralPath $link)){return $false}
      if((ReadHash $link) -cne $old){return $false}
    }
  }
  return $true
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Fail 'WINDOWS_REQUIRED'}
  if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){Fail 'WINDOWS_PS51_X64_REQUIRED'}
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_ONLY_EXACT_OWNER_RESIDENT_NEUTRAL_CWD'){
    Fail 'EXACT_OWNER_CUTOVER_APPROVAL_REQUIRED'
  }
  if($HostedFixtureRoot.Length -gt 0){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){Fail 'HOSTED_OVERRIDE_DENIED'}
    $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      Fail 'HOSTED_OVERRIDE_NOT_IN_RUNNER_TEMP'
    }
    $root=Join-Path $fixture 'LocalAppData\SpotifyControl'
    $desktop=Join-Path $fixture 'Desktop'
    $startMenu=Join-Path $fixture 'StartMenu'
  }else{
    $ident=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($ident)
    if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'ORIGINAL_NORMAL_USER_ONLY'
    }
    $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  }
  $stage='PIN_EXACT_CURRENT_STABLE'
  $bin=Join-Path $root 'bin'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  if(-not(PlainFolder $root) -or -not(PlainFolder $bin) -or
     -not(PinFile (Join-Path $bin 'spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0') -or
     -not(PinFile (Join-Path $bin 'addon-manager.ps1') 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
     -not(PinFile $agent 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')){
    Fail 'ONLY_EXACT_STABLE_V0628_R17_SUPPORTED'
  }
  if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
    Fail 'SPOTIFY_MUST_BE_CLOSED'
  }
  $log.Add('CURRENT_STABLE=EXACT_V0628_R17')
  $stage='SNAPSHOT_USER_LAUNCHERS_READONLY'
  $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($dir in @($desktop,$startMenu)){
    if([string]::IsNullOrWhiteSpace([string]$dir)){continue}
    $lnk=Join-Path $dir 'Spotify (Managed).lnk'
    if(-not $seen.Add($lnk)){continue}
    if(Test-Path -LiteralPath $lnk){
      $info=Get-Item -LiteralPath $lnk -Force -ErrorAction Stop
      if($info.PSIsContainer -or
         ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         $info.Length -lt 30 -or $info.Length -gt 102400){
        Fail 'MANAGED_SHORTCUT_UNSAFE'
      }
      $linkHashes[$lnk]=ReadHash $lnk
    }else{
      $linkHashes[$lnk]='ABSENT'
    }
  }
  $log.Add('MANAGED_SHORTCUTS=SNAPSHOTTED_BYTE_PINS_OR_ABSENT')
  $stage='EXACT_RESIDENT_PROCESS_PROOF'
  $hosts=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
  if($hosts.Count -gt 256){Fail 'SCRIPT_HOST_INVENTORY_TOO_LARGE'}
  $resident=@()
  foreach($p in $hosts){
    if(-not(EqPath (VbsArgument ([string]$p.CommandLine)) $agent)){continue}
    if(-not(EqPath ([string]$p.ExecutablePath) $wscript)){Fail 'RESIDENT_HOST_IMAGE_NOT_SYSTEM32'}
    if($null -eq (OwnProcess ([int]$p.ProcessId))){Fail 'RESIDENT_NOT_SAME_OWNER'}
    $resident+=,$p
  }
  if($resident.Count -gt 1){Fail 'MULTIPLE_EXACT_RESIDENTS'}
  if($resident.Count -eq 0){
    $log.Add('RESIDENT=NONE')
    $log.Add('RESULT=NO_RESIDENT_TO_CUTOVER_OTHER_HANDLES_NOT_CERTIFIED')
  }else{
    $old=$resident[0]
    $birth=[datetime]$old.CreationDate
    if($null -eq (OwnProcess ([int]$old.ProcessId))){Fail 'RESIDENT_CHANGED_DURING_PROOF'}
    $log.Add('RESIDENT=ONE_EXACT_USER_OWNED_WSCRIPT')
    if(-not $Commit){
      $log.Add('RESULT=READY_FOR_EXACT_CUTOVER_NO_CHANGES')
    }else{
      $stage='LEGACY_MUTEX_ADMISSION'
      $mutexes=EnterOldMutexes
      if($null -eq $mutexes -or $mutexes.Count -ne 2){
        Fail 'LEGACY_MUTEX_PAIR_INCOMPLETE'
      }
      $log.Add('MAINTENANCE_AND_AGENTTICK_MUTEXES=HELD')
      $live=OwnProcess ([int]$old.ProcessId)
      if($null -eq $live -or [datetime]$live.CreationDate -ne $birth -or
         -not(EqPath ([string]$live.ExecutablePath) $wscript) -or
         -not(EqPath (VbsArgument ([string]$live.CommandLine)) $agent)){
        Fail 'RESIDENT_CHANGED_BEFORE_CUTOVER'
      }
      if(-not(LinksUnchanged)){Fail 'OWNER_SHORTCUT_CHANGED_BEFORE_CUTOVER'}
      $stage='START_SAME_PINNED_AGENT_WITH_NEUTRAL_CWD'
      $newAgent=Start-Process -FilePath $wscript -WorkingDirectory $root -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru
      Start-Sleep -Seconds 2
      if($newAgent.HasExited){Fail 'NEW_RESIDENT_EXITED_EARLY'}
      $newInfo=OwnProcess ([int]$newAgent.Id)
      if($null -eq $newInfo -or
         -not(EqPath ([string]$newInfo.ExecutablePath) $wscript) -or
         -not(EqPath (VbsArgument ([string]$newInfo.CommandLine)) $agent)){
        Fail 'NEW_RESIDENT_IDENTITY_UNVERIFIED'
      }
      if(-not(LinksUnchanged)){Fail 'OWNER_SHORTCUT_CHANGED_DURING_CUTOVER'}
      $stage='TERMINATE_ONLY_EXACT_OLD_RESIDENT'
      $last=OwnProcess ([int]$old.ProcessId)
      if($null -eq $last -or [datetime]$last.CreationDate -ne $birth -or
         -not(EqPath ([string]$last.ExecutablePath) $wscript) -or
         -not(EqPath (VbsArgument ([string]$last.CommandLine)) $agent)){
        Fail 'ORIGINAL_RESIDENT_IDENTITY_DRIFT'
      }
      if(-not [SpotifyR27VerifiedProcessEnd]::TerminateOnlyExact(
           [int]$old.ProcessId,$birth.ToUniversalTime().ToFileTimeUtc(),$wscript)){
        Fail 'OLD_RESIDENT_TERMINATION_UNVERIFIED'
      }
      $oldEnded=$true
      if($newAgent.HasExited){Fail 'NEW_RESIDENT_EXITED_AFTER_CUTOVER'}
      if(-not(LinksUnchanged)){Fail 'OWNER_SHORTCUT_CHANGED_AFTER_CUTOVER'}
      $log.Add('EXACT_OLD_RESIDENT=TERMINATED;NEW_RESIDENT=RUNNING_NEUTRAL_START')
      $log.Add('OWNER_SHORTCUTS=BYTE_IDENTICAL_OR_ABSENT')
      $log.Add('RESULT=EXACT_RESIDENT_CUTOVER_COMPLETED_OTHER_HANDLES_NOT_CERTIFIED')
    }
  }
}catch{
  $reason=[string]$_.Exception.Message
  $known=@('WINDOWS_REQUIRED','WINDOWS_PS51_X64_REQUIRED','EXACT_OWNER_CUTOVER_APPROVAL_REQUIRED',
    'HOSTED_OVERRIDE_DENIED','HOSTED_OVERRIDE_NOT_IN_RUNNER_TEMP','ORIGINAL_NORMAL_USER_ONLY',
    'ONLY_EXACT_STABLE_V0628_R17_SUPPORTED','SPOTIFY_MUST_BE_CLOSED','MANAGED_SHORTCUT_UNSAFE',
    'SCRIPT_HOST_INVENTORY_TOO_LARGE','RESIDENT_HOST_IMAGE_NOT_SYSTEM32',
    'RESIDENT_NOT_SAME_OWNER','MULTIPLE_EXACT_RESIDENTS','RESIDENT_CHANGED_DURING_PROOF',
    'OWNER_SID_UNKNOWN','ABANDONED_LEGACY_MUTEX','LEGACY_MUTEX_NOT_IDLE',
    'LEGACY_MUTEX_PAIR_INCOMPLETE','RESIDENT_CHANGED_BEFORE_CUTOVER',
    'OWNER_SHORTCUT_CHANGED_BEFORE_CUTOVER','NEW_RESIDENT_EXITED_EARLY',
    'NEW_RESIDENT_IDENTITY_UNVERIFIED','OWNER_SHORTCUT_CHANGED_DURING_CUTOVER',
    'ORIGINAL_RESIDENT_IDENTITY_DRIFT','OLD_RESIDENT_TERMINATION_UNVERIFIED',
    'NEW_RESIDENT_EXITED_AFTER_CUTOVER','OWNER_SHORTCUT_CHANGED_AFTER_CUTOVER')
  if($reason -cnotin $known){$reason='UNVERIFIED_WINDOWS_OR_PROCESS_ERROR'}
  $log.Add('HOLD_STAGE='+$stage)
  $log.Add('HOLD_REASON='+$reason)
  $log.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  if(-not $oldEnded -and $null -ne $newAgent -and -not $newAgent.HasExited){
    try{$newAgent.Kill();[void]$newAgent.WaitForExit(5000)}catch{}
  }
  for($i=$mutexes.Count-1;$i -ge 0;$i--){
    try{$mutexes[$i].ReleaseMutex()}catch{}
    try{$mutexes[$i].Dispose()}catch{}
  }
  $log.Add('EXACT_OLD_RESIDENT_TERMINATED='+$(if($oldEnded){'YES'}else{'NO'}))
  $log.Add('PRIVATE_PATHS_PIDS_COMMANDLINES_EXPORTED=NO')
  if($HostedFixtureRoot.Length -eq 0){
    try{Set-Clipboard -Value ($log -join [Environment]::NewLine)}catch{}
  }
}
$log | ForEach-Object{Write-Output $_}
