# V057 READ-ONLY Windows legacy Addon Manager scheduler/process observation.
# Enumerates Task Scheduler folders INCLUDING hidden tasks, and relevant
# running shell processes. NEVER stops, disables, edits or registers tasks.
# Unpatched legacy scripts are NOT protected by V047 cooperative lock.
# This observer NEVER grants any production cutover authority, including when
# all accessible task and process counts are zero: manual launches and races.
Set-StrictMode -Version 2.0

function Resolve-CustomAppV057CutoverObservation {
 param([Parameter(Mandatory=$true)]$Snapshot)
 $needed=@('task_scan_complete','process_scan_complete','task_count',
   'suspect_task_count','enabled_suspect_task_count','running_suspect_task_count',
   'opaque_task_action_count','suspect_process_count','opaque_shell_process_count',
   'read_errors','hidden_tasks_requested')
 foreach($name in $needed){
   if($null-eq $Snapshot.PSObject.Properties[$name]){
      throw 'V057_SNAPSHOT_MISSING_REQUIRED_FIELD'
   }
 }
 foreach($name in @('task_count','suspect_task_count','enabled_suspect_task_count',
     'running_suspect_task_count','opaque_task_action_count','suspect_process_count',
     'opaque_shell_process_count','read_errors')){
   if($Snapshot.$name -isnot [int] -or $Snapshot.$name -lt 0 -or
      $Snapshot.$name -gt 50000){throw 'V057_SNAPSHOT_INVALID_NONNEGATIVE_COUNT'}
 }
 $complete=([bool]$Snapshot.task_scan_complete -and
   [bool]$Snapshot.process_scan_complete -and
   [bool]$Snapshot.hidden_tasks_requested -and [int]$Snapshot.read_errors -eq 0)
 $old=([int]$Snapshot.enabled_suspect_task_count -gt 0 -or
       [int]$Snapshot.running_suspect_task_count -gt 0 -or
       [int]$Snapshot.suspect_process_count -gt 0)
 $opaque=([int]$Snapshot.opaque_task_action_count -gt 0 -or
          [int]$Snapshot.opaque_shell_process_count -gt 0)
 $state=if(-not $complete){'INCOMPLETE_FAIL_CLOSED'}
        elseif($old){'LEGACY_WRITERS_POSSIBLE'}
        elseif($opaque){'OPAQUE_EXECUTION_PATHS'}
        else{'READ_ONLY_CLEAR_BUT_RACY'}
 return [pscustomobject]@{
    schema=1;state=$state;scan_complete=$complete
    legacy_writer_or_task_detected=$old;opaque_execution=$opaque
    task_count=[int]$Snapshot.task_count
    suspect_task_count=[int]$Snapshot.suspect_task_count
    suspect_process_count=[int]$Snapshot.suspect_process_count
    unknown_or_inaccessible_count=([int]$Snapshot.read_errors+
       [int]$Snapshot.opaque_task_action_count+
       [int]$Snapshot.opaque_shell_process_count)
    # This result is evidence for a future human-authorized cutover plan,
    # not proof of exclusive process ownership or an enabled scheduler barrier.
    manual_legacy_launch_excluded=$false
    earlier_unpatched_processes_excluded=$false
    scheduler_registration_modified=$false
    scheduler_running_instances_terminated=$false
    production_mutation_authorized=$false
    new_engine_enrollment_authorized=$false
    live_cutover_go=$false
 }
}

function Get-CustomAppV057ReadOnlyWindowsInventory {
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
   throw 'V057_WINDOWS_ONLY'
 }
 $counts=[ordered]@{
   task_scan_complete=$false;process_scan_complete=$false
   hidden_tasks_requested=$false
   task_count=[int]0;suspect_task_count=[int]0
   enabled_suspect_task_count=[int]0
   running_suspect_task_count=[int]0
   opaque_task_action_count=[int]0
   suspect_process_count=[int]0
   opaque_shell_process_count=[int]0
   read_errors=[int]0
 }
 # Broad, conservative family matcher: these are *potential* old writers.
 # Never disclose names, paths, arguments, usernames, PIDs, commands or XML.
 $owner='(?i)spotify.?control|addon.?manager|autoapps|spicetify.*(update|apply)'
 $shell='(?i)(powershell|pwsh|cmd|wscript|cscript|python|spicetify)(\.exe)?$'
 try{
   $svc=New-Object -ComObject Schedule.Service
   $svc.Connect()
   $queue=New-Object 'System.Collections.Generic.Queue[object]'
   $queue.Enqueue($svc.GetFolder('\'))
   $folders=0
   while($queue.Count -gt 0){
     $folders++
     if($folders -gt 256){throw 'V057_TASK_FOLDER_SCAN_CAP'}
     $folder=$queue.Dequeue()
     $tasks=@($folder.GetTasks(1)) # 1 = TASK_ENUM_HIDDEN
     $counts.hidden_tasks_requested=$true
     foreach($task in $tasks){
       $counts.task_count++
       if($counts.task_count -gt 5000){throw 'V057_TASK_COUNT_SCAN_CAP'}
       try{
         $matched=([string]$task.Path -match $owner)
         $opaque=$false
         $definition=$task.Definition
         $actions=@($definition.Actions)
         if($actions.Count -eq 0){$opaque=$true}
         foreach($action in $actions){
           if([int]$action.Type -ne 0){$opaque=$true;continue}
           $exec=([string]$action.Path)+' '+([string]$action.Arguments)
           if($exec -match $owner){$matched=$true}
           # Encoded/external script launch cannot be ascribed safely to
           # an exact script solely by seeing a benign command name.
           if($exec -match '(?i)-encodedcommand|-(enc|ec)\s' -and
              $exec -match '(?i)powershell|pwsh'){$opaque=$true}
         }
         if($opaque){$counts.opaque_task_action_count++}
         if($matched){
           $counts.suspect_task_count++
           if([bool]$task.Enabled){$counts.enabled_suspect_task_count++}
           $running=@($task.GetInstances(0))
           if($running.Count -gt 0 -or [int]$task.State -eq 4){
             $counts.running_suspect_task_count++
           }
         }
       }catch{
         # No silent omission of unreadable task action / running state.
         $counts.read_errors++
       }
     }
     $sub=@($folder.GetFolders(0))
     foreach($f in $sub){$queue.Enqueue($f)}
   }
   $counts.task_scan_complete=$true
 }catch{
   $counts.read_errors++
   $counts.task_scan_complete=$false
 }
 try{
   $q=@('powershell.exe','pwsh.exe','cmd.exe','wscript.exe','cscript.exe',
        'python.exe','pythonw.exe','spicetify.exe')
   $where=@($q|ForEach-Object{"Name='$($_)'"}) -join ' OR '
   $processes=@(Get-CimInstance -ClassName Win32_Process -Filter $where -ErrorAction Stop)
   if($processes.Count -gt 5000){throw 'V057_PROCESS_ENUMERATION_CAP'}
   foreach($p in $processes){
     $cmd=[string]$p.CommandLine
     if([string]::IsNullOrWhiteSpace($cmd)){
       $counts.opaque_shell_process_count++
     }elseif($cmd -match $owner){
       $counts.suspect_process_count++
     }elseif($cmd -match '(?i)-encodedcommand|-(enc|ec)\s'){
       $counts.opaque_shell_process_count++
     }
   }
   $counts.process_scan_complete=$true
 }catch{
   $counts.read_errors++
   $counts.process_scan_complete=$false
 }
 return Resolve-CustomAppV057CutoverObservation -Snapshot ([pscustomobject]$counts)
}
