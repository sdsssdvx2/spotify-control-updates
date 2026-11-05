# Production-compatible, non-authoritative mapping correction. Loaded into a
# HARD-DISABLED candidate only. The caller MUST already have established all
# durable journal, immutable recovery evidence, old-live complete tree/file
# count/size, no-reparse, stage/app/persistence backups, live tree and path
# containment evidence. This function never does I/O or grants permission.
#
# Qualified original v010 remains byte-exact and remains the decision source
# for every other phase/state. Only the two genuinely observed false denials
# are corrected for the journaled atomic contract that retains exact old-live
# until cleanup-starting.
$CustomAppProductionRetainedOldLiveCompatibilitySchema = 1
$CustomAppProductionRetainedOldLiveCompatibilityManagedBy = 'custom-app-production-retained-old-live-compat-v1'
$CustomAppProductionRetainedOldLiveCompatibilityQualifiedOriginalBlob = '0273d7e28a56759b1d0ec9cbf037483b04d98d63'

function Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011 {
    param(
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)]$Live,
        [Parameter(Mandatory=$true)]$Transaction
    )
    # Do not bypass any existing v010 positive or negative decisions.
    $original=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $Phase -Live $Live -Transaction $Transaction
    if($null -eq $original){return [pscustomobject]@{ok=$false;reason='restore-resume-v011-original-null'}}
    if([bool]$original.ok){return $original}
    $expectedReason=switch($Phase) {
        'apply-starting' {'restore-resume-apply-starting-filesystem-state-invalid'}
        'apply-returned-success-pending-verification' {'restore-resume-apply-returned-filesystem-state-invalid'}
        default {''}
    }
    if([string]::IsNullOrWhiteSpace($expectedReason) -or [string]$original.reason -cne $expectedReason){return $original}
    # The original v010 already denied the input. The admission caller first
    # verifies transaction-root reparse-free contents: exactly old-live and no
    # candidate. Its old-live tree sha256, count, bytes must match immutable
    # recovery evidence. We may only map that already-verified state.
    if(
        [string]$Live.state -ceq 'candidate-live-exact' -and
        [string]$Transaction.status -ceq 'present-verified' -and
        [string]$Transaction.old_status -ceq 'present-verified' -and
        [string]$Transaction.candidate_status -ceq 'absent'
    ){
        return [pscustomobject]@{
            ok=$true
            reason='restore-resume-v011-journaled-apply-retained-exact-old-live'
            original_denial_preserved_for_other_states=$true
            original_denial_reason=[string]$original.reason
            map_only=$true
            result_is_authority=$false
            admission_is_authority=$false
            restore_authorized=$false
            apply_authorized=$false
            cleanup_authorized=$false
            production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }
    return $original
}

function Test-CustomAppProductionRetainedOldLiveCompatibilitySelfTestV011 {
    # This is pure local-state mapping with no filesystem changes, I/O,
    # HMAC session material, process start, or network access.
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'retained-old-live compatibility selftest requires disabled production pipeline'}
    if([string]$CustomAppProductionRetainedOldLiveCompatibilityQualifiedOriginalBlob -cne '0273d7e28a56759b1d0ec9cb9f037483b04d98d63'){
        # Deliberately keep pin exact: no silent fallback to unqualified old code.
        throw 'qualified original restore mapping source pin drift'
    }
    foreach($fn in @('Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010','Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011')){
        if(-not(Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)){throw ('required restore mapping unavailable '+$fn)}
    }
    $count=0
    $old=[pscustomobject]@{state='candidate-live-exact'}
    $txn=[pscustomobject]@{status='present-verified';old_status='present-verified';candidate_status='absent'}
    foreach($phase in @('apply-starting','apply-returned-success-pending-verification')){
        $baseline=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $phase -Live $old -Transaction $txn
        if([bool]$baseline.ok){throw ('qualified original incorrectly accepts retained old-live '+$phase)}
        $new=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011 -Phase $phase -Live $old -Transaction $txn
        if(-not[bool]$new.ok -or [string]$new.reason -cne 'restore-resume-v011-journaled-apply-retained-exact-old-live' -or [bool]$new.result_is_authority -or [bool]$new.production_mutation_authorized -or [bool]$new.apply_authorized){throw ('v011 exact retained old-live denied or authorized '+$phase)}
        $count++
    }
    foreach($case in @(
        [pscustomobject]@{phase='candidate-live';live='candidate-live-exact';transaction='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='rollback-required';live='candidate-live-exact';transaction='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-verified';live='candidate-live-exact';transaction='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='old-live-exact';transaction='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';transaction='already-absent';old='absent';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';transaction='present-verified';old='absent';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';transaction='present-verified';old='present-verified';candidate='present-verified'},
        [pscustomobject]@{phase='apply-returned-success-pending-verification';live='candidate-live-exact';transaction='present-verified';old='present-verified';candidate='present-verified'},
        [pscustomobject]@{phase='apply-returned-success-pending-verification';live='absent-after-live-move';transaction='present-verified';old='present-verified';candidate='absent'}
    )){
        $l=[pscustomobject]@{state=[string]$case.live}
        $t=[pscustomobject]@{status=[string]$case.transaction;old_status=[string]$case.old;candidate_status=[string]$case.candidate}
        $a=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $case.phase -Live $l -Transaction $t
        $b=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV011 -Phase $case.phase -Live $l -Transaction $t
        if([bool]$a.ok -ne [bool]$b.ok -or [string]$a.reason -cne [string]$b.reason){throw ('v011 unrelated original decision altered: '+$case.phase+'/'+$case.live)}
        $count++
    }
    if($count-ne11){throw 'v011 mapping selftest case count mismatch'}
    Write-Host 'CUSTOM_APP_PRODUCTION_RETAINED_OLD_LIVE_COMPAT_SELFTEST_V011_PASS cases=11 only_two_apply_phases_extended=true other_original_mappings_unchanged=true authority=false'
}
