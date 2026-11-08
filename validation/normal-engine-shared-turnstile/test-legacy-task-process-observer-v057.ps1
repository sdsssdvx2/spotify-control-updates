# V057 hosted acceptance. Synthetic admission cases plus Windows COM/CIM read
# on disposable GitHub runner. No scheduled-task or process writes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
 throw 'V057_TEST_REQUIRES_HOSTED_WINDOWS'
}
. (Join-Path $PSScriptRoot 'legacy-task-process-observer-v057.ps1')
function Assert-V057([bool]$Condition,[string]$Why){
 if(-not$Condition){throw ('V057_TEST_'+$Why)}
}
function Snapshot-V057 {
 return [pscustomobject]@{
    task_scan_complete=$true;process_scan_complete=$true
    hidden_tasks_requested=$true
    task_count=[int]23;suspect_task_count=[int]0
    enabled_suspect_task_count=[int]0;running_suspect_task_count=[int]0
    opaque_task_action_count=[int]0;suspect_process_count=[int]0
    opaque_shell_process_count=[int]0;read_errors=[int]0
 }
}
function Assert-V057NoAuthority($Result){
 Assert-V057 (-not[bool]$Result.live_cutover_go -and
   -not[bool]$Result.production_mutation_authorized -and
   -not[bool]$Result.new_engine_enrollment_authorized -and
   -not[bool]$Result.manual_legacy_launch_excluded -and
   -not[bool]$Result.earlier_unpatched_processes_excluded -and
   -not[bool]$Result.scheduler_registration_modified -and
   -not[bool]$Result.scheduler_running_instances_terminated) 'ACCIDENTAL_PRODUCTION_AUTHORITY'
}
$clean=Snapshot-V057
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $clean
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'READ_ONLY_CLEAR_BUT_RACY' -and $r.scan_complete) 'FALSE_GLOBAL_RACE_PROOF'
Write-Host 'V057_ZERO_VISIBLE_WRITERS_STILL_NOT_EXCLUSIVE_NO_MUTATION_AUTHORITY_PASS'
$t=Snapshot-V057;$t.suspect_task_count=1;$t.enabled_suspect_task_count=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'LEGACY_WRITERS_POSSIBLE') 'ENABLED_LEGACY_TASK_NOT_DETECTED'
$t=Snapshot-V057;$t.suspect_task_count=1;$t.running_suspect_task_count=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'LEGACY_WRITERS_POSSIBLE') 'RUNNING_DISABLED_TASK_NOT_DETECTED'
$t=Snapshot-V057;$t.suspect_process_count=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'LEGACY_WRITERS_POSSIBLE') 'MANUAL_LEGACY_LAUNCH_NOT_DETECTED'
Write-Host 'V057_ENABLED_RUNNING_LEGACY_TASK_AND_MANUAL_PROCESS_DENIED_PASS'
$t=Snapshot-V057;$t.opaque_task_action_count=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'OPAQUE_EXECUTION_PATHS') 'OPAQUE_TASK_NOT_BLOCKED'
$t=Snapshot-V057;$t.opaque_shell_process_count=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'OPAQUE_EXECUTION_PATHS') 'OPAQUE_PROCESS_NOT_BLOCKED'
$t=Snapshot-V057;$t.hidden_tasks_requested=$false
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'INCOMPLETE_FAIL_CLOSED') 'HIDDEN_TASK_SCAN_NOT_REQUIRED'
$t=Snapshot-V057;$t.task_scan_complete=$false
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'INCOMPLETE_FAIL_CLOSED') 'PARTIAL_SCAN_NOT_BLOCKED'
$t=Snapshot-V057;$t.read_errors=1
$r=Resolve-CustomAppV057CutoverObservation -Snapshot $t
Assert-V057NoAuthority $r
Assert-V057 ($r.state -ceq 'INCOMPLETE_FAIL_CLOSED') 'ACCESS_DENIED_NOT_BLOCKED'
Write-Host 'V057_HIDDEN_TASKS_OPAQUE_COMMANDS_ACCESS_FAILURES_FAIL_CLOSED_PASS'
$missing=Snapshot-V057
$missing.PSObject.Properties.Remove('task_count')
$denied=$false
try{[void](Resolve-CustomAppV057CutoverObservation -Snapshot $missing)}
catch{if([string]$_.Exception.Message -ceq 'V057_SNAPSHOT_MISSING_REQUIRED_FIELD'){$denied=$true}else{throw}}
Assert-V057 $denied 'MISSING_SCHEMA_NOT_REJECTED'
$negative=Snapshot-V057;$negative.opaque_task_action_count=-1
$denied=$false
try{[void](Resolve-CustomAppV057CutoverObservation -Snapshot $negative)}
catch{if([string]$_.Exception.Message -ceq 'V057_SNAPSHOT_INVALID_NONNEGATIVE_COUNT'){$denied=$true}else{throw}}
Assert-V057 $denied 'NEGATIVE_COUNT_NOT_REJECTED'
Write-Host 'V057_INVALID_SCHEMA_AND_NEGATIVE_COUNT_REJECTED_PASS'
$badBool=Snapshot-V057;$badBool.task_scan_complete='False'
$denied=$false
try{[void](Resolve-CustomAppV057CutoverObservation -Snapshot $badBool)}
catch{if([string]$_.Exception.Message -ceq 'V057_SNAPSHOT_INVALID_BOOLEAN'){$denied=$true}else{throw}}
Assert-V057 $denied 'STRING_FALSE_MUST_NOT_COUNT_AS_BOOLEAN_TRUE'
$badCounts=Snapshot-V057
$badCounts.task_count=2;$badCounts.suspect_task_count=3
$denied=$false
try{[void](Resolve-CustomAppV057CutoverObservation -Snapshot $badCounts)}
catch{if([string]$_.Exception.Message -ceq 'V057_SNAPSHOT_INCONSISTENT_COUNTS'){$denied=$true}else{throw}}
Assert-V057 $denied 'IMPOSSIBLE_SUSPECT_TASK_COUNT_NOT_REJECTED'
Write-Host 'V057_TYPED_BOOLEAN_FALSE_AND_IMPOSSIBLE_COUNTS_REJECTED_PASS'

$real=Get-CustomAppV057ReadOnlyWindowsInventory
Assert-V057NoAuthority $real
Assert-V057 ($real.schema -eq 1 -and
  $real.state -in @('READ_ONLY_CLEAR_BUT_RACY','LEGACY_WRITERS_POSSIBLE',
    'OPAQUE_EXECUTION_PATHS','INCOMPLETE_FAIL_CLOSED') -and
  $real.task_count -ge 0 -and $real.suspect_task_count -ge 0 -and
  $real.suspect_process_count -ge 0) 'WINDOWS_REAL_READONLY_INVENTORY_INVALID'
Write-Host ('V057_WINDOWS_COM_HIDDEN_TASK_AND_CIM_PROBE_SANITIZED_PASS state='+$real.state+
 ';complete='+$real.scan_complete+
 ';task_count='+$real.task_count+
 ';suspect_tasks='+$real.suspect_task_count+
 ';suspect_processes='+$real.suspect_process_count+
 ';unknown_or_inaccessible='+$real.unknown_or_inaccessible_count)
Write-Host 'V057_NO_SCHEDULER_WRITE_NO_STOP_NO_PROCESS_KILL_NO_REAL_SPOTIFY_CHANGE_PASS'
