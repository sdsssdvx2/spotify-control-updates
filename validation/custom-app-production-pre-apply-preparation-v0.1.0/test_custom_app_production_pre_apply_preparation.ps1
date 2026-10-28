$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay/load the exact validated stage-executor harness first. It leaves the full
# permit/reservation/persistence/admission/staging dependency chain available.
. (Join-Path $root 'validation/custom-app-production-stage-executor-v0.1.0/test_custom_app_production_stage_executor.ps1')

# The validated persistence core expects these production helper contracts. The
# fixture implementations below are intentionally conservative and confined to RUNNER_TEMP.
if(-not (Get-Command Test-PathSafe -CommandType Function -ErrorAction SilentlyContinue)){
    function global:Test-PathSafe {
        param([string]$Path,[ValidateSet('Leaf','Container')][string]$Kind)
        if([string]::IsNullOrWhiteSpace($Path)){return $false}
        if($Kind -ceq 'Leaf'){return (Test-Path -LiteralPath $Path -PathType Leaf)}
        return (Test-Path -LiteralPath $Path -PathType Container)
    }
}
if(-not (Get-Command Copy-TreeSafe -CommandType Function -ErrorAction SilentlyContinue)){
    function global:Copy-TreeSafe {
        param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
        $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        if(-not (Test-Path -LiteralPath $src -PathType Container)){throw 'Copy-TreeSafe source missing.'}
        $si=Get-Item -LiteralPath $src -Force;if(($si.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Copy-TreeSafe source reparse.'}
        if(Test-Path -LiteralPath $Destination){throw 'Copy-TreeSafe destination exists.'}
        [IO.Directory]::CreateDirectory($Destination)|Out-Null
        foreach($item in @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction Stop)){
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Copy-TreeSafe tree reparse.'}
            $rel=$item.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$dst=Join-Path $Destination $rel
            if($item.PSIsContainer){[IO.Directory]::CreateDirectory($dst)|Out-Null;continue}
            $parent=[IO.Path]::GetDirectoryName($dst);if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($item.FullName,$dst,$false)
        }
        return $Destination
    }
}
$global:Version='0.6.5-r17'
$global:DataBackupRoot=Join-Path $env:RUNNER_TEMP 'preapply-unused-default-persistence-backup'
. (Join-Path $root 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1')
. (Join-Path $root 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-pre-apply-preparation.ps1')

function Assert-PreApplyNoAuthorityV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.preparation_is_authority) "$Label preparation authority"
    Assert-False ([bool]$Result.backups_are_authority) "$Label backup authority"
    Assert-True ([bool]$Result.requires_atomic_apply_rollback_executor) "$Label atomic executor requirement missing"
    Assert-True ([bool]$Result.requires_fresh_revalidation_before_apply) "$Label fresh pre-apply requirement missing"
    Assert-False ([bool]$Result.apply_authorized) "$Label apply authority"
    Assert-False ([bool]$Result.live_destination_authorized) "$Label live destination authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function New-PreApplyPersistenceFixtureV010 {
    param([string]$Label)
    $base=Join-Path $env:RUNNER_TEMP ('custom-app-preapply-persistence-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    $local=Join-Path $base 'Local';$roaming=Join-Path $base 'Roaming';$spotify=Join-Path $local 'Spotify'
    foreach($d in @((Join-Path $spotify 'Browser\IndexedDB'),(Join-Path $spotify 'Browser\Local Storage'),(Join-Path $spotify 'Default\Session Storage'),(Join-Path $spotify 'Local Storage'),(Join-Path $roaming 'spicetify'))){[IO.Directory]::CreateDirectory($d)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $spotify 'Browser\IndexedDB\000001.log'),"browser-indexeddb-$Label`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $spotify 'Browser\Local Storage\state.bin'),"browser-local-$Label`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $spotify 'Default\Session Storage\session.bin'),"default-session-$Label`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $spotify 'Local Storage\root.bin'),"root-local-$Label`n",[Text.UTF8Encoding]::new($false))
    [IO.Directory]::CreateDirectory((Join-Path $spotify 'Default'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $spotify 'Default\Preferences'),('{"fixture":"'+$Label+'"}'),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $roaming 'spicetify\config-xpui.ini'),("[Setting]`nfixture=$Label`n"),[Text.UTF8Encoding]::new($false))
    $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $roaming
    [pscustomobject]@{base=$base;local=$local;roaming=$roaming;before=$before}
}

function New-PreApplyFixtureV010 {
    param([string]$Label,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce='89898989898989898989898989898989')
    $x=New-ProductionStageExecutorFixtureV010 -Label ('preapply-'+$Label) -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    # Root .git is deliberately added after permit construction. Runtime baseline excludes
    # root VCS metadata, while the rollback backup must preserve it byte-exactly.
    $git=Join-Path $x.live '.git';[IO.Directory]::CreateDirectory($git)|Out-Null
    [IO.File]::WriteAllText((Join-Path $git 'config'),("[remote `"origin`"]`nurl = https://github.com/$Source.git`n"),[Text.UTF8Encoding]::new($false))
    $stage=Invoke-ProductionStageFixtureV010 -X $x -At $now -PostAt $now.AddSeconds(1)
    if(-not [bool]$stage.ok){throw ('pre-apply fixture stage failed: '+[string]$stage.reason)}
    $p=New-PreApplyPersistenceFixtureV010 $Label
    $prepRoot=Join-Path $x.base 'preapply';$rollback=Join-Path $prepRoot 'rollback-backups';$persist=Join-Path $prepRoot 'persistence-backups'
    [IO.Directory]::CreateDirectory($rollback)|Out-Null;[IO.Directory]::CreateDirectory($persist)|Out-Null
    [pscustomobject]@{x=$x;stage=$stage;persistence=$p;prep_root=$prepRoot;rollback_root=$rollback;persistence_backup_root=$persist}
}

function Invoke-PreApplyFixtureV010 {
    param($Q,[AllowNull()]$StageResult=$null,[AllowNull()]$LifecycleRow=$null,[AllowNull()]$BindingRow=$null,[AllowNull()]$Permit=$null,[byte[]]$SessionKey=$key,[AllowNull()][string]$RollbackRoot=$null,[AllowNull()][string]$PersistenceBackupRoot=$null,[DateTimeOffset]$At=$now.AddSeconds(2))
    if($null -eq $StageResult){$StageResult=$Q.stage.result};if($null -eq $LifecycleRow){$LifecycleRow=$Q.x.f.lifecycle};if($null -eq $BindingRow){$BindingRow=$Q.x.f.binding};if($null -eq $Permit){$Permit=$Q.x.permit};if([string]::IsNullOrWhiteSpace($RollbackRoot)){$RollbackRoot=$Q.rollback_root};if([string]::IsNullOrWhiteSpace($PersistenceBackupRoot)){$PersistenceBackupRoot=$Q.persistence_backup_root}
    Invoke-CustomAppProductionPreApplyPreparationV010 -AllowedRoot $Q.x.store.root -StoreDirectory $Q.x.store.store -ExpectedConsumptionId ([string]$Q.x.consumption.consumption_id) -StageExecutorResult $StageResult -Permit $Permit -Name $Q.x.f.name -LifecycleRow $LifecycleRow -ProvenanceRow $Q.x.f.provenance -BindingRow $BindingRow -ShadowProtocolQualification $Q.x.f.shadow -LiveAttestedQualification $Q.x.f.live -SessionKey $SessionKey -RollbackBackupRoot $RollbackRoot -PersistenceBackupRoot $PersistenceBackupRoot -LocalAppDataRoot $Q.persistence.local -AppDataRoot $Q.persistence.roaming -Now $At
}

function Assert-PreApplyDeniedV010 {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-PreApplyNoAuthorityV010 $Result $Label
}

$count=0
$validQ=New-PreApplyFixtureV010 'valid';$valid=Invoke-PreApplyFixtureV010 $validQ
Assert-True ([bool]$valid.ok) ('valid pre-apply preparation denied: '+[string]$valid.reason);Assert-PreApplyNoAuthorityV010 $valid 'valid'
Assert-True ([bool]$valid.requires_cleanup_if_not_applied) 'valid cleanup requirement missing'
$check=Test-CustomAppProductionPreApplyPreparedResultV010 $valid.result;Assert-True ([bool]$check.ok) ('valid prepared result failed: '+[string]$check.reason)
Assert-True (Test-Path -LiteralPath (Join-Path ([string]$valid.result.app_backup_path) '.git\config') -PathType Leaf) 'rollback backup omitted strong .git provenance'
$gitLive=[IO.File]::ReadAllBytes((Join-Path $validQ.x.live '.git\config'));$gitBackup=[IO.File]::ReadAllBytes((Join-Path ([string]$valid.result.app_backup_path) '.git\config'));Assert-True ([Convert]::ToBase64String($gitLive) -ceq [Convert]::ToBase64String($gitBackup)) 'rollback backup changed .git config bytes'
$persistAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $validQ.persistence.local -AppDataRoot $validQ.persistence.roaming;Assert-True ([string]$persistAfter.fingerprint -ceq [string]$validQ.persistence.before.fingerprint) 'valid preparation changed protected persistence'
$liveAfter=Get-CustomAppLocalRuntimeBaseline -Name $validQ.x.f.name -AppPath $validQ.x.live;Assert-True ([string]$liveAfter.tree_sha256 -ceq [string]$validQ.x.live_baseline.tree_sha256) 'valid preparation changed live runtime'
$count++

$authorityQ=New-PreApplyFixtureV010 'stage-authority' -Nonce (N '9');$tampered=Copy-Deep $authorityQ.stage.result;$tampered.apply_authorized=$true;$tampered.result_fingerprint=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 $tampered);$r=Invoke-PreApplyFixtureV010 $authorityQ $tampered
Assert-PreApplyDeniedV010 $r 'stage-authority-tamper';Assert-True ([string]$r.reason -like 'stage-result-invalid:*apply_authorized-true*') 'stage authority tamper reason drifted';$count++

$keyQ=New-PreApplyFixtureV010 'wrong-key' -Nonce (N 'a');$r=Invoke-PreApplyFixtureV010 -Q $keyQ -SessionKey ([byte[]](33..64));Assert-PreApplyDeniedV010 $r 'wrong-key';Assert-True ([string]$r.reason -like 'pre-apply-admission-denied:*permit-hmac-mismatch*') 'wrong key pre-apply reason drifted';$count++

$removedQ=New-PreApplyFixtureV010 'removed' -Nonce (N 'b');$removed=Copy-Deep $removedQ.x.f.lifecycle;$removed.present=$false;$removed.user_removed=$true;$r=Invoke-PreApplyFixtureV010 -Q $removedQ -LifecycleRow $removed;Assert-PreApplyDeniedV010 $r 'user-removed';Assert-True ([string]$r.reason -like 'pre-apply-live-revalidation-denied:*') 'user removal was not denied by fresh live gate';$count++

$liveDriftQ=New-PreApplyFixtureV010 'live-drift' -Nonce (N 'c');[IO.File]::AppendAllText((Join-Path $liveDriftQ.x.live 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PreApplyFixtureV010 $liveDriftQ;Assert-PreApplyDeniedV010 $r 'live-drift';Assert-True ([string]$r.reason -like 'pre-apply-live-revalidation-denied:*tree-changed*') 'live drift reason drifted';$count++

$stageDriftQ=New-PreApplyFixtureV010 'stage-drift' -Nonce (N 'd');[IO.File]::AppendAllText((Join-Path ([string]$stageDriftQ.stage.result.stage_path) 'index.js'),"// stage drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-PreApplyFixtureV010 $stageDriftQ;Assert-PreApplyDeniedV010 $r 'stage-drift';Assert-True ([string]$r.reason -ceq 'pre-apply-stage-tree-mismatch') 'stage drift reason drifted';$count++

$storeQ=New-PreApplyFixtureV010 'store-drift' -Nonce (N 'e');[IO.File]::WriteAllText((Join-Path $storeQ.x.store.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false));$r=Invoke-PreApplyFixtureV010 $storeQ;Assert-PreApplyDeniedV010 $r 'store-drift';Assert-True ([string]$r.reason -like 'pre-apply-admission-denied:*persisted-consumption-read-denied*') 'store drift reason drifted';$count++

$overlapQ=New-PreApplyFixtureV010 'backup-overlap' -Nonce (N '1');$r=Invoke-PreApplyFixtureV010 -Q $overlapQ -RollbackRoot (Join-Path $overlapQ.x.live 'backup');Assert-PreApplyDeniedV010 $r 'backup-root-overlap';Assert-True ([string]$r.reason -like '*overlap*') 'backup overlap reason drifted';$count++

$futureQ=New-PreApplyFixtureV010 'future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (N '2');$future=Invoke-PreApplyFixtureV010 $futureQ;Assert-True ([bool]$future.ok) ('future app pre-apply denied: '+[string]$future.reason);Assert-PreApplyNoAuthorityV010 $future 'future-app';Assert-True ((Test-CustomAppProductionPreApplyPreparedResultV010 $future.result).ok) 'future app prepared result invalid';$count++

$appTamperQ=New-PreApplyFixtureV010 'app-backup-tamper' -Nonce (N '3');$appPrepared=Invoke-PreApplyFixtureV010 $appTamperQ;Assert-True ([bool]$appPrepared.ok) 'app backup tamper fixture preparation failed';[IO.File]::AppendAllText((Join-Path ([string]$appPrepared.result.app_backup_path) 'index.js'),"// backup tamper`n",[Text.UTF8Encoding]::new($false));$appCheck=Test-CustomAppProductionPreApplyPreparedResultV010 $appPrepared.result;Assert-False ([bool]$appCheck.ok) 'app backup tamper accepted';Assert-True ([string]$appCheck.reason -ceq 'pre-apply-result-app-backup-integrity-mismatch') 'app backup tamper reason drifted';$count++

$persistTamperQ=New-PreApplyFixtureV010 'persistence-backup-tamper' -Nonce (N '4');$persistPrepared=Invoke-PreApplyFixtureV010 $persistTamperQ;Assert-True ([bool]$persistPrepared.ok) 'persistence tamper fixture preparation failed';$manifest=Get-Content -LiteralPath (Join-Path ([string]$persistPrepared.result.persistence_backup_path) 'guard-manifest.json') -Raw|ConvertFrom-Json;$existing=@($manifest.before.surfaces|Where-Object{[bool]$_.exists}|Select-Object -First 1);if($existing.Count-ne 1){throw 'no existing persistence surface to tamper'};$surfacePath=Join-Path (Join-Path ([string]$persistPrepared.result.persistence_backup_path) 'surfaces') ([string]$existing[0].id);if([string]$existing[0].kind -ceq 'Directory'){$leaf=Get-ChildItem -LiteralPath $surfacePath -File -Recurse|Select-Object -First 1;[IO.File]::AppendAllText($leaf.FullName,"tamper",[Text.UTF8Encoding]::new($false))}else{[IO.File]::AppendAllText($surfacePath,"tamper",[Text.UTF8Encoding]::new($false))};$persistCheck=Test-CustomAppProductionPreApplyPreparedResultV010 $persistPrepared.result;Assert-False ([bool]$persistCheck.ok) 'persistence backup tamper accepted';Assert-True ([string]$persistCheck.reason -like 'pre-apply-result-persistence-backup-surface-mismatch-*') 'persistence backup tamper reason drifted';$count++

$stageAfterQ=New-PreApplyFixtureV010 'stage-after-tamper' -Nonce (N '5');$stagePrepared=Invoke-PreApplyFixtureV010 $stageAfterQ;Assert-True ([bool]$stagePrepared.ok) 'stage-after tamper fixture preparation failed';[IO.File]::AppendAllText((Join-Path ([string]$stagePrepared.result.stage_path) 'index.js'),"// later tamper`n",[Text.UTF8Encoding]::new($false));$stageCheck=Test-CustomAppProductionPreApplyPreparedResultV010 $stagePrepared.result;Assert-False ([bool]$stageCheck.ok) 'retained stage tamper accepted';Assert-True ([string]$stageCheck.reason -ceq 'pre-apply-result-stage-integrity-mismatch') 'retained stage tamper reason drifted';$count++

$fingerprintQ=New-PreApplyFixtureV010 'fingerprint-tamper' -Nonce (N '6');$fpPrepared=Invoke-PreApplyFixtureV010 $fingerprintQ;Assert-True ([bool]$fpPrepared.ok) 'fingerprint fixture preparation failed';$fpTamper=Copy-Deep $fpPrepared.result;$fpTamper.preparation_fingerprint=('0'*64);$fpCheck=Test-CustomAppProductionPreApplyPreparedResultV010 $fpTamper;Assert-False ([bool]$fpCheck.ok) 'preparation fingerprint tamper accepted';Assert-True ([string]$fpCheck.reason -ceq 'pre-apply-result-fingerprint-mismatch') 'preparation fingerprint tamper reason drifted';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_PRE_APPLY_PREPARATION_MATRIX_PASS total='+$count)
