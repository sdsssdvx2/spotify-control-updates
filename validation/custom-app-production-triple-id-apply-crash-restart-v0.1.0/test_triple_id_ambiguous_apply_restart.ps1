# CI-ONLY actual ZIP -> third HMAC permit -> journaled atomic -> compiled FAKE
# apply -> process-death in TWO ambiguous phases -> unchanged recovery worker
# baseline fail-closed -> narrow strict compatibility overlay -> exact old-code
# restore + FAKE recovery apply -> persistent rollback-complete + replay denial.
# NO real Spotify, production main, or user PC access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'TID_APPLY_RESTART_HOSTED_WINDOWS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$parentDir=Join-Path $root 'validation/custom-app-production-triple-id-journaled-forward-commit-v0.1.0'
$forward=Join-Path $parentDir 'test_triple_id_journaled_forward_commit.ps1'
$worker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
$mapping=Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1'
$overlay=Join-Path $PSScriptRoot 'restore-resume-retained-old-live-overlay.ps1'
$originalBlob='0273d7e28a56759b1d0ec9cbf037483b04d98d63'
function Assert-AR([bool]$Pass,[string]$Reason){if(-not$Pass){throw ('TID_APPLY_RESTART_FAIL: '+$Reason)}}
function Invoke-ARChild {
    param([Parameter(Mandatory=$true)][string]$Path,[string[]]$Arguments=@(),[Parameter(Mandatory=$true)][string]$Log)
    $old=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path @Arguments *>&1 | Tee-Object -FilePath $Log
        return [int]$LASTEXITCODE
    } finally {$ErrorActionPreference=$old}
}
function Read-ARJson([string]$Path){
    Assert-AR (Test-Path -LiteralPath $Path -PathType Leaf) ('missing-json-'+$Path)
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop|ConvertFrom-Json)
}
function Read-ARCounter([string]$Path){
    Assert-AR (Test-Path -LiteralPath $Path -PathType Leaf) ('missing-fake-counter-'+$Path)
    return [int]([IO.File]::ReadAllText($Path).Trim())
}
function Read-AROriginalJournal([string]$Root,[string]$Store){
    # Must be called in a fresh host scope; the worker is not allowed to
    # assume a journal can grant execution authority.
    $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Root -StoreDirectory $Store
    Assert-AR ([bool]$j.ok -and [bool]$j.reloaded_from_persistent_store) 'journal-read-failed'
    return $j
}
foreach($f in @($forward,$worker,$mapping,$overlay)){Assert-AR (Test-Path -LiteralPath $f -PathType Leaf) ('qualified-dependency-not-present-'+$f)}
Assert-AR ((git hash-object $mapping).Trim() -ceq $originalBlob) 'unmodified-qualified-restore-admission-blob-drift'
$rawOverlay=[IO.File]::ReadAllText($overlay)
Assert-AR ($rawOverlay.Contains('retained_old_live_preverified_by_existing_durable_envelope')) 'narrow-overlay-missing-contract'
Assert-AR ($rawOverlay -notmatch '(?i)Invoke-Expression|DownloadString|Invoke-WebRequest|Start-Process|Restore-SpotifyPersistenceBackup') 'overlay-includes-unreviewed-side-effect'
$prevRoot=$env:RUNNER_TEMP;$prevTemp=$env:TEMP;$prevTmp=$env:TMP
$phases=@('apply-starting','apply-returned-success-pending-verification')
$saved=@{}
$cases=0
try{
    foreach($phase in $phases){
        $isolated=Join-Path $prevRoot ('third-id-apply-crash-'+[Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($isolated)|Out-Null
        $env:RUNNER_TEMP=$isolated;$env:TEMP=$isolated;$env:TMP=$isolated
        $env:SC_TID_APPLY_INTERRUPT_PHASE=$phase
        $statePath=Join-Path $isolated 'restart-state.json'
        $env:SC_TID_APPLY_CRASH_STATE_PATH=$statePath
        $tag=$(if($phase -ceq 'apply-starting'){'starting'}else{'pending'})
        $log=Join-Path $PSScriptRoot ($tag+'-parent.log')
        $exit=Invoke-ARChild -Path $forward -Log $log
        $env:SC_TID_APPLY_INTERRUPT_PHASE=$null;$env:SC_TID_APPLY_CRASH_STATE_PATH=$null
        Assert-AR ($exit-eq0) ('new-third-id-zip-parent-exited-failed-'+$phase+'-'+$exit)
        $state=Read-ARJson $statePath
        Assert-AR ([int]$state.schema -eq 1 -and [bool]$state.validation_only -and -not[bool]$state.production_mutation_authorized -and -not[bool]$state.execution_authorized) 'non-validation-state-or-authority'
        Assert-AR ([string]$state.expected_start_phase -ceq $phase -and [string]$state.transaction_id -cmatch '^[0-9a-f]{64}$') ('phase-or-transaction-id-drift-'+$phase)
        $parentText=Get-Content -LiteralPath $log -Raw
        Assert-AR ($parentText.Contains(('TRIPLE_ID_APPLY_CRASH_PARENT_PASS phase='+$phase+' fake_normal_apply_once=true retained_old_live_and_all_backups=true journal_durable=true no_hmac_key_in_child_state=true'))) ('new-parent-proof-missing-'+$phase)
        $stateText=[IO.File]::ReadAllText($statePath)
        Assert-AR ($stateText -notmatch '(?i)session.?key|hmac.?key|bearer|client.?secret|token.?secret|DINPIKey') 'ephemeral-key-leaked-to-restart-child'
        Assert-AR ((Read-ARCounter ([string]$state.primary_apply_count_path)) -eq 1) ('fake-new-apply-not-exactly-one-'+$phase)
        Assert-AR (-not(Test-Path -LiteralPath ([string]$state.apply_count_path))) 'recovery-apply-ran-before-process-resume'
        foreach($f in @('old_live_path','stage_workspace_path','app_backup_path','persistence_backup_path')){
            Assert-AR (Test-Path -LiteralPath ([string]$state.$f) -PathType Container) ('rollback-source-missing-before-restart-'+$phase+'-'+$f)
        }
        $wrong=($stateText|ConvertFrom-Json);$wrong.transaction_id='0'*64
        $wrongPath=Join-Path $isolated 'wrong-state.json'
        [IO.File]::WriteAllText($wrongPath,($wrong|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        $wrongResult=Join-Path $isolated 'wrong-result.json'
        $wrongExit=Invoke-ARChild -Path $worker -Arguments @('-StatePath',$wrongPath,'-ResultPath',$wrongResult) -Log (Join-Path $PSScriptRoot ($tag+'-wrong-id.log'))
        Assert-AR ($wrongExit-ne0) ('wrong-id-admitted-'+$phase)
        $wrongData=Read-ARJson $wrongResult
        Assert-AR (-not[bool]$wrongData.admission_ok -and -not[bool]$wrongData.executor_ok) ('wrong-id-progressed-'+$phase)
        $originalResult=Join-Path $isolated 'unmodified-result.json'
        $originalExit=Invoke-ARChild -Path $worker -Arguments @('-StatePath',$statePath,'-ResultPath',$originalResult) -Log (Join-Path $PSScriptRoot ($tag+'-original-denial.log'))
        Assert-AR ($originalExit-ne0) ('original-mapping-unexpectedly-admitted-'+$phase)
        $original=Read-ARJson $originalResult
        Assert-AR (-not[bool]$original.admission_ok -and -not[bool]$original.executor_ok) ('original-mapping-advanced-recovery-'+$phase)
        Assert-AR ([string]$original.error -match 'restore-resume-(apply-starting|apply-returned)-filesystem-state-invalid') ('unexpected-original-denial-'+$phase+' '+[string]$original.error)
        Assert-AR ((Read-ARCounter ([string]$state.primary_apply_count_path)) -eq 1 -and -not(Test-Path -LiteralPath ([string]$state.apply_count_path))) ('unmodified-mapping-performed-side-effect-'+$phase)
        Assert-AR (Test-Path -LiteralPath ([string]$state.old_live_path) -PathType Container) ('old-live-deleted-after-original-denial-'+$phase)
        $saved[$phase]=[pscustomobject]@{state=$state;path=$statePath;root=$isolated;tag=$tag}
        $cases++
        Write-Host ('TRIPLE_ID_APPLY_CRASH_UNPATCHED_PRECHECK_DENIAL_PASS phase='+$phase+' real_zip=true wrong_id_denied=true retained_old_live_not_misclassified_as_authority=true')
    }
    # Only the temporary Actions checkout receives this additive overlay.
    Assert-AR ((git hash-object $mapping).Trim() -ceq $originalBlob) 'qualified-original-mapping-changed-before-overlay'
    [IO.File]::AppendAllText($mapping,([Environment]::NewLine+$rawOverlay),[Text.UTF8Encoding]::new($false))
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($mapping,[ref]$tokens,[ref]$parseErrors)
    Assert-AR ($parseErrors.Count-eq0) ('bounded-mapping-overlay-parse-failed-'+[string]$(if($parseErrors.Count){$parseErrors[0].Message}else{''}))
    . $mapping
    Test-TripleIdRetainedOldLiveMappingOverlayV010
    $cases++
    foreach($phase in $phases){
        $savedCase=$saved[$phase]
        $env:RUNNER_TEMP=[string]$savedCase.root;$env:TEMP=[string]$savedCase.root;$env:TMP=[string]$savedCase.root
        $state=$savedCase.state
        $resultPath=Join-Path $savedCase.root 'recovery-result.json'
        $childExit=Invoke-ARChild -Path $worker -Arguments @('-StatePath',$savedCase.path,'-ResultPath',$resultPath) -Log (Join-Path $PSScriptRoot ($savedCase.tag+'-fresh-process-rollback.log'))
        $result=Read-ARJson $resultPath
        Assert-AR ($childExit -eq0) ('bounded-recovery-executor-denied-'+$phase+' '+[string]$result.error+' '+[string]$result.executor_reason+' checkpoint='+[string]$result.executor_last_checkpoint)
        Assert-AR ([bool]$result.success -and [bool]$result.executor_ok -and [bool]$result.restore_performed -and [bool]$result.recovery_apply_executed -and [bool]$result.rollback_complete_persisted -and [bool]$result.rollback_required_was_appended) ('recovery-evidence-incomplete-'+$phase)
        Assert-AR ([string]$result.executor_started_phase -ceq $phase -and [string]$result.final_phase -ceq 'rollback-complete' -and [int]$result.apply_count -eq 1) ('recovery-wrong-phase-or-apply-count-'+$phase)
        Assert-AR ([int]$result.process_id -ne [int]$state.parent_process_id -and [bool]$result.bootstrap_dependencies_verified) ('recovery-process-not-independent-'+$phase)
        Assert-AR ((Read-ARCounter ([string]$state.primary_apply_count_path)) -eq 1 -and (Read-ARCounter ([string]$state.apply_count_path)) -eq 1) ('primary-or-rollback-apply-duplicated-'+$phase)
        Assert-AR ([IO.File]::ReadAllText([string]$state.applied_probe_path) -ceq [IO.File]::ReadAllText([string]$state.live_probe_path)) ('fake-restore-apply-did-not-see-restored-old-code-'+$phase)
        Assert-AR ((Get-FileHash -LiteralPath ([string]$state.primary_applied_index_path) -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$state.primary_applied_index_sha256) ('primary-new-apply-output-drift-'+$phase)
        Assert-AR ([string]$result.evidence_fingerprint_after -ceq [string]$state.evidence_fingerprint) ('immutable-evidence-drift-'+$phase)
        $replayPath=Join-Path $savedCase.root 'terminal-replay-result.json'
        $replayExit=Invoke-ARChild -Path $worker -Arguments @('-StatePath',$savedCase.path,'-ResultPath',$replayPath) -Log (Join-Path $PSScriptRoot ($savedCase.tag+'-terminal-replay.log'))
        Assert-AR ($replayExit-ne0) ('completed-rollback-replay-admitted-'+$phase)
        $replay=Read-ARJson $replayPath
        Assert-AR (-not[bool]$replay.executor_ok -and (Read-ARCounter ([string]$state.primary_apply_count_path)) -eq1 -and (Read-ARCounter ([string]$state.apply_count_path)) -eq1) ('terminal-replay-relaunched-fake-apply-'+$phase)
        $cases++
        Write-Host ('TRIPLE_ID_REAL_ZIP_AMBIGUOUS_APPLY_RESTART_PASS phase='+$phase+' fresh_process=true narrow_mapping=true original_denial_reproduced=true new_fake_apply_count=1 old_fake_recovery_apply_count=1 rollback_complete_durable=true wrong_id_and_replay_denied=true no_key_persisted=true')
    }
    Assert-AR ($cases-eq5) ('integration-scenario-count-drift-'+$cases)
    $evidence=[ordered]@{
        schema=1;status='PASS';validation_only=$true;new_scenario_count=$cases
        normal_forward_parent='b4cf2461b087504894f56c4f09d1cc12cf5eb5e5'
        stages=@('apply-starting','apply-returned-success-pending-verification')
        original_baseline_denied_while_old_live_retained=$true
        restoration_overlay_exact_exception_cases=2
        mapping_regression_cases=11
        independent_windows_process_restored_old_code=$true
        real_zip_third_hmac_permit_durable_consumption=$true
        original_app_git_spotify_persistence_restored=$true
        primary_apply_once_per_case=$true;recovery_apply_once_per_case=$true
        signed_session_key_not_serialized=$true;replay_and_wrong_id_denied=$true
        hard_disabled_production_main='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
        actual_installed_spotify_untouched=$true
        tested_sha=(git rev-parse HEAD).Trim()
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'evidence.json'),($evidence|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Write-Host 'TRIPLE_ID_REAL_ZIP_APPLY_CRASH_RESTART_ALL_EVIDENCE_PASS ambiguous_phases=2 original_denial_reproduced=true narrow_overlay=true fresh_process=true'
} finally {
    $env:SC_TID_APPLY_INTERRUPT_PHASE=$null;$env:SC_TID_APPLY_CRASH_STATE_PATH=$null
    $env:RUNNER_TEMP=$prevRoot;$env:TEMP=$prevTemp;$env:TMP=$prevTmp
}
