# CI-only fresh-process recovery after an interrupted synthetic cutover.
# Recovery restores/deletes ONLY a V058 GUID-owned far-future scratch task.
# An already created synthetic enrollment is NOT rolled back or overwritten:
# the old engine must remain blocked until a separately verified authority exists.
param([Parameter(Mandatory=$true)][string]$JournalPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'CUTOVER_REHEARSAL_RECOVERY_HOSTED_ONLY'
}
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$journal=[IO.Path]::GetFullPath($JournalPath)
if(-not$journal.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Path]::GetFileName($journal) -cnotmatch '^V063-Cutover-Rehearsal-[a-f0-9]{32}\.json$' -or
 -not[IO.File]::Exists($journal)){
 throw 'CUTOVER_REHEARSAL_RECOVERY_OUTSIDE_PRIVATE_JOURNAL'
}
$item=Get-Item -LiteralPath $journal -Force -ErrorAction Stop
if($item.PSIsContainer -or
 ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
 [int64]$item.Length -lt 150 -or [int64]$item.Length -gt 8192){
 throw 'CUTOVER_REHEARSAL_RECOVERY_JOURNAL_INVALID'
}
# No journal, marker or fixture contents are printed.
$utf8=[Text.UTF8Encoding]::new($false,$true)
$j=$utf8.GetString([IO.File]::ReadAllBytes($journal)) | ConvertFrom-Json -ErrorAction Stop
$expected=@('schema','owner','fixture_root','scratch_task_journal',
 'state_sha256','marker_sha256','production_mutation_authorized')
if(@($j.PSObject.Properties).Count -ne $expected.Count -or
 @($expected|Where-Object{$null-eq$j.PSObject.Properties[$_]}).Count -gt 0 -or
 [int]$j.schema -ne 1 -or
 [string]$j.owner -cne 'GITHUB_HOSTED_ISOLATED_SINGLE_WRITER_REHEARSAL' -or
 [string]$j.state_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
 [string]$j.marker_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
 $j.production_mutation_authorized -isnot [bool] -or
 [bool]$j.production_mutation_authorized){
 throw 'CUTOVER_REHEARSAL_RECOVERY_SCHEMA_OR_AUTHORITY_INVALID'
}
$fixture=[IO.Path]::GetFullPath([string]$j.fixture_root).TrimEnd('\','/')
$taskJournal=[IO.Path]::GetFullPath([string]$j.scratch_task_journal)
if(-not$fixture.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Path]::GetFileName($fixture) -cnotmatch '^v063-cutover-[a-f0-9]{32}$' -or
 -not$taskJournal.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Path]::GetFileName($taskJournal) -cnotmatch '^V058-Scratch-[a-f0-9]{32}\.json$' -or
 -not[IO.File]::Exists($taskJournal)){
 throw 'CUTOVER_REHEARSAL_RECOVERY_FIXTURE_OR_TASK_UNBOUND'
}
$local=Join-Path $fixture 'Local'
$old=Join-Path $local 'SpotifyControl'
$state=Join-Path $old 'addons-state.json'
$marker=Join-Path $local 'SpotifyControlUpdates-CustomApp-State'
foreach($p in @($fixture,$local,$old)){
 $info=Get-Item -LiteralPath $p -Force -ErrorAction Stop
 if(-not$info.PSIsContainer -or
  ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'CUTOVER_REHEARSAL_RECOVERY_REPARSE_PARENT'
 }
}
foreach($file in @($state,$marker)){
 $info=Get-Item -LiteralPath $file -Force -ErrorAction Stop
 if($info.PSIsContainer -or
  ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'CUTOVER_REHEARSAL_RECOVERY_UNEXPECTED_FILE_TYPE'
 }
}
if((Get-FileHash -LiteralPath $state -Algorithm SHA256).Hash.ToLowerInvariant() -cne
    [string]$j.state_sha256 -or
   (Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash.ToLowerInvariant() -cne
    [string]$j.marker_sha256){
 throw 'CUTOVER_REHEARSAL_RECOVERY_STATE_OR_ENROLLMENT_CHANGED'
}
# Exact V010 production routine executes with hosted override only.
. (Join-Path $PSScriptRoot '..\custom-app-normal-entrypoint-transaction-integration\normal-update-engine-fence.ps1')
$denied=$false
try{[void](Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $local)}
catch{
 if([string]$_.Exception.Message -ceq
   'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'){
  $denied=$true
 }else{throw}
}
if(-not$denied){throw 'CUTOVER_REHEARSAL_RECOVERY_LEGACY_NOT_BLOCKED'}
# Real TaskScheduler calls are contained in the original V058 module, and
# accept only a scratch GUID-named task created by that module in this runner.
. (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
$recovered=Restore-V058OwnedScratchFromJournal -JournalPath $taskJournal
if(-not[bool]$recovered.recovered_in_fresh_process -or
   -not[bool]$recovered.enabled_state_restored -or
   -not[bool]$recovered.scratch_task_deleted -or
   [bool]$recovered.production_mutation_authorized -or
   [bool]$recovered.user_task_mutation){
 throw 'CUTOVER_REHEARSAL_RECOVERY_SCRATCH_TASK_NOT_RESTORED'
}
if((Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash.ToLowerInvariant() -cne
 [string]$j.marker_sha256){
 throw 'CUTOVER_REHEARSAL_RECOVERY_ENROLLMENT_WAS_MODIFIED'
}
Write-Host 'CUTOVER_REHEARSAL_FRESH_PROCESS_SCRATCH_TASK_RESTORED_AND_REMOVED_PASS'
Write-Host 'CUTOVER_REHEARSAL_INTERRUPTED_ENROLLMENT_RETAINED_OLD_WRITER_BLOCKED_PASS'
Write-Host 'CUTOVER_REHEARSAL_NO_PRODUCTION_CUTOVER_OR_MARKER_DELETION_PASS'
