param(
    [ValidateSet('all','prepare','resume')][string]$Mode='all',
    [AllowNull()][string]$StatePath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if(-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    $env:TEMP=$env:RUNNER_TEMP
    $env:TMP=$env:RUNNER_TEMP
}

function Assert-RRITrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RRIFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RRIEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Assert-RRIZeroAuthority($Value,[string]$Label){
    $x=if($Value.PSObject.Properties['result']){$Value.result}else{$Value}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if($x.PSObject.Properties[$f]){Assert-RRIFalse ([bool]$x.$f) "$Label authority escaped $f"}
    }
}

if($Mode -ceq 'all'){
    if([string]::IsNullOrWhiteSpace($StatePath)){
        if([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'restart-restore-runner-temp-missing'}
        $StatePath=Join-Path $env:RUNNER_TEMP ('restart-restore-state-'+[Guid]::NewGuid().ToString('N')+'.json')
    }
    if(Test-Path -LiteralPath $StatePath){Remove-Item -LiteralPath $StatePath -Force}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode prepare -StatePath $StatePath
    if($LASTEXITCODE -ne 0){throw "restart-restore prepare child failed exit=$LASTEXITCODE"}
    Assert-RRITrue (Test-Path -LiteralPath $StatePath -PathType Leaf) 'restart-restore prepare child did not persist state'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode resume -StatePath $StatePath
    if($LASTEXITCODE -ne 0){throw "restart-restore resume child failed exit=$LASTEXITCODE"}
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Write-Output 'CUSTOM_APP_PRODUCTION_RESTART_RESTORE_PROCESS_BOUNDARY_PASS'
    exit 0
}

if([string]::IsNullOrWhiteSpace($StatePath)){throw 'restart-restore-state-path-required'}
$StatePath=[IO.Path]::GetFullPath($StatePath)

if($Mode -ceq 'prepare'){
    # Reuse the exact #190 test harness. It replays its 5-case evidence-bound atomic matrix,
    # then leaves the fixture helpers loaded for one additional real crash state.
    . (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

    $fixture=New-AtomicFixtureV010 'restart-restore-actual-crash' -Nonce '51515151515151515151515151515151'
    $label='restart-restore-actual-crash'
    $crash=Invoke-EBFixtureV010 -Fixture $fixture -Nonce 'abababababababababababababababab' -Label $label -Fault 'after-live-move-before-journal'
    Assert-RRIFalse ([bool]$crash.ok) 'restart-restore prepare crash unexpectedly succeeded'
    Assert-RRITrue ([bool]$crash.live_move_started) 'restart-restore prepare did not reach first rename'
    Assert-RRITrue ([bool]$crash.recovery_evidence_persisted) 'restart-restore prepare did not persist recovery evidence'

    $inspectionArgs=Get-EBInspectionArgsV010 $fixture $label
    $inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @inspectionArgs
    Assert-RRITrue ([bool]$inspection.ok) ('restart-restore prepare inspection denied: '+[string]$inspection.reason)
    Assert-RRIEq $inspection.receipt.state 'first-rename-complete-unjournaled' 'restart-restore prepare exact crash state'

    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @inspectionArgs -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1))
    Assert-RRITrue ([bool]$repair.ok) ('restart-restore prepare normalization denied: '+[string]$repair.reason)
    Assert-RRIEq $repair.phase 'live-moved-to-old' 'restart-restore prepare normalized phase'

    $journal=Get-EBJournalV010 $fixture $label
    Assert-RRITrue ([bool]$journal.ok) ('restart-restore prepare journal unreadable: '+[string]$journal.reason)
    Assert-RRIEq $journal.entry.phase 'live-moved-to-old' 'restart-restore prepare durable phase'
    Assert-RRIEq $journal.transaction_id $repair.transaction_id 'restart-restore prepare transaction id continuity'

    $evidence=Get-EBEvidenceV010 $fixture $label ([string]$repair.transaction_id)
    Assert-RRITrue ([bool]$evidence.ok) ('restart-restore prepare evidence unreadable: '+[string]$evidence.reason)

    $p=$fixture.prepared.result
    $transactionRoot=Get-EBTransactionRootV010 $crash
    Assert-RRITrue (-not [string]::IsNullOrWhiteSpace($transactionRoot)) 'restart-restore prepare transaction root missing'
    Assert-RRITrue (Test-Path -LiteralPath $transactionRoot -PathType Container) 'restart-restore prepare transaction root not retained'
    Assert-RRIFalse (Test-Path -LiteralPath ([string]$fixture.q.x.live)) 'restart-restore prepare live should be absent after first rename'
    Assert-RRITrue (Test-Path -LiteralPath (Join-Path $transactionRoot 'old-live') -PathType Container) 'restart-restore prepare old-live missing'
    Assert-RRITrue (Test-Path -LiteralPath (Join-Path $transactionRoot 'candidate') -PathType Container) 'restart-restore prepare candidate missing'

    $state=[ordered]@{
        schema=1
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        allowed_root=(Get-EBTrustRootV010)
        store_directory=(Get-EBStoreV010 $fixture $label)
        transaction_id=[string]$repair.transaction_id
        live_path=[string]$fixture.q.x.live
        transaction_root=[string]$transactionRoot
        local_app_data_root=[string]$fixture.q.persistence.local
        app_data_root=[string]$fixture.q.persistence.roaming
        stage_workspace_path=[string]$p.stage_workspace_path
        app_backup_path=[string]$p.app_backup_path
        app_backup_tree_sha256=[string]$p.app_backup_tree_sha256
        app_backup_file_count=[int]$p.app_backup_file_count
        app_backup_total_bytes=[int64]$p.app_backup_total_bytes
        persistence_backup_path=[string]$p.persistence_backup_path
        persistence_fingerprint=[string]$p.persistence_fingerprint
        recovery_evidence_fingerprint=[string]$evidence.evidence_fingerprint
        expected_phase='live-moved-to-old'
    }
    [IO.File]::WriteAllText($StatePath,($state|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Assert-RRITrue (Test-Path -LiteralPath $StatePath -PathType Leaf) 'restart-restore prepare failed to persist handoff state'
    Write-Output ('CUSTOM_APP_PRODUCTION_RESTART_RESTORE_PREPARE_PASS tx='+[string]$state.transaction_id)
    exit 0
}

if($Mode -ceq 'resume'){
    if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){throw 'restart-restore-resume-state-missing'}
    $state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Assert-RRITrue ([int]$state.schema -eq 1) 'restart-restore resume state schema invalid'

    # Load and execute the exact #157 matrix in this fresh PowerShell process. This supplies the
    # pinned fake spicetify executable and proves the unchanged restore executor before the bridge case.
    . (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')

    Assert-RRITrue (Test-Path -LiteralPath ([string]$fakeExe) -PathType Leaf) 'restart-restore resume fake spicetify missing'
    Assert-RRITrue ([string]$fakeSha -match '^[0-9a-f]{64}$') 'restart-restore resume fake spicetify pin invalid'
    Assert-RRITrue (Test-Path -LiteralPath ([string]$state.transaction_root) -PathType Container) 'restart-restore resume transaction root missing across process boundary'
    Assert-RRIFalse (Test-Path -LiteralPath ([string]$state.live_path)) 'restart-restore resume live unexpectedly exists before recovery'

    $evidenceBefore=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id)
    Assert-RRITrue ([bool]$evidenceBefore.ok) ('restart-restore resume evidence missing across process boundary: '+[string]$evidenceBefore.reason)
    Assert-RRIEq $evidenceBefore.evidence_fingerprint $state.recovery_evidence_fingerprint 'restart-restore resume evidence fingerprint continuity'

    $now=[DateTimeOffset]::UtcNow
    $admission=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id) -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot ([string]$state.allowed_root) -SpicetifyPath ([string]$fakeExe) -ExpectedSpicetifySha256 ([string]$fakeSha) -Now $now
    Assert-RRITrue ([bool]$admission.ok) ('restart-restore resume admission denied: '+[string]$admission.reason)
    Assert-RRIEq $admission.receipt.phase 'live-moved-to-old' 'restart-restore resume admitted phase'
    Assert-RRITrue ([bool]$admission.receipt.requires_exact_restore) 'restart-restore resume exact restore not required'
    Assert-RRITrue ([bool]$admission.receipt.requires_recovery_apply) 'restart-restore resume recovery apply not required'
    Assert-RRIZeroAuthority $admission.receipt 'restart-restore admission'

    $control=Join-Path ([string]$state.allowed_root) ('restart-restore-control-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($control)|Out-Null
    $countPath=Join-Path $control 'count.txt'
    $appliedPath=Join-Path $control 'applied.txt'
    $env:SC_RX_COUNT=$countPath
    $env:SC_RX_LIVE=Join-Path ([string]$state.live_path) 'index.js'
    $env:SC_RX_APPLIED=$appliedPath
    $env:SC_RX_MODE='success'
    try{
        $result=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id) -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot ([string]$state.allowed_root) -SpicetifyPath ([string]$fakeExe) -ExpectedSpicetifySha256 ([string]$fakeSha) -Now $now -TimeoutSeconds 20
        Assert-RRITrue ([bool]$result.ok) ('restart-restore executor denied: '+[string]$result.reason)
        Assert-RRIEq $result.result.started_phase 'live-moved-to-old' 'restart-restore executor started phase'
        Assert-RRITrue ([bool]$result.result.rollback_required_was_appended) 'restart-restore executor did not append rollback-required barrier'
        Assert-RRITrue ([bool]$result.result.restore_performed) 'restart-restore executor did not restore'
        Assert-RRITrue ([bool]$result.result.recovery_apply_executed) 'restart-restore executor did not run recovery apply'
        Assert-RRITrue ([bool]$result.result.rollback_complete_persisted) 'restart-restore executor did not persist rollback-complete'
        Assert-RRIZeroAuthority $result.result 'restart-restore executor result'

        Assert-RRITrue (Test-Path -LiteralPath $countPath -PathType Leaf) 'restart-restore fake apply count missing'
        Assert-RRIEq ([IO.File]::ReadAllText($countPath).Trim()) '1' 'restart-restore recovery apply count'
        Assert-RRITrue (Test-Path -LiteralPath $appliedPath -PathType Leaf) 'restart-restore fake applied snapshot missing'

        $journalAfter=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory)
        Assert-RRITrue ([bool]$journalAfter.ok) ('restart-restore completed journal unreadable: '+[string]$journalAfter.reason)
        Assert-RRIEq $journalAfter.entry.phase 'rollback-complete' 'restart-restore completed journal phase'
        Assert-RRIEq $journalAfter.transaction_id $state.transaction_id 'restart-restore completed transaction id'

        $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$state.live_path)
        Assert-RRIEq $app.tree_sha256 $state.app_backup_tree_sha256 'restart-restore old app tree'
        Assert-RRITrue ([int]$app.file_count -eq [int]$state.app_backup_file_count) 'restart-restore old app file count'
        Assert-RRITrue ([int64]$app.total_bytes -eq [int64]$state.app_backup_total_bytes) 'restart-restore old app total bytes'
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root)
        Assert-RRIEq $persist.fingerprint $state.persistence_fingerprint 'restart-restore protected persistence fingerprint'

        $liveIndex=Join-Path ([string]$state.live_path) 'index.js'
        Assert-RRITrue (Test-Path -LiteralPath $liveIndex -PathType Leaf) 'restart-restore restored live index missing'
        Assert-RRIEq ([IO.File]::ReadAllText($appliedPath)) ([IO.File]::ReadAllText($liveIndex)) 'restart-restore recovery apply did not see restored old live state'

        foreach($p in @([string]$state.transaction_root,[string]$state.stage_workspace_path,[string]$state.app_backup_path,[string]$state.persistence_backup_path)){
            Assert-RRITrue (Test-Path -LiteralPath $p -PathType Container) ("restart-restore recovery artifact was retired early: $p")
        }
        $evidenceAfter=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id)
        Assert-RRITrue ([bool]$evidenceAfter.ok) ('restart-restore evidence unreadable after rollback-complete: '+[string]$evidenceAfter.reason)
        Assert-RRIEq $evidenceAfter.evidence_fingerprint $state.recovery_evidence_fingerprint 'restart-restore evidence fingerprint after completion'

        $selfCheck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $result.result
        Assert-RRITrue ([bool]$selfCheck.ok) ('restart-restore result self-check denied: '+[string]$selfCheck.reason)

        $beforeReplay=[int]([IO.File]::ReadAllText($countPath).Trim())
        $replay=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$state.allowed_root) -StoreDirectory ([string]$state.store_directory) -ExpectedTransactionId ([string]$state.transaction_id) -LocalAppDataRoot ([string]$state.local_app_data_root) -AppDataRoot ([string]$state.app_data_root) -SpicetifyAllowedRoot ([string]$state.allowed_root) -SpicetifyPath ([string]$fakeExe) -ExpectedSpicetifySha256 ([string]$fakeSha) -Now $now.AddSeconds(1) -TimeoutSeconds 20
        Assert-RRIFalse ([bool]$replay.ok) 'restart-restore rollback-complete replay was accepted'
        Assert-RRITrue ([string]$replay.reason -like 'recovery-restore-executor-initial-admission-denied:*phase-not-auto-restorable') ('restart-restore replay denial reason drift: '+[string]$replay.reason)
        Assert-RRIEq ([IO.File]::ReadAllText($countPath).Trim()) ([string]$beforeReplay) 'restart-restore replay launched a second recovery apply'
    } finally {
        foreach($n in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
    }

    Write-Output ('CUSTOM_APP_PRODUCTION_RESTART_RESTORE_RESUME_PASS tx='+[string]$state.transaction_id)
    exit 0
}

throw ('restart-restore-unknown-mode:'+ $Mode)
