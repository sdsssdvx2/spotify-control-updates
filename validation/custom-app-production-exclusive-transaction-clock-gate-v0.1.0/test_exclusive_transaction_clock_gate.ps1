param([ValidateSet('main','try','crash')][string]$Mode='main',[string]$Name='tagify',[string]$LivePath='',[string]$ReadyPath='',[string]$MarkerJournal='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){throw 'exclusive-gate-test-requires-hosted-Windows'}
. (Join-Path $PSScriptRoot 'custom-app-production-exclusive-transaction-clock-gate.ps1')
function Assert-EG([bool]$Ok,[string]$Why){if(-not$Ok){throw ('EXCLUSIVE_GATE_CI_FAIL '+$Why)}}
if($Mode -ceq 'try'){
    $r=Open-CustomAppProductionExclusiveGateLockV010 -Name $Name -LivePath $LivePath
    if([bool]$r.ok){$r.lock_handle.Dispose();Write-Host 'EXCLUSIVE_CHILD_ACQUIRED';exit 0}
    Write-Host ('EXCLUSIVE_CHILD_DENIED '+[string]$r.reason)
    exit 7
}
if($Mode -ceq 'crash'){
    $g=Open-CustomAppProductionExclusiveGateLockV010 -Name $Name -LivePath $LivePath
    Assert-EG ([bool]$g.ok) ('crash-child-lock-denied '+[string]$g.reason)
    $cid='a'*64;$nonce='b'*32
    $claim=Write-CustomAppProductionExclusiveGateActiveRecordV010 -Lock $g -ConsumptionId $cid -JournalStoreDirectory $MarkerJournal -TransactionNonce $nonce
    Assert-EG ([bool]$claim.ok) ('crash-child-claim-denied '+[string]$claim.reason)
    [IO.File]::WriteAllText($ReadyPath,'CHILD_HAS_DURABLE_ACTIVE_CLAIM',([Text.UTF8Encoding]::new($false)))
    # Parent force-kills this process: intentionally do NOT dispose lock or
    # remove record, reproducing a mid-transaction power/process failure.
    Start-Sleep -Seconds 45
    throw 'crash-child-was-not-killed'
}
$cases=0;$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$demo=Join-Path $root ('exclusive-demo-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($demo)|Out-Null
$live=Join-Path $demo 'live-tagify';[IO.Directory]::CreateDirectory($live)|Out-Null
$journal=Join-Path $demo 'journal-future-transaction'
$clock=Test-CustomAppProductionWallClockAdmissionV010 -SuppliedNow ([DateTimeOffset]::UtcNow)
Assert-EG ([bool]$clock.ok -and $clock.skew_seconds -lt 10) 'clock-current-was-rejected'
$cases++
foreach($x in @(
    [DateTimeOffset]::UtcNow.AddMinutes(-5),
    [DateTimeOffset]::UtcNow.AddMinutes(5),
    [DateTimeOffset]::UtcNow.AddDays(-1)
)){
    $r=Test-CustomAppProductionWallClockAdmissionV010 -SuppliedNow $x
    Assert-EG (-not[bool]$r.ok -and [string]$r.reason -ceq 'wall-clock-supplied-time-not-current') 'synthetic-clock-accepted'
    $cases++
}
$invalid=Test-CustomAppProductionWallClockAdmissionV010 -SuppliedNow ([DateTimeOffset]::UtcNow) -MaxSkewSeconds 86400
Assert-EG (-not[bool]$invalid.ok) 'invalid-clock-skew-config-accepted';$cases++
$path=Get-CustomAppProductionExclusiveGatePathsV010 -Name 'tagify' -LivePath $live
$again=Get-CustomAppProductionExclusiveGatePathsV010 -Name 'tagify' -LivePath $live
Assert-EG ([string]$path.key -ceq [string]$again.key -and [string]$path.key -cmatch '^[0-9a-f]{64}$') 'per-app-key-not-deterministic';$cases++
$rejectName=$false
try{[void](Get-CustomAppProductionExclusiveGatePathsV010 -Name '../bad' -LivePath $live)}catch{$rejectName=$true}
Assert-EG $rejectName 'traversal-name-admitted';$cases++
$rejectPath=$false
try{[void](Get-CustomAppProductionExclusiveGatePathsV010 -Name 'tagify' -LivePath 'C:\Windows\System32')}catch{$rejectPath=$true}
Assert-EG $rejectPath 'operating-system-live-admitted';$cases++
# FileShare.None is OS-protected across DIFFERENT Windows PowerShell processes.
$lock=Open-CustomAppProductionExclusiveGateLockV010 -Name 'tagify' -LivePath $live
Assert-EG ([bool]$lock.ok) ('first-app-exclusive-lock-denied '+[string]$lock.reason)
try{
    $output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode try -Name tagify -LivePath $live)
    $exit=$LASTEXITCODE
    Assert-EG ($exit -eq 7 -and ($output -join ' ') -match 'EXCLUSIVE_CHILD_DENIED') 'cross-process-same-app-lock-not-exclusive'
    $cases++
    $alias=Open-CustomAppProductionExclusiveGateLockV010 -Name 'ivLyrics' -LivePath $live
    Assert-EG (-not[bool]$alias.ok) 'same-live-directory-with-different-app-alias-was-not-serialized'
    $cases++
    $otherLive=Join-Path $demo 'live-other';[IO.Directory]::CreateDirectory($otherLive)|Out-Null
    $other=Open-CustomAppProductionExclusiveGateLockV010 -Name 'ivLyrics' -LivePath $otherLive
    Assert-EG ([bool]$other.ok) 'different-app-transaction-unnecessarily-blocked'
    $other.lock_handle.Dispose()
    $cases++
}finally{$lock.lock_handle.Dispose()}
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode try -Name tagify -LivePath $live)
Assert-EG ($LASTEXITCODE -eq 0 -and ($output -join ' ') -match 'EXCLUSIVE_CHILD_ACQUIRED') 'lock-not-released-after-handle-dispose';$cases++
$ready=Join-Path $demo 'child-claimed.ready'
$child=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Mode','crash','-Name','tagify','-LivePath',('"'+$live+'"'),'-ReadyPath',('"'+$ready+'"'),'-MarkerJournal',('"'+$journal+'"')) -PassThru -WindowStyle Hidden
try{
    $observed=$false
    foreach($i in 1..100){
        if(Test-Path -LiteralPath $ready -PathType Leaf){$observed=$true;break}
        if($child.HasExited){break}
        Start-Sleep -Milliseconds 100
    }
    Assert-EG $observed 'child-never-persisted-durable-active-claim'
    $cross=Open-CustomAppProductionExclusiveGateLockV010 -Name 'tagify' -LivePath $live
    Assert-EG (-not[bool]$cross.ok) 'another-process-acquired-lock-during-child-active-claim'
    $cases++
}finally{
    if(-not$child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue}
    $child.WaitForExit(10000)|Out-Null
}
Assert-EG (Test-Path -LiteralPath $path.record -PathType Leaf) 'process-death-lost-durable-active-transaction'
$record=Read-CustomAppProductionExclusiveGateRecordV010 -Paths $path
Assert-EG ([bool]$record.ok -and [string]$record.record.consumption_id -ceq ('a'*64)) 'durable-postcrash-record-not-recoverable';$cases++
$after=Open-CustomAppProductionExclusiveGateLockV010 -Name 'tagify' -LivePath $live
Assert-EG ([bool]$after.ok) 'crashed-process-os-file-lock-never-released'
try{
    Assert-EG (Test-Path -LiteralPath $after.paths.record -PathType Leaf) 'active-claim-should-still-block-next-update'
    $duplicate=Write-CustomAppProductionExclusiveGateActiveRecordV010 -Lock $after -ConsumptionId ('c'*64) -JournalStoreDirectory $journal -TransactionNonce ('d'*32)
    Assert-EG (-not[bool]$duplicate.ok -and [string]$duplicate.reason -match 'active-transaction-blocks-new-claim') 'crash-left-transaction-was-overwritten'
    $cases++
}finally{$after.lock_handle.Dispose()}
$terminal=Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 -Name 'tagify' -LivePath $live -ExpectedConsumptionId ('a'*64) -ExpectedTransactionId ('e'*64)
Assert-EG (-not[bool]$terminal.ok -and (Test-Path -LiteralPath $path.record -PathType Leaf)) 'missing-journal-allowed-unsafe-marker-retirement';$cases++
$bytes=[IO.File]::ReadAllBytes($path.record)
try{
    [IO.File]::WriteAllText($path.record,'{}',([Text.UTF8Encoding]::new($false)))
    $bad=Read-CustomAppProductionExclusiveGateRecordV010 $path
    Assert-EG (-not[bool]$bad.ok) 'corrupt-active-record-accepted'
    $cases++
}finally{[IO.File]::WriteAllBytes($path.record,$bytes)}
$valid=Read-CustomAppProductionExclusiveGateRecordV010 $path
Assert-EG ([bool]$valid.ok) 'unchanged-active-record-not-recovered-after-tamper-test';$cases++
# A retired consumption ID stays blocked even with NO active marker. Use an
# entirely separate isolated app rather than deleting the crash-active record.
$replayLive=Join-Path $demo 'retired-replay-app';[IO.Directory]::CreateDirectory($replayLive)|Out-Null
$replayPaths=Get-CustomAppProductionExclusiveGatePathsV010 -Name 'playlist-maker' -LivePath $replayLive
$oldCid='f'*64
$archivePath=Get-CustomAppProductionExclusiveGateRetiredPathV010 -Paths $replayPaths -ConsumptionId $oldCid
[IO.File]::WriteAllText($archivePath,'invalid-archive-must-fail-closed',([Text.UTF8Encoding]::new($false)))
$badArchive=Test-CustomAppProductionExclusiveGateRetiredReceiptV010 -Path $archivePath -Paths $replayPaths -ConsumptionId $oldCid
Assert-EG (-not[bool]$badArchive.ok) 'tampered-retired-consumption-archive-accepted';$cases++
$replayLock=Open-CustomAppProductionExclusiveGateLockV010 -Name 'playlist-maker' -LivePath $replayLive
Assert-EG ([bool]$replayLock.ok) 'separate-app-history-test-lock-denied'
try{
    $reuse=Write-CustomAppProductionExclusiveGateActiveRecordV010 -Lock $replayLock -ConsumptionId $oldCid -JournalStoreDirectory $journal -TransactionNonce ('b'*32)
    Assert-EG (-not[bool]$reuse.ok -and [string]$reuse.reason -match 'consumption-already-retired') 'retired-consumption-ID-replay-was-accepted'
    Assert-EG (-not(Test-Path -LiteralPath $replayPaths.record)) 'retired-ID-replay-created-active-claim'
    $cases++
}finally{$replayLock.lock_handle.Dispose()}
Assert-EG ($cases -eq 20) ('gate-case-count-drift '+$cases)
Write-Host 'EXCLUSIVE_APP_CLOCK_AND_CRASH_GATE_MATRIX_PASS cases=20 current_utc=true stale_and_future_denied=true same_app_cross_process_lock=true same_live_alias_denied=true other_app_allowed=true crash_retains_blocking_marker=true corrupt_marker_fail_closed=true no_journal_no_retirement=true retired_consumption_replay_denied=true installed_spotify_untouched=true'
