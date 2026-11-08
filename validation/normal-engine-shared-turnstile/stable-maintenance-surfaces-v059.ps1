# V059 stable Spotify Control v0.6.28 EXACT maintenance launch surfaces.
# Source-verified Install-TasksAndShortcuts:
#  - root scheduled task "SpotifyControl Maintenance", ONLOGON /DELAY 0001:00
#  - only if scheduling fails: per-user Startup fallback link of same name
#  - both launch spotify-control.ps1 -Action Maintain
#  - separately resident spotify-control-agent.vbs calls -Action AgentTick
# Never write, delete, disable, stop or register a real task/link/process.
Set-StrictMode -Version 2.0

function Resolve-V059MaintenanceLaunchTopology {
 param([Parameter(Mandatory=$true)][string]$TaskState,
       [Parameter(Mandatory=$true)][string]$ShortcutState,
       [Parameter(Mandatory=$true)][bool]$ProcessScanComplete,
       [Parameter(Mandatory=$true)][int]$SuspectedLegacyProcesses,
       [Parameter(Mandatory=$true)][int]$OpaqueProcesses)
 $tasks=@('ABSENT','EXACT_ENABLED','EXACT_DISABLED','FOREIGN','UNKNOWN')
 $links=@('ABSENT','EXACT','FOREIGN','UNKNOWN')
 if($TaskState -cnotin $tasks -or $ShortcutState -cnotin $links -or
    $SuspectedLegacyProcesses -lt 0 -or $OpaqueProcesses -lt 0){
    throw 'V059_INVALID_LAUNCH_TOPOLOGY_STATE'
 }
 $taskActive=($TaskState -ceq 'EXACT_ENABLED')
 $startupActive=($ShortcutState -ceq 'EXACT')
 $uncertain=($TaskState -cin @('FOREIGN','UNKNOWN') -or
    $ShortcutState -cin @('FOREIGN','UNKNOWN') -or
    -not$ProcessScanComplete -or $OpaqueProcesses -gt 0)
 $state=if($uncertain){'UNVERIFIED_EXECUTION_OR_OWNER'}
        elseif($taskActive -and $startupActive){'DUAL_AUTO_LAUNCH_COLLISION'}
        elseif($SuspectedLegacyProcesses -gt 0){'LEGACY_PROCESS_RUNNING'}
        elseif($taskActive){'ONLOGON_TASK_LAUNCH_PRESENT'}
        elseif($startupActive){'STARTUP_SHORTCUT_FALLBACK_PRESENT'}
        elseif($TaskState -ceq 'EXACT_DISABLED'){'EXACT_TASK_DISABLED_BUT_MANUAL_LAUNCH_UNFENCED'}
        else{'NO_KNOWN_AUTO_LAUNCH_BUT_MANUAL_LAUNCH_UNFENCED'}
 return [pscustomobject]@{
   schema=1;launch_state=$state
   task_state=$TaskState;shortcut_state=$ShortcutState
   task_active=$taskActive;startup_active=$startupActive
   process_scan_complete=$ProcessScanComplete
   suspected_legacy_processes=$SuspectedLegacyProcesses
   opaque_processes=$OpaqueProcesses
   known_dual_auto_launch=($taskActive -and $startupActive)
   exact_production_scheduler_task_name='SpotifyControl Maintenance'
   exact_per_user_startup_link_name='SpotifyControl Maintenance.lnk'
   separate_resident_agent_entrypoint='spotify-control-agent.vbs'
   separate_resident_action='AgentTick'
   # Source proof does not reveal which path is installed on the user's PC.
   # A clear snapshot cannot prevent later unpatched manual launch.
   installed_legacy_task_disabled=$false
   manual_legacy_launch_excluded=$false
   older_unpatched_processes_excluded=$false
   live_cutover_go=$false
   production_mutation_authorized=$false
 }
}

function Get-V059ExpectedMainAndStartupLocations {
 param([string]$HostedLocalRoot=$null,[string]$HostedStartupFolder=$null)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'V059_WINDOWS_ONLY'
 }
 $fixture= -not[string]::IsNullOrWhiteSpace($HostedLocalRoot)
 if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
       throw 'V059_HOSTED_PATH_OVERRIDE_ONLY'
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $local=[IO.Path]::GetFullPath($HostedLocalRoot).TrimEnd('\','/')
    $startup=[IO.Path]::GetFullPath($HostedStartupFolder).TrimEnd('\','/')
    if(-not$local.StartsWith($runner+'\',[StringComparison]::OrdinalIgnoreCase) -or
       -not$startup.StartsWith($runner+'\',[StringComparison]::OrdinalIgnoreCase)){
       throw 'V059_HOSTED_PATH_OUTSIDE_PRIVATE_RUNNER_TEMP'
    }
 }else{
    if(-not[string]::IsNullOrWhiteSpace($HostedStartupFolder)){
       throw 'V059_STARTUP_ONLY_HOSTED_OVERRIDE_FORBIDDEN'
    }
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $startup=[Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    if([string]::IsNullOrWhiteSpace($local) -or
       [string]::IsNullOrWhiteSpace($startup)){throw 'V059_REAL_WINDOWS_PROFILE_FOLDERS_NOT_READABLE'}
    $local=[IO.Path]::GetFullPath($local).TrimEnd('\','/')
    $startup=[IO.Path]::GetFullPath($startup).TrimEnd('\','/')
 }
 return [pscustomobject]@{
    main=Join-Path $local 'SpotifyControl\bin\spotify-control.ps1'
    addon=Join-Path $local 'SpotifyControl\bin\addon-manager.ps1'
    agent=Join-Path $local 'SpotifyControl\bin\spotify-control-agent.vbs'
    root=Join-Path $local 'SpotifyControl'
    startup_link=Join-Path $startup 'SpotifyControl Maintenance.lnk'
 }
}

function Get-V059StartupFallbackReadOnly {
 param([Parameter(Mandatory=$true)][string]$Link,
       [Parameter(Mandatory=$true)][string]$ExpectedMain,
       [Parameter(Mandatory=$true)][string]$ExpectedRoot)
 if(-not[IO.File]::Exists($Link)){return 'ABSENT'}
 try{
    $attrs=[IO.File]::GetAttributes($Link)
    if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){return 'FOREIGN'}
    if([IO.Path]::GetExtension($Link) -cne '.lnk'){return 'FOREIGN'}
    $obj=New-Object -ComObject WScript.Shell
    # Read shortcut properties ONLY. Never call Save() / CreateLink.
    $lnk=$obj.CreateShortcut($Link)
    $exe=[string]$lnk.TargetPath
    $args=[string]$lnk.Arguments
    $wd=[string]$lnk.WorkingDirectory
    $p=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    $file=[regex]::Escape([IO.Path]::GetFullPath($ExpectedMain))
    $pattern='(?i)^\s*-NoProfile\s+-WindowStyle\s+Hidden\s+-ExecutionPolicy\s+Bypass\s+-File\s+"'+
      $file+'"\s+-Action\s+Maintain\s*$'
    if(-not([IO.Path]::GetFullPath($exe)).Equals($p,[StringComparison]::OrdinalIgnoreCase) -or
        $args -cnotmatch $pattern -or
        -not ([IO.Path]::GetFullPath($wd)).Equals([IO.Path]::GetFullPath($ExpectedRoot),
             [StringComparison]::OrdinalIgnoreCase)){
        return 'FOREIGN'
    }
    return 'EXACT'
 }catch{
    return 'UNKNOWN'
 }
}

function Get-V059ScheduledMaintenanceReadOnly {
 param([Parameter(Mandatory=$true)][string]$ExpectedMain)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'V059_WINDOWS_ONLY'
 }
 try{
    $service=New-Object -ComObject Schedule.Service
    $service.Connect()
    $root=$service.GetFolder('\')
    $task=$null
    try{$task=$root.GetTask('SpotifyControl Maintenance')}
    catch{
      if([int64]$_.Exception.HResult -eq -2147024894){return 'ABSENT'}
      return 'UNKNOWN'
    }
    if([string]$task.Path -cne '\SpotifyControl Maintenance'){return 'FOREIGN'}
    $def=$task.Definition
    $actions=@($def.Actions)
    $triggers=@($def.Triggers)
    if($actions.Count -ne 1 -or [int]$actions[0].Type -ne 0 -or
       $triggers.Count -ne 1 -or [int]$triggers[0].Type -ne 9){
       return 'FOREIGN'
    }
    $exe=[IO.Path]::GetFullPath([string]$actions[0].Path)
    $expected=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $normalized=[IO.Path]::GetFullPath($expected)
    if(-not$exe.Equals($normalized,[StringComparison]::OrdinalIgnoreCase)){
        return 'FOREIGN'
    }
    $args=[string]$actions[0].Arguments
    $p=[regex]::Escape([IO.Path]::GetFullPath($ExpectedMain))
    $pattern='(?i)^\s*-NoProfile\s+-WindowStyle\s+Hidden\s+-ExecutionPolicy\s+Bypass\s+-File\s+"'+
        $p+'"\s+-Action\s+Maintain\s*$'
    if($args -cnotmatch $pattern){return 'FOREIGN'}
    if([bool]$task.Enabled){return 'EXACT_ENABLED'}
    return 'EXACT_DISABLED'
 }catch{
    return 'UNKNOWN'
 }
}
