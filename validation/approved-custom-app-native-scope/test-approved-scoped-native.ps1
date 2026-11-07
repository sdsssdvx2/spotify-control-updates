# Targeted real upstream scoped-output acceptance for the four ACTUALLY
# approved, installed-only Custom Apps. No HMAC issuance, journal mutation,
# installed Spotify or real user data. V024/V025 already have their own
# qualified authentic HMAC transaction / crash resume evidence.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'V026_TARGETED_HOSTED_WINDOWS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/v0.6.21/addon_policy_registry.ps1.inc')
. (Join-Path $root 'validation/v0.6.22/addon_source_adapter_engine.ps1.inc')
. (Join-Path $root 'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1')
. (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
. (Join-Path $PSScriptRoot 'approved-scoped-native.ps1')
function Assert-V026([bool]$Ok,[string]$Message){if(-not$Ok){throw ('V026_TEST_FAILED: '+$Message)}}
$allowed=@(
    [pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$true},
    [pscustomobject]@{name='better-local-files';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
    [pscustomobject]@{name='eternal-jukebox';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
    [pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true}
)
$catalog=@(Get-AddonPolicyRegistry)
Assert-V026 ($catalog.Count -eq 9) 'actual authoritative policy registry unexpectedly changed'
$registered=Get-AddonPolicyRegistryFingerprint
Assert-V026 ($registered -cmatch '^[0-9a-f]{64}$') 'real policy fingerprint invalid'
$assertCount=0
foreach($i in $allowed){
    $p=Resolve-ApprovedCustomAppScopedNativeV026 -Item $i
    Assert-V026 ([bool]$p.ok -and $p.name -ceq $i.name -and $p.source -ceq $i.source -and
        [string]$p.registry_sha256 -ceq $registered -and
        -not[bool]$p.authenticated_hmac_stage -and
        -not[bool]$p.production_mutation_authorized) ('positive installed-only exact policy denied '+$i.name+': '+$p.reason)
    $assertCount++
}
foreach($x in @(
    [pscustomobject]@{name='tagify';kind='custom-app';policy='monitor-only';source='alexk218/tagify';installed=$true},
    [pscustomobject]@{name='star-ratings';kind='marketplace-extension';policy='source-watch-only';source='brimell/spicetify-star-ratings';installed=$true},
    [pscustomobject]@{name='splitify';kind='custom-app';policy='unknown-source';source=$null;installed=$true},
    [pscustomobject]@{name='sc-cover-ambience.js';kind='extension';policy='rescue-copy-cleanup-only';source='Theblockbuster1/spicetify-extensions';installed=$true},
    [pscustomobject]@{name='new-unknown-app';kind='custom-app';policy='auto';source='example/unknown';installed=$true}
)){
    $p=Resolve-ApprovedCustomAppScopedNativeV026 -Item $x
    Assert-V026 (-not[bool]$p.ok -and -not[bool]$p.production_mutation_authorized) ('dangerous disallowed app eligible '+$x.name)
    $assertCount++
}
foreach($i in $allowed){
    foreach($changed in @(
        @{installed=$false},
        @{source='unexpected/changed'},
        @{policy='monitor-only'},
        @{kind='marketplace-extension'}
    )){
        $q=$i|Select-Object name,kind,policy,source,installed
        foreach($key in $changed.Keys){$q.$key=$changed[$key]}
        $p=Resolve-ApprovedCustomAppScopedNativeV026 -Item $q
        Assert-V026 (-not[bool]$p.ok -and -not[bool]$p.production_mutation_authorized) ('changed installed policy or source accepted '+$i.name+' '+($changed.Keys -join ',' ))
        $assertCount++
    }
}
Write-Host ('V026_EXISTING_REAL_REGISTRY_FOUR_INSTALLED_APPS_AND_PROTECTED_NEGATIVES_PASS cases='+$assertCount)
$exeHash=(Get-FileHash $OfficialExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-V026 ($exeHash -ceq '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db') 'official exe SHA mismatch'
$base=Join-Path $env:RUNNER_TEMP ('v026-approved-matrix-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($base)
$official=Join-Path $base 'spicetify.exe'
[IO.File]::Copy($OfficialExecutable,$official,$false)
$caseCount=0
foreach($i in $allowed){
    $source=Join-Path (Join-Path $base 'staged') $i.name
    $private=Join-Path (Join-Path $base 'private') $i.name
    $assets=Join-Path $source 'assets'
    [void][IO.Directory]::CreateDirectory($assets)
    $marker='V026_SCOPED_'+$i.name.Replace('-','_')+'_QUALIFIED_SOURCE'
    [IO.File]::WriteAllText((Join-Path $source 'index.js'),("console.log('"+$marker+"');"),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'manifest.json'),('{"name":"'+$i.name+'"}'),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $assets 'note.txt'),('V026_SECOND_SOURCE_FILE_'+$i.name),[Text.UTF8Encoding]::new($false))
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$i.name) -AppPath $source
    Assert-V026 ([bool]$baseline.safe -and [bool]$baseline.installable -and
        [string]$baseline.manifest_name -ceq [string]$i.name -and [int]$baseline.file_count -ge 3) ('synthetic approved source not structurally valid '+$i.name)
    $wrong=Invoke-ApprovedCustomAppScopedNativeHostedV026 -Item $i -CandidateAppPath $source -ExpectedRuntimeTreeSha256 ('0'*64) -OfficialExecutable $official -PrivateRoot $private
    Assert-V026 (-not[bool]$wrong.ok -and -not[bool]$wrong.vendor_started -and -not(Test-Path $private)) ('wrong candidate tree launched vendor '+$i.name)
    $result=Invoke-ApprovedCustomAppScopedNativeHostedV026 -Item $i -CandidateAppPath $source -ExpectedRuntimeTreeSha256 ([string]$baseline.tree_sha256) -OfficialExecutable $official -PrivateRoot $private
    Assert-V026 ([bool]$result.ok -and [bool]$result.vendor_started -and
        [bool]$result.official_native_scoped_output_verified -and
        [string]$result.name -ceq [string]$i.name -and
        [string]$result.source -ceq [string]$i.source -and
        [string]$result.runtime_tree_sha256 -ceq [string]$baseline.tree_sha256 -and
        [string]$result.target_xpui_sha256 -cmatch '^[a-f0-9]{64}$' -and
        [bool]$result.nontarget_output_preserved -and
        [bool]$result.approved_candidate_full_tree_preserved -and
        -not[bool]$result.authenticated_hmac_stage -and
        [bool]$result.needs_authenticated_stage_and_full_journal -and
        -not[bool]$result.production_mutation_authorized) ('genuine native refresh unsuccessful '+$i.name+': '+$result.reason)
    $after=Get-CustomAppLocalRuntimeBaseline -Name ([string]$i.name) -AppPath $source
    Assert-V026 ([string]$after.tree_sha256 -ceq [string]$baseline.tree_sha256) ('official native changed original stage '+$i.name)
    Write-Host ('V026_OFFICIAL_SCOPED_NATIVE_SOURCE_OUTPUT_PASS app='+$i.name+' files='+$baseline.file_count)
    $caseCount++
}
Assert-V026 ($caseCount -eq 4) 'four approved Custom Apps were not all exercised'
Write-Host 'V026_FOUR_APPROVED_INSTALLED_ONLY_CUSTOM_APP_REAL_OFFICIAL_SCOPED_OUTPUT_PASS production_authority=false Tagify_denied=true Marketplace_denied=true original_stage_preserved=true'
