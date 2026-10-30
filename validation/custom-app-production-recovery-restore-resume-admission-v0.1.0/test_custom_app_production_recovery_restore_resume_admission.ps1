$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/test_custom_app_production_recovery_evidence_admission_integration.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-restore-resume-admission.ps1')

function Assert-RRTrue([bool]$v,[string]$m){if(-not $v){throw $m}}
function Assert-RRFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-RREq($a,$b,[string]$m){if([string]$a -cne [string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-RR($x){return (($x | ConvertTo-Json -Depth 50) | ConvertFrom-Json)}
function Remove-RRPath([string]$Path){if(Test-Path -LiteralPath $Path){[IO.Directory]::Delete($Path,$true)}}

function Set-RRLiveStage($Q){
    $live=[string]$Q.f.q.x.live
    Remove-RRPath $live
    [void](Copy-IntegrationTreeV010 -Source ([string]$Q.f.prepared.stage_path) -Destination $live)
    $r=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Q.f.identity.name) -AppPath $live
    if(-not [bool]$r.safe -or -not [bool]$r.installable -or [string]$r.tree_sha256 -cne [string]$Q.f.prepared.stage_tree_sha256){throw 'restore-resume fixture failed to set exact candidate live'}
}

function Add-RRCandidate($Q){
    $candidate=Join-Path ([string]$Q.f.txn) 'candidate'
    if(Test-Path -LiteralPath $candidate){throw 'restore-resume fixture candidate already exists'}
    [void](Copy-IntegrationTreeV010 -Source ([string]$Q.f.prepared.stage_path) -Destination $candidate)
    return $candidate
}

function New-RRFixtureV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)][ValidateSet('default','live-moved-before-candidate','live-moved-after-candidate','candidate-before-finalize','candidate-after-finalize','finalized','rollback-live-absent','rollback-live-stage-txn','rollback-live-stage-no-txn')][string]$State='default',
        [string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('4'*32)
    )
    $q=New-IntegrationFixtureV010 -Label ('restore-resume-'+$Label) -Phase $Phase -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    switch($State){
        'default' {}
        'live-moved-before-candidate' {[void](Add-RRCandidate $q); Remove-RRPath ([string]$q.f.q.x.live)}
        'live-moved-after-candidate' {Set-RRLiveStage $q}
        'candidate-before-finalize' {Set-RRLiveStage $q}
        'candidate-after-finalize' {Set-RRLiveStage $q; Remove-RRPath ([string]$q.f.txn)}
        'finalized' {Set-RRLiveStage $q; Remove-RRPath ([string]$q.f.txn)}
        'rollback-live-absent' {[void](Add-RRCandidate $q); Remove-RRPath ([string]$q.f.q.x.live)}
        'rollback-live-stage-txn' {Set-RRLiveStage $q}
        'rollback-live-stage-no-txn' {Set-RRLiveStage $q; Remove-RRPath ([string]$q.f.txn)}
    }
    return $q
}

function Invoke-RRFixtureV010 {
    param([Parameter(Mandatory=$true)]$Q,[AllowNull()][string]$ExeSha=$null,[bool]$OmitPin=$false,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if([string]::IsNullOrWhiteSpace($ExeSha)){$ExeSha=[string]$Q.exeSha}
    if($OmitPin){
        return Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming -Now $At
    }
    return Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming -SpicetifyAllowedRoot $Q.f.allowed -SpicetifyPath $Q.exe -ExpectedSpicetifySha256 $ExeSha -Now $At
}

function Assert-RRZeroAuthorityV010 {
    param($R,[string]$Label)
    $x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R}
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-RRFalse ([bool]$x.$f) "$Label authority escaped $f"}
}

function Assert-RRSuccessV010 {
    param($Q,$R,[string]$Live,[string]$Txn,[bool]$Apply,[string]$Label,[DateTimeOffset]$At)
    Assert-RRTrue ([bool]$R.ok) "$Label denied: $([string]$R.reason)"
    Assert-RRZeroAuthorityV010 $R $Label
    Assert-RREq $R.receipt.live_state $Live "$Label live state"
    Assert-RREq $R.receipt.transaction_status $Txn "$Label txn state"
    Assert-RRTrue ([bool]$R.receipt.requires_recovery_apply -eq $Apply) "$Label recovery apply mapping"
    Assert-RRTrue ([bool]$R.receipt.restore_resume_eligible) "$Label not eligible"
    Assert-RRTrue ([bool]$R.receipt.requires_exact_restore) "$Label exact restore lost"
    $ck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $R.receipt -Now $At.AddSeconds(1)
    Assert-RRTrue ([bool]$ck.ok) "$Label receipt invalid: $([string]$ck.reason)"
}

$count=0
$q=New-RRFixtureV010 -Label 'live-moved-before-candidate' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('1'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'absent-after-live-move' 'present-verified' $false 'live-moved-before-candidate' $at; Assert-RREq $r.receipt.transaction_old_status 'present-verified' 'live-moved old'; Assert-RREq $r.receipt.transaction_candidate_status 'present-verified' 'live-moved candidate'; $count++
$q=New-RRFixtureV010 -Label 'live-moved-after-candidate' -Phase 'live-moved-to-old' -State 'live-moved-after-candidate' -Nonce ('2'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'present-verified' $false 'live-moved-after-candidate' $at; Assert-RREq $r.receipt.transaction_candidate_status 'absent' 'live-moved candidate should be moved'; $count++
$q=New-RRFixtureV010 -Label 'candidate-before-finalize' -Phase 'candidate-live' -State 'candidate-before-finalize' -Nonce ('3'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'present-verified' $false 'candidate-before-finalize' $at; $count++
$q=New-RRFixtureV010 -Label 'candidate-after-finalize' -Phase 'candidate-live' -State 'candidate-after-finalize' -Nonce ('4'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'already-absent' $false 'candidate-after-finalize' $at; $count++

foreach($phase in @('transaction-finalized','apply-starting','apply-returned-success-pending-verification')){
    $nonce=$(if($phase -ceq 'transaction-finalized'){('5'*32)}elseif($phase -ceq 'apply-starting'){('6'*32)}else{('7'*32)})
    $q=New-RRFixtureV010 -Label $phase.Replace('-','') -Phase $phase -State 'finalized' -Nonce $nonce
    $at=[DateTimeOffset]::UtcNow
    $r=Invoke-RRFixtureV010 $q -At $at
    Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'already-absent' ($phase -cne 'transaction-finalized') $phase $at
    $count++
}

$q=New-RRFixtureV010 -Label 'rollback-old-live-txn' -Phase 'rollback-required' -State 'default' -Nonce ('8'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'old-live-exact' 'present-verified' $true 'rollback-old-live-txn' $at; $count++
$q=New-RRFixtureV010 -Label 'rollback-live-absent' -Phase 'rollback-required' -State 'rollback-live-absent' -Nonce ('9'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'absent-after-live-move' 'present-verified' $true 'rollback-live-absent' $at; $count++
$q=New-RRFixtureV010 -Label 'rollback-stage-txn' -Phase 'rollback-required' -State 'rollback-live-stage-txn' -Nonce ('a'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'present-verified' $true 'rollback-stage-txn' $at; $count++
$q=New-RRFixtureV010 -Label 'rollback-stage-no-txn' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('b'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'already-absent' $true 'rollback-stage-no-txn' $at; $count++

$q=New-RRFixtureV010 -Label 'future' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('c'*32); $at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'absent-after-live-move' 'present-verified' $false 'future-app' $at; Assert-RREq $r.receipt.name 'future-app' 'future app identity'; $count++

$q=New-RRFixtureV010 -Label 'persistence-current-drift' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('d'*32)
[IO.File]::AppendAllText((Join-Path $q.f.q.persistence.roaming 'spicetify\config-xpui.ini'),"# recovery current drift`n",[Text.UTF8Encoding]::new($false))
$at=[DateTimeOffset]::UtcNow; $r=Invoke-RRFixtureV010 $q -At $at; Assert-RRSuccessV010 $q $r 'candidate-live-exact' 'already-absent' $true 'persistence-current-drift' $at; Assert-RRFalse ([bool]$r.receipt.current_persistence_matches_durable) 'current persistence drift was hidden'; $count++

$q=New-RRFixtureV010 -Label 'live-moved-missing-txn' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('e'*32); Remove-RRPath ([string]$q.f.txn); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'live-moved missing transaction accepted'; Assert-RREq $r.reason 'restore-resume-live-moved-transaction-state-invalid' 'live-moved missing txn reason'; $count++
$q=New-RRFixtureV010 -Label 'live-moved-missing-candidate' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('f'*32); Remove-RRPath (Join-Path ([string]$q.f.txn) 'candidate'); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'live-moved absent live without candidate accepted'; Assert-RREq $r.reason 'restore-resume-live-moved-filesystem-state-invalid' 'live-moved candidate reason'; $count++
$q=New-RRFixtureV010 -Label 'candidate-old-live' -Phase 'candidate-live' -State 'default' -Nonce ('1'*32); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'candidate-live with old live accepted'; Assert-RREq $r.reason 'restore-resume-candidate-live-runtime-state-invalid' 'candidate old live reason'; $count++
$q=New-RRFixtureV010 -Label 'finalized-txn-present' -Phase 'transaction-finalized' -State 'candidate-before-finalize' -Nonce ('2'*32); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'transaction-finalized with txn accepted'; Assert-RREq $r.reason 'restore-resume-transaction-finalized-filesystem-state-invalid' 'finalized txn reason'; $count++

$q=New-RRFixtureV010 -Label 'live-drift' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('3'*32); [IO.File]::AppendAllText((Join-Path $q.f.q.x.live 'index.js'),"// recovery live drift`n",[Text.UTF8Encoding]::new($false)); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'unrecognized live drift accepted'; Assert-RREq $r.reason 'restore-resume-live-tree-unrecognized' 'live drift reason'; $count++
$q=New-RRFixtureV010 -Label 'txn-extra' -Phase 'rollback-required' -State 'default' -Nonce ('4'*32); [IO.Directory]::CreateDirectory((Join-Path $q.f.txn 'unexpected'))|Out-Null; $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'unexpected transaction child accepted'; Assert-RREq $r.reason 'restore-resume-transaction-root-contents-invalid' 'transaction child reason'; $count++
$q=New-RRFixtureV010 -Label 'old-live-drift' -Phase 'rollback-required' -State 'default' -Nonce ('5'*32); [IO.File]::AppendAllText((Join-Path $q.f.txn 'old-live\index.js'),"// old drift`n",[Text.UTF8Encoding]::new($false)); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'old-live drift accepted'; Assert-RREq $r.reason 'restore-resume-old-live-tree-mismatch' 'old-live drift reason'; $count++
$q=New-RRFixtureV010 -Label 'candidate-drift' -Phase 'rollback-required' -State 'rollback-live-absent' -Nonce ('6'*32); [IO.File]::AppendAllText((Join-Path $q.f.txn 'candidate\index.js'),"// candidate drift`n",[Text.UTF8Encoding]::new($false)); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'candidate drift accepted'; Assert-RREq $r.reason 'restore-resume-candidate-tree-mismatch' 'candidate drift reason'; $count++
$q=New-RRFixtureV010 -Label 'stage-drift' -Phase 'rollback-required' -State 'default' -Nonce ('7'*32); [IO.File]::AppendAllText((Join-Path $q.f.prepared.stage_path 'index.js'),"// retained stage drift`n",[Text.UTF8Encoding]::new($false)); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'retained stage drift accepted'; Assert-RREq $r.reason 'restore-resume-stage-tree-mismatch' 'stage drift reason'; $count++
$q=New-RRFixtureV010 -Label 'app-backup-drift' -Phase 'rollback-required' -State 'default' -Nonce ('8'*32); [IO.File]::AppendAllText((Join-Path $q.f.prepared.app_backup_path 'index.js'),"// backup drift`n",[Text.UTF8Encoding]::new($false)); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'app backup drift accepted'; Assert-RREq $r.reason 'restore-resume-app-backup-integrity-mismatch' 'app backup drift reason'; $count++

$q=New-RRFixtureV010 -Label 'persistence-backup-drift' -Phase 'rollback-required' -State 'default' -Nonce ('9'*32)
$manifest=Get-Content -LiteralPath (Join-Path $q.f.prepared.persistence_backup_path 'guard-manifest.json') -Raw | ConvertFrom-Json
$surface=@($manifest.before.surfaces | Where-Object {[bool]$_.exists} | Select-Object -First 1)
if($surface.Count -ne 1){throw 'restore resume no persistence surface to tamper'}
$surfacePath=Join-Path (Join-Path $q.f.prepared.persistence_backup_path 'surfaces') ([string]$surface[0].id)
if([string]$surface[0].kind -ceq 'Directory'){
    $leaf=Get-ChildItem -LiteralPath $surfacePath -File -Recurse | Select-Object -First 1
    if($null -eq $leaf){throw 'restore resume no persistence leaf'}
    [IO.File]::AppendAllText($leaf.FullName,'tamper',[Text.UTF8Encoding]::new($false))
}else{
    [IO.File]::AppendAllText($surfacePath,'tamper',[Text.UTF8Encoding]::new($false))
}
$r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'persistence backup drift accepted'; Assert-RRTrue ([string]$r.reason -like 'restore-resume-persistence-backup-invalid:*') 'persistence backup reason'; $count++

$q=New-RRFixtureV010 -Label 'wrong-pin' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('a'*32); $r=Invoke-RRFixtureV010 -Q $q -ExeSha ('0'*64); Assert-RRFalse ([bool]$r.ok) 'wrong spicetify pin accepted'; Assert-RRTrue ([string]$r.reason -like 'restore-resume-spicetify-pin-invalid:*') 'wrong pin reason'; $count++
$q=New-RRFixtureV010 -Label 'missing-pin' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('b'*32); $r=Invoke-RRFixtureV010 -Q $q -OmitPin:$true; Assert-RRFalse ([bool]$r.ok) 'missing spicetify pin accepted'; Assert-RREq $r.reason 'restore-resume-spicetify-pin-inputs-missing' 'missing pin reason'; $count++

$q=New-RRFixtureV010 -Label 'wrong-phase' -Phase 'apply-verified' -State 'default' -Nonce ('c'*32); $r=Invoke-RRFixtureV010 $q; Assert-RRFalse ([bool]$r.ok) 'housekeeping phase accepted as restore resume'; Assert-RREq $r.reason 'restore-resume-phase-not-auto-restorable' 'wrong phase reason'; $count++

$q=New-RRFixtureV010 -Label 'receipt' -Phase 'rollback-required' -State 'rollback-live-stage-no-txn' -Nonce ('d'*32)
$at=[DateTimeOffset]::UtcNow
$good=Invoke-RRFixtureV010 -Q $q -At $at
Assert-RRTrue ([bool]$good.ok) 'receipt setup denied'
$bad=Copy-RR $good.receipt; $bad.restore_authorized=$true; $bad.restore_resume_admission_fingerprint=Get-CustomAppProductionRecoveryRestoreResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryRestoreResumeAdmissionMaterialV010 $bad)
$ck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1); Assert-RRFalse ([bool]$ck.ok) 'authority-tampered restore resume receipt accepted'; Assert-RRTrue ([string]$ck.reason -like '*authority-escaped-restore_authorized*') 'authority tamper reason'
$bad=Copy-RR $good.receipt; $bad.restore_resume_admission_fingerprint=('0'*64)
$ck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1); Assert-RRFalse ([bool]$ck.ok) 'fingerprint-tampered restore resume receipt accepted'; Assert-RREq $ck.reason 'restore-resume-receipt-fingerprint-mismatch' 'fingerprint reason'
$ck=Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 -Receipt $good.receipt -Now $at.AddSeconds(11); Assert-RRFalse ([bool]$ck.ok) 'expired restore resume receipt accepted'; Assert-RREq $ck.reason 'restore-resume-receipt-expired' 'expiry reason'; $count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_RESTORE_RESUME_ADMISSION_MATRIX_PASS total=$count"
