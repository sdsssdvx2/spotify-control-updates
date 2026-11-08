# V060: real deployed stable v0.6.28 source function, isolated OS mutex
# interoperability across two Windows PowerShell processes, plus r17 direct
# mutation-entrypoint source-guard comparison. GitHub-hosted Windows ONLY.
# NEVER runs complete Spotify Control or Addon Manager, never touches tasks,
# user's Spotify, Startup, profiles, state, network or data.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V060_MUTEX_TEST_GITHUB_HOSTED_WINDOWS_ONLY'
}
function Assert-V060([bool]$Condition,[string]$Reason){
 if(-not$Condition){throw ('V060_MUTEX_TEST_'+$Reason)}
}
function Read-ExactV060([string]$Relative,[long]$ExpectedSize,[string]$ExpectedSha){
 $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
 $path=Join-Path $root $Relative
 if(-not[IO.File]::Exists($path) -or
    (Get-Item -LiteralPath $path).Length -ne $ExpectedSize -or
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSha){
    throw 'V060_STABLE_RECONSTRUCTED_FILE_SHA_OR_SIZE_NOT_PINNED'
 }
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile(
   $path,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw 'V060_REAL_STABLE_POWERSHELL_PARSE_FAILED'}
 $functions=@($ast.FindAll({
   param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
 },$true))
 return [pscustomobject]@{path=$path;functions=$functions}
}
function Get-V060ExactFunction($Source,[string]$Name){
 $f=@($Source.functions|Where-Object{$_.Name -ceq $Name})
 if($f.Count -ne 1){throw ('V060_UNIQUE_REAL_SOURCE_FUNCTION_REQUIRED_'+$Name)}
 return $f[0]
}
$main=Read-ExactV060 'validation\v0.6.28\out\bin\spotify-control.ps1' 284321 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
$addon=Read-ExactV060 'validation\v0.6.28\out\bin\addon-manager.ps1' 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$enter=Get-V060ExactFunction $main 'Enter-SpotifyControlMutex'
$leave=Get-V060ExactFunction $main 'Exit-SpotifyControlMutex'
$maintain=Get-V060ExactFunction $main 'Maintain'
$agent=Get-V060ExactFunction $main 'Invoke-ResidentAgentTick'
$mutexBody=[string]$enter.Extent.Text
$maintainBody=[string]$maintain.Extent.Text
$agentBody=[string]$agent.Extent.Text
Assert-V060 ($mutexBody.Contains('Local\SpotifyControl-{0}-{1}') -and
 $mutexBody.Contains('$Purpose,$safeSid') -and
 $mutexBody.Contains('WaitOne(0,$false)') -and
 $maintainBody.Contains('Enter-SpotifyControlMutex -Purpose "Maintenance"') -and
 $maintainBody.Contains('if ($null -eq $lease)') -and
 $agentBody.Contains('Enter-SpotifyControlMutex -Purpose "AgentTick"') -and
 $agentBody.Contains('Maintain')) 'REAL_MAIN_MUTEX_OR_CALLER_GUARD_DRIFT'
# Dot-source ONLY the two exact verified function AST extents and a benign
# no-op error logger (used solely if the lock cannot be acquired).
$code='function Write-Log { param([string]$Message,[string]$Level="INFO") }'+
 [Environment]::NewLine + [string]$enter.Extent.Text +
 [Environment]::NewLine + [string]$leave.Extent.Text
. ([scriptblock]::Create($code))
$held=Enter-SpotifyControlMutex -Purpose Maintenance
Assert-V060 ($null-ne$held -and $held -is [System.Threading.Mutex]) 'LEGACY_MAIN_MUTEX_UNAVAILABLE'
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$testRoot=Join-Path $root ('v060-mutex-interop-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$child=Join-Path $testRoot 'legacy-main-source-lock-probe.ps1'
$childScript='param([ValidateSet("Maintenance","AgentTick")][string]$Purpose)'+
 [Environment]::NewLine + $code + [Environment]::NewLine +
 '$lease=Enter-SpotifyControlMutex -Purpose $Purpose'+[Environment]::NewLine +
 'if($null-eq$lease){exit 17}'+[Environment]::NewLine +
 'Exit-SpotifyControlMutex -Mutex $lease'+[Environment]::NewLine+'exit 0'+[Environment]::NewLine
[IO.File]::WriteAllText($child,$childScript,[Text.UTF8Encoding]::new($false))
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
Assert-V060 ([IO.File]::Exists($ps)) 'WINDOWS_POWERSHELL_NOT_FOUND'
function Probe-V060([string]$Purpose){
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$ps
 $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$child+'" -Purpose '+$Purpose
 $psi.WorkingDirectory=$testRoot
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 try{
  $p.StartInfo=$psi
  if(-not$p.Start()){throw 'V060_PROBE_CHILD_START_FAILED'}
  if(-not$p.WaitForExit(20000)){
   # Only our newly spawned scratch child; no legacy/Spoitfy processes.
   $p.Kill();[void]$p.WaitForExit()
   throw 'V060_PROBE_CHILD_TIMEOUT'
  }
  $stdout=$p.StandardOutput.ReadToEnd()
  $stderr=$p.StandardError.ReadToEnd()
  if($stdout.Length+$stderr.Length -gt 8000){
    throw 'V060_PROBE_CHILD_UNEXPECTED_OUTPUT'
  }
  return [int]$p.ExitCode
 }finally{$p.Dispose()}
}
try{
 $blocked=Probe-V060 'Maintenance'
 Assert-V060 ($blocked -eq 17) 'UNPATCHED_STABLE_MAINTENANCE_NOT_BLOCKED_BY_EXISTING_MUTEX'
 Write-Host 'V060_REAL_STABLE_MAINTENANCE_MUTEX_HELD_BLOCKS_OTHER_PROCESS_PASS'
 $agentIndependent=Probe-V060 'AgentTick'
 Assert-V060 ($agentIndependent -eq 0) 'AGENTTICK_AND_MAINTENANCE_MUTEXES_NOT_DISTINCT'
 Write-Host 'V060_LEGACY_AGENTTICK_MUTEX_DISTINCT_AND_MAINTENANCE_REMAINS_BLOCKED_PASS'
 Assert-V060 ((Probe-V060 'Maintenance') -eq 17) 'SECOND_MAINTENANCE_PROBE_BYPASSED_LEASE'
}finally{
 Exit-SpotifyControlMutex -Mutex $held
}
Assert-V060 ((Probe-V060 'Maintenance') -eq 0) 'OLD_MAINTENANCE_MUTEX_NOT_RELEASED_CROSS_PROCESS'
Write-Host 'V060_REAL_STABLE_MAINTENANCE_OS_MUTEX_RELEASES_FOR_CHILD_PROCESS_PASS'
# The original Addon Manager r17 is a separately launched PowerShell script.
# Enumerate the three real mutation entrypoints and their SAME-PROCESS guards.
# This is static evidence; absence of one token cannot imply there are
# no protections anywhere else. No execution of mutating functions.
$direct=@('Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction')
foreach($name in $direct){
 $fn=Get-V060ExactFunction $addon $name
 $body=[string]$fn.Body.Extent.Text
 $hasNewLease=$body.Contains('Enter-CustomAppEngineTurnstileV047')
 $hasMainMutex=$body.Contains('Enter-SpotifyControlMutex')
 $hasEnrollmentGuard=$body.Contains('Assert-CustomAppNormalUpdateEngineExclusivityV010')
 Write-Host ('V060_PINNED_R17_'+$name.ToUpperInvariant().Replace('-','_')+
    '_SHARED_TURNSTILE='+[bool]$hasNewLease+
    ';MAIN_MUTEX='+[bool]$hasMainMutex+
    ';PREEXISTING_ENROLLMENT_GUARD='+[bool]$hasEnrollmentGuard)
}
# Do not grant authority even if source shows a preexisting enrollment guard:
# installed profile state and any copied old scripts are unobserved.
Write-Host 'V060_PINNED_STABLE_MAIN_R17_FUNCTIONS_ONLY_NO_LIVE_PROGRAM_EXECUTION_PASS'
Write-Host 'V060_NO_USER_TASK_PROFILE_STARTUP_OR_SPOTIFY_MUTATION_NO_PRODUCTION_AUTHORITY_PASS'
