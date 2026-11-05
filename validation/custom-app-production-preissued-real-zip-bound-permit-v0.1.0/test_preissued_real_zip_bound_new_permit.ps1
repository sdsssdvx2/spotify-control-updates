$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$readiness=Join-Path $root 'validation/custom-app-production-dual-id-new-permit-readiness-v0.1.0/test_custom_app_production_dual_id_new_permit_readiness.ps1'
$bytes=[IO.File]::ReadAllBytes($readiness)
$beforeHash=(Get-FileHash -LiteralPath $readiness -Algorithm SHA256).Hash.ToLowerInvariant()
$pin='a266712e330a09944f7a8dbdca531390520545a4'
if((git -C $root hash-object $readiness).Trim()-cne$pin){throw 'Frozen qualified readiness fixture drift'}
if([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'Windows isolated RUNNER_TEMP absent'}
$originalTemp=$env:TEMP;$originalTmp=$env:TMP
$env:TEMP=$env:RUNNER_TEMP;$env:TMP=$env:RUNNER_TEMP
$workspace=$null
function Assert-PRZ([bool]$Yes,[string]$Why){if(-not$Yes){throw $Why}}
function Copy-PRZ($Value){return ($Value|ConvertTo-Json -Depth 100|ConvertFrom-Json)}
function New-PRZZip([string]$Destination){
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $z=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    try{
        foreach($item in @(
            [pscustomobject]@{name='index.js';text="console.log('synthetic-preissued-v2');"},
            [pscustomobject]@{name='manifest.json';text='{"name":"tagify"}'},
            [pscustomobject]@{name='assets/value.txt';text='byte-real-bound-before-issuer'}
        )){
            $entry=$z.CreateEntry([string]$item.name,[IO.Compression.CompressionLevel]::Optimal)
            $w=$entry.Open()
            try{$buffer=[Text.Encoding]::UTF8.GetBytes([string]$item.text);$w.Write($buffer,0,$buffer.Length)}finally{$w.Dispose()}
        }
    }finally{$z.Dispose();$stream.Dispose()}
}
try{
    . (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
    . (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.1/release-id-fix-v011.ps1')
    . (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
    . (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1')
    . (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
    . (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
    . (Join-Path $root 'validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1')
    $workspace=New-CustomAppStageWorkspaceV010
    $zip=Join-Path $workspace 'actual-source.zip'
    New-PRZZip $zip
    $observation=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode auto
    $tree=([string]$observation.tree_sha256).Trim().ToLowerInvariant()
    Assert-PRZ ([bool]$observation.manifest_valid -and [string]$observation.manifest_name -ceq 'tagify' -and $tree -cmatch '^[a-f0-9]{64}$' -and $tree -cne ('d'*64)) 'Real source ZIP did not yield authentic tagify tree'
    $archiveHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $stage=Expand-CustomAppStageArchiveV010 -ZipPath $zip -Destination (Join-Path $workspace 'stage') -ValidationRoot $workspace -WrapperMode auto -Name 'tagify' -ExpectedTreeSha256 $tree -ExpectedManifestName 'tagify'
    Assert-PRZ ([string]$stage.tree_sha256 -ceq $tree -and [bool]$stage.baseline.installable) 'Real archive did not produce exact safe staged tree'
    Assert-PRZ (-not(Test-CustomAppStageAcquisitionMutationAuthorityV010 $stage)) 'Pre-issue staging leaked mutation authority'
    Write-Host "PREISSUED_ZIP_STAGED_BEFORE_PERMIT_PASS sha=$tree"

    # Only an ephemeral fixture default is changed; no signed record, module,
    # installed program or persistent user setting is rewritten.
    $before=[Text.UTF8Encoding]::new($false).GetString($bytes)
    $old='[string]$RemoteTree=(''d''*64)'
    $replacement='[string]$RemoteTree=$(if($env:PRZ_REAL_TREE_SHA256){$env:PRZ_REAL_TREE_SHA256}else{(''d''*64)})'
    Assert-PRZ ($before.Split([string[]]@($old),[StringSplitOptions]::None).Count-eq2) 'Frozen fixture parameter patch anchor ambiguous'
    $patched=$before.Replace($old,$replacement)
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($patched,[ref]$tokens,[ref]$errors)
    Assert-PRZ ($errors.Count-eq0) 'Ephemeral remote fixture parameter PS5.1 parse failed'
    [IO.File]::WriteAllText($readiness,$patched,[Text.UTF8Encoding]::new($false))
    $env:PRZ_REAL_TREE_SHA256=$tree

    # Re-run qualified signed issuer -> nonce reserve -> durable consumption ->
    # fresh start on real ZIP hash, not a fabricated constant or forged receipt.
    . (Join-Path $root 'validation/custom-app-production-dual-id-new-permit-executor-start-gate-v0.1.0/test_custom_app_production_dual_id_new_permit_executor_start_gate.ps1')
    $fx=$script:TDSValidFixture
    Assert-PRZ ($null-ne$fx -and $null-ne$script:TDSPersisted) 'Signed source-bound Triple-ID fixture missing'
    $r=Invoke-TDSV010
    Assert-PRZ ([bool]$r.ok -and [bool]$r.staging_eligible -and -not[bool]$r.executor_may_start) ('Triple-ID signed start rejected real ZIP: '+[string]$r.reason)
    $permit=$fx.p.q.issuer.permit
    $binding=$fx.p.q.i.f.q.bundle.binding
    Assert-PRZ (([string]$permit.remote_tree_sha256).Trim().ToLowerInvariant() -ceq $tree) 'Signed Permit remote tree not equal to actual pre-issued ZIP'
    Assert-PRZ (([string]$r.decision.remote_tree_sha256).Trim().ToLowerInvariant() -ceq $tree) 'Start decision remote tree not equal to actual ZIP'
    Assert-PRZ (([string]$binding.last_remote_tree_sha256).Trim().ToLowerInvariant() -ceq $tree) 'Source binding tree not equal to actual ZIP'

    $check=Test-CustomAppStageBindingRowV010 -BindingRow $binding -ExpectedName ([string]$fx.p.q.i.f.q.bundle.lifecycle.name)
    Assert-PRZ ([bool]$check.ok) ('Stage binding denied source SHA: '+[string]$check.reason)
    $stageResult=[pscustomobject]@{
        schema=$CustomAppStageAcquisitionSchema;managed_by=$CustomAppStageWorkspaceManagedBy;status='staged-verified'
        name=[string]$check.name;source_identity=[string]$check.source;github_repo_id=[int64]$check.repo_id;surface_kind=[string]$check.surface
        commit_sha=[string]$check.commit_sha;remote_tree_sha256=$tree;binding_fingerprint=[string]$check.binding_fingerprint
        workspace_path=$workspace;stage_path=[string]$stage.stage_path;archive_sha256=$archiveHash;stage_baseline=$stage.baseline
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false
    }
    $bridge=Test-CustomAppProductionStageExecutorStageResultV010 -StageResult $stageResult -AdmissionDecision $r.decision -BindingRow $binding
    Assert-PRZ ([bool]$bridge.ok) ('Actual bytes are not source-and-Permit bound: '+[string]$bridge.reason)
    $bad=Copy-PRZ $stageResult;$bad.remote_tree_sha256=('f'*64)
    $c=Test-CustomAppProductionStageExecutorStageResultV010 -StageResult $bad -AdmissionDecision $r.decision -BindingRow $binding
    Assert-PRZ (-not[bool]$c.ok) 'Transplanted remote tree was accepted'
    $bad=Copy-PRZ $stageResult;$bad.binding_fingerprint=('0'*64)
    $c=Test-CustomAppProductionStageExecutorStageResultV010 -StageResult $bad -AdmissionDecision $r.decision -BindingRow $binding
    Assert-PRZ (-not[bool]$c.ok) 'Transplanted immutable binding was accepted'
    [IO.File]::AppendAllText((Join-Path ([string]$stage.stage_path) 'index.js'),'//tampered',[Text.UTF8Encoding]::new($false))
    $fresh=Get-CustomAppLocalRuntimeBaseline -Name ([string]$check.name) -AppPath ([string]$stage.stage_path)
    Assert-PRZ (([string]$fresh.tree_sha256).Trim().ToLowerInvariant() -cne $tree) 'Changed stage bytes were still accepted by signed source tree'
    Write-Host 'PREISSUED_REAL_ZIP_BOUND_TRIPLE_ID_PERMIT_E2E_PASS stage_before_issue=true actual_tree_sha_bound=true hmac_issued=true reservation_persisted=true single_use_consumption_persisted=true start_revalidated=true wrong_tree_denied=true wrong_binding_denied=true tamper_denied=true zero_mutation=true'
}finally{
    try{[IO.File]::WriteAllBytes($readiness,$bytes)}finally{
        Remove-Item Env:\PRZ_REAL_TREE_SHA256 -ErrorAction SilentlyContinue
        $env:TEMP=$originalTemp;$env:TMP=$originalTmp
        if(-not[string]::IsNullOrWhiteSpace($workspace) -and (Test-Path -LiteralPath $workspace)){
            try{Remove-CustomAppStageWorkspaceV010 -Path $workspace}catch{Write-Warning ('Isolated workspace cleanup failed: '+[string]$_.Exception.Message)}
        }
    }
    Assert-PRZ ((Get-FileHash -LiteralPath $readiness -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $beforeHash) 'Temporary qualified test bytes were not restored'
    Assert-PRZ ((git -C $root hash-object $readiness).Trim() -ceq $pin) 'Qualified readiness test Git identity changed'
    Write-Host 'PREISSUED_QUALIFIED_FIXTURE_SHA_RESTORED_PASS'
}
