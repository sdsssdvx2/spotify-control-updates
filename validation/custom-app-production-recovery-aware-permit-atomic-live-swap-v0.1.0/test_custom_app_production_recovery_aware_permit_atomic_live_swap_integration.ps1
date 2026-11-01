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
    $matrix=[regex]::Match($normalized,'(?im)^\$(?:count|casecount|testcount|total)\s*=\s*0\s*$')
    if(-not $matrix.Success){throw "fixture-only matrix boundary missing: $Label"}
    $prefix=$normalized.Substring(0,$matrix.Index)
    $lines=@($prefix -split "`n")
    $importPattern='^\s*\.\s*\(Join-Path\s+\$root\s+''(?<rel>validation/[^'']+/test_[^'']+\.ps1)''\)\s*$'
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i] -match $importPattern){
            $parentRel=([string]$Matches['rel']).Replace('\','/')
            $fixtureRel=New-RAALFixtureOnlyCopyV010 -RelativePath $parentRel
            $lines[$i]=$lines[$i].Replace($parentRel,$fixtureRel)
        }
    }
    return (($lines -join "`n")+"`n")
}

function New-RAALFixtureOnlyCopyV010 {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $rel=$RelativePath.Replace('\','/')
    if($script:RAALFixtureOnlyMap.ContainsKey($rel)){return [string]$script:RAALFixtureOnlyMap[$rel]}
    $full=Join-Path $root ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw "fixture-only source missing: $rel"}
    $dirRel=[IO.Path]::GetDirectoryName($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
    $leaf=[IO.Path]::GetFileNameWithoutExtension($rel)
    $genName=$leaf+'.fixture-only.'+[Guid]::NewGuid().ToString('N')+'.ps1'
    $genRel=(Join-Path $dirRel $genName).Replace('\','/')
    $genFull=Join-Path $root ($genRel.Replace('/',[IO.Path]::DirectorySeparatorChar))
    $script:RAALFixtureOnlyMap[$rel]=$genRel
    $sourceText=[IO.File]::ReadAllText($full,[Text.UTF8Encoding]::new($false))
    $fixtureText=ConvertTo-RAALFixtureOnlyPrefixV010 -Text $sourceText -Label $rel
    [IO.File]::WriteAllText($genFull,$fixtureText,[Text.UTF8Encoding]::new($false))
    $generatedFixtureFiles.Add($genFull)
    return $genRel
}

$source=Join-Path $root ($preApplyRel.Replace('/',[IO.Path]::DirectorySeparatorChar))
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false)).Replace("`r`n","`n")

# Keep the exact recovery-closed semantics validated by the parent r4 harness: do not
# mutate live bytes after durable recovery closure merely to manufacture .git coverage.
$startMarker='    # Root VCS metadata is deliberately invisible to the runtime baseline but must be'
$endMarker="'root git metadata changed runtime baseline'"
$start=Get-RAALIntegrationUniqueMarkerIndexV010 -Text $text -Marker $startMarker -Label 'post-recovery-vcs-start'
$endPhrase=Get-RAALIntegrationUniqueMarkerIndexV010 -Text $text -Marker $endMarker -Label 'post-recovery-vcs-end'
if($endPhrase -le $start){throw 'integration semantic VCS patch boundaries reversed'}
$end=$text.IndexOf("`n",$endPhrase,[StringComparison]::Ordinal)
if($end -lt 0){$end=$text.Length}else{$end++}
$replacement=@'
    # Recovery closure is durable evidence. Keep the live tree byte-identical after
    # closure; the exact generic atomic parent matrix separately proves .git handling.
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
'@.Replace("`r`n","`n")
$patched=$text.Substring(0,$start)+$replacement+$text.Substring($end)
if($patched.IndexOf($startMarker,[StringComparison]::Ordinal) -ge 0){throw 'integration recovery-closed semantic patch failed'}

# Recursively replace every inherited test_*.ps1 import with a temporary copy that
# retains only setup/fixture/helper definitions before its matrix counter. Core files
# remain the exact qualified production-validation implementations; only already-green
# parent test matrices are skipped. This prevents 30+ minute duplicate matrix replay.
$fixtureOnly=ConvertTo-RAALFixtureOnlyPrefixV010 -Text $patched -Label $preApplyRel
if($fixtureOnly.IndexOf('function New-RAPPFixtureV010',[StringComparison]::Ordinal) -lt 0 -or $fixtureOnly.IndexOf('function Invoke-RAPPFixtureV010',[StringComparison]::Ordinal) -lt 0){throw 'integration fixture-only pre-apply helpers missing'}
if($fixtureOnly -match '(?im)^\$(?:count|casecount|testcount|total)\s*=\s*0\s*$'){throw 'integration parent matrix survived recursive fixture isolation'}

$integration=@'

# ---- Recovery-aware pre-apply -> exact generic atomic composition ----
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-atomic-live-swap-v0.1.0/custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')

function Assert-RAALITrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAALIFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAALIEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$script:RAALIAtomicFault='none'
function Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:RAALIAtomicFault -ceq 'throw-after-candidate-move' -and $Checkpoint -ceq 'after-candidate-move'){throw 'recovery-aware-integration-after-candidate-move'}
}

function Invoke-RAALIRecoveryAtomicV010 {
    param([Parameter(Mandatory=$true)]$X,[Parameter(Mandatory=$true)]$Prepared,[string]$Fault='none')
    $ctx=New-RAIssueLiveContextV010 -Bundle $X.bundle
    $priorOverride=$script:RAPPFreshLiveOverride
    $priorFault=$script:RAALIAtomicFault
    $script:RAPPFreshLiveOverride=[pscustomobject]@{stable_tree_sha256=[string]$X.stable_tree;actual_tree_sha256=[string]$X.actual_live_tree;live_path=[string]$X.live_path;manifest_name=[string]$X.manifest_name}
    $script:RAALIAtomicFault=$Fault
    $at=[DateTimeOffset]::Parse([string]$Prepared.result.post_backup_revalidated_at).AddSeconds(1)
    try {
        return Invoke-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapV010 -RecoveryAwareStageExecutorResult $X.stage -RecoveryAwarePreparedResult $Prepared.result -Name ([string]$X.bundle.lifecycle.name) -LifecycleRow $X.bundle.lifecycle -ProvenanceRow $X.bundle.provenance -BindingRow $X.bundle.binding -LifecycleStageResult $X.bundle.stage -ShadowResult $X.bundle.shadow -RetirementResumeResult $X.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $X.q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $X.q.f.ce.q.f.f.store -ConsumptionStoreDirectory $X.f.p.store -ExpectedTransactionId ([string]$X.q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $X.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $X.q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $X.f.persisted -Permit $X.f.p.f.p.r.issuer.permit -SessionKey $script:RAIssuerKey -Now $at
    } finally {
        $script:RAPPFreshLiveOverride=$priorOverride
        $script:RAALIAtomicFault=$priorFault
    }
}

function Remove-RAALITransactionRootsV010($X){
    try {
        $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$X.live_path))
        foreach($item in @(Get-ChildItem -LiteralPath $parent -Force -Directory -ErrorAction SilentlyContinue | Where-Object{$_.Name -match '^\.spotify-control-txn-[0-9a-fA-F]{32}$'})){
            Remove-CustomAppAtomicDirectoryV010 -Path $item.FullName -ExpectedParent $parent -ExpectedName $item.Name
        }
    } catch {}
}

$integrationCount=0
$ix=New-RAPPFixtureV010 -Label 'atomic-integration-valid' -Nonce ('d'*32)
try {
    $prep=Invoke-RAPPFixtureV010 -X $ix
    Assert-RAALITrue ([bool]$prep.ok) ('integration pre-apply denied: '+[string]$prep.reason)
    $beforeFull=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$ix.live_path)
    $r=Invoke-RAALIRecoveryAtomicV010 -X $ix -Prepared $prep
    Assert-RAALITrue ([bool]$r.ok) ('recovery-aware atomic composition denied: '+[string]$r.reason)
    Assert-RAALITrue ([bool]$r.recovery_revalidated_immediately_before_atomic -and [bool]$r.live_code_swap_performed) 'valid composition lost recovery/swap proof'
    Assert-RAALITrue ([bool]$r.requires_transaction_finalization -and [bool]$r.requires_spicetify_apply_phase) 'valid composition lost downstream separation'
    foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALIFalse ([bool]$r.result.$f) ('valid composition escaped '+$f)}
    $resultCheck=Test-CustomAppProductionRecoveryAwarePermitAtomicLiveSwapResultV010 -Result $r.result
    Assert-RAALITrue ([bool]$resultCheck.ok) ('valid composition result invalid: '+[string]$resultCheck.reason)
    $liveRuntime=& $script:RASEOriginalLocalBaseline -Name ([string]$ix.bundle.lifecycle.name) -AppPath ([string]$ix.live_path)
    Assert-RAALIEq ([string]$liveRuntime.tree_sha256).Trim().ToLowerInvariant() ([string]$ix.remote_tree).Trim().ToLowerInvariant() 'valid composition live runtime not exact remote tree'
    $old=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$r.result.old_live_path)
    Assert-RAALIEq ([string]$old.tree_sha256).Trim().ToLowerInvariant() ([string]$beforeFull.tree_sha256).Trim().ToLowerInvariant() 'valid composition old-live not exact pre-swap tree'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $ix.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $ix.q.f.ce.q.f.f.q.persistence.roaming
    Assert-RAALIEq ([string]$persist.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'valid composition changed protected persistence'
    $restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$ix.live_path) -AppBackupPath ([string]$prep.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$prep.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$prep.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$prep.result.persistence_fingerprint) -LocalAppDataRoot $ix.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $ix.q.f.ce.q.f.f.q.persistence.roaming
    Assert-RAALITrue ([bool]$restore.ok) ('valid composition cleanup restore failed: '+[string]$restore.reason)
    $integrationCount++
} finally {Remove-RAALITransactionRootsV010 $ix;Remove-RAPPFixtureV010 $ix}

$fx=New-RAPPFixtureV010 -Label 'atomic-integration-rollback' -Nonce ('e'*32)
try {
    $prep=Invoke-RAPPFixtureV010 -X $fx
    Assert-RAALITrue ([bool]$prep.ok) ('rollback integration pre-apply denied: '+[string]$prep.reason)
    $beforeFull=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$fx.live_path)
    $r=Invoke-RAALIRecoveryAtomicV010 -X $fx -Prepared $prep -Fault 'throw-after-candidate-move'
    Assert-RAALIFalse ([bool]$r.ok) 'post-mutation integration fault unexpectedly succeeded'
    Assert-RAALITrue ([bool]$r.rollback_attempted -and [bool]$r.rollback_ok) ('post-mutation integration rollback not verified: '+[string]$r.reason)
    foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALIFalse ([bool]$r.$f) ('rollback composition escaped '+$f)}
    $afterFull=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$fx.live_path)
    Assert-RAALIEq ([string]$afterFull.tree_sha256).Trim().ToLowerInvariant() ([string]$beforeFull.tree_sha256).Trim().ToLowerInvariant() 'post-mutation integration rollback app tree mismatch'
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fx.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $fx.q.f.ce.q.f.f.q.persistence.roaming
    Assert-RAALIEq ([string]$persist.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'post-mutation integration rollback persistence mismatch'
    $integrationCount++
} finally {Remove-RAALITransactionRootsV010 $fx;Remove-RAPPFixtureV010 $fx}

if($integrationCount -ne 2){throw "recovery-aware atomic integration count drifted: $integrationCount"}
Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_INTEGRATION_PASS count=$integrationCount recovery_closed_live_bytes=true recursive_fixture_only_parent=true actual_recovery_pre_apply=true exact_generic_atomic=true exact_rollback=true zero_apply_authority=true"
'@.Replace("`r`n","`n")

$temp=Join-Path $preApplyDir ('test_custom_app_production_recovery_aware_permit_atomic_integration_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try {
    [IO.File]::WriteAllText($temp,($fixtureOnly+$integration),[Text.UTF8Encoding]::new($false))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "generated recovery-aware atomic integration failed exit=$LASTEXITCODE"}
} finally {
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
    foreach($path in @($generatedFixtureFiles)){if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)}}
}
