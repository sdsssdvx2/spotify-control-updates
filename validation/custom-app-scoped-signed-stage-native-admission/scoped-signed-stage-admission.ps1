# V021: read-only bridge from the real-byte HMAC-qualified prepared ZIP
# to V020's strictly limited single-index.js candidate. Never authorizes apply.
function New-CustomAppScopedSignedStageDeniedV021 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;candidate_index_path=$null
        authenticated_stage_and_permit_verified=$false
        single_index_subset_qualified=$false;ready_to_apply=$false
        source_swap_authorized=$false;spicetify_refresh_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Resolve-CustomAppScopedSignedStageCandidateV021 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$WorkspacePath,
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$ArchiveSha256,
        [Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)]$ExtractedStageResult,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ExecutorStartResult,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param($why) New-CustomAppScopedSignedStageDeniedV021 -Reason ([string]$why)}
    # Hosted-only is an experiment guard, NOT an authorization mechanism for a shipped app.
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
        return (& $deny 'signed-stage-scoped-bridge-hosted-only')
    }
    foreach($fn in @('Test-CustomAppProductionByteRealPreparedStageHandoffV010',
                     'Get-CustomAppLocalRuntimeBaseline')){
        if(-not(Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)){
            return (& $deny ('signed-stage-qualified-dependency-missing-'+$fn))
        }
    }
    if($Name -cnotmatch '^[a-z][a-z0-9_-]{1,63}$'){
        return (& $deny 'signed-stage-scoped-app-name-invalid')
    }
    $key=$Name.Trim().ToLowerInvariant()
    $p=@{
        Name=$key;WorkspacePath=$WorkspacePath;ArchivePath=$ArchivePath
        ArchiveSha256=$ArchiveSha256;StagePath=$StagePath
        ExtractedStageResult=$ExtractedStageResult;LifecycleRow=$LifecycleRow
        BindingRow=$BindingRow;IssuerResult=$IssuerResult
        ExecutorStartResult=$ExecutorStartResult;SessionKey=$SessionKey
        AllowedRoot=$AllowedRoot;ConsumptionStoreDirectory=$ConsumptionStoreDirectory
        Now=$Now
    }
    try{$handoff=Test-CustomAppProductionByteRealPreparedStageHandoffV010 @p}
    catch{return (& $deny 'signed-stage-handoff-threw')}
    if($null-eq$handoff -or -not[bool]$handoff.ok -or
       -not[bool]$handoff.byte_real_stage_attested -or
       -not[bool]$handoff.new_permit_bound -or
       -not[bool]$handoff.fresh_start_attested -or
       -not[bool]$handoff.consumption_store_reloaded -or
       [bool]$handoff.ready_to_apply -or
       [bool]$handoff.production_mutation_authorized){
        return (& $deny ('signed-stage-handoff-invalid-or-unbound:'+[string]$handoff.reason))
    }
    try{
        $stage=[IO.Path]::GetFullPath($StagePath).TrimEnd('\','/')
        $baseline=Get-CustomAppLocalRuntimeBaseline -Name $key -AppPath $stage
    }catch{return (& $deny 'signed-stage-candidate-current-baseline-invalid')}
    if(-not[bool]$baseline.safe -or -not[bool]$baseline.installable -or
       [bool]$baseline.mutation_authorized -or
       [int]$baseline.file_count -ne 2 -or
       [string]$baseline.tree_sha256 -cne [string]$handoff.stage_tree_sha256 -or
       [string]$baseline.manifest_name -cne [string]$BindingRow.binding.manifest_name -or
       -not([string]$baseline.path).Equals($stage,[StringComparison]::OrdinalIgnoreCase)){
        return (& $deny 'signed-stage-scoped-subset-baseline-or-manifest-invalid')
    }
    # Official custom apps can have assets. V020 cannot swap them, so this
    # exact subset deliberately rejects third files instead of losing data.
    $idx=@($baseline.files|Where-Object{[string]$_.path -ceq 'index.js'})
    $man=@($baseline.files|Where-Object{[string]$_.path -ceq 'manifest.json'})
    if($idx.Count -ne 1 -or $man.Count -ne 1 -or
       @($baseline.files|Where-Object{[string]$_.path -cnotin @('index.js','manifest.json')}).Count -ne 0){
        return (& $deny 'signed-stage-scoped-subset-multifile-unsupported')
    }
    $indexPath=Join-Path $stage 'index.js'
    $manifestPath=Join-Path $stage 'manifest.json'
    try{
        # Freeze exact bytes in-memory. Downstream must never trust a mutable
        # stage path after this read-only attestation, only this digest-bound
        # byte snapshot (and must rerun the fresh permit gate before apply).
        $indexBytes=[IO.File]::ReadAllBytes($indexPath)
        $manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
        $sha=[Security.Cryptography.SHA256]::Create()
        try{
            $indexSha=([BitConverter]::ToString($sha.ComputeHash($indexBytes))).Replace('-','').ToLowerInvariant()
            $manifestSha=([BitConverter]::ToString($sha.ComputeHash($manifestBytes))).Replace('-','').ToLowerInvariant()
        }finally{$sha.Dispose()}
    }catch{return (& $deny 'signed-stage-scoped-subset-read-drift')}
    if($indexBytes.Length -ne [int64]$idx[0].size -or
       $manifestBytes.Length -ne [int64]$man[0].size -or
       $indexSha -cne [string]$idx[0].sha256 -or
       $manifestSha -cne [string]$man[0].sha256 -or
       [int64]$idx[0].size -lt 1 -or [int64]$idx[0].size -gt 2097152 -or
       $indexSha -cnotmatch '^[a-f0-9]{64}$'){
        return (& $deny 'signed-stage-scoped-index-manifest-digest-drift')
    }
    # A two-file stage can still declare unshipped runtime dependencies
    # through manifest subfiles/subfiles_extension. Only dependency-free
    # index+manifest is safe for the V020 single-index subset.
    try{
        $manifestObject=([Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json -ErrorAction Stop)
    }catch{return (& $deny 'signed-stage-scoped-manifest-parse-failed')}
    foreach($field in @('subfiles','subfiles_extension')){
        $property=$manifestObject.PSObject.Properties[$field]
        if($null-ne$property){
            if($null-eq$property.Value -or -not($property.Value -is [Array]) -or
               @($property.Value).Count -ne 0){
                return (& $deny ('signed-stage-scoped-manifest-dependencies-not-supported-'+$field))
            }
        }
    }
    # Manifest parse and index selection derive from the exact byte snapshots
    # already pinned to the authenticated stage tree; no second path reopening.
    $receipt=$IssuerResult.receipt
    if(([string]$receipt.name).Trim().ToLowerInvariant() -cne $key -or
       ([string]$receipt.current_remote_tree_sha256).Trim().ToLowerInvariant() -cne
          [string]$handoff.stage_tree_sha256 -or
       ([string]$handoff.consumption_id).Trim().ToLowerInvariant() -cne
          ([string]$ExecutorStartResult.receipt.consumption_id).Trim().ToLowerInvariant()){
        return (& $deny 'signed-stage-scoped-signed-identity-drift')
    }
    return [pscustomobject]@{
        ok=$true;reason='hmac-bound-real-prepared-stage-single-index-subset-readonly'
        candidate_index_path=$indexPath;candidate_index_sha256=$indexSha
        candidate_index_bytes_base64=[Convert]::ToBase64String($indexBytes)
        candidate_is_immutable_snapshot=$true
        manifest_sha256=$manifestSha;manifest_name=[string]$baseline.manifest_name
        stage_tree_sha256=[string]$baseline.tree_sha256
        source_identity=[string]$BindingRow.source_identity
        remote_commit_sha=[string]$BindingRow.last_remote_commit_sha
        consumption_id=[string]$handoff.consumption_id
        authenticated_stage_and_permit_verified=$true
        single_index_subset_qualified=$true
        ready_to_apply=$false;source_swap_authorized=$false
        spicetify_refresh_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Test-CustomAppScopedSignedStageSelfTestV021 {
    if($script:CustomAppProductionPipelineEnabled){throw 'signed-stage-bridge-must-not-enable-fullchain'}
    $denied=New-CustomAppScopedSignedStageDeniedV021 -Reason 'selftest'
    if([bool]$denied.ok -or [bool]$denied.production_mutation_authorized){throw 'signed-stage-deny-not-fail-closed'}
    Write-Host 'SIGNED_STAGE_NATIVE_V021_READONLY_SELFTEST_PASS'
}
