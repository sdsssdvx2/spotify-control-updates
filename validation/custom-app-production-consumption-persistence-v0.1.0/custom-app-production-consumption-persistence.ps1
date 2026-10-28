$CustomAppProductionConsumptionPersistenceSchema = 1
$CustomAppProductionConsumptionPersistenceManagedBy = 'custom-app-production-consumption-persistence-v1'
$CustomAppProductionConsumptionPersistenceQualifiedConsumptionHead = 'ed7fa27fc9bfaa78858e130743a2de508a3c0bf9'
$CustomAppProductionConsumptionPersistenceZeroHash = ('0' * 64)

function Get-CustomAppProductionConsumptionPersistenceSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionConsumptionPersistenceSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionConsumptionPersistenceWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-CustomAppProductionConsumptionPersistencePathV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='path',[bool]$AllowRoot=$false,[bool]$RequireExisting=$false)
    $r=[IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-CustomAppProductionConsumptionPersistenceWithinV010 -Root $r -Path $p -AllowRoot:$AllowRoot)){throw "$Label escaped allowed fixture root."}
    if(-not (Test-Path -LiteralPath $r -PathType Container)){throw "$Label allowed root is missing."}
    $rootItem=Get-Item -LiteralPath $r -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label allowed root is a reparse point."}
    $probe=$p
    while(-not $probe.Equals($r,[StringComparison]::OrdinalIgnoreCase)){
        if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label contains a reparse-point ancestor."}}
        $parent=[IO.Directory]::GetParent($probe);if($null -eq $parent){throw "$Label parent chain escaped allowed root."};$probe=$parent.FullName
        if(-not ($probe.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $probe.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw "$Label parent chain escaped allowed root."}
    }
    if($RequireExisting -and -not (Test-Path -LiteralPath $p)){throw "$Label is missing."}
    return $p
}

function Get-CustomAppProductionConsumptionStateJsonV010 {
    param([Parameter(Mandatory=$true)]$State)
    return ($State | ConvertTo-Json -Depth 40 -Compress)
}

function Get-CustomAppProductionConsumptionEnvelopeMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_consumption_head,
        [string]$Envelope.revision,[string]$Envelope.state_sha256,[string]$Envelope.previous_envelope_sha256,
        [string]$Envelope.written_at,[string]$Envelope.append_only,[string]$Envelope.persistence_is_authority,
        [string]$Envelope.production_execution_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppProductionConsumptionEnvelopeV010 {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$PreviousEnvelopeSha256,[DateTimeOffset]$WrittenAt=[DateTimeOffset]::UtcNow)
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $State
    if(-not [bool]$stateCheck.ok){throw ('cannot envelope invalid consumption state: '+[string]$stateCheck.reason)}
    $prev=$PreviousEnvelopeSha256.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $prev)){throw 'previous envelope sha256 invalid'}
    $stateJson=Get-CustomAppProductionConsumptionStateJsonV010 -State $State
    $e=[pscustomobject]@{
        schema=$CustomAppProductionConsumptionPersistenceSchema;managed_by=$CustomAppProductionConsumptionPersistenceManagedBy;qualified_consumption_head=$CustomAppProductionConsumptionPersistenceQualifiedConsumptionHead
        revision=[int64]$State.revision;state_sha256=(Get-CustomAppProductionConsumptionPersistenceSha256V010 $stateJson);previous_envelope_sha256=$prev;written_at=$WrittenAt.ToUniversalTime().ToString('o')
        append_only=$true;persistence_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false;state=$State;envelope_sha256=$null
    }
    $e.envelope_sha256=Get-CustomAppProductionConsumptionPersistenceSha256V010 (Get-CustomAppProductionConsumptionEnvelopeMaterialV010 -Envelope $e)
    return $e
}

function Test-CustomAppProductionConsumptionEnvelopeV010 {
    param([AllowNull()]$Envelope)
    if($null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='envelope-null'}}
    if([int]$Envelope.schema -ne $CustomAppProductionConsumptionPersistenceSchema -or [string]$Envelope.managed_by -cne $CustomAppProductionConsumptionPersistenceManagedBy -or [string]$Envelope.qualified_consumption_head -cne $CustomAppProductionConsumptionPersistenceQualifiedConsumptionHead){return [pscustomobject]@{ok=$false;reason='envelope-owner-schema-parent-mismatch'}}
    if(-not [bool]$Envelope.append_only -or [bool]$Envelope.persistence_is_authority -or [bool]$Envelope.production_execution_authorized -or [bool]$Envelope.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason='envelope-authority-or-append-contract-invalid'}}
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $Envelope.state
    if(-not [bool]$stateCheck.ok){return [pscustomobject]@{ok=$false;reason=('envelope-state-invalid:'+[string]$stateCheck.reason)}}
    try{$revision=[int64]$Envelope.revision}catch{return [pscustomobject]@{ok=$false;reason='envelope-revision-invalid'}}
    if($revision -ne [int64]$stateCheck.revision){return [pscustomobject]@{ok=$false;reason='envelope-state-revision-mismatch'}}
    $stateJson=Get-CustomAppProductionConsumptionStateJsonV010 -State $Envelope.state
    $expectedState=Get-CustomAppProductionConsumptionPersistenceSha256V010 $stateJson
    if(([string]$Envelope.state_sha256).Trim().ToLowerInvariant() -cne $expectedState){return [pscustomobject]@{ok=$false;reason='envelope-state-sha256-mismatch'}}
    $prev=([string]$Envelope.previous_envelope_sha256).Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $prev)){return [pscustomobject]@{ok=$false;reason='envelope-previous-sha256-invalid'}}
    $actual=([string]$Envelope.envelope_sha256).Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionConsumptionPersistenceSha256V010 $actual)){return [pscustomobject]@{ok=$false;reason='envelope-sha256-invalid'}}
    $expected=Get-CustomAppProductionConsumptionPersistenceSha256V010 (Get-CustomAppProductionConsumptionEnvelopeMaterialV010 -Envelope $Envelope)
    if($actual -cne $expected){return [pscustomobject]@{ok=$false;reason='envelope-sha256-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='envelope-valid';revision=$revision;state_sha256=$expectedState;envelope_sha256=$actual}
}

function Get-CustomAppProductionConsumptionPersistencePathsV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $store=Assert-CustomAppProductionConsumptionPersistencePathV010 -AllowedRoot $AllowedRoot -Path $StoreDirectory -Label 'consumption store' -RequireExisting:$true
    $history=Assert-CustomAppProductionConsumptionPersistencePathV010 -AllowedRoot $AllowedRoot -Path (Join-Path $store 'history') -Label 'consumption history' -RequireExisting:$true
    if(-not (Test-Path -LiteralPath $history -PathType Container)){throw 'consumption history is not a directory'}
    return [pscustomobject]@{
        allowed_root=[IO.Path]::GetFullPath($AllowedRoot);store=$store;history=$history
        current=(Join-Path $store 'current.json');lock=(Join-Path $store '.consumption.lock')
    }
}

function Open-CustomAppProductionConsumptionPersistenceLockV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    try{return [IO.File]::Open([string]$Paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch [IO.IOException]{throw 'consumption-persistence-lock-busy'}
}

function Write-CustomAppProductionConsumptionDurableFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][IO.FileMode]$Mode)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text);$stream=$null
    try{$stream=[IO.File]::Open($Path,$Mode,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
    finally{if($null -ne $stream){$stream.Dispose()}}
}

function ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'consumption persistence file is reparse point'}
    if($item.Length -gt 4194304){throw 'consumption persistence file exceeds 4 MiB'}
    $raw=[IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
    try{$e=$raw|ConvertFrom-Json}catch{throw 'consumption persistence JSON invalid'}
    $check=Test-CustomAppProductionConsumptionEnvelopeV010 -Envelope $e
    if(-not [bool]$check.ok){throw ('consumption persistence envelope invalid: '+[string]$check.reason)}
    return [pscustomobject]@{envelope=$e;raw=$raw;check=$check;raw_sha256=(Get-CustomAppProductionConsumptionPersistenceSha256V010 $raw)}
}

function Read-CustomAppProductionConsumptionStoreUnlockedV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    $historyFiles=@(Get-ChildItem -LiteralPath ([string]$Paths.history) -File -Filter '*.json' -Force | Sort-Object Name)
    if($historyFiles.Count -eq 0){
        if(Test-Path -LiteralPath ([string]$Paths.current)){throw 'consumption-store-current-without-history'}
        return [pscustomobject]@{ok=$false;reason='consumption-store-uninitialized';initialized=$false;revision=[int64]-1;state=$null;envelope=$null;history_count=0;current_matches_history=$false}
    }
    $expectedRevision=[int64]0;$previous=$CustomAppProductionConsumptionPersistenceZeroHash;$latest=$null
    foreach($file in $historyFiles){
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'consumption history entry is reparse point'}
        $entry=ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 -Path $file.FullName;$e=$entry.envelope
        if([int64]$e.revision -ne $expectedRevision){throw 'consumption history revision chain invalid'}
        if(([string]$e.previous_envelope_sha256).Trim().ToLowerInvariant() -cne $previous){throw 'consumption history hash chain invalid'}
        $expectedName=('{0:D20}-{1}.json' -f [int64]$e.revision,([string]$e.envelope_sha256).Trim().ToLowerInvariant())
        if([string]$file.Name -cne $expectedName){throw 'consumption history filename identity invalid'}
        $previous=([string]$e.envelope_sha256).Trim().ToLowerInvariant();$latest=$e;$expectedRevision++
    }
    if(-not (Test-Path -LiteralPath ([string]$Paths.current) -PathType Leaf)){throw 'consumption-store-current-missing'}
    $current=ConvertFrom-CustomAppProductionConsumptionEnvelopeFileV010 -Path ([string]$Paths.current)
    if([int64]$current.envelope.revision -ne [int64]$latest.revision -or ([string]$current.envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$latest.envelope_sha256).Trim().ToLowerInvariant()){throw 'consumption-store-current-history-mismatch'}
    return [pscustomobject]@{ok=$true;reason='consumption-store-valid';initialized=$true;revision=[int64]$latest.revision;state=$latest.state;envelope=$latest;history_count=$historyFiles.Count;current_matches_history=$true;current_raw_sha256=$current.raw_sha256}
}

function Read-CustomAppProductionConsumptionStoreV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$lock=$null
    try{$lock=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths;$r=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths
        if(-not [bool]$r.ok){return $r}
        return [pscustomobject]@{ok=$true;reason='consumption-store-reloaded';initialized=$true;revision=[int64]$r.revision;state=$r.state;envelope=$r.envelope;history_count=[int]$r.history_count;current_matches_history=$true;reloaded_from_persistent_store=$true;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null -ne $lock){$lock.Dispose()}}
}

function Initialize-CustomAppProductionConsumptionStoreV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$lock=$null
    try{$lock=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths;$existing=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths;if([bool]$existing.ok){return [pscustomobject]@{ok=$false;reason='consumption-store-already-initialized';production_execution_authorized=$false;production_mutation_authorized=$false}}
        if([string]$existing.reason -cne 'consumption-store-uninitialized'){return [pscustomobject]@{ok=$false;reason=[string]$existing.reason;production_execution_authorized=$false;production_mutation_authorized=$false}}
        $state=New-CustomAppProductionExecutorConsumptionStateV010;$e=New-CustomAppProductionConsumptionEnvelopeV010 -State $state -PreviousEnvelopeSha256 $CustomAppProductionConsumptionPersistenceZeroHash -WrittenAt $Now;$json=$e|ConvertTo-Json -Depth 50 -Compress;$historyPath=Join-Path ([string]$paths.history) ('{0:D20}-{1}.json' -f [int64]$e.revision,[string]$e.envelope_sha256)
        Write-CustomAppProductionConsumptionDurableFileV010 -Path $historyPath -Text $json -Mode ([IO.FileMode]::CreateNew);Write-CustomAppProductionConsumptionDurableFileV010 -Path ([string]$paths.current) -Text $json -Mode ([IO.FileMode]::CreateNew)
        $verify=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths;if(-not [bool]$verify.ok -or [int64]$verify.revision -ne 0){throw 'consumption store initialization readback failed'}
        return [pscustomobject]@{ok=$true;reason='consumption-store-initialized-and-readback-verified';revision=[int64]0;state=$verify.state;envelope=$verify.envelope;reloaded_from_persistent_store=$true;read_after_write_verified=$true;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null -ne $lock){$lock.Dispose()}}
}

function Test-CustomAppProductionConsumptionStateExtendsExactlyOneV010 {
    param([Parameter(Mandatory=$true)]$Current,[Parameter(Mandatory=$true)]$Next)
    $a=Test-CustomAppProductionExecutorConsumptionStateV010 -State $Current;$b=Test-CustomAppProductionExecutorConsumptionStateV010 -State $Next
    if(-not [bool]$a.ok){return [pscustomobject]@{ok=$false;reason=('current-state-invalid:'+[string]$a.reason)}}
    if(-not [bool]$b.ok){return [pscustomobject]@{ok=$false;reason=('next-state-invalid:'+[string]$b.reason)}}
    if([int64]$Next.revision -ne ([int64]$Current.revision+1)){return [pscustomobject]@{ok=$false;reason='next-state-not-single-revision-extension'}}
    $currentRows=@($Current.consumptions);$nextRows=@($Next.consumptions);if($nextRows.Count -ne ($currentRows.Count+1)){return [pscustomobject]@{ok=$false;reason='next-state-not-single-row-extension'}}
    for($i=0;$i -lt $currentRows.Count;$i++){$left=$currentRows[$i]|ConvertTo-Json -Depth 40 -Compress;$right=$nextRows[$i]|ConvertTo-Json -Depth 40 -Compress;if($left -cne $right){return [pscustomobject]@{ok=$false;reason='next-state-rewrites-history'}}}
    return [pscustomobject]@{ok=$true;reason='next-state-exact-single-extension'}
}

function Save-CustomAppProductionConsumptionStateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$NextState,
        [Parameter(Mandatory=$true)][int64]$ExpectedCurrentRevision,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;read_after_write_verified=$false;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    try{$paths=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('consumption-store-path-denied:'+[string]$_.Exception.Message)}
    $lock=$null;$temp=$null;$backup=$null
    try{
        try{$lock=Open-CustomAppProductionConsumptionPersistenceLockV010 -Paths $paths}catch{return & $deny ([string]$_.Exception.Message)}
        try{$current=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths}catch{return & $deny ('consumption-store-read-denied:'+[string]$_.Exception.Message)}
        if(-not [bool]$current.ok){return & $deny ([string]$current.reason)}
        if([int64]$current.revision -ne $ExpectedCurrentRevision){return & $deny 'consumption-store-revision-conflict'}
        $extend=Test-CustomAppProductionConsumptionStateExtendsExactlyOneV010 -Current $current.state -Next $NextState;if(-not [bool]$extend.ok){return & $deny ([string]$extend.reason)}
        $e=New-CustomAppProductionConsumptionEnvelopeV010 -State $NextState -PreviousEnvelopeSha256 ([string]$current.envelope.envelope_sha256) -WrittenAt $Now;$json=$e|ConvertTo-Json -Depth 50 -Compress
        $historyPath=Join-Path ([string]$paths.history) ('{0:D20}-{1}.json' -f [int64]$e.revision,[string]$e.envelope_sha256)
        try{Write-CustomAppProductionConsumptionDurableFileV010 -Path $historyPath -Text $json -Mode ([IO.FileMode]::CreateNew)}catch{return & $deny ('consumption-history-create-failed:'+[string]$_.Exception.Message)}
        if($FailurePoint -ceq 'after-history-before-current'){return & $deny 'simulated-crash-after-history-before-current'}
        $temp=Join-Path ([string]$paths.store) ('current.tmp.'+[Guid]::NewGuid().ToString('N'));$backup=Join-Path ([string]$paths.store) ('current.backup.'+[Guid]::NewGuid().ToString('N'))
        Write-CustomAppProductionConsumptionDurableFileV010 -Path $temp -Text $json -Mode ([IO.FileMode]::CreateNew)
        [IO.File]::Replace($temp,[string]$paths.current,$backup,$true);$temp=$null
        try{$verify=Read-CustomAppProductionConsumptionStoreUnlockedV010 -Paths $paths}catch{return & $deny ('consumption-store-readback-denied:'+[string]$_.Exception.Message)}
        if(-not [bool]$verify.ok -or [int64]$verify.revision -ne [int64]$NextState.revision -or ([string]$verify.envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$e.envelope_sha256).Trim().ToLowerInvariant()){return & $deny 'consumption-store-readback-mismatch'}
        if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue;$backup=$null}
        $last=@($verify.state.consumptions)[-1]
        return [pscustomobject]@{ok=$true;reason='consumption-state-durably-persisted-and-readback-verified';persisted=$true;read_after_write_verified=$true;revision=[int64]$verify.revision;state=$verify.state;envelope=$verify.envelope;consumption_id=[string]$last.consumption_id;reloaded_from_persistent_store=$true;persistence_is_authority=$false;executor_may_stage=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }finally{
        if($null -ne $temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
        if($null -ne $lock){$lock.Dispose()}
    }
}
