# V026. Approved installed-only Custom App native source-to-XPUI adapter.
# Reuses the EXACT existing Addon Manager registry + source adapter authority.
# This is a genuine official Spicetify CLI acceptance in a disposable hosted
# Windows profile; output MUST NOT be promoted as authenticated HMAC mutation.
# It creates NO user-profile state, production update, install or permit.
function Resolve-ApprovedCustomAppScopedNativeV026 {
    param([Parameter(Mandatory=$true)]$Item)
    $deny={param([string]$Reason)
        return [pscustomobject]@{ok=$false;reason=$Reason;name=[string]$Item.name
            source=$null;handler=$null;registry_sha256=$null
            authenticated_hmac_stage=$false;production_mutation_authorized=$false}}
    if(-not(Get-Command Get-AddonMutationAuthorization -CommandType Function -ErrorAction SilentlyContinue) -or
       -not(Get-Command Get-AddonSourceAdapterPlan -CommandType Function -ErrorAction SilentlyContinue) -or
       -not(Get-Command Resolve-ManagedCustomAppUpdateTopology -CommandType Function -ErrorAction SilentlyContinue)){
        return & $deny 'v026-authoritative-existing-addon-policy-functions-unavailable'
    }
    # The explicit names are a CEILING, not a second authorizing policy.
    # Actual authorization must also pass the runtime's registry and adapter.
    $name=[string]$Item.name
    $allowed=[ordered]@{
        'better-local-files'=@('Pithaya/spicetify-apps-dist','pithaya','git-commit-tree')
        'eternal-jukebox'=@('Pithaya/spicetify-apps-dist','pithaya','git-commit-tree')
        'ivLyrics'=@('ivLis-Studio/ivLyrics','ivlyrics','semver-release-exact-tree')
        'playlist-maker'=@('Pithaya/spicetify-apps-dist','pithaya','git-commit-tree')
    }
    if(-not$allowed.Contains($name)){return & $deny 'v026-not-on-frozen-installed-only-allowlist'}
    if([string]$Item.kind -cne 'custom-app' -or [string]$Item.policy -cne 'auto' -or
       $Item.installed -cne $true){
        return & $deny 'v026-not-installed-exact-custom-app-policy'
    }
    try{
        $auth=Get-AddonMutationAuthorization -Item $Item
        $plan=Get-AddonSourceAdapterPlan -Item $Item
        $topology=Resolve-ManagedCustomAppUpdateTopology -Item $Item -Authorization $auth
    }catch{return & $deny ('v026-existing-authoritative-authorization-threw:'+[string]$_.Exception.Message)}
    $expected=$allowed[$name]
    if($null-eq$auth -or $null-eq$plan -or $null-eq$topology -or
       -not[bool]$auth.Allowed -or -not[bool]$plan.allowed -or
       -not[bool]$plan.mutation_authorized -or
       -not[bool]$topology.manager_direct_mutation_authorized -or
       [bool]$topology.marketplace_native_refresh -or
       [string]$topology.owner -cne 'addon-manager-installed-only' -or
       [string]$topology.update_mode -cne 'explicit-source-adapter' -or
       [string]$auth.Entry.install_mode -cne 'installed-only' -or
       [string]$auth.Entry.mutation_mode -cne 'auto' -or
       [string]$auth.Entry.data_policy -notin @('preserve-installed-only','preserve-local-divergence') -or
       [string]$auth.Entry.rollback_strategy -cne 'exact-directory-transaction' -or
       [string]$auth.Entry.source -cne [string]$expected[0] -or
       [string]$Item.source -cne [string]$expected[0] -or
       [string]$auth.Handler -cne [string]$expected[1] -or
       [string]$plan.mutation_handler -cne [string]$expected[1] -or
       [string]$auth.Entry.version_strategy -cne [string]$expected[2] -or
       [string]$plan.registry_sha256 -cne [string]$auth.RegistrySha256 -or
       [string]$topology.handler -cne [string]$expected[1]){
        return & $deny 'v026-registry-source-adapter-or-owner-contract-denied'
    }
    if([string]$plan.adapter.mode -cne 'existing-handler-delegation' -or
       -not[bool]$plan.adapter.mutation_capable -or
       [string]$plan.adapter.rollback_strategy -cne 'exact-directory-transaction'){
        return & $deny 'v026-adapter-is-not-existing-qualified-directory-transaction'
    }
    return [pscustomobject]@{
        ok=$true;reason='approved-installed-custom-app-scoped-native-candidate'
        name=$name;source=[string]$expected[0];handler=[string]$expected[1]
        registry_sha256=[string]$auth.RegistrySha256
        data_policy=[string]$auth.Entry.data_policy
        version_strategy=[string]$auth.Entry.version_strategy
        existing_handler=[string]$auth.Handler
        app_kind='custom-app';owner='addon-manager-installed-only'
        installed_only=$true;scoped_native_candidate=$true
        authenticated_hmac_stage=$false;actual_production_stage_verified=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Assert-ApprovedCustomAppHostedPathV026 {
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$RunnerRoot)
    $r=[IO.Path]::GetFullPath($RunnerRoot).TrimEnd('\','/')
    $p=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($r.StartsWith('\\') -or $p.StartsWith('\\') -or
       -not$p.StartsWith(($r+'\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'v026-hosted-path-outside-exact-runner-temp'
    }
    $probe=$p
    while($probe.Length -ge $r.Length){
        if([IO.File]::Exists($probe) -or [IO.Directory]::Exists($probe)){
            if(((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'v026-hosted-path-reparse-point'
            }
        }
        if($probe.Equals($r,[StringComparison]::OrdinalIgnoreCase)){break}
        $parent=[IO.Path]::GetDirectoryName($probe)
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe){throw 'v026-hosted-parent-invalid'}
        $probe=$parent
    }
    return $p
}
function Invoke-ApprovedCustomAppScopedNativeHostedV026 {
    param(
        [Parameter(Mandatory=$true)]$Item,
        [Parameter(Mandatory=$true)][string]$CandidateAppPath,
        [Parameter(Mandatory=$true)][string]$ExpectedRuntimeTreeSha256,
        [Parameter(Mandatory=$true)][string]$OfficialExecutable,
        [Parameter(Mandatory=$true)][string]$PrivateRoot
    )
    $deny={param([string]$why,[bool]$started=$false)
        return [pscustomobject]@{ok=$false;reason=$why;vendor_started=$started
            production_execution_authorized=$false;production_mutation_authorized=$false
            authenticated_hmac_stage=$false;official_native_scoped_output_verified=$false}}
    $qualification=Resolve-ApprovedCustomAppScopedNativeV026 -Item $Item
    if(-not[bool]$qualification.ok){return & $deny ([string]$qualification.reason)}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        return & $deny 'v026-real-vendor-disposable-hosted-Windows-only'
    }
    if($ExpectedRuntimeTreeSha256 -cnotmatch '^[a-f0-9]{64}$'){
        return & $deny 'v026-candidate-tree-hash-invalid'
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    try{
        $candidate=Assert-ApprovedCustomAppHostedPathV026 -Path $CandidateAppPath -RunnerRoot $runner
        $root=Assert-ApprovedCustomAppHostedPathV026 -Path $PrivateRoot -RunnerRoot $runner
        $exe=Assert-ApprovedCustomAppHostedPathV026 -Path $OfficialExecutable -RunnerRoot $runner
    }catch{return & $deny 'v026-untrusted-candidate-or-official-cli-path'}
    $app=[string]$qualification.name
    if([IO.Path]::GetFileName($candidate) -cne $app -or
       $root.StartsWith(($candidate+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       $candidate.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Directory]::Exists($root) -or $root.Length -ge 160){
        return & $deny 'v026-target-path-or-private-root-unqualified'
    }
    $pinned='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
    if(-not[IO.File]::Exists($exe) -or
       (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pinned){
        return & $deny 'v026-official-upstream-binary-sha-mismatch'
    }
    try{$baseline=Get-CustomAppLocalRuntimeBaseline -Name $app -AppPath $candidate}
    catch{return & $deny 'v026-candidate-runtime-invalid-or-unreadable'}
    if(-not[bool]$baseline.safe -or -not[bool]$baseline.installable -or
       [string]$baseline.tree_sha256 -cne $ExpectedRuntimeTreeSha256 -or
       @($baseline.files|Where-Object{[string]$_.path -ceq 'index.js'}).Count -ne 1 -or
       @($baseline.files|Where-Object{[string]$_.path -ceq 'manifest.json'}).Count -ne 1){
        return & $deny 'v026-candidate-full-runtime-tree-not-exactly-pinned'
    }
    $clone=Join-Path (Join-Path $root 'CustomApps') $app
    $xpui=Join-Path $root 'FakeSpotify\Apps\xpui'
    $target=Join-Path $xpui ('spicetify-routes-'+$app+'.js')
    $other=Join-Path $xpui 'spicetify-routes-foreign.js'
    $sentinel=Join-Path $xpui 'user-settings-dont-change.dat'
    $nativeConfig=Join-Path $root 'config-xpui.ini'
    $start=$null;$handle=$null
    $started=$false
    try{
        foreach($dir in @($clone,$xpui,(Join-Path $root 'Backup'),
                            (Join-Path $root 'Roaming'),(Join-Path $root 'Local'))){
            [void][IO.Directory]::CreateDirectory($dir)
        }
        foreach($file in @($baseline.files)){
            $rel=[string]$file.path
            if($rel -notmatch '^[A-Za-z0-9_./-]+$' -or
               $rel.Contains('..') -or $rel.StartsWith('/') -or $rel.Contains(':')){
                throw 'v026-unexpected-canonical-file-path'
            }
            $src=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path $candidate ($rel.Replace('/','\'))) -RunnerRoot $runner
            $dst=Assert-ApprovedCustomAppHostedPathV026 -Path (Join-Path $clone ($rel.Replace('/','\'))) -RunnerRoot $runner
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            [IO.File]::Copy($src,$dst,$false)
            if((Get-FileHash $dst -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$file.sha256){
                throw 'v026-qualifed-stage-copy-drift'
            }
        }
        $copy=Get-CustomAppLocalRuntimeBaseline -Name $app -AppPath $clone
        if([string]$copy.tree_sha256 -cne [string]$baseline.tree_sha256){
            throw 'v026-full-candidate-clone-differs'
        }
        $fakeSpotify=Join-Path $root 'FakeSpotify'
        $prefs=Join-Path $root 'prefs'
        [IO.File]::WriteAllText($prefs,"app.last-launched-version = 1.2.3"+[Environment]::NewLine)
        [IO.File]::WriteAllBytes((Join-Path $root 'Backup\xpui.spa'),[byte[]](0x50,0x4b))
        [IO.File]::WriteAllText($target,'V026_BEFORE_TARGET')
        [IO.File]::WriteAllText($other,'V026_OTHER_APP_DO_NOT_CHANGE')
        [IO.File]::WriteAllText($sentinel,'V026_PROTECTED_USER_STATE')
        $ini='[Setting]'+[Environment]::NewLine+
            'spotify_path = '+$fakeSpotify+[Environment]::NewLine+
            'prefs_path = '+$prefs+[Environment]::NewLine+
            'check_spicetify_update = false'+[Environment]::NewLine+
            'current_theme = '+[Environment]::NewLine+
            '[Backup]'+[Environment]::NewLine+
            'version = 1.2.3'+[Environment]::NewLine+
            'with = 2.46.4'+[Environment]::NewLine+
            '[AdditionalOptions]'+[Environment]::NewLine+
            'custom_apps = '+$app+[Environment]::NewLine
        [IO.File]::WriteAllText($nativeConfig,$ini,[Text.UTF8Encoding]::new($false))
        $handle=[IO.File]::Open($exe,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $hash=[Security.Cryptography.SHA256]::Create()
        try{$actual=([BitConverter]::ToString($hash.ComputeHash($handle))).Replace('-','').ToLowerInvariant()}
        finally{$hash.Dispose()}
        if($actual -cne $pinned){throw 'v026-native-executable-changed-before-start'}
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$exe
        $psi.Arguments='--bypass-admin -n -a refresh'
        $psi.WorkingDirectory=$root
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.EnvironmentVariables['SPICETIFY_CONFIG']=$root
        $psi.EnvironmentVariables['SPICETIFY_STATE']=$root
        $psi.EnvironmentVariables['APPDATA']=(Join-Path $root 'Roaming')
        $psi.EnvironmentVariables['LOCALAPPDATA']=(Join-Path $root 'Local')
        $start=New-Object Diagnostics.Process
        $start.StartInfo=$psi
        if(-not $start.Start()){throw 'v026-official-cli-did-not-start'}
        $started=$true
        if(-not $start.WaitForExit(60000)){
            $start.Kill();[void]$start.WaitForExit()
            throw 'v026-official-cli-timeout'
        }
        if([int]$start.ExitCode -ne 0){throw ('v026-official-cli-exit-'+$start.ExitCode)}
        if(-not[IO.File]::Exists($target)){throw 'v026-official-cli-target-not-written'}
        $utf8=[Text.UTF8Encoding]::new($false,$true)
        $sourceCode=$utf8.GetString([IO.File]::ReadAllBytes((Join-Path $clone 'index.js')))
        $nativeCode=$utf8.GetString([IO.File]::ReadAllBytes($target))
        if([string]::IsNullOrWhiteSpace($sourceCode) -or
           -not $nativeCode.Contains($sourceCode)){
            throw 'v026-official-target-does-not-contain-qualified-index-source'
        }
        if([IO.File]::ReadAllText($other) -cne 'V026_OTHER_APP_DO_NOT_CHANGE' -or
           [IO.File]::ReadAllText($sentinel) -cne 'V026_PROTECTED_USER_STATE'){
            throw 'v026-official-cli-changed-nontarget-user-files'
        }
        $after=Get-CustomAppLocalRuntimeBaseline -Name $app -AppPath $candidate
        $copyAfter=Get-CustomAppLocalRuntimeBaseline -Name $app -AppPath $clone
        if([string]$after.tree_sha256 -cne $ExpectedRuntimeTreeSha256 -or
           [string]$copyAfter.tree_sha256 -cne $ExpectedRuntimeTreeSha256){
            throw 'v026-official-cli-mutated-original-or-verified-clone'
        }
        return [pscustomobject]@{
            ok=$true;reason='approved-installed-only-app-official-native-scoped-test'
            name=$app;source=[string]$qualification.source
            handler=[string]$qualification.handler
            registry_sha256=[string]$qualification.registry_sha256
            runtime_tree_sha256=$ExpectedRuntimeTreeSha256
            official_binary_sha256=$actual
            target_xpui_sha256=(Get-FileHash $target -Algorithm SHA256).Hash.ToLowerInvariant()
            approved_candidate_full_tree_preserved=$true
            nontarget_output_preserved=$true
            vendor_started=$true;official_native_scoped_output_verified=$true
            authenticated_hmac_stage=$false
            needs_authenticated_stage_and_full_journal=$true
            production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }catch{return & $deny ('v026-official-native-scoped-acceptance-denied:'+[string]$_.Exception.Message) $started}
    finally{if($null-ne$start){$start.Dispose()};if($null-ne$handle){$handle.Dispose()}}
}
