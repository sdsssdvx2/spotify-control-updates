# V059 exact real-source Maintenance task + fallback shortcut safety matrix.
# Creates ONLY a disposable .lnk under RUNNER_TEMP. No task registration,
# disabling, killing, user profile writes or Spotify/Addon execution.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V059_TEST_REQUIRES_HOSTED_WINDOWS'
}
. (Join-Path $PSScriptRoot 'stable-maintenance-surfaces-v059.ps1')
function Assert-V059([bool]$Condition,[string]$Reason){
 if(-not$Condition){throw ('V059_TEST_'+$Reason)}
}
function MustNeverAuthorize-V059($r){
 Assert-V059 (-not[bool]$r.live_cutover_go -and
              -not[bool]$r.manual_legacy_launch_excluded -and
              -not[bool]$r.older_unpatched_processes_excluded -and
              -not[bool]$r.production_mutation_authorized -and
              -not[bool]$r.installed_legacy_task_disabled) 'UNVERIFIED_REAL_CUTOVER_AUTHORITY'
}
$cases=@(
 [pscustomobject]@{task='EXACT_ENABLED';link='ABSENT';complete=$true;running=0;opaque=0;state='ONLOGON_TASK_LAUNCH_PRESENT'},
 [pscustomobject]@{task='ABSENT';link='EXACT';complete=$true;running=0;opaque=0;state='STARTUP_SHORTCUT_FALLBACK_PRESENT'},
 [pscustomobject]@{task='EXACT_ENABLED';link='EXACT';complete=$true;running=0;opaque=0;state='DUAL_AUTO_LAUNCH_COLLISION'},
 [pscustomobject]@{task='EXACT_DISABLED';link='ABSENT';complete=$true;running=0;opaque=0;state='EXACT_TASK_DISABLED_BUT_MANUAL_LAUNCH_UNFENCED'},
 [pscustomobject]@{task='ABSENT';link='ABSENT';complete=$true;running=0;opaque=0;state='NO_KNOWN_AUTO_LAUNCH_BUT_MANUAL_LAUNCH_UNFENCED'},
 [pscustomobject]@{task='EXACT_ENABLED';link='ABSENT';complete=$false;running=0;opaque=0;state='UNVERIFIED_EXECUTION_OR_OWNER'},
 [pscustomobject]@{task='EXACT_ENABLED';link='ABSENT';complete=$true;running=2;opaque=0;state='LEGACY_PROCESS_RUNNING'},
 [pscustomobject]@{task='EXACT_ENABLED';link='ABSENT';complete=$true;running=0;opaque=1;state='UNVERIFIED_EXECUTION_OR_OWNER'},
 [pscustomobject]@{task='FOREIGN';link='ABSENT';complete=$true;running=0;opaque=0;state='UNVERIFIED_EXECUTION_OR_OWNER'},
 [pscustomobject]@{task='ABSENT';link='UNKNOWN';complete=$true;running=0;opaque=0;state='UNVERIFIED_EXECUTION_OR_OWNER'}
)
foreach($c in $cases){
 $r=Resolve-V059MaintenanceLaunchTopology -TaskState $c.task -ShortcutState $c.link -ProcessScanComplete $c.complete -SuspectedLegacyProcesses $c.running -OpaqueProcesses $c.opaque
 MustNeverAuthorize-V059 $r
 Assert-V059 ([string]$r.launch_state -ceq [string]$c.state) ('UNEXPECTED_TOPOLOGY_'+$c.state)
}
Write-Host 'V059_TASK_STARTUP_DUAL_PROCESS_OPAQUE_AND_NO_TASK_STATES_FAIL_CLOSED_PASS'
$threw=$false
try{[void](Resolve-V059MaintenanceLaunchTopology -TaskState 'INVALID' -ShortcutState 'ABSENT' -ProcessScanComplete $true -SuspectedLegacyProcesses 0 -OpaqueProcesses 0)}
catch{if([string]$_.Exception.Message -ceq 'V059_INVALID_LAUNCH_TOPOLOGY_STATE'){$threw=$true}else{throw}}
Assert-V059 $threw 'UNKNOWN_TASK_STATE_WAS_ALLOWED'
$threw=$false
try{[void](Resolve-V059MaintenanceLaunchTopology -TaskState 'ABSENT' -ShortcutState 'ABSENT' -ProcessScanComplete $true -SuspectedLegacyProcesses -1 -OpaqueProcesses 0)}
catch{if([string]$_.Exception.Message -ceq 'V059_INVALID_LAUNCH_TOPOLOGY_STATE'){$threw=$true}else{throw}}
Assert-V059 $threw 'INVALID_NEGATIVE_PROCESS_COUNT_ALLOWED'
Write-Host 'V059_INVALID_ENUM_AND_NEGATIVE_COUNT_REJECTED_PASS'

$root=Join-Path $env:RUNNER_TEMP ('v059-entrypoints-'+[guid]::NewGuid().ToString('N'))
$local=Join-Path $root 'Local'
$startup=Join-Path $root 'Startup'
$folder=Join-Path $local 'SpotifyControl'
$bin=Join-Path $folder 'bin'
foreach($p in @($root,$local,$startup,$folder,$bin)){[void][IO.Directory]::CreateDirectory($p)}
$paths=Get-V059ExpectedMainAndStartupLocations -HostedLocalRoot $local -HostedStartupFolder $startup
Assert-V059 ([string]$paths.main -ceq (Join-Path $bin 'spotify-control.ps1') -and
 [string]$paths.startup_link -ceq (Join-Path $startup 'SpotifyControl Maintenance.lnk')) 'INSTALLER_SOURCE_PATHS_DIFFER'
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'ABSENT') 'MISSING_FALLBACK_LINK_NOT_ABSENT'
$wsh=New-Object -ComObject WScript.Shell
$lnk=$wsh.CreateShortcut($paths.startup_link)
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.TargetPath=$ps
$lnk.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$paths.main+'" -Action Maintain'
$lnk.WorkingDirectory=$paths.root
$lnk.Description='Spotify Control automatic maintenance'
$lnk.Save() # ONLY synthetic under RUNNER_TEMP
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'EXACT') 'REAL_WSH_COM_READ_ONLY_SHORTCUT_IDENTITY_NOT_VERIFIED'
$lnk.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$paths.main+'" -Action Evil'
$lnk.Save()
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'FOREIGN') 'MODIFIED_SHORTCUT_ARGUMENTS_NOT_BLOCKED'
$lnk.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$paths.main+'" -Action Maintain'
$lnk.TargetPath=Join-Path $env:SystemRoot 'System32\cmd.exe'
$lnk.Save()
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'FOREIGN') 'FOREIGN_EXECUTABLE_NOT_BLOCKED'
$lnk.TargetPath=$ps
$lnk.WorkingDirectory=$root
$lnk.Save()
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'FOREIGN') 'FOREIGN_WORKING_DIRECTORY_NOT_BLOCKED'
$lnk.WorkingDirectory=$paths.root
$lnk.Save()
Assert-V059 ((Get-V059StartupFallbackReadOnly -Link $paths.startup_link -ExpectedMain $paths.main -ExpectedRoot $paths.root) -ceq 'EXACT') 'RESTORED_SYNTHETIC_LINK_NOT_EXACT'
Write-Host 'V059_ACTUAL_WSH_COM_STARTUP_SHORTCUT_READ_ONLY_AND_FIVE_MUTATION_SCOPES_PASS'

# Actual Windows hosted scheduler: read ONLY exact public task name if it
# happens to exist. No installed account or modification assumed.
$taskState=Get-V059ScheduledMaintenanceReadOnly -ExpectedMain $paths.main
Assert-V059 ($taskState -cin @('ABSENT','UNKNOWN','FOREIGN','EXACT_ENABLED','EXACT_DISABLED')) 'HOSTED_TASK_READ_BAD_ENUM'
$summary=Resolve-V059MaintenanceLaunchTopology -TaskState $taskState -ShortcutState 'EXACT' -ProcessScanComplete $false -SuspectedLegacyProcesses 0 -OpaqueProcesses 0
MustNeverAuthorize-V059 $summary
Write-Host 'V059_HOSTED_REAL_SCHEDULER_READ_ONLY_NO_LIVE_APPROVAL_PASS'

# Cleanup only the synthetic temporary shortcut created in this test.
[IO.File]::Delete($paths.startup_link)
Assert-V059 (-not[IO.File]::Exists($paths.startup_link)) 'SYNTHETIC_STARTUP_LINK_CLEANUP_FAILED'
Write-Host 'V059_NO_USER_TASK_STARTUP_PROFILE_OR_SPOTIFY_CHANGED_PASS'
