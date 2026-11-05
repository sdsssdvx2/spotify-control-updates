# Isolated Windows CI integration: third Triple-ID real ZIP/pre-permit-backup
# -> existing atomic swap -> exact rollback. Never operate on an installed app.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'ISOLATED_WINDOWS_ACTIONS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-pre-permit-backups-bridge-v0.1.0/test_custom_app_production_pre_permit_backups_bridge.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1')
function Assert-TID([bool]$Condition,[string]$Reason){if(-not$Condition){throw ('TRIPLE_ID_ATOMIC_E2E_FAIL: '+$Reason)}}
function Assert-Isolated([string]$Path,[string]$Label){
    $base=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $pathFull=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    Assert-TID ($pathFull.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) ($Label+' escaped runner temp')
    Assert-TID ($pathFull.Substring($base.Length).TrimStart('\','/').Length -gt 8) ($Label+' insufficiently isolated')
}
$script:TIDLive=[string]$q.bundle.lifecycle.locations[0]
foreach($pair in @(
    @($script:TIDLive,'live'),
    @([string]$script:PPBStageResult.stage_result.stage_path,'stage'),
    @([string]$script:PPBValid.result.app_backup_path,'app-backup'),
    @([string]$script:PPBValid.result.persistence_backup_path,'persistence-backup'),
    @([string]$cf3.store,'consumption-store')
)){Assert-Isolated -Path ([string]$pair[0]) -Label ([string]$pair[1])}
Assert-TID ([bool]$script:PPBValid.ok -and [bool]$script:PPBStageResult.ok) 'independently qualified parents not ready'
Assert-TID (-not[bool]$script:PPBValid.production_mutation_authorized) 'prepermit bridge authority escaped'
$script:TIDArgs=@{
    AllowedRoot=[string]$script:BRHAllowedRoot
    StoreDirectory=[string]$cf3.store
    ExpectedConsumptionId=[string]$script:PPBStageResult.stage_result.consumption_id
    StageExecutorResult=$script:PPBStageResult.stage_result
    PreparedResult=$script:PPBValid.result
    Permit=$script:PPBIssuer.permit
    Name='tagify'
    LifecycleRow=$q.bundle.lifecycle
    ProvenanceRow=$q.bundle.provenance
    BindingRow=$q.bundle.binding
    ShadowProtocolQualification=$live.shadow
    LiveAttestedQualification=$live.live
    SessionKey=$script:DINPIKey
    LocalAppDataRoot=$script:PPBLocal
    AppDataRoot=$script:PPBRoaming
    Now=$script:PPBAt.AddMilliseconds(350)
}
$script:Before=Get-CustomAppUpdateTreeSnapshotV010 -Root $script:TIDLive
$script:BeforeRuntime=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
$script:BeforeGit=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $script:TIDLive '.git')
$script:BeforePersist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-TID ([string]$script:Before.tree_sha256 -ceq [string]$script:PPBValid.result.app_backup_tree_sha256) 'prepermit backup mismatch'
$script:Cases=0
function Assert-Original([string]$Label){
    $b=Get-CustomAppUpdateTreeSnapshotV010 -Root $script:TIDLive
    $r=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
    $g=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $script:TIDLive '.git')
    $p=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
    Assert-TID ([string]$b.tree_sha256 -ceq [string]$script:Before.tree_sha256 -and [int]$b.file_count -eq [int]$script:Before.file_count -and [int64]$b.total_bytes -eq [int64]$script:Before.total_bytes) ($Label+' app bytes not restored')
    Assert-TID ([string]$r.tree_sha256 -ceq [string]$script:BeforeRuntime.tree_sha256) ($Label+' runtime drift')
    Assert-TID ([string]$g.tree_sha256 -ceq [string]$script:BeforeGit.tree_sha256) ($Label+' git drift')
    Assert-TID ([string]$p.fingerprint -ceq [string]$script:BeforePersist.fingerprint) ($Label+' Spotify persistence drift')
}
function Assert-Denied($Result,[string]$Label,[bool]$ExpectedRollback=$false){
    Assert-TID ($null-ne$Result -and -not[bool]$Result.ok -and -not[bool]$Result.live_code_swap_performed) ($Label+' unexpectedly accepted')
    Assert-TID (-not[bool]$Result.production_mutation_authorized -and -not[bool]$Result.spicetify_apply_authorized) ($Label+' elevated authority')
    Assert-TID ([bool]$Result.rollback_attempted -eq $ExpectedRollback) ($Label+' unexpected rollback state')
    if($ExpectedRollback){Assert-TID ([bool]$Result.rollback_ok) ($Label+' rollback failed')}
    Assert-Original $Label
    $script:Cases++
}
$pre=Test-CustomAppProductionAtomicPreconditionsV010 @TIDArgs
Assert-TID ([bool]$pre.ok) ('new Triple-ID standard prepared result rejected: '+[string]$pre.reason)
Assert-Original 'read-only preconditions'
$script:Cases++

$bad=@{};foreach($k in $script:TIDArgs.Keys){$bad[$k]=$script:TIDArgs[$k]}
$bad.SessionKey=[byte[]](33..64)
Assert-Denied (Invoke-CustomAppProductionAtomicLiveSwapV010 @bad) 'wrong HMAC key'
$bad.Now=$script:PPBAt.AddMinutes(5);$bad.SessionKey=$script:DINPIKey
Assert-Denied (Invoke-CustomAppProductionAtomicLiveSwapV010 @bad) 'expired permit'

$stageFile=Join-Path ([string]$script:PPBStageResult.stage_result.stage_path) 'index.js'
$originalStage=[IO.File]::ReadAllBytes($stageFile)
try{
    [IO.File]::AppendAllText($stageFile,'tampered-stage-after-approval')
    Assert-Denied (Invoke-CustomAppProductionAtomicLiveSwapV010 @TIDArgs) 'stage-byte-drift'
}finally{[IO.File]::WriteAllBytes($stageFile,$originalStage)}

$script:FaultPoint=''
function Invoke-CustomAppProductionAtomicLiveSwapValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:FaultPoint -ceq $Checkpoint){throw ('isolated fixture fault: '+$Checkpoint)}
}
foreach($point in @('after-live-move','after-candidate-move')){
    $script:FaultPoint=$point
    Assert-Denied (Invoke-CustomAppProductionAtomicLiveSwapV010 @TIDArgs) ('failure-'+$point) $true
}
$script:FaultPoint=''
$result=Invoke-CustomAppProductionAtomicLiveSwapV010 @TIDArgs
Assert-TID ([bool]$result.ok -and [bool]$result.live_code_swap_performed) ('real fixture swap failed: '+[string]$result.reason)
Assert-TID (-not[bool]$result.spicetify_apply_authorized -and -not[bool]$result.production_mutation_authorized) 'atomic result granted unauthorized apply'
$nowRuntime=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $script:TIDLive
Assert-TID ([string]$nowRuntime.tree_sha256 -ceq [string]$script:PPBValid.result.stage_tree_sha256) 'live code differs from previously prepared ZIP'
$nowGit=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $script:TIDLive '.git')
$nowPersist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-TID ([string]$nowGit.tree_sha256 -ceq [string]$script:BeforeGit.tree_sha256) 'post-swap original git not preserved'
Assert-TID ([string]$nowPersist.fingerprint -ceq [string]$script:BeforePersist.fingerprint) 'post-swap Spotify persistence modified'
Assert-TID (Test-Path -LiteralPath ([string]$result.old_live_path) -PathType Container) 'rollback source absent'
$old=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$result.old_live_path)
Assert-TID ([string]$old.tree_sha256 -ceq [string]$script:Before.tree_sha256) 'old-live tree no longer exact'
$script:Cases++

# Spicetify apply is deliberately NOT called: result has no apply authority.
# Exercise the real restoration path as a simulated post-swap abort.
$rollback=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath $script:TIDLive -AppBackupPath ([string]$script:PPBValid.result.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$script:PPBValid.result.app_backup_tree_sha256) -PersistenceBackupPath ([string]$script:PPBValid.result.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$script:PPBValid.result.persistence_fingerprint) -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
Assert-TID ([bool]$rollback.ok) ('post-swap rollback failed: '+[string]$rollback.reason)
Assert-Original 'post-swap abort'
$script:Cases++
Assert-TID ($script:Cases -eq 8) ('case count='+$script:Cases)
Write-Host "TRIPLE_ID_PREPARED_ATOMIC_E2E_PASS cases=$script:Cases actual_isolated_swap=true new_permit=true durable_consumption=true prepermit_backup=true no_redownload=true fault_rollback=true exact_code_git_persistence_restore=true spicetify_not_executed=true"
