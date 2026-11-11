# R77 HOLD — owner Windows read-only ACL + version prepublication admission.
# Not an updater. No download, install, delete, Registry/ACL/config edit,
# process termination, Spotify/Spicetify apply, scheduled task or API call.
# Only a bounded clipboard summary changes, if Set-Clipboard is available.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R77_OWNER_ACL_READONLY')
$out.Add('NETWORK=NO;INSTALL=NO;UPDATE=NO;APPLY=NO;REGISTRY_WRITE=NO;ACL_WRITE=NO')
$out.Add('PROCESS_KILL=NO;SOURCE_WRITE=NO;CONFIG_WRITE=NO;USER_ORIGINAL_DELETE=NO')
$phase='ENVIRONMENT'
$errors=New-Object 'System.Collections.Generic.List[string]'
function Add([string]$key,[string]$value) {
  if($key -notmatch '^[A-Z0-9_]{2,48}$' -or $value -notmatch '^[A-Za-z0-9_.-]{1,110}$') {
    throw 'OUTPUT_ALLOWLIST_VIOLATION'
  }
  $out.Add(($key+'='+$value))
}
function ExactFile([string]$p,[long]$size,[string]$digest) {
  try {
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      return 'NOT_REGULAR'
    }
    if([long]$f.Length -ne $size){return 'SIZE_MISMATCH'}
    $got=(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($got -ceq $digest){return 'EXACT'}
    return 'SHA_MISMATCH'
  }catch [System.Management.Automation.ItemNotFoundException]{return 'MISSING'}
   catch [System.IO.FileNotFoundException]{return 'MISSING'}
   catch{return 'UNREADABLE'}
}
function PlainFile([string]$p) {
  try {
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return (-not $f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function Ver3([string]$v) {
  if($v -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,4})(?:\.|$)'){return $null}
  try{return [Version]::new([int]$Matches[1],[int]$Matches[2],[int]$Matches[3])}
  catch{return $null}
}
function SafeVersion([string]$v) {
  if($v -match '^(\d{1,3}\.\d{1,3}\.\d{1,4})(?:\.(\d{1,7}))?$'){
    $s=[string]$Matches[1]
    if($Matches[2]){$s+='.'+[string]$Matches[2]}
    return $s
  }
  return 'UNKNOWN'
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    throw 'WINDOWS_POWERSHELL_51_X64_REQUIRED'
  }
  if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or
     [string]::IsNullOrWhiteSpace($env:APPDATA)){throw 'USER_PROFILE_ENV_MISSING'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=[Security.Principal.WindowsPrincipal]::new($identity)
  Add 'OWNER_TOKEN' $(if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){'ELEVATED_READONLY'}else{'STANDARD_USER'})
  $root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $bin=Join-Path $root 'bin'
  $phase='EXACT_INSTALLED_STABLE'
  $pinMain=ExactFile (Join-Path $bin 'spotify-control.ps1') 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
  $pinAddon=ExactFile (Join-Path $bin 'addon-manager.ps1') 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
  $pinAgent=ExactFile (Join-Path $bin 'spotify-control-agent.vbs') 4855 '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
  $pinBoot=ExactFile (Join-Path $root 'bootstrap\spotify-control-self-updater.ps1') 42963 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
  Add 'STABLE_MAIN_V0628' $pinMain
  Add 'ADDON_MANAGER_R17' $pinAddon
  Add 'RESIDENT_VBS' $pinAgent
  Add 'OFFICIAL_BOOTSTRAP' $pinBoot
  $stable=($pinMain -ceq 'EXACT' -and $pinAddon -ceq 'EXACT' -and $pinAgent -ceq 'EXACT' -and $pinBoot -ceq 'EXACT')
  Add 'EXACT_INSTALLED_STACK' $(if($stable){'PASS'}else{'HOLD_NOT_EXACT'})
  $phase='OWNER_SPOTIFY_VERSION'
  $spotifyPath=Join-Path $env:APPDATA 'Spotify\Spotify.exe'
  $spotifyVer='UNKNOWN'
  $spotifySigner='UNKNOWN'
  if(PlainFile $spotifyPath) {
    try {
      $raw=[Diagnostics.FileVersionInfo]::GetVersionInfo($spotifyPath).ProductVersion
      if($null -ne $raw){$spotifyVer=SafeVersion ([string]$raw)}
    }catch{}
    try {
      $sign=Get-AuthenticodeSignature -LiteralPath $spotifyPath -ErrorAction Stop
      if([string]$sign.Status -ceq 'Valid' -and $null -ne $sign.SignerCertificate -and
         [string]$sign.SignerCertificate.Subject -match '(?i)(^|,)\s*O=Spotify AB(,|$)'){
        $spotifySigner='VALID_SPOTIFY_AB'
      }elseif([string]$sign.Status -ceq 'Valid'){$spotifySigner='VALID_OTHER_SIGNER'}
      else{$spotifySigner='NOT_VALID'}
    }catch{$spotifySigner='UNKNOWN'}
  }else{$spotifyVer='NOT_AT_STANDARD_PATH'}
  Add 'SPOTIFY_VERSION' $spotifyVer
  Add 'SPOTIFY_SIGNATURE' $spotifySigner
  $phase='SPICETIFY_DECLARED_VERSION'
  $cliPath=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
  $cliVer='UNKNOWN'
  $cliPin='UNKNOWN'
  if(PlainFile $cliPath){
    $cliPin='OTHER_OR_UNVERIFIED'
    try {
      $cliDigest=(Get-FileHash -LiteralPath $cliPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
      if($cliDigest -ceq '85576d80b04ef8922a7f7fe3befbf9fcc56025dfb699b21339b546893742f0c1'){
        $cliPin='OFFICIAL_2462'
        $cliVer='2.46.2'
      }elseif($cliDigest -ceq '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
        $cliPin='OFFICIAL_2464'
        $cliVer='2.46.4'
      }
      # Another CLI version can be reported by the installed binary, but
      # is never considered source-authenticated by this inspection.
    }catch{$cliPin='HASH_UNREADABLE'}
    if($cliPin -cnotin @('OFFICIAL_2462','OFFICIAL_2464')){
      # Version probing executes the existing user's CLI -v (non-mutating
      # command); do not run unknown linked paths or elevated programs.
      try {
        $v=@(& $cliPath -v 2>&1)
        if($LASTEXITCODE -eq 0 -and $v.Count -gt 0 -and
           ([string]($v -join ' ')) -match '\b(\d{1,3}\.\d{1,3}\.\d{1,4})\b'){
          $cliVer=[string]$Matches[1]
        }
      }catch{}
    }
  }else{$cliPin='NOT_AT_STANDARD_PATH'}
  Add 'SPICETIFY_CLI_VERSION' $cliVer
  Add 'SPICETIFY_CLI_SOURCE_PIN' $cliPin
  $phase='VERSION_COMPATIBILITY'
  $supported='UNKNOWN'
  $upper='UNKNOWN'
  $candidate=Ver3 $spotifyVer
  $min=[Version]::new(1,2,14)
  if($cliVer -ceq '2.46.2'){$upper='1.3.6'}
  if($cliVer -ceq '2.46.4'){$upper='1.3.7'}
  if($upper -ne 'UNKNOWN' -and $null -ne $candidate){
    $max=Ver3 $upper
    if($spotifySigner -cne 'VALID_SPOTIFY_AB'){$supported='UNVERIFIED_SPOTIFY_SIGNER'}
    elseif($candidate -lt $min -or $candidate -gt $max){$supported='OUTSIDE_SUPPORTED_RANGE'}
    elseif($cliPin -cnotin @('OFFICIAL_2462','OFFICIAL_2464')){$supported='VERSION_RANGE_ONLY_CLI_UNPINNED'}
    else{$supported='OFFICIALLY_SUPPORTED_RANGE'}
  }
  Add 'KNOWN_WINDOWS_COMPAT_MAX' $upper
  Add 'CURRENT_COMPATIBILITY' $supported
  $phase='RUNNING_PROCESS_COUNTS'
  $running='UNKNOWN'
  $resident='UNKNOWN'
  try{
    $spotifyCount=@(Get-Process -Name Spotify -ErrorAction Stop).Count
    $running=if($spotifyCount -eq 0){'CLOSED'}else{'RUNNING'}
  }catch [Microsoft.PowerShell.Commands.ProcessCommandException]{$running='CLOSED'}
  catch{}
  try{
    $processes=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
    $expected=Join-Path $bin 'spotify-control-agent.vbs'
    $quoted=[regex]::Escape($expected)
    $exact=@($processes | Where-Object {
      $line=[string]$_.CommandLine
      $line -match ('(?i)(^|[\s"])'+$quoted+'(?=$|[\s"])')
    }).Count
    $resident=if($exact -eq 1){'ONE_MATCH'}elseif($exact -eq 0){'NONE_MATCH'}else{'MULTIPLE_MATCH'}
  }catch{}
  Add 'SPOTIFY_PROCESS' $running
  Add 'RESIDENT_PROCESS_PATH_MATCH' $resident
  $phase='SAVED_STATE_READONLY'
  $state='MISSING_OR_UNREADABLE'
  $armed='UNKNOWN'
  $stateGuard='UNKNOWN'
  $statePath=Join-Path $root 'state.json'
  if(PlainFile $statePath){
    try{
      $size=(Get-Item -LiteralPath $statePath -ErrorAction Stop).Length
      if($size -ge 10 -and $size -le 2097152){
        $doc=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $state='PARSED_NOT_AUTHORITY'
        $armed=if($doc.agent_mutation_enabled -eq $true){'ARMED_SAVED'}elseif($doc.agent_mutation_enabled -eq $false){'OFF_SAVED'}else{'UNKNOWN'}
        $rawGuard=[string]$doc.guard_enforced
        if($rawGuard -cin @('blocked','unblocked','unknown')){$stateGuard=($rawGuard.ToUpperInvariant()+'_REPORTED_ONLY')}
      }
    }catch{}
  }
  Add 'STATE_FILE' $state
  Add 'AGENT_MUTATION_SAVED' $armed
  Add 'SPOTIFY_UPDATE_GUARD_SAVED' $stateGuard
  $phase='LIVE_SPOTIFY_UPDATE_ACL'
  # Mirror the exact pinned future-main Get-SpotifyUpdateDirectory
  # and Get-SpotifyUpdateAclState read-only predicate. No filesystem
  # writes and no CLI icacls execution occur in this user-side script.
  $updateDir=Join-Path $env:LOCALAPPDATA 'Spotify\Update'
  $aclNow='UNKNOWN'
  try {
    $folder=Get-Item -LiteralPath $updateDir -Force -ErrorAction Stop
    if(-not $folder.PSIsContainer){
      $aclNow='NOT_A_DIRECTORY'
    }elseif(($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      $aclNow='REPARSE_HOLD'
    }else{
      $acl=Get-Acl -LiteralPath $updateDir -ErrorAction Stop
      $sidText=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
      if([string]::IsNullOrWhiteSpace($sidText)){throw 'UNKNOWN_USER_SID'}
      $denyWrite=$false
      $denyDelete=$false
      foreach($rule in $acl.Access){
        if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Deny){continue}
        $ruleSid=''
        try{
          $ruleSid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        }catch{
          $ruleSid=[string]$rule.IdentityReference
        }
        if($ruleSid -cne $sidText -and $ruleSid -cne ('*'+$sidText)){continue}
        $rights=[Security.AccessControl.FileSystemRights]$rule.FileSystemRights
        $writeMask=(
          [Security.AccessControl.FileSystemRights]::Write -bor
          [Security.AccessControl.FileSystemRights]::WriteData -bor
          [Security.AccessControl.FileSystemRights]::CreateFiles -bor
          [Security.AccessControl.FileSystemRights]::AppendData -bor
          [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
          [Security.AccessControl.FileSystemRights]::Modify
        )
        if(($rights -band $writeMask) -ne 0){$denyWrite=$true}
        if(($rights -band [Security.AccessControl.FileSystemRights]::Delete) -ne 0){
          $denyDelete=$true
        }
      }
      $aclNow=if($denyWrite -and $denyDelete){
        'OWNER_WRITE_DELETE_DENY_ACE_PRESENT'
      }else{
        'OWNER_DENY_ACE_INCOMPLETE'
      }
    }
  }catch [System.Management.Automation.ItemNotFoundException]{
    $aclNow='UPDATE_DIR_ABSENT'
  }catch [System.IO.DirectoryNotFoundException]{
    $aclNow='UPDATE_DIR_ABSENT'
  }catch{
    $aclNow='UNKNOWN_ACL_READ_ERROR'
  }
  Add 'UPDATE_FOLDER_ACL_NOW' $aclNow
  $guardMatch='NOT_CERTIFIED'
  if($stateGuard -ceq 'BLOCKED_REPORTED_ONLY'){
    $guardMatch=if($aclNow -ceq 'OWNER_WRITE_DELETE_DENY_ACE_PRESENT'){
      'SAVED_BLOCKED_MATCHES_LIVE_ACL'
    }elseif($aclNow -cin @('OWNER_DENY_ACE_INCOMPLETE','UPDATE_DIR_ABSENT')){
      'SAVED_BLOCKED_ACL_MISMATCH'
    }else{'UNVERIFIED'}
  }elseif($stateGuard -ceq 'UNBLOCKED_REPORTED_ONLY'){
    $guardMatch=if($aclNow -ceq 'OWNER_WRITE_DELETE_DENY_ACE_PRESENT'){
      'SAVED_UNBLOCKED_ACL_MISMATCH'
    }elseif($aclNow -cin @('OWNER_DENY_ACE_INCOMPLETE','UPDATE_DIR_ABSENT')){
      'SAVED_UNBLOCKED_MATCHES_ACL'
    }else{'UNVERIFIED'}
  }
  Add 'SAVED_GUARD_VS_ACL' $guardMatch
  Add 'ACL_PROOF_LEVEL' 'OWNER_DENY_ACES_ONLY_NOT_ACCESS_CHECK'
  $phase='FINAL_ADMISSION'
  $admission='HOLD_REVIEW_ONLY'
  if($stable -and $spotifySigner -ceq 'VALID_SPOTIFY_AB' -and
     $supported -ceq 'OFFICIALLY_SUPPORTED_RANGE' -and
     $running -ceq 'CLOSED' -and $resident -ceq 'ONE_MATCH' -and
     $armed -ceq 'OFF_SAVED'){
     $admission='PRECHECK_PASS_NOT_INSTALL_AUTHORITY'
  }
  Add 'OWNER_ROLLOUT_ADMISSION' $admission
  $environment='HOLD_REVIEW_ONLY'
  if($stable -and $spotifySigner -ceq 'VALID_SPOTIFY_AB' -and
     $supported -ceq 'OFFICIALLY_SUPPORTED_RANGE' -and
     $running -ceq 'CLOSED' -and $resident -ceq 'ONE_MATCH' -and
     $armed -cin @('ARMED_SAVED','OFF_SAVED') -and
     $guardMatch -ceq 'SAVED_BLOCKED_MATCHES_LIVE_ACL'){
    $environment='READONLY_CONSISTENT_NOT_DEPLOY_AUTHORITY'
  }
  Add 'OWNER_ENVIRONMENT_PRECHECK' $environment
  Add 'RESULT' 'READONLY_SNAPSHOT_COMPLETE'
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -notin @('WINDOWS_POWERSHELL_51_X64_REQUIRED','USER_PROFILE_ENV_MISSING')){
    $reason='UNCLASSIFIED_READONLY_ERROR'
  }
  Add 'FAILED_PHASE' $phase
  Add 'HOLD_REASON' $reason
  Add 'RESULT' 'HOLD_READONLY'
}finally{
  $out.Add('AUTHORIZE_DEPLOY=NO;AUTOMATIC_RETRY=NO;OWNER_SOURCE_CHANGE=NO')
  $out.Add('RAW_PATHS_SECRETS_PID_AND_PROCESS_ARGS_OUTPUT=NO')
  $out.Add('PUBLIC_BASELINE_RELEASE=V0628;NEXT_RELEASE=NOT_PUBLISHED')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out | ForEach-Object {Write-Output $_}
}
