$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$preApplyRel='validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0/test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1'
$preApplyDir=Join-Path $root 'validation/custom-app-production-recovery-aware-permit-pre-apply-preparation-v0.1.0'
$generatedFixtureFiles=New-Object System.Collections.Generic.List[string]
$script:RAALFixtureOnlyMap=@{}

function Get-RAALIntegrationUniqueMarkerIndexV010 {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$Marker,[Parameter(Mandatory=$true)][string]$Label)
    $first=$Text.IndexOf($Marker,[StringComparison]::Ordinal)
    if($first -lt 0){throw "integration semantic patch marker missing: $Label"}
    if($Text.IndexOf($Marker,$first+$Marker.Length,[StringComparison]::Ordinal) -ge 0){throw "integration semantic patch marker not unique: $Label"}
    return $first
}

function ConvertTo-RAALFixtureOnlyPrefixV010 {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$Label)
    $normalized=$Text.Replace("`r`n","`n")
    $matrix=[regex]::Match($normalized,'(?im)^\$(?:(?:count|casecount|testcount|total)|[A-Za-z_][A-Za-z0-9_]*count)\s*=\s*0\s*$')
    if($matrix.Success){$boundary=$matrix.Index}else{
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($normalized,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw "fixture-only AST parse failed: $Label"}
        $functions=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]})
        if($functions.Count -eq 0){throw "fixture-only matrix boundary missing and no helper functions: $Label"}
        $boundary=0;foreach($fn in $functions){if([int]$fn.Extent.EndOffset -gt $boundary){$boundary=[int]$fn.Extent.EndOffset}}
        if($boundary -le 0 -or $boundary -ge $normalized.Length -or [string]::IsNullOrWhiteSpace($normalized.Substring($boundary))){throw "fixture-only AST fallback found no matrix body: $Label"}
    }
    $prefix=$normalized.Substring(0,$boundary);$lines=@($prefix -split "`n")
    $importPattern='^\s*\.\s*\(Join-Path\s+\$root\s+''(?<rel>validation/[^'']+/test_[^'']+\.ps1)''\)\s*$'
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i] -match $importPattern){$parentRel=([string]$Matches['rel']).Replace('\','/');$fixtureRel=New-RAALFixtureOnlyCopyV010 -RelativePath $parentRel;$lines[$i]=$lines[$i].Replace($parentRel,$fixtureRel)}
    }
    return (($lines -join "`n")+"`n")
}

function New-RAALFixtureOnlyCopyV010 {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $rel=$RelativePath.Replace('\','/');if($script:RAALFixtureOnlyMap.ContainsKey($rel)){return [string]$script:RAALFixtureOnlyMap[$rel]}
    $full=Join-Path $root ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar));if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw "fixture-only source missing: $rel"}
    $dirRel=[IO.Path]::GetDirectoryName($rel.Replace('/',[IO.Path]::DirectorySeparatorChar));$leaf=[IO.Path]::GetFileNameWithoutExtension($rel);$genName=$leaf+'.fixture-only.'+[Guid]::NewGuid().ToString('N')+'.ps1';$genRel=(Join-Path $dirRel $genName).Replace('\','/');$genFull=Join-Path $root ($genRel.Replace('/',[IO.Path]::DirectorySeparatorChar));$script:RAALFixtureOnlyMap[$rel]=$genRel
    $sourceText=[IO.File]::ReadAllText($full,[Text.UTF8Encoding]::new($false));$fixtureText=ConvertTo-RAALFixtureOnlyPrefixV010 -Text $sourceText -Label $rel;[IO.File]::WriteAllText($genFull,$fixtureText,[Text.UTF8Encoding]::new($false));$generatedFixtureFiles.Add($genFull);return $genRel
}

$source=Join-Path $root ($preApplyRel.Replace('/',[IO.Path]::DirectorySeparatorChar));$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false)).Replace("`r`n","`n")
$startMarker='    # Root VCS metadata is deliberately invisible to the runtime baseline but must be'
$endMarker="'root git metadata changed runtime baseline'"
$start=Get-RAALIntegrationUniqueMarkerIndexV010 -Text $text -Marker $startMarker -Label 'post-recovery-vcs-start';$endPhrase=Get-RAALIntegrationUniqueMarkerIndexV010 -Text $text -Marker $endMarker -Label 'post-recovery-vcs-end'
if($endPhrase -le $start){throw 'integration semantic VCS patch boundaries reversed'};$end=$text.IndexOf("`n",$endPhrase,[StringComparison]::Ordinal);if($end -lt 0){$end=$text.Length}else{$end++}
$replacement=@'
    # Recovery closure is durable evidence. Keep live bytes unchanged after closure.
    # Unauthorized byte-real drift is injected only in dedicated negative cases below.
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
'@.Replace("`r`n","`n")
$patched=$text.Substring(0,$start)+$replacement+$text.Substring($end)
if($patched.IndexOf($startMarker,[StringComparison]::Ordinal) -ge 0){throw 'integration recovery-closed semantic patch failed'}
$fixtureOnly=ConvertTo-RAALFixtureOnlyPrefixV010 -Text $patched -Label $preApplyRel
if($fixtureOnly.IndexOf('function New-RAPPFixtureV010',[StringComparison]::Ordinal) -lt 0 -or $fixtureOnly.IndexOf('function Invoke-RAPPFixtureV010',[StringComparison]::Ordinal) -lt 0){throw 'integration fixture-only pre-apply helpers missing'}
$temp=Join-Path $preApplyDir ('test_recovery_atomic_fixture_only_'+[Guid]::NewGuid().ToString('N')+'.ps1')

try {
    [IO.File]::WriteAllText($temp,$fixtureOnly,[Text.UTF8Encoding]::new($false));. $temp
    . (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
    . (Join-Path $root 'validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/custom-app-production-atomic-live-swap-mutation.ps1')
    . (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-atomic-live-swap-v0.1.0/custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')

    function Assert-RAALITrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
    function Assert-RAALIFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
    function Assert-RAALIEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

    $script:RAALIMutationFault='none'
    function Invoke-CustomAppProductionAtomicLiveSwapMutationValidationHookV010 {
        param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
        if($script:RAALIMutationFault -ceq 'throw-after-candidate-move' -and $Checkpoint -ceq 'after-candidate-move'){throw 'recovery-aware-integration-after-candidate-move'}
    }
    function Invoke-CustomAppProductionRecoveryAwarePermitAtomicValidationHookV010 {param([string]$Checkpoint,$Context)}

    function Invoke-RAALIRecoveryAtomicV010 {
        param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)]$Prepared,[string]$Fault='none',[Nullable[DateTimeOffset]]$At=$null)
        $ctx=New-RAIssueLiveContextV010 -Bundle $X.bundle;$priorOverride=$script:RAPPFreshLiveOverride;$priorFault=$script:RAALIMutationFault
        $script:RAPPFreshLiveOverride=[pscustomobject]@{stable_tree_sha256=[string]$X.stable_tree;actual_tree_sha256=[string]$X.actual_live_tree;live_path=[string]$X.live_path;manifest_name=[string]$X.manifest_name};$script:RAALIMutationFault=$Fault
        $when=$(if($null -ne $At){[DateTimeOffset]$At}else{[DateTimeOffset]::Parse([string]$Prepared.result.post_backup_revalidated_at).AddSeconds(1)})
        try {
            Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 -RecoveryAwareStageExecutorResult $X.stage -RecoveryAwarePreparedResult $Prepared.result -Name ([string]$X.bundle.lifecycle.name) -LifecycleRow $X.bundle.lifecycle -ProvenanceRow $X.bundle.provenance -BindingRow $X.bundle.binding -LifecycleStageResult $X.bundle.stage -ShadowResult $X.bundle.shadow -RetirementResumeResult $X.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $X.q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $X.q.f.ce.q.f.f.store -ConsumptionStoreDirectory $X.f.p.store -ExpectedTransactionId ([string]$X.q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $X.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $X.q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $X.f.persisted -Permit $X.f.p.f.p.r.issuer.permit -SessionKey $script:RAIssuerKey -Now $when
        } finally {$script:RAPPFreshLiveOverride=$priorOverride;$script:RAALIMutationFault=$priorFault}
    }
    function Restore-RAALIValidV010 {param($X,$Prepared,$Result,[string]$Label)
        $restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$X.live_path) -AppBackupPath ([string]$Prepared.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$Prepared.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$Prepared.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$Prepared.result.persistence_fingerprint) -LocalAppDataRoot $X.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $X.q.f.ce.q.f.f.q.persistence.roaming
        Assert-RAALITrue ([bool]$restore.ok) ($Label+' restore failed: '+[string]$restore.reason);$clean=Remove-CustomAppProductionRecoveryAwarePermitAtomicTransactionV010 -TransactionRoot ([string]$Result.result.transaction_root) -LivePath ([string]$X.live_path);Assert-RAALITrue ([bool]$clean.ok) ($Label+' transaction cleanup failed: '+[string]$clean.reason)
    }
    function Assert-RAALINoTransactionV010 {param($X,[string]$Label);$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$X.live_path));$tx=@(Get-ChildItem -LiteralPath $parent -Force -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '^\.spotify-control-txn-[0-9a-fA-F]{32}$'});Assert-RAALITrue ($tx.Count -eq 0) ($Label+' left transaction workspace')}

    $integrationCount=0
    $valid=New-RAPPFixtureV010 -Label 'bounded-atomic-valid' -Nonce ('d'*32)
    try {
        $prep=Invoke-RAPPFixtureV010 -X $valid;Assert-RAALITrue ([bool]$prep.ok) ('valid pre-apply denied: '+[string]$prep.reason);$before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$valid.live_path)
        Assert-RAALIEq ([string]$before.tree_sha256).Trim().ToLowerInvariant() ([string]$prep.result.app_backup_tree_sha256).Trim().ToLowerInvariant() 'valid byte-real live/backup mismatch before atomic'
        Assert-RAALIFalse (([string]$valid.stable_tree).Trim().ToLowerInvariant() -ceq ([string]$before.tree_sha256).Trim().ToLowerInvariant()) 'valid fixture collapsed stable and byte-real trees'
        $r=Invoke-RAALIRecoveryAtomicV010 -X $valid -Prepared $prep;Assert-RAALITrue ([bool]$r.ok) ('valid bounded recovery atomic denied: '+[string]$r.reason);Assert-RAALITrue ([bool]$r.result.byte_real_live_reverified -and [bool]$r.result.historical_consumption_reverified_after_atomic) 'valid evidence flags missing'
        $live=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path);Assert-RAALIEq ([string]$live.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'valid post-swap live not exact staged runtime'
        $old=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$r.result.old_live_path);Assert-RAALIEq ([string]$old.tree_sha256).Trim().ToLowerInvariant() ([string]$before.tree_sha256).Trim().ToLowerInvariant() 'valid old-live not exact byte-real original'
        $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$persist.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'valid protected persistence changed';Restore-RAALIValidV010 $valid $prep $r 'valid';$integrationCount++
    } finally {Remove-RAPPFixtureV010 $valid}

    $fault=New-RAPPFixtureV010 -Label 'bounded-atomic-rollback' -Nonce ('e'*32)
    try {
        $prep=Invoke-RAPPFixtureV010 -X $fault;Assert-RAALITrue ([bool]$prep.ok) ('rollback pre-apply denied: '+[string]$prep.reason);$before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$fault.live_path)
        $r=Invoke-RAALIRecoveryAtomicV010 -X $fault -Prepared $prep -Fault 'throw-after-candidate-move';Assert-RAALIFalse ([bool]$r.ok) 'post-mutation fault unexpectedly succeeded';Assert-RAALITrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) ('post-mutation rollback not verified: '+[string]$r.reason)
        $after=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$fault.live_path);Assert-RAALIEq ([string]$after.tree_sha256).Trim().ToLowerInvariant() ([string]$before.tree_sha256).Trim().ToLowerInvariant() 'post-mutation rollback app mismatch';$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fault.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $fault.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$persist.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'post-mutation rollback persistence mismatch';Assert-RAALINoTransactionV010 $fault 'post-mutation rollback';$integrationCount++
    } finally {Remove-RAPPFixtureV010 $fault}

    $liveDrift=New-RAPPFixtureV010 -Label 'bounded-atomic-byte-real-drift' -Nonce ('f'*32)
    try {
        $prep=Invoke-RAPPFixtureV010 -X $liveDrift;Assert-RAALITrue ([bool]$prep.ok) ('byte-real drift pre-apply denied: '+[string]$prep.reason);$git=Join-Path ([string]$liveDrift.live_path) '.git';[IO.Directory]::CreateDirectory($git)|Out-Null;[IO.File]::WriteAllText((Join-Path $git 'config'),'unauthorized-byte-real-drift',[Text.UTF8Encoding]::new($false))
        $r=Invoke-RAALIRecoveryAtomicV010 -X $liveDrift -Prepared $prep;Assert-RAALIFalse ([bool]$r.ok) 'byte-real drift accepted';Assert-RAALITrue ([string]$r.reason -like '*byte-real-live-backup-mismatch*') ('byte-real drift reason '+[string]$r.reason);Assert-RAALINoTransactionV010 $liveDrift 'byte-real drift';$restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$liveDrift.live_path) -AppBackupPath ([string]$prep.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$prep.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$prep.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$prep.result.persistence_fingerprint) -LocalAppDataRoot $liveDrift.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $liveDrift.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALITrue ([bool]$restore.ok) 'byte-real drift cleanup restore failed';$integrationCount++
    } finally {Remove-RAPPFixtureV010 $liveDrift}

    $stageDrift=New-RAPPFixtureV010 -Label 'bounded-atomic-stage-drift' -Nonce ('1'*32)
    try {
        $prep=Invoke-RAPPFixtureV010 -X $stageDrift;Assert-RAALITrue ([bool]$prep.ok) ('stage drift pre-apply denied: '+[string]$prep.reason);$before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$stageDrift.live_path);[IO.File]::AppendAllText((Join-Path ([string]$stageDrift.stage.stage_path) 'index.js'),"// unauthorized-stage-drift`n",[Text.UTF8Encoding]::new($false))
        $r=Invoke-RAALIRecoveryAtomicV010 -X $stageDrift -Prepared $prep;Assert-RAALIFalse ([bool]$r.ok) 'stage drift accepted';Assert-RAALITrue ([string]$r.reason -like '*atomic-mutation-stage-runtime-mismatch*') ('stage drift reason '+[string]$r.reason);$after=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$stageDrift.live_path);Assert-RAALIEq ([string]$after.tree_sha256).Trim().ToLowerInvariant() ([string]$before.tree_sha256).Trim().ToLowerInvariant() 'stage drift changed live';Assert-RAALINoTransactionV010 $stageDrift 'stage drift';$integrationCount++
    } finally {Remove-RAPPFixtureV010 $stageDrift}

    $historical=New-RAPPFixtureV010 -Label 'bounded-atomic-unrelated-rev2' -Nonce ('2'*32)
    try {
        $prep=Invoke-RAPPFixtureV010 -X $historical;Assert-RAALITrue ([bool]$prep.ok) ('historical pre-apply denied: '+[string]$prep.reason)
        $histB=New-RAPCFixtureV010 -Label 'bounded-atomic-unrelated-rev2-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('3'*32);$bAt=$historical.q.at.AddSeconds(16)
        $bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $historical.f.persisted.persisted_snapshot.state -ExpectedConsumptionRevision 1 -At $bAt;Assert-RAALITrue ([bool]$bCandidate.ok) ('unrelated rev2 candidate failed: '+[string]$bCandidate.reason)
        $bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$historical.f.p.store};$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier -At $bAt.AddSeconds(1);Assert-RAALITrue ([bool]$bPersist.ok) ('unrelated rev2 persistence failed: '+[string]$bPersist.reason)
        $r=Invoke-RAALIRecoveryAtomicV010 -X $historical -Prepared $prep -At $bAt.AddSeconds(2);Assert-RAALITrue ([bool]$r.ok) ('historical rev1 denied after unrelated rev2: '+[string]$r.reason);Assert-RAALIEq $r.result.current_consumption_revision 2 'historical current revision';Assert-RAALIEq ([string]$r.result.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() ([string]$historical.f.persisted.receipt.persistence_envelope_sha256).Trim().ToLowerInvariant() 'historical target envelope continuity';Restore-RAALIValidV010 $historical $prep $r 'historical';$integrationCount++
    } finally {Remove-RAPPFixtureV010 $historical}

    if($integrationCount -ne 5){throw "recovery-aware bounded atomic integration count drifted: $integrationCount != 5"}
    Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_INTEGRATION_PASS count=$integrationCount recovery_closed_live_bytes=true no_test_only_baseline_bridge=true stable_and_byte_real_views_separate=true bounded_mutation=true exact_rollback=true unrelated_historical_append=true zero_apply_authority=true"
} finally {
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
    foreach($path in @($generatedFixtureFiles)){if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}}
}
