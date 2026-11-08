# Spotify Control 0.6.29 safe rollout: ONE read-only Windows installed-state proof.
# No downloads, network calls, app execution, file writes, task edits, or secrets.
# This is NOT authority to install/enable mutation. Output is a strict allowlist.
param(
  [string]$HostedFixtureRoot = ''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$canonical = [ordered]@{
  main    = @('spotify-control.ps1',284321,'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0')
  addon   = @('addon-manager.ps1',323385,'5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285')
  agent   = @('spotify-control-agent.vbs',4855,'2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278')
  bootstrap = @('spotify-control-self-updater.ps1',42963,'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6')
}
function Test-ContainedPath {
  param([Parameter(Mandatory=$true)][string]$Parent,
        [Parameter(Mandatory=$true)][string]$Child)
  $parentFull=[IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
  $childFull=[IO.Path]::GetFullPath($Child)
  return $childFull.StartsWith(($parentFull+'\'),[StringComparison]::OrdinalIgnoreCase)
}
function Test-PlainDirectory {
  param([string]$Path)
  if(-not [IO.Directory]::Exists($Path)){return $false}
  try {
    $entry=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return ($entry.PSIsContainer -and (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0))
  }catch{return $false}
}
function Get-PlainFile {
  param([string]$Path,[int64]$MaxSize)
  try {
    $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $null}
    if($file.Length -lt 0 -or $file.Length -gt $MaxSize){return $null}
    return $file
  }catch{return $null}
}
function Get-CanonicalStatus {
  param([string]$Path,[object[]]$Expected)
  try {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return 'ABSENT_OR_UNSAFE'}
    $file=Get-PlainFile -Path $Path -MaxSize 2097152
    if($null -eq $file){return 'ABSENT_OR_UNSAFE'}
    if([int64]$file.Length -ne [int64]$Expected[1]){return 'NOT_EXACT_STABLE'}
    $sha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($sha -cne [string]$Expected[2]){return 'NOT_EXACT_STABLE'}
    return 'EXACT_STABLE'
  }catch{return 'UNVERIFIED'}
}
function Get-Presence {
  param([string]$Directory,[string]$Leaf)
  try {
    $items=@(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop |
      Where-Object {$_.Name.Equals($Leaf,[StringComparison]::OrdinalIgnoreCase)})
    if($items.Count -eq 0){return 'ABSENT'}
    if($items.Count -ne 1){return 'UNKNOWN'}
    $item=$items[0]
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return 'UNKNOWN'}
    return 'PRESENT'
  }catch{return 'UNKNOWN'}
}
function Get-StateSummary {
  param([string]$Path)
  $unknown=[pscustomobject]@{
    status='UNKNOWN';schema='UNKNOWN';mutation='UNKNOWN'
    pending='UNKNOWN';health='UNKNOWN';ambiguity='UNKNOWN'
  }
  try{
    $file=Get-PlainFile -Path $Path -MaxSize 4194304
    if($null -eq $file -or $file.Length -lt 2){return $unknown}
    $s=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json
    if($null -eq $s){return $unknown}
    $schema='UNKNOWN'
    if($null -ne $s.PSObject.Properties['schema'] -and
       $s.schema -is [int] -and [int]$s.schema -ge 1 -and [int]$s.schema -le 50){
       $schema=[string]$s.schema
    }
    $armed='UNKNOWN'
    if($null -ne $s.PSObject.Properties['agent_mutation_enabled'] -and
       $s.agent_mutation_enabled -is [bool]){
       $armed=if($s.agent_mutation_enabled){'ENABLED'}else{'DISABLED'}
    }
    $pending='UNKNOWN'
    if($null -ne $s.PSObject.Properties['pending_maintenance'] -and
       $s.pending_maintenance -is [bool]){
       $pending=if($s.pending_maintenance){'YES'}else{'NO'}
    }
    $health='UNKNOWN'
    if($null -ne $s.PSObject.Properties['maintenance_check_healthy'] -and
       $s.maintenance_check_healthy -is [bool]){
       $health=if($s.maintenance_check_healthy){'HEALTHY'}else{'UNHEALTHY'}
    }
    $amb='UNKNOWN'
    if($null -ne $s.PSObject.Properties['pending_addon_auto_ambiguous'] -and
       $s.pending_addon_auto_ambiguous -is [int] -and [int]$s.pending_addon_auto_ambiguous -ge 0 -and
       [int]$s.pending_addon_auto_ambiguous -le 100000){
       $amb=if([int]$s.pending_addon_auto_ambiguous -eq 0){'ZERO'}else{'NONZERO'}
    }
    return [pscustomobject]@{
       status='READABLE';schema=$schema;mutation=$armed;pending=$pending;health=$health;ambiguity=$amb
    }
  }catch{return $unknown}
}
function Get-MaintenanceTask {
  param([string]$ExpectedMain)
  try{
    $svc=New-Object -ComObject Schedule.Service
    $svc.Connect()
    $folder=$svc.GetFolder('\')
    try{$task=$folder.GetTask('SpotifyControl Maintenance')}
    catch{
      if([int64]$_.Exception.HResult -eq -2147024894){return 'ABSENT'}
      return 'UNKNOWN'
    }
    if([string]$task.Path -cne '\SpotifyControl Maintenance'){return 'FOREIGN'}
    $def=$task.Definition
    $actions=@($def.Actions);$triggers=@($def.Triggers)
    if($actions.Count -ne 1 -or [int]$actions[0].Type -ne 0 -or
       $triggers.Count -ne 1 -or [int]$triggers[0].Type -ne 9){return 'FOREIGN'}
    $shell=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    if(-not([IO.Path]::GetFullPath([string]$actions[0].Path)).Equals($shell,[StringComparison]::OrdinalIgnoreCase)){
      return 'FOREIGN'
    }
    $quoted=[regex]::Escape([IO.Path]::GetFullPath($ExpectedMain))
    $pattern='(?i)^\s*-NoProfile\s+-WindowStyle\s+Hidden\s+-ExecutionPolicy\s+Bypass\s+-File\s+"'+
      $quoted+'"\s+-Action\s+Maintain\s*$'
    if([string]$actions[0].Arguments -cnotmatch $pattern -or
       -not[string]::IsNullOrWhiteSpace([string]$actions[0].WorkingDirectory)){return 'FOREIGN'}
    if(@($task.GetInstances(0)).Count -ne 0){return 'RUNNING_INSTANCE'}
    if([bool]$task.Enabled){return 'EXACT_ENABLED'}
    return 'EXACT_DISABLED'
  }catch{return 'UNKNOWN'}
}
function Get-ResidentTask {
  try{
    $svc=New-Object -ComObject Schedule.Service
    $svc.Connect()
    $folder=$svc.GetFolder('\')
    try{$task=$folder.GetTask('SpotifyControl Resident Agent')}
    catch{
      if([int64]$_.Exception.HResult -eq -2147024894){return 'ABSENT'}
      return 'UNKNOWN'
    }
    # Presence only, not authority or exact task identity.
    if([bool]$task.Enabled){return 'PRESENT_ENABLED_UNATTESTED'}
    return 'PRESENT_DISABLED_UNATTESTED'
  }catch{return 'UNKNOWN'}
}
function Get-StartupStatus {
  param([string]$Link,[string]$ExpectedMain,[string]$ExpectedRoot)
  try{
    $name=Split-Path -Leaf $Link
    $dir=Split-Path -Parent $Link
    if(-not (Test-PlainDirectory $dir)){return 'UNKNOWN'}
    $present=Get-Presence -Directory $dir -Leaf $name
    if($present -ceq 'ABSENT'){return 'ABSENT'}
    if($present -cne 'PRESENT'){return 'UNKNOWN'}
    $shell=New-Object -ComObject WScript.Shell
    # CreateShortcut opens an existing .lnk for reading. Do NOT Save().
    $lnk=$shell.CreateShortcut($Link)
    $exe=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    if(-not ([IO.Path]::GetFullPath([string]$lnk.TargetPath)).Equals($exe,[StringComparison]::OrdinalIgnoreCase)){
      return 'FOREIGN'
    }
    $quoted=[regex]::Escape([IO.Path]::GetFullPath($ExpectedMain))
    $pattern='(?i)^\s*-NoProfile\s+-WindowStyle\s+Hidden\s+-ExecutionPolicy\s+Bypass\s+-File\s+"'+
      $quoted+'"\s+-Action\s+Maintain\s*$'
    if([string]$lnk.Arguments -cnotmatch $pattern -or
       [string]$lnk.Description -cne 'Spotify Control automatic maintenance' -or
       -not ([IO.Path]::GetFullPath([string]$lnk.WorkingDirectory)).Equals(
        [IO.Path]::GetFullPath($ExpectedRoot),[StringComparison]::OrdinalIgnoreCase)){return 'FOREIGN'}
    return 'EXACT'
  }catch{return 'UNKNOWN'}
}
function Get-AgentProcessCount {
  param([string]$ExpectedAgent)
  try{
    $rows=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='wscript.exe' OR Name='cscript.exe'" -ErrorAction Stop)
    if($rows.Count -gt 5000){return 'UNKNOWN'}
    $found=0;$opaque=0
    $path=[regex]::Escape([IO.Path]::GetFullPath($ExpectedAgent))
    foreach($row in $rows){
      $command=[string]$row.CommandLine
      if([string]::IsNullOrWhiteSpace($command)){$opaque++;continue}
      if($command -match $path){$found++}
    }
    return ('MATCHED_'+[string]$found+'_OPAQUE_'+[string]$opaque)
  }catch{return 'UNKNOWN'}
}
function Get-SpicetifyConfigState {
  param([string]$Path)
  try{
    $file=Get-PlainFile -Path $Path -MaxSize 1048576
    if($null -eq $file){return 'ABSENT_OR_UNSAFE'}
    # Metadata only; no usernames, paths, contents or CustomApp names emitted.
    $text=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    $keys=[regex]::Matches($text,'(?im)^\s*custom_apps\s*=\s*([^\r\n]*)\s*$')
    if($keys.Count -ne 1){return 'AMBIGUOUS_OR_MISSING_KEY'}
    $names=@($keys[0].Groups[1].Value.Split('|') | Where-Object { $_.Trim().Length -gt 0 })
    if($names.Count -gt 200){return 'AMBIGUOUS_OR_MISSING_KEY'}
    return ('CUSTOM_APPS_'+$names.Count)
  }catch{return 'UNVERIFIED'}
}

$hosted= -not [string]::IsNullOrWhiteSpace($HostedFixtureRoot)
$root=$null;$startup=$null;$roaming=$null
$lines=New-Object 'System.Collections.Generic.List[string]'
$lines.Add('DIAGNOSTIC=SPOTIFY_CONTROL_V0629_ONEPASS_PREFLIGHT_R1')
$lines.Add('MODE=READ_ONLY;NETWORK=NO;INSTALL=NO;SPOTIFY_EXEC=NO;NO_TASK_CHANGE;NO_FILE_WRITE')
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'NON_WINDOWS'}
  if($hosted){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
       -not(Test-ContainedPath -Parent $env:RUNNER_TEMP -Child $HostedFixtureRoot)){
      throw 'HOSTED_FIXTURE_OVERRIDE_DENIED'
    }
    $base=[IO.Path]::GetFullPath($HostedFixtureRoot)
    $root=Join-Path $base 'LocalAppData\SpotifyControl'
    $startup=Join-Path $base 'Startup'
    $roaming=Join-Path $base 'Roaming'
  }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $roaming=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    $startup=[Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    if([string]::IsNullOrWhiteSpace($local) -or [string]::IsNullOrWhiteSpace($roaming) -or
       [string]::IsNullOrWhiteSpace($startup)){throw 'APPDATA_LOCATIONS_UNAVAILABLE'}
    $root=Join-Path $local 'SpotifyControl'
  }
  $bin=Join-Path $root 'bin'
  $boot=Join-Path $root 'bootstrap'
  $layoutOK=(Test-PlainDirectory $root) -and (Test-PlainDirectory $bin) -and (Test-PlainDirectory $boot)
  if(-not $layoutOK){throw 'EXPECTED_INSTALL_LAYOUT_ABSENT_OR_REPARSE'}
  $main=Join-Path $bin $canonical.main[0]
  $addon=Join-Path $bin $canonical.addon[0]
  $agent=Join-Path $bin $canonical.agent[0]
  $bootstrap=Join-Path $boot $canonical.bootstrap[0]
  $mainStatus=Get-CanonicalStatus -Path $main -Expected $canonical.main
  $addonStatus=Get-CanonicalStatus -Path $addon -Expected $canonical.addon
  $agentStatus=Get-CanonicalStatus -Path $agent -Expected $canonical.agent
  $bootStatus=Get-CanonicalStatus -Path $bootstrap -Expected $canonical.bootstrap
  $state=Get-StateSummary -Path (Join-Path $root 'state.json')
  $txAddon=Get-Presence -Directory $root -Leaf 'addon-last-transaction.json'
  $txSpice=Get-Presence -Directory $root -Leaf 'spicetify-last-transaction.json'
  $task=Get-MaintenanceTask -ExpectedMain $main
  $start=Get-StartupStatus -Link (Join-Path $startup 'SpotifyControl Maintenance.lnk') -ExpectedMain $main -ExpectedRoot $root
  $residentTask=Get-ResidentTask
  $residentProc=Get-AgentProcessCount -ExpectedAgent $agent
  $spiceConfig=Get-SpicetifyConfigState -Path (Join-Path $roaming 'spicetify\config-xpui.ini')
  $spotifyRunning='UNKNOWN'
  try{$spotifyRunning=if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -gt 0){'YES'}else{'NO'}}catch{}
  $lines.Add('MAIN='+$mainStatus)
  $lines.Add('ADDON='+$addonStatus)
  $lines.Add('RESIDENT_AGENT='+$agentStatus)
  $lines.Add('BOOTSTRAP='+$bootStatus)
  $lines.Add('STATE='+$state.status+';SCHEMA='+$state.schema)
  $lines.Add('AGENT_MUTATION='+$state.mutation)
  $lines.Add('PENDING_MAINTENANCE='+$state.pending+';HEALTH='+$state.health+';AUTO_AMBIGUITY='+$state.ambiguity)
  $lines.Add('ADDON_PENDING_TRANSACTION='+$txAddon)
  $lines.Add('SPICETIFY_TRANSACTION_FILE='+$txSpice+';STATUS=NOT_CLASSIFIED')
  $lines.Add('SCHEDULER_MAINTENANCE='+$task)
  $lines.Add('STARTUP_MAINTENANCE='+$start)
  $lines.Add('SCHEDULER_RESIDENT_AGENT='+$residentTask)
  $lines.Add('RESIDENT_PROCESS='+$residentProc)
  $lines.Add('SPOTIFY_RUNNING='+$spotifyRunning)
  $lines.Add('SPICETIFY_CONFIG='+$spiceConfig)
  $stable=($mainStatus -ceq 'EXACT_STABLE' -and $addonStatus -ceq 'EXACT_STABLE' -and
    $agentStatus -ceq 'EXACT_STABLE' -and $bootStatus -ceq 'EXACT_STABLE')
  $lines.Add('EXACT_STABLE_SOURCE_SET='+$(if($stable){'PASS'}else{'NOT_PROVEN'}))
  $lines.Add('RESULT='+$(if($stable){'BASELINE_ATTESTED_LIVE_UPDATE_NOT_AUTHORIZED'}else{'HOLD_CURRENT_INSTALL_UNVERIFIED'}))
}catch{
  $lines.Add('RESULT=HOLD_READONLY_INPUTS_UNVERIFIED')
}
$lines.Add('LIVE_INSTALL_AUTHORIZED=NO;CONFIG_EDIT=NO;SPOTIFY_UPDATE=NO;ORIGINALS_DELETE=NO')
$lines.Add('USER_IDENTIFIERS_PATHS_SECRET_VALUES_EXPORTED=NO')
$clipboard='SKIPPED_HOSTED'
if(-not $hosted){
  try{
    $copy=Get-Command Set-Clipboard -ErrorAction Stop
    Set-Clipboard -Value ($lines -join [Environment]::NewLine) -ErrorAction Stop
    $clipboard='COPIED'
  }catch{$clipboard='UNAVAILABLE'}
}
$lines.Add('CLIPBOARD='+$clipboard)
$lines | ForEach-Object {Write-Output $_}
