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
$stage=Invoke-V058OwnedScratchQuiescence -LeaveDisabledForChild
Assert-V058 ([bool]$stage.disabled_verified -and
   -not[bool]$stage.production_mutation_authorized -and
   -not[bool]$stage.real_task_touched -and
   (Get-V058OwnedCount) -eq ($before+1) -and
   [IO.File]::Exists([string]$stage.journal_path) -and
   -not[bool]$folder.GetTask([string]$stage.scratch_task_name).Enabled) 'FRESH_PROCESS_STAGE_NOT_DISABLED'
$originalReceipt=[IO.File]::ReadAllBytes([string]$stage.journal_path)
try{
  # Tamper with the only on-disk identity pin; a restorer MUST refuse
  # before enabling anything. Original is preserved for recovery.
  $utf8=[Text.UTF8Encoding]::new($false,$true)
  $text=$utf8.GetString($originalReceipt)
  $tampered=[regex]::Replace($text,'(?<="action_xml_sha256":")[a-f0-9]{64}','0000000000000000000000000000000000000000000000000000000000000000')
  Assert-V058 ($tampered -cne $text) 'JOURNAL_TAMPER_TEST_DID_NOT_MODIFY_HASH'
  [IO.File]::WriteAllBytes([string]$stage.journal_path,[Text.Encoding]::UTF8.GetBytes($tampered))
  $denied=$false
  try{[void](Restore-V058OwnedScratchFromJournal -JournalPath ([string]$stage.journal_path))}
  catch{if([string]$_.Exception.Message -ceq 'V058_RECOVERY_CONCURRENT_TASK_DEFINITION_DRIFT'){$denied=$true}else{throw}}
  Assert-V058 ($denied -and
     -not[bool]$folder.GetTask([string]$stage.scratch_task_name).Enabled) 'ALTERED_JOURNAL_ENABLED_TASK'
  Write-Host 'V058_SEPARATE_RECOVERY_REJECTS_TAMPERED_DISK_JOURNAL_BEFORE_TASK_WRITE_PASS'
}finally{
 [IO.File]::WriteAllBytes([string]$stage.journal_path,$originalReceipt)
}
$child=Join-Path $PSScriptRoot 'scheduler-scratch-fresh-recover-v058.ps1'
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$process=New-Object Diagnostics.Process
try{
  $p=New-Object Diagnostics.ProcessStartInfo
  $p.FileName=$ps
  $p.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$child+'" -JournalPath "'+[string]$stage.journal_path+'"'
  $p.UseShellExecute=$false;$p.CreateNoWindow=$true
  $p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
  $process.StartInfo=$p
  if(-not$process.Start()){throw 'V058_CHILD_PROCESS_START_FAILED'}
  if(-not$process.WaitForExit(45000)){
    $process.Kill();[void]$process.WaitForExit()
    throw 'V058_CHILD_PROCESS_RECOVERY_TIMEOUT'
  }
  $stdout=$process.StandardOutput.ReadToEnd()
  $stderr=$process.StandardError.ReadToEnd()
  if($process.ExitCode -ne 0 -or
     $stdout.Length+$stderr.Length -gt 4000 -or
     -not$stdout.Contains('V058_SEPARATE_POWERSHELL_PROCESS_RESTORED_AND_REMOVED_ONLY_OWNED_SCRATCH_TASK_PASS')){
     $type=if($stderr.Contains('V058_RECOVERY_')){'V058_RECOVERY_DENIED'}
           else{'V058_CHILD_NON_POLICY_ERROR'}
     throw $type
  }
}finally{$process.Dispose()}
Assert-V058 ((Get-V058OwnedCount) -eq $before) 'FRESH_CHILD_LEFT_UNOWNED_OR_DISABLED_TASK'
Write-Host 'V058_FRESH_PROCESS_JOURNAL_RESTORED_AND_REMOVED_DISABLED_SCRATCH_TASK_PASS'
Write-Host 'V058_ONLY_EPHEMERAL_OWNED_SCRATCH_TASKS_TOUCHED_NO_LEGACY_OR_SPOTIFY_MUTATION_PASS'
