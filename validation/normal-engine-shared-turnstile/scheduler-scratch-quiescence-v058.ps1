# V058: isolated GitHub-hosted Windows Task Scheduler scratch acceptance.
# NOT an operating legacy-task adapter, NOT a deployment or cutover gate.
# Changes ONLY a newly created and uniquely owned V058-Scratch-<GUID> task.
# Does not invoke, stop, kill, or alter any existing scheduled job.
# Reversible Enabled property only; NEVER re-registers the task during restore.
Set-StrictMode -Version 2.0

function Get-V058Utf8Sha256([string]$Value){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{
   return ([BitConverter]::ToString($sha.ComputeHash(
     [Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','').ToLowerInvariant()
 }finally{$sha.Dispose()}
}
function Assert-V058HostedScope {
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
    -not[IO.Directory]::Exists($env:RUNNER_TEMP)){
    throw 'V058_GITHUB_HOSTED_WINDOWS_ONLY'
 }
}
function Get-V058ScratchXmlIdentity {
 param([Parameter(Mandatory=$true)][string]$TaskXml)
 if($TaskXml.Length -lt 100 -or $TaskXml.Length -gt 131072 -or
   $TaskXml -match '(?i)<!DOCTYPE|<!ENTITY'){
   throw 'V058_TASK_XML_NOT_SIMPLE'
 }
 $doc=New-Object System.Xml.XmlDocument
 $doc.XmlResolver=$null
 $reader=New-Object IO.StringReader($TaskXml)
 try{$doc.Load($reader)}finally{$reader.Dispose()}
 $enabled=@($doc.SelectNodes('/*[local-name()="Task"]/*[local-name()="Settings"]/*[local-name()="Enabled"]'))
 if($enabled.Count -ne 1 -or
    [string]$enabled[0].InnerText -cnotin @('true','false')){
    throw 'V058_EXPECTED_ONLY_SETTINGS_ENABLED_NODE'
 }
 $actions=@($doc.SelectNodes('/*[local-name()="Task"]/*[local-name()="Actions"]/*[local-name()="Exec"]'))
 $allActions=@($doc.SelectNodes('/*[local-name()="Task"]/*[local-name()="Actions"]/*'))
 if($actions.Count -ne 1 -or $allActions.Count -ne 1){
    throw 'V058_EXEC_ACTION_NOT_EXACTLY_ONE'
 }
 $cmd=@($actions[0].SelectNodes('./*[local-name()="Command"]'))
 $args=@($actions[0].SelectNodes('./*[local-name()="Arguments"]'))
 if($cmd.Count -ne 1 -or $args.Count -ne 1){
    throw 'V058_ACTION_ARGUMENTS_MISSING'
 }
 $description=@($doc.SelectNodes('/*[local-name()="Task"]/*[local-name()="RegistrationInfo"]/*[local-name()="Description"]'))
 $triggers=@($doc.SelectNodes('/*[local-name()="Task"]/*[local-name()="Triggers"]/*'))
 if($description.Count -ne 1 -or [string]$description[0].InnerText -cne 'V058_ISOLATED_UNRUNNABLE_SCRATCH_ONLY' -or
    $triggers.Count -ne 1 -or [string]$triggers[0].LocalName -cne 'TimeTrigger'){
    throw 'V058_SCRATCH_OWNER_OR_FUTURE_TRIGGER_NOT_EXACT'
 }
 $starts=@($triggers[0].SelectNodes('./*[local-name()="StartBoundary"]'))
 if($starts.Count -ne 1 -or [string]$starts[0].InnerText -cne '2099-01-01T00:00:00'){
    throw 'V058_SCRATCH_TRIGGER_MUST_BE_FAR_FUTURE'
 }
 $expectedCmd=Join-Path $env:WINDIR 'System32\cmd.exe'
 if(-not ([string]$cmd[0].InnerText).Equals($expectedCmd,[StringComparison]::OrdinalIgnoreCase) -or
    [string]$args[0].InnerText -cne '/c exit 0'){
    throw 'V058_UNRECOGNIZED_EXECUTABLE_OR_ACTION'
 }
 $was=[string]$enabled[0].InnerText
 $enabled[0].InnerText='V058_ENABLED_ONLY_FIELD'
 return [pscustomobject]@{
   normalized_sha256=(Get-V058Utf8Sha256 -Value $doc.OuterXml)
   enabled=($was -ceq 'true')
   user_task=$false
   action='INERT_FAR_FUTURE_CMD_EXIT_ZERO'
   signed_production_authority=$false
 }
}
function Resolve-V058QuiescenceDecision {
 param([Parameter(Mandatory=$true)]$Observation)
 foreach($field in @('task_identity_exact','task_disabled','instances_zero',
    'process_observation_complete','manual_launch_fenced','source_lease_held',
    'original_task_journal_durable')){
   $prop=$Observation.PSObject.Properties[$field]
   if($null-eq$prop -or $prop.Value -isnot [bool]){
      throw 'V058_UNTYPED_OR_INCOMPLETE_OBSERVATION'
   }
 }
 $taskReady=([bool]$Observation.task_identity_exact -and
   [bool]$Observation.task_disabled -and
   [bool]$Observation.instances_zero -and
   [bool]$Observation.original_task_journal_durable)
 $strong=($taskReady -and
    [bool]$Observation.process_observation_complete -and
    [bool]$Observation.manual_launch_fenced -and
    [bool]$Observation.source_lease_held)
 $state=if(-not[bool]$Observation.task_identity_exact){'UNKNOWN_TASK_AUTHORITY'}
        elseif(-not[bool]$Observation.original_task_journal_durable){'NO_DURABLE_ROLLBACK'}
        elseif(-not[bool]$Observation.task_disabled){'NEW_LAUNCHES_NOT_BLOCKED'}
        elseif(-not[bool]$Observation.instances_zero){'LEGACY_EXECUTION_NOT_DRAINED'}
        elseif(-not[bool]$Observation.process_observation_complete){'PROCESS_VISIBILITY_INCOMPLETE'}
        elseif(-not[bool]$Observation.manual_launch_fenced){'MANUAL_LEGACY_LAUNCH_UNFENCED'}
        elseif(-not[bool]$Observation.source_lease_held){'NO_NEW_ENGINE_SOURCE_LEASE'}
        else{'CONDITIONAL_READINESS_ONLY'}
 return [pscustomobject]@{
   state=$state
   task_observation_ready=$taskReady
   process_and_launch_observation_ready=$strong
   task_change_scope='V058_NEW_SCRATCH_ONLY'
   # A finite sequence of observations is not a real OS access-control
   # fence against unmodified same-user scripts, and cannot grant cutover.
   real_windows_task_disabled=$false
   live_cutover_go=$false
   production_mutation_authorized=$false
   manual_legacy_launch_excluded=$false
   older_unpatched_processes_excluded=$false
 }
}
function Write-V058ScratchJournal {
 param([Parameter(Mandatory=$true)][string]$Path,
       [Parameter(Mandatory=$true)][string]$Name,
       [Parameter(Mandatory=$true)][string]$XmlSha)
 $json=([ordered]@{schema=1;scratch_task=$Name
   owner='V058_ISOLATED_UNRUNNABLE_SCRATCH_ONLY'
   action_xml_sha256=$XmlSha;originally_enabled=$true
   production_mutation_authorized=$false
   created_under_temporary_runner=$true}|ConvertTo-Json -Compress)
 $bytes=[Text.Encoding]::UTF8.GetBytes($json)
 $handle=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,
   [IO.FileAccess]::Write,[IO.FileShare]::None)
 try{
   $handle.Write($bytes,0,$bytes.Length)
   $handle.Flush($true)
 }finally{$handle.Dispose()}
 if(-not[IO.File]::Exists($Path) -or
    (Get-V058Utf8Sha256 -Value ([IO.File]::ReadAllText($Path))) -cne
      (Get-V058Utf8Sha256 -Value $json)){
   throw 'V058_DURABLE_SCRATCH_JOURNAL_NOT_VERIFIED'
 }
}
function Assert-V058ScratchTaskExact {
 param([Parameter(Mandatory=$true)]$Task,
       [Parameter(Mandatory=$true)][string]$ExpectedName)
 if($ExpectedName -cnotmatch '^V058-Scratch-[0-9a-f]{32}$' -or
    [string]$Task.Path -cne ('\'+$ExpectedName)){
   throw 'V058_SCRATCH_TASK_PATH_UNOWNED'
 }
 return Get-V058ScratchXmlIdentity -TaskXml ([string]$Task.Xml)
}
function Invoke-V058OwnedScratchQuiescence {
 param([switch]$InjectExceptionAfterDisable)
 Assert-V058HostedScope
 $name='V058-Scratch-'+[guid]::NewGuid().ToString('N')
 $base=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
 $journal=Join-Path $base ($name+'.json')
 $service=New-Object -ComObject Schedule.Service
 $service.Connect()
 $folder=$service.GetFolder('\')
 $created=$false;$disabled=$false;$preserved=$false;$cleaned=$false
 $originalHash=$null;$observedDisabled=$false
 try{
   $def=$service.NewTask(0)
   $def.RegistrationInfo.Description='V058_ISOLATED_UNRUNNABLE_SCRATCH_ONLY'
   $def.Settings.Enabled=$true
   $def.Settings.Hidden=$true
   $def.Settings.StartWhenAvailable=$false
   $def.Settings.AllowDemandStart=$false
   $def.Settings.ExecutionTimeLimit='PT30S'
   $def.Principal.UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name
   $def.Principal.LogonType=3 # TASK_LOGON_INTERACTIVE_TOKEN
   $act=$def.Actions.Create(0) # TASK_ACTION_EXEC
   $act.Path=(Join-Path $env:WINDIR 'System32\cmd.exe')
   $act.Arguments='/c exit 0'
   $trigger=$def.Triggers.Create(1) # TASK_TRIGGER_TIME; not RegistrationTrigger
   $trigger.StartBoundary='2099-01-01T00:00:00'
   [void]$folder.RegisterTaskDefinition($name,$def,2,$null,$null,3,$null)
   $created=$true
   $task=$folder.GetTask($name)
   $before=Assert-V058ScratchTaskExact -Task $task -ExpectedName $name
   if(-not[bool]$before.enabled){throw 'V058_SCRATCH_NOT_ORIGINALLY_ENABLED'}
   $originalHash=[string]$before.normalized_sha256
   $running=@($task.GetInstances(0))
   if($running.Count -ne 0){throw 'V058_NEW_SCRATCH_TASK_UNEXPECTED_RUNNING_INSTANCE'}
   Write-V058ScratchJournal -Path $journal -Name $name -XmlSha $originalHash
   # No Stop, Run, DeleteTask or RegisterTaskDefinition for an EXISTING task.
   # This field-only change is allowed solely for our fresh scratch task.
   $task.Enabled=$false;$disabled=$true
   $now=$folder.GetTask($name)
   $after=Assert-V058ScratchTaskExact -Task $now -ExpectedName $name
   if([bool]$after.enabled -or
      [string]$after.normalized_sha256 -cne $originalHash){
     throw 'V058_SCRATCH_DEFINITION_CHANGED_BEYOND_ENABLED'
   }
   $observedDisabled=$true
   $runningAgain=@($now.GetInstances(0))
   $decision=Resolve-V058QuiescenceDecision -Observation ([pscustomobject]@{
      task_identity_exact=$true;task_disabled=$true
      instances_zero=($runningAgain.Count -eq 0)
      process_observation_complete=$false;manual_launch_fenced=$false
      source_lease_held=$false;original_task_journal_durable=$true
   })
   if($decision.live_cutover_go -or
      [string]$decision.state -cne 'PROCESS_VISIBILITY_INCOMPLETE'){
     throw 'V058_SCRATCH_GRANTED_FALSE_REAL_PRODUCTION_ADMISSION'
   }
   if($InjectExceptionAfterDisable){
      throw 'V058_INJECTED_FAILURE_AFTER_JOURNALED_DISABLE'
   }
   # Verify expected identity BEFORE touching Enabled during rollback.
   $restore=$folder.GetTask($name)
   $identity=Assert-V058ScratchTaskExact -Task $restore -ExpectedName $name
   if([bool]$identity.enabled -or [string]$identity.normalized_sha256 -cne $originalHash){
      throw 'V058_SCRATCH_CONCURRENT_EDITS_BLOCK_ROLLBACK'
   }
   $restore.Enabled=$true;$disabled=$false
   $check=Assert-V058ScratchTaskExact -Task ($folder.GetTask($name)) -ExpectedName $name
   if(-not[bool]$check.enabled -or [string]$check.normalized_sha256 -cne $originalHash){
      throw 'V058_SCRATCH_ORIGINAL_ENABLED_STATE_NOT_RESTORED'
   }
   $preserved=$true
 }finally{
   if($created){
      # Never touch tasks outside the unique task we just registered.
      # The runner is disposable; unsafe identity drift leaves task
      # untouched rather than clobbering somebody else's edits.
      try{
         $cleanupTask=$folder.GetTask($name)
         $last=Assert-V058ScratchTaskExact -Task $cleanupTask -ExpectedName $name
         if($last.normalized_sha256 -cne $originalHash){
            throw 'V058_SCRATCH_CLEANUP_CAS_MISMATCH'
         }
         if(-not[bool]$last.enabled){
            $cleanupTask.Enabled=$true
            $last=Assert-V058ScratchTaskExact -Task ($folder.GetTask($name)) -ExpectedName $name
            if(-not[bool]$last.enabled){throw 'V058_SCRATCH_CLEANUP_REENABLE_FAILED'}
         }
         # Delete ONLY the CI-created, freshly owned scratch task, never a
         # previously existing task nor any real Addon Manager task.
         $folder.DeleteTask($name,0)
         $cleaned=$true
      }catch{
         throw 'V058_SCRATCH_CLEANUP_NEEDS_ISOLATED_RUNNER_TEARDOWN'
      }
   }
 }
 return [pscustomobject]@{
   originally_enabled=$true
   disabled_observed=$observedDisabled
   restored=$preserved
   scratch_deleted=$cleaned
   production_mutation_authorized=$false
   prior_user_tasks_modified=$false
   any_real_spotify_mutation=$false
 }
}
