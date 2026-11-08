# V061 hosted-only real r17 FUNCTION execution, not whole-program execution.
# Extract precisely 3 V060 wrapped mutators and 4 known lease helpers from
# a freshly built and byte-proven stable r17 candidate via PowerShell AST.
# All dependencies prior to a sentinel Backup are replaced with inert mocks.
# No real addon, Spotify, user profile, scheduler, installed agent, API,
# network call, original ledger or source file is read or written.
param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V061_ONLY_HOSTED_WINDOWS'
}
function Assert-V061([bool]$condition,[string]$message){
 if(-not$condition){throw ('V061_ACCEPTANCE_'+$message)}
}
function Expect-V061Failure([scriptblock]$run,[string]$expected){
 $got=$false
 try{[void](& $run)}
 catch{
   if([string]$_.Exception.Message -ceq $expected){$got=$true}
   else{throw}
 }
 Assert-V061 $got ('EXPECTED_DENIAL_'+$expected)
}
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$source=[IO.Path]::GetFullPath($CandidatePath)
Assert-V061 ($source.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -and
 [IO.Path]::GetFileName($source) -ceq 'addon-manager-reentrant-V060-NONDEPLOY.ps1' -and
 [IO.File]::Exists($source)) 'CANDIDATE_OUTSIDE_ISOLATED_RUNNER_OR_NOT_BUILT'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
Assert-V061 ($parseErrors.Count -eq 0) 'CANDIDATE_PARSE_INVALID'
$definitions=@($ast.FindAll({
  param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
},$true))
$wanted=@(
 'Enter-CustomAppEngineTurnstileV047',
 'Enter-CustomAppReentrantTurnstileV060',
 'Exit-CustomAppReentrantTurnstileV060',
 'Assert-CustomAppReentrantLeaseInvariantV060',
 'Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction'
)
$fragments=New-Object 'System.Collections.Generic.List[string]'
foreach($name in $wanted){
 $nodes=@($definitions|Where-Object{$_.Name -ceq $name})
 Assert-V061 ($nodes.Count -eq 1) ('CANDIDATE_FUNCTION_NOT_UNIQUE_'+$name)
 $fragment=[string]$nodes[0].Extent.Text
 $fragments.Add($fragment)
}
# Ensure actual mutators contain the V060 entry before even the first
# prior-code condition, and leave the lock through a finally.
foreach($name in @('Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction')){
 $part=[string](@($definitions|Where-Object{$_.Name -ceq $name})[0].Body.Extent.Text)
 $enter=$part.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 $guard=$part.IndexOf('try {',[StringComparison]::Ordinal)
 $exit=$part.LastIndexOf('Exit-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 Assert-V061 ($enter -ge 0 -and $guard -gt $enter -and $exit -gt $guard) ('MUTATOR_NOT_WRAPPED_'+$name)
}
# We deliberately DO NOT dot-source the candidate program. This text
# contains ONLY the exact seven AST function extents; its top-level actions,
# selftests, logging setup and all other executable source are excluded.
$sourceFunctions=$fragments -join [Environment]::NewLine
. ([scriptblock]::Create($sourceFunctions))
$script:V060AddonLeaseState=$null
$private=Join-Path $root ('v061-r17-functions-'+[guid]::NewGuid().ToString('N'))
$script:SafeLocal=Join-Path $private 'Local'
$expectedDirectory=Join-Path $script:SafeLocal 'SpotifyControl'
[void][IO.Directory]::CreateDirectory($expectedDirectory)
$script:TransactionPath=Join-Path $private 'NONEXISTENT-transaction.json'
$script:Phase='initial'
$script:PathsChecked=0
$script:ProcessProbed=0
$script:BackupCalled=0
$script:NestedObserved=0
$script:MockedLogCount=0
$script:NoOutsideOperations=0
# The actual V047 FILE OPEN function is retained as a scriptblock, and
# this CI-only selector forces EVERY call into the ephemeral hosted path.
# In particular there is NO fallback to the runner's real LocalAppData.
$script:ActualV047=(Get-Command Enter-CustomAppEngineTurnstileV047).ScriptBlock
function Enter-CustomAppEngineTurnstileV047 {
 param([string]$HostedCiRoot=$null)
 if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot) -and
    -not[IO.Path]::GetFullPath($HostedCiRoot).Equals(
      [IO.Path]::GetFullPath($script:SafeLocal),
      [StringComparison]::OrdinalIgnoreCase)){
    throw 'V061_REJECTED_ANOTHER_FILE_LEASE_ROOT'
 }
 & $script:ActualV047 -HostedCiRoot $script:SafeLocal
}
# This is the original 323385-byte legacy r17 function's OWN pre-I/O
# dependency surface. No effects are permitted beyond mock counters.
function Get-Process {
 [CmdletBinding()]
 param([Parameter(Position=0)][string[]]$Name)
 if(@($Name).Count -ne 1 -or [string]$Name[0] -cne 'Spotify'){
   throw 'V061_UNEXPECTED_PROCESS_QUERY'
 }
 $script:ProcessProbed++
 if($script:Phase -ceq 'blocked'){
   throw 'V061_UNPROTECTED_PROCESS_QUERY_BEFORE_OS_LOCK'
 }
 # Simulate a fully stopped Spotify. No OS process is enumerated.
}
function Test-PathSafe {
 param($Path,$Kind)
 if([string]$Path -cne $script:TransactionPath -or
    [string]$Kind -cne 'Leaf'){
   throw 'V061_UNEXPECTED_DISK_PATH_TEST'
 }
 $script:PathsChecked++
 if($script:Phase -ceq 'blocked'){
   throw 'V061_UNPROTECTED_DISK_PATH_TEST_BEFORE_OS_LOCK'
 }
 # Exactly first lookup reports unresolved ledger, inducing nested call
 # to *actual* Rollback-LastTransaction; every later lookup is absent.
 if($script:Phase -ceq 'nested' -and $script:PathsChecked -eq 1){
   return $true
 }
 return $false
}
function Write-AddonLog {
 param([string]$Message,[string]$Level='INFO')
 $script:MockedLogCount++
 $h=Assert-CustomAppReentrantLeaseInvariantV060
 if($script:Phase -ceq 'blocked'){
   throw 'V061_LOGGED_BEFORE_HELD_LOCK_DENIAL'
 }
 if(-not[bool]$h.active){throw 'V061_LOG_CALLED_WITHOUT_OS_LEASE'}
 if($script:Phase -ceq 'nested' -and
    $Message.Contains('No addon transaction to roll back.')){
   if([int]$h.depth -ne 2){
     throw 'V061_REAL_NESTED_ROLLBACK_DID_NOT_REENTER_ONE_LEASE'
   }
   # Independent non-reentrant API is still exclusive while nested.
   $denied=$false
   try{
      $unexpected=& $script:ActualV047 -HostedCiRoot $script:SafeLocal
      if($null-ne$unexpected){$unexpected.Dispose()}
   }catch{
     if([string]$_.Exception.Message -ceq
          'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'){$denied=$true}
     else{throw}
   }
   if(-not$denied){throw 'V061_NESTED_ROLLBACK_NOT_EXCLUSIVE'}
   $script:NestedObserved++
 }
}
function Backup-SpotifyWebData {
 $script:BackupCalled++
 $h=Assert-CustomAppReentrantLeaseInvariantV060
 if($script:Phase -cne 'nested' -or -not[bool]$h.active -or
    [int]$h.depth -ne 1){
   throw 'V061_BACKUP_MOCK_OUTSIDE_EXPECTED_REENTRANT_SCOPE'
 }
 # No native filesystem or Spotify backup is ever attempted.
 throw 'V061_STOP_BEFORE_ALL_ORIGINAL_BACKUP_IO'
}
# Test #1: an already-held OS lease must deny all three actual ORIGINAL
# mutators BEFORE any real source Get-Process / Test-PathSafe / WriteLog.
$held=& $script:ActualV047 -HostedCiRoot $script:SafeLocal
$script:Phase='blocked'
try{
 foreach($name in @('Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction')){
   Expect-V061Failure {& $name} 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'
 }
 Assert-V061 ($script:PathsChecked -eq 0 -and $script:ProcessProbed -eq 0 -and
  $script:BackupCalled -eq 0 -and $script:MockedLogCount -eq 0) 'OLD_MUTATORS_EXECUTED_SIDE_EFFECT_PREREQUISITE_WHILE_LOCKED'
}finally{$held.Dispose()}
$h=Assert-CustomAppReentrantLeaseInvariantV060
Assert-V061 (-not[bool]$h.active) 'DENIED_MUTATORS_LEAKED_LEASE'
Write-Host 'V061_ACTUAL_WRAPPED_STABLE_R17_THREE_MUTATORS_DENY_BEFORE_SIDE_EFFECT_WHEN_OS_LOCK_HELD_PASS'
# Test #2: real r17 RollbackLast/CommitLast with a known missing ledger
# can safely no-op and release even without any original disk operations.
$script:Phase='noop'
Rollback-LastTransaction
Commit-LastTransaction
Assert-V061 ($script:PathsChecked -eq 2 -and
 $script:BackupCalled -eq 0 -and $script:MockedLogCount -eq 2) 'REAL_DIRECT_NOOP_INCOMPLETE'
$h=Assert-CustomAppReentrantLeaseInvariantV060
Assert-V061 (-not[bool]$h.active) 'REAL_DIRECT_NOOP_LEFT_LEASE'
Write-Host 'V061_ACTUAL_R17_ROLLBACK_AND_COMMIT_EARLY_NOOP_RELEASE_ONE_LEASE_PASS'
# Test #3: actual Update-AutoApps invokes actual Rollback-LastTransaction
# within SAME thread/runspace and holds ONE OS FileShare.None for both.
$script:Phase='nested'
$script:PathsChecked=0
Expect-V061Failure {Update-AutoApps} 'V061_STOP_BEFORE_ALL_ORIGINAL_BACKUP_IO'
Assert-V061 ($script:NestedObserved -eq 1 -and $script:PathsChecked -eq 3 -and
 $script:ProcessProbed -eq 1 -and $script:BackupCalled -eq 1) 'REAL_NESTED_R17_FUNCTION_CONTROL_FLOW_CHANGED'
$h=Assert-CustomAppReentrantLeaseInvariantV060
Assert-V061 (-not[bool]$h.active) 'ACTUAL_R17_NESTED_ROLLBACK_LEAKED_OS_LEASE'
# The cross-process OS handle was freed after the outermost finally.
$released=& $script:ActualV047 -HostedCiRoot $script:SafeLocal
Assert-V061 ($released -is [IO.FileStream]) 'ACTUAL_R17_NESTED_FINALLY_DID_NOT_RELEASE_FILE'
$released.Dispose()
Assert-V061 (@(Get-ChildItem -LiteralPath $expectedDirectory -Force).Count -eq 1 -and
 [IO.File]::Exists((Join-Path $expectedDirectory '.engine-cutover-turnstile.lock')) -and
 (Get-Item -LiteralPath (Join-Path $expectedDirectory '.engine-cutover-turnstile.lock')).Length -eq 0) 'NONEMPTY_OR_UNEXPECTED_PRIVATE_FIXTURE_WRITES'
Write-Host 'V061_REAL_R17_UPDATE_NESTED_REAL_ROLLBACK_KEEP_EXCLUSIVE_LOCK_AND_RELEASE_AFTER_FAILURE_PASS'
Write-Host 'V061_NO_STABLE_WHOLE_PROGRAM_RUN_NO_REAL_BACKUP_NO_USER_PROFILE_NO_LIVE_CUTOVER_PASS'
