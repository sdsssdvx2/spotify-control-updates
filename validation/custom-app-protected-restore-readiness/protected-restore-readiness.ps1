# Validation candidate: read-only recovery evidence under an EXISTING journal
# lock; never call historical Open-CustomAppProductionCrashJournalLockV010,
# which creates .journal.lock on inspection (OpenOrCreate).
function Read-CustomAppProtectedEvidenceReadOnlyV014 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
    )
    $deny={param([string]$Reason)[pscustomobject]@{
        ok=$false;reason=$Reason;reloaded_from_persistent_store=$false
        evidence_is_authority=$false;execution_authorized=$false
        restore_authorized=$false;apply_authorized=$false
        cleanup_authorized=$false;production_mutation_authorized=$false
    }}
    if(-not(Test-CustomAppProductionRecoveryEvidenceSha256V010 $ExpectedTransactionId)){
        return & $deny 'protected-evidence-transaction-id-invalid'
    }
    $paths=$null;$lock=$null
    try {
        $paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
        if(-not[IO.File]::Exists([string]$paths.lock)){
            throw 'protected-evidence-journal-lock-missing'
        }
        # Journal and its evidence envelope are read together under ONE
        # existing exclusive lock. No create, modify, write or delete path.
        $lock=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
        $journal=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths
        if(-not[bool]$journal.ok -or
           [string]$journal.transaction_id -cne $ExpectedTransactionId){
            throw 'protected-evidence-journal-identity-invalid'
        }
        $path=Get-CustomAppProductionRecoveryEvidencePathV010 -JournalPaths $paths
        Assert-CustomAppUserTxnNoReparseV010 -Path $path
        if(-not[IO.File]::Exists($path)){throw 'protected-evidence-file-missing'}
        $e=ConvertFrom-CustomAppProductionRecoveryEvidenceFileV010 -Path $path
        $check=Test-CustomAppProductionRecoveryEvidenceEnvelopeV010 -Envelope $e -JournalEntry $journal.entry -AllowedRoot $AllowedRoot
        if(-not[bool]$check.ok){
            throw ('protected-evidence-envelope-invalid:'+[string]$check.reason)
        }
        $latest=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths
        if(-not[bool]$latest.ok -or
           [long]$latest.revision -ne [long]$journal.revision -or
           [string]$latest.entry.entry_sha256 -cne [string]$journal.entry.entry_sha256){
            throw 'protected-evidence-journal-changed-during-read'
        }
        return [pscustomobject]@{
            ok=$true;reason='protected-evidence-read-existing-lock-no-create'
            reloaded_from_persistent_store=$true;path=$path
            transaction_id=[string]$check.transaction_id
            preparation_fingerprint=[string]$check.preparation_fingerprint
            evidence_fingerprint=[string]$check.evidence_fingerprint
            envelope=$e;journal_phase=[string]$journal.entry.phase
            journal_revision=[long]$journal.revision
            journal_entry_sha256=[string]$journal.entry.entry_sha256
            evidence_is_authority=$false;execution_authorized=$false
            restore_authorized=$false;apply_authorized=$false
            cleanup_authorized=$false;production_mutation_authorized=$false
        }
    }catch{
        return & $deny ('protected-evidence-denied:'+[string]$_.Exception.Message)
    }finally{
        if($null -ne $lock){$lock.Dispose()}
    }
}

# This candidate retains historical bounded filesystem, evidence envelope and
# restore-resume receipt logic by exact four-anchor derivation, and replaces
# only the historical three unsafe transitive reads plus the function name.
# Historical restore-resume Git blob: 0273d7e28a56759b1d0ec9cbf037483b04d98d63

function Resolve-CustomAppProtectedRestoreResumeAdmissionV014 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,
        [AllowNull()][string]$SpicetifyPath=$null,
        [AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 $tx)){return & $deny 'restore-resume-transaction-id-invalid'}

    try{$journal=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}
    catch{return & $deny ('restore-resume-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null -eq $journal -or -not [bool]$journal.ok -or $null -eq $journal.entry){return & $deny 'restore-resume-journal-invalid'}
    if(([string]$journal.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$journal.entry.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'restore-resume-journal-transaction-mismatch'}
    $phase=[string]$journal.entry.phase
    if($phase -notin @('live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','rollback-required')){return & $deny 'restore-resume-phase-not-auto-restorable'}

    try{$plan=New-CustomAppProductionRecoveryPlanFromClassificationV010 -Classification (Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $journal -ExpectedTransactionId $tx) -StoreRead $journal -ExpectedTransactionId $tx}
    catch{return & $deny ('restore-resume-plan-resolution-failed:'+[string]$_.Exception.Message)}
    $pc=Test-CustomAppProductionRecoveryPlanV010 -Plan $plan
    if(-not [bool]$pc.ok){return & $deny ('restore-resume-plan-invalid:'+[string]$pc.reason)}
    if(-not [bool]$plan.requires_recovery_executor -or -not [bool]$plan.requires_exact_app_restore -or -not [bool]$plan.requires_exact_persistence_restore -or [bool]$plan.housekeeping_only -or [bool]$plan.no_action -or [bool]$plan.requires_manual_inspection){
        return & $deny 'restore-resume-plan-contract-invalid'
    }
    if($phase -in @('live-moved-to-old','candidate-live','transaction-finalized')){
        if([string]$plan.classification -cne 'exact-app-and-persistence-recovery-required' -or [bool]$plan.requires_recovery_apply){return & $deny 'restore-resume-plan-pre-apply-mapping-invalid'}
    } else {
        if([string]$plan.classification -cne 'rollback-and-recovery-apply-required' -or -not [bool]$plan.requires_recovery_apply){return & $deny 'restore-resume-plan-apply-mapping-invalid'}
    }

    $evidence=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null -eq $evidence -or -not [bool]$evidence.ok){return & $deny ('restore-resume-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){
        if([bool]$e.$f){return & $deny ('restore-resume-evidence-authority-escaped-'+$f)}
    }
    foreach($p in @(
        @('name',[string]$journal.entry.name),
        @('source_identity',[string]$journal.entry.source_identity),
        @('remote_commit_sha',[string]$journal.entry.remote_commit_sha),
        @('consumption_id',[string]$journal.entry.consumption_id),
        @('stage_result_fingerprint',[string]$journal.entry.stage_result_fingerprint),
        @('preparation_fingerprint',[string]$journal.entry.preparation_fingerprint)
    )){
        if(([string]$e.($p[0])).Trim().ToLowerInvariant() -cne ([string]$p[1]).Trim().ToLowerInvariant()){return & $deny ('restore-resume-evidence-journal-mismatch-'+$p[0])}
    }
    foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){
        if(-not (Test-CustomAppProductionRecoveryRestoreResumePathEqualV010 -A ([string]$e.$f) -B ([string]$journal.entry.$f))){return & $deny ('restore-resume-evidence-journal-path-mismatch-'+$f)}
    }

    $stage=Test-CustomAppProductionRecoveryRestoreResumeStageV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$stage.ok){return & $deny ([string]$stage.reason)}
    $backups=Test-CustomAppProductionRecoveryRestoreResumeBackupsV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$backups.ok){return & $deny ([string]$backups.reason)}
    $live=Get-CustomAppProductionRecoveryRestoreResumeLiveStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$live.ok){return & $deny ([string]$live.reason)}
    $txn=Get-CustomAppProductionRecoveryRestoreResumeTransactionStateV010 -Envelope $e -AllowedRoot $AllowedRoot
    if(-not [bool]$txn.ok){return & $deny ([string]$txn.reason)}
    $mapping=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $phase -Live $live -Transaction $txn
    if(-not [bool]$mapping.ok){return & $deny ([string]$mapping.reason)}

    try{$persistNow=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}
    catch{return & $deny ('restore-resume-current-persistence-read-failed:'+[string]$_.Exception.Message)}
    if(-not (Test-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 ([string]$persistNow.fingerprint))){return & $deny 'restore-resume-current-persistence-fingerprint-invalid'}

    $exeSha=''
    if([bool]$plan.requires_recovery_apply){
        if(
            [string]::IsNullOrWhiteSpace($SpicetifyAllowedRoot) -or
            [string]::IsNullOrWhiteSpace($SpicetifyPath) -or
            [string]::IsNullOrWhiteSpace($ExpectedSpicetifySha256)
        ){
            return & $deny 'restore-resume-spicetify-pin-inputs-missing'
        }
        try{$exe=Get-CustomAppProductionRecoveryPreflightExecutableEvidenceV010 -AllowedRoot $SpicetifyAllowedRoot -Path $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256}
        catch{return & $deny ('restore-resume-spicetify-pin-invalid:'+[string]$_.Exception.Message)}
        $exeSha=([string]$exe.sha256).Trim().ToLowerInvariant()
    }

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryRestoreResumeAdmissionSchema
        managed_by=$CustomAppProductionRecoveryRestoreResumeAdmissionManagedBy
        qualified_cleanup_resume_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedCleanupResumeHead
        qualified_evidence_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedEvidenceHead
        qualified_journal_head=$CustomAppProductionRecoveryRestoreResumeAdmissionQualifiedJournalHead
        transaction_id=$tx
        phase=$phase
        classification=[string]$plan.classification
        plan_fingerprint=([string]$plan.plan_fingerprint).Trim().ToLowerInvariant()
        evidence_fingerprint=([string]$e.evidence_fingerprint).Trim().ToLowerInvariant()
        journal_revision=[int64]$journal.revision
        journal_entry_sha256=([string]$journal.entry.entry_sha256).Trim().ToLowerInvariant()
        name=([string]$e.name).Trim().ToLowerInvariant()
        source_identity=([string]$e.source_identity).Trim().ToLowerInvariant()
        remote_commit_sha=([string]$e.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$e.consumption_id).Trim().ToLowerInvariant()
        preparation_fingerprint=([string]$e.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$e.live_path
        transaction_root=[string]$e.transaction_root
        stage_workspace_path=[string]$e.stage_workspace_path
        app_backup_path=[string]$e.app_backup_path
        persistence_backup_path=[string]$e.persistence_backup_path
        live_state=[string]$live.state
        live_runtime_tree_sha256=[string]$live.tree_sha256
        transaction_status=[string]$txn.status
        transaction_old_status=[string]$txn.old_status
        transaction_candidate_status=[string]$txn.candidate_status
        stage_status=[string]$stage.status
        app_backup_tree_sha256=([string]$e.app_backup_tree_sha256).Trim().ToLowerInvariant()
        persistence_fingerprint=([string]$e.persistence_fingerprint).Trim().ToLowerInvariant()
        current_persistence_fingerprint=([string]$persistNow.fingerprint).Trim().ToLowerInvariant()
        current_persistence_matches_durable=(([string]$persistNow.fingerprint).Trim().ToLowerInvariant() -ceq ([string]$e.persistence_fingerprint).Trim().ToLowerInvariant())
        requires_recovery_apply=[bool]$plan.requires_recovery_apply
        spicetify_executable_sha256=$exeSha
        restore_resume_eligible=$true
        requires_exact_restore=$true
        requires_future_executor_fresh_revalidation=$true
        checked_at=$Now.ToUniversalTime().ToString('o')
        eligible_until=$Now.AddSeconds(10).ToUniversalTime().ToString('o')
        admission_is_authority=$false
        execution_authorized=$false
        restore_authorized=$false
        apply_authorized=$false
        cleanup_authorized=$false
        production_mutation_authorized=$false
        restore_resume_admission_fingerprint=$null
    }
    $receipt.restore_resume_admission_fingerprint=Get-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryRestoreResumeAdmissionMaterialV010 -Receipt $receipt)
    return [pscustomobject]@{ok=$true;reason='recovery-restore-resume-bounded-state-eligible-zero-authority';receipt=$receipt;evidence=$e;plan=$plan;live=$live;transaction=$txn;stage=$stage;backups=$backups;filesystem_mapping_reason=[string]$mapping.reason}
}

# The sealed source is selected by the current user's DPAPI store, not
# caller-supplied JSON, app names, paths, transaction identifiers or plans.
# Normal production profile roots are taken from the active Windows user.
# CI-only profile overrides are allowed solely under a hosted runner.
function Get-CustomAppSealedRestoreReadinessV014 {
    param(
        [string]$HostedCiRoot,
        [string]$HostedCiLocalAppDataRoot,
        [string]$HostedCiAppDataRoot,
        $HeldCrossEngineSession
    )
    $global=$null;$ownsGlobal=$false
    try {
        if($null-ne$HeldCrossEngineSession){
            $global=$HeldCrossEngineSession
        }else{
            $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
            $ownsGlobal=$true
        }
        $audit=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $HostedCiRoot -HeldCrossEngineSession $global
        if(-not[bool]$audit.ok -or [bool]$audit.result_is_authority -or
           [bool]$audit.production_mutation_authorized){
            throw 'protected-readiness-source-is-not-readonly'
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $global)
        $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $roaming=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot)){
            if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
               $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
               [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
                throw 'protected-readiness-profile-override-not-hosted'
            }
            $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
            foreach($x in @($HostedCiRoot,$HostedCiLocalAppDataRoot,$HostedCiAppDataRoot)){
                if([string]::IsNullOrWhiteSpace($x) -or
                   -not[IO.Path]::IsPathRooted($x) -or $x.StartsWith('\\') -or
                   -not[IO.Path]::GetFullPath($x).StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
                    throw 'protected-readiness-hosted-root-unqualified'
                }
            }
            $local=[IO.Path]::GetFullPath($HostedCiLocalAppDataRoot)
            $roaming=[IO.Path]::GetFullPath($HostedCiAppDataRoot)
        }elseif(-not[string]::IsNullOrWhiteSpace($HostedCiLocalAppDataRoot) -or
                -not[string]::IsNullOrWhiteSpace($HostedCiAppDataRoot)){
            throw 'protected-readiness-profile-override-without-hosted-ci-denied'
        }
        foreach($dir in @($local,$roaming)){
            [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $dir -RequireDirectory)
        }
        $out=New-Object 'System.Collections.Generic.List[object]'
        foreach($item in @($audit.items)){
            if(-not[bool]$item.active){
                $out.Add([pscustomobject]@{
                    name=[string]$item.name;active=$false
                    phase='none';eligible=$false;reason='no-active-transaction'
                    receipt=$null;source_fingerprint=''
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
                continue
            }
            $src=$item.source;$plan=$item.plan
            if($null-eq$src -or $null-eq$plan -or
               [bool]$src.production_mutation_authorized -or
               [string]$plan.transaction_id -cne [string]$src.transaction_id){
                throw 'protected-readiness-source-or-plan-missing'
            }
            if([string]$item.phase -notin @(
                'live-moved-to-old','candidate-live','transaction-finalized',
                'apply-starting','apply-returned-success-pending-verification',
                'rollback-required'
            )){
                $out.Add([pscustomobject]@{
                    name=[string]$src.name;active=$true
                    phase=[string]$item.phase;eligible=$false
                    reason='phase-not-qualified-for-exact-restore'
                    receipt=$null;source_fingerprint=[string]$src.source_fingerprint
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
                continue
            }
            # Apply/resume requires a separately authenticated executable pin
            # enrolled before the crash, never a caller/PATH-provided digest.
            if([bool]$plan.requires_recovery_apply){
                $out.Add([pscustomobject]@{
                    name=[string]$src.name;active=$true
                    phase=[string]$item.phase;eligible=$false
                    reason='verified-spicetify-binary-pin-not-enrolled'
                    receipt=$null;source_fingerprint=[string]$src.source_fingerprint
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
                continue
            }
            $live=[string]$src.live;$name=[string]$src.name
            $missing=-not[IO.Directory]::Exists($live)
            $paths=if($missing){
                Get-CustomAppUserTxnMissingLivePathsV011 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
            }else{
                Get-CustomAppUserTxnPathsV010 -Name $name -LivePath $live -HostedCiRoot $HostedCiRoot
            }
            if([string]$paths.key -cne [string]$src.key){
                throw 'protected-readiness-recomputed-state-key-mismatch'
            }
            Assert-CustomAppUserTxnNoReparseV010 -Path ([string]$paths.lock)
            if(-not[IO.File]::Exists([string]$paths.lock)){
                throw 'protected-readiness-per-app-lock-absent'
            }
            $handle=$null
            try{
                $handle=[IO.File]::Open([string]$paths.lock,[IO.FileMode]::Open,
                    [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                [void](Assert-CustomAppUserTxnPrivateDirectoryV010 -Path $paths.directory)
                $originalBytes=[IO.File]::ReadAllBytes([string]$paths.state)
                $originalSha=Get-CustomAppUserTxnSha256V010 ([Convert]::ToBase64String($originalBytes))
                $state=Read-CustomAppUserTxnStateV010 -Paths $paths
                if($null-eq$state.active -or
                   [long]$state.revision -ne [long]$src.state_revision -or
                   [string]$state.name -cne $name -or
                   [string]$state.live -cne $live -or
                   [string]$state.active.consumption_id -cne [string]$src.consumption_id -or
                   [string]$state.active.transaction_id -cne [string]$src.transaction_id -or
                   [string]$state.active.nonce -cne [string]$src.nonce){
                    throw 'protected-readiness-dpapi-source-changed'
                }
                $sess=[pscustomobject]@{
                    ok=$true;state=$state;paths=$paths;lock_handle=$handle
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                }
                $locator=Read-CustomAppUserTxnJournalLocatorV010 -Session $sess
                $loc=$locator.record
                if(-not[bool]$locator.ok -or
                   [string]$loc.transaction_id -cne [string]$src.transaction_id -or
                   [string]$loc.consumption_id -cne [string]$src.consumption_id -or
                   [string]$loc.nonce -cne [string]$src.nonce -or
                   [string]$loc.allowed_root -cne [string]$src.allowed_root -or
                   [string]$loc.store_directory -cne [string]$src.store_directory){
                    throw 'protected-readiness-sealed-locator-drift'
                }
                $j=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$loc.allowed_root) -StoreDirectory ([string]$loc.store_directory)
                if(-not[bool]$j.ok -or
                   [string]$j.entry.name -cne $name -or
                   [string]$j.entry.live_path -cne $live -or
                   [string]$j.entry.consumption_id -cne [string]$src.consumption_id -or
                   [string]$j.transaction_id -cne [string]$src.transaction_id -or
                   [long]$j.revision -ne [long]$src.journal_revision -or
                   [string]$j.entry.entry_sha256 -cne [string]$src.journal_entry_sha256 -or
                   [string]$j.entry.phase -cne [string]$item.phase){
                    throw 'protected-readiness-journal-changed-before-admission'
                }
                $args=@{
                    AllowedRoot=[string]$loc.allowed_root
                    StoreDirectory=[string]$loc.store_directory
                    ExpectedTransactionId=[string]$src.transaction_id
                    LocalAppDataRoot=$local
                    AppDataRoot=$roaming
                }
                $result=Resolve-CustomAppProtectedRestoreResumeAdmissionV014 @args
                if($null-eq$result -or -not[bool]$result.ok){
                    $reason=if($null-eq$result){'no-result'}else{[string]$result.reason}
                    $out.Add([pscustomobject]@{
                        name=$name;active=$true;phase=[string]$item.phase
                        eligible=$false;reason=('qualified-readonly-admission-denied:'+$reason)
                        receipt=$null;source_fingerprint=[string]$src.source_fingerprint
                        production_execution_authorized=$false
                        production_mutation_authorized=$false
                    })
                    continue
                }
                $validated=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $result.receipt
                if(-not[bool]$validated.ok -or
                   [bool]$result.receipt.admission_is_authority -or
                   [bool]$result.receipt.production_mutation_authorized -or
                   [string]$result.receipt.transaction_id -cne [string]$src.transaction_id -or
                   [string]$result.receipt.consumption_id -cne [string]$src.consumption_id -or
                   [string]$result.receipt.phase -cne [string]$item.phase -or
                   [long]$result.receipt.journal_revision -ne [long]$j.revision -or
                   [string]$result.receipt.journal_entry_sha256 -cne [string]$j.entry.entry_sha256 -or
                   [string]$result.receipt.plan_fingerprint -cne [string]$plan.plan_fingerprint){
                    throw 'protected-readiness-historical-receipt-continuity-failed'
                }
                $after=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot ([string]$loc.allowed_root) -StoreDirectory ([string]$loc.store_directory)
                if([string]$after.entry.entry_sha256 -cne [string]$j.entry.entry_sha256 -or
                   [long]$after.revision -ne [long]$j.revision -or
                   (Get-CustomAppUserTxnSha256V010 ([Convert]::ToBase64String([IO.File]::ReadAllBytes([string]$paths.state)))) -cne $originalSha){
                    throw 'protected-readiness-source-changed-after-historical-admission'
                }
                $out.Add([pscustomobject]@{
                    name=$name;active=$true;phase=[string]$item.phase
                    eligible=$true;reason='fresh-qualified-no-create-readonly-admission'
                    receipt=$result.receipt;source_fingerprint=[string]$src.source_fingerprint
                    production_execution_authorized=$false
                    production_mutation_authorized=$false
                })
            }finally{
                if($null-ne$handle){$handle.Dispose()}
            }
            [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $global)
        }
        return [pscustomobject]@{
            schema=1;ok=$true;enrollment_found=[bool]$audit.enrollment_found
            inspected_count=[int]$audit.inspected_count
            active_count=[int]$audit.active_count
            items=@($out.ToArray())
            qualification_is_not_execution=$true
            read_existing_journal_lock_only=$true
            result_is_authority=$false;production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }finally{
        if($ownsGlobal -and $null-ne$global -and $null-ne$global.lock_handle){
            $global.lock_handle.Dispose()
        }
    }
}
function Test-CustomAppSealedRestoreReadinessSelfTestV014 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'protected-readiness-production-fullchain-unqualified'
    }
    foreach($fn in @('Read-CustomAppProtectedEvidenceReadOnlyV014',
                     'Resolve-CustomAppProtectedRestoreResumeAdmissionV014',
                     'Get-CustomAppSealedRestoreReadinessV014')){
        if(-not(Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('protected-readiness-required-function-missing-'+$fn)
        }
    }
    Write-Host 'PROTECTED_READINESS_SELFTEST_PASS existing_journal_lock_only=true dpapi_source_only=true no_mutation=true no_spicetify_execution=true'
}
