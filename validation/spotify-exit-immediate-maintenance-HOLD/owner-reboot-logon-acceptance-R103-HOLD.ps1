# R103 HOLD: read-only post-reboot owner logon and exact v0.6.30 acceptance.
# Never starts apps/tasks, edits registry, switches versions, or retries.
[CmdletBinding()]
param([switch]$HostedDecisionSelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R103_OWNER_REBOOT_LOGON_READONLY')
$out.Add('OPERATING_FILE_WRITE=NO;REGISTRY_WRITE=NO;TASK_WRITE=NO;PROCESS_CHANGE=NO;AUTO_RETRY=NO')
$phase='ENTRY'
function Fail([string]$code){throw [InvalidOperationException]::new($code)}
function SafeFile([string]$path,[long]$size,[string]$sha){
  try{
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($item.PSIsContainer -or
       ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       [long]$item.Length -ne $size){return $false}
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    return $hash -ceq $sha
  }catch{return $false}
}
function ExpectedAction([string]$exe,[string]$arg,[string]$agent,[string]$wscript){
  $q='"'+$agent+'"'
  return ([string]::Equals($exe,$wscript,[StringComparison]::OrdinalIgnoreCase) -and
          $arg.Trim() -cin @($q,('//B //NoLogo '+$q),('//NoLogo //B '+$q)))
}
function R103Decision([bool]$file,[bool]$task,[bool]$one,[bool]$newBoot,
                      [bool]$taskThisBoot,[bool]$residentThisBoot,[bool]$correlated){
  if(-not $file){return 'HOLD_INSTALLED_RELEASE_UNVERIFIED'}
  if(-not $task){return 'HOLD_OWNER_TASK_UNVERIFIED'}
  if(-not $one){return 'HOLD_SINGLE_OWNER_RESIDENT_UNVERIFIED'}
  if(-not $newBoot){return 'CURRENT_BOOT_POST_UPGRADE_NOT_PROVEN'}
  if(-not $taskThisBoot -or -not $residentThisBoot){
    return 'HOLD_LOGON_TASK_AND_RESIDENT_THIS_BOOT_UNVERIFIED'
  }
  if(-not $correlated){return 'HOLD_TASK_RESIDENT_TEMPORAL_CORRELATION_UNVERIFIED'}
  return 'POST_REBOOT_OWNER_TASK_RESIDENT_CORRELATED_NOT_CAUSAL_PROOF'
}
function Eq([string]$a,[string]$b){
  return [string]::Equals($a,$b,[StringComparison]::OrdinalIgnoreCase)
}
# Keep exactly the same principal/account SID resolution as approved R102.
# Task Scheduler may store NTAccount aliases rather than a literal SID.
function R103PrincipalClass([string]$user,[string]$group,
                            [Security.Principal.WindowsIdentity]$identity){
  if(-not [string]::IsNullOrWhiteSpace($group)){return 'GROUP_SCOPED'}
  if([string]::IsNullOrWhiteSpace($user)){return 'MISSING_OR_DYNAMIC'}
  try{
    $principal=if($user -match '^S-\d-\d+(?:-\d+)+$'){
      [Security.Principal.SecurityIdentifier]::new($user)
    }else{
      ([Security.Principal.NTAccount]::new($user)).Translate(
        [Security.Principal.SecurityIdentifier])
    }
    if([string]::Equals($principal.Value,$identity.User.Value,
       [StringComparison]::OrdinalIgnoreCase)){return 'CURRENT_OWNER_RESOLVED'}
    if($principal.Value -cin @('S-1-5-18','S-1-5-19','S-1-5-20')){
      return 'BUILTIN_SERVICE'
    }
    return 'OTHER_RESOLVED_PRINCIPAL'
  }catch{return 'UNRESOLVED_PRINCIPAL'}
}
try{
  if($HostedDecisionSelfTest){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
      Fail 'R103_HOSTED_SELFTEST_ONLY_GITHUB_WINDOWS'
    }
    $arr=@(
      @{bits=@($true,$true,$true,$true,$true,$true,$true);expected='POST_REBOOT_OWNER_TASK_RESIDENT_CORRELATED_NOT_CAUSAL_PROOF'},
      @{bits=@($true,$true,$true,$false,$true,$true,$true);expected='CURRENT_BOOT_POST_UPGRADE_NOT_PROVEN'},
      @{bits=@($true,$false,$true,$true,$true,$true,$true);expected='HOLD_OWNER_TASK_UNVERIFIED'},
      @{bits=@($true,$true,$false,$true,$true,$true,$true);expected='HOLD_SINGLE_OWNER_RESIDENT_UNVERIFIED'},
      @{bits=@($true,$true,$true,$true,$false,$true,$true);expected='HOLD_LOGON_TASK_AND_RESIDENT_THIS_BOOT_UNVERIFIED'},
      @{bits=@($true,$true,$true,$true,$true,$true,$false);expected='HOLD_TASK_RESIDENT_TEMPORAL_CORRELATION_UNVERIFIED'}
    )
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    foreach($value in @($identity.User.Value,$identity.Name)){
      if((R103PrincipalClass $value '' $identity) -cne 'CURRENT_OWNER_RESOLVED'){
        Fail 'R103_OWNER_SID_OR_ALIAS_RESOLUTION_FAILED'
      }
    }
    if((R103PrincipalClass $identity.User.Value 'S-1-5-32-545' $identity) -cne
       'GROUP_SCOPED'){Fail 'R103_GROUP_PRINCIPAL_MUST_BE_REJECTED'}
    if((R103PrincipalClass 'S-1-5-18' '' $identity) -cne
       'BUILTIN_SERVICE'){Fail 'R103_BUILTIN_PRINCIPAL_MUST_BE_REJECTED'}
    foreach($c in $arr){
      [object[]]$argsForTest=$c.bits
      if((R103Decision @argsForTest) -cne $c.expected){
        Fail 'R103_HOSTED_DECISION_GATE_FAILED'
      }
    }
    $out.Add('RESULT=R103_HOSTED_DECISION_TEST_PASS_NO_OWNER_INSPECTION')
  }else{
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $PSVersionTable.PSEdition -cne 'Desktop' -or
       $PSVersionTable.PSVersion.Major -ne 5 -or
       -not [Environment]::Is64BitProcess){
      Fail 'R103_OWNER_WINDOWS_PS51_X64_REQUIRED'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'R103_OWNER_NONADMIN_REQUIRED'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $agent=Join-Path $root 'bin\spotify-control-agent.vbs'
    $main=Join-Path $root 'bin\spotify-control.ps1'
    $addon=Join-Path $root 'bin\addon-manager.ps1'
    $bootfile=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
    $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
    $phase='EXACT_INSTALLED_RELEASE'
    $installed=(
      (SafeFile $main 294101 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d') -and
      (SafeFile $agent 13308 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5') -and
      (SafeFile $addon 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -and
      (SafeFile $bootfile 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')
    )
    $out.Add('R103_INSTALLED_V0630_FILE_PINS='+$(if($installed){'PASS'}else{'HOLD'}))
    $phase='COMMITTED_JOURNAL_AND_BOOT_TIME'
    $journalOK=$false;$committedAt=$null
    try{
      $p=Join-Path $root 'self-update-last-transaction.json'
      $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      if($f.PSIsContainer -or
         ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         [long]$f.Length -lt 5 -or [long]$f.Length -gt 1048576){
        throw 'R103_JOURNAL_FILE_UNVERIFIED'
      }
      $doc=Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      if([string]$doc.status -ceq 'committed'){
        $journalOK=$true
        $committedAt=[datetime]$f.LastWriteTimeUtc
      }
    }catch{}
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $bootTime=([datetime]$os.LastBootUpTime).ToUniversalTime()
    $now=[datetime]::UtcNow
    if($bootTime -gt $now -or $bootTime -lt [datetime]'2020-01-01'){
      Fail 'R103_BOOT_TIME_UNVERIFIED'
    }
    $afterCommit=($journalOK -and $null -ne $committedAt -and
                  $bootTime -gt $committedAt.AddSeconds(30))
    $out.Add('R103_COMMIT_JOURNAL='+$(if($journalOK){'COMMITTED_REPORTED'}else{'UNVERIFIED'}))
    $out.Add('R103_BOOT_AFTER_JOURNAL_WRITE='+$(if($afterCommit){'YES'}else{'NOT_PROVEN'}))
    $phase='EXACT_USER_LOGON_TASK_READONLY'
    $svc=New-Object -ComObject Schedule.Service
    $svc.Connect()
    $stack=New-Object System.Collections.Stack
    $stack.Push($svc.GetFolder('\'))
    $taskCount=0;$folderCount=0;$matches=0;$partial=$false
    $chosen=$null
    $singleReject='NOT_OBSERVED'
    while($stack.Count -gt 0){
      if(++$folderCount -gt 512){$partial=$true;break}
      $folder=$stack.Pop()
      try{
        $tasks=$folder.GetTasks(1)
        for($i=1;$i -le $tasks.Count;$i++){
          if(++$taskCount -gt 4096){$partial=$true;break}
          try{
            $task=$tasks.Item($i)
            $definition=$task.Definition
            $actions=$definition.Actions
            $referred=$false;$exact=$false
            for($j=1;$j -le $actions.Count;$j++){
              $action=$actions.Item($j)
              if([int]$action.Type -ne 0){continue}
              $arg=[string]$action.Arguments
              $pathPattern='(^|[\s"])'+[regex]::Escape($agent)+'(?=$|[\s"])'
              if([regex]::IsMatch($arg,$pathPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)){
                $referred=$true
                if($actions.Count -eq 1){
                  $exact=ExpectedAction ([string]$action.Path) $arg $agent $wscript
                }
              }
            }
            if(-not $referred){continue}
            $matches++
            $triggerCount=0;$allLogon=$true
            $triggers=$definition.Triggers
            for($k=1;$k -le $triggers.Count;$k++){
              $tr=$triggers.Item($k)
              if(-not [bool]$tr.Enabled){continue}
              $triggerCount++
              if([int]$tr.Type -ne 9 -or
                 (R103PrincipalClass ([string]$tr.UserId) '' $identity) -cne
                    'CURRENT_OWNER_RESOLVED'){
                $allLogon=$false
              }
            }
            $principal=[string]$definition.Principal.UserId
            $group=[string]$definition.Principal.GroupId
            $ownerOK=((R103PrincipalClass $principal $group $identity) -ceq
                      'CURRENT_OWNER_RESOLVED')
            $acceptable=($exact -and $ownerOK -and [string]::IsNullOrWhiteSpace($group) -and
                         [bool]$task.Enabled -and $triggerCount -ge 1 -and $allLogon -and
                         [int]$definition.Principal.LogonType -eq 3 -and
                         [int]$definition.Settings.MultipleInstances -eq 2)
            if($acceptable){$chosen=$task;$singleReject='NONE'}
            else{
              $singleReject=if(-not $exact){'ACTION_MISMATCH'}
              elseif(-not $ownerOK){'PRINCIPAL_MISMATCH'}
              elseif(-not [bool]$task.Enabled){'TASK_DISABLED'}
              elseif($triggerCount -lt 1 -or -not $allLogon){'TRIGGER_SCOPE_MISMATCH'}
              elseif([int]$definition.Principal.LogonType -ne 3){'LOGON_TOKEN_MISMATCH'}
              elseif([int]$definition.Settings.MultipleInstances -ne 2){'INSTANCE_POLICY_MISMATCH'}
              else{'OTHER_UNVERIFIED'}
            }
          }catch{$partial=$true}
        }
      }catch{$partial=$true}
      try{
        $children=$folder.GetFolders(0)
        for($m=1;$m -le $children.Count;$m++){$stack.Push($children.Item($m))}
      }catch{$partial=$true}
    }
    $taskVerified=($matches -eq 1 -and $null -ne $chosen -and -not $partial)
    $out.Add('R103_OWNER_LOGON_TASK='+$(if($taskVerified){'ONE_EXACT_VISIBLE_SCOPE'}else{'HOLD_UNVERIFIED'}))
    $out.Add('R103_AGENT_REFERENCING_TASKS='+$(if($matches -eq 0){'ZERO'}elseif($matches -eq 1){'ONE'}else{'MULTIPLE'}))
    $out.Add('R103_SINGLE_MATCH_REJECTION='+$(if($matches -eq 1){$singleReject}else{'NOT_SINGLE_MATCH'}))
    $out.Add('R103_TASK_ENUMERATION='+$(if($partial){'PARTIAL'}else{'ACCESSIBLE_SCOPE_ONLY'}))
    $taskRun=$false;$taskMoment=$null
    if($taskVerified){
      try{
        $taskMoment=([datetime]$chosen.LastRunTime).ToUniversalTime()
        $taskRun=($taskMoment -ge $bootTime.AddMinutes(-2) -and
                  $taskMoment -le $now.AddMinutes(2))
      }catch{}
    }
    $out.Add('R103_SCHEDULER_TASK_RAN_THIS_BOOT='+$(if($taskRun){'OBSERVED'}else{'NOT_PROVEN'}))
    $phase='ONE_OWNER_RESIDENT_PROCESS'
    $procs=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
    if($procs.Count -gt 1024){Fail 'R103_PROCESS_LIST_UNBOUNDED'}
    $expectedPattern='(^|[\s"])'+[regex]::Escape($agent)+'(?=$|[\s"])'
    $found=@($procs | Where-Object{
      [regex]::IsMatch([string]$_.CommandLine,$expectedPattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    })
    $one=$false;$residentThisBoot=$false;$correlated=$false
    if($found.Count -eq 1){
      try{
        $p=$found[0]
        $owner=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
        $one=([int]$owner.ReturnValue -eq 0 -and
              (Eq ([string]$owner.Sid) $identity.User.Value) -and
              (Eq ([string]$p.ExecutablePath) $wscript))
        $pStart=([datetime]$p.CreationDate).ToUniversalTime()
        $residentThisBoot=($one -and $pStart -ge $bootTime.AddMinutes(-2) -and
                           $pStart -le $now.AddMinutes(2))
        if($taskRun -and $residentThisBoot){
          $gap=($pStart-$taskMoment).TotalSeconds
          $correlated=($gap -ge -30 -and $gap -le 300)
        }
      }catch{$one=$false;$residentThisBoot=$false;$correlated=$false}
    }
    $out.Add('R103_OWNER_RESIDENT='+$(if($one){'ONE_EXACT_OWNER_WSCRIPT'}else{'HOLD_UNVERIFIED'}))
    $out.Add('R103_OWNER_RESIDENT_STARTED_THIS_BOOT='+$(if($residentThisBoot){'OBSERVED'}else{'NOT_PROVEN'}))
    $out.Add('R103_TASK_RESIDENT_TEMPORAL_CORRELATION='+$(if($correlated){'WITHIN_300_SECONDS'}else{'NOT_PROVEN'}))
    $out.Add('R103_TASK_PROCESS_CAUSAL_PROOF=NOT_CLAIMED')
    $out.Add('R103_IN_MEMORY_AGENT_CODE_VERSION=NOT_PROVEN')
    $out.Add('R103_SPOTIFY_PLAYBACK_FUNCTIONALITY=NOT_TESTED')
    $out.Add('RESULT='+(R103Decision $installed $taskVerified $one $afterCommit $taskRun $residentThisBoot $correlated))
  }
}catch{
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('RESULT=HOLD_READONLY_UNVERIFIED')
}finally{
  $out.Add('R103_USER_ORIGINALS_AND_OPERATING_SETTINGS=UNCHANGED')
  $out.Add('RAW_PATHS_USER_SID_SECRETS_PIDS_AND_ARGS_OUTPUT=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object{Write-Output $_}
}
