# Windows hosted ONLY. Real candidate bytes, real Win32 File.Replace and
# fresh-process intent-bound rollback. Never touches installed Spotify.
param([switch]$Recover,
 [switch]$RecoverCombined,
 [string]$FixtureRoot,
 [string]$Journal,
 [string]$JournalSha256,
 [string]$ScratchTaskJournal,
 [string]$BundleRoot,
 [string]$OriginalMain,
 [string]$OriginalAddon)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'hosted-atomic-source-pair-cutover-HOLD.ps1')
if($Recover){
 $status=Restore-V064HostedSourcePair -FixtureRoot $FixtureRoot -Journal $Journal -JournalSha256 $JournalSha256
 if([string]$status.status -cne 'HOSTED_OLD_SOURCES_RESTORED_FROM_JOURNAL' -or
  -not[bool]$status.source_bytes_exact -or
  [bool]$status.production_mutation_authorized){
  throw 'V064_CHILD_RECOVERY_STATUS_INVALID'
 }
 Write-Host 'V064_FRESH_CHILD_WIN32_ATOMIC_FILE_REPLACE_RECOVERY_PASS'
 if($RecoverCombined){
  # Restore the exact verified old scripts FIRST, then (and only then)
  # re-enable/remove our freshly owned far-future synthetic task.
  Assert-V064 (-not[string]::IsNullOrWhiteSpace($ScratchTaskJournal)) 'COMBINED_RECOVERY_NEEDS_TASK_JOURNAL'
  . (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
  $result=Restore-V058OwnedScratchFromJournal -JournalPath $ScratchTaskJournal
  Assert-V064 ([bool]$result.recovered_in_fresh_process -and
    [bool]$result.enabled_state_restored -and
    [bool]$result.scratch_task_deleted -and
    -not[bool]$result.user_task_mutation -and
    -not[bool]$result.production_mutation_authorized) 'COMBINED_RECOVERY_TASK_NOT_RESTORED_AFTER_SOURCE'
  Write-Host 'V064_FRESH_CHILD_OLD_SOURCE_FIRST_THEN_OWNED_SCRATCH_TASK_RESTORED_PASS'
 }
 return
}
Assert-V064 (-not[string]::IsNullOrWhiteSpace($BundleRoot) -and
 -not[string]::IsNullOrWhiteSpace($OriginalMain) -and
 -not[string]::IsNullOrWhiteSpace($OriginalAddon)) 'TEST_REQUIRED_INPUTS_MISSING'
$stableMain=(Resolve-Path -LiteralPath $OriginalMain).Path
$stableAddon=(Resolve-Path -LiteralPath $OriginalAddon).Path
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
Assert-V064 (
 (Get-V064Sha $stableMain) -ceq 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0' -and
 (Get-V064Sha $stableAddon) -ceq '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
) 'TEST_STABLE_SOURCE_PROVENANCE_FAILED'
function New-V064PrivateFixture {
 $id=[guid]::NewGuid().ToString('N')
 $root=Join-Path $env:RUNNER_TEMP ('v064-source-'+$id)
 $bin=Join-Path $root 'Local\SpotifyControl\bin'
 $recovery=Join-Path $root 'Recovery'
 [void][IO.Directory]::CreateDirectory($bin)
 [void][IO.Directory]::CreateDirectory($recovery)
 $main=Join-Path $bin 'spotify-control.ps1'
 $addon=Join-Path $bin 'addon-manager.ps1'
 Copy-V064DurableNew -Source $stableMain -Target $main -ExpectedSha (Get-V064Sha $stableMain)
 Copy-V064DurableNew -Source $stableAddon -Target $addon -ExpectedSha (Get-V064Sha $stableAddon)
 $state=Join-Path $root 'Local\SpotifyControl\addons-state.json'
 [IO.File]::WriteAllText($state,'{"schema":1,"ownership":"private_github_ci_only"}',([Text.UTF8Encoding]::new($false,$true)))
 $extra=Join-Path $bin 'spotify-control-agent.vbs'
 [IO.File]::WriteAllText($extra,'WScript.Echo "synthetic-unmodified-agent"',([Text.UTF8Encoding]::new($false,$true)))
 return [pscustomobject]@{root=$root;main=$main;addon=$addon;state=$state;extra=$extra
  stateHash=(Get-V064Sha $state);extraHash=(Get-V064Sha $extra)}
}
function Invoke-V064Child {
 param($Result,[switch]$ExpectedFailure)
 $before=$ErrorActionPreference
 if($ExpectedFailure){$ErrorActionPreference='Continue'}
 try{
  if($ExpectedFailure){
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Recover -FixtureRoot $Result.root -Journal $Result.journal -JournalSha256 $Result.journal_sha256 *> $null
  }else{
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Recover -FixtureRoot $Result.root -Journal $Result.journal -JournalSha256 $Result.journal_sha256
  }
  $exit=$LASTEXITCODE
 }finally{$ErrorActionPreference=$before}
 if($ExpectedFailure){
  Assert-V064 ($exit -ne 0) 'INVALID_RECOVERY_JOURNAL_ACCEPTED'
 }else{
  Assert-V064 ($exit -eq 0) 'FRESH_PROCESS_RECOVERY_FAILED'
 }
}
function Check-V064Preservation($Fixture){
 Assert-V064 ((Get-V064Sha $Fixture.state) -ceq $Fixture.stateHash -and
  (Get-V064Sha $Fixture.extra) -ceq $Fixture.extraHash) 'UNRELATED_STATE_OR_AGENT_MUTATED'
}
$bundlePath=(Resolve-Path -LiteralPath $BundleRoot).Path
$expectedManifest=Get-Content -LiteralPath (Join-Path $bundlePath 'MANIFEST-HOLD.json') -Raw|ConvertFrom-Json
# Case 1: fail between first and second file. Recovery does not infer a
# successful pair from a successful first rename.
$f1=New-V064PrivateFixture
$r1=Start-V064HostedSourcePairPublish -FixtureRoot $f1.root -BundleRoot $bundlePath -InjectStop 'after-main' -ExplicitHostedSimulationApproval
Assert-V064 ([string]$r1.status -ceq 'HOSTED_INJECTED_STOP_AFTER_FIRST_REPLACE' -and
 (Get-V064Sha $f1.main) -ceq [string]$expectedManifest.candidate_main_sha256 -and
 (Get-V064Sha $f1.addon) -ceq [string]$expectedManifest.original_addon_sha256) 'FIRST_REPLACE_INTERRUPTION_NOT_REAL'
Invoke-V064Child -Result ([pscustomobject]@{root=$f1.root;journal=$r1.journal;journal_sha256=$r1.journal_sha256})
Assert-V064 ((Get-V064Sha $f1.main) -ceq [string]$expectedManifest.original_main_sha256 -and
 (Get-V064Sha $f1.addon) -ceq [string]$expectedManifest.original_addon_sha256) 'FIRST_REPLACE_ROLLBACK_NOT_BYTE_EXACT'
Check-V064Preservation $f1
Write-Host 'V064_REAL_MAIN_FIRST_REPLACE_INTERRUPTED_AND_CHILD_ROLLBACK_PASS'
# Case 2: two replacements complete and crash before final authority.
$f2=New-V064PrivateFixture
$r2=Start-V064HostedSourcePairPublish -FixtureRoot $f2.root -BundleRoot $bundlePath -InjectStop 'after-addon' -ExplicitHostedSimulationApproval
Assert-V064 ([string]$r2.status -ceq 'HOSTED_INJECTED_STOP_AFTER_TWO_REPLACES' -and
 (Get-V064Sha $f2.main) -ceq [string]$expectedManifest.candidate_main_sha256 -and
 (Get-V064Sha $f2.addon) -ceq [string]$expectedManifest.candidate_addon_sha256) 'BOTH_REPLACEMENTS_NOT_COMMITTED'
# Adversarial metadata alteration MUST deny before writing either source.
$journalOriginal=[IO.File]::ReadAllBytes([string]$r2.journal)
try{
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 [IO.File]::AppendAllText([string]$r2.journal,'UNTRUSTED_TRAILING_BYTES',$utf8)
 Invoke-V064Child -Result ([pscustomobject]@{root=$f2.root;journal=$r2.journal;journal_sha256=$r2.journal_sha256}) -ExpectedFailure
 Assert-V064 ((Get-V064Sha $f2.main) -ceq [string]$expectedManifest.candidate_main_sha256 -and
  (Get-V064Sha $f2.addon) -ceq [string]$expectedManifest.candidate_addon_sha256) 'TAMPERED_JOURNAL_CHANGED_SOURCES'
}finally{[IO.File]::WriteAllBytes([string]$r2.journal,$journalOriginal)}
Invoke-V064Child -Result ([pscustomobject]@{root=$f2.root;journal=$r2.journal;journal_sha256=$r2.journal_sha256})
Assert-V064 ((Get-V064Sha $f2.main) -ceq [string]$expectedManifest.original_main_sha256 -and
 (Get-V064Sha $f2.addon) -ceq [string]$expectedManifest.original_addon_sha256) 'TWO_REPLACEMENT_ROLLBACK_FAILED'
# Repeated recovery is idempotent and cannot overwrite old source.
Invoke-V064Child -Result ([pscustomobject]@{root=$f2.root;journal=$r2.journal;journal_sha256=$r2.journal_sha256})
Check-V064Preservation $f2
Write-Host 'V064_REAL_TWO_REPLACES_JOURNAL_TAMPER_DENIED_AND_IDEMPOTENT_ROLLBACK_PASS'
# Case 3: arbitrary external drift on one file means *all* recovery
# activity stops before the other target can be changed.
$f3=New-V064PrivateFixture
$r3=Start-V064HostedSourcePairPublish -FixtureRoot $f3.root -BundleRoot $bundlePath -InjectStop 'after-main' -ExplicitHostedSimulationApproval
[IO.File]::AppendAllText($f3.addon,'EXTERNAL_DRIFT',([Text.UTF8Encoding]::new($false,$true)))
Invoke-V064Child -Result ([pscustomobject]@{root=$f3.root;journal=$r3.journal;journal_sha256=$r3.journal_sha256}) -ExpectedFailure
Assert-V064 ((Get-V064Sha $f3.main) -ceq [string]$expectedManifest.candidate_main_sha256) 'RECOVERED_MAIN_BEFORE_DETECTING_ADDON_DRIFT'
# Only CI tests may restore the local synthetic test input directly.
[IO.File]::WriteAllBytes($f3.addon,[IO.File]::ReadAllBytes($stableAddon))
Invoke-V064Child -Result ([pscustomobject]@{root=$f3.root;journal=$r3.journal;journal_sha256=$r3.journal_sha256})
Check-V064Preservation $f3
Write-Host 'V064_CROSS_FILE_EXTERNAL_DRIFT_BLOCKED_BEFORE_ANY_ROLLBACK_PASS'
# Case 4: clean original pair is replaceable only inside disposable CI,
# never deployable, but the exact two candidate SHA values match after
# atomic publication and can be independently reversed.
$f4=New-V064PrivateFixture
$r4=Start-V064HostedSourcePairPublish -FixtureRoot $f4.root -BundleRoot $bundlePath -ExplicitHostedSimulationApproval
Assert-V064 ([string]$r4.status -ceq 'HOSTED_SOURCE_PAIR_ONLY_COMMITTED' -and
 -not[bool]$r4.production_mutation_authorized -and
 (Get-V064Sha $f4.main) -ceq [string]$expectedManifest.candidate_main_sha256 -and
 (Get-V064Sha $f4.addon) -ceq [string]$expectedManifest.candidate_addon_sha256) 'CLEAN_SOURCE_PAIR_NOT_BYTE_VERIFIED'
Invoke-V064Child -Result ([pscustomobject]@{root=$f4.root;journal=$r4.journal;journal_sha256=$r4.journal_sha256})
Check-V064Preservation $f4
Write-Host 'V064_REAL_COHERENT_MAIN_ADDON_PAIR_PUBLISHED_AND_INDEPENDENTLY_REVERTED_PASS'
# Case 5: one real TaskScheduler scratch disable + exact two-file source
# replacement + independent rollback. The old task must NEVER be re-enabled
# while the candidate scripts remain installed after a failed recovery.
. (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
$f5=New-V064PrivateFixture
$taskProof=$null;$taskDone=$false;$r5=$null
try{
 $taskProof=Invoke-V058OwnedScratchQuiescence -LeaveDisabledForChild
 Assert-V064 ([bool]$taskProof.disabled_verified -and
  -not[bool]$taskProof.production_mutation_authorized) 'COMBINED_TASK_NOT_DISABLED'
 $r5=Start-V064HostedSourcePairPublish -FixtureRoot $f5.root -BundleRoot $bundlePath -InjectStop 'after-addon' -ExplicitHostedSimulationApproval
 Assert-V064 ((Get-V064Sha $f5.main) -ceq [string]$expectedManifest.candidate_main_sha256 -and
  (Get-V064Sha $f5.addon) -ceq [string]$expectedManifest.candidate_addon_sha256) 'COMBINED_ACTUAL_SOURCE_PAIR_NOT_REPLACED'
 $journalOriginal=[IO.File]::ReadAllBytes([string]$r5.journal)
 try{
  [IO.File]::AppendAllText([string]$r5.journal,'UNTRUSTED_APPEND',([Text.UTF8Encoding]::new($false,$true)))
  $prev=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  try{
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Recover -RecoverCombined -FixtureRoot $f5.root -Journal $r5.journal -JournalSha256 $r5.journal_sha256 -ScratchTaskJournal $taskProof.journal_path *> $null
   $bad=$LASTEXITCODE
  }finally{$ErrorActionPreference=$prev}
  Assert-V064 ($bad -ne 0) 'CORRUPT_SOURCE_RECOVERY_ALLOWED_TASK_REENABLE'
  $svc=New-Object -ComObject Schedule.Service
  $svc.Connect()
  $taskFolder=$svc.GetFolder('\')
  $task=$taskFolder.GetTask([string]$taskProof.scratch_task_name)
  Assert-V064 (-not[bool]$task.Enabled -and
    (Get-V064Sha $f5.main) -ceq [string]$expectedManifest.candidate_main_sha256) 'CORRUPT_SOURCE_RECOVERY_ENABLED_TASK_OR_OVERWROTE_SOURCE'
 }finally{[IO.File]::WriteAllBytes([string]$r5.journal,$journalOriginal)}
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Recover -RecoverCombined -FixtureRoot $f5.root -Journal $r5.journal -JournalSha256 $r5.journal_sha256 -ScratchTaskJournal $taskProof.journal_path
 if($LASTEXITCODE -ne 0){throw 'V064_COMBINED_SOURCE_THEN_SCHEDULER_RECOVERY_FAILED'}
 $taskDone=$true
 Assert-V064 ((Get-V064Sha $f5.main) -ceq [string]$expectedManifest.original_main_sha256 -and
  (Get-V064Sha $f5.addon) -ceq [string]$expectedManifest.original_addon_sha256) 'COMBINED_RECOVERY_NOT_BOTH_OLD_SOURCES'
 Check-V064Preservation $f5
 Write-Host 'V064_ONE_HOSTED_REAL_TASK_DISABLED_UNTIL_BOTH_SOURCE_FILES_RESTORED_PASS'
}finally{
 if($null-ne$taskProof -and -not$taskDone){
  try{[void](Restore-V058OwnedScratchFromJournal -JournalPath ([string]$taskProof.journal_path)}
  catch{Write-Host 'V064_FAILURE_OWNED_GITHUB_RUNNER_TASK_NEEDS_DISPOSABLE_RUNNER_TEARDOWN'}
 }
}
Write-Host 'V064_ALL_TESTS_HOSTED_ONLY_NO_INSTALLED_MAIN_VBS_SPOTIFY_SCHEDULER_DATA_TOUCHED_PASS'
