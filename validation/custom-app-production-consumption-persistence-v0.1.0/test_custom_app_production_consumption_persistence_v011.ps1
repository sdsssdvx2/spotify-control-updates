$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-executor-consumption-v0.1.0/test_custom_app_production_executor_consumption.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-consumption-persistence.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-consumption-persistence-contract-v011.ps1')

function Assert-PersistResultDeniedAuthorityV011 {
    param($Result,[string]$Label)
    if($Result.PSObject.Properties['persistence_is_authority']){Assert-False ([bool]$Result.persistence_is_authority) "$Label persistence authority"}
    if($Result.PSObject.Properties['executor_may_stage']){Assert-False ([bool]$Result.executor_may_stage) "$Label stage authority"}
    if($Result.PSObject.Properties['executor_may_apply']){Assert-False ([bool]$Result.executor_may_apply) "$Label apply authority"}
    if($Result.PSObject.Properties['production_execution_authorized']){Assert-False ([bool]$Result.production_execution_authorized) "$Label production execution authority"}
    if($Result.PSObject.Properties['production_mutation_authorized']){Assert-False ([bool]$Result.production_mutation_authorized) "$Label production mutation authority"}
}

function New-PersistenceStoreFixtureV011 {
    param([string]$Label)
    $base=Join-Path $env:RUNNER_TEMP ('custom-app-production-consumption-persistence-v011-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    $store=Join-Path $base 'store';$history=Join-Path $store 'history'
    New-Item -ItemType Directory -Force -Path $base,$store,$history|Out-Null
    $init=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $base -StoreDirectory $store -Now $now
    if(-not [bool]$init.ok){throw ('store init failed: '+[string]$init.reason)}
    $read=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $base -StoreDirectory $store
    if(-not [bool]$read.ok){throw ('store init reload failed: '+[string]$read.reason)}
    $barrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $read
    return [pscustomobject]@{root=$base;store=$store;history=$history;init=$init;read=$read;barrier=$barrier}
}

function New-PersistableConsumptionV011 {
    param($CurrentState,[string]$Nonce,[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify')
    $fx=New-ConsumptionFixture -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $r=Consume-Fixture $fx $CurrentState ([int64]$CurrentState.revision)
    if(-not [bool]$r.ok){throw ('could not build persistable consumption: '+[string]$r.reason)}
    return [pscustomobject]@{fixture=$fx;result=$r;next_state=$r.next_state}
}

function Assert-ReadFailsV011 {
    param([string]$Root,[string]$Store,[string]$ExpectedLike,[string]$Label)
    $failed=$false
    try{[void](Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $Root -StoreDirectory $Store)}catch{$failed=$true;if([string]$_.Exception.Message -notlike $ExpectedLike){throw "$Label wrong failure: $($_.Exception.Message)"}}
    Assert-True $failed "$Label unexpectedly read successfully"
}

$count=0
$s=New-PersistenceStoreFixtureV011 'fresh'
Assert-True ([bool]$s.init.read_after_write_verified) 'init read-after-write verification missing'
Assert-True ([bool]$s.read.envelope.requires_persisted_consumption_before_executor) 'persist-before-executor field missing from rev0 envelope'
Assert-False ([bool]$s.barrier.ok) 'empty persisted store unexpectedly passed executor barrier'
Assert-True ([string]$s.barrier.reason -ceq 'persisted-consumption-row-missing') 'empty store barrier reason drifted'
Assert-PersistResultDeniedAuthorityV011 $s.read 'fresh-read';$count++

$c1=New-PersistableConsumptionV011 $s.read.state '11111111111111111111111111111111'
$p1=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c1.next_state -ExpectedCurrentRevision 0 -Now $now
Assert-True ([bool]$p1.ok -and [bool]$p1.persisted -and [bool]$p1.read_after_write_verified) ('first persist failed: '+[string]$p1.reason)
Assert-PersistResultDeniedAuthorityV011 $p1 'first-persist'
$r1=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $s.root -StoreDirectory $s.store
$b1=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $r1 -ExpectedConsumptionId ([string]$c1.result.consumption_id)
Assert-True ([bool]$b1.ok) ('persisted executor barrier denied exact row: '+[string]$b1.reason)
Assert-True ([bool]$b1.requires_persisted_consumption_before_executor) 'barrier did not preserve persist-before-executor requirement'
Assert-False ([bool]$b1.executor_may_stage) 'persistence barrier granted stage authority'
Assert-False ([bool]$b1.executor_may_apply) 'persistence barrier granted apply authority';$count++

$c2=New-PersistableConsumptionV011 $r1.state '22222222222222222222222222222222'
$p2=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c2.next_state -ExpectedCurrentRevision 1 -Now $now.AddSeconds(1)
Assert-True ([bool]$p2.ok -and [int64]$p2.revision -eq 2) 'second append persistence failed'
Assert-True ((Get-ChildItem -LiteralPath $s.history -File -Filter '*.json').Count -eq 3) 'append-only history count drifted';$count++

$stale=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $c2.next_state -ExpectedCurrentRevision 0 -Now $now.AddSeconds(2)
Assert-False ([bool]$stale.ok) 'stale CAS unexpectedly persisted';Assert-True ([string]$stale.reason -ceq 'consumption-store-revision-conflict') 'stale CAS reason drifted';Assert-PersistResultDeniedAuthorityV011 $stale 'stale-cas';$count++

$nonExtension=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $p2.state -ExpectedCurrentRevision 2 -Now $now.AddSeconds(3)
Assert-False ([bool]$nonExtension.ok) 'non-extension state unexpectedly persisted';Assert-True ([string]$nonExtension.reason -ceq 'next-state-not-single-revision-extension') 'non-extension reason drifted';$count++

$badNext=Copy-Deep $c2.next_state;$badNext.production_execution_authorized=$true
$bad=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $s.store -NextState $badNext -ExpectedCurrentRevision 2 -Now $now.AddSeconds(4)
Assert-False ([bool]$bad.ok) 'authority-corrupt state unexpectedly persisted';Assert-True ([string]$bad.reason -like 'next-state-invalid:*') 'authority-corrupt reason drifted';$count++

$escapeRoot=Join-Path $env:RUNNER_TEMP ('escape-'+[Guid]::NewGuid().ToString('N'));$escapeStore=Join-Path $escapeRoot 'store';New-Item -ItemType Directory -Force -Path $escapeRoot,$escapeStore,(Join-Path $escapeStore 'history')|Out-Null
$escape=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $s.root -StoreDirectory $escapeStore -NextState $c2.next_state -ExpectedCurrentRevision 2 -Now $now
Assert-False ([bool]$escape.ok) 'path escape unexpectedly persisted';Assert-True ([string]$escape.reason -like 'consumption-store-path-denied:*') 'path escape reason drifted';$count++

$lockStore=New-PersistenceStoreFixtureV011 'lock';$lockC=New-PersistableConsumptionV011 $lockStore.read.state '33333333333333333333333333333333';$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $lockStore.root -StoreDirectory $lockStore.store;$held=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths
try{$locked=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $lockStore.root -StoreDirectory $lockStore.store -NextState $lockC.next_state -ExpectedCurrentRevision 0 -Now $now;Assert-False ([bool]$locked.ok) 'lock contention unexpectedly persisted';Assert-True ([string]$locked.reason -ceq 'consumption-persistence-lock-busy') 'lock contention reason drifted'}finally{$held.Dispose()};$count++

$crash=New-PersistenceStoreFixtureV011 'crash';$crashC=New-PersistableConsumptionV011 $crash.read.state '44444444444444444444444444444444';$crashSave=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $crash.root -StoreDirectory $crash.store -NextState $crashC.next_state -ExpectedCurrentRevision 0 -Now $now -FailurePoint 'after-history-before-current'
Assert-False ([bool]$crashSave.ok) 'simulated crash unexpectedly succeeded';Assert-True ([string]$crashSave.reason -ceq 'simulated-crash-after-history-before-current') 'simulated crash reason drifted';Assert-ReadFailsV011 $crash.root $crash.store '*current-history-mismatch*' 'crash-window';$currentOnly=ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 -Path (Join-Path $crash.store 'current.json');Assert-True ([int64]$currentOnly.envelope.revision -eq 0) 'crash window replaced current before failure point';$count++

$tamper=New-PersistenceStoreFixtureV011 'tamper';$tamperC=New-PersistableConsumptionV011 $tamper.read.state '55555555555555555555555555555555';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $tamper.root -StoreDirectory $tamper.store -NextState $tamperC.next_state -ExpectedCurrentRevision 0 -Now $now);[IO.File]::WriteAllText((Join-Path $tamper.store 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false))
Assert-ReadFailsV011 $tamper.root $tamper.store '*JSON invalid*' 'current-tamper';$count++

$flagTamper=New-PersistenceStoreFixtureV011 'flagtamper';$flagC=New-PersistableConsumptionV011 $flagTamper.read.state '66666666666666666666666666666666';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $flagTamper.root -StoreDirectory $flagTamper.store -NextState $flagC.next_state -ExpectedCurrentRevision 0 -Now $now);$currentPath=Join-Path $flagTamper.store 'current.json';$env=(Get-Content -LiteralPath $currentPath -Raw|ConvertFrom-Json);$env.requires_persisted_consumption_before_executor=$false;$env.envelope_sha256=Get-CustomAppProductionConsumptionPersistenceSha256V010 (Get-CustomAppProductionConsumptionEnvelopeMaterialV010 $env);[IO.File]::WriteAllText($currentPath,($env|ConvertTo-Json -Depth 50 -Compress),[Text.UTF8Encoding]::new($false))
Assert-ReadFailsV011 $flagTamper.root $flagTamper.store '*persist-before-executor-contract-invalid*' 'persist-flag-tamper';$count++

$currentRollback=New-PersistenceStoreFixtureV011 'currentrollback';$rbC=New-PersistableConsumptionV011 $currentRollback.read.state '77777777777777777777777777777777';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $currentRollback.root -StoreDirectory $currentRollback.store -NextState $rbC.next_state -ExpectedCurrentRevision 0 -Now $now);$rev0=Get-ChildItem -LiteralPath $currentRollback.history -File -Filter '00000000000000000000-*.json'|Select-Object -First 1;Copy-Item -LiteralPath $rev0.FullName -Destination (Join-Path $currentRollback.store 'current.json') -Force
Assert-ReadFailsV011 $currentRollback.root $currentRollback.store '*current-history-mismatch*' 'current-rollback';$count++

$historyRollback=New-PersistenceStoreFixtureV011 'historyrollback';$hrC=New-PersistableConsumptionV011 $historyRollback.read.state '88888888888888888888888888888888';[void](Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $historyRollback.root -StoreDirectory $historyRollback.store -NextState $hrC.next_state -ExpectedCurrentRevision 0 -Now $now);$latest=Get-ChildItem -LiteralPath $historyRollback.history -File -Filter '00000000000000000001-*.json'|Select-Object -First 1;Remove-Item -LiteralPath $latest.FullName -Force
Assert-ReadFailsV011 $historyRollback.root $historyRollback.store '*current-history-mismatch*' 'history-rollback';$count++

$detState=New-CustomAppProductionExecutorConsumptionStateV010;$detA=New-CustomAppProductionConsumptionEnvelopeV010 -State $detState -PreviousEnvelopeSha256 $CustomAppProductionConsumptionPersistenceZeroHash -WrittenAt $now;$detB=New-CustomAppProductionConsumptionEnvelopeV010 -State $detState -PreviousEnvelopeSha256 $CustomAppProductionConsumptionPersistenceZeroHash -WrittenAt $now
Assert-True ([string]$detA.envelope_sha256 -ceq [string]$detB.envelope_sha256) 'envelope hash nondeterministic';Assert-True ([bool]$detA.requires_persisted_consumption_before_executor) 'deterministic envelope omitted persisted barrier';$count++

$futureStore=New-PersistenceStoreFixtureV011 'future';$futureC=New-PersistableConsumptionV011 $futureStore.read.state '99999999999999999999999999999999' 'future-app' 'owner/future-app' 'Future App';$futureP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $futureStore.root -StoreDirectory $futureStore.store -NextState $futureC.next_state -ExpectedCurrentRevision 0 -Now $now
Assert-True ([bool]$futureP.ok) ('generic future app persistence denied: '+[string]$futureP.reason);$futureRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $futureStore.root -StoreDirectory $futureStore.store;$futureBarrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $futureRead -ExpectedConsumptionId ([string]$futureC.result.consumption_id);Assert-True ([bool]$futureBarrier.ok) 'generic future app did not satisfy persisted barrier';Assert-False ([bool]$futureBarrier.executor_may_stage) 'generic persistence granted stage authority';$count++

$probeRoot=if([string]::IsNullOrWhiteSpace([string]$env:CUSTOM_APP_CONSUMPTION_RELOAD_ROOT)){Join-Path $env:RUNNER_TEMP 'custom-app-production-consumption-reload-proof-v011'}else{[IO.Path]::GetFullPath([string]$env:CUSTOM_APP_CONSUMPTION_RELOAD_ROOT)}
if(Test-Path -LiteralPath $probeRoot){Remove-Item -LiteralPath $probeRoot -Recurse -Force};$probeStore=Join-Path $probeRoot 'store';New-Item -ItemType Directory -Force -Path $probeRoot,$probeStore,(Join-Path $probeStore 'history')|Out-Null;$probeInit=Initialize-CustomAppProductionConsumptionStoreV010 -AllowedRoot $probeRoot -StoreDirectory $probeStore -Now $now;if(-not [bool]$probeInit.ok){throw 'probe init failed'};$probeRead=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $probeRoot -StoreDirectory $probeStore;$probeC=New-PersistableConsumptionV011 $probeRead.state 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$probeP=Save-CustomAppProductionConsumptionStateV010 -AllowedRoot $probeRoot -StoreDirectory $probeStore -NextState $probeC.next_state -ExpectedCurrentRevision 0 -Now $now;if(-not [bool]$probeP.ok){throw 'probe persist failed'};Set-Content -LiteralPath (Join-Path $probeRoot 'expected-consumption-id.txt') -Value ([string]$probeP.consumption_id) -Encoding ASCII
$count++

Write-Host ('CUSTOM_APP_PRODUCTION_CONSUMPTION_PERSISTENCE_V011_MATRIX_PASS total='+$count+' reload_root='+$probeRoot)
