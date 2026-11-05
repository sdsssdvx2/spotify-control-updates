$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# The parent fixture is the independently qualified 18-case byte-real new
# permit transaction with a durable, physical append-only consumption store.
. (Join-Path $root 'validation/custom-app-production-byte-real-prepared-stage-handoff-v0.1.0/test_custom_app_production_byte_real_prepared_stage_handoff.ps1')
. (Join-Path $root 'validation/custom-app-production-stage-acquisition-admission-v0.1.0/custom-app-production-stage-acquisition-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-prepared-stage-executor-bridge.ps1')

function Assert-PSB([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
function Assert-PSBDenied($Value,[string]$Label){
    Assert-PSB ($null-ne$Value -and -not[bool]$Value.ok) ("$Label unexpected success: "+[string]$Value.reason)
    Assert-PSB (-not[bool]$Value.ready_to_apply -and -not[bool]$Value.production_mutation_authorized) ("$Label mutation authority escaped")
}
function Copy-PSB($Object){return ($Object|ConvertTo-Json -Depth 100|ConvertFrom-Json)}

$script:PSBWorkspace=New-CustomAppStageWorkspaceV010
$script:PSBZip=Join-Path $script:PSBWorkspace 'remote.zip'
$script:PSBStage=Join-Path $script:PSBWorkspace 'stage'
[IO.File]::Copy($script:BRHZip,$script:PSBZip,$false)
$script:PSBZipSha=(Get-FileHash -LiteralPath $script:PSBZip -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-PSB ($script:PSBZipSha -ceq $script:BRHZipHash) 'reused ZIP differs from signed archive'
$script:PSBExtract=Expand-CustomAppStageArchiveV010 -ZipPath $script:PSBZip -Destination $script:PSBStage -ValidationRoot $script:PSBWorkspace -WrapperMode auto -Name 'tagify' -ExpectedTreeSha256 ([string]$script:BRHExtract.tree_sha256) -ExpectedManifestName 'tagify'
Assert-PSB ([string]$script:PSBExtract.tree_sha256 -ceq [string]$script:BRHExtract.tree_sha256) 'prepared stage byte identity drift'
$script:PSBArgs=@{
    Name='tagify';WorkspacePath=$script:PSBWorkspace;ArchivePath=$script:PSBZip
    ArchiveSha256=$script:PSBZipSha;StagePath=$script:PSBStage
    ExtractedStageResult=$script:PSBExtract;LifecycleRow=$q.bundle.lifecycle
    ProvenanceRow=$q.bundle.provenance;BindingRow=$q.bundle.binding
    IssuerResult=$issued;ExecutorStartResult=$start;SessionKey=$script:DINPIKey
    AllowedRoot=$script:BRHAllowedRoot;ConsumptionStoreDirectory=$script:BRHConsumptionStore
    CurrentBaseline=$live.baseline;ShadowProtocolQualification=$live.shadow
    LiveAttestedQualification=$live.live;Now=$now;PostStageNow=$now.AddMilliseconds(100)
}

function Invoke-PSB {
    param([AllowNull()][hashtable]$Overrides=$null)
    $p=@{};foreach($key in $script:PSBArgs.Keys){$p[$key]=$script:PSBArgs[$key]}
    if($null-ne$Overrides){foreach($key in $Overrides.Keys){$p[$key]=$Overrides[$key]}}
    return Invoke-CustomAppProductionPreparedStageExecutorBridgeV010 @p
}

$count=0
$success=Invoke-PSB
Assert-PSB ([bool]$success.ok) ('prepared exact stage executor denied: '+[string]$success.reason)
Assert-PSB ([bool]$success.stage_prepared_before_permit -and -not[bool]$success.fetched_again -and [bool]$success.post_stage_revalidated) 'reused-stage flow unexpectedly downloaded or omitted revalidation'
Assert-PSB ([bool]$success.physical_store_reloaded_twice -and -not[bool]$success.ready_to_apply -and -not[bool]$success.production_mutation_authorized) 'success returned unsafe authority'
$legacyCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $success.stage_result
Assert-PSB ([bool]$legacyCheck.ok) ('existing prepared-stage output contract rejected: '+[string]$legacyCheck.reason)
Assert-PSB ([string]$success.stage_result.remote_tree_sha256 -ceq [string]$q.bundle.binding.last_remote_tree_sha256) 'standard stage output wrong remote tree'
Assert-PSB ([string]$success.stage_result.consumption_id -ceq [string]$saved.receipt.consumption_id) 'standard stage output wrong physical consumption ID'
$count++

$repeat=Invoke-PSB
Assert-PSB ([bool]$repeat.ok -and [string]$repeat.stage_result.result_fingerprint -ceq [string]$success.stage_result.result_fingerprint) 'repeat read-only stage dispatch unstable'
$count++

$wrongArchive=Invoke-PSB -Overrides @{ArchiveSha256=('0'*64)}
Assert-PSBDenied $wrongArchive 'wrong signed archive digest'
$count++

$wrongKey=Invoke-PSB -Overrides @{SessionKey=[byte[]](33..64)}
Assert-PSBDenied $wrongKey 'incorrect ephemeral signing key'
$count++

$wrongPermit=Copy-PSB $issued
$wrongPermit.permit.token_id=('f'*64)
$denied=Invoke-PSB -Overrides @{IssuerResult=$wrongPermit}
Assert-PSBDenied $denied 'transplanted generic permit under signed issuer'
$count++

$removed=Copy-PSB $q.bundle.lifecycle;$removed.user_removed=$true
$denied=Invoke-PSB -Overrides @{LifecycleRow=$removed}
Assert-PSBDenied $denied 'lifecycle user removal'
$count++

$expired=Invoke-PSB -Overrides @{Now=$now.AddSeconds(9);PostStageNow=$now.AddSeconds(9)}
Assert-PSBDenied $expired 'expired start eligibility'
$count++

$backwards=Invoke-PSB -Overrides @{PostStageNow=$now.AddMilliseconds(-1)}
Assert-PSBDenied $backwards 'post-stage time reversal'
$count++

$tooLong=Invoke-PSB -Overrides @{PostStageNow=$now.AddSeconds(6)}
Assert-PSBDenied $tooLong 'post-stage unbounded duration'
$count++

$zipBytes=[IO.File]::ReadAllBytes($script:PSBZip)
try{
    [IO.File]::AppendAllText($script:PSBZip,'zip mutation between handoff and legacy admission')
    $denied=Invoke-PSB
    Assert-PSBDenied $denied 'archive changed after permit'
}finally{[IO.File]::WriteAllBytes($script:PSBZip,$zipBytes)}
$count++

$stageFile=Join-Path $script:PSBStage 'index.js'
$stageBytes=[IO.File]::ReadAllBytes($stageFile)
try{
    [IO.File]::AppendAllText($stageFile,'stage bytes changed')
    $denied=Invoke-PSB
    Assert-PSBDenied $denied 'stage changed after permit'
}finally{[IO.File]::WriteAllBytes($stageFile,$stageBytes)}
$count++

$physical=Get-CustomAppProductionConsumptionPersistencePathsV010 -AllowedRoot $script:BRHAllowedRoot -StoreDirectory $script:BRHConsumptionStore
$currentBytes=[IO.File]::ReadAllBytes([string]$physical.current)
try{
    [IO.File]::AppendAllText([string]$physical.current,'tampered-current-pointer')
    $denied=Invoke-PSB
    Assert-PSBDenied $denied 'physical consumption pointer tampered'
}finally{[IO.File]::WriteAllBytes([string]$physical.current,$currentBytes)}
$count++

$wrongLayout=Invoke-PSB -Overrides @{StagePath=$script:BRHStage;WorkspacePath=$script:BRHWorkspace;ArchivePath=$script:BRHZip;ExtractedStageResult=$script:BRHExtract}
Assert-PSBDenied $wrongLayout 'nonstandard stage directory cannot enter generic executor'
$count++

$final=Invoke-PSB
Assert-PSB ([bool]$final.ok) ('prepared-stage after negative probes denied: '+[string]$final.reason)
Assert-PSB ([string]$final.stage_result.result_fingerprint -ceq [string]$success.stage_result.result_fingerprint) 'negative probes modified deterministic standard stage receipt'
$count++

if($count-ne14){throw "prepared-stage bridge matrix cases=$count expected=14"}
Write-Host "CUSTOM_APP_PRODUCTION_PREPARED_STAGE_BRIDGE_PASS cases=$count no_redownload=true real_zip=true stage_admission_pre_post=true existing_stage_executor_receipt_valid=true same_consumption_store=true wrong_permit_and_archive_denied=true no_install=true"
