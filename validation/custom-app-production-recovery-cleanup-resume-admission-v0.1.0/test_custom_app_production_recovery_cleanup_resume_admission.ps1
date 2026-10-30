$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/test_custom_app_production_recovery_evidence_admission_integration.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-cleanup-resume-admission.ps1')

function Assert-CRTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-CRFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-CREq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-CR($x){return(($x|ConvertTo-Json -Depth 50)|ConvertFrom-Json)}

function Convert-ToCleanupStartingFilesystemV010 {
    param([Parameter(Mandatory=$true)]$Q)
    $live=[string]$Q.f.q.x.live
    if(Test-Path -LiteralPath $live){[IO.Directory]::Delete($live,$true)}
    [void](Copy-IntegrationTreeV010 -Source ([string]$Q.f.prepared.stage_path) -Destination $live)
    $runtime=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Q.f.identity.name) -AppPath $live
    if(-not[bool]$runtime.safe -or -not[bool]$runtime.installable -or [string]$runtime.tree_sha256 -cne [string]$Q.f.prepared.stage_tree_sha256){throw 'cleanup-resume fixture live does not equal staged runtime'}
    if(Test-Path -LiteralPath $Q.f.txn){[IO.Directory]::Delete([string]$Q.f.txn,$true)}
    if(Test-Path -LiteralPath $Q.f.txn){throw 'cleanup-resume fixture transaction root remained'}
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming
    if([string]$persist.fingerprint -cne [string]$Q.f.prepared.persistence_fingerprint){throw 'cleanup-resume fixture protected persistence drifted'}
    return $Q
}

function New-CleanupResumeFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('8'*32))
    $q=New-IntegrationFixtureV010 -Label ('resume-'+$Label) -Phase 'cleanup-starting' -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    return Convert-ToCleanupStartingFilesystemV010 -Q $q
}

function Invoke-CleanupResumeFixtureV010 {
    param([Parameter(Mandatory=$true)]$Q,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    return Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming -Now $At
}

function Remove-CleanupResumeStageV010 {param($Q) if(Test-Path -LiteralPath $Q.f.prepared.stage_workspace_path){[IO.Directory]::Delete([string]$Q.f.prepared.stage_workspace_path,$true)}}
function Remove-CleanupResumeAppV010 {param($Q) $container=[IO.Path]::GetDirectoryName([string]$Q.f.prepared.app_backup_path);if(Test-Path -LiteralPath $container){[IO.Directory]::Delete($container,$true)}}
function Remove-CleanupResumePersistenceV010 {param($Q) if(Test-Path -LiteralPath $Q.f.prepared.persistence_backup_path){[IO.Directory]::Delete([string]$Q.f.prepared.persistence_backup_path,$true)}}
function Assert-CRZeroAuthorityV010 {param($R,[string]$Label)$x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R};foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-CRFalse ([bool]$x.$f) "$Label authority escaped $f"}}
function Assert-CRSuccessV010 {param($Q,$R,[string]$Stage,[string]$App,[string]$Persist,[string]$Label,[DateTimeOffset]$At)Assert-CRTrue ([bool]$R.ok) "$Label denied: $([string]$R.reason)";Assert-CRZeroAuthorityV010 $R $Label;Assert-CREq $R.receipt.stage_status $Stage "$Label stage status";Assert-CREq $R.receipt.app_backup_status $App "$Label app status";Assert-CREq $R.receipt.persistence_backup_status $Persist "$Label persistence status";$ck=Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 -Receipt $R.receipt -Now $At.AddSeconds(1);Assert-CRTrue ([bool]$ck.ok) "$Label receipt invalid: $([string]$ck.reason)"}

$count=0
$q=New-CleanupResumeFixtureV010 'all-present' -Nonce ('8'*32);$at=[DateTimeOffset]::UtcNow;$beforeStage=Test-Path -LiteralPath $q.f.prepared.stage_workspace_path;$beforeApp=Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$q.f.prepared.app_backup_path));$beforePersist=Test-Path -LiteralPath $q.f.prepared.persistence_backup_path;$r=Invoke-CleanupResumeFixtureV010 -Q $q -At $at;Assert-CRSuccessV010 $q $r 'present-verified' 'present-verified' 'present-verified' 'all-present' $at;Assert-CRTrue ((Test-Path -LiteralPath $q.f.prepared.stage_workspace_path)-eq$beforeStage) 'admission mutated stage';Assert-CRTrue ((Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$q.f.prepared.app_backup_path)))-eq$beforeApp) 'admission mutated app backup';Assert-CRTrue ((Test-Path -LiteralPath $q.f.prepared.persistence_backup_path)-eq$beforePersist) 'admission mutated persistence backup';$count++

$q=New-CleanupResumeFixtureV010 'stage-absent' -Nonce ('9'*32);Remove-CleanupResumeStageV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'already-absent' 'present-verified' 'present-verified' 'stage-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'app-absent' -Nonce ('a'*32);Remove-CleanupResumeAppV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'present-verified' 'already-absent' 'present-verified' 'app-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'persistence-absent' -Nonce ('b'*32);Remove-CleanupResumePersistenceV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'present-verified' 'present-verified' 'already-absent' 'persistence-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'stage-app-absent' -Nonce ('c'*32);Remove-CleanupResumeStageV010 $q;Remove-CleanupResumeAppV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'already-absent' 'already-absent' 'present-verified' 'stage-app-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'stage-persistence-absent' -Nonce ('d'*32);Remove-CleanupResumeStageV010 $q;Remove-CleanupResumePersistenceV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'already-absent' 'present-verified' 'already-absent' 'stage-persistence-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'app-persistence-absent' -Nonce ('e'*32);Remove-CleanupResumeAppV010 $q;Remove-CleanupResumePersistenceV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'present-verified' 'already-absent' 'already-absent' 'app-persistence-absent' $at;$count++
$q=New-CleanupResumeFixtureV010 'all-absent' -Nonce ('f'*32);Remove-CleanupResumeStageV010 $q;Remove-CleanupResumeAppV010 $q;Remove-CleanupResumePersistenceV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'already-absent' 'already-absent' 'already-absent' 'all-absent' $at;$count++

$q=New-CleanupResumeFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('1'*32);Remove-CleanupResumeStageV010 $q;$at=[DateTimeOffset]::UtcNow;$r=Invoke-CleanupResumeFixtureV010 $q $at;Assert-CRSuccessV010 $q $r 'already-absent' 'present-verified' 'present-verified' 'future-app' $at;Assert-CREq $r.receipt.name 'future-app' 'future app identity';$count++

$q=New-CleanupResumeFixtureV010 'transaction-reappeared' -Nonce ('2'*32);[IO.Directory]::CreateDirectory([string]$q.f.txn)|Out-Null;$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'transaction root reappearance accepted';Assert-CREq $r.reason 'cleanup-resume-transaction-root-must-be-absent' 'transaction root reason';Assert-CRZeroAuthorityV010 $r 'transaction-root';$count++
$q=New-CleanupResumeFixtureV010 'live-drift' -Nonce ('3'*32);[IO.File]::AppendAllText((Join-Path $q.f.q.x.live 'index.js'),"// cleanup resume live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'live drift accepted';Assert-CREq $r.reason 'cleanup-resume-live-runtime-not-exact-applied-tree' 'live drift reason';$count++
$q=New-CleanupResumeFixtureV010 'protected-persistence-drift' -Nonce ('4'*32);[IO.File]::AppendAllText((Join-Path $q.f.q.persistence.roaming 'spicetify\config-xpui.ini'),"# cleanup resume drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'protected persistence drift accepted';Assert-CREq $r.reason 'cleanup-resume-protected-persistence-drift' 'persistence drift reason';$count++
$q=New-CleanupResumeFixtureV010 'stage-drift' -Nonce ('5'*32);[IO.File]::AppendAllText((Join-Path $q.f.prepared.stage_path 'index.js'),"// stage drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'stage drift accepted';Assert-CREq $r.reason 'cleanup-resume-stage-tree-mismatch' 'stage drift reason';$count++
$q=New-CleanupResumeFixtureV010 'app-drift' -Nonce ('6'*32);[IO.File]::AppendAllText((Join-Path $q.f.prepared.app_backup_path 'index.js'),"// app backup drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'app backup drift accepted';Assert-CREq $r.reason 'cleanup-resume-app-backup-tree-mismatch' 'app drift reason';$count++
$q=New-CleanupResumeFixtureV010 'persistence-backup-drift' -Nonce ('7'*32);$manifest=Get-Content -LiteralPath (Join-Path $q.f.prepared.persistence_backup_path 'guard-manifest.json') -Raw|ConvertFrom-Json;$surface=@($manifest.before.surfaces|Where-Object{[bool]$_.exists}|Select-Object -First 1);if($surface.Count-ne1){throw 'cleanup resume no persistence surface to tamper'};$surfacePath=Join-Path (Join-Path $q.f.prepared.persistence_backup_path 'surfaces') ([string]$surface[0].id);if([string]$surface[0].kind-ceq'Directory'){$leaf=Get-ChildItem -LiteralPath $surfacePath -File -Recurse|Select-Object -First 1;if($null-eq$leaf){throw 'cleanup resume no persistence leaf'};[IO.File]::AppendAllText($leaf.FullName,'tamper',[Text.UTF8Encoding]::new($false))}else{[IO.File]::AppendAllText($surfacePath,'tamper',[Text.UTF8Encoding]::new($false))};$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'persistence backup drift accepted';Assert-CRTrue ([string]$r.reason-like'cleanup-resume-persistence-backup-invalid:*') 'persistence backup drift reason';$count++

$q=New-IntegrationFixtureV010 -Label 'resume-wrong-phase' -Phase 'apply-verified' -Nonce ('0'*32);$q=Convert-ToCleanupStartingFilesystemV010 -Q $q;$r=Invoke-CleanupResumeFixtureV010 $q;Assert-CRFalse ([bool]$r.ok) 'apply-verified phase accepted as cleanup-starting resume';Assert-CREq $r.reason 'cleanup-resume-phase-not-cleanup-starting' 'wrong phase reason';$count++

$q=New-CleanupResumeFixtureV010 'receipt' -Nonce ('a'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-CleanupResumeFixtureV010 -Q $q -At $at;Assert-CRTrue ([bool]$good.ok) 'receipt setup denied';$bad=Copy-CR $good.receipt;$bad.cleanup_authorized=$true;$bad.resume_admission_fingerprint=Get-CustomAppProductionRecoveryCleanupResumeAdmissionSha256V010 (Get-CustomAppProductionRecoveryCleanupResumeAdmissionMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-CRFalse ([bool]$ck.ok) 'authority-tampered cleanup resume receipt accepted';Assert-CRTrue ([string]$ck.reason-like'*authority-escaped-cleanup_authorized*') 'authority tamper reason';$bad=Copy-CR $good.receipt;$bad.resume_admission_fingerprint=('0'*64);$ck=Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-CRFalse ([bool]$ck.ok) 'fingerprint-tampered cleanup resume receipt accepted';Assert-CREq $ck.reason 'cleanup-resume-receipt-fingerprint-mismatch' 'fingerprint tamper reason';$ck=Test-CustomAppProductionRecoveryCleanupResumeAdmissionReceiptV010 -Receipt $good.receipt -Now $at.AddSeconds(11);Assert-CRFalse ([bool]$ck.ok) 'expired cleanup resume receipt accepted';Assert-CREq $ck.reason 'cleanup-resume-receipt-expired' 'expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_CLEANUP_RESUME_ADMISSION_MATRIX_PASS total=$count"
