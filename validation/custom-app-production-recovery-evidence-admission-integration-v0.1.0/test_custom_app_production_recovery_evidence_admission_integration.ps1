$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/test_custom_app_production_recovery_evidence.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-execution-admission-v0.1.0/custom-app-production-recovery-execution-admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-evidence-admission-integration.ps1')

function Assert-ITrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-IFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-IEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-I($x){return(($x|ConvertTo-Json -Depth 50)|ConvertFrom-Json)}

$script:IFinal=('f'*64);$script:IApply=('a'*64);$script:ICleanup=('c'*64)
$script:INormal=@('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')

function Copy-IntegrationTreeV010 {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $dst=[IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-Path -LiteralPath $src -PathType Container)){throw 'integration-copy-source-missing'}
    if(Test-Path -LiteralPath $dst){throw 'integration-copy-destination-exists'}
    $srcItem=Get-Item -LiteralPath $src -Force -ErrorAction Stop;if(($srcItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'integration-copy-source-reparse-point'}
    [IO.Directory]::CreateDirectory($dst)|Out-Null
    foreach($dir in @(Get-ChildItem -LiteralPath $src -Force -Directory -Recurse -ErrorAction Stop|Sort-Object FullName)){
        if(($dir.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'integration-copy-source-contains-reparse-point'}
        $rel=$dir.FullName.Substring($src.Length).TrimStart('\','/');if(-not[string]::IsNullOrWhiteSpace($rel)){[IO.Directory]::CreateDirectory((Join-Path $dst $rel))|Out-Null}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $src -Force -File -Recurse -ErrorAction Stop|Sort-Object FullName)){
        if(($file.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'integration-copy-source-contains-reparse-point'}
        $rel=$file.FullName.Substring($src.Length).TrimStart('\','/');$target=Join-Path $dst $rel;$parent=[IO.Path]::GetDirectoryName($target);if(-not[string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($file.FullName,$target,$false)
    }
    $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $src;$after=Get-CustomAppUpdateTreeSnapshotV010 -Root $dst
    if([string]$after.tree_sha256-cne[string]$before.tree_sha256-or[int]$after.file_count-ne[int]$before.file_count-or[int64]$after.total_bytes-ne[int64]$before.total_bytes){throw 'integration-copy-tree-verification-failed'}
    return $after
}

function Initialize-IntegrationCrashArtifactsV010 {
    param([Parameter(Mandatory=$true)]$F)
    if(Test-Path -LiteralPath $F.txn){throw 'integration-transaction-root-unexpectedly-exists'}
    [IO.Directory]::CreateDirectory([string]$F.txn)|Out-Null
    $txnItem=Get-Item -LiteralPath $F.txn -Force -ErrorAction Stop;if(($txnItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'integration-transaction-root-reparse-point'}
    $oldLive=Join-Path $F.txn 'old-live';$copied=Copy-IntegrationTreeV010 -Source ([string]$F.prepared.app_backup_path) -Destination $oldLive
    if([string]$copied.tree_sha256-cne[string]$F.prepared.app_backup_tree_sha256-or[int]$copied.file_count-ne[int]$F.prepared.app_backup_file_count-or[int64]$copied.total_bytes-ne[int64]$F.prepared.app_backup_total_bytes){throw 'integration-old-live-not-exact-pre-swap-backup'}
    return [pscustomobject]@{transaction_root=[string]$F.txn;old_live_path=$oldLive;tree_sha256=[string]$copied.tree_sha256;file_count=[int]$copied.file_count;total_bytes=[int64]$copied.total_bytes}
}

function Advance-IntegrationJournalV010 {
    param($F,[Parameter(Mandatory=$true)][string]$Target)
    $cur=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $F.allowed -StoreDirectory $F.store
    if(-not[bool]$cur.ok){throw ('integration journal read failed: '+[string]$cur.reason)}
    $base=[DateTimeOffset]::UtcNow.AddMinutes(-1)
    if($Target-in@('rollback-required','rollback-complete')){
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $F.allowed -StoreDirectory $F.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-required' -Now $base.AddSeconds(1)
        if(-not[bool]$cur.ok){throw ('rollback-required append failed: '+[string]$cur.reason)}
        if($Target-ceq'rollback-complete'){$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $F.allowed -StoreDirectory $F.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'rollback-complete' -Now $base.AddSeconds(2);if(-not[bool]$cur.ok){throw ('rollback-complete append failed: '+[string]$cur.reason)}}
        return $cur
    }
    if($Target-ceq'prepared'){return $cur}
    $idx=[array]::IndexOf($script:INormal,$Target);if($idx-lt1){throw ('unsupported integration target '+$Target)}
    for($i=1;$i-le$idx;$i++){
        $phase=[string]$script:INormal[$i];$args=@{AllowedRoot=$F.allowed;StoreDirectory=$F.store;ExpectedRevision=[int64]$cur.revision;ExpectedEntrySha256=[string]$cur.entry.entry_sha256;Phase=$phase;Now=$base.AddSeconds($i)}
        if($phase-in@('transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean')){$args.FinalizationFingerprint=$script:IFinal}
        if($phase-in@('apply-verified','cleanup-starting','committed-clean')){$args.ApplyResultFingerprint=$script:IApply}
        if($phase-ceq'committed-clean'){$args.CleanupResultFingerprint=$script:ICleanup}
        $cur=Append-CustomAppProductionCrashJournalPhaseV010 @args;if(-not[bool]$cur.ok){throw ("append failed phase=$phase reason=$([string]$cur.reason)")}
    }
    return $cur
}

function New-IntegrationFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$Phase,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('2'*32))
    $f=New-RecoveryEvidenceFixtureV010 -Label ('integration-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $ew=Write-REFixtureV010 $f;if(-not[bool]$ew.ok){throw ('integration evidence write failed: '+[string]$ew.reason)}
    $crash=Initialize-IntegrationCrashArtifactsV010 -F $f
    $current=Advance-IntegrationJournalV010 -F $f -Target $Phase
    $plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $f.allowed -StoreDirectory $f.store -ExpectedTransactionId ([string]$f.identity.transaction_id)
    $pc=Test-CustomAppProductionRecoveryPlanV010 $plan;if(-not[bool]$pc.ok){throw ('integration plan invalid: '+[string]$pc.reason)}
    $exeRoot=Join-Path $f.q.x.base 'integration-bin';[IO.Directory]::CreateDirectory($exeRoot)|Out-Null;$exe=Join-Path $exeRoot 'spicetify.exe';[IO.File]::WriteAllText($exe,'fake-spicetify-integration',[Text.UTF8Encoding]::new($false));$exeSha=Get-CustomAppProductionRecoveryPreflightFileSha256V010 $exe
    $pre=Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $f.allowed -StoreDirectory $f.store -ExpectedTransactionId ([string]$f.identity.transaction_id) -Plan $plan -SpicetifyAllowedRoot $f.allowed -SpicetifyPath $exe -ExpectedSpicetifySha256 $exeSha
    if(-not[bool]$pre.ok){throw ('integration preflight failed: '+[string]$pre.reason)}
    return [pscustomobject]@{f=$f;crash=$crash;current=$current;plan=$plan;pre=$pre;exe=$exe;exeSha=$exeSha}
}

function Refresh-IntegrationPreflightV010 {
    param([Parameter(Mandatory=$true)]$Q)
    $fresh=Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -Plan $Q.plan -SpicetifyAllowedRoot $Q.f.allowed -SpicetifyPath $Q.exe -ExpectedSpicetifySha256 $Q.exeSha
    if(-not[bool]$fresh.ok){throw ('integration fresh preflight failed: '+[string]$fresh.reason)}
    return $fresh
}

function Invoke-IntegrationFixtureV010 {
    param($Q,[AllowNull()]$Plan=$null,[AllowNull()]$Preflight=$null,[AllowNull()][string]$ExeSha=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if($null-eq$Plan){$Plan=$Q.plan};if($null-eq$Preflight){$Preflight=$Q.pre.receipt};if([string]::IsNullOrWhiteSpace($ExeSha)){$ExeSha=$Q.exeSha}
    return Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -Plan $Plan -PreflightReceipt $Preflight -SpicetifyAllowedRoot $Q.f.allowed -SpicetifyPath $Q.exe -ExpectedSpicetifySha256 $ExeSha -Now $At
}
function Assert-IZero($R,[string]$label){$x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R};foreach($p in @('integration_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-IFalse ([bool]$x.$p) "$label authority escaped $p"}}

$count=0
$cases=@(
    @('live-moved-to-old','exact-app-persistence-restore',$true,$false,$false),
    @('candidate-live','exact-app-persistence-restore',$true,$false,$false),
    @('transaction-finalized','exact-app-persistence-restore',$true,$false,$false),
    @('apply-starting','exact-app-persistence-restore-and-recovery-apply',$true,$true,$false),
    @('apply-returned-success-pending-verification','exact-app-persistence-restore-and-recovery-apply',$true,$true,$false),
    @('rollback-required','exact-app-persistence-restore-and-recovery-apply',$true,$true,$false),
    @('apply-verified','idempotent-housekeeping',$false,$false,$true),
    @('cleanup-starting','idempotent-housekeeping',$false,$false,$true),
    @('prepared','no-action',$false,$false,$false),
    @('committed-clean','no-action',$false,$false,$false),
    @('rollback-complete','no-action',$false,$false,$false),
    @('atomic-mutation-starting','manual-inspection',$false,$false,$false)
)
$i=0
foreach($c in $cases){$i++;$phase=$c[0];$q=New-IntegrationFixtureV010 -Label ($phase.Replace('-','')) -Phase $phase -Nonce (($i.ToString('x'))*32).Substring(0,32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-IntegrationFixtureV010 -Q $q -At $at;Assert-ITrue ([bool]$r.ok) "$phase integration denied: $([string]$r.reason)";Assert-IZero $r $phase;$ck=Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 -Receipt $r.receipt -Now $at.AddSeconds(1);Assert-ITrue ([bool]$ck.ok) "$phase receipt invalid: $([string]$ck.reason)";Assert-IEq $r.receipt.executor_class $c[1] "$phase executor";Assert-ITrue ([bool]$r.receipt.requires_exact_restore-eq[bool]$c[2]) "$phase restore";Assert-ITrue ([bool]$r.receipt.requires_recovery_apply-eq[bool]$c[3]) "$phase apply";Assert-ITrue ([bool]$r.receipt.requires_idempotent_cleanup-eq[bool]$c[4]) "$phase cleanup";if([bool]$c[2]){Assert-ITrue ([bool]$r.receipt.backup_integrity_verified) "$phase backup proof missing"}else{Assert-IFalse ([bool]$r.receipt.backup_integrity_verified) "$phase unnecessary backup proof"};$count++}

$future=New-IntegrationFixtureV010 -Label 'future' -Phase 'candidate-live' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('d'*32);$r=Invoke-IntegrationFixtureV010 $future;Assert-ITrue ([bool]$r.ok) ('future app integration denied: '+[string]$r.reason);Assert-IEq $r.receipt.name 'future-app' 'future app identity';$count++

$appDrift=New-IntegrationFixtureV010 'app-backup-drift' 'candidate-live' -Nonce ('e'*32);[IO.File]::AppendAllText((Join-Path $appDrift.f.prepared.app_backup_path 'index.js'),"// backup drift`n",[Text.UTF8Encoding]::new($false));$stale=Invoke-IntegrationFixtureV010 $appDrift;Assert-IFalse ([bool]$stale.ok) 'stale app backup drift preflight accepted';Assert-ITrue ([string]$stale.reason-like'recovery-integration-fresh-admission-denied:*fresh-preflight-fingerprint-mismatch*') 'stale app backup drift reason';$fresh=Refresh-IntegrationPreflightV010 $appDrift;$r=Invoke-IntegrationFixtureV010 -Q $appDrift -Preflight $fresh.receipt;Assert-IFalse ([bool]$r.ok) 'fresh app backup drift escaped durable evidence';Assert-IEq $r.reason 'recovery-integration-app-backup-integrity-mismatch' 'app backup drift reason';$count++

$persistDrift=New-IntegrationFixtureV010 'persistence-backup-drift' 'rollback-required' -Nonce ('f'*32);$manifest=Get-Content -LiteralPath (Join-Path $persistDrift.f.prepared.persistence_backup_path 'guard-manifest.json') -Raw|ConvertFrom-Json;$existing=@($manifest.before.surfaces|Where-Object{[bool]$_.exists}|Select-Object -First 1);if($existing.Count-ne1){throw 'no existing persistence surface to tamper'};$surfacePath=Join-Path (Join-Path $persistDrift.f.prepared.persistence_backup_path 'surfaces') ([string]$existing[0].id);if([string]$existing[0].kind-ceq'Directory'){$leaf=Get-ChildItem -LiteralPath $surfacePath -File -Recurse|Select-Object -First 1;if($null-eq$leaf){throw 'no persistence backup leaf to tamper'};[IO.File]::AppendAllText($leaf.FullName,'tamper',[Text.UTF8Encoding]::new($false))}else{[IO.File]::AppendAllText($surfacePath,'tamper',[Text.UTF8Encoding]::new($false))};$stale=Invoke-IntegrationFixtureV010 $persistDrift;Assert-IFalse ([bool]$stale.ok) 'stale persistence backup drift preflight accepted';Assert-ITrue ([string]$stale.reason-like'recovery-integration-fresh-admission-denied:*fresh-preflight-fingerprint-mismatch*') 'stale persistence backup drift reason';$fresh=Refresh-IntegrationPreflightV010 $persistDrift;$r=Invoke-IntegrationFixtureV010 -Q $persistDrift -Preflight $fresh.receipt;Assert-IFalse ([bool]$r.ok) 'fresh persistence backup drift escaped durable evidence';Assert-ITrue ([string]$r.reason-like'recovery-integration-persistence-backup-invalid:*surface-mismatch-*') 'persistence backup drift reason';$count++

$house=New-IntegrationFixtureV010 'housekeeping-missing-backups' 'apply-verified' -Nonce ('1'*32);foreach($p in @($house.f.prepared.app_backup_path,$house.f.prepared.persistence_backup_path)){if(Test-Path $p){[IO.Directory]::Delete($p,$true)}};$r=Invoke-IntegrationFixtureV010 $house;Assert-IFalse ([bool]$r.ok) 'housekeeping missing backups bypassed fresh admission';Assert-ITrue ([string]$r.reason-like'recovery-integration-fresh-admission-denied:*') 'housekeeping missing backup reason';Assert-IZero $r 'housekeeping-missing-backups';$count++

$eTamper=New-IntegrationFixtureV010 'evidence-tamper' 'candidate-live' -Nonce ('3'*32);$er=Read-REFixtureV010 $eTamper.f;$obj=[IO.File]::ReadAllText([string]$er.path,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$obj.persistence_fingerprint=('0'*64);$obj.evidence_fingerprint=Get-CustomAppProductionRecoveryEvidenceSha256V010 (Get-CustomAppProductionRecoveryEvidenceMaterialV010 $obj);[IO.File]::WriteAllText([string]$er.path,($obj|ConvertTo-Json -Depth 50 -Compress),[Text.UTF8Encoding]::new($false));$r=Invoke-IntegrationFixtureV010 $eTamper;Assert-IFalse ([bool]$r.ok) 'evidence tamper+rehash accepted';Assert-ITrue ([string]$r.reason-like'recovery-integration-evidence-read-denied:*') 'evidence tamper reason';$count++

$phaseDrift=New-IntegrationFixtureV010 'phase-drift' 'prepared' -Nonce ('4'*32);$oldPlan=Copy-I $phaseDrift.plan;$oldPre=Copy-I $phaseDrift.pre.receipt;$cur=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $phaseDrift.f.allowed -StoreDirectory $phaseDrift.f.store;$cur=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $phaseDrift.f.allowed -StoreDirectory $phaseDrift.f.store -ExpectedRevision ([int64]$cur.revision) -ExpectedEntrySha256 ([string]$cur.entry.entry_sha256) -Phase 'atomic-mutation-starting' -Now ([DateTimeOffset]::UtcNow.AddSeconds(-5));$r=Invoke-IntegrationFixtureV010 -Q $phaseDrift -Plan $oldPlan -Preflight $oldPre;Assert-IFalse ([bool]$r.ok) 'phase drift accepted';Assert-ITrue ([string]$r.reason-like'recovery-integration-fresh-admission-denied:*') 'phase drift reason';$count++

$wrongExe=New-IntegrationFixtureV010 'wrong-exe' 'apply-starting' -Nonce ('5'*32);$r=Invoke-IntegrationFixtureV010 -Q $wrongExe -ExeSha ('9'*64);Assert-IFalse ([bool]$r.ok) 'wrong executable pin accepted';Assert-ITrue ([string]$r.reason-like'recovery-integration-fresh-admission-denied:*') 'wrong exe reason';$count++

$receiptTamper=New-IntegrationFixtureV010 'receipt-tamper' 'candidate-live' -Nonce ('6'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-IntegrationFixtureV010 -Q $receiptTamper -At $at;Assert-ITrue ([bool]$good.ok) 'receipt tamper setup failed';$bad=Copy-I $good.receipt;$bad.restore_authorized=$true;$bad.integration_fingerprint=Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationSha256V010 (Get-CustomAppProductionRecoveryEvidenceAdmissionIntegrationMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-IFalse ([bool]$ck.ok) 'authority-tampered integration receipt accepted';Assert-ITrue ([string]$ck.reason-like'*authority-escaped-restore_authorized*') 'receipt authority reason';$count++

$expiry=New-IntegrationFixtureV010 'expiry' 'candidate-live' -Nonce ('7'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-IntegrationFixtureV010 -Q $expiry -At $at;$ck=Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 -Receipt $good.receipt -Now $at.AddSeconds(11);Assert-IFalse ([bool]$ck.ok) 'expired integration receipt accepted';Assert-IEq $ck.reason 'recovery-integration-expired' 'expiry reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_EVIDENCE_ADMISSION_INTEGRATION_MATRIX_PASS total=$count"
