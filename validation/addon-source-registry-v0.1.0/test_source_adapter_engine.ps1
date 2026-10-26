param([string]$ReportPath)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation\v0.6.21\addon_policy_registry.ps1.inc')
. (Join-Path $PSScriptRoot 'source_adapter_engine.ps1')

function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}

Invoke-AddonPolicyRegistrySelfTest
$registry=@(Get-AddonPolicyRegistry)
Assert-Eq $registry.Count 9 'Registry entry count drifted.'
$catalog=@(Get-AddonSourceAdapterCatalog)
Assert-Eq $catalog.Count 6 'Adapter catalog count drifted.'
Assert-Eq @($catalog|ForEach-Object{$_.id}|Sort-Object -Unique).Count 6 'Adapter IDs are not unique.'
Assert-Eq @($catalog|ForEach-Object{$_.version_strategy}|Sort-Object -Unique).Count 6 'Adapter strategies are not unique.'

$expected=@{
    'ivLyrics'='ivlyrics-release-tree-v1'
    'better-local-files'='pithaya-git-tree-v1'
    'eternal-jukebox'='pithaya-git-tree-v1'
    'playlist-maker'='pithaya-git-tree-v1'
    'tagify'='github-release-monitor-v1'
    'splitify'='unresolved-source-v1'
    'star-ratings'='github-head-monitor-v1'
    'sc-cover-ambience.js'='external-owner-cleanup-v1'
    'sc-star-ratings.js'='external-owner-cleanup-v1'
}
$plans=New-Object System.Collections.Generic.List[object]
foreach($entry in $registry){
    $item=[pscustomobject]@{name=[string]$entry.name;kind=[string]$entry.kind;policy=[string]$entry.inventory_policy;source=$entry.source;installed=$true}
    $plan=Get-AddonSourceAdapterPlan -Item $item
    Assert-True ([bool]$plan.allowed) "Registered item did not plan: $($entry.name) / $($plan.reason)"
    Assert-Eq $plan.adapter.id $expected[[string]$entry.name] "Wrong adapter for $($entry.name)."
    $plans.Add($plan)
}

$authorized=@($plans|Where-Object{$_.mutation_authorized}|ForEach-Object{[string]$_.entry.name}|Sort-Object)
$expectedAuthorized=@('better-local-files','eternal-jukebox','ivLyrics','playlist-maker')|Sort-Object
Assert-Eq ($authorized -join ',') ($expectedAuthorized -join ',') 'Mutation authority changed.'
Assert-Eq @($plans|Where-Object{$_.mutation_authorized -and -not $_.adapter.mutation_capable}).Count 0 'Non-mutating adapter became mutation-authorized.'
Assert-Eq @($plans|Where-Object{$_.mutation_authorized -and $_.mutation_handler -notin @('pithaya','ivlyrics')}).Count 0 'Unexpected mutation handler was authorized.'

$tagPlan=@($plans|Where-Object{$_.entry.name -ceq 'tagify'})[0]
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion 'v1.2.3' -RemoteVersion '1.3.0').status 'monitor-update-available' 'Tagify update monitoring failed.'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion '1.3.0' -RemoteVersion '1.3.0').status 'monitor-current' 'Tagify current monitoring failed.'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion '1.3.0' -RemoteVersion '1.2.9').status 'monitor-remote-older' 'Tagify downgrade observation failed.'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion '1.3.0' -RemoteVersion '1.4.0-beta.1').status 'monitor-unparseable-version' 'Prerelease must fail closed in strict monitor parser.'
Assert-True (-not [bool]$tagPlan.mutation_authorized) 'Tagify unexpectedly gained mutation authority.'

$starPlan=@($plans|Where-Object{$_.entry.name -ceq 'star-ratings'})[0]
Assert-Eq (Get-AddonSourceVersionObservation -Plan $starPlan -LocalRevision 'abc' -RemoteRevision 'abc').status 'watch-current' 'Star current observation failed.'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $starPlan -LocalRevision 'abc' -RemoteRevision 'def').status 'watch-changed' 'Star changed observation failed.'
Assert-True (-not [bool]$starPlan.mutation_authorized) 'Star Ratings unexpectedly gained mutation authority.'

$splitPlan=@($plans|Where-Object{$_.entry.name -ceq 'splitify'})[0]
Assert-Eq (Get-AddonSourceVersionObservation -Plan $splitPlan).status 'unresolved-source' 'Splitify must remain unresolved-source.'
Assert-True (-not [bool]$splitPlan.mutation_authorized) 'Splitify unexpectedly gained mutation authority.'

$coverPlan=@($plans|Where-Object{$_.entry.name -ceq 'sc-cover-ambience.js'})[0]
Assert-Eq (Get-AddonSourceVersionObservation -Plan $coverPlan).status 'external-owner' 'SC Cover Ambience must remain external-owner.'
Assert-True (-not [bool]$coverPlan.mutation_authorized) 'SC Cover Ambience unexpectedly gained mutation authority.'
Assert-Eq $coverPlan.entry.data_policy 'never-disable-or-optimize' 'SC Cover Ambience protection policy changed.'

$absentIv=[pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$false}
$absentIvPlan=Get-AddonSourceAdapterPlan $absentIv
Assert-True ([bool]$absentIvPlan.allowed) 'Absent installed-only ivLyrics should still produce a source plan.'
Assert-True (-not [bool]$absentIvPlan.mutation_authorized) 'Absent ivLyrics was authorized for auto-install.'
Assert-Eq $absentIvPlan.authorization_reason 'not-installed' 'Absent ivLyrics denial reason changed.'

$tampered=[pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';source='evil/example';installed=$true}
$tamperedPlan=Get-AddonSourceAdapterPlan $tampered
Assert-True (-not [bool]$tamperedPlan.allowed) 'Source mismatch unexpectedly planned.'
Assert-Eq $tamperedPlan.reason 'source-mismatch' 'Source mismatch reason changed.'

$policyTampered=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';source='alexk218/tagify';installed=$true}
$policyTamperedPlan=Get-AddonSourceAdapterPlan $policyTampered
Assert-True (-not [bool]$policyTamperedPlan.allowed) 'Policy mismatch unexpectedly planned.'
Assert-Eq $policyTamperedPlan.reason 'policy-mismatch' 'Policy mismatch reason changed.'

$unknown=[pscustomobject]@{name='future-addon';kind='custom-app';policy='auto';source='future/source';installed=$true}
$unknownPlan=Get-AddonSourceAdapterPlan $unknown
Assert-True (-not [bool]$unknownPlan.allowed) 'Unknown addon unexpectedly planned.'
Assert-Eq $unknownPlan.reason 'unregistered-or-kind-mismatch' 'Unknown addon denial reason changed.'

$playlistPlan=@($plans|Where-Object{$_.entry.name -ceq 'playlist-maker'})[0]
$prov=New-AddonSourceAdapterTransactionProvenance -Plan $playlistPlan
Assert-True (Test-AddonSourceAdapterTransactionProvenance -Provenance $prov -Plan $playlistPlan) 'Valid source-adapter transaction provenance was rejected.'
$badProv=[pscustomobject]@{
    source_adapter_schema=$prov.source_adapter_schema;source_adapter_id='github-release-monitor-v1';source_adapter_strategy=$prov.source_adapter_strategy
    source_adapter_source=$prov.source_adapter_source;source_adapter_rollback=$prov.source_adapter_rollback;registry_sha256=$prov.registry_sha256;mutation_handler=$prov.mutation_handler
}
Assert-True (-not (Test-AddonSourceAdapterTransactionProvenance -Provenance $badProv -Plan $playlistPlan)) 'Tampered adapter provenance was accepted.'
$monitorProvenanceBlocked=$false
try{[void](New-AddonSourceAdapterTransactionProvenance -Plan $tagPlan)}catch{$monitorProvenanceBlocked=$true}
Assert-True $monitorProvenanceBlocked 'Monitor-only plan was allowed to create mutation transaction provenance.'

foreach($adapter in $catalog){
    if(-not [bool]$adapter.mutation_capable){
        Assert-Eq $adapter.archive_policy 'none' "Non-mutating adapter $($adapter.id) unexpectedly acquired archive handling."
        Assert-True ([string]$adapter.network_mode -in @('metadata-only','none')) "Non-mutating adapter $($adapter.id) has unsafe network mode."
    }else{
        Assert-Eq $adapter.archive_policy 'existing-handler-only' "Mutation adapter $($adapter.id) bypasses existing archive safety handler."
        Assert-Eq $adapter.network_mode 'existing-handler-only' "Mutation adapter $($adapter.id) bypasses existing network handler."
    }
}

$fingerprint=Get-AddonSourceAdapterFingerprint
Assert-True ($fingerprint -match '^[0-9a-f]{64}$') 'Adapter fingerprint is not SHA-256.'
Assert-Eq $fingerprint (Get-AddonSourceAdapterFingerprint) 'Adapter fingerprint is nondeterministic.'

$report=[ordered]@{
    result='PASS';schema=$SourceAdapterSchema;registry_sha256=(Get-AddonPolicyRegistryFingerprint);adapter_sha256=$fingerprint
    registry_entries=$registry.Count;adapter_count=$catalog.Count;mutation_authorized_names=$authorized
    tagify_status='monitor-only';star_ratings_status='source-watch-only';splitify_status='unresolved-source';sc_cover_ambience='never-disable-or-optimize'
    unknown_addons='fail-closed';new_auto_install_authority=$false;generic_archive_extraction=$false
}
if(-not [string]::IsNullOrWhiteSpace($ReportPath)){
    $dir=Split-Path -Parent $ReportPath;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
    [pscustomobject]$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
Write-Host 'ADDON_SOURCE_ADAPTER_ENGINE_V010_PASS'
[pscustomobject]$report|ConvertTo-Json -Depth 8
