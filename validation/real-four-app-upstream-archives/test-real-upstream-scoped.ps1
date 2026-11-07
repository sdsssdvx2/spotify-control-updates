# V027: actual publicly released source bytes, not four synthetic index.js
# fixtures. Pithaya apps each live on a different dist/<app> git ref; ivLyrics
# comes from the separately released ZIP. This acceptance never edits the
# user's Spicetify, profile, Spotify or previously installed CustomApps.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'V027_REAL_ARCHIVE_ACCEPTANCE_REQUIRES_HOSTED_WINDOWS'
}
# The shared V026 vendor admission deliberately permits ONLY RUNNER_TEMP.
# .NET's ordinary user TEMP can be a different path on hosted Windows.
# Constrain both the legacy stage workspace and the vendor's input to one
# disposable runner-owned root; do NOT broaden the vendor path allowlist.
$env:TEMP=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$env:TMP=$env:TEMP
if(-not[IO.Directory]::Exists($env:TEMP)){throw 'V027_RUNNER_TEMP_NOT_A_DIRECTORY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.21/addon_policy_registry.ps1.inc'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.22/addon_source_adapter_engine.ps1.inc'),[Text.Encoding]::UTF8)))
. (Join-Path $root 'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1')
. (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
. (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $root 'validation/approved-custom-app-native-scope/approved-scoped-native.ps1')
function Assert-V027([bool]$Ok,[string]$What){
    if(-not$Ok){throw ('V027_REAL_UPSTREAM_ASSERTION_FAILED: '+$What)}
}
$script:SourceMatrix=@(
 [pscustomobject]@{
   name='better-local-files';source='Pithaya/spicetify-apps-dist'
   manifest='Local Files';branch='dist/better-local-files'
   commit='bf467fab93e6c1f8b8d4189dc1054bd1cafb3f3a'
   required='extension.js';handler='pithaya';kind='git-branch'
 },
 [pscustomobject]@{
   name='eternal-jukebox';source='Pithaya/spicetify-apps-dist'
   manifest='Eternal Jukebox';branch='dist/eternal-jukebox'
   commit='78764378798505884cc5c6e40fe7f7ac504d6c8a'
   required='extension.js';handler='pithaya';kind='git-branch'
 },
 [pscustomobject]@{
   name='playlist-maker';source='Pithaya/spicetify-apps-dist'
   manifest='Playlist maker';branch='dist/playlist-maker'
   commit='9fd89fb40a53e4cfbf0953d34f806f4a8a36fc64'
   required='extension.js';handler='pithaya';kind='git-branch'
 },
 [pscustomobject]@{
   name='ivLyrics';source='ivLis-Studio/ivLyrics';manifest='ivLyrics'
   release='v7.1.6';asset_id=718257950
   archive_sha256='bdd7c047b303c519997d3f5c5f0ca416e607aad0a6de6592bb15fddb6e6269ac'
   archive_bytes=10464403
   required='index.js';handler='ivlyrics';kind='release-asset'
 }
)
$expectedNames=@('better-local-files','eternal-jukebox','playlist-maker','ivLyrics')
Assert-V027 ((@($script:SourceMatrix|ForEach-Object{[string]$_.name}) -join '|') -ceq ($expectedNames -join '|')) 'four pinned app identities changed'
$owner=Join-Path $env:RUNNER_TEMP ('v027-upstream-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($owner)|Out-Null
$stageRoot=Get-CustomAppStageWorkspaceRootV010
[void](Assert-ApprovedCustomAppHostedPathV026 -Path $stageRoot -RunnerRoot $env:RUNNER_TEMP)
$workspace=New-CustomAppStageWorkspaceV010
[void](Assert-ApprovedCustomAppHostedPathV026 -Path $workspace -RunnerRoot $env:RUNNER_TEMP)
$policyFingerprint=Get-AddonPolicyRegistryFingerprint
[System.Collections.Generic.List[object]]$results=New-Object 'System.Collections.Generic.List[object]'
foreach($row in $script:SourceMatrix){
    $name=[string]$row.name
    $item=[pscustomobject]@{
        name=$name;kind='custom-app';policy='auto';source=[string]$row.source;installed=$true
    }
    $authorization=Resolve-ApprovedCustomAppScopedNativeV026 -Item $item
    Assert-V027 ([bool]$authorization.ok -and [string]$authorization.source -ceq [string]$row.source -and
        [string]$authorization.handler -ceq [string]$row.handler -and
        [string]$authorization.registry_sha256 -ceq $policyFingerprint -and
        -not[bool]$authorization.production_mutation_authorized) ('actual-app policy refused '+$name)
    $zip=Join-Path $workspace ($name+'.zip')
    if([string]$row.kind -ceq 'git-branch'){
        $source=Join-Path $owner ('git-'+$name)
        $url='https://github.com/Pithaya/spicetify-apps-dist.git'
        & git clone --quiet --depth 1 --single-branch --branch ([string]$row.branch) $url $source
        Assert-V027 ($LASTEXITCODE -eq 0) ('Pithaya source branch clone failed '+$name)
        $actualCommit=(& git -C $source rev-parse HEAD).Trim()
        $actualBranch=(& git -C $source symbolic-ref --short HEAD).Trim()
        $actualRemote=(& git -C $source remote get-url origin).Trim()
        Assert-V027 ($actualCommit -ceq [string]$row.commit -and
           $actualBranch -ceq [string]$row.branch -and
           $actualRemote -ceq $url) ('Pithaya source ref/commit identity drift '+$name)
        & git -C $source archive --format=zip --output="$zip" HEAD
        Assert-V027 ($LASTEXITCODE -eq 0) ('Pithaya git archive failed '+$name)
    }else{
        Assert-V027 ($name -ceq 'ivLyrics' -and $row.release -ceq 'v7.1.6' -and
            [int64]$row.asset_id -eq 718257950) 'ivLyrics exact release-asset contract changed'
        $url='https://github.com/ivLis-Studio/ivLyrics/releases/download/v7.1.6/ivLyrics.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
        $digest=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-V027 ($digest -ceq [string]$row.archive_sha256 -and
            (Get-Item -LiteralPath $zip).Length -eq [int64]$row.archive_bytes) 'ivLyrics release archive exact asset changed'
    }
    Assert-V027 ([IO.File]::Exists($zip)) ('real release ZIP not present '+$name)
    $zipDigest=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $evidence=Get-CustomAppObserverZipEvidence -ZipPath $zip -WrapperMode auto
    Assert-V027 ([bool]$evidence.manifest_valid -and -not[bool]$evidence.build_required -and
        [string]$evidence.manifest_name -ceq [string]$row.manifest -and
        [int]$evidence.app_root_count -eq 1 -and
        @($evidence.files|Where-Object{[string]$_.path -ceq [string]$row.required}).Count -eq 1) (
           'upstream ZIP is not expected exact install-ready package '+$name)
    $dest=Join-Path (Join-Path $workspace 'stage') $name
    $expanded=Expand-CustomAppStageArchiveV010 -ZipPath $zip -Destination $dest -ValidationRoot $workspace -WrapperMode auto -Name $name -ExpectedTreeSha256 ([string]$evidence.tree_sha256) -ExpectedManifestName ([string]$row.manifest)
    Assert-V027 ([string]$expanded.tree_sha256 -ceq [string]$evidence.tree_sha256 -and
        [int]$expanded.file_count -eq [int]$evidence.file_count -and
        [string]$expanded.manifest_name -ceq [string]$row.manifest -and
        -not[bool]$expanded.production_mutation_authorized) ('official exact ZIP extraction drift '+$name)
    # Do not claim the staged files have an HMAC permit: the exact remote
    # binding and signed per-transaction permit are the NEXT integration
    # boundary, and the historical Tagify-specific HMAC gate rejects these.
    $private=Join-Path $owner ('scoped-'+$name)
    $n=Invoke-ApprovedCustomAppScopedNativeHostedV026 -Item $item -CandidateAppPath $dest -ExpectedRuntimeTreeSha256 ([string]$expanded.tree_sha256) -OfficialExecutable $OfficialExecutable -PrivateRoot $private
    Assert-V027 ([bool]$n.ok -and [bool]$n.vendor_started -and
        [bool]$n.official_native_scoped_output_verified -and
        [string]$n.source -ceq [string]$row.source -and
        [string]$n.runtime_tree_sha256 -ceq [string]$evidence.tree_sha256 -and
        [bool]$n.nontarget_output_preserved -and
        [bool]$n.approved_candidate_full_tree_preserved -and
        -not[bool]$n.authenticated_hmac_stage -and
        -not[bool]$n.production_mutation_authorized) (
          'upstream official scoped output refused '+$name+': '+[string]$n.reason)
    $after=Get-CustomAppLocalRuntimeBaseline -Name $name -AppPath $dest
    Assert-V027 ([string]$after.tree_sha256 -ceq [string]$evidence.tree_sha256 -and
        [string]$after.manifest_name -ceq [string]$row.manifest) (
          'real upstream stage changed after official CLI '+$name)
    $results.Add([pscustomobject]@{
        app=$name;source=[string]$row.source;manifest=[string]$row.manifest
        archive_sha256=$zipDigest;runtime_tree_sha256=[string]$expanded.tree_sha256
        files=[int]$expanded.file_count;bytes=[int64]$expanded.total_bytes
        spicetify_sha256=[string]$n.official_binary_sha256
        official_target_sha256=[string]$n.target_xpui_sha256
        source_kind=[string]$row.kind
        authorized_staged_update=$false;production_mutation_authorized=$false
    })
    Write-Host ('V027_REAL_UPSTREAM_ARCHIVE_OFFICIAL_SCOPED_PASS app='+$name+' files='+$expanded.file_count+' manifest='+[string]$row.manifest)
}
Assert-V027 ($results.Count -eq 4) 'not all 4 actual release archives verified'
$protected=[pscustomobject]@{
    name='tagify';kind='custom-app';source='alexk218/tagify';policy='monitor-only';installed=$true
}
$denied=Resolve-ApprovedCustomAppScopedNativeV026 -Item $protected
Assert-V027 (-not[bool]$denied.ok -and -not[bool]$denied.production_mutation_authorized) 'protected Tagify became eligible'
$manifest=Join-Path $owner 'source-and-output-evidence.json'
[IO.File]::WriteAllText($manifest,($results.ToArray()|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Host 'V027_ALL_FOUR_ACTUAL_UPSTREAM_SOURCE_ZIPS_SAFE_EXTRACTED_REAL_SCOPED_OUTPUT_PASS'
Write-Host 'V027_ONLY_ORIGINAL_PINNED_FREE_CLI_NO_USER_SPOTIFY_NO_HMAC_PERMIT_PRODUCTION_AUTHORITY_FALSE'
