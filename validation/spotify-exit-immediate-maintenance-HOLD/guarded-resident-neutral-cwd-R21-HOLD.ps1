# R21: exact installed resident VBS neutral workdir + two managed links.
# Optional R18 once-only official stable recovery; zero background retries.
# This module is HOLD until Windows fixture acceptance.
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$ApprovalPhrase='',
  [byte[]]$PinnedR18Source=$null,
  [switch]$RunApprovedStableUpdate,
  [string]$HostedFixtureRoot=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R21_EXACT_AGENT_CWD_NEUTRAL_CUTOVER')
$log.Add('USER_DATA_DELETE=NO;FOREIGN_PROCESS_KILL=NO;V0629=FORBIDDEN')
$log.Add('SCOPE=EXACT_MANAGED_SHORTCUT_WORKDIR_AND_SAME_USER_AGENT_ONLY')
$stage='INITIAL'
$mutexes=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
$oldEnded=$false
$newAgent=$null
$changes=New-Object 'System.Collections.Generic.List[object]'
$shortcutChangesMade=0
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
function EnterOldMutexes{
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if([string]::IsNullOrWhiteSpace($sid)){Fail 'OWNER_SID_UNKNOWN'}
  $safe=$sid -replace '[^A-Za-z0-9]','_'
  foreach($purpose in @('Maintenance','AgentTick')){
    $m=New-Object Threading.Mutex($false,('Local\SpotifyControl-'+$purpose+'-'+$safe))
    $got=$false
    try{$got=$m.WaitOne(0,$false)}
    catch [Threading.AbandonedMutexException] {
      try{$m.ReleaseMutex()}catch{}
      $m.Dispose()
      Fail 'ABANDONED_LEGACY_MUTEX'
    }
    if(-not $got){$m.Dispose();Fail 'LEGACY_MUTEX_NOT_IDLE'}
    $script:mutexes.Add($m)
  }
}
if(-not ('SpotifyR21VerifiedProcessEnd' -as [type])){
  Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SpotifyR21VerifiedProcessEnd {
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
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Fail 'WINDOWS_REQUIRED'}
  if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){Fail 'WINDOWS_PS51_X64_REQUIRED'}
  if($RunApprovedStableUpdate -and -not $Commit){Fail 'STABLE_UPDATE_REQUIRES_COMMIT'}
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_VBS_RESTART_AND_MANAGED_SHORTCUT_CWD'){
    Fail 'EXACT_AGENT_RESTART_APPROVAL_REQUIRED'
  }
  if($null -eq $PinnedR18Source -or $PinnedR18Source.Length -ne 54515 -or
     (Sha $PinnedR18Source) -cne 'ec8c86a7d79611702dab926c131f1e4fddca0bca22edff50d0512e37484fb121'){
     Fail 'R18_SOURCE_PIN_MISSING'
  }
  $hosted=$HostedFixtureRoot.Length -gt 0
  if($hosted){
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
      Fail 'RUN_AS_ORIGINAL_NONADMIN_USER_ONLY'
    }
    $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  }
  if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){Fail 'SPOTIFY_MUST_BE_CLOSED'}
  $bin=Join-Path $root 'bin'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  if(-not(PlainFolder $root) -or -not(PlainFolder $bin) -or
     -not(PinFile $agent 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')){
    Fail 'INSTALLED_RESIDENT_SOURCE_NOT_PINNED'
  }
  $stage='R18_READONLY_ORIGINAL_PREPARED_PROOF'
  $r18=[ScriptBlock]::Create([Text.Encoding]::ASCII.GetString($PinnedR18Source))
  $pre=@(& $r18 -HostedFixtureRoot $HostedFixtureRoot)
  if($pre -cnotcontains 'SOURCE_AND_FULL_TREES=EXACT_PREPARED_BEFORE' -or
     $pre -cnotcontains 'RESTORE_BEFORE_TREE=EXACT_REQUIRES_PRESERVATION' -or
     $pre -cnotcontains 'RESULT=READY_FOR_APPROVED_RESTORE_PRESERVATION_THEN_RECONCILIATION'){
    Fail 'R18_READONLY_PREPARED_PROOF_NOT_READY'
  }
  $log.Add('CURRENT_PREPARED_AND_ALL_OLD_TREES=EXACT')
  $stage='EXACT_SINGLE_OWNER_RESIDENT_PROOF'
  $allHosts=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
  if($allHosts.Count -gt 256){Fail 'SCRIPT_HOST_INVENTORY_TOO_LARGE'}
  $resident=@()
  foreach($p in $allHosts){
    if(-not(EqPath (VbsArgument ([string]$p.CommandLine)) $agent)){continue}
    if(-not(EqPath ([string]$p.ExecutablePath) $wscript)){Fail 'RESIDENT_HOST_IMAGE_NOT_SYSTEM32'}
    if($null -eq (OwnProcess ([int]$p.ProcessId))){Fail 'RESIDENT_OWNER_NOT_CURRENT_USER'}
    $resident+=,$p
  }
  if($resident.Count -ne 1){Fail 'SINGLE_EXACT_RESIDENT_REQUIRED'}
  $old=$resident[0]
  $creation=[datetime]$old.CreationDate
  if($null -eq (OwnProcess ([int]$old.ProcessId))){Fail 'RESIDENT_PROCESS_RACE'}
  $log.Add('RESIDENT=EXACT_SINGLE_USER_OWNED_WSCRIPT')
  $stage='MANAGED_SHORTCUT_PROOF'
  $links=@()
  foreach($folder in @($desktop,$startMenu)){
    if([string]::IsNullOrWhiteSpace($folder)){continue}
    $link=Join-Path $folder 'Spotify (Managed).lnk'
    if(Test-Path -LiteralPath $link){$links+=,$link}
  }
  if($links.Count -lt 1 -or $links.Count -gt 2){Fail 'EXPECTED_ONE_OR_TWO_MANAGED_LINKS'}
  $shell=New-Object -ComObject WScript.Shell
  foreach($link in $links){
    $item=Get-Item -LiteralPath $link -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      Fail 'MANAGED_LINK_NOT_PLAIN_FILE'
    }
    $shortcut=$shell.CreateShortcut($link)
    if(-not(EqPath ([string]$shortcut.TargetPath) $wscript) -or
       [string]$shortcut.Arguments -cne ('"'+$agent+'"')){Fail 'MANAGED_LINK_TARGET_NOT_EXACT'}
    $work=[string]$shortcut.WorkingDirectory
    if(-not(EqPath $work $bin) -and -not(EqPath $work $root)){Fail 'MANAGED_LINK_CUSTOM_WORKDIR_PRESERVE'}
    $orig=[IO.File]::ReadAllBytes($link)
    if($orig.Length -gt 102400 -or $orig.Length -lt 30){Fail 'MANAGED_LINK_UNEXPECTED_SIZE'}
    $changes.Add([pscustomobject]@{
      path=$link;orig=$orig;origSha=(Sha $orig);needsChange=(EqPath $work $bin);backup='';
    })
  }
  $todo=@($changes|Where-Object {$_.needsChange})
  $log.Add('MANAGED_LINKS_EXACT_COUNT='+[string]$links.Count)
  $log.Add('MANAGED_LINKS_REQUIRE_WORKDIR_CHANGE='+[string]$todo.Count)
  if(-not $Commit){
    $log.Add('RESULT=READY_FOR_EXACT_AGENT_CUTOVER_NO_MUTATION')
  }else{
    $stage='LEGACY_MUTEX_ADMISSION'
    EnterOldMutexes
    $log.Add('MAINTENANCE_AND_AGENTTICK_MUTEXES=HELD')
    $check=OwnProcess ([int]$old.ProcessId)
    if($null -eq $check -or [datetime]$check.CreationDate -ne $creation -or
       -not(EqPath (VbsArgument ([string]$check.CommandLine)) $agent)){
      Fail 'RESIDENT_CHANGED_BEFORE_CUTOVER'
    }
    $stage='PRESERVE_ORIGINAL_MANAGED_LINKS'
    $backups=Join-Path $root 'backups\agent-shortcut-neutral-cwd-R21'
    if(-not(Test-Path -LiteralPath $backups)){
      [void][IO.Directory]::CreateDirectory($backups)
    }
    if(-not(PlainFolder $backups)){Fail 'SHORTCUT_BACKUP_DIRECTORY_UNSAFE'}
    $tag=[guid]::NewGuid().ToString('N')
    $index=0
    foreach($change in $todo){
      $index++
      $location=Join-Path $backups ('original-'+$tag+'-'+$index+'.lnk')
      $f=New-Object IO.FileStream($location,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try{$f.Write($change.orig,0,$change.orig.Length);$f.Flush($true)}
      finally{$f.Dispose()}
      if((ReadHash $location) -cne $change.origSha){Fail 'ORIGINAL_LINK_BACKUP_SHA_DRIFT'}
      $change.backup=$location
    }
    $stage='COMMIT_NEUTRAL_MANAGED_LINK_WORKDIR'
    foreach($change in $todo){
      if((ReadHash $change.path) -cne $change.origSha){Fail 'MANAGED_LINK_RACE_BEFORE_CAS'}
      $new=Join-Path (Split-Path $change.path -Parent) ('.SpotifyManaged-R21-'+$tag+'.lnk')
      [IO.File]::Copy($change.path,$new,$false)
      try{
        $staged=$shell.CreateShortcut($new)
        $staged.WorkingDirectory=$root
        $staged.Save()
        if(-not(EqPath ([string]$shell.CreateShortcut($new).WorkingDirectory) $root)){
          Fail 'STAGED_LINK_NOT_NEUTRAL'
        }
        [IO.File]::Replace($new,$change.path,$null,$true)
        if(-not(EqPath ([string]$shell.CreateShortcut($change.path).WorkingDirectory) $root)){
          Fail 'COMMITTED_LINK_NOT_NEUTRAL'
        }
      }finally{if(Test-Path -LiteralPath $new){[IO.File]::Delete($new)}}
      $shortcutChangesMade++
    }
    $log.Add('MANAGED_LINKS_NEUTRALIZED='+[string]$shortcutChangesMade)
    $stage='START_NEUTRAL_CWD_AGENT'
    $newAgent=Start-Process -FilePath $wscript -WorkingDirectory $root -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru
    Start-Sleep -Seconds 2
    if($newAgent.HasExited){Fail 'NEW_AGENT_EXITED_EARLY'}
    $newInfo=OwnProcess ([int]$newAgent.Id)
    if($null -eq $newInfo -or -not(EqPath ([string]$newInfo.ExecutablePath) $wscript) -or
       -not(EqPath (VbsArgument ([string]$newInfo.CommandLine)) $agent)){
      Fail 'NEW_AGENT_IDENTITY_NOT_EXACT'
    }
    $log.Add('NEUTRAL_CWD_AGENT=STARTED_EXACT')
    $stage='END_ONLY_PREVIOUS_EXACT_RESIDENT'
    $last=OwnProcess ([int]$old.ProcessId)
    if($null -eq $last -or [datetime]$last.CreationDate -ne $creation -or
       -not(EqPath ([string]$last.ExecutablePath) $wscript) -or
       -not(EqPath (VbsArgument ([string]$last.CommandLine)) $agent)){
      Fail 'ORIGINAL_AGENT_IDENTITY_CHANGED_DO_NOT_KILL'
    }
    if(-not [SpotifyR21VerifiedProcessEnd]::TerminateOnlyExact(
         [int]$old.ProcessId,$creation.ToUniversalTime().ToFileTimeUtc(),$wscript)){
      Fail 'ORIGINAL_AGENT_EXACT_TERMINATION_UNVERIFIED'
    }
    $oldEnded=$true
    if($newAgent.HasExited){Fail 'NEUTRAL_AGENT_EXITED_AFTER_OLD_END'}
    $log.Add('ORIGINAL_AGENT=EXACT_VERIFIED_PROCESS_ONLY_ENDED')
    $log.Add('NEUTRAL_AGENT=ONE_RESIDENT_RUNNING')
    if($RunApprovedStableUpdate){
      $stage='ONE_APPROVED_R18_OFFICIAL_RECOVERY_AND_STABLE_UPDATE'
      $receipt=@(& $r18 -HostedFixtureRoot $HostedFixtureRoot -Commit -ApprovalPhrase 'EXACT_PREPARED_NO_BIN_SWAP' -ContinueOfficialStableUpdate -OfficialUpdateApprovalPhrase 'APPROVE_OFFICIAL_V0628_CORE_UPGRADE')
      foreach($line in $receipt){$log.Add([string]$line)}
      if($receipt -contains 'RESULT=OFFICIAL_STABLE_V0628_R17_COMMITTED_VERIFIED'){
        $log.Add('RESULT=R21_AGENT_CWD_FIXED_AND_STABLE_V0628_R17_COMMITTED')
      }else{
        $log.Add('RESULT=R21_AGENT_CWD_FIXED_OFFICIAL_UPDATE_HOLD_NO_RETRY')
      }
    }else{
      $log.Add('RESULT=R21_AGENT_CWD_FIXED_NO_OFFICIAL_UPDATE_ATTEMPTED')
    }
  }
}catch{
  $kind=[string]$_.Exception.Message
  $allowed=@('WINDOWS_REQUIRED','WINDOWS_PS51_X64_REQUIRED','STABLE_UPDATE_REQUIRES_COMMIT',
    'EXACT_AGENT_RESTART_APPROVAL_REQUIRED','R18_SOURCE_PIN_MISSING',
    'HOSTED_OVERRIDE_DENIED','HOSTED_OVERRIDE_NOT_IN_RUNNER_TEMP','RUN_AS_ORIGINAL_NONADMIN_USER_ONLY',
    'SPOTIFY_MUST_BE_CLOSED','INSTALLED_RESIDENT_SOURCE_NOT_PINNED',
    'R18_READONLY_PREPARED_PROOF_NOT_READY','SCRIPT_HOST_INVENTORY_TOO_LARGE',
    'RESIDENT_HOST_IMAGE_NOT_SYSTEM32','RESIDENT_OWNER_NOT_CURRENT_USER',
    'SINGLE_EXACT_RESIDENT_REQUIRED','RESIDENT_PROCESS_RACE',
    'EXPECTED_ONE_OR_TWO_MANAGED_LINKS','MANAGED_LINK_NOT_PLAIN_FILE',
    'MANAGED_LINK_TARGET_NOT_EXACT','MANAGED_LINK_CUSTOM_WORKDIR_PRESERVE',
    'MANAGED_LINK_UNEXPECTED_SIZE','OWNER_SID_UNKNOWN','ABANDONED_LEGACY_MUTEX',
    'LEGACY_MUTEX_NOT_IDLE','RESIDENT_CHANGED_BEFORE_CUTOVER',
    'SHORTCUT_BACKUP_DIRECTORY_UNSAFE','ORIGINAL_LINK_BACKUP_SHA_DRIFT',
    'MANAGED_LINK_RACE_BEFORE_CAS','STAGED_LINK_NOT_NEUTRAL',
    'COMMITTED_LINK_NOT_NEUTRAL','NEW_AGENT_EXITED_EARLY',
    'NEW_AGENT_IDENTITY_NOT_EXACT','ORIGINAL_AGENT_IDENTITY_CHANGED_DO_NOT_KILL',
    'ORIGINAL_AGENT_EXACT_TERMINATION_UNVERIFIED','NEUTRAL_AGENT_EXITED_AFTER_OLD_END')
  if($kind -cnotin $allowed){$kind='UNVERIFIED_WINDOWS_OR_COM_ERROR'}
  $log.Add('HOLD_STAGE='+$stage)
  $log.Add('HOLD_REASON='+$kind)
  $log.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  if(-not $oldEnded -and $null -ne $newAgent -and -not $newAgent.HasExited){
    try{$newAgent.Kill();[void]$newAgent.WaitForExit(5000)}catch{}
  }
  for($i=$mutexes.Count-1;$i -ge 0;$i--){
    try{$mutexes[$i].ReleaseMutex()}catch{}
    try{$mutexes[$i].Dispose()}catch{}
  }
  $log.Add('EXACT_ORIGINAL_AGENT_TERMINATED='+$(if($oldEnded){'YES'}else{'NO'}))
  $log.Add('USER_PATHS_PIDS_COMMANDLINES_AND_ERRORS_EXPORTED=NO')
  if($HostedFixtureRoot.Length -eq 0){
    try{Set-Clipboard -Value ($log -join [Environment]::NewLine)}catch{}
  }
}
$log|ForEach-Object{Write-Output $_}
