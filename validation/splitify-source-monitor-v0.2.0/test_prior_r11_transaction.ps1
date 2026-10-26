$ErrorActionPreference='Stop'
Set-StrictMode -Version 2

$addonPath=Join-Path $PSScriptRoot 'out/bin/addon-manager.ps1'
if(-not (Test-Path -LiteralPath $addonPath -PathType Leaf)){throw "Candidate Addon Manager missing: $addonPath"}
$addon=Get-Content -LiteralPath $addonPath -Raw

function Get-CandidateFunctionBlock {
    param([Parameter(Mandatory=$true)][string]$Name)
    $marker="function $Name {"
    $start=$addon.IndexOf($marker,[StringComparison]::Ordinal)
    if($start -lt 0){throw "Candidate function missing: $Name"}
    $next=$addon.IndexOf("`nfunction ",$start+$marker.Length,[StringComparison]::Ordinal)
    if($next -lt 0){$next=$addon.Length}
    return $addon.Substring($start,$next-$start)
}

# Evaluate only the exact pure policy/source-adapter functions needed by this fixture.
# No inventory/network/update/apply/rollback function is imported or executed.
$names=@(
    'Get-AddonPolicyRegistry',
    'Get-AddonPolicyRegistryFingerprint',
    'Get-AddonPolicyRegistryEntry',
    'Get-AddonMutationAuthorization',
    'Get-AddonSourceAdapterCatalog',
    'Get-AddonSourceAdapterByStrategy',
    'Assert-AddonSourceAdapterEntryContract',
    'Get-AddonSourceAdapterPlan',
    'Test-AddonSourceAdapterTransactionProvenance',
    'Get-AddonSourceAdapterFingerprint',
    'Assert-AddonSourceAdapterTransactionAuthorization'
)
$scriptText='$AddonSourceAdapterSchema = 1'+"`n`n"+(($names|ForEach-Object{Get-CandidateFunctionBlock $_}) -join "`n`n")
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw 'Extracted candidate compatibility surface failed PowerShell parse.'}
Invoke-Expression $scriptText

$currentRegistry=Get-AddonPolicyRegistryFingerprint
$priorRegistry='05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'
if($currentRegistry -ceq $priorRegistry){throw 'Candidate registry fingerprint unexpectedly equals r11 fingerprint.'}
$currentAdapter=Get-AddonSourceAdapterFingerprint
if($currentAdapter -notmatch '^[0-9a-f]{64}$'){throw 'Candidate source-adapter fingerprint is invalid.'}

$splitify=[pscustomobject]@{name='splitify';kind='custom-app';policy='monitor-only';source='alexander-rebello/splitify';installed=$true}
$splitifyPlan=Get-AddonSourceAdapterPlan -Item $splitify
if(-not [bool]$splitifyPlan.allowed){throw "Splitify monitor plan was rejected: $($splitifyPlan.reason)"}
if([string]$splitifyPlan.adapter.id -cne 'github-release-monitor-v1'){throw "Splitify resolved to unexpected adapter: $($splitifyPlan.adapter.id)"}
if([bool]$splitifyPlan.mutation_authorized){throw 'Splitify monitor plan unexpectedly gained mutation authority.'}

$change=[pscustomobject]@{
    name='playlist-maker'
    registry_kind='custom-app'
    registry_policy='auto'
    registry_source='Pithaya/spicetify-apps-dist'
    registry_handler='pithaya'
    source_adapter_id='pithaya-git-tree-v1'
    source_adapter_strategy='git-commit-tree'
    source_adapter_source='Pithaya/spicetify-apps-dist'
    source_adapter_rollback='exact-directory-transaction'
}
$priorTx=[pscustomobject]@{
    schema=2
    registry_schema=1
    registry_sha256=$priorRegistry
    source_adapter_schema=1
    source_adapter_sha256=$currentAdapter
    changes=@($change)
}
$mode=Assert-AddonSourceAdapterTransactionAuthorization -Tx $priorTx
if([string]$mode -cne 'current-source-adapter-compatible-prior-registry'){throw "Exact r11 transaction compatibility failed: $mode"}

# A changed managed source must still fail closed even under the exact prior registry fingerprint.
$tamperedChange=[pscustomobject]@{
    name='playlist-maker'
    registry_kind='custom-app'
    registry_policy='auto'
    registry_source='evil/source'
    registry_handler='pithaya'
    source_adapter_id='pithaya-git-tree-v1'
    source_adapter_strategy='git-commit-tree'
    source_adapter_source='evil/source'
    source_adapter_rollback='exact-directory-transaction'
}
$tampered=[pscustomobject]@{
    schema=2;registry_schema=1;registry_sha256=$priorRegistry
    source_adapter_schema=1;source_adapter_sha256=$currentAdapter;changes=@($tamperedChange)
}
$failed=$false
try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $tampered)}catch{$failed=$true}
if(-not $failed){throw 'Tampered r11-compatible transaction was incorrectly authorized.'}

# Compatibility is pinned to one exact historical fingerprint, not an arbitrary old registry.
$unknownPrior=[pscustomobject]@{
    schema=2;registry_schema=1;registry_sha256=('a'*64)
    source_adapter_schema=1;source_adapter_sha256=$currentAdapter;changes=@($change)
}
$failed=$false
try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $unknownPrior)}catch{$failed=$true}
if(-not $failed){throw 'Unknown historical registry fingerprint was incorrectly authorized.'}

Write-Host "SPLITIFY_R12_R11_SOURCE_TRANSACTION_COMPAT_PASS current_registry=$currentRegistry prior_registry=$priorRegistry adapter=$currentAdapter mode=$mode"
