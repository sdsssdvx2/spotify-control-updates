$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-crash-recovery-journal.ps1')

function Assert-TrueV010 { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-FalseV010 { param([bool]$Condition,[string]$Message) if($Condition){throw $Message} }
function Assert-EqualV010 { param($Actual,$Expected,[string]$Message) if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"} }
function Copy-DeepCrashV010 { param($Object) return ($Object|ConvertTo-Json -Depth 50|ConvertFrom-Json) }
function Repeat-CharCrashV010 { param([string]$C,[int]$N) return (($C * $N) -join '') }

$script:Roots=New-Object System.Collections.Generic.List[string]
$script:CaseCount=0
$baseNow=[DateTimeOffset]::UtcNow.AddMinutes(-2)

function New-CrashJournalFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify')
    $root=Join-Path $env:TEMP ('spotify-control-crash-journal-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root)|Out-Null;$script:Roots.Add($root)
    $live=Join-Path $root 'live-app';$txn=Join-Path $root '.spotify-control-txn-0123456789abcdef0123456789abcdef';$stage=Join-Path $root 'stage-workspace';$app=Join-Path $root 'app-backup';$persist=Join-Path $root 'persistence-backup'
    foreach($p in @($live,$txn,$stage,$app,$persist)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $store=Join-Path $root 'journal-store'
    $cid=Get-CustomAppProductionCrashJournalSha256V010 ('cid-'+$Label);$stageFp=Get-CustomAppProductionCrashJournalSha256V010 ('stage-'+$Label);$prepFp=Get-CustomAppProductionCrashJournalSha256V010 ('prep-'+$Label)
    $identity=New-CustomAppProductionCrashJournalIdentityV010 -Name $Name -ConsumptionId $cid -SourceIdentity $Source -RemoteCommitSha (Repeat-CharCrashV010 'a' 40) -StageResultFingerprint $stageFp -PreparationFingerprint $prepFp -AllowedRoot $root -LivePath $live -TransactionRoot $txn -StageWorkspacePath $stage -AppBackupPath $app -PersistenceBackupPath $persist
    $at=$baseNow.AddSeconds($script:Roots.Count)
    $init=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $root -StoreDirectory $store -Identity $identity -Now $at
    Assert-TrueV010 ([bool]$init.ok) ("$Label init failed: "+[string]$init.reason)
    return [pscustomobject]@{label=$Label;root=$root;store=$store;live=$live;txn=$txn;stage=$stage;app=$app;persist=$persist;identity=$identity;current=$init;at=$at;final_fp=(Get-CustomAppProductionCrashJournalSha256V010 ('final-'+$Label));apply_fp=(Get-CustomAppProductionCrashJournalSha256V010 ('apply-'+$Label));cleanup_fp=(Get-CustomAppProductionCrashJournalSha256V010 ('cleanup-'+$Label))}
}
function Add-CrashJournalPhaseV010 {
    param($Fixture,[string]$Phase,[AllowNull()][string]$Final=$null,[AllowNull()][string]$Apply=$null,[AllowNull()][string]$Cleanup=$null,[AllowNull()][DateTimeOffset]$At=$null,[string]$FailurePoint='none')
    if($null -eq $At){$At=$Fixture.at.AddSeconds([int64]$Fixture.current.revision+1)}
    $r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $Fixture.root -StoreDirectory $Fixture.store -ExpectedRevision ([int64]$Fixture.current.revision) -ExpectedEntrySha256 ([string]$Fixture.current.entry.entry_sha256) -Phase $Phase -FinalizationFingerprint $Final -ApplyResultFingerprint $Apply -CleanupResultFingerprint $Cleanup -Now $At -FailurePoint $FailurePoint
    if([bool]$r.ok){$Fixture.current=$r}
    return $r
}
function Read-ClassCrashV010 { param($Fixture) $r=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Fixture.root -StoreDirectory $Fixture.store;Assert-TrueV010 ([bool]$r.ok) ($Fixture.label+' reload failed');return Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $r -ExpectedTransactionId $Fixture.identity.transaction_id }
function Advance-ToCandidateCrashV010 { param($F) foreach($p in @('atomic-mutation-starting','live-moved-to-old','candidate-live')){$r=Add-CrashJournalPhaseV010 $F $p;Assert-TrueV010 ([bool]$r.ok) ($F.label+' '+$p+' failed')} }
function Advance-ToFinalizedCrashV010 { param($F) Advance-ToCandidateCrashV010 $F;$r=Add-CrashJournalPhaseV010 $F 'transaction-finalized' -Final $F.final_fp;Assert-TrueV010 ([bool]$r.ok) ($F.label+' finalization phase failed') }
function Advance-ToApplyReturnedCrashV010 { param($F) Advance-ToFinalizedCrashV010 $F;foreach($p in @('apply-starting','apply-returned-success-pending-verification')){$r=Add-CrashJournalPhaseV010 $F $p;Assert-TrueV010 ([bool]$r.ok) ($F.label+' '+$p+' failed')} }
function Advance-ToApplyVerifiedCrashV010 { param($F) Advance-ToApplyReturnedCrashV010 $F;$r=Add-CrashJournalPhaseV010 $F 'apply-verified' -Apply $F.apply_fp;Assert-TrueV010 ([bool]$r.ok) ($F.label+' apply verified failed') }

# Full phase chain + conservative restart classification at every crash window.
$f=New-CrashJournalFixtureV010 'full-chain'
$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'safe-abandon-or-restart-only-after-fresh-admission' 'prepared classification';Assert-TrueV010 ([bool]$c.no_action) 'prepared should not authorize recovery mutation';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-TrueV010 ([bool]$r.ok) 'atomic start append failed';$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'filesystem-recovery-inspection-required' 'atomic-start classification';Assert-TrueV010 ([bool]$c.requires_recovery_executor) 'atomic-start should require recovery executor';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'live-moved-to-old';Assert-TrueV010 ([bool]$r.ok) 'live moved append failed';$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'exact-app-and-persistence-recovery-required' 'live-moved classification';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'candidate-live';Assert-TrueV010 ([bool]$r.ok) 'candidate-live append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.requires_recovery_executor) 'candidate-live should require recovery';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'transaction-finalized' -Final $f.final_fp;Assert-TrueV010 ([bool]$r.ok) 'finalized append failed';$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'exact-app-and-persistence-recovery-required' 'finalized classification';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'apply-starting';Assert-TrueV010 ([bool]$r.ok) 'apply-starting append failed';$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'rollback-and-recovery-apply-required' 'apply-starting classification';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'apply-returned-success-pending-verification';Assert-TrueV010 ([bool]$r.ok) 'apply-returned append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.requires_recovery_executor) 'unverified apply should require recovery';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'apply-verified' -Apply $f.apply_fp;Assert-TrueV010 ([bool]$r.ok) 'apply-verified append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.housekeeping_only) 'verified apply should only allow future housekeeping classification';Assert-FalseV010 ([bool]$c.requires_recovery_executor) 'verified apply should not demand rollback';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'cleanup-starting';Assert-TrueV010 ([bool]$r.ok) 'cleanup-starting append failed';$c=Read-ClassCrashV010 $f;Assert-EqualV010 $c.classification 'fresh-revalidate-then-idempotent-housekeeping-only' 'cleanup classification';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'committed-clean' -Cleanup $f.cleanup_fp;Assert-TrueV010 ([bool]$r.ok) 'committed-clean append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.no_action) 'committed clean should be no action';Assert-EqualV010 $c.classification 'no-action-new-permit-required-for-future-update' 'committed classification';$script:CaseCount++

# Rollback branch is explicit and terminal after verified recovery.
$f=New-CrashJournalFixtureV010 'rollback-chain';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-TrueV010 ([bool]$r.ok) 'rollback fixture atomic start failed';$r=Add-CrashJournalPhaseV010 $f 'rollback-required';Assert-TrueV010 ([bool]$r.ok) 'rollback-required append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.requires_recovery_executor) 'rollback-required classification weak';$script:CaseCount++
$r=Add-CrashJournalPhaseV010 $f 'rollback-complete';Assert-TrueV010 ([bool]$r.ok) 'rollback-complete append failed';$c=Read-ClassCrashV010 $f;Assert-TrueV010 ([bool]$c.no_action) 'rollback complete should be no action';$script:CaseCount++

# Illegal/duplicate transitions remain fail-closed.
$f=New-CrashJournalFixtureV010 'illegal-skip';$r=Add-CrashJournalPhaseV010 $f 'candidate-live';Assert-FalseV010 ([bool]$r.ok) 'prepared -> candidate-live accepted';Assert-EqualV010 $r.reason 'journal-illegal-phase-transition' 'illegal skip reason';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'duplicate-phase';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-TrueV010 ([bool]$r.ok) 'duplicate fixture first append failed';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-FalseV010 ([bool]$r.ok) 'duplicate phase accepted';$script:CaseCount++

# CAS protects revision and head hash independently.
$f=New-CrashJournalFixtureV010 'cas';$r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedRevision 99 -ExpectedEntrySha256 $f.current.entry.entry_sha256 -Phase 'atomic-mutation-starting' -Now $f.at.AddSeconds(1);Assert-FalseV010 ([bool]$r.ok) 'stale revision accepted';Assert-EqualV010 $r.reason 'journal-revision-conflict' 'stale revision reason';$script:CaseCount++
$r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedRevision 0 -ExpectedEntrySha256 (Repeat-CharCrashV010 'f' 64) -Phase 'atomic-mutation-starting' -Now $f.at.AddSeconds(1);Assert-FalseV010 ([bool]$r.ok) 'stale head hash accepted';Assert-EqualV010 $r.reason 'journal-head-sha256-conflict' 'stale head reason';$script:CaseCount++

# Future and reversed timestamps are rejected before durable mutation.
$f=New-CrashJournalFixtureV010 'future-time';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting' -At ([DateTimeOffset]::UtcNow.AddHours(1));Assert-FalseV010 ([bool]$r.ok) 'future timestamp accepted';Assert-EqualV010 $r.reason 'journal-future-timestamp-denied' 'future timestamp reason';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'reverse-time';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting' -At $f.at.AddSeconds(-1);Assert-FalseV010 ([bool]$r.ok) 'time reversal accepted';Assert-EqualV010 $r.reason 'journal-time-reversal-denied' 'time reversal reason';$script:CaseCount++

# Duplicate store initialization / transaction reuse is denied.
$f=New-CrashJournalFixtureV010 'duplicate-init';$r=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store -Identity $f.identity -Now $f.at.AddSeconds(2);Assert-FalseV010 ([bool]$r.ok) 'duplicate journal initialization accepted';Assert-EqualV010 $r.reason 'journal-store-already-initialized' 'duplicate init reason';$script:CaseCount++

# Path escape cannot enter identity or store contract.
$escapeRoot=Join-Path $env:TEMP ('spotify-control-crash-escape-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($escapeRoot)|Out-Null;$script:Roots.Add($escapeRoot);$outside=Join-Path ([IO.Directory]::GetParent($escapeRoot).FullName) ('outside-'+[Guid]::NewGuid().ToString('N'));$threw=$false
try{[void](New-CustomAppProductionCrashJournalIdentityV010 -Name 'tagify' -ConsumptionId (Repeat-CharCrashV010 '1' 64) -SourceIdentity 'alexk218/tagify' -RemoteCommitSha (Repeat-CharCrashV010 '2' 40) -StageResultFingerprint (Repeat-CharCrashV010 '3' 64) -PreparationFingerprint (Repeat-CharCrashV010 '4' 64) -AllowedRoot $escapeRoot -LivePath $outside -TransactionRoot (Join-Path $escapeRoot 'txn') -StageWorkspacePath (Join-Path $escapeRoot 'stage') -AppBackupPath (Join-Path $escapeRoot 'app') -PersistenceBackupPath (Join-Path $escapeRoot 'persist'))}catch{$threw=$true};Assert-TrueV010 $threw 'identity path escape accepted';$script:CaseCount++

# Exclusive lock blocks competing writers.
$f=New-CrashJournalFixtureV010 'lock';$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $f.root -StoreDirectory $f.store;$held=Open-CustomAppProductionCrashJournalLockV010 $paths
try{$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-FalseV010 ([bool]$r.ok) 'lock contention writer accepted';Assert-EqualV010 $r.reason 'crash-journal-lock-busy' 'lock contention reason'}finally{$held.Dispose()};$script:CaseCount++

# Current/history tamper and rollback are detected.
$f=New-CrashJournalFixtureV010 'current-tamper';[IO.File]::WriteAllText((Join-Path $f.store 'current.json'),'{not-json',(New-Object Text.UTF8Encoding($false)));$threw=$false;try{[void](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store)}catch{$threw=$true};Assert-TrueV010 $threw 'current JSON tamper accepted';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'history-tamper';$h=@(Get-ChildItem (Join-Path $f.store 'history') -File -Filter '*.json')[0];$raw=[IO.File]::ReadAllText($h.FullName);[IO.File]::WriteAllText($h.FullName,$raw.Replace('"phase":"prepared"','"phase":"candidate-live"'),(New-Object Text.UTF8Encoding($false)));$threw=$false;try{[void](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store)}catch{$threw=$true};Assert-TrueV010 $threw 'history tamper accepted';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'current-rollback';$rev0=@(Get-ChildItem (Join-Path $f.store 'history') -File -Filter '*.json'|Sort-Object Name)[0];$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting';Assert-TrueV010 ([bool]$r.ok) 'rollback fixture append failed';[IO.File]::Copy($rev0.FullName,(Join-Path $f.store 'current.json'),$true);$threw=$false;try{[void](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store)}catch{$threw=$true};Assert-TrueV010 $threw 'current rollback accepted';$script:CaseCount++

# Crash exactly after immutable history but before current pointer is fail-closed, never silently downgraded.
$f=New-CrashJournalFixtureV010 'history-current-crash';$r=Add-CrashJournalPhaseV010 $f 'atomic-mutation-starting' -FailurePoint 'after-history-before-current';Assert-FalseV010 ([bool]$r.ok) 'simulated history/current crash reported success';Assert-EqualV010 $r.reason 'simulated-crash-after-history-before-current' 'simulated crash reason';$threw=$false;try{[void](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store)}catch{$threw=$true};Assert-TrueV010 $threw 'history/current crash mismatch silently accepted';$script:CaseCount++

# Phase-specific evidence is mandatory before later milestones.
$f=New-CrashJournalFixtureV010 'missing-final';Advance-ToCandidateCrashV010 $f;$r=Add-CrashJournalPhaseV010 $f 'transaction-finalized';Assert-FalseV010 ([bool]$r.ok) 'finalized phase without finalization fingerprint accepted';Assert-TrueV010 ([string]$r.reason -like 'next-entry-invalid:entry-finalization-evidence-required') 'missing final evidence reason drifted';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'missing-apply';Advance-ToApplyReturnedCrashV010 $f;$r=Add-CrashJournalPhaseV010 $f 'apply-verified';Assert-FalseV010 ([bool]$r.ok) 'apply-verified without apply receipt accepted';Assert-TrueV010 ([string]$r.reason -like 'next-entry-invalid:entry-apply-evidence-required') 'missing apply evidence reason drifted';$script:CaseCount++
$f=New-CrashJournalFixtureV010 'missing-cleanup';Advance-ToApplyVerifiedCrashV010 $f;$r=Add-CrashJournalPhaseV010 $f 'cleanup-starting';Assert-TrueV010 ([bool]$r.ok) 'cleanup start failed';$r=Add-CrashJournalPhaseV010 $f 'committed-clean';Assert-FalseV010 ([bool]$r.ok) 'committed-clean without cleanup receipt accepted';Assert-TrueV010 ([string]$r.reason -like 'next-entry-invalid:entry-cleanup-evidence-required') 'missing cleanup evidence reason drifted';$script:CaseCount++

# Recomputed hash cannot turn the journal into authority.
$f=New-CrashJournalFixtureV010 'authority-tamper';$bad=Copy-DeepCrashV010 $f.current.entry;$bad.journal_is_authority=$true;$bad.entry_sha256=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalEntryMaterialV010 $bad);$check=Test-CustomAppProductionCrashJournalEntryV010 -Entry $bad -AllowedRoot $f.root;Assert-FalseV010 ([bool]$check.ok) 'authority-tampered entry accepted after recomputing hash';Assert-EqualV010 $check.reason 'entry-authority-or-ordering-contract-invalid' 'authority tamper reason';$script:CaseCount++

# History identity cannot switch source/transaction even with internally valid recomputed identity/hash.
$f=New-CrashJournalFixtureV010 'identity-drift';$current=$f.current.entry;$alt=Copy-DeepCrashV010 $f.identity;$alt.source_identity='owner/other';$alt.transaction_id=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalIdentityMaterialV010 $alt);$fake=New-CustomAppProductionCrashJournalEntryV010 -Identity $alt -Revision 1 -PreviousEntrySha256 $current.entry_sha256 -Phase 'atomic-mutation-starting' -RecordedAt $f.at.AddSeconds(1);$fakeJson=$fake|ConvertTo-Json -Depth 30 -Compress;$historyPath=Join-Path (Join-Path $f.store 'history') ('{0:D20}-{1}.json' -f 1,[string]$fake.entry_sha256);[IO.File]::WriteAllText($historyPath,$fakeJson,(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText((Join-Path $f.store 'current.json'),$fakeJson,(New-Object Text.UTF8Encoding($false)));$threw=$false;try{[void](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store)}catch{$threw=$true};Assert-TrueV010 $threw 'transaction/source identity drift accepted in history';$script:CaseCount++

# Terminal committed journal cannot be replay-extended.
$f=New-CrashJournalFixtureV010 'terminal';Advance-ToApplyVerifiedCrashV010 $f;$r=Add-CrashJournalPhaseV010 $f 'cleanup-starting';Assert-TrueV010 ([bool]$r.ok) 'terminal cleanup start failed';$r=Add-CrashJournalPhaseV010 $f 'committed-clean' -Cleanup $f.cleanup_fp;Assert-TrueV010 ([bool]$r.ok) 'terminal commit failed';$r=Add-CrashJournalPhaseV010 $f 'rollback-required';Assert-FalseV010 ([bool]$r.ok) 'terminal committed journal extended';$script:CaseCount++

# Classification refuses the wrong transaction identity.
$r=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $f.root -StoreDirectory $f.store;$c=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $r -ExpectedTransactionId (Repeat-CharCrashV010 '0' 64);Assert-FalseV010 ([bool]$c.ok) 'wrong transaction id classification accepted';Assert-EqualV010 $c.classification 'fail-closed' 'wrong tx classification';$script:CaseCount++

# Separate PowerShell process must reload the durable committed journal and still observe zero authority.
$out=Join-Path $f.root 'restart-probe.json';$core=Join-Path $PSScriptRoot 'custom-app-production-crash-recovery-journal.ps1';$probe=Join-Path $PSScriptRoot 'probe_custom_app_production_crash_recovery_journal.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -CorePath $core -AllowedRoot $f.root -StoreDirectory $f.store -ExpectedTransactionId $f.identity.transaction_id -OutPath $out
if($LASTEXITCODE){throw 'separate-process restart probe failed'};$proof=Get-Content -LiteralPath $out -Raw|ConvertFrom-Json;Assert-TrueV010 ([bool]$proof.reloaded_from_persistent_store) 'restart probe did not reload persistent store';Assert-EqualV010 $proof.phase 'committed-clean' 'restart probe phase';Assert-EqualV010 $proof.classification 'no-action-new-permit-required-for-future-update' 'restart probe classification';Assert-FalseV010 ([bool]$proof.journal_is_authority) 'restart probe authority escaped';$script:CaseCount++

# Journal phase state itself never authorizes staging/apply/production mutation.
foreach($root in $script:Roots){if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
Write-Host ("CUSTOM_APP_PRODUCTION_CRASH_RECOVERY_JOURNAL_MATRIX_PASS total={0}" -f $script:CaseCount)
