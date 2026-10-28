$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-executor-consumption-v0.1.0/test_custom_app_production_executor_consumption.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-consumption-persistence.ps1')

function Assert-PersistNoAuthority {
    param($Result,[string]$Label)
    Assert-False ([bool]$Result.persistence_is_authority) "$Label persistence authority"
    Assert-False ([bool]$Result.executor_may_stage) "$Label stage authority"
    Assert-False ([bool]$Result.executor_may_apply) "$Label apply authority"
    Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"
    Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"
}

function New-PersistenceStoreFixture {
    param([string]$Label)
    $base=Join-Path $env:RUNNER_TEMP ('custom-app-production-consumption-persistence-v010-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    $store=Join-Path $base 'store';$history=Join-Path $store 'history'
    New-Item -ItemType Directory -Force -Path $base,$store,$history|Out-Null
    $init=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $base -StoreDirectory $store -Now $now
    if(-not [bool]$init.ok){throw ('store init failed: '+[string]$init.reason)}
    return [pscustomobject]@{root=$base;store=$store;history=$history;init=$init}
}

function New-PersistableConsumption {
    param($CurrentState,[string]$Nonce,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $fx=New-ConsumptionFixture -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $r=Consume-Fixture $fx $CurrentState ([int64]$CurrentState.revision)
    if(-not [bool]$r.ok){throw ('could not build persistable consumption: '+[string]$r.reason)}
    return [pscustomobject]@{fixture=$fx;result=$r;next_state=$r.next_state}
}

function Assert-ReadFails {
    param([string]$Root,[string]$Store,[string]$ExpectedLike,[string]$Label)
    $failed=$false
    try{[void](Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $Root -StoreDirectory $Store)}catch{$failed=$true;if([string]$_.Exception.Message -notlike $ExpectedLike){throw "$Label wrong failure: $($_.Exception.Message)"}}
    Assert-True $failed "$Label unexpectedly read successfully"
}

$count=0
$s=New-PersistenceStoreFixture 'fresh'
Assert-True ([bool]$s.init.read_after_write_verified) 'init read-after-write verification missing';Assert-PersistNoAuthority $s.init 'init'
$r=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $s.root -StoreDirectory $s.store
Assert-True ([bool]$r.ok -and [int64]$r.revision -eq 0 -and @($r.state.consumptions).Count -eq 0) 'fresh persisted state invalid';Assert-PersistNoAuthority $r 'fresh-read';$count++

$c1=New-PersistableConsumption $r.state '10101010101010101010101010101010'
$p1=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c1.next_state -ExpectedCurrentRevision 0 -Now $now
Assert-True ([bool]$p1.ok -and [bool]$p1.persisted -and [bool]$p1.read_after_write_verified) ('first persist failed: '+[string]$p1.reason);Assert-True ([int64]$p1.revision -eq 1) 'first persist revision drifted';Assert-PersistNoAuthority $p1 'first-persist';$count++

$reload=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $s.root -StoreDirectory $s.store
Assert-True ([bool]$reload.ok -and [int64]$reload.revision -eq 1 -and [bool]$reload.reloaded_from_persistent_store) 'reload after first persist failed';Assert-True (([string]@($reload.state.consumptions)[0].consumption_id) -ceq ([string]$c1.result.consumption_id)) 'reload consumption identity drifted';Assert-PersistNoAuthority $reload 'reload';$count++

$c2=New-PersistableConsumption $reload.state '20202020202020202020202020202020'
$p2=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c2.next_state -ExpectedCurrentRevision 1 -Now $now.AddSeconds(1)
Assert-True ([bool]$p2.ok -and [int64]$p2.revision -eq 2 -and (Get-ChildItem -LiteralPath $s.history -File -Filter '*.json').Count -eq 3) 'second append persistence failed';Assert-PersistNoAuthority $p2 'second-persist';$count++

$stale=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c2.next_state -ExpectedCurrentRevision 0 -Now $now.AddSeconds(2)
Assert-False ([bool]$stale.ok) 'stale CAS unexpectedly persisted';Assert-True ([string]$stale.reason -ceq 'consumption-store-revision-conflict') 'stale CAS reason drifted';Assert-PersistNoAuthority $stale 'stale-cas';$count++

$nonExtension=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $p2.state -ExpectedCurrentRevision 2 -Now $now.AddSeconds(3)
Assert-False ([bool]$nonExtension.ok) 'non-extension state unexpectedly persisted';Assert-True ([string]$nonExtension.reason -ceq 'next-state-not-single-revision-extension') 'non-extension reason drifted';Assert-PersistNoAuthority $nonExtension 'non-extension';$count++

$badNext=Copy-Deep $c2.next_state;$badNext.production_execution_authorized=$true
$bad=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $badNext -ExpectedCurrentRevision 2 -Now $now.AddSeconds(4)
Assert-False ([bool]$bad.ok) 'authority-corrupt state unexpectedly persisted';Assert-True ([string]$bad.reason -like 'next-state-invalid:*') 'authority-corrupt reason drifted';Assert-PersistNoAuthority $bad 'authority-corrupt';$count++

$escapeRoot=Join-Path $env:RUNNER_TEMP ('escape-'+[Guid]::NewGuid().ToString('N'));$escapeStore=Join-Path $escapeRoot 'store';New-Item -ItemType Directory -Force -Path $escapeRoot,$escapeStore,(Join-Path $escapeStore 'history')|Out-Null
$escape=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $escapeStore -NextState $c2.next_state -ExpectedCurrentRevision 2 -Now $now
Assert-False ([bool]$escape.ok) 'path escape unexpectedly persisted';Assert-True ([string]$escape.reason -like 'consumption-store-path-denied:*') 'path escape reason drifted';Assert-PersistNoAuthority $escape 'path-escape';$count++

$lockStore=New-PersistenceStoreFixture 'lock';$lockRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $lockStore.root -StoreDirectory $lockStore.store;$lockC=New-PersistableConsumption $lockRead.state '30303030303030303030303030303030';$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $lockStore.root -StoreDirectory $lockStore.store;$held=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths
try{$locked=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $lockStore.root -StoreDirectory $lockStore.store -NextState $lockC.next_state -ExpectedCurrentRevision 0 -Now $now;Assert-False ([bool]$locked.ok) 'lock contention unexpectedly persisted';Assert-True ([string]$locked.reason -ceq 'consumption-persistence-lock-busy') 'lock contention reason drifted';Assert-PersistNoAuthority $locked 'lock-contention'}finally{$held.Dispose()};$count++

$crash=New-PersistenceStoreFixture 'crash';$crashRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $crash.root -StoreDirectory $crash.store;$crashC=New-PersistableConsumption $crashRead.state '40404040404040404040404040404040';$crashSave=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $crash.root -StoreDirectory $crash.store -NextState $crashC.next_state -ExpectedCurrentRevision 0 -Now $now -FailurePoint 'after-history-before-current'
Assert-False ([bool]$crashSave.ok) 'simulated crash unexpectedly succeeded';Assert-True ([string]$crashSave.reason -ceq 'simulated-crash-after-history-before-current') 'simulated crash reason drifted';Assert-PersistNoAuthority $crashSave 'simulated-crash';Assert-ReadFails $crash.root $crash.store '*current-history-mismatch*' 'crash-window';$currentOnly=ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 -Path (Join-Path $crash.store 'current.json');Assert-True ([int64]$currentOnly.envelope.revision -eq 0) 'crash window replaced current before failure point';$count++

$tamper=New-PersistenceStoreFixture 'tamper';$tamperRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $tamper.root -StoreDirectory $tamper.store;$tamperC=New-PersistableConsumption $tamperRead.state '50505050505050505050505050505050';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $tamper.root -StoreDirectory $tamper.store -NextState $tamperC.next_state -ExpectedCurrentRevision 0 -Now $now);Set-Content -LiteralPath (Join-Path $tamper.store 'current.json') -Value '{"tampered":true}' -Encoding UTF8
Assert-ReadFails $tamper.root $tamper.store '*JSON invalid*' 'current-tamper';$count++

$currentRollback=New-PersistenceStoreFixture 'currentrollback';$rbRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $currentRollback.root -StoreDirectory $currentRollback.store;$rbC=New-PersistableConsumption $rbRead.state '60606060606060606060606060606060';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $currentRollback.root -StoreDirectory $currentRollback.store -NextState $rbC.next_state -ExpectedCurrentRevision 0 -Now $now);$rev0=Get-ChildItem -LiteralPath $currentRollback.history -File -Filter '00000000000000000000-*.json'|Select-Object -First 1;Copy-Item -LiteralPath $rev0.FullName -Destination (Join-Path $currentRollback.store 'current.json') -Force
Assert-ReadFails $currentRollback.root $currentRollback.store '*current-history-mismatch*' 'current-rollback';$count++

$historyRollback=New-PersistenceStoreFixture 'historyrollback';$hrRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $historyRollback.root -StoreDirectory $historyRollback.store;$hrC=New-PersistableConsumption $hrRead.state '70707070707070707070707070707070';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $historyRollback.root -StoreDirectory $historyRollback.store -NextState $hrC.next_state -ExpectedCurrentRevision 0 -Now $now);$latest=Get-ChildItem -LiteralPath $historyRollback.history -File -Filter '00000000000000000001-*.json'|Select-Object -First 1;Remove-Item -LiteralPath $latest.FullName -Force
Assert-ReadFails $historyRollback.root $historyRollback.store '*current-history-mismatch*' 'history-rollback';$count++

$detState=New-CustomAppProductionExecutorConsumptionStateV010;$detA=New-CustomAppProductionConsumptionEnvelopeV010 -State $detState -PreviousEnvelopeSha256 $CustomAppProductionConsumptionPersistenceZeroHash -WrittenAt $now;$detB=New-CustomAppProductionConsumptionEnvelopeV010 -State $detState -PreviousEnvelopeSha256 $CustomAppProductionConsumptionPersistenceZeroHash -WrittenAt $now
Assert-True ([string]$detA.envelope_sha256 -ceq [string]$detB.envelope_sha256) 'envelope hash nondeterministic';$count++

$futureStore=New-PersistenceStoreFixture 'future';$futureRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $futureStore.root -StoreDirectory $futureStore.store;$futureC=New-PersistableConsumption $futureRead.state '80808080808080808080808080808080' 'future-app' 'owner/future-app' 'Future App';$futureP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $futureStore.root -StoreDirectory $futureStore.store -NextState $futureC.next_state -ExpectedCurrentRevision 0 -Now $now
Assert-True ([bool]$futureP.ok) ('generic future app persistence denied: '+[string]$futureP.reason);Assert-PersistNoAuthority $futureP 'future-app-persist';$count++

# Leave one exact persisted store for a separate PowerShell process reload probe.
$probeRoot=if([string]::IsNullOrWhiteSpace([string]$env:CUSTOM_APP_CONSUMPTION_RELOAD_ROOT)){Join-Path $env:RUNNER_TEMP 'custom-app-production-consumption-reload-proof'}else{[IO.Path]::GetFullPath([string]$env:CUSTOM_APP_CONSUMPTION_RELOAD_ROOT)}
if(Test-Path -LiteralPath $probeRoot){Remove-Item -LiteralPath $probeRoot -Recurse -Force};$probeStore=Join-Path $probeRoot 'store';New-Item -ItemType Directory -Force -Path $probeRoot,$probeStore,(Join-Path $probeStore 'history')|Out-Null;$probeInit=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $probeRoot -StoreDirectory $probeStore -Now $now;if(-not [bool]$probeInit.ok){throw 'probe init failed'};$probeC=New-PersistableConsumption $probeInit.state '90909090909090909090909090909090';$probeP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $probeRoot -StoreDirectory $probeStore -NextState $probeC.next_state -ExpectedCurrentRevision 0 -Now $now;if(-not [bool]$probeP.ok){throw 'probe persist failed'};Set-Content -LiteralPath (Join-Path $probeRoot 'expected-consumption-id.txt') -Value ([string]$probeP.consumption_id) -Encoding ASCII
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_CONSUMPTION_PERSISTENCE_MATRIX_PASS total='+$count+' reload_root='+$probeRoot)
