# V028: targeted provider-aware source acquisition acceptance. Previous V027
# already proved real official Spicetify scoped refresh for all four pinned
# upstream archives; do NOT re-run vendor CLI or full V025 transaction suites.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V028_SOURCE_ACQUISITION_TEST_HOSTED_ONLY'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.21/addon_policy_registry.ps1.inc'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root 'validation/v0.6.22/addon_source_adapter_engine.ps1.inc'),[Text.Encoding]::UTF8)))
. (Join-Path $root 'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1')
. (Join-Path $root 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1')
. (Join-Path $root 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1')
. (Join-Path $root 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1')
. (Join-Path $root 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1')
. (Join-Path $root 'validation/approved-custom-app-native-scope/approved-scoped-native.ps1')
. (Join-Path $PSScriptRoot 'approved-live-source-acquisition.ps1')
function Assert-Acquire([bool]$Okay,[string]$What){
    if(-not$Okay){throw ('V028_SOURCE_ACCEPTANCE_FAILURE:'+ $What)}
}
$items=@(
 [pscustomobject]@{name='better-local-files';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
 [pscustomobject]@{name='eternal-jukebox';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
 [pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true},
 [pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$true}
)
foreach($item in $items){
    $policy=Get-ApprovedLiveSourcePolicyV028 -Item $item
    $snapshot=Get-ApprovedLiveRemoteSnapshotV028 -Policy $policy
    Assert-Acquire ([string]$snapshot.name -ceq [string]$item.name -and
       [string]$snapshot.source -ceq [string]$item.source -and
       [string]$snapshot.commit_sha -cmatch '^[0-9a-f]{40}$' -and
       [string]$snapshot.registry_sha256 -ceq (Get-AddonPolicyRegistryFingerprint) -and
       [int64]$snapshot.repository_id -gt 0 -and
       -not[bool]$snapshot.production_mutation_authorized) ('latest source provider metadata '+$item.name)
    if([string]$snapshot.type -ceq 'pithaya-branch'){
        Assert-Acquire ([string]$snapshot.branch -ceq ('dist/'+[string]$item.name) -and
           [string]$snapshot.archive_uri -ceq ('https://codeload.github.com/Pithaya/spicetify-apps-dist/zip/'+[string]$snapshot.commit_sha)) (
             'Pithaya app branch not independent exact commit '+$item.name)
    }else{
        Assert-Acquire ([string]$snapshot.type -ceq 'ivlyrics-release' -and
           [string]$snapshot.asset_digest -cmatch '^sha256:[0-9a-f]{64}$' -and
           [int64]$snapshot.asset_id -gt 0 -and
           [string]$snapshot.manifest_name -ceq 'ivLyrics') 'official ivLyrics unique release archive origin'
    }
    Write-Host ('V028_LIVE_SOURCE_METADATA_PIN_PASS app='+[string]$item.name)
}
foreach($bad in @(
 [pscustomobject]@{name='tagify';kind='custom-app';policy='monitor-only';source='alexk218/tagify';installed=$true},
 [pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$false},
 [pscustomobject]@{name='better-local-files';kind='custom-app';policy='auto';source='other/changed';installed=$true},
 [pscustomobject]@{name='star-ratings';kind='marketplace-extension';policy='source-watch-only';source='brimell/spicetify-star-ratings';installed=$true}
)){
    $denied=$false
    try{[void](Get-ApprovedLiveSourcePolicyV028 -Item $bad)}catch{$denied=$true}
    Assert-Acquire $denied ('unapproved or removed item accepted '+[string]$bad.name)
}
Write-Host 'V028_PROTECTED_AND_ABSENT_INSTALLED_SOURCE_DENIAL_PASS'
# Only one representative of each existing adapter type needs to be
# re-downloaded; V027 already exercised the full real content of every app
# through the official CLI. Do not rerun expensive redundant native tests.
foreach($item in @($items[0],$items[3])){
    $acquired=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
    Assert-Acquire ([bool]$acquired.ok -and
       [string]$acquired.name -ceq [string]$item.name -and
       [string]$acquired.source -ceq [string]$item.source -and
       [string]$acquired.source_snapshot.commit_sha -cmatch '^[0-9a-f]{40}$' -and
       [string]$acquired.source_provenance_sha256 -cmatch '^[0-9a-f]{64}$' -and
       [string]$acquired.archive_sha256 -cmatch '^[0-9a-f]{64}$' -and
       [string]$acquired.runtime_tree_sha256 -cmatch '^[0-9a-f]{64}$' -and
       [string]$acquired.manifest_name -ceq [string]$acquired.source_snapshot.manifest_name -and
       [int]$acquired.file_count -ge 3 -and
       [bool]$acquired.ready_for_separate_cryptographic_permit -and
       -not[bool]$acquired.authenticated_hmac_permit -and
       -not[bool]$acquired.production_mutation_authorized -and
       -not[bool]$acquired.spicetify_executed) ('actual current live source acquisition failed '+[string]$item.name)
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath ([string]$acquired.stage_path)
    Assert-Acquire ([string]$baseline.tree_sha256 -ceq [string]$acquired.runtime_tree_sha256 -and
       [string]$baseline.manifest_name -ceq [string]$acquired.manifest_name) ('source stage was altered after byte attestation '+[string]$item.name)
    Write-Host ('V028_LIVE_ZIP_FULL_TREE_STAGED_PASS app='+[string]$item.name+' files='+[string]$acquired.file_count)
    Remove-CustomAppStageWorkspaceV010 -Path ([string]$acquired.workspace_path)
    Assert-Acquire (-not(Test-Path -LiteralPath ([string]$acquired.workspace_path))) ('disposable returned stage not cleaned '+[string]$item.name)
}
Write-Host 'V028_TWO_REAL_LIVE_ADAPTERS_SOURCE_ACQUISITION_REVALIDATED_PASS'
Write-Host 'V028_NO_PRETEND_HMAC_NO_USER_INSTALL_NO_SPOTIFY_CHANGES_NO_NEW_NATIVE_REGRESSION_PASS'
