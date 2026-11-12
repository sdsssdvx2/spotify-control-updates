# R102 hosted Windows only: actual Task Scheduler COM owner-logon
# registration/readback and cleanup. Never execute agent or modify owner PC.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5){
  throw 'R102_REAL_COM_FIXTURE_GITHUB_WINDOWS_PS51_ONLY'
}
$source='validation/spotify-exit-immediate-maintenance-HOLD/owner-approved-complete-lifecycle-R102-HOLD.ps1'
$t=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$t,[ref]$errors)
if(@($errors).Count -ne 0){throw 'R102_OWNER_SOURCE_SYNTAX_INVALID'}
function SourceFunction([string]$name){
  $items=@($ast.FindAll({
    param($n)
    $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name
  },$true))
  if($items.Count -ne 1){throw 'R102_HELPER_SOURCE_NOT_UNIQUE'}
  return $items[0].Extent.Text
}
$probe=SourceFunction 'R102TaskProbe'
$quote=[char]39
$needle='$folders.Push($service.GetFolder('+$quote+'\'+$quote+'))'
$replacement='$folders.Push($service.GetFolder($global:R102HostedFolder))'
if($probe.Split(@($needle),[StringSplitOptions]::None).Count -ne 2){
  throw 'R102_EXACT_COM_ROOT_ANCHOR_CHANGED'
}
$probe=$probe.Replace($needle,$replacement)
$names=@('Deny','RequireOnce','R102OneValue','R102ExistingTaskAdmission',
         'R102AgentActionClass','R102PrincipalClass')
$functions=(@($names|ForEach-Object{SourceFunction $_}) -join [Environment]::NewLine)
. ([ScriptBlock]::Create($functions+[Environment]::NewLine+$probe))
$svc=New-Object -ComObject Schedule.Service
$svc.Connect()
$root=$svc.GetFolder('\')
$folderName='R102HoldFixture-'+[guid]::NewGuid().ToString('N')
$global:R102HostedFolder='\'+$folderName
$user=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$agent=Join-Path $env:RUNNER_TEMP 'R102SyntheticNeverExecuted.vbs'
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
$folderMade=$false
$taskMade=$false
$clean=$false
try {
  if(Test-Path -LiteralPath $agent){throw 'R102_SYNTHETIC_AGENT_MUST_NOT_EXIST'}
  $folder=$root.CreateFolder($folderName,$null)
  $folderMade=$true
  $def=$svc.NewTask(0)
  $def.RegistrationInfo.Description='R102 isolated GH runner test, never execute'
  $def.Principal.UserId=$user
  $def.Principal.LogonType=3
  $def.Principal.RunLevel=0
  $def.Settings.Enabled=$true
  $def.Settings.MultipleInstances=2
  $trigger=$def.Triggers.Create(9)
  $trigger.UserId=$user
  $trigger.Enabled=$true
  $action=$def.Actions.Create(0)
  $action.Path=$wscript
  $action.Arguments='//B //NoLogo "'+$agent+'"'
  $null=$folder.RegisterTaskDefinition('OwnerResident',$def,6,$user,$null,3,$null)
  $taskMade=$true
  $rows=@(R102TaskProbe $agent)
  foreach($line in @(
    'R102_TASK_COM_ENUM=ACCESSIBLE_SCOPE_ENUMERATED_NOT_GLOBAL_PROOF',
    'R102_TASK_AGENT_TOKEN_MATCHES=1',
    'R102_TASK_DIRECT_OWNER_LOGON_ENABLED=1',
    'R102_TASK_UNKNOWN_MATCH_DETAILS=0',
    'R102_TASK_OTHER_OR_UNKNOWN_PRINCIPAL=0',
    'R102_SINGLE_MATCH_PRINCIPAL=CURRENT_OWNER_RESOLVED',
    'R102_SINGLE_MATCH_ACTION=ONE_DIRECT_WSCRIPT_ACTION',
    'R102_SINGLE_MATCH_ENABLED=YES',
    'R102_SINGLE_MATCH_TRIGGER=LOGON_ENABLED',
    'R102_SINGLE_MATCH_LOGON_SCOPE=CURRENT_USER',
    'R102_SINGLE_MATCH_INSTANCE_POLICY=IGNORE_NEW',
    'R102_SINGLE_MATCH_LOGON_TYPE=INTERACTIVE_TOKEN')){
      if($rows -cnotcontains $line){throw ('R102_COM_OWNER_CONTRACT_'+$line.Split('=')[0])}
  }
  $pin=R102ExistingTaskAdmission $rows
  $pinAfter=R102ExistingTaskAdmission @(R102TaskProbe $agent)
  if($pin -cne $pinAfter){throw 'R102_COM_TASK_PIN_NOT_STABLE'}
  Write-Output 'R102_REAL_COM_OWNER_TASK_ADMISSION=PASS'
  Write-Output 'R102_REAL_COM_TASK_REGISTRATION_PIN=STABLE'
  Write-Output 'R102_REAL_LOGON_AND_AGENT_EXECUTION=NOT_RUN'
}finally {
  if($taskMade){try{$folder.DeleteTask('OwnerResident',0)}catch{}}
  if($folderMade){try{$root.DeleteFolder($folderName,0)}catch{}}
  try{
    $null=$root.GetFolder($global:R102HostedFolder)
  }catch [Runtime.InteropServices.COMException]{$clean=$true}
  Remove-Variable R102HostedFolder -Scope Global -ErrorAction SilentlyContinue
  if(-not $clean){throw 'R102_HOSTED_TASK_CLEANUP_INCOMPLETE'}
}
Write-Output 'R102_HOSTED_SCRATCH_TASK_CLEANUP=PASS'
