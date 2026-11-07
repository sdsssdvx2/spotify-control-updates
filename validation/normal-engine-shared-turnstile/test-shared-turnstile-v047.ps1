# Actual generated Addon Manager handlers plus direct process-level lock.
# No real Spotify install, network, user home, or active legacy transaction.
param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V047_TEST_HOSTED_WINDOWS_ONLY'
}
. (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
function Assert-V047([bool]$ok,[string]$reason){if(-not$ok){throw ('V047_TEST_'+$reason)}}
function Must-Throw-V047([scriptblock]$body,[string]$code){
 $denied=$false
 try{& $body|Out-Null}catch{if([string]$_.Exception.Message -ceq $code){$denied=$true}else{throw}}
 Assert-V047 $denied ('WRONG_DENIAL_'+$code)
}
$source=(Resolve-Path -LiteralPath $CandidatePath).Path
$tok=$null;$errs=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tok,[ref]$errs)
Assert-V047 ($errs.Count -eq 0) 'CANDIDATE_PS51_PARSE_ERROR'
$fns=@($ast.FindAll({
 param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]
},$true))
foreach($name in @('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction')){
 $found=@($fns|Where-Object{$_.Name -ceq $name})
 Assert-V047 ($found.Count -eq 1) ('ORIGINAL_HANDLER_MISSING_'+$name)
 $body=[string]$found[0].Body.Extent.Text
 Assert-V047 ($body.IndexOf('Enter-CustomAppEngineTurnstileV047',[StringComparison]::Ordinal) -ge 0 -and
   $body.IndexOf('Enter-CustomAppEngineTurnstileV047',[StringComparison]::Ordinal) -lt
     $body.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal) -and
   $body.Contains('} finally {') -and
   $body.Contains('$__engineLeaseV047.Dispose()')) ('ENTRYPOINT_NOT_WRAPPED_'+$name)
}
Write-Host 'V047_REAL_GENERATED_ADDON_AUTO_AND_BOTH_MANUAL_HANDLERS_WRAPPED_PASS'
$fixture=Join-Path $env:RUNNER_TEMP ('v047-lock-fixture-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'SpotifyControl'))|Out-Null
$held=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $fixture
Assert-V047 ($null-ne$held -and $held -is [IO.FileStream]) 'EXCLUSIVE_LOCK_NOT_FILE_STREAM'
$lock=Join-Path (Join-Path $fixture 'SpotifyControl') '.engine-cutover-turnstile.lock'
Assert-V047 ([IO.File]::Exists($lock) -and (Get-Item $lock).Length -eq 0) 'LOCK_FILE_NOT_EMPTY_ZERO_BYTE'
Must-Throw-V047 {Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $fixture} 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'
# Separate PowerShell process tries to acquire identical FileShare.None;
# full process loss cannot leave a stale in-memory Windows lease.
$childPath=Join-Path $fixture 'turnstile-child-probe.ps1'
$childCode=@'
param([string]$Module,[string]$HostedRoot)
$ErrorActionPreference='Stop'
. $Module
try{
 $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $HostedRoot
 $lease.Dispose()
 exit 0
}catch{
 if([string]$_.Exception.Message -ceq 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'){exit 17}
 exit 19
}
'@
[IO.File]::WriteAllText($childPath,$childCode,[Text.UTF8Encoding]::new($false))
function Invoke-Child-V047 {
 param([string]$Probe,[string]$Module,[string]$HostedRoot)
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName='powershell.exe'
 $p.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Probe+'" -Module "'+$Module+'" -HostedRoot "'+$HostedRoot+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true
 $p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 $proc=New-Object Diagnostics.Process
 try{
   $proc.StartInfo=$p
   if(-not$proc.Start()){throw 'V047_SUBPROCESS_COULD_NOT_START'}
   if(-not$proc.WaitForExit(20000)){
     $proc.Kill();[void]$proc.WaitForExit()
     throw 'V047_SUBPROCESS_TIMEOUT'
   }
   return [int]$proc.ExitCode
 }finally{$proc.Dispose()}
}
$modulePath=Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1'
$denied=Invoke-Child-V047 -Probe $childPath -Module $modulePath -HostedRoot $fixture
Assert-V047 ($denied -eq 17) 'SECOND_PROCESS_NOT_DENIED_WHEN_FIRST_HOLDS_LOCK'
$held.Dispose()
$again=Invoke-Child-V047 -Probe $childPath -Module $modulePath -HostedRoot $fixture
Assert-V047 ($again -eq 0) 'PROCESS_EXIT_OR_DISPOSE_DID_NOT_RELEASE_LEASE'
$lockHandle=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $fixture
$lockHandle.Dispose()
Write-Host 'V047_CROSS_PROCESS_FILESHARE_EXCLUSIVITY_RELEASE_AND_REOPEN_PASS'
# A malformed object at the exact lock name cannot be silently ignored.
[IO.File]::WriteAllText($lock,'NOT_THE_ZERO_BYTE_LOCK')
Must-Throw-V047 {Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $fixture} 'V047_ENGINE_LOCK_FILE_REPARSE_OR_INVALID'
Assert-V047 ([IO.File]::ReadAllText($lock) -ceq 'NOT_THE_ZERO_BYTE_LOCK') 'MALFORMED_LOCK_FILE_OVERWRITTEN'
Write-Host 'V047_MALFORMED_LOCK_FAIL_CLOSED_AND_NO_FORCED_DELETE_PASS'
# The real Addon Manager's Update branch is exercised ONLY under an
# enrolled marker on this throwaway GitHub user; it must fail before any
# original rollback, source download or modification, and release lease.
$realLocal=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$legacy=Join-Path $realLocal 'SpotifyControl'
$enrolled=Join-Path $realLocal 'SpotifyControlUpdates-CustomApp-State'
Assert-V047 (-not[IO.File]::Exists($enrolled) -and
 -not[IO.Directory]::Exists($enrolled)) 'HOSTED_RUNNER_OLD_NEW_MARKER_PREEXISTS'
[IO.Directory]::CreateDirectory($legacy)|Out-Null
[IO.Directory]::CreateDirectory($enrolled)|Out-Null
try{
 $log=Join-Path $fixture 'generated-action-update.log'
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $source -Action Update -Force *>&1 |
  Tee-Object -FilePath $log | Out-Null
 $rc=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 Assert-V047 ($rc -ne 0) 'ACTUAL_GENERATED_UPDATE_BYPASSED_ENGINE_ENROLLMENT_GUARD'
 $errorLog=Join-Path $legacy 'logs\addons-error.log'
 Assert-V047 ([IO.File]::Exists($errorLog)) 'GENERATED_ADDON_DID_NOT_LOG_LEGACY_GUARD'
 $content=[IO.File]::ReadAllText($errorLog)
 Assert-V047 ($content.Contains('normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration')) 'LEGACY_GUARD_NOT_INSIDE_NEW_EXCLUSIVE_LEASE'
 $after=Enter-CustomAppEngineTurnstileV047
 Assert-V047 ($null-ne$after -and $after -is [IO.FileStream]) 'ACTUAL_HANDLER_FAILED_TO_RELEASE_LEASE_AFTER_DENIAL'
 $after.Dispose()
 Assert-V047 ([IO.Directory]::Exists($enrolled)) 'REAL_HANDLER_REMOVED_NEW_ENGINE_MARKER'
 Write-Host 'V047_ACTUAL_ADDON_ACTION_UPDATE_IN_LEASE_THEN_OLD_NEW_FENCE_DENIED_PASS'
}finally{
 if([IO.Directory]::Exists($enrolled)){
   if(@(Get-ChildItem -LiteralPath $enrolled -Force).Count){throw 'V047_CI_MARKER_ALTERED_DO_NOT_CLEANUP'}
   [IO.Directory]::Delete($enrolled)
 }
}
Write-Host 'V047_EXISTING_LEGACY_NO_NEW_ENGINE_START_OR_INSTALLED_SPOTIFY_TOUCH_PASS'

# Close the former V046 standalone readiness gap: the new candidate must
# recheck the SAME real profile snapshot under the SAME lock used by
# generated old Update/Commit/Rollback. Reuse the already qualified hosted
# V046 source+XPUI fixture, without downloading or modifying real Spotify.
. (Join-Path $PSScriptRoot '..\normal-engine-cutover-readonly/test-cutover-admission-v046.ps1')
. (Join-Path $PSScriptRoot 'locked-cutover-admission-v047.ps1')
$admission=Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs
Assert-V047 ($admission.status -ceq 'observed-readonly' -and
 $admission.profile_sha256 -cmatch '^[a-f0-9]{64}
) 'V046_FIXTURE_NOT_COHERENT_AFTER_ADMISSION_TESTS'
$expected=[string]$admission.profile_sha256
$session=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $expected @fixtureArgs
Assert-V047 ($session.status -ceq 'locked-readonly' -and
 $session.lock_handle -is [IO.FileStream] -and
 $session.binding_sha256 -ceq $expected -and
 $session.cooperative_legacy_engine_lease_held -and
 -not$session.older_unpatched_processes_excluded -and
 -not$session.production_mutation_authorized -and
 -not$session.enrollment_authorized -and
 -not$session.backup_preimage_durable) 'NEW_ENGINE_LOCKED_ADMISSION_GRANTED_UNQUALIFIED_AUTHORITY'
$childBlocked=Invoke-Child-V047 -Probe $childPath -Module $modulePath -HostedRoot (Join-Path $root 'Local')
Assert-V047 ($childBlocked -eq 17) 'OLD_ENGINE_CAN_ENTER_WHILE_NEW_CUTOVER_HOLDS_SAME_LEASE'
$session.lock_handle.Dispose()
Assert-V047 ((Invoke-Child-V047 -Probe $childPath -Module $modulePath -HostedRoot (Join-Path $root 'Local')) -eq 0) 'NEW_CUTOVER_LEASE_NOT_RELEASED'
Write-Host 'V047_LOCKED_PROFILE_ADMISSION_RECHECK_AND_CROSS_ENGINE_EXCLUSIVITY_PASS'
[IO.File]::WriteAllText($pending,'{"status":"awaiting-apply"}')
try{
 Must-Throw-V047 {Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $expected @fixtureArgs} 'V047_LOCKED_PROFILE_NOT_QUALIFIED'
 Assert-V047 ([IO.File]::Exists($pending)) 'NEW_ADMISSION_ERASED_OLD_PENDING_TRANSACTION'
}finally{[IO.File]::Delete($pending)}
$defer=@{};foreach($k in $fixtureArgs.Keys){$defer[$k]=$fixtureArgs[$k]}
$defer.SimulatedSpotifyRunning=$true
Must-Throw-V047 {Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $expected @defer} 'V047_LOCKED_PROFILE_NOT_QUALIFIED'
Must-Throw-V047 {Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 ('0'*64) @fixtureArgs} 'V047_LOCKED_PROFILE_NOT_QUALIFIED'
Assert-V047 ((Invoke-Child-V047 -Probe $childPath -Module $modulePath -HostedRoot (Join-Path $root 'Local')) -eq 0) 'FAILED_NEW_ADMISSION_LEAKED_EXCLUSIVE_LOCK'
Write-Host 'V047_PENDING_LEGACY_RUNNING_SPOTIFY_AND_CHANGED_BINDING_RELEASE_LOCK_PASS'
Assert-V047 (-not[IO.Directory]::Exists((Join-Path $root 'Local\SpotifyControlUpdates-CustomApp-State')) -and
 -not[IO.File]::Exists($pending) -and
 (Get-FileHash $state -Algorithm SHA256).Hash -ceq $legacyStart) 'NEW_ENGINE_ADMISSION_WROTE_ACTIVE_OR_OLD_STATE'
Write-Host 'V047_NEW_ENGINE_NO_ENROLLMENT_NO_SPOTIFY_CHANGE_NO_USER_MUTATION_PASS'

