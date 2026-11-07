# Development-only V023: authenticate the existing HMAC-controlled whole-app
# swap, then exercise genuine pinned upstream Spicetify -a refresh against a
# disposable, exact-tree private clone. No production dispatcher is wired.
function New-CustomAppWholeTreeScopedNativeDeniedV023 {
    param([string]$Reason,[bool]$VendorStarted=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;vendor_started=$VendorStarted
        real_official_native_scoped_refresh_verified=$false
        signed_permit_and_whole_tree_bound=$false
        production_execution_authorized=$false
        production_mutation_authorized=$false
        apply_authorized=$false;commit_authorized=$false
    }
}
function Assert-CustomAppWholeTreeHostedPathV023 {
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$RunnerRoot)
    $root=[IO.Path]::GetFullPath($RunnerRoot).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($root.StartsWith('\\') -or $full.StartsWith('\\') -or
       -not $full.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'whole-tree-native-path-outside-hosted-runner'
    }
    $walk=$full
    while($walk.Length -ge $root.Length){
        if([IO.File]::Exists($walk) -or [IO.Directory]::Exists($walk)){
            if(((Get-Item -LiteralPath $walk -Force).Attributes -band
                  [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'whole-tree-native-reparse-denied'
            }
        }
        if($walk.Equals($root,[StringComparison]::OrdinalIgnoreCase)){break}
        $next=[IO.Path]::GetDirectoryName($walk)
        if([string]::IsNullOrWhiteSpace($next) -or $next -ceq $walk){throw 'whole-tree-native-parent-invalid'}
        $walk=$next
    }
    return $full
}
function Invoke-CustomAppQualifiedWholeTreeScopedNativeV023 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LiveAppPath,
        [Parameter(Mandatory=$true)]$StageExecutorResult,
        [Parameter(Mandatory=$true)][hashtable]$PostSwapCommon,
        [Parameter(Mandatory=$true)][DateTimeOffset]$Now,
        [Parameter(Mandatory=$true)][string]$OfficialExecutable,
        [Parameter(Mandatory=$true)][string]$ExpectedOfficialSha256,
        [Parameter(Mandatory=$true)][string]$PrivateNativeRoot
    )
    $deny={param([string]$why,[bool]$started=$false)
        New-CustomAppWholeTreeScopedNativeDeniedV023 -Reason $why -VendorStarted $started}
    # Only trusted GitHub-hosted Windows accepts this experimental real binary.
    # The environment flags are NOT a production permission mechanism.
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        return (& $deny 'whole-tree-native-real-vendor-hosted-Windows-only')
    }
    if($Name -cne 'tagify' -or $ExpectedOfficialSha256 -cne
          '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
        return (& $deny 'whole-tree-native-explicit-app-or-official-exe-pin-invalid')
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    try{
        $live=Assert-CustomAppWholeTreeHostedPathV023 -Path $LiveAppPath -RunnerRoot $runner
        $native=Assert-CustomAppWholeTreeHostedPathV023 -Path $PrivateNativeRoot -RunnerRoot $runner
        $exe=Assert-CustomAppWholeTreeHostedPathV023 -Path $OfficialExecutable -RunnerRoot $runner
    }catch{return (& $deny 'whole-tree-native-hosted-path-preflight-denied')}
    if($native.Length -ge 160 -or
       [IO.Directory]::Exists($native) -or [IO.File]::Exists($native)){
        return (& $deny 'whole-tree-native-private-root-reused-or-too-long')
    }
    if(-not[IO.File]::Exists($exe) -or
       (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne
         $ExpectedOfficialSha256){
        return (& $deny 'whole-tree-native-genuine-executable-hash-denied')
    }
    if(-not$PostSwapCommon.ContainsKey('Name') -or
       ([string]$PostSwapCommon.Name) -cne $Name -or
       -not$PostSwapCommon.ContainsKey('StageExecutorResult') -or
       -not$PostSwapCommon.ContainsKey('FinalizationResult') -or
       -not$PostSwapCommon.ContainsKey('PreparedResult') -or
       -not$PostSwapCommon.ContainsKey('SessionKey')){
        return (& $deny 'whole-tree-native-signed-postswap-input-incomplete')
    }
    if([string]$PostSwapCommon.StageExecutorResult.result_fingerprint -cne
         [string]$StageExecutorResult.result_fingerprint -or
       [string]$PostSwapCommon.ExpectedConsumptionId -cne
         [string]$StageExecutorResult.consumption_id){
        return (& $deny 'whole-tree-native-stage-or-consumption-mismatch')
    }
    # This invokes the PRE-EXISTING HMAC, durable single-use consumption,
    # provenance, backup, source-tree and current lifecycle revalidation.
    try{$admission=Resolve-CustomAppProductionPostSwapApplyAdmissionV010 @PostSwapCommon -Now $Now}
    catch{return (& $deny 'whole-tree-native-existing-postswap-admission-threw')}
    if($null-eq$admission -or -not[bool]$admission.ok -or
       -not[bool]$admission.apply_eligible -or
       [bool]$admission.production_mutation_authorized -or
       [bool]$admission.spicetify_apply_authorized -or
       [string]$admission.decision.consumption_id -cne [string]$StageExecutorResult.consumption_id -or
       [string]$admission.decision.live_tree_sha256 -cne
            [string]$StageExecutorResult.remote_tree_sha256 -or
       [string]$admission.decision.source_identity -cne
            [string]$StageExecutorResult.source_identity -or
       [string]$admission.decision.remote_commit_sha -cne
            [string]$StageExecutorResult.remote_commit_sha){
        return (& $deny ('whole-tree-native-existing-signed-postswap-admission-denied:'+[string]$admission.reason))
    }
    if(-not $live.Equals(([IO.Path]::GetFullPath([string]$PostSwapCommon.FinalizationResult.live_path).TrimEnd('\','/')),
          [StringComparison]::OrdinalIgnoreCase)){
        return (& $deny 'whole-tree-native-not-the-admitted-live-app')
    }
    try{$baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live}
    catch{return (& $deny 'whole-tree-native-live-runtime-read-denied')}
    if(-not[bool]$baseline.safe -or -not[bool]$baseline.installable -or
       [string]$baseline.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256 -or
       [int]$baseline.file_count -lt 3 -or
       @($baseline.files|Where-Object{[string]$_.path -ceq 'index.js'}).Count -ne 1 -or
       @($baseline.files|Where-Object{[string]$_.path -ceq 'manifest.json'}).Count -ne 1 -or
       @($baseline.files|Where-Object{[string]$_.path -ceq 'assets/check.txt'}).Count -ne 1){
        return (& $deny 'whole-tree-native-multifile-source-baseline-or-asset-unqualified')
    }
    # All effects, including official vendor calls, are restricted to a
    # disposable private profile under RUNNER_TEMP. The installed Spotify,
    # current user Spicetify profile and real XPUI are never referenced.
    $clone=Join-Path $native 'CustomApps\tagify'
    $spotify=Join-Path $native 'FakeSpotify'
    $xpui=Join-Path $spotify 'Apps\xpui'
    $backup=Join-Path $native 'Backup\xpui.spa'
    $config=Join-Path $native 'config-xpui.ini'
    $prefs=Join-Path $native 'prefs'
    $target=Join-Path $xpui 'spicetify-routes-tagify.js'
    $bystander=Join-Path $xpui 'spicetify-routes-beta.js'
    $sentinel=Join-Path $xpui 'private-user-sentinel.dat'
    $betaContent='WHOLE_TREE_UNRELATED_BETA_MUST_NOT_CHANGE'
    $sentinelContent='WHOLE_TREE_UNRELATED_SENTINEL'
    try{
        foreach($dir in @($clone,$xpui,(Split-Path $backup -Parent),
                           (Join-Path $native 'Roaming'),(Join-Path $native 'Local'))){
            [void][IO.Directory]::CreateDirectory($dir)
        }
        foreach($file in @($baseline.files)){
            $rel=[string]$file.path
            $normalized=$rel.Replace('/','\')
            if($normalized -match '(^|\\)\.\.(\\|$)' -or
               $normalized.StartsWith('\') -or $normalized.Contains(':') -or
               -not($normalized -cmatch '^[A-Za-z0-9_.\\/-]+$')){
                throw 'whole-tree-native-relative-source-path-denied'
            }
            $from=Assert-CustomAppWholeTreeHostedPathV023 -Path (Join-Path $live $normalized) -RunnerRoot $runner
            $dest=Assert-CustomAppWholeTreeHostedPathV023 -Path (Join-Path $clone $normalized) -RunnerRoot $runner
            [void][IO.Directory]::CreateDirectory(([IO.Path]::GetDirectoryName($dest)))
            [IO.File]::Copy($from,$dest,$false)
            if((Get-FileHash $dest -Algorithm SHA256).Hash.ToLowerInvariant() -cne
               [string]$file.sha256){throw 'whole-tree-native-source-copy-byte-drift'}
        }
        $copied=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $clone
        if(-not[bool]$copied.safe -or
           [string]$copied.tree_sha256 -cne [string]$baseline.tree_sha256 -or
           [int]$copied.file_count -ne [int]$baseline.file_count){
            throw 'whole-tree-native-private-full-tree-clone-drift'
        }
        [IO.File]::WriteAllText($prefs,"app.last-launched-version = 1.2.3"+[Environment]::NewLine)
        [IO.File]::WriteAllBytes($backup,[byte[]](0x50,0x4b))
        [IO.File]::WriteAllText($target,'WHOLE_TREE_BEFORE_TARGET')
        [IO.File]::WriteAllText($bystander,$betaContent)
        [IO.File]::WriteAllText($sentinel,$sentinelContent)
        $ini='[Setting]'+[Environment]::NewLine+
          'spotify_path = '+$spotify+[Environment]::NewLine+
          'prefs_path = '+$prefs+[Environment]::NewLine+
          'check_spicetify_update = false'+[Environment]::NewLine+
          'current_theme = '+[Environment]::NewLine+
          '[Backup]'+[Environment]::NewLine+
          'version = 1.2.3'+[Environment]::NewLine+
          'with = 2.46.4'+[Environment]::NewLine+
          '[AdditionalOptions]'+[Environment]::NewLine+
          'custom_apps = tagify'+[Environment]::NewLine
        [IO.File]::WriteAllText($config,$ini,([Text.UTF8Encoding]::new($false)))
    }catch{return (& $deny ('whole-tree-native-disposable-setup-denied:'+[string]$_.Exception.Message))}
    # Only these private surfaces may be changed by the official CLI.
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$exe
    $psi.Arguments='--bypass-admin -n -a refresh'
    $psi.WorkingDirectory=$native
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$false
    $psi.RedirectStandardError=$false
    $psi.EnvironmentVariables['SPICETIFY_CONFIG']=$native
    $psi.EnvironmentVariables['SPICETIFY_STATE']=$native
    $psi.EnvironmentVariables['APPDATA']=(Join-Path $native 'Roaming')
    $psi.EnvironmentVariables['LOCALAPPDATA']=(Join-Path $native 'Local')
    $started=$false
    try{
        $p=New-Object Diagnostics.Process
        $p.StartInfo=$psi
        if(-not$p.Start()){throw 'whole-tree-native-official-cli-did-not-start'}
        $started=$true
        if(-not$p.WaitForExit(60000)){
            $p.Kill();[void]$p.WaitForExit()
            throw 'whole-tree-native-official-cli-timed-out'
        }
        if([int]$p.ExitCode -ne 0){throw ('whole-tree-native-official-cli-exit-'+$p.ExitCode)}
        if(-not[IO.File]::Exists($target) -or
           -not[IO.File]::ReadAllText($target).Contains('tagify-version-2')){
            throw 'whole-tree-native-official-cli-target-missing-or-unpatched'
        }
        if([IO.File]::ReadAllText($bystander) -cne $betaContent -or
           [IO.File]::ReadAllText($sentinel) -cne $sentinelContent){
            throw 'whole-tree-native-official-cli-changed-nontarget'
        }
        $after=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $live
        $afterClone=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $clone
        if([string]$after.tree_sha256 -cne [string]$baseline.tree_sha256 -or
           [string]$afterClone.tree_sha256 -cne [string]$baseline.tree_sha256){
            throw 'whole-tree-native-official-cli-changed-approved-live-or-clone'
        }
        Write-Host 'WHOLE_TREE_V023_REAL_HMAC_STAGE_FULL_DIR_OFFICIAL_SCOPED_REFRESH_PASS'
        return [pscustomobject]@{
            ok=$true;reason='official-single-app-refresh-on-approved-HMAC-whole-tree-private-clone'
            name=$Name;source_identity=[string]$StageExecutorResult.source_identity
            consumption_id=[string]$StageExecutorResult.consumption_id
            source_tree_sha256=[string]$baseline.tree_sha256
            native_xpui_target_sha256=(Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
            vendor_started=$true;real_official_native_scoped_refresh_verified=$true
            signed_permit_and_whole_tree_bound=$true
            full_tree_file_count=[int]$baseline.file_count
            nontarget_unchanged=$true;live_tree_unchanged=$true
            production_execution_authorized=$false
            production_mutation_authorized=$false;apply_authorized=$false
            commit_authorized=$false
        }
    }catch{return (& $deny ('whole-tree-native-hosted-official-refresh-failed:'+[string]$_.Exception.Message) $started)}
    finally{if($null-ne$p){$p.Dispose()}}
}
