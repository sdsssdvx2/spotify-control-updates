$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$policy=(Resolve-Path (Join-Path $root 'validation\v0.6.21\addon_policy_registry.ps1.inc')).Path
. ([scriptblock]::Create((Get-Content -LiteralPath $policy -Raw)))
$engine=(Resolve-Path (Join-Path $PSScriptRoot 'addon_source_adapter_engine.ps1.inc')).Path
. ([scriptblock]::Create((Get-Content -LiteralPath $engine -Raw)))
function Write-AddonLog { param([string]$Message,[string]$Level='INFO'); Write-Host "[$Level] $Message" }
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Eq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual='$Actual' expected='$Expected'"}}

Invoke-AddonPolicyRegistrySelfTest
Invoke-AddonSourceAdapterSelfTest
$catalog=@(Get-AddonSourceAdapterCatalog)
Assert-Eq $catalog.Count 6 'adapter count'
$fingerprint=Get-AddonSourceAdapterFingerprint
Assert-True ($fingerprint -match '^[0-9a-f]{64}$') 'adapter fingerprint format'

$entry=Get-AddonPolicyRegistryEntry -Name 'playlist-maker' -Kind 'custom-app'
$item=[pscustomobject]@{name='playlist-maker';kind='custom-app';policy=[string]$entry.inventory_policy;source=[string]$entry.source;installed=$true}
$plan=Get-AddonSourceAdapterPlan -Item $item
Assert-True ([bool]$plan.allowed -and [bool]$plan.mutation_authorized) 'playlist-maker must be authorized through source adapter'
$prov=New-AddonSourceAdapterTransactionProvenance -Plan $plan
$change=[pscustomobject]@{
    name='playlist-maker';registry_kind='custom-app';registry_policy=[string]$entry.inventory_policy;registry_source=[string]$entry.source;registry_handler=[string]$plan.mutation_handler
    source_adapter_id=[string]$prov.source_adapter_id;source_adapter_strategy=[string]$prov.source_adapter_strategy;source_adapter_source=[string]$prov.source_adapter_source;source_adapter_rollback=[string]$prov.source_adapter_rollback
}
$tx=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=(Get-AddonPolicyRegistryFingerprint);source_adapter_schema=1;source_adapter_sha256=$fingerprint;changes=@($change)}
Assert-Eq (Assert-AddonSourceAdapterTransactionAuthorization -Tx $tx) 'current-source-adapter' 'current source-adapter transaction guard'

$badSha=$tx.PSObject.Copy();$badSha.source_adapter_sha256=('0'*64)
$blocked=$false;try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $badSha)}catch{$blocked=$true};Assert-True $blocked 'catalog drift must reject'
$badId=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=$tx.registry_sha256;source_adapter_schema=1;source_adapter_sha256=$fingerprint;changes=@([pscustomobject]@{
    name='playlist-maker';registry_kind='custom-app';registry_policy=[string]$entry.inventory_policy;registry_source=[string]$entry.source;registry_handler=[string]$plan.mutation_handler
    source_adapter_id='github-release-monitor-v1';source_adapter_strategy=[string]$prov.source_adapter_strategy;source_adapter_source=[string]$prov.source_adapter_source;source_adapter_rollback=[string]$prov.source_adapter_rollback
})}
$blocked=$false;try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $badId)}catch{$blocked=$true};Assert-True $blocked 'adapter id tamper must reject'
$partial=[pscustomobject]@{schema=2;source_adapter_schema=1;changes=@([pscustomobject]@{name='x'})}
$blocked=$false;try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $partial)}catch{$blocked=$true};Assert-True $blocked 'partial adapter metadata must reject'
$legacy=[pscustomobject]@{schema=2;changes=@([pscustomobject]@{name='legacy'})}
Assert-Eq (Assert-AddonSourceAdapterTransactionAuthorization -Tx $legacy) 'legacy-r10-no-source-adapter' 'legacy r10 compatibility'

$tag=Get-AddonPolicyRegistryEntry -Name 'tagify' -Kind 'custom-app';$tagItem=[pscustomobject]@{name='tagify';kind='custom-app';policy=[string]$tag.inventory_policy;source=[string]$tag.source;installed=$true};$tagPlan=Get-AddonSourceAdapterPlan $tagItem
Assert-True (-not [bool]$tagPlan.mutation_authorized) 'Tagify mutation authority'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion '1.2.3' -RemoteVersion '1.3.0').status 'monitor-update-available' 'Tagify monitor update'
Assert-Eq (Get-AddonSourceVersionObservation -Plan $tagPlan -LocalVersion '1.2.3' -RemoteVersion '1.3.0-beta.1').status 'monitor-unparseable-version' 'Tagify prerelease fail closed'

$cover=Get-AddonPolicyRegistryEntry -Name 'sc-cover-ambience.js' -Kind 'extension';$coverItem=[pscustomobject]@{name='sc-cover-ambience.js';kind='extension';policy=[string]$cover.inventory_policy;source=$cover.source;installed=$true};$coverPlan=Get-AddonSourceAdapterPlan $coverItem
Assert-True (-not [bool]$coverPlan.mutation_authorized) 'SC Cover Ambience mutation authority'
Assert-Eq $cover.data_policy 'never-disable-or-optimize' 'SC Cover Ambience policy'

Write-Host "R11_SOURCE_ADAPTER_FIXTURES_PASS adapter_sha256=$fingerprint registry_sha256=$(Get-AddonPolicyRegistryFingerprint)"
