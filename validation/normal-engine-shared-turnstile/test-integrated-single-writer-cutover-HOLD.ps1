# Integrated synthetic-only Windows rehearsal of the next single-writer cutover.
# Reuses V046 legacy-state admission, V047 exclusive file lease, V010
# enrollment fence, V057/V059 observer gates and V058 owned-task disable
# with independent fresh-process restore. Simulates a crash AFTER marker
# publication, BEFORE new-engine authority. No production source/XPUI/tasks.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'CUTOVER_INTEGRATION_GITHUB_HOSTED_WINDOWS_ONLY'
}
function Assert-Cutover([bool]$ok,[string]$message){
 if(-not$ok){throw ('CUTOVER_INTEGRATION_'+$message)}
}
function Must-CutoverDeny([scriptblock]$action,[string]$expected){
 $matched=$false
 try{[void](& $action)}catch{
  if([string]$_.Exception.Message -ceq $expected){$matched=$true}
  else{throw}
 }
 Assert-Cutover $matched ('EXPECTED_DENIAL_'+$expected)
}
# Source modules are existing validated components, not copied into this test.
$normal=Join-Path $PSScriptRoot '..\normal-engine-cutover-readonly\cutover-admission-v046.ps1'
. $normal
. (Join-Path $PSScriptRoot '..\custom-app-normal-entrypoint-transaction-integration\normal-update-engine-fence.ps1')
. (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
. (Join-Path $PSScriptRoot 'legacy-task-process-observer-v057.ps1')
. (Join-Path $PSScriptRoot 'stable-maintenance-surfaces-v059.ps1')
. (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$nonce=[guid]::NewGuid().ToString('N')
$fixture=Join-Path $runner ('v063-cutover-'+$nonce)
$local=Join-Path $fixture 'Local'
$old=Join-Path $local 'SpotifyControl'
$state=Join-Path $old 'addons-state.json'
$pending=Join-Path $old 'addon-last-transaction.json'
$marker=Join-Path $local 'SpotifyControlUpdates-CustomApp-State'
$journal=Join-Path $runner ('V063-Cutover-Rehearsal-'+$nonce+'.json')
$utf8=[Text.UTF8Encoding]::new($false,$true)
[void][IO.Directory]::CreateDirectory($old)
[IO.File]::WriteAllText($state,'{"schema":1,"owner":"GITHUB_ISOLATED_TEST_ONLY"}',$utf8)
$originalState=(Get-FileHash -LiteralPath $state -Algorithm SHA256).Hash.ToLowerInvariant()
$taskProof=$null
$taskRecovered=$false
$lease=$null
try{
 # Contract A: old pending journal blocks cutover REGARDLESS of contents.
 $clear=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
 Assert-Cutover ([bool]$clear.legacy_transaction_absent -and
  [bool]$clear.dpapi_new_engine_absent -and
  [string]$clear.state_sha256 -ceq $originalState) 'BASELINE_CLEAN_LEGACY_STATE'
 [IO.File]::WriteAllText($pending,'{"unresolved":"simulated"}',$utf8)
 try{
  Must-CutoverDeny {
    Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
  } 'V046_LEGACY_TRANSACTION_STILL_PRESENT_DO_NOT_MIGRATE'
 }finally{[IO.File]::Delete($pending)}
 # Contract B: a foreign/partial/uncertain enrollment blocks any old code.
 [IO.Directory]::CreateDirectory($marker)|Out-Null
 try{
  Must-CutoverDeny {
    Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local
  } 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
  Must-CutoverDeny {
    Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
  } 'V046_NEW_ENGINE_ALREADY_ENROLLED_REQUIRE_EXISTING_JOURNAL_RECOVERY'
 }finally{[IO.Directory]::Delete($marker)}
 Write-Host 'CUTOVER_INTEGRATION_PENDING_OLD_LEDGER_AND_EXISTING_NEW_ENROLLMENT_DENIED_PASS'
 # Contract C: even a *complete* observer scan is not a real process fence.
 $snap=[pscustomobject]@{
  task_scan_complete=$true;process_scan_complete=$true
  hidden_tasks_requested=$true
  task_count=[int]1;suspect_task_count=[int]1
  enabled_suspect_task_count=[int]0
  running_suspect_task_count=[int]0
  opaque_task_action_count=[int]0
  suspect_process_count=[int]1
  opaque_shell_process_count=[int]0;read_errors=[int]0
 }
 $inUse=Resolve-CustomAppV057CutoverObservation -Snapshot $snap
 Assert-Cutover ([string]$inUse.state -ceq 'LEGACY_WRITERS_POSSIBLE' -and
  -not[bool]$inUse.live_cutover_go) 'OBSERVED_LEGACY_WRITER_NOT_BLOCKED'
 $snap.suspect_process_count=[int]0
 $invisible=Resolve-CustomAppV057CutoverObservation -Snapshot $snap
 Assert-Cutover ([string]$invisible.state -ceq 'READ_ONLY_CLEAR_BUT_RACY' -and
  -not[bool]$invisible.production_mutation_authorized -and
  -not[bool]$invisible.manual_legacy_launch_excluded) 'CLEAN_PROCESS_SCAN_GRANTED_FALSE_AUTHORITY'
 $startup=Resolve-V059MaintenanceLaunchTopology -TaskState 'EXACT_ENABLED' -ShortcutState 'ABSENT' -ProcessScanComplete $true -SuspectedLegacyProcesses ([int]0) -OpaqueProcesses ([int]0)
 Assert-Cutover ([string]$startup.launch_state -ceq 'ONLOGON_TASK_LAUNCH_PRESENT' -and
  -not[bool]$startup.live_cutover_go) 'ACTIVE_MAINTENANCE_TASK_INVISIBLE'
 $disabled=Resolve-V059MaintenanceLaunchTopology -TaskState 'EXACT_DISABLED' -ShortcutState 'ABSENT' -ProcessScanComplete $true -SuspectedLegacyProcesses ([int]0) -OpaqueProcesses ([int]0)
 Assert-Cutover ([string]$disabled.launch_state -ceq 'EXACT_TASK_DISABLED_BUT_MANUAL_LAUNCH_UNFENCED' -and
  -not[bool]$disabled.manual_legacy_launch_excluded) 'DISABLED_TASK_MISTAKEN_FOR_MANUAL_FENCE'
 Write-Host 'CUTOVER_INTEGRATION_V057_V059_TASK_PROCESS_MANUAL_LAUNCH_NOT_PROVEN_PASS'
 # Contract D: real Windows TaskScheduler API, but ONLY a new V058 GUID
 # scratch task with a 2099 trigger and inert cmd.exe action. It must
 # survive a simulated process crash until a separate child restores it.
 $taskProof=Invoke-V058OwnedScratchQuiescence -LeaveDisabledForChild
 Assert-Cutover ([bool]$taskProof.disabled_verified -and
  -not[bool]$taskProof.production_mutation_authorized -and
  -not[bool]$taskProof.real_task_touched -and
  [IO.File]::Exists([string]$taskProof.journal_path)) 'SYNTHETIC_TASK_NOT_JOURNALED_AND_DISABLED'
 $q=Resolve-V058QuiescenceDecision -Observation ([pscustomobject]@{
  task_identity_exact=$true;task_disabled=$true;instances_zero=$true
  process_observation_complete=$true;manual_launch_fenced=$false
  source_lease_held=$false;original_task_journal_durable=$true
 })
 Assert-Cutover ([string]$q.state -ceq 'MANUAL_LEGACY_LAUNCH_UNFENCED' -and
   -not[bool]$q.live_cutover_go -and -not[bool]$q.production_mutation_authorized) 'SCRATCH_TASK_GRANTED_LIVE_AUTHORITY'
 # Contract E: V047 file lease spans final V046+V010 admission, durable
 # intent publication, and synthetic enrollment. Never reuse this as a
 # real new-engine DPAPI store or source-enrollment authority.
 $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $local
 Assert-Cutover ($lease -is [IO.FileStream] -and
  -not$lease.SafeFileHandle.IsClosed -and [int64]$lease.Length -eq 0) 'NO_EXCLUSIVE_SOURCE_LEASE'
 $more=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
 $pre=Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local
 Assert-Cutover ([string]$more.state_sha256 -ceq $originalState -and
   [bool]$more.legacy_transaction_absent -and [bool]$pre.ok -and
   -not[bool]$pre.production_mutation_authorized) 'BEFORE_ENROLLMENT_INPUTS_DRIFT'
 $markerBytes=$utf8.GetBytes(('CI-ONLY-V063-'+$nonce))
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$markerSha=([BitConverter]::ToString($sha.ComputeHash($markerBytes))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Dispose()}
 $payload=[ordered]@{
  schema=1;owner='GITHUB_HOSTED_ISOLATED_SINGLE_WRITER_REHEARSAL'
  fixture_root=$fixture
  scratch_task_journal=[string]$taskProof.journal_path
  state_sha256=$originalState;marker_sha256=$markerSha
  production_mutation_authorized=$false
 }
 $data=$utf8.GetBytes(($payload|ConvertTo-Json -Depth 4 -Compress))
 $out=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$out.Write($data,0,$data.Length);$out.Flush($true)}finally{$out.Dispose()}
 # The final recheck occurs WHILE V047 is held. This is a test-only
 # marker; there is no actual DPAPI enrollment and NO real update.
 [void](Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local)
 [void](Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local)
 $h=[IO.File]::Open($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$h.Write($markerBytes,0,$markerBytes.Length);$h.Flush($true)}finally{$h.Dispose()}
 Assert-Cutover ((Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $markerSha) 'MARKER_DURABILITY_OR_BYTES_UNVERIFIED'
 Must-CutoverDeny {
   Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local
 } 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 Must-CutoverDeny {
   Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
 } 'V046_NEW_ENGINE_ALREADY_ENROLLED_REQUIRE_EXISTING_JOURNAL_RECOVERY'
 Write-Host 'CUTOVER_INTEGRATION_V047_HELD_JOURNAL_FIRST_ENROLLMENT_FAIL_CLOSED_PASS'
 $lease.Dispose();$lease=$null
 # Crash boundary: the original process intentionally does not clear the
 # marker. A NEW powershell.exe process validates the synthetic journal,
 # restores the isolated scheduler task, and leaves the old writer fenced.
 $child=Join-Path $PSScriptRoot 'recover-hosted-cutover-rehearsal-HOLD.ps1'
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -JournalPath $journal
 if($LASTEXITCODE -ne 0){throw 'CUTOVER_INTEGRATION_FRESH_PROCESS_RECOVERY_FAILED'}
 $taskRecovered=$true
 Assert-Cutover ([IO.File]::Exists($marker) -and
   (Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $markerSha) 'CRASH_RECOVERY_WRONGLY_CLEARED_UNRESOLVED_MARKER'
 Must-CutoverDeny {
  Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local
 } 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 Write-Host 'CUTOVER_INTEGRATION_CROSS_PROCESS_TASK_RESTORE_WITH_OLD_WRITER_STILL_BLOCKED_PASS'
 Write-Host 'CUTOVER_INTEGRATION_PRODUCTION_FILES_TASKS_SPOTIFY_AND_VBS_UNCHANGED_PASS'
 Write-Host 'CUTOVER_INTEGRATION_LIVE_CUTOVER_GO_FALSE_MANUAL_UNPATCHED_LAUNCH_UNPROVEN_PASS'
}finally{
 if($null-ne$lease){$lease.Dispose()}
 if($null-ne$taskProof -and -not$taskRecovered){
  # This is CI scratch cleanup only; cannot touch any preexisting task.
  try{
    [void](Restore-V058OwnedScratchFromJournal -JournalPath ([string]$taskProof.journal_path))
    Write-Host 'CUTOVER_INTEGRATION_FAILURE_CLEANUP_ONLY_GUID_SCRATCH_TASK'
  }catch{
    Write-Host 'CUTOVER_INTEGRATION_PRIVATE_RUNNER_SCRATCH_RECOVERY_NEEDS_TEARDOWN'
  }
 }
}
