$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Exact qualified parent creates and validates a real ZIP and then the standard
# stage executor output. This test creates a THIRD distinct permit AFTER its
# backup copies, never forging a "prepared before" provenance.
. (Join-Path $root 'validation/custom-app-production-prepared-stage-executor-bridge-v0.1.0/test_custom_app_production_prepared_stage_executor_bridge.ps1')
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1')
. (Join-Path $root 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1')
. (Join-Path $root 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-pre-permit-backups-bridge.ps1')

function Assert-PPB([bool]$Condition,[string]$Reason){if(-not$Condition){throw $Reason}}
function Assert-PPBDenied($X,[string]$Label){
    Assert-PPB ($null-ne$X -and -not[bool]$X.ok) ("$Label incorrectly accepted")
    Assert-PPB (-not[bool]$X.apply_authorized -and -not[bool]$X.production_mutation_authorized) ("$Label elevated production authority")
}
function Copy-PPB($X){return ($X|ConvertTo-Json -Depth 100|ConvertFrom-Json)}

$script:PPBRoot=Join-Path $env:RUNNER_TEMP ('pre-permit-backup-'+[Guid]::NewGuid().ToString('N'))
$script:PPBAppRoot=Join-Path $script:PPBRoot 'app'
$script:PPBPersistRoot=Join-Path $script:PPBRoot 'persistence'
$script:PPBLocal=[string]$q.x.f.x.fixture.q.persistence.local
$script:PPBRoaming=[string]$q.x.f.x.fixture.q.persistence.roaming
[IO.Directory]::CreateDirectory($script:PPBRoot)|Out-Null

$script:PPBPreArgs=@{
    Name='tagify';LifecycleRow=$q.bundle.lifecycle;BindingRow=$q.bundle.binding
    StagePath=$script:PSBStage;StageWorkspacePath=$script:PSBWorkspace
    RollbackBackupRoot=$script:PPBAppRoot;PersistenceBackupRoot=$script:PPBPersistRoot
    LocalAppDataRoot=$script:PPBLocal;AppDataRoot=$script:PPBRoaming
    Now=$q.at.AddMilliseconds(-500)
}
function Invoke-PPBPre {
    param([hashtable]$Overrides=$null)
    $x=@{};foreach($k in $script:PPBPreArgs.Keys){$x[$k]=$script:PPBPreArgs[$k]}
    if($null-ne$Overrides){foreach($k in $Overrides.Keys){$x[$k]=$Overrides[$k]}}
    return Invoke-CustomAppProductionPrePermitBackupPreparationV010 @x
}
$count=0
$script:PPBPrepared=Invoke-PPBPre
Assert-PPB ([bool]$script:PPBPrepared.ok) ('pre-permit real byte backup denied: '+[string]$script:PPBPrepared.reason)
Assert-PPB ([bool]$script:PPBPrepared.backups_prepared -and -not[bool]$script:PPBPrepared.production_mutation_authorized) 'pre-permit backup not ready or mutated'
Assert-PPB ([string]$script:PPBPrepared.receipt.remote_tree_sha256 -ceq [string]$script:PSBExtract.tree_sha256) 'backup prepared for wrong remote ZIP'
Assert-PPB ([bool](Test-CustomAppPrePermitBackupsBridgeReceiptV010 -Receipt $script:PPBPrepared.receipt).ok) 'pre-permit receipt invalid'
$count++

$overlap=Invoke-PPBPre -Overrides @{RollbackBackupRoot=(Join-Path $script:PPBLocal 'Spotify')}
Assert-PPBDenied $overlap 'backup root inside Spotify persistence'
$count++
$overlap=Invoke-PPBPre -Overrides @{RollbackBackupRoot=(Join-Path $script:PSBWorkspace 'other')}
Assert-PPBDenied $overlap 'backup root inside preacquired stage workspace'
$count++
$removed=Copy-PPB $q.bundle.lifecycle;$removed.user_removed=$true
Assert-PPBDenied (Invoke-PPBPre -Overrides @{LifecycleRow=$removed}) 'pre-permit user removal'
$count++

# Fresh third new-cycle permit is issued only AFTER actual backup creation.
$prior3=Invoke-DINPV010 $q
Assert-PPB ([bool]$prior3.ok) ('pre-backup third-cycle readiness denied: '+[string]$prior3.reason)
$f3=[pscustomobject]@{q=$q;prior=$prior3.receipt;live=$live;new_id=(Get-DINPIANewTransactionId 'prebackup-third-new-cycle')}
$a3=Invoke-DINPIAV010 -F $f3
Assert-PPB ([bool]$a3.ok) ('third-cycle admission denied: '+[string]$a3.reason)
$ic3=[pscustomobject]@{f=$f3;admission=$a3.receipt}
$script:PPBIssuer=Invoke-DINPIIssuerV010 -Q $ic3
Assert-PPB ([bool]$script:PPBIssuer.ok) ('third-cycle issuer denied: '+[string]$script:PPBIssuer.reason)
$rc3=[pscustomobject]@{i=$ic3;issuer=$script:PPBIssuer;state=(New-CustomAppProductionPermitReservationStateV010);at=$q.at.AddSeconds(1)}
$res3=Invoke-DINPRV010 -Q $rc3
Assert-PPB ([bool]$res3.ok) ('third-cycle reservation denied: '+[string]$res3.reason)
$rs3=Join-Path $q.x.f.trust ('prebackup-reservation-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $rs3 'history'))|Out-Null
$rp3=[pscustomobject]@{q=$rc3;reservation=$res3;store=$rs3;at=$rc3.at.AddMilliseconds(500)}
$dur3=Invoke-DINPPV010 -P $rp3 -ReservationResult $res3 -IssuerResult $script:PPBIssuer
Assert-PPB ([bool]$dur3.ok) ('third-cycle durable reservation denied: '+[string]$dur3.reason)
$consume3=Invoke-DINCV010 -P $rp3 -Persist $dur3 -Issuer $script:PPBIssuer -At $rp3.at.AddMilliseconds(100)
Assert-PPB ([bool]$consume3.ok) ('third-cycle one-time consumption denied: '+[string]$consume3.reason)
$cs3=Join-Path $q.x.f.trust ('prebackup-consumption-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $cs3 'history'))|Out-Null
$cf3=[pscustomobject]@{p=$rp3;candidate=$consume3;store=$cs3;at=$rp3.at.AddMilliseconds(200)}
$script:PPBSaved=Invoke-DNCPV010 -F $cf3 -Candidate $consume3 -ReservationPersistence $dur3 -Issuer $script:PPBIssuer
Assert-PPB ([bool]$script:PPBSaved.ok) ('third-cycle durable consumption denied: '+[string]$script:PPBSaved.reason)
$script:PPBAt=$cf3.at.AddMilliseconds(100)
$script:PPBStart=Invoke-TDSV010 -F $cf3 -Persistence $script:PPBSaved -Issuer $script:PPBIssuer -Permit $script:PPBIssuer.permit -Key $script:DINPIKey -At $script:PPBAt
Assert-PPB ([bool]$script:PPBStart.ok -and [bool]$script:PPBStart.staging_eligible) ('third-cycle signed start denied: '+[string]$script:PPBStart.reason)
$stageArgs=@{};foreach($k in $script:PSBArgs.Keys){$stageArgs[$k]=$script:PSBArgs[$k]}
$stageArgs.IssuerResult=$script:PPBIssuer;$stageArgs.ExecutorStartResult=$script:PPBStart
$stageArgs.ConsumptionStoreDirectory=$cf3.store
$stageArgs.Now=$script:PPBAt;$stageArgs.PostStageNow=$script:PPBAt.AddMilliseconds(100)
$script:PPBStageResult=Invoke-CustomAppProductionPreparedStageExecutorBridgeV010 @stageArgs
Assert-PPB ([bool]$script:PPBStageResult.ok) ('third-cycle prepared stage executor denied: '+[string]$script:PPBStageResult.reason)
$count++

$script:PPBHandoffArgs=@{
    PreparedBackupResult=$script:PPBPrepared;StageExecutorResult=$script:PPBStageResult.stage_result
    IssuerResult=$script:PPBIssuer;ExecutorStartResult=$script:PPBStart
    Name='tagify';LifecycleRow=$q.bundle.lifecycle;ProvenanceRow=$q.bundle.provenance
    BindingRow=$q.bundle.binding;AllowedRoot=$script:BRHAllowedRoot
    ConsumptionStoreDirectory=[string]$cf3.store
    LocalAppDataRoot=$script:PPBLocal;AppDataRoot=$script:PPBRoaming
    SessionKey=$script:DINPIKey;CurrentBaseline=$live.baseline
    ShadowProtocolQualification=$live.shadow;LiveAttestedQualification=$live.live
    Now=$script:PPBAt;PostCheckNow=$script:PPBAt.AddMilliseconds(250)
}
# CurrentBaseline is deliberately not an input on the downstream handoff:
# it must take a fresh live baseline itself before every acceptance.
[void]$script:PPBHandoffArgs.Remove('CurrentBaseline')
function Invoke-PPBHandoff {
    param([hashtable]$Overrides=$null)
    $p=@{};foreach($key in $script:PPBHandoffArgs.Keys){$p[$key]=$script:PPBHandoffArgs[$key]}
    if($null-ne$Overrides){foreach($key in $Overrides.Keys){$p[$key]=$Overrides[$key]}}
    return Invoke-CustomAppProductionPrePermitBackupsHandoffV010 @p
}
$script:PPBValid=Invoke-PPBHandoff
Assert-PPB ([bool]$script:PPBValid.ok) ('pre-issued backups standard pre-apply result denied: '+[string]$script:PPBValid.reason)
Assert-PPB ([bool]$script:PPBValid.prepermit_backup_verified_again -and -not[bool]$script:PPBValid.apply_authorized) 'pre-issued backups were not verified or gained authority'
$standard=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $script:PPBValid.result
Assert-PPB ([bool]$standard.ok) ('exact standard prepared backup contract invalid: '+[string]$standard.reason)
Assert-PPB ([string]$script:PPBValid.result.stage_result_fingerprint -ceq [string]$script:PPBStageResult.stage_result.result_fingerprint) 'standard pre-apply receipt stage transaction drift'
$count++

$bad=Copy-PPB $script:PPBPrepared;$bad.receipt.preparation_fingerprint=('0'*64)
Assert-PPBDenied (Invoke-PPBHandoff -Overrides @{PreparedBackupResult=$bad}) 'tampered pre-permit preparation receipt'
$count++
$bad=Copy-PPB $script:PPBPrepared;$bad.receipt.prepared_at=$q.at.AddSeconds(3).ToUniversalTime().ToString('o')
$bad.receipt.preparation_fingerprint=Get-CustomAppProductionPreApplySha256V010 -Text (Get-CustomAppPrePermitBackupsBridgeReceiptMaterialV010 -Receipt $bad.receipt)
Assert-PPBDenied (Invoke-PPBHandoff -Overrides @{PreparedBackupResult=$bad}) 'chronology violation despite valid unkeyed receipt hash'
$count++
Assert-PPBDenied (Invoke-PPBHandoff -Overrides @{SessionKey=[byte[]](33..64)}) 'wrong ephemeral HMAC signing key'
$count++
Assert-PPBDenied (Invoke-PPBHandoff -Overrides @{Now=$script:PPBAt.AddSeconds(9);PostCheckNow=$script:PPBAt.AddSeconds(9)}) 'expired start eligibility'
$count++

$backupFile=Join-Path ([string]$script:PPBPrepared.receipt.app_backup_path) 'index.js'
$beforeBackup=[IO.File]::ReadAllBytes($backupFile)
try{
    [IO.File]::AppendAllText($backupFile,'tampered-prepermit-app-backup')
    Assert-PPBDenied (Invoke-PPBHandoff) 'app backup changed after signing'
}finally{[IO.File]::WriteAllBytes($backupFile,$beforeBackup)}
$count++

$manifestFile=Join-Path ([string]$script:PPBPrepared.receipt.persistence_backup_path) 'guard-manifest.json'
$beforeGuard=[IO.File]::ReadAllBytes($manifestFile)
try{
    $m=Get-Content -LiteralPath $manifestFile -Raw|ConvertFrom-Json
    $m.before.fingerprint=('0'*64)
    [IO.File]::WriteAllText($manifestFile,($m|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    Assert-PPBDenied (Invoke-PPBHandoff) 'Spotify persistence guard fingerprint changed after signing'
}finally{[IO.File]::WriteAllBytes($manifestFile,$beforeGuard)}
$count++

$liveFile=Join-Path ([string]$script:PPBPrepared.receipt.live_path) 'index.js'
$beforeLive=[IO.File]::ReadAllBytes($liveFile)
try{
    [IO.File]::AppendAllText($liveFile,'live-changed-after-backup')
    Assert-PPBDenied (Invoke-PPBHandoff) 'live app changed after pre-permit backup'
}finally{[IO.File]::WriteAllBytes($liveFile,$beforeLive)}
$count++

$badBinding=Copy-PPB $q.bundle.binding
$badBinding.auto_install_authorized=$true
Assert-PPBDenied (Invoke-PPBHandoff -Overrides @{BindingRow=$badBinding}) 'binding auto-install authority escalated after backup'
$count++

$again=Invoke-PPBHandoff
Assert-PPB ([bool]$again.ok) ('post-tamper backup restore did not recover: '+[string]$again.reason)
Assert-PPB ([string]$again.result.preparation_fingerprint -ceq [string]$script:PPBValid.result.preparation_fingerprint) 'read-only revalidation changed standard prepared fingerprint'
$count++

if($count-ne15){throw "pre-permit backup bridge proof count=$count expected=15"}
Write-Host "CUSTOM_APP_PRODUCTION_PRE_PERMIT_BACKUPS_BRIDGE_PASS cases=$count byte_real_backup_before_new_permit=true app_and_Spotify_persistence_snapshot_exact=true old_generic_preapply_receipt_compatible=true no_post_permit_copy=true changed_live_backup_and_signing_key_denied=true zero_authority=true"
