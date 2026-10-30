$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay the exact validated recovery evidence/admission integration chain first.
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/test_custom_app_production_recovery_evidence_admission_integration.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')
. (Join-Path $root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-bounded-recovery-executor.ps1')

function Assert-RXTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-RXFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RXEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RX($x){return(($x|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}
function RXNonce([string]$c){return (($c*32).Substring(0,32))}

$script:RecoveryApplyMode='success'
$script:RecoveryApplyCalls=0
function Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath,[int]$TimeoutSeconds=180)
    $script:RecoveryApplyCalls++
    $s=[DateTimeOffset]::UtcNow
    if($script:RecoveryApplyMode-ceq'failure'){return [pscustomobject]@{ok=$false;reason='fixture-spicetify-apply-failure';exit_code=7;timed_out=$false;started_at=$s;finished_at=$s.AddMilliseconds(1)}}
    return [pscustomobject]@{ok=$true;reason='spicetify-apply-exit-zero';exit_code=0;timed_out=$false;started_at=$s;finished_at=$s.AddMilliseconds(1)}
}

$script:RecoveryHookMode='none'
$script:RecoveryHookFixture=$null
function Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:RecoveryHookMode-ceq'rollback-cas-race' -and $Checkpoint-ceq'before-rollback-required-journal'){
        $q=$script:RecoveryHookFixture;$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store
        $r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store -ExpectedRevision ([int64]$j.revision) -ExpectedEntrySha256 ([string]$j.entry.entry_sha256) -Phase 'rollback-required' -Now ([DateTimeOffset]::UtcNow)
        if(-not[bool]$r.ok){throw ('fixture rollback race append failed: '+[string]$r.reason)}
        $script:RecoveryHookMode='none';return
    }
    if($script:RecoveryHookMode-ceq'restore-backup-disappears' -and $Checkpoint-ceq'before-restore'){
        $q=$script:RecoveryHookFixture
        if(Test-Path -LiteralPath ([string]$q.f.prepared.app_backup_path)){[IO.Directory]::Delete([string]$q.f.prepared.app_backup_path,$true)}
        $script:RecoveryHookMode='none';return
    }
    if($script:RecoveryHookMode-ceq'commit-cas-race' -and $Checkpoint-ceq'before-committed-clean-journal'){
        $q=$script:RecoveryHookFixture;$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store
        $r=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store -ExpectedRevision ([int64]$j.revision) -ExpectedEntrySha256 ([string]$j.entry.entry_sha256) -Phase 'committed-clean' -CleanupResultFingerprint ([string]$Context.cleanup_fingerprint) -Now ([DateTimeOffset]::UtcNow)
        if(-not[bool]$r.ok){throw ('fixture committed-clean race append failed: '+[string]$r.reason)}
        $script:RecoveryHookMode='none';return
    }
}

function Set-RXLiveToStagedV010 {
    param([Parameter(Mandatory=$true)]$Q)
    $live=[string]$Q.f.q.x.live;$stage=[string]$Q.f.prepared.stage_path;$gitSource=Join-Path ([string]$Q.f.prepared.app_backup_path) '.git'
    if(Test-Path -LiteralPath $live){[IO.Directory]::Delete($live,$true)}
    [void](Copy-IntegrationTreeV010 -Source $stage -Destination $live)
    if(Test-Path -LiteralPath $gitSource -PathType Container){[void](Copy-IntegrationTreeV010 -Source $gitSource -Destination (Join-Path $live '.git'))}
    $b=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Q.f.prepared.name) -AppPath $live
    Assert-RXEq $b.tree_sha256 $Q.f.prepared.stage_tree_sha256 'fixture live did not become staged runtime'
    return $b
}
function Invoke-RXFixtureV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()][string]$ExpectedSha=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if([string]::IsNullOrWhiteSpace($ExpectedSha)){$ExpectedSha=[string]$Q.exeSha}
    return Invoke-CustomAppProductionBoundedRecoveryExecutorV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming -SpicetifyAllowedRoot $Q.f.allowed -SpicetifyPath $Q.exe -ExpectedSpicetifySha256 $ExpectedSha -TimeoutSeconds 30 -Now $At
}
function Assert-RXSuccessV010 {
    param($R,[string]$Label,[string]$Status)
    Assert-RXTrue ([bool]$R.ok) "$Label failed: $([string]$R.reason)"
    Assert-RXEq $R.result.status $Status "$Label status"
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RXFalse ([bool]$R.result.$f) "$Label authority escaped $f"}
    $c=Test-CustomAppProductionBoundedRecoveryExecutorResultV010 -Result $R.result;Assert-RXTrue ([bool]$c.ok) "$Label result invalid: $([string]$c.reason)"
}
function Assert-RXJournalPhaseV010($Q,[string]$Phase,[string]$Label){$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store;Assert-RXTrue ([bool]$j.ok) "$Label journal invalid";Assert-RXEq $j.entry.phase $Phase "$Label journal phase";return $j}

$count=0

# 1. Candidate-live exact rollback: old app + protected persistence restored and recovery apply runs once.
$q=New-IntegrationFixtureV010 -Label 'rx-candidate' -Phase 'candidate-live' -Nonce (RXNonce '1');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$script:RecoveryApplyCalls=0
$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r 'candidate rollback' 'rollback-complete';Assert-RXEq $script:RecoveryApplyCalls 1 'candidate recovery apply count';[void](Assert-RXJournalPhaseV010 $q 'rollback-complete' 'candidate rollback');$full=Get-CustomAppUpdateTreeSnapshotV010 -Root $q.f.q.x.live;Assert-RXEq $full.tree_sha256 $q.f.prepared.app_backup_tree_sha256 'candidate old app not restored';$p=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $q.f.q.persistence.local -AppDataRoot $q.f.q.persistence.roaming;Assert-RXEq $p.fingerprint $q.f.prepared.persistence_fingerprint 'candidate persistence not restored';Assert-RXTrue (Test-Path -LiteralPath $q.f.prepared.stage_workspace_path) 'rollback removed retained stage';Assert-RXTrue (Test-Path -LiteralPath $q.f.prepared.app_backup_path) 'rollback removed app backup';$count++

# 2. Apply-starting follows the same bounded rollback path.
$q=New-IntegrationFixtureV010 -Label 'rx-apply-starting' -Phase 'apply-starting' -Nonce (RXNonce '2');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$script:RecoveryApplyCalls=0;$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r 'apply-starting rollback' 'rollback-complete';Assert-RXEq $script:RecoveryApplyCalls 1 'apply-starting recovery apply count';$count++

# 3. Already rollback-required is restartable without another phase transition before restore.
$q=New-IntegrationFixtureV010 -Label 'rx-already-rollback' -Phase 'rollback-required' -Nonce (RXNonce '3');[void](Set-RXLiveToStagedV010 $q);$before=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store;$script:RecoveryApplyMode='success';$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r 'already rollback-required' 'rollback-complete';Assert-RXEq $r.result.journal_start_revision $before.revision 'rollback restart start revision';$count++

# 4. Generic future app identity is not literal-name routed.
$q=New-IntegrationFixtureV010 -Label 'rx-future' -Phase 'candidate-live' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (RXNonce '4');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r 'future app rollback' 'rollback-complete';Assert-RXEq $r.result.name 'future-app' 'future app result identity';$count++

# 5-7. No-action/manual classes never gain execution authority and leave journal unchanged.
foreach($spec in @(@('prepared','5'),@('committed-clean','6'),@('rollback-complete','7'),@('atomic-mutation-starting','8'))){$q=New-IntegrationFixtureV010 -Label ('rx-refuse-'+$spec[0]) -Phase $spec[0] -Nonce (RXNonce $spec[1]);$before=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store;$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) "$($spec[0]) unexpectedly executed";$after=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store;Assert-RXEq $after.revision $before.revision "$($spec[0]) journal mutated";Assert-RXEq $after.entry.phase $before.entry.phase "$($spec[0]) phase mutated";$count++}

# 9. Wrong executable hash is refused before rollback-required is persisted.
$q=New-IntegrationFixtureV010 -Label 'rx-bad-exe' -Phase 'candidate-live' -Nonce (RXNonce '9');[void](Set-RXLiveToStagedV010 $q);$before=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store;$r=Invoke-RXFixtureV010 -Q $q -ExpectedSha ('9'*64);Assert-RXFalse ([bool]$r.ok) 'wrong executable hash accepted';$after=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store;Assert-RXEq $after.revision $before.revision 'wrong executable mutated journal';Assert-RXEq $after.entry.phase 'candidate-live' 'wrong executable phase changed';$count++

# 10. Durable recovery evidence tamper is fail-closed.
$q=New-IntegrationFixtureV010 -Label 'rx-evidence-tamper' -Phase 'candidate-live' -Nonce (RXNonce 'a');$er=Read-REFixtureV010 $q.f;$o=[IO.File]::ReadAllText([string]$er.path,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$o.persistence_fingerprint=('0'*64);$o.evidence_fingerprint=Get-CustomAppProductionRecoveryEvidenceSha256V010 (Get-CustomAppProductionRecoveryEvidenceMaterialV010 $o);[IO.File]::WriteAllText([string]$er.path,($o|ConvertTo-Json -Depth 60 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'tampered recovery evidence executed';[void](Assert-RXJournalPhaseV010 $q 'candidate-live' 'evidence tamper');$count++

# 11. App rollback backup drift is refused before journal mutation.
$q=New-IntegrationFixtureV010 -Label 'rx-app-drift' -Phase 'candidate-live' -Nonce (RXNonce 'b');[IO.File]::AppendAllText((Join-Path $q.f.prepared.app_backup_path 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'drifted app backup executed';[void](Assert-RXJournalPhaseV010 $q 'candidate-live' 'app backup drift');$count++

# 12. CAS race before rollback-required is fail-closed.
$q=New-IntegrationFixtureV010 -Label 'rx-rollback-race' -Phase 'candidate-live' -Nonce (RXNonce 'c');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryHookFixture=$q;$script:RecoveryHookMode='rollback-cas-race';$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'rollback CAS race returned success';[void](Assert-RXJournalPhaseV010 $q 'rollback-required' 'rollback CAS race');$script:RecoveryHookMode='none';$count++

# 13. A backup disappearing after rollback-required leaves durable recovery-needed state.
$q=New-IntegrationFixtureV010 -Label 'rx-restore-fault' -Phase 'candidate-live' -Nonce (RXNonce 'd');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryHookFixture=$q;$script:RecoveryHookMode='restore-backup-disappears';$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'restore fault returned success';[void](Assert-RXJournalPhaseV010 $q 'rollback-required' 'restore fault');$script:RecoveryHookMode='none';$count++

# 14. Recovery apply failure leaves rollback-required for safe retry.
$q=New-IntegrationFixtureV010 -Label 'rx-apply-fault' -Phase 'candidate-live' -Nonce (RXNonce 'e');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='failure';$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'recovery apply failure returned success';[void](Assert-RXJournalPhaseV010 $q 'rollback-required' 'apply fault');$script:RecoveryApplyMode='success';$count++

# 15. apply-verified performs strict pre-cleanup validation, journals cleanup-starting first, then bounded cleanup.
$q=New-IntegrationFixtureV010 -Label 'rx-housekeeping' -Phase 'apply-verified' -Nonce (RXNonce 'f');[void](Set-RXLiveToStagedV010 $q);$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r 'apply-verified housekeeping' 'housekeeping-committed-clean';[void](Assert-RXJournalPhaseV010 $q 'committed-clean' 'apply-verified housekeeping');Assert-RXFalse (Test-Path -LiteralPath $q.f.prepared.stage_workspace_path) 'stage workspace survived housekeeping';Assert-RXFalse (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$q.f.prepared.app_backup_path)) 'app backup container survived housekeeping';Assert-RXFalse (Test-Path -LiteralPath $q.f.prepared.persistence_backup_path) 'persistence backup survived housekeeping';$count++

# 16-18. cleanup-starting restart is idempotent when each retired artifact was already fully removed.
foreach($spec in @(@('stage','1'),@('app','2'),@('persistence','3'))){$q=New-IntegrationFixtureV010 -Label ('rx-resume-'+$spec[0]) -Phase 'cleanup-starting' -Nonce (RXNonce $spec[1]);[void](Set-RXLiveToStagedV010 $q);switch($spec[0]){'stage'{[IO.Directory]::Delete([string]$q.f.prepared.stage_workspace_path,$true)}'app'{[IO.Directory]::Delete([IO.Path]::GetDirectoryName([string]$q.f.prepared.app_backup_path),$true)}'persistence'{[IO.Directory]::Delete([string]$q.f.prepared.persistence_backup_path,$true)}};$r=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $r ("resume $($spec[0])") 'housekeeping-committed-clean';[void](Assert-RXJournalPhaseV010 $q 'committed-clean' ("resume $($spec[0])"));$count++}

# 19. cleanup-starting with an unexpected stage child is never treated as owned cleanup state.
$q=New-IntegrationFixtureV010 -Label 'rx-stage-unexpected' -Phase 'cleanup-starting' -Nonce (RXNonce '4');[void](Set-RXLiveToStagedV010 $q);[IO.File]::WriteAllText((Join-Path $q.f.prepared.stage_workspace_path 'unexpected-user-file.txt'),'do-not-delete',[Text.UTF8Encoding]::new($false));$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'unexpected stage child deleted';[void](Assert-RXJournalPhaseV010 $q 'cleanup-starting' 'unexpected stage child');Assert-RXTrue (Test-Path -LiteralPath (Join-Path $q.f.prepared.stage_workspace_path 'unexpected-user-file.txt')) 'unexpected stage child was removed';$count++

# 20. cleanup resume refuses live runtime drift.
$q=New-IntegrationFixtureV010 -Label 'rx-live-drift' -Phase 'cleanup-starting' -Nonce (RXNonce '5');[void](Set-RXLiveToStagedV010 $q);[IO.Directory]::Delete([string]$q.f.prepared.stage_workspace_path,$true);[IO.File]::AppendAllText((Join-Path $q.f.q.x.live 'index.js'),"// live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'cleanup resume accepted live drift';[void](Assert-RXJournalPhaseV010 $q 'cleanup-starting' 'cleanup live drift');Assert-RXTrue (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$q.f.prepared.app_backup_path)) 'cleanup live drift removed backup';$count++

# 21. cleanup resume refuses protected persistence drift.
$q=New-IntegrationFixtureV010 -Label 'rx-persistence-drift' -Phase 'cleanup-starting' -Nonce (RXNonce '6');[void](Set-RXLiveToStagedV010 $q);[IO.Directory]::Delete([string]$q.f.prepared.stage_workspace_path,$true);[IO.File]::AppendAllText((Join-Path $q.f.q.persistence.local 'Spotify\Browser\IndexedDB\000001.log'),'drift',[Text.UTF8Encoding]::new($false));$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'cleanup resume accepted protected persistence drift';[void](Assert-RXJournalPhaseV010 $q 'cleanup-starting' 'cleanup persistence drift');$count++

# 22. CAS race at committed-clean cannot manufacture executor success.
$q=New-IntegrationFixtureV010 -Label 'rx-commit-race' -Phase 'apply-verified' -Nonce (RXNonce '7');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryHookFixture=$q;$script:RecoveryHookMode='commit-cas-race';$r=Invoke-RXFixtureV010 $q;Assert-RXFalse ([bool]$r.ok) 'commit CAS race returned success';[void](Assert-RXJournalPhaseV010 $q 'committed-clean' 'commit CAS race');$script:RecoveryHookMode='none';$count++

# 23. Authority-bit tampering cannot turn a non-authoritative success receipt into authority.
$q=New-IntegrationFixtureV010 -Label 'rx-result-tamper' -Phase 'candidate-live' -Nonce (RXNonce '8');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$good=Invoke-RXFixtureV010 $q;Assert-RXSuccessV010 $good 'result tamper setup' 'rollback-complete';$bad=Copy-RX $good.result;$bad.execution_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 (Get-CustomAppProductionBoundedRecoveryExecutorResultMaterialV010 $bad);$ck=Test-CustomAppProductionBoundedRecoveryExecutorResultV010 $bad;Assert-RXFalse ([bool]$ck.ok) 'authority-tampered recovery result accepted';Assert-RXTrue ([string]$ck.reason-like'*authority-escaped-execution_authorized*') 'authority tamper reason drifted';$count++

Write-Host "CUSTOM_APP_PRODUCTION_BOUNDED_RECOVERY_EXECUTOR_MATRIX_PASS total=$count"
