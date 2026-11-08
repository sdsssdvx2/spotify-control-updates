# V060 hosted-only Windows regression: the old V047 wrapper can call
# Rollback-LastTransaction nested within Update-AutoApps, so a second
# FileShare.None open would be refused. New nested LIFO token retains ONE
# V047 OS lock; other processes remain excluded until final Exit.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V060_REENTRANT_TEST_HOSTED_WINDOWS_ONLY'
}
. (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
. (Join-Path $PSScriptRoot 'reentrant-addon-turnstile-v060.ps1')
function Assert-V060([bool]$Good,[string]$Reason){
 if(-not$Good){throw ('V060_REENTRANT_TEST_'+$Reason)}
}
function MustDeny-V060([scriptblock]$Body,[string]$Code){
 $denied=$false
 try{[void](& $Body)}catch{
   if([string]$_.Exception.Message -ceq $Code){$denied=$true}else{throw}
 }
 Assert-V060 $denied ('DENIAL_NOT_ENFORCED_'+$Code)
}
# Pin both the stable r17 and the preexisting V047 wrapper structure.
$parent=(Resolve-Path (Join-Path $PSScriptRoot '..\v0.6.28\out\bin\addon-manager.ps1')).Path
Assert-V060 ((Get-Item -LiteralPath $parent).Length -eq 323385 -and
 (Get-FileHash $parent -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285') 'OLD_PRODUCTION_SOURCE_PIN'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($parent,[ref]$tokens,[ref]$errors)
Assert-V060 ($errors.Count -eq 0) 'PINNED_OLD_SOURCE_PARSE'
$fns=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$updates=@($fns|Where-Object{$_.Name -ceq 'Update-AutoApps'})
$rollbacks=@($fns|Where-Object{$_.Name -ceq 'Rollback-LastTransaction'})
$commits=@($fns|Where-Object{$_.Name -ceq 'Commit-LastTransaction'})
Assert-V060 ($updates.Count -eq 1 -and $rollbacks.Count -eq 1 -and
 $commits.Count -eq 1 -and
 ([string]$updates[0].Body.Extent.Text).Contains('Rollback-LastTransaction')) 'REAL_NESTED_ROLLBACK_NOT_PINNED'
$oldV047=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build-locked-addon-v047.ps1') -Raw
Assert-V060 ($oldV047.Contains("$"+"targets=@('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction')") -and
 $oldV047.Contains('Enter-CustomAppEngineTurnstileV047') -and
 $oldV047.Contains('$__engineLeaseV047.Dispose()')) 'PREEXISTING_V047_NESTED_LOCK_STRUCTURE_NOT_PINNED'
Write-Host 'V060_REAL_R17_UPDATE_CALLS_ROLLBACK_WHILE_V047_WRAPPED_BOTH_MUTATORS_PASS'
$fixture=Join-Path $env:RUNNER_TEMP ('v060-reentrant-'+[guid]::NewGuid().ToString('N'))
$local=Join-Path $fixture 'Local'
[void][IO.Directory]::CreateDirectory((Join-Path $local 'SpotifyControl'))
$probe=Join-Path $fixture 'v047-probe-child.ps1'
$module=Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1'
$code=@'
param([Parameter(Mandatory=$true)][string]$Module,
      [Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. $Module
try{
 $h=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $Root
 if($null-eq$h){exit 19}
 $h.Dispose()
 exit 0
}catch{
 if([string]$_.Exception.Message -ceq 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'){exit 17}
 exit 19
}
'@
[IO.File]::WriteAllText($probe,$code,[Text.UTF8Encoding]::new($false))
function ChildProbe-V060 {
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $p.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -Module "'+$module+'" -Root "'+$local+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true
 $p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 $proc=New-Object Diagnostics.Process
 try{
  $proc.StartInfo=$p
  if(-not$proc.Start()){throw 'V060_LOCK_PROBE_START_FAILED'}
  if(-not$proc.WaitForExit(20000)){
    $proc.Kill();[void]$proc.WaitForExit()
    throw 'V060_LOCK_PROBE_TIMEOUT'
  }
  $out=$proc.StandardOutput.ReadToEnd();$err=$proc.StandardError.ReadToEnd()
  if($out.Length+$err.Length -gt 8192){throw 'V060_LOCK_PROBE_OUTPUT_BOUNDS'}
  return [int]$proc.ExitCode
 }finally{$proc.Dispose()}
}
# Prove the *original* FileShare.None API cannot be called a second time
# even inside this process, then prove the nested layer succeeds.
$outer=Enter-CustomAppReentrantTurnstileV060 -HostedCiRoot $local
try{
 $h=Assert-CustomAppReentrantLeaseInvariantV060
 Assert-V060 ([bool]$h.active -and $h.depth -eq 1 -and
  -not[bool]$h.production_mutation_authorized) 'OUTER_LEASE_UNVERIFIED'
 MustDeny-V060 {Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $local} 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'
 $inner=Enter-CustomAppReentrantTurnstileV060 -HostedCiRoot $local
 try{
  $h=Assert-CustomAppReentrantLeaseInvariantV060
  Assert-V060 ([bool]$h.active -and $h.depth -eq 2) 'NESTED_REENTRANT_NOT_OWNED'
  Assert-V060 ((ChildProbe-V060) -eq 17) 'SECOND_PROCESS_BYPASSED_NESTED_LEASE'
  MustDeny-V060 {Exit-CustomAppReentrantTurnstileV060 -Token $outer} 'V060_REENTRANT_RELEASE_TOKEN_NOT_LIFO'
  $h=Assert-CustomAppReentrantLeaseInvariantV060
  Assert-V060 ($h.depth -eq 2) 'NON_LIFO_WRONGLY_DISCARDED_LOCK'
  Write-Host 'V060_SAME_RUNSPACE_NESTED_ROLLBACK_ONE_LOCK_OTHER_PROCESS_DENIED_PASS'
 }finally{
  Exit-CustomAppReentrantTurnstileV060 -Token $inner
 }
 Assert-V060 ((ChildProbe-V060) -eq 17) 'INNER_EXIT_RELEASED_OUTER_OS_LEASE'
 $h=Assert-CustomAppReentrantLeaseInvariantV060
 Assert-V060 ($h.depth -eq 1) 'NESTED_EXIT_DEPTH_NOT_ONE'
 Write-Host 'V060_NESTED_RETURN_KEEP_OUTER_FILESHARE_EXCLUSIVE_PASS'
}finally{
 Exit-CustomAppReentrantTurnstileV060 -Token $outer
}
Assert-V060 ((ChildProbe-V060) -eq 0) 'OUTER_EXIT_FAILED_TO_RELEASE_OS_HANDLE'
$h=Assert-CustomAppReentrantLeaseInvariantV060
Assert-V060 (-not[bool]$h.active -and $h.depth -eq 0) 'NO_ACTIVE_LEASE_SHOULD_REMAIN'
MustDeny-V060 {Exit-CustomAppReentrantTurnstileV060 -Token $outer} 'V060_REENTRANT_RELEASE_WITHOUT_OWNER'
Write-Host 'V060_OUTER_EXIT_RELEASES_OS_LOCK_AND_DOUBLE_EXIT_FAIL_CLOSED_PASS'
# Simulate Update handler failed after invoking a nested rollback. Both
# try/finally scopes must release their exact tokens, without deployment.
function Invoke-V060SyntheticRollback {
 $t=Enter-CustomAppReentrantTurnstileV060 -HostedCiRoot $local
 try{
  $h=Assert-CustomAppReentrantLeaseInvariantV060
  Assert-V060 ($h.depth -eq 2 -and (ChildProbe-V060) -eq 17) 'NESTED_ROLLBACK_LOST_LOCK'
  return 'rolled-back-synthetic'
 }finally{Exit-CustomAppReentrantTurnstileV060 -Token $t}
}
function Invoke-V060SyntheticUpdateFailure {
 $t=Enter-CustomAppReentrantTurnstileV060 -HostedCiRoot $local
 try{
  $rolled=Invoke-V060SyntheticRollback
  Assert-V060 ($rolled -ceq 'rolled-back-synthetic') 'NESTED_ROLLBACK_RESULT_CHANGED'
  throw 'V060_INJECTED_AFTER_NESTED_ROLLBACK'
 }finally{Exit-CustomAppReentrantTurnstileV060 -Token $t}
}
MustDeny-V060 {Invoke-V060SyntheticUpdateFailure} 'V060_INJECTED_AFTER_NESTED_ROLLBACK'
Assert-V060 ((ChildProbe-V060) -eq 0) 'SYNTHETIC_ROLLBACK_FAILURE_LEAKED_OS_HANDLE'
Write-Host 'V060_SYNTHETIC_UPDATE_ROLLBACK_NESTING_EXCEPTION_EXACT_RELEASE_PASS'
Write-Host 'V060_NO_OLD_ADDON_EXECUTION_NO_REAL_SPOTIFY_NO_PRODUCTION_AUTHORITY_PASS'
