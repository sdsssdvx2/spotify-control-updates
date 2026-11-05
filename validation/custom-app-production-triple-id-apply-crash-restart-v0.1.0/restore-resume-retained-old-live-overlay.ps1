# VALIDATION-ONLY overlay for one narrowly observed real-journal compatibility gap.
# Append ONLY to the exact SHA-pinned original restore-resume admission module in
# the disposable GitHub-hosted Windows runner checkout. NEVER source in production.
# The original admission still verifies the durable journal, recovery envelope,
# stage, both backups, live tree, whole old-live tree+filecount+bytes, reparse
# safety, and permitted transaction-root children before invoking this mapping.
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows'){
    throw 'triple-id-retained-old-live-overlay-github-hosted-windows-only'
}
$script:TripleIdQualifiedOriginalRestoreMappingV010=(Get-Command 'Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010' -CommandType Function -ErrorAction Stop).ScriptBlock
if($null -eq $script:TripleIdQualifiedOriginalRestoreMappingV010){throw 'original-qualified-recovery-mapping-missing'}
function Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 {
    param([Parameter(Mandatory=$true)][string]$Phase,[Parameter(Mandatory=$true)]$Live,[Parameter(Mandatory=$true)]$Transaction)
    # Always honor the original mapping first. Override ONLY its one known
    # false denial for post-atomic, pre-cleanup apply states retaining old-live.
    $baseline=& $script:TripleIdQualifiedOriginalRestoreMappingV010 -Phase $Phase -Live $Live -Transaction $Transaction
    if($null-eq$baseline){return [pscustomobject]@{ok=$false;reason='triple-id-original-mapping-null'}}
    if([bool]$baseline.ok){return $baseline}
    if(
        $Phase -in @('apply-starting','apply-returned-success-pending-verification') -and
        [string]$Live.state -ceq 'candidate-live-exact' -and
        [string]$Transaction.status -ceq 'present-verified' -and
        [string]$Transaction.old_status -ceq 'present-verified' -and
        [string]$Transaction.candidate_status -ceq 'absent'
    ){
        return [pscustomobject]@{
            ok=$true;reason='triple-id-journaled-apply-retained-exact-old-live-bound'
            strict_original_mapping_denied=$true
            allowed_only_for_two_ambiguous_apply_phases=$true
            retained_old_live_preverified_by_existing_durable_envelope=$true
            mapping_is_authority=$false;restore_authorized=$false;apply_authorized=$false;production_mutation_authorized=$false
        }
    }
    return $baseline
}
# Fast structural regression checks: approval is a mapping result only, NOT a
# durable HMAC permit, persistence evidence, or new execution authority.
function Test-TripleIdRetainedOldLiveMappingOverlayV010 {
    $live=[pscustomobject]@{state='candidate-live-exact'}
    $retained=[pscustomobject]@{status='present-verified';old_status='present-verified';candidate_status='absent'}
    $count=0
    foreach($phase in @('apply-starting','apply-returned-success-pending-verification')){
        $baseline=& $script:TripleIdQualifiedOriginalRestoreMappingV010 -Phase $phase -Live $live -Transaction $retained
        if($null-eq$baseline -or [bool]$baseline.ok){throw ('expected-old-mapping-rejection-missing-'+$phase)}
        $allowed=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $phase -Live $live -Transaction $retained
        if(-not[bool]$allowed.ok -or [string]$allowed.reason -cne 'triple-id-journaled-apply-retained-exact-old-live-bound' -or [bool]$allowed.mapping_is_authority -or [bool]$allowed.restore_authorized -or [bool]$allowed.apply_authorized){throw ('new-mapping-rejected-exact-retained-old-'+$phase)}
        $count++
    }
    foreach($negative in @(
        [pscustomobject]@{phase='candidate-live';live='candidate-live-exact';txn='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='rollback-required';live='candidate-live-exact';txn='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-verified';live='candidate-live-exact';txn='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='old-live-exact';txn='present-verified';old='present-verified';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';txn='already-absent';old='absent';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';txn='present-verified';old='absent';candidate='absent'},
        [pscustomobject]@{phase='apply-starting';live='candidate-live-exact';txn='present-verified';old='present-verified';candidate='present-verified'},
        [pscustomobject]@{phase='apply-returned-success-pending-verification';live='candidate-live-exact';txn='present-verified';old='present-verified';candidate='present-verified'},
        [pscustomobject]@{phase='apply-returned-success-pending-verification';live='absent-after-live-move';txn='present-verified';old='present-verified';candidate='absent'}
    )){
        $l=[pscustomobject]@{state=[string]$negative.live}
        $t=[pscustomobject]@{status=[string]$negative.txn;old_status=[string]$negative.old;candidate_status=[string]$negative.candidate}
        $baseline=& $script:TripleIdQualifiedOriginalRestoreMappingV010 -Phase $negative.phase -Live $l -Transaction $t
        $actual=Test-CustomAppProductionRecoveryRestoreResumeFilesystemMappingV010 -Phase $negative.phase -Live $l -Transaction $t
        if([bool]$actual.ok -ne [bool]$baseline.ok -or [string]$actual.reason -cne [string]$baseline.reason){throw ('negative-mapping-regressed-'+$negative.phase+'-'+$negative.live+'-'+$negative.old)}
        $count++
    }
    if($count-ne11){throw 'retained-old-live-mapping-case-count-drift'}
    Write-Host 'TRIPLE_ID_APPLY_CRASH_MAPPING_OVERLAY_MATRIX_PASS cases=11 two_exact_ambiguous_apply_phases=true other_legacy_decisions_unchanged=true zero_authority=true'
}
