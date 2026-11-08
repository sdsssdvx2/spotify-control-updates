# V058 hosted-only acceptance; ONLY synthetic decision objects + TWO new
# ephemeral tasks owned by this test. Never change any installed user task.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
 throw 'V058_NOT_GITHUB_HOSTED_WINDOWS'
}
. (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
function Assert-V058([bool]$Good,[string]$Reason){
 if(-not$Good){throw ('V058_TEST_'+$Reason)}
}
function CheckNeverGo-V058($x){
 Assert-V058 ($x.live_cutover_go -eq $false -and
 $x.production_mutation_authorized -eq $false -and
 $x.manual_legacy_launch_excluded -eq $false -and
 $x.older_unpatched_processes_excluded -eq $false) 'REAL_CUTOVER_AUTHORITY_LEAK'
}
function V058TestFixture {
 return [pscustomobject]@{
  task_identity_exact=$true
  task_disabled=$true
  instances_zero=$true
  process_observation_complete=$true
  manual_launch_fenced=$true
  source_lease_held=$true
  original_task_journal_durable=$true
 }
}
$a=V058TestFixture
$r=Resolve-V058QuiescenceDecision -Observation $a
CheckNeverGo-V058 $r
Assert-V058 ([string]$r.state -ceq 'CONDITIONAL_READINESS_ONLY' -and
  [bool]$r.task_observation_ready) 'ALL_SYNTHETIC_FIELDS_STILL_NO_PROD_ADMISSION'
$cases=[ordered]@{
 task_identity_exact='UNKNOWN_TASK_AUTHORITY'
 original_task_journal_durable='NO_DURABLE_ROLLBACK'
 task_disabled='NEW_LAUNCHES_NOT_BLOCKED'
 instances_zero='LEGACY_EXECUTION_NOT_DRAINED'
 process_observation_complete='PROCESS_VISIBILITY_INCOMPLETE'
 manual_launch_fenced='MANUAL_LEGACY_LAUNCH_UNFENCED'
 source_lease_held='NO_NEW_ENGINE_SOURCE_LEASE'
}
foreach($key in @($cases.Keys)){
 $input=V058TestFixture
 $input.$key=$false
 $r=Resolve-V058QuiescenceDecision -Observation $input
 CheckNeverGo-V058 $r
 Assert-V058 ([string]$r.state -ceq [string]$cases[$key]) ('UNSAFE_CONDITION_ACCEPTED_'+$key)
}
Write-Host 'V058_SEVEN_MISSING_BOUNDARIES_AND_ALL_TRUE_STILL_NO_PRODUCTION_AUTHORITY_PASS'
$bad=V058TestFixture;$bad.instances_zero='False'
$threw=$false
try{[void](Resolve-V058QuiescenceDecision -Observation $bad)}
catch{if([string]$_.Exception.Message -ceq 'V058_UNTYPED_OR_INCOMPLETE_OBSERVATION'){$threw=$true}else{throw}}
Assert-V058 $threw 'STRING_FALSE_MISCAST_AS_FALSE_BOOLEAN'
$bad=V058TestFixture;$bad.PSObject.Properties.Remove('task_disabled')
$threw=$false
try{[void](Resolve-V058QuiescenceDecision -Observation $bad)}
catch{if([string]$_.Exception.Message -ceq 'V058_UNTYPED_OR_INCOMPLETE_OBSERVATION'){$threw=$true}else{throw}}
Assert-V058 $threw 'OMITTED_DISABLED_FIELD_ALLOWED'
Write-Host 'V058_TYPED_OBSERVATION_AND_MISSING_FIELDS_FAIL_CLOSED_PASS'

$service=New-Object -ComObject Schedule.Service
$service.Connect()
$folder=$service.GetFolder('\')
function Get-V058OwnedCount {
 $tasks=@($folder.GetTasks(1))
 return @($tasks|Where-Object{([string]$_.Name) -cmatch '^V058-Scratch-[0-9a-f]{32}$'}).Count
}
$before=Get-V058OwnedCount
$ok=Invoke-V058OwnedScratchQuiescence
Assert-V058 ([bool]$ok.disabled_observed -and [bool]$ok.restored -and
   [bool]$ok.scratch_deleted -and
   -not[bool]$ok.production_mutation_authorized -and
   -not[bool]$ok.prior_user_tasks_modified -and
   (Get-V058OwnedCount) -eq $before) 'REAL_SCRATCH_DISABLE_REENABLE_DELETE_UNSAFE'
Write-Host 'V058_REAL_COM_SCRATCH_ENABLED_FALSE_THEN_ORIGINAL_TRUE_EXACT_XML_CAS_PASS'
$failed=$false
try{[void](Invoke-V058OwnedScratchQuiescence -InjectExceptionAfterDisable)}
catch{
 if([string]$_.Exception.Message -ceq 'V058_INJECTED_FAILURE_AFTER_JOURNALED_DISABLE'){
   $failed=$true
 }else{throw}
}
Assert-V058 ($failed -and (Get-V058OwnedCount) -eq $before) 'INJECTED_FAILURE_FAILED_SAFE_REENABLE_AND_CLEANUP'
Write-Host 'V058_INJECTED_FAILURE_AFTER_DURABLE_JOURNAL_NO_TASK_LEFT_DISABLED_PASS'
Write-Host 'V058_ONLY_EPHEMERAL_OWNED_SCRATCH_TASKS_TOUCHED_NO_LEGACY_OR_SPOTIFY_MUTATION_PASS'
