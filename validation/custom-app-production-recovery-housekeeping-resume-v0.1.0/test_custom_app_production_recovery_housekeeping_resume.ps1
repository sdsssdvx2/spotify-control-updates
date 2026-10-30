$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay/load the exact validated recovery integration harness first.
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/test_custom_app_production_recovery_evidence_admission_integration.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-housekeeping-resume-contract.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-housekeeping-resume-store.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-housekeeping-resume-writer.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-housekeeping-resume-gate.ps1')

function Assert-HRTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-HRFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-HREq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-HR($Value){return (($Value|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}
function Assert-HRZeroAuthority($Value,[string]$Label){$x=if($Value.PSObject.Properties['decision']){$Value.decision}elseif($Value.PSObject.Properties['envelope']){$Value.envelope}else{$Value};foreach($f in @('resume_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized')){if($x.PSObject.Properties[$f]){Assert-HRFalse ([bool]$x.$f) "$Label authority escaped $f"}}}

function Set-HRLiveToAppliedV010 {
    param([Parameter(Mandatory=$true)]$Q)
    $live=[string]$Q.f.q.x.live;$stage=[string]$Q.f.prepared.stage_path
    $git=Join-Path $live '.git';$savedGit=Join-Path $Q.f.q.x.base ('hr-preserved-git-'+[Guid]::NewGuid().ToString('N'))
    if(Test-Path -LiteralPath $git){[void](Copy-IntegrationTreeV010 -Source $git -Destination $savedGit)}
    if(Test-Path -LiteralPath $live){[IO.Directory]::Delete($live,$true)}
    [void](Copy-IntegrationTreeV010 -Source $stage -Destination $live)
    if(Test-Path -LiteralPath $savedGit){[void](Copy-IntegrationTreeV010 -Source $savedGit -Destination (Join-Path $live '.git'));[IO.Directory]::Delete($savedGit,$true)}
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Q.f.prepared.name) -AppPath $live
    if(-not[bool]$runtime.safe -or -not[bool]$runtime.installable -or [string]$runtime.tree_sha256 -cne [string]$Q.f.prepared.stage_tree_sha256){throw 'housekeeping fixture failed to install staged runtime'}
    return $runtime
}

function Append-HRCleanupStartingV010 {
    param([Parameter(Mandatory=$true)]$Q)
    $cur=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store
    if(-not[bool]$cur.ok){throw ('housekeeping fixture journal read failed: '+[string]$cur.reason)}
    if([string]$cur.entry.phase -ceq 'cleanup-starting'){return $cur}
    if([string]$cur.entry.phase -cne 'apply-verified'){throw ('housekeeping fixture cannot advance phase '+[string]$cur.entry.phase)}
    $next=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'cleanup-starting' -Now ([DateTimeOffset]::UtcNow.AddSeconds(-1))
    if(-not[bool]$next.ok){throw ('housekeeping fixture cleanup-starting append failed: '+[string]$next.reason)}
    return $next
}

function New-HRFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$SourcePhase='apply-verified',[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('8'*32),[bool]$InitializeResume=$true,[bool]$AdvanceCleanup=$true)
    $q=New-IntegrationFixtureV010 -Label ('hr-'+$Label) -Phase $SourcePhase -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    [void](Set-HRLiveToAppliedV010 -Q $q)
    $init=$null
    if($InitializeResume){
        $init=Initialize-CustomAppProductionRecoveryHousekeepingResumeV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store -ExpectedTransactionId ([string]$q.f.identity.transaction_id) -LocalAppDataRoot $q.f.q.persistence.local -AppDataRoot $q.f.q.persistence.roaming -Now ([DateTimeOffset]::UtcNow
        )
        if(-not[bool]$init.ok){throw ('housekeeping resume initialization failed: '+[string]$init.reason)}
        Assert-HRZeroAuthority $init ('init-'+$Label)
    }
    $current=$(if($AdvanceCleanup){Append-HRCleanupStartingV010 -Q $q}else{Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store})
    return [pscustomobject]@{q=$q;init=$init;current=$current}
}

function Invoke-HRGateV010 {
    param([Parameter(Mandatory=$true)]$F,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    return Resolve-CustomAppProductionRecoveryHousekeepingResumeGateV010 -AllowedRoot $F.q.f.allowed -StoreDirectory $F.q.f.store -ExpectedTransactionId ([string]$F.q.f.identity.transaction_id) -LocalAppDataRoot $F.q.f.q.persistence.local -AppDataRoot $F.q.f.q.persistence.roaming -Now $At
}
function Remove-HRStageV010($F){$h=$F.init.envelope;return Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$h.stage_workspace_path) -ExpectedRoot ([string]$h.stage_workspace_root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'recovery-stage-workspace'}
function Remove-HRAppBackupV010($F){$h=$F.init.envelope;$container=[IO.Path]::GetDirectoryName([string]$h.app_backup_path);return Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path $container -ExpectedRoot ([string]$h.app_backup_root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'recovery-app-backup'}
function Remove-HRPersistenceBackupV010($F){$h=$F.init.envelope;return Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$h.persistence_backup_path) -ExpectedRoot ([string]$h.persistence_backup_root) -ExpectedNamePattern '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$' -Label 'recovery-persistence-backup'}

$count=0
$valid=New-HRFixtureV010 -Label 'valid' -Nonce ('1'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-HRGateV010 -F $valid -At $at;Assert-HRTrue ([bool]$r.ok) ('valid resume denied: '+[string]$r.reason);Assert-HRZeroAuthority $r 'valid';Assert-HREq $r.decision.stage_cleanup_status 'present-verified' 'valid stage';Assert-HREq $r.decision.app_backup_cleanup_status 'present-verified' 'valid app';Assert-HREq $r.decision.persistence_backup_cleanup_status 'present-verified' 'valid persistence';$dc=Test-CustomAppProductionRecoveryHousekeepingResumeDecisionV010 -Decision $r.decision -Now $at.AddSeconds(1);Assert-HRTrue ([bool]$dc.ok) ('valid decision invalid: '+[string]$dc.reason);$count++

Assert-HREq (Remove-HRStageV010 $valid) 'deleted-now' 'stage delete';$r=Invoke-HRGateV010 $valid;Assert-HRTrue ([bool]$r.ok) ('resume after stage delete denied: '+[string]$r.reason);Assert-HREq $r.decision.stage_cleanup_status 'already-absent' 'stage absent status';Assert-HREq $r.decision.app_backup_cleanup_status 'present-verified' 'app retained after stage delete';$count++
Assert-HREq (Remove-HRAppBackupV010 $valid) 'deleted-now' 'app delete';$r=Invoke-HRGateV010 $valid;Assert-HRTrue ([bool]$r.ok) ('resume after app delete denied: '+[string]$r.reason);Assert-HREq $r.decision.stage_cleanup_status 'already-absent' 'stage still absent';Assert-HREq $r.decision.app_backup_cleanup_status 'already-absent' 'app absent status';Assert-HREq $r.decision.persistence_backup_cleanup_status 'present-verified' 'persistence retained after app delete';$count++
Assert-HREq (Remove-HRPersistenceBackupV010 $valid) 'deleted-now' 'persistence delete';$r=Invoke-HRGateV010 $valid;Assert-HRTrue ([bool]$r.ok) ('resume after all deletes denied: '+[string]$r.reason);Assert-HREq $r.decision.stage_cleanup_status 'already-absent' 'stage absent final';Assert-HREq $r.decision.app_backup_cleanup_status 'already-absent' 'app absent final';Assert-HREq $r.decision.persistence_backup_cleanup_status 'already-absent' 'persistence absent final';$count++

$future=New-HRFixtureV010 -Label 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32);$r=Invoke-HRGateV010 $future;Assert-HRTrue ([bool]$r.ok) ('future app resume denied: '+[string]$r.reason);Assert-HREq $r.decision.name 'future-app' 'future app name';$count++

$phaseFirst=New-HRFixtureV010 -Label 'phase-first' -SourcePhase 'cleanup-starting' -Nonce ('3'*32) -AdvanceCleanup:$false;$r=Invoke-HRGateV010 $phaseFirst;Assert-HRTrue ([bool]$r.ok) ('cleanup-starting-before-first-delete resume denied: '+[string]$r.reason);Assert-HREq $phaseFirst.init.envelope.source_phase 'cleanup-starting' 'cleanup-starting source phase';$count++

$replay=New-HRFixtureV010 -Label 'replay' -Nonce ('4'*32) -AdvanceCleanup:$false;$again=Initialize-CustomAppProductionRecoveryHousekeepingResumeV010 -AllowedRoot $replay.q.f.allowed -StoreDirectory $replay.q.f.store -ExpectedTransactionId ([string]$replay.q.f.identity.transaction_id) -LocalAppDataRoot $replay.q.f.q.persistence.local -AppDataRoot $replay.q.f.q.persistence.roaming;Assert-HRFalse ([bool]$again.ok) 'resume envelope replay accepted';Assert-HRTrue ([string]$again.reason -like '*already-exists-replay-denied*') ('resume replay reason '+[string]$again.reason);$count++

$nonHouse=New-HRFixtureV010 -Label 'non-housekeeping' -SourcePhase 'prepared' -Nonce ('5'*32) -InitializeResume:$false -AdvanceCleanup:$false;$bad=Initialize-CustomAppProductionRecoveryHousekeepingResumeV010 -AllowedRoot $nonHouse.q.f.allowed -StoreDirectory $nonHouse.q.f.store -ExpectedTransactionId ([string]$nonHouse.q.f.identity.transaction_id) -LocalAppDataRoot $nonHouse.q.f.q.persistence.local -AppDataRoot $nonHouse.q.f.q.persistence.roaming;Assert-HRFalse ([bool]$bad.ok) 'non-housekeeping phase gained resume envelope';Assert-HREq $bad.reason 'housekeeping-resume-phase-not-housekeeping' 'non-housekeeping reason';$count++

$missing=New-HRFixtureV010 -Label 'missing-envelope' -Nonce ('6'*32) -InitializeResume:$false;[void](Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$missing.q.f.prepared.stage_workspace_path) -ExpectedRoot (Get-CustomAppStageWorkspaceRootV010) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'missing-envelope-stage');$r=Invoke-HRGateV010 $missing;Assert-HRFalse ([bool]$r.ok) 'partial cleanup without durable resume envelope accepted';Assert-HRTrue ([string]$r.reason -like 'housekeeping-resume-envelope-*') ('missing envelope reason '+[string]$r.reason);$count++

$liveDrift=New-HRFixtureV010 -Label 'live-drift' -Nonce ('7'*32);[IO.File]::AppendAllText((Join-Path $liveDrift.q.f.q.x.live 'index.js'),"// live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $liveDrift;Assert-HRFalse ([bool]$r.ok) 'live drift accepted';Assert-HRTrue ([string]$r.reason -like '*live-runtime-drift*') ('live drift reason '+[string]$r.reason);$count++

$gitDrift=New-HRFixtureV010 -Label 'git-drift' -Nonce ('8'*32);[IO.File]::AppendAllText((Join-Path $gitDrift.q.f.q.x.live '.git\config'),"# git drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $gitDrift;Assert-HRFalse ([bool]$r.ok) 'git drift accepted';Assert-HRTrue ([string]$r.reason -like '*git-tree-drift*') ('git drift reason '+[string]$r.reason);$count++

$persistDrift=New-HRFixtureV010 -Label 'persistence-drift' -Nonce ('9'*32);[IO.File]::AppendAllText((Join-Path $persistDrift.q.f.q.persistence.local 'Spotify\Browser\IndexedDB\000001.log'),"drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $persistDrift;Assert-HRFalse ([bool]$r.ok) 'protected persistence drift accepted';Assert-HRTrue ([string]$r.reason -like '*protected-persistence-drift*') ('persistence drift reason '+[string]$r.reason);$count++

$stageDrift=New-HRFixtureV010 -Label 'stage-drift' -Nonce ('a'*32);[IO.File]::AppendAllText((Join-Path $stageDrift.q.f.prepared.stage_path 'index.js'),"// stage drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $stageDrift;Assert-HRFalse ([bool]$r.ok) 'retained stage drift accepted';Assert-HRTrue ([string]$r.reason -like '*stage-tree-drift*') ('stage drift reason '+[string]$r.reason);$count++

$appDrift=New-HRFixtureV010 -Label 'app-drift' -Nonce ('b'*32);[IO.File]::AppendAllText((Join-Path $appDrift.q.f.prepared.app_backup_path 'index.js'),"// app backup drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $appDrift;Assert-HRFalse ([bool]$r.ok) 'app backup drift accepted';Assert-HRTrue ([string]$r.reason -like '*app-backup-invalid:*tree-drift*') ('app backup drift reason '+[string]$r.reason);$count++

$pbDrift=New-HRFixtureV010 -Label 'persistence-backup-drift' -Nonce ('c'*32);[IO.File]::AppendAllText((Join-Path $pbDrift.q.f.prepared.persistence_backup_path 'guard-manifest.json')," `n",[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $pbDrift;Assert-HRFalse ([bool]$r.ok) 'persistence backup drift accepted';Assert-HRTrue ([string]$r.reason -like '*persistence-backup-invalid:*') ('persistence backup drift reason '+[string]$r.reason);$count++

$envTamper=New-HRFixtureV010 -Label 'envelope-tamper' -Nonce ('d'*32);$paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $envTamper.q.f.allowed -StoreDirectory $envTamper.q.f.store;$o=[IO.File]::ReadAllText([string]$paths.file,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$o.name='other-app';$o.resume_fingerprint=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeEnvelopeMaterialV010 $o);[IO.File]::WriteAllText([string]$paths.file,($o|ConvertTo-Json -Depth 60 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $envTamper;Assert-HRFalse ([bool]$r.ok) 'rehash envelope identity tamper accepted';Assert-HRTrue ([string]$r.reason -like '*source-journal-anchor-mismatch*' -or [string]$r.reason -like '*envelope-evidence-mismatch*') ('envelope tamper reason '+[string]$r.reason);$count++

$anchorTamper=New-HRFixtureV010 -Label 'anchor-tamper' -Nonce ('e'*32);$paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $anchorTamper.q.f.allowed -StoreDirectory $anchorTamper.q.f.store;$o=[IO.File]::ReadAllText([string]$paths.file,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$o.source_journal_entry_sha256=('0'*64);$o.resume_fingerprint=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeEnvelopeMaterialV010 $o);[IO.File]::WriteAllText([string]$paths.file,($o|ConvertTo-Json -Depth 60 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $anchorTamper;Assert-HRFalse ([bool]$r.ok) 'rehash source journal anchor tamper accepted';Assert-HREq $r.reason 'housekeeping-resume-source-journal-anchor-missing' 'source journal anchor reason';$count++

$corrupt=New-HRFixtureV010 -Label 'corrupt' -Nonce ('f'*32);$paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $corrupt.q.f.allowed -StoreDirectory $corrupt.q.f.store;[IO.File]::WriteAllText([string]$paths.file,'{bad',[Text.UTF8Encoding]::new($false));$r=Invoke-HRGateV010 $corrupt;Assert-HRFalse ([bool]$r.ok) 'corrupt resume JSON accepted';Assert-HRTrue ([string]$r.reason -like 'housekeeping-resume-envelope-read-failed:*JSON-invalid*') ('corrupt reason '+[string]$r.reason);$count++

$lockCase=New-HRFixtureV010 -Label 'lock' -Nonce ('1f'*16);$paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $lockCase.q.f.allowed -StoreDirectory $lockCase.q.f.store;$held=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{$r=Invoke-HRGateV010 $lockCase}finally{$held.Dispose()};Assert-HRFalse ([bool]$r.ok) 'resume lock contention accepted';Assert-HRTrue ([string]$r.reason -like '*housekeeping-resume-lock-busy*') ('lock reason '+[string]$r.reason);$count++

$decisionTamper=New-HRFixtureV010 -Label 'decision-tamper' -Nonce ('2f'*16);$at=[DateTimeOffset]::UtcNow;$good=Invoke-HRGateV010 -F $decisionTamper -At $at;Assert-HRTrue ([bool]$good.ok) 'decision tamper setup failed';$bad=Copy-HR $good.decision;$bad.cleanup_authorized=$true;$bad.decision_fingerprint=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeDecisionMaterialV010 $bad);$dc=Test-CustomAppProductionRecoveryHousekeepingResumeDecisionV010 -Decision $bad -Now $at.AddSeconds(1);Assert-HRFalse ([bool]$dc.ok) 'authority-tampered resume decision accepted';Assert-HRTrue ([string]$dc.reason -like '*authority-escaped-cleanup_authorized*') ('decision authority reason '+[string]$dc.reason);$count++

$expiry=New-HRFixtureV010 -Label 'expiry' -Nonce ('3f'*16);$at=[DateTimeOffset]::UtcNow;$good=Invoke-HRGateV010 -F $expiry -At $at;Assert-HRTrue ([bool]$good.ok) 'expiry setup failed';$dc=Test-CustomAppProductionRecoveryHousekeepingResumeDecisionV010 -Decision $good.decision -Now $at.AddSeconds(11);Assert-HRFalse ([bool]$dc.ok) 'expired resume decision accepted';Assert-HREq $dc.reason 'housekeeping-resume-decision-expired' 'expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_HOUSEKEEPING_RESUME_MATRIX_PASS total=$count"
