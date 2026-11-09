# R28: future-stable coordinated one-shot update; intentionally NOT released.
# Public production use blocked until independently pinned official release.
# Tested only in a github-hosted isolated Windows fixture; no auto retry.
[CmdletBinding()]
param(
  [switch]$Commit,
  [string]$ApprovalPhrase='',
  [byte[]]$PinnedR27Source=$null,
  [string]$HostedFixtureRoot='',
  [string]$HostedExpectedManifestSHA256='',
  [string]$HostedExpectedBootstrapSHA256='',
  [string]$HostedExpectedMainSHA256='',
  [string]$HostedExpectedAgentSHA256='',
  [string]$PinnedReleaseFactsJson='',
  [string]$ApprovedPublicManifestSHA256='',
  [string]$ApprovedPublicSourceCommit=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R28_OWNER_APPROVED_ONESHOT_FUTURE_STABLE')
$log.Add('AUTO_RETRY=OFF;RELEASE_PUBLICATION=NO;USER_SHORTCUT_WRITE=NO')
$phase='INITIAL'
$mutexes=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
$cutoverDone=$false
$updateCommitted=$false
$oldNeutralEnded=$false
$newVersionProcess=$null
$finished=$false
$links=@{}
function StopNow([string]$reason){throw [InvalidOperationException]::new($reason)}
function Digest([byte[]]$b){
  $h=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function FileSHA([string]$p){
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function PlainDir([string]$p){
  try{$x=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      return ($x.PSIsContainer -and ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)}
  catch{return $false}
}
function ExactFile([string]$p,[long]$n,[string]$h){
  try{$x=Get-Item -LiteralPath $p -Force -ErrorAction Stop
      return (-not $x.PSIsContainer -and
       ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
       [long]$x.Length -eq $n -and (FileSHA $p) -ceq $h)}
  catch{return $false}
}
function Same([string]$a,[string]$b){
  try{return [IO.Path]::GetFullPath($a).TrimEnd('\','/').Equals(
    [IO.Path]::GetFullPath($b).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)}
  catch{return $false}
}
function VbsArg([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){return ''}
  $matches=[regex]::Matches($s,'(?i)(?:"([^"]+\.vbs)"|(?<=\s)([^\s"]+\.vbs)(?=\s|$))')
  if($matches.Count -ne 1){return ''}
  if($matches[0].Groups[1].Success){return $matches[0].Groups[1].Value}
  return $matches[0].Groups[2].Value
}
function OwnerProcess([int]$pidToCheck){
  try{
    $p=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$pidToCheck) -ErrorAction Stop)
    if($p.Count -ne 1){return $null}
    $owner=Invoke-CimMethod -InputObject $p[0] -MethodName GetOwnerSid -ErrorAction Stop
    if([int]$owner.ReturnValue -ne 0 -or
      [string]$owner.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
      return $null
    }
    return $p[0]
  }catch{return $null}
}
function OneExactResident([string]$agent,[string]$wscript){
  $all=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
  if($all.Count -gt 256){StopNow 'SCRIPT_HOST_COUNT_NOT_BOUNDED'}
  $same=@()
  foreach($p in $all){
    if(-not(Same (VbsArg ([string]$p.CommandLine)) $agent)){continue}
    if(-not(Same ([string]$p.ExecutablePath) $wscript)){StopNow 'RESIDENT_WSCRIPT_IMAGE_NOT_EXACT'}
    if($null -eq (OwnerProcess ([int]$p.ProcessId))){StopNow 'RESIDENT_NOT_SAME_USER'}
    $same+=,$p
  }
  if($same.Count -ne 1){StopNow 'EXACT_SINGLE_RESIDENT_REQUIRED'}
  return $same[0]
}
function LinksStable{
  foreach($p in @($links.Keys)){
    if([string]$links[$p] -ceq 'ABSENT'){
      if(Test-Path -LiteralPath $p){return $false}
    }else{
      if(-not(Test-Path -LiteralPath $p)){return $false}
      if((FileSHA $p) -cne [string]$links[$p]){return $false}
    }
  }
  return $true
}
function AcquireLegacyPair{
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $safe=$sid -replace '[^A-Za-z0-9]','_'
  $owned=New-Object 'System.Collections.Generic.List[System.Threading.Mutex]'
  try{
    foreach($purpose in @('Maintenance','AgentTick')){
      $m=New-Object System.Threading.Mutex($false,('Local\SpotifyControl-'+$purpose+'-'+$safe))
      $held=$false
      try{
        try{$held=$m.WaitOne(0,$false)}
        catch [System.Threading.AbandonedMutexException]{
          try{$m.ReleaseMutex()}catch{}
          StopNow 'ABANDONED_LEGACY_MUTEX'
        }
        if(-not $held){StopNow 'LEGACY_MUTEX_NOT_IDLE'}
        $owned.Add($m)
      }catch{
        if(-not $held){try{$m.Dispose()}catch{}}
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
function ExpectedSha([string]$s){
  return ($s -cmatch '^[0-9a-f]{64}$')
}
function InvokeOfficial([string]$scriptPath,[string]$action){
  $lines=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Action $action -Json 2>&1)
  $code=$LASTEXITCODE
  if($code -ne 0 -or $lines.Count -eq 0){
    StopNow ('OFFICIAL_BOOTSTRAP_'+$action+'_FAILED_HOLD')
  }
  try{$result=$lines[-1] | ConvertFrom-Json -ErrorAction Stop}
  catch{StopNow ('OFFICIAL_BOOTSTRAP_'+$action+'_UNVERIFIED_RECEIPT')}
  if($result.success -ne $true -or [string]$result.action -cne $action){
    StopNow ('OFFICIAL_BOOTSTRAP_'+$action+'_UNEXPECTED_RESULT')
  }
  return $result
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){StopNow 'WINDOWS_REQUIRED'}
  if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){StopNow 'WINDOWS_PS51_X64_REQUIRED'}
  if($null -eq $PinnedR27Source -or $PinnedR27Source.Length -ne 14472 -or
     (Digest $PinnedR27Source) -cne '096a9d13d499af4057f3a40d15dc105dfe2a5de97296373f949b3e6a58dd8064'){
    StopNow 'PINNED_R27_SOURCE_NOT_MATCHED'
  }
  $hosted=$HostedFixtureRoot.Length -gt 0
  if(-not $hosted){
    # Unpublished code remains blocked: require independently approved release pins.
    if(-not(ExpectedSha $ApprovedPublicManifestSHA256) -or
       $ApprovedPublicSourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
       $ApprovedPublicSourceCommit -cin @('bb6d90146f20b73d36fbf8cb813f1b190f403c48',('f'*40),('e'*40))){
      StopNow 'PUBLIC_RELEASE_INDEPENDENT_PINS_REQUIRED'
    }
    if($HostedExpectedManifestSHA256.Length -ne 0 -or
       $HostedExpectedBootstrapSHA256.Length -ne 0 -or
       $HostedExpectedMainSHA256.Length -ne 0 -or
       $HostedExpectedAgentSHA256.Length -ne 0){
      StopNow 'HOSTED_RELEASE_OVERRIDES_FORBIDDEN_IN_PUBLIC_MODE'
    }
    $ident=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($ident)
    if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
      StopNow 'ORIGINAL_NORMAL_USER_ONLY'
    }
    $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $linkDirs=@(
      [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory),
      (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
    $expectedManifest=$ApprovedPublicManifestSHA256
    $expectedSource=$ApprovedPublicSourceCommit
    $expectedBootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
    $expectedMain='37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec'
    $expectedAgent='da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d'
    $manifestURL='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
    $fixture=''
  }
  if($hosted){
  if($ApprovedPublicManifestSHA256.Length -ne 0 -or $ApprovedPublicSourceCommit.Length -ne 0){StopNow 'PUBLIC_RELEASE_PINS_FORBIDDEN_IN_HOSTED_MODE'}
  if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
     $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
     [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    StopNow 'HOSTED_RELEASE_OVERRIDE_NOT_ALLOWED'
  }
  $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
  $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
  if(-not $fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
    StopNow 'HOSTED_FIXTURE_NOT_UNDER_RUNNER_TEMP'
  }
  if($Commit -and $ApprovalPhrase -cne 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE'){
    StopNow 'OWNER_ONE_SHOT_APPROVAL_REQUIRED'
  }
  foreach($h in @($HostedExpectedManifestSHA256,$HostedExpectedBootstrapSHA256,
      $HostedExpectedMainSHA256,$HostedExpectedAgentSHA256)){
    if(-not(ExpectedSha $h)){StopNow 'HOSTED_RELEASE_SHA_PIN_REQUIRED'}
  }
  $root=Join-Path $fixture 'LocalAppData\SpotifyControl'
  $linkDirs=@((Join-Path $fixture 'Desktop'),(Join-Path $fixture 'StartMenu'))
  $expectedManifest=$HostedExpectedManifestSHA256
  $expectedSource=('f'*40)
  $expectedBootstrap=$HostedExpectedBootstrapSHA256
  $expectedMain=$HostedExpectedMainSHA256
  $expectedAgent=$HostedExpectedAgentSHA256
  $portFile=Join-Path $fixture 'server-port'
  $port=[int]([IO.File]::ReadAllText($portFile))
  if($port -lt 1 -or $port -gt 65535){StopNow 'HOSTED_LOOPBACK_PORT_INVALID'}
  $manifestURL='http://127.0.0.1:'+([string]$port)+'/manifest.json'
  }
  $bin=Join-Path $root 'bin'
  $main=Join-Path $bin 'spotify-control.ps1'
  $addon=Join-Path $bin 'addon-manager.ps1'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
  $boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
  $phase='CURRENT_STABLE_EXACT_PIN'
  if(-not(PlainDir $root) -or -not(PlainDir $bin) -or
     -not(ExactFile $main 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0') -or
     -not(ExactFile $addon 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') -or
     -not(ExactFile $agent 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278') -or
     -not(ExactFile $boot 42963 $expectedBootstrap)){
    StopNow 'INSTALLED_STABLE_OR_BOOTSTRAP_NOT_EXACT'
  }
  if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
    StopNow 'SPOTIFY_MUST_BE_CLOSED'
  }
  $log.Add('CURRENT_STABLE_V0628_R17_AND_BOOTSTRAP=EXACT_PINNED')
  $phase='NEXT_STABLE_MANIFEST_ADMISSION'
  $wc=New-Object Net.WebClient
  try{$rawManifest=[byte[]]$wc.DownloadData($manifestURL)}
  finally{$wc.Dispose()}
  if($rawManifest.Length -lt 1000 -or $rawManifest.Length -gt 200000 -or
     (Digest $rawManifest) -cne $expectedManifest){
    StopNow 'NEXT_STABLE_MANIFEST_SHA_NOT_PINNED'
  }
  try{$manifest=[Text.Encoding]::UTF8.GetString($rawManifest)|ConvertFrom-Json -ErrorAction Stop}
  catch{StopNow 'NEXT_STABLE_MANIFEST_NOT_JSON'}
  if($manifest.channel -cne 'stable' -or $manifest.latest_version -cne '0.6.30' -or
     [string]$manifest.source_commit -cne $expectedSource -or
     [string]$manifest.source_repository -cne 'sdsssdvx2/spotify-control-updates' -or
     [string]$manifest.bootstrap.sha256 -cne $expectedBootstrap -or
     @($manifest.updates).Count -ne 19 -or
     [string]$manifest.updates[18].from_version -cne '0.6.28' -or
     [string]$manifest.updates[18].to_version -cne '0.6.30'){
    StopNow 'NEXT_STABLE_MANIFEST_NOT_SPECIFIED_TEST_RELEASE'
  }
  $new=@{}
  foreach($f in @($manifest.latest_files)){
    $new[[string]$f.path]=[string]$f.sha256
  }
  if($new.Count -ne 3 -or
     $new['bin/spotify-control.ps1'] -cne $expectedMain -or
     $new['bin/spotify-control-agent.vbs'] -cne $expectedAgent -or
     $new['bin/addon-manager.ps1'] -cne '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'){
    StopNow 'NEXT_STABLE_RELEASE_FILE_PINS_MISMATCH'
  }
  # Bind factual release-source admission to the same manifest and target
  # bytes that the approved one-shot Bootstrap will consume. The facts by
  # themselves do NOT authorize a process cutover or a release.
  $phase='RELEASE_SOURCE_FACTS_CROSS_CHECK'
  if([string]::IsNullOrWhiteSpace($PinnedReleaseFactsJson) -or
     $PinnedReleaseFactsJson.Length -gt 2400){
    StopNow 'PINNED_RELEASE_SOURCE_FACTS_REQUIRED'
  }
  try{$facts=$PinnedReleaseFactsJson | ConvertFrom-Json -ErrorAction Stop}
  catch{StopNow 'RELEASE_SOURCE_FACTS_JSON_INVALID'}
  $expectedFactStatus=if($hosted){'HOSTED_SYNTHETIC_SOURCE_ONLY_NOT_PUBLIC_VERIFIED'}else{'PUBLIC_SOURCE_AND_PAYLOAD_READONLY_VERIFIED_NOT_OWNER_AUTHORIZED'}
  if($facts.schema -cne 'SPOTIFY_R30_PUBLIC_RELEASE_FACTS_V1' -or
     $facts.status -cne $expectedFactStatus -or
     $facts.from_version -cne '0.6.28' -or
     $facts.to_version -cne '0.6.30' -or
     [string]$facts.source_commit -cne $expectedSource -or
     [string]$facts.manifest_sha256 -cne $expectedManifest -or
     [string]$facts.payload_set_sha256 -cne [string]$manifest.payload_set_sha256 -or
     [string]$facts.bootstrap_sha256 -cne $expectedBootstrap -or
     [string]$facts.main_sha256 -cne $expectedMain -or
     [string]$facts.agent_sha256 -cne $expectedAgent -or
     [string]$facts.addon_sha256 -cne $new['bin/addon-manager.ps1'] -or
     [int]$facts.chunk_count -ne 20){
    StopNow 'RELEASE_SOURCE_FACTS_NOT_BOUND_TO_MANIFEST_AND_PAYLOAD'
  }
  if($hosted){
    $log.Add('R30_RELEASE_SOURCE_FACTS=EXACT_HOSTED_UNPUBLISHED_ONLY')
    $log.Add('NEXT_RELEASE=EXACT_HOSTED_ONLY_TEST_MANIFEST')
  }else{
    $log.Add('R30_RELEASE_SOURCE_FACTS=PUBLIC_PINS_AND_FACTS_MATCH_NOT_OWNER_AUTHORITY')
    $log.Add('NEXT_RELEASE=EXACT_PINNED_PUBLIC_STABLE_MANIFEST')
  }
  $phase='SNAPSHOT_OWNER_SHORTCUTS_AND_DATA'
  foreach($base in $linkDirs){
    $link=Join-Path $base 'Spotify (Managed).lnk'
    if(Test-Path -LiteralPath $link){
      $info=Get-Item -LiteralPath $link -Force -ErrorAction Stop
      if($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        StopNow 'USER_SHORTCUT_UNSAFE'
      }
      $links[$link]=FileSHA $link
    }else{$links[$link]='ABSENT'}
  }
  $stateFile=Join-Path $root 'state.json'
  $sentinelFile=Join-Path $root 'unrelated-user-preserve.txt'
  $stateBefore=FileSHA $stateFile
  $sentinelBefore=if($hosted){FileSHA $sentinelFile}else{''}
  $r27=[ScriptBlock]::Create([Text.Encoding]::ASCII.GetString($PinnedR27Source))
  $phase='R27_READONLY_OWNER_PROOF'
  $pre=@(& $r27 -HostedFixtureRoot $fixture)
  if($pre -cnotcontains 'RESULT=READY_FOR_EXACT_CUTOVER_NO_CHANGES'){
    StopNow 'R27_OWNER_PREFLIGHT_NOT_READY'
  }
  $log.Add('EXACT_OWNER_RESIDENT=READY_TO_CUTOVER_NO_MUTATION')
  if(-not $Commit){
    $log.Add('RESULT=READY_FOR_ONE_SHOT_APPROVED_STABLE_NO_MUTATION')
  }else{
    $phase='OUTER_LEGACY_MUTEXES'
    $mutexes=AcquireLegacyPair
    if($mutexes.Count -ne 2){StopNow 'OUTER_LEGACY_MUTEX_PAIR_INCOMPLETE'}
    $log.Add('OUTER_MAINTENANCE_AND_AGENTTICK_MUTEXES=HELD')
    if(-not(LinksStable)){StopNow 'USER_LINK_CHANGED_BEFORE_CUTOVER'}
    $phase='R27_OWNER_ONLY_RESIDENT_NEUTRAL_CUTOVER'
    $switch=@(& $r27 -HostedFixtureRoot $fixture -Commit -ApprovalPhrase 'APPROVE_ONLY_EXACT_OWNER_RESIDENT_NEUTRAL_CWD')
    if($switch -cnotcontains 'RESULT=EXACT_RESIDENT_CUTOVER_COMPLETED_OTHER_HANDLES_NOT_CERTIFIED' -or
       $switch -cnotcontains 'EXACT_OLD_RESIDENT_TERMINATED=YES'){
      StopNow 'R27_EXACT_OWNER_CUTOVER_NOT_COMPLETED'
    }
    $cutoverDone=$true
    $oldNeutral=OneExactResident $agent $wscript
    $oldNeutralCreation=[datetime]$oldNeutral.CreationDate
    $log.Add('EXACT_OLD_RESIDENT=REPLACED_WITH_NEUTRAL_CWD')
    if(-not(LinksStable)){StopNow 'USER_LINK_CHANGED_AFTER_CUTOVER'}
    $phase='OFFICIAL_BOOTSTRAP_CHECK'
    [void](InvokeOfficial $boot 'Check')
    $log.Add('OFFICIAL_BOOTSTRAP_PRECHECK=PASS')
    $phase='OFFICIAL_BOOTSTRAP_UPDATE_ONCE'
    [void](InvokeOfficial $boot 'Update')
    $updateCommitted=$true
    if((FileSHA $main) -cne $expectedMain -or
       (FileSHA $agent) -cne $expectedAgent -or
       (FileSHA $addon) -cne $new['bin/addon-manager.ps1']){
      StopNow 'OFFICIAL_BOOTSTRAP_COMMIT_FILE_PINS_MISMATCH'
    }
    $txn=Join-Path $root 'self-update-last-transaction.json'
    $journal=Get-Content -LiteralPath $txn -Raw | ConvertFrom-Json
    if([string]$journal.status -cne 'committed'){StopNow 'OFFICIAL_COMMIT_JOURNAL_NOT_TERMINAL'}
    $log.Add('OFFICIAL_MAIN_AND_RESIDENT_VBS=STABLE_COMMITTED_PINNED')
    $phase='OFFICIAL_BOOTSTRAP_POSTCHECK'
    [void](InvokeOfficial $boot 'Check')
    $log.Add('OFFICIAL_POSTCHECK=PASS')
    # New VBS bytes are installed, but old VBS remains in memory. Make the
    # new version the ONE resident before releasing either legacy mutex.
    $phase='START_NEW_RELEASE_RESIDENT'
    $liveOld=OneExactResident $agent $wscript
    if([int]$liveOld.ProcessId -ne [int]$oldNeutral.ProcessId -or
       [datetime]$liveOld.CreationDate -ne $oldNeutralCreation){
      StopNow 'OLD_NEUTRAL_RESIDENT_CHANGED_BEFORE_FINAL_HANDOFF'
    }
    $newVersionProcess=Start-Process -FilePath $wscript -WorkingDirectory $root -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru
    Start-Sleep -Seconds 2
    if($newVersionProcess.HasExited){StopNow 'NEW_RELEASE_RESIDENT_EXITED_EARLY'}
    $checked=OwnerProcess ([int]$newVersionProcess.Id)
    if($null -eq $checked -or
       -not(Same ([string]$checked.ExecutablePath) $wscript) -or
       -not(Same (VbsArg ([string]$checked.CommandLine)) $agent)){
      StopNow 'NEW_RELEASE_RESIDENT_NOT_EXACT_OWNER'
    }
    $again=OwnerProcess ([int]$oldNeutral.ProcessId)
    if($null -eq $again -or [datetime]$again.CreationDate -ne $oldNeutralCreation -or
       -not(Same ([string]$again.ExecutablePath) $wscript) -or
       -not(Same (VbsArg ([string]$again.CommandLine)) $agent)){
      StopNow 'OLD_NEUTRAL_RESIDENT_CHANGED_DURING_FINAL_HANDOFF'
    }
    if(-not [SpotifyR27VerifiedProcessEnd]::TerminateOnlyExact(
         [int]$oldNeutral.ProcessId,$oldNeutralCreation.ToUniversalTime().ToFileTimeUtc(),$wscript)){
      StopNow 'OLD_NEUTRAL_RESIDENT_TERMINATION_UNVERIFIED'
    }
    $oldNeutralEnded=$true
    $phase='VERIFY_ONE_NEW_RESIDENT_AND_OWNER_DATA'
    $one=OneExactResident $agent $wscript
    if([int]$one.ProcessId -ne [int]$newVersionProcess.Id -or $newVersionProcess.HasExited){
      StopNow 'NEW_RELEASE_RESIDENT_NOT_SINGLE'
    }
    if(-not(LinksStable) -or (FileSHA $stateFile) -cne $stateBefore -or
       ($hosted -and (FileSHA $sentinelFile) -cne $sentinelBefore)){
      StopNow 'OWNER_SHORTCUTS_OR_STATE_CHANGED'
    }
    $log.Add('NEW_RELEASE_VBS=ONE_EXACT_OWNER_RESIDENT_RUNNING')
    $log.Add('USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL')
    $log.Add($(if($hosted){'RESULT=HOSTED_FUTURE_STABLE_ONESHOT_COMMITTED'}else{'RESULT=PINNED_PUBLIC_STABLE_ONESHOT_COMMITTED'}))
    $finished=$true
  }
}catch{
  $r=[string]$_.Exception.Message
  $permitted=@('WINDOWS_REQUIRED','WINDOWS_PS51_X64_REQUIRED','PINNED_R27_SOURCE_NOT_MATCHED',
    'PUBLIC_RELEASE_INDEPENDENT_PINS_REQUIRED','HOSTED_RELEASE_OVERRIDE_NOT_ALLOWED',
    'PUBLIC_RELEASE_PINS_FORBIDDEN_IN_HOSTED_MODE','HOSTED_RELEASE_OVERRIDES_FORBIDDEN_IN_PUBLIC_MODE',
    'ORIGINAL_NORMAL_USER_ONLY',
    'HOSTED_FIXTURE_NOT_UNDER_RUNNER_TEMP','OWNER_ONE_SHOT_APPROVAL_REQUIRED',
    'HOSTED_RELEASE_SHA_PIN_REQUIRED','INSTALLED_STABLE_OR_BOOTSTRAP_NOT_EXACT',
    'PINNED_RELEASE_SOURCE_FACTS_REQUIRED','RELEASE_SOURCE_FACTS_JSON_INVALID',
    'RELEASE_SOURCE_FACTS_NOT_BOUND_TO_MANIFEST_AND_PAYLOAD',
    'SPOTIFY_MUST_BE_CLOSED','HOSTED_LOOPBACK_PORT_INVALID',
    'NEXT_STABLE_MANIFEST_SHA_NOT_PINNED','NEXT_STABLE_MANIFEST_NOT_JSON',
    'NEXT_STABLE_MANIFEST_NOT_SPECIFIED_TEST_RELEASE','NEXT_STABLE_RELEASE_FILE_PINS_MISMATCH',
    'USER_SHORTCUT_UNSAFE','R27_OWNER_PREFLIGHT_NOT_READY','OUTER_LEGACY_MUTEX_PAIR_INCOMPLETE',
    'USER_LINK_CHANGED_BEFORE_CUTOVER','R27_EXACT_OWNER_CUTOVER_NOT_COMPLETED',
    'USER_LINK_CHANGED_AFTER_CUTOVER','OFFICIAL_BOOTSTRAP_COMMIT_FILE_PINS_MISMATCH',
    'OFFICIAL_COMMIT_JOURNAL_NOT_TERMINAL','OLD_NEUTRAL_RESIDENT_CHANGED_BEFORE_FINAL_HANDOFF',
    'NEW_RELEASE_RESIDENT_EXITED_EARLY','NEW_RELEASE_RESIDENT_NOT_EXACT_OWNER',
    'OLD_NEUTRAL_RESIDENT_CHANGED_DURING_FINAL_HANDOFF',
    'OLD_NEUTRAL_RESIDENT_TERMINATION_UNVERIFIED','NEW_RELEASE_RESIDENT_NOT_SINGLE',
    'OWNER_SHORTCUTS_OR_STATE_CHANGED','SCRIPT_HOST_COUNT_NOT_BOUNDED',
    'RESIDENT_WSCRIPT_IMAGE_NOT_EXACT','RESIDENT_NOT_SAME_USER',
    'EXACT_SINGLE_RESIDENT_REQUIRED','ABANDONED_LEGACY_MUTEX','LEGACY_MUTEX_NOT_IDLE',
    'OUTER_LEGACY_MUTEX_PAIR_INCOMPLETE')
  if($r -cnotin $permitted -and
     $r -notmatch '^OFFICIAL_BOOTSTRAP_(Check|Update)_(FAILED_HOLD|UNVERIFIED_RECEIPT|UNEXPECTED_RESULT)$'){
    $r='UNVERIFIED_WINDOWS_OR_BOOTSTRAP_ERROR'
  }
  $log.Add('HOLD_STAGE='+$phase)
  $log.Add('HOLD_REASON='+$r)
  $log.Add('RESULT=HOLD_NO_AUTOMATIC_RETRY')
}finally{
  # This controller only terminates a process it CREATED, by exact
  # Win32 identity, if final handoff was NOT completed and a former
  # known resident may still be active. Never stop a foreign process.
  if(-not $finished -and $null -ne $newVersionProcess -and -not $newVersionProcess.HasExited){
    if($oldNeutralEnded){
      # Never leave the owner WITHOUT a resident merely because a late
      # receipt/state validation failed after the old agent was already
      # terminated. Continue HOLD/no retries; preserve the exact new one.
      $log.Add('NEW_RELEASE_RESIDENT=RETAINED_AFTER_OLD_RESIDENT_ENDED_HOLD')
    }else{
      try{
        $p=OwnerProcess ([int]$newVersionProcess.Id)
        if($null -ne $p -and
           (Same ([string]$p.ExecutablePath) (Join-Path $env:WINDIR 'System32\wscript.exe')) -and
           (Same (VbsArg ([string]$p.CommandLine)) $agent)){
          [void][SpotifyR27VerifiedProcessEnd]::TerminateOnlyExact(
            [int]$p.ProcessId,([datetime]$p.CreationDate).ToUniversalTime().ToFileTimeUtc(),
            (Join-Path $env:WINDIR 'System32\wscript.exe'))
        }
      }catch{}
    }
  }
  for($i=$mutexes.Count-1;$i -ge 0;$i--){
    try{$mutexes[$i].ReleaseMutex()}catch{}
    try{$mutexes[$i].Dispose()}catch{}
  }
  $log.Add('EXACT_INITIAL_CUTOVER_DONE='+$(if($cutoverDone){'YES'}else{'NO'}))
  $log.Add('OFFICIAL_UPDATE_INVOKED_SUCCESS='+$(if($updateCommitted){'YES'}else{'NO'}))
  $log.Add('USER_PRIVATE_PATHS_AND_PROCESS_IDS_EXPORTED=NO')
}
$log|ForEach-Object{Write-Output $_}
