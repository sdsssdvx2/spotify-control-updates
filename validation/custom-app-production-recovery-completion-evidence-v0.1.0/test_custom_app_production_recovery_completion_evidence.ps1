$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-completion-evidence.ps1')

function Assert-CETrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-CEFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-CEEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-CE($x){return(($x|ConvertTo-Json -Depth 70)|ConvertFrom-Json)}
function Assert-CEZeroAuthority($R,[string]$Label){$x=if($R.PSObject.Properties['envelope']){$R.envelope}else{$R};foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-CEFalse ([bool]$x.$f) "$Label authority escaped $f"}}

function New-CECompletedFixtureV010 {
    param([string]$Label,[string]$Phase='live-moved-to-old',[string]$State='live-moved-before-candidate',[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('8'*32))
    $q=New-RXFixtureV010 -Label ('completion-'+$Label) -Phase $Phase -State $State -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $r=Invoke-RXFixtureV010 $q
    if(-not[bool]$r.ok){throw ('completion fixture executor failed: '+[string]$r.reason)}
    $rc=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $r.result
    if(-not[bool]$rc.ok){throw ('completion fixture executor result invalid: '+[string]$rc.reason)}
    return [pscustomobject]@{q=$q;executor=$r.result}
}
function Invoke-CEWriteV010 {
    param($F,[AllowNull()]$ExecutorResult=$null,[AllowNull()][string]$Tx=$null,[AllowNull()][string]$Exe=$null,[AllowNull()][string]$Sha=$null,[AllowNull()][string]$ExeRoot=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if($null-eq$ExecutorResult){$ExecutorResult=$F.executor}
    if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$F.q.f.f.identity.transaction_id}
    if([string]::IsNullOrWhiteSpace($Exe)){$Exe=$fakeExe}
    if([string]::IsNullOrWhiteSpace($Sha)){$Sha=$fakeSha}
    if([string]::IsNullOrWhiteSpace($ExeRoot)){$ExeRoot=[string]$F.q.f.f.allowed}
    return Write-CustomAppProductionRecoveryCompletionEvidenceV010 -AllowedRoot $F.q.f.f.allowed -StoreDirectory $F.q.f.f.store -ExpectedTransactionId $Tx -ExecutorResult $ExecutorResult -LocalAppDataRoot $F.q.f.f.q.persistence.local -AppDataRoot $F.q.f.f.q.persistence.roaming -SpicetifyAllowedRoot $ExeRoot -SpicetifyPath $Exe -ExpectedSpicetifySha256 $Sha -Now $At
}
function Invoke-CEReadV010 {
    param($F,[AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$F.q.f.f.identity.transaction_id}
    return Read-CustomAppProductionRecoveryCompletionEvidenceV010 -AllowedRoot $F.q.f.f.allowed -StoreDirectory $F.q.f.f.store -ExpectedTransactionId $Tx -Now $At
}
function Restore-CEOldStateV010($F){
    $p=$F.q.f.f.prepared
    $r=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$F.q.f.f.q.x.live) -AppBackupPath ([string]$p.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$p.app_backup_tree_sha256) -PersistenceBackupPath ([string]$p.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$p.persistence_fingerprint) -LocalAppDataRoot $F.q.f.f.q.persistence.local -AppDataRoot $F.q.f.f.q.persistence.roaming
    Assert-CETrue ([bool]$r.ok) ('fixture old-state restore failed: '+[string]$r.reason)
}
function Assert-CERetainedV010($F,[string]$Label){
    Assert-CETrue (Test-Path -LiteralPath ([string]$F.q.f.f.prepared.stage_workspace_path) -PathType Container) "$Label stage workspace missing"
    Assert-CETrue (Test-Path -LiteralPath ([string]$F.q.f.f.prepared.app_backup_path) -PathType Container) "$Label app backup missing"
    Assert-CETrue (Test-Path -LiteralPath ([string]$F.q.f.f.prepared.persistence_backup_path) -PathType Container) "$Label persistence backup missing"
}
function Assert-CEWriteDeniedNoFileV010($F,$R,[string]$Pattern,[string]$Label){
    Assert-CEFalse ([bool]$R.ok) "$Label accepted"
    Assert-CETrue ([string]$R.reason -like $Pattern) "$Label reason drifted: $([string]$R.reason)"
    Assert-CEZeroAuthority $R $Label
    $paths=Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 -AllowedRoot $F.q.f.f.allowed -StoreDirectory $F.q.f.f.store
    Assert-CEFalse (Test-Path -LiteralPath ([string]$paths.file)) "$Label unexpectedly persisted evidence"
    Assert-CERetainedV010 $F $Label
}

$count=0
$main=New-CECompletedFixtureV010 -Label 'main' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('1'*32)
Assert-CEEq (Get-RXPhaseV010 $main.q) 'rollback-complete' 'main executor journal phase'
Assert-CERetainedV010 $main 'main-prewrite'
$mainTxn=[string]$main.q.f.f.txn
Assert-CETrue (Test-Path -LiteralPath $mainTxn -PathType Container) 'main transaction root unexpectedly absent'
Assert-CETrue (Test-Path -LiteralPath (Join-Path $mainTxn 'old-live') -PathType Container) 'main old-live missing'
Assert-CETrue (Test-Path -LiteralPath (Join-Path $mainTxn 'candidate') -PathType Container) 'main candidate missing'

$r=Invoke-CEWriteV010 -F $main -Sha ('0'*64);Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-spicetify-pin-input-mismatch' 'wrong-spicetify-hash';$count++
$missingExe=Join-Path ([string]$main.q.f.f.allowed) ('missing-'+[Guid]::NewGuid().ToString('N')+'\spicetify.exe');$r=Invoke-CEWriteV010 -F $main -Exe $missingExe;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-spicetify-recheck-denied:*' 'missing-spicetify';$count++
$outsideRoot=Join-Path ([string]$main.q.f.f.q.x.base) ('exe-bound-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($outsideRoot)|Out-Null;$r=Invoke-CEWriteV010 -F $main -ExeRoot $outsideRoot;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-spicetify-recheck-denied:*' 'spicetify-root-escape';$count++

$bad=Copy-CE $main.executor;$bad.restore_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $bad);$r=Invoke-CEWriteV010 -F $main -ExecutorResult $bad;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-executor-result-invalid:*authority-escaped-restore_authorized*' 'executor-authority-tamper';$count++
$bad=Copy-CE $main.executor;$bad.result_fingerprint=('0'*64);$r=Invoke-CEWriteV010 -F $main -ExecutorResult $bad;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-executor-result-invalid:*fingerprint-mismatch*' 'executor-fingerprint-tamper';$count++
$r=Invoke-CEWriteV010 -F $main -Tx ('9'*64);Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-executor-result-not-retirement-pending' 'wrong-transaction';$count++

$held=Open-CustomAppProductionRecoveryCompletionEvidenceLockV010 -AllowedRoot $main.q.f.f.allowed -StoreDirectory $main.q.f.f.store
try{$r=Invoke-CEWriteV010 $main}finally{$held.Dispose()}
Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-lock-busy' 'lock-contention';$count++

$liveFile=Join-Path ([string]$main.q.f.f.q.x.live) 'index.js';[IO.File]::AppendAllText($liveFile,"// completion-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-current-live-not-exact-old-state' 'live-drift';Restore-CEOldStateV010 $main;$count++
$persistFile=Join-Path ([string]$main.q.f.f.q.persistence.roaming) 'spicetify\config-xpui.ini';[IO.File]::AppendAllText($persistFile,"# completion-persistence-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-current-persistence-not-exact-old-state' 'persistence-drift';Restore-CEOldStateV010 $main;$count++

$stageFile=Join-Path ([string]$main.q.f.f.prepared.stage_path) 'index.js';$stageBytes=[IO.File]::ReadAllBytes($stageFile);[IO.File]::AppendAllText($stageFile,"// completion-stage-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-stage-invalid:*' 'stage-drift';[IO.File]::WriteAllBytes($stageFile,$stageBytes);$count++
$appFile=Join-Path ([string]$main.q.f.f.prepared.app_backup_path) 'index.js';$appBytes=[IO.File]::ReadAllBytes($appFile);[IO.File]::AppendAllText($appFile,"// completion-app-backup-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-backups-invalid:*' 'app-backup-drift';[IO.File]::WriteAllBytes($appFile,$appBytes);$count++
$persistSurface=Join-Path ([string]$main.q.f.f.prepared.persistence_backup_path) 'surfaces\spicetify-config';$psBytes=[IO.File]::ReadAllBytes($persistSurface);[IO.File]::AppendAllText($persistSurface,"# completion-persistence-backup-surface-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-backups-invalid:*' 'persistence-backup-drift';[IO.File]::WriteAllBytes($persistSurface,$psBytes);$count++

$extra=Join-Path $mainTxn 'unexpected';[IO.Directory]::CreateDirectory($extra)|Out-Null;$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-transaction-invalid:*contents-invalid*' 'transaction-extra';[IO.Directory]::Delete($extra,$true);$count++
$oldFile=Join-Path $mainTxn 'old-live\index.js';$oldBytes=[IO.File]::ReadAllBytes($oldFile);[IO.File]::AppendAllText($oldFile,"// completion-old-live-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-transaction-invalid:*old-live-tree-mismatch*' 'old-live-drift';[IO.File]::WriteAllBytes($oldFile,$oldBytes);$count++
$candidateFile=Join-Path $mainTxn 'candidate\index.js';$candidateBytes=[IO.File]::ReadAllBytes($candidateFile);[IO.File]::AppendAllText($candidateFile,"// completion-candidate-drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CEWriteV010 $main;Assert-CEWriteDeniedNoFileV010 $main $r 'recovery-completion-evidence-transaction-invalid:*candidate-tree-mismatch*' 'candidate-drift';[IO.File]::WriteAllBytes($candidateFile,$candidateBytes);$count++

$writeAt=[DateTimeOffset]::UtcNow;$good=Invoke-CEWriteV010 -F $main -At $writeAt;Assert-CETrue ([bool]$good.ok) ('valid completion write denied: '+[string]$good.reason);Assert-CETrue ([bool]$good.persisted) 'valid completion not persisted';Assert-CETrue ([bool]$good.read_after_write_verified) 'valid completion readback not verified';Assert-CEZeroAuthority $good 'valid-write';Assert-CEEq $good.envelope.transaction_status 'present-verified' 'main transaction status';Assert-CEEq $good.envelope.transaction_old_status 'present-verified' 'main old status';Assert-CEEq $good.envelope.transaction_candidate_status 'present-verified' 'main candidate status';Assert-CETrue ([bool]$good.envelope.executor_result_embedded) 'executor result not embedded';Assert-CETrue ([bool]$good.envelope.retirement_admission_required) 'retirement admission flag missing';Assert-CERetainedV010 $main 'valid-write';Assert-CETrue (Test-Path -LiteralPath $mainTxn -PathType Container) 'completion write deleted transaction root';$count++
$read=Invoke-CEReadV010 -F $main -At $writeAt.AddSeconds(1);Assert-CETrue ([bool]$read.ok) ('valid completion read denied: '+[string]$read.reason);Assert-CETrue ([bool]$read.reloaded_from_persistent_store) 'completion not reloaded from durable store';Assert-CEEq $read.completion_fingerprint $good.completion_fingerprint 'completion read fingerprint';Assert-CEZeroAuthority $read 'valid-read';$count++

$probe=Join-Path $PSScriptRoot 'probe_custom_app_production_recovery_completion_evidence.ps1';$probeRaw=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -AllowedRoot $main.q.f.f.allowed -StoreDirectory $main.q.f.f.store -ExpectedTransactionId $main.q.f.f.identity.transaction_id);if($LASTEXITCODE){throw 'completion separate-process reload probe failed'};$probeObj=($probeRaw|Select-Object -Last 1)|ConvertFrom-Json;Assert-CETrue ([bool]$probeObj.ok) 'completion separate-process probe not ok';Assert-CETrue ([bool]$probeObj.reloaded_from_persistent_store) 'completion separate-process probe not durable';Assert-CEEq $probeObj.completion_fingerprint $good.completion_fingerprint 'completion separate-process fingerprint';foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-CEFalse ([bool]$probeObj.$f) "completion probe authority escaped $f"};$count++

$paths=Get-CustomAppProductionRecoveryCompletionEvidencePathsV010 -AllowedRoot $main.q.f.f.allowed -StoreDirectory $main.q.f.f.store;$original=[IO.File]::ReadAllBytes([string]$paths.file);$originalHash=(Get-FileHash -LiteralPath ([string]$paths.file) -Algorithm SHA256).Hash.ToLowerInvariant();$replay=Invoke-CEWriteV010 $main;Assert-CEFalse ([bool]$replay.ok) 'completion replay write accepted';Assert-CEEq $replay.reason 'recovery-completion-evidence-already-exists-replay-denied' 'completion replay reason';Assert-CEEq (Get-FileHash -LiteralPath ([string]$paths.file) -Algorithm SHA256).Hash.ToLowerInvariant() $originalHash 'completion replay modified original';$count++

$obj=[IO.File]::ReadAllText([string]$paths.file,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$obj.name='tampered-name';$obj.completion_fingerprint=Get-CustomAppProductionRecoveryCompletionEvidenceSha256V010 (Get-CustomAppProductionRecoveryCompletionEvidenceMaterialV010 -Envelope $obj);[IO.File]::WriteAllText([string]$paths.file,($obj|ConvertTo-Json -Depth 70 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-CEReadV010 $main;Assert-CEFalse ([bool]$r.ok) 'top-level tamper+rehash accepted';Assert-CETrue ([string]$r.reason -like 'recovery-completion-evidence-executor-continuity-mismatch-name') ('top-level tamper reason drifted: '+[string]$r.reason);[IO.File]::WriteAllBytes([string]$paths.file,$original);$count++
$obj=[IO.File]::ReadAllText([string]$paths.file,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$obj.evidence_written_at=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('o');$obj.completion_fingerprint=Get-CustomAppProductionRecoveryCompletionEvidenceSha256V010 (Get-CustomAppProductionRecoveryCompletionEvidenceMaterialV010 -Envelope $obj);[IO.File]::WriteAllText([string]$paths.file,($obj|ConvertTo-Json -Depth 70 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-CEReadV010 $main;Assert-CEFalse ([bool]$r.ok) 'future evidence timestamp accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-time-invalid' 'future timestamp reason';[IO.File]::WriteAllBytes([string]$paths.file,$original);$count++
[IO.File]::WriteAllText([string]$paths.file,'{bad',[Text.UTF8Encoding]::new($false));$r=Invoke-CEReadV010 $main;Assert-CEFalse ([bool]$r.ok) 'corrupt completion JSON accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-JSON-invalid' 'corrupt JSON reason';[IO.File]::WriteAllBytes([string]$paths.file,$original);$count++
[IO.File]::WriteAllText([string]$paths.file,('x'*($CustomAppProductionRecoveryCompletionEvidenceMaxBytes+1)),[Text.UTF8Encoding]::new($false));$r=Invoke-CEReadV010 $main;Assert-CEFalse ([bool]$r.ok) 'oversize completion evidence accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-file-exceeds-4-MiB' 'oversize reason';[IO.File]::WriteAllBytes([string]$paths.file,$original);$count++
$held=Open-CustomAppProductionRecoveryCompletionEvidenceLockV010 -AllowedRoot $main.q.f.f.allowed -StoreDirectory $main.q.f.f.store;try{$r=Invoke-CEReadV010 $main}finally{$held.Dispose()};Assert-CEFalse ([bool]$r.ok) 'completion read lock contention accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-lock-busy' 'read lock reason';$count++
$r=Invoke-CEReadV010 -F $main -Tx ('8'*64);Assert-CEFalse ([bool]$r.ok) 'wrong transaction completion read accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-transaction-mismatch' 'wrong read tx reason';$count++

$journalPath=Join-Path ([string]$main.q.f.f.store) 'current.json';$journalBytes=[IO.File]::ReadAllBytes($journalPath);[IO.File]::WriteAllText($journalPath,'{bad',[Text.UTF8Encoding]::new($false));$r=Invoke-CEReadV010 $main;Assert-CEFalse ([bool]$r.ok) 'corrupt journal accepted by completion evidence read';Assert-CETrue ([string]$r.reason -like 'recovery-completion-evidence-journal-*') ('journal corruption reason drifted: '+[string]$r.reason);[IO.File]::WriteAllBytes($journalPath,$journalBytes);$count++

$oldOnly=New-CECompletedFixtureV010 -Label 'old-only' -Phase 'live-moved-to-old' -State 'live-moved-after-candidate' -Nonce ('2'*32);$w=Invoke-CEWriteV010 $oldOnly;Assert-CETrue ([bool]$w.ok) ('old-only completion denied: '+[string]$w.reason);Assert-CEEq $w.envelope.transaction_status 'present-verified' 'old-only txn status';Assert-CEEq $w.envelope.transaction_old_status 'present-verified' 'old-only old status';Assert-CEEq $w.envelope.transaction_candidate_status 'absent' 'old-only candidate status';Assert-CERetainedV010 $oldOnly 'old-only';$count++
$absent=New-CECompletedFixtureV010 -Label 'absent' -Phase 'transaction-finalized' -State 'finalized' -Nonce ('3'*32);$w=Invoke-CEWriteV010 $absent;Assert-CETrue ([bool]$w.ok) ('absent-transaction completion denied: '+[string]$w.reason);Assert-CEEq $w.envelope.transaction_status 'already-absent' 'absent txn status';Assert-CEEq $w.envelope.transaction_old_status 'absent' 'absent old status';Assert-CEEq $w.envelope.transaction_candidate_status 'absent' 'absent candidate status';Assert-CERetainedV010 $absent 'absent';$count++
$future=New-CECompletedFixtureV010 -Label 'future' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('4'*32);$w=Invoke-CEWriteV010 $future;Assert-CETrue ([bool]$w.ok) ('future app completion denied: '+[string]$w.reason);Assert-CEEq $w.envelope.name 'future-app' 'future completion identity';Assert-CERetainedV010 $future 'future';$count++

$missing=New-CECompletedFixtureV010 -Label 'missing-read' -Phase 'transaction-finalized' -State 'finalized' -Nonce ('5'*32);$r=Invoke-CEReadV010 $missing;Assert-CEFalse ([bool]$r.ok) 'missing completion evidence accepted';Assert-CEEq $r.reason 'recovery-completion-evidence-file-missing' 'missing completion reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_COMPLETION_EVIDENCE_MATRIX_PASS total=$count"