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

$names=@(
    'Get-AddonPolicyRegistry','Get-AddonPolicyRegistryFingerprint','Get-AddonPolicyRegistryEntry','Get-AddonMutationAuthorization',
    'Get-AddonSourceAdapterCatalog','Get-AddonSourceAdapterByStrategy','Assert-AddonSourceAdapterEntryContract','Get-AddonSourceAdapterPlan',
    'Test-AddonSourceAdapterTransactionProvenance','Get-AddonSourceAdapterFingerprint','Assert-AddonSourceAdapterTransactionAuthorization'
)
$scriptText='$AddonSourceAdapterSchema = 1'+"`n`n"+(($names|ForEach-Object{Get-CandidateFunctionBlock $_}) -join "`n`n")
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw 'Extracted candidate compatibility surface failed PowerShell parse.'}
Invoke-Expression $scriptText

$currentRegistry=Get-AddonPolicyRegistryFingerprint
$priorRegistry='05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'
$expectedCurrent='0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
$expectedAdapter='c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
if($currentRegistry -cne $expectedCurrent){throw "Candidate registry fingerprint mismatch: $currentRegistry"}
$currentAdapter=Get-AddonSourceAdapterFingerprint
if($currentAdapter -cne $expectedAdapter){throw "Candidate source-adapter fingerprint mismatch: $currentAdapter"}

$splitify=[pscustomobject]@{name='splitify';kind='custom-app';policy='monitor-only';source='alexander-rebello/splitify';installed=$true}
$splitifyPlan=Get-AddonSourceAdapterPlan -Item $splitify
if(-not [bool]$splitifyPlan.allowed -or [string]$splitifyPlan.adapter.id -cne 'github-release-monitor-v1' -or [bool]$splitifyPlan.mutation_authorized){throw 'Splitify monitor plan contract failed.'}

$change=[pscustomobject]@{
    name='playlist-maker';registry_kind='custom-app';registry_policy='auto';registry_source='Pithaya/spicetify-apps-dist';registry_handler='pithaya'
    source_adapter_id='pithaya-git-tree-v1';source_adapter_strategy='git-commit-tree';source_adapter_source='Pithaya/spicetify-apps-dist';source_adapter_rollback='exact-directory-transaction'
}
$priorTx=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=$priorRegistry;source_adapter_schema=1;source_adapter_sha256=$currentAdapter;changes=@($change)}
$mode=Assert-AddonSourceAdapterTransactionAuthorization -Tx $priorTx
if([string]$mode -cne 'current-source-adapter-compatible-prior-registry'){throw "Exact r11 transaction compatibility failed: $mode"}

$tamperedChange=[pscustomobject]@{
    name='playlist-maker';registry_kind='custom-app';registry_policy='auto';registry_source='evil/source';registry_handler='pithaya'
    source_adapter_id='pithaya-git-tree-v1';source_adapter_strategy='git-commit-tree';source_adapter_source='evil/source';source_adapter_rollback='exact-directory-transaction'
}
$tampered=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=$priorRegistry;source_adapter_schema=1;source_adapter_sha256=$currentAdapter;changes=@($tamperedChange)}
$failed=$false
try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $tampered)}catch{$failed=$true}
if(-not $failed){throw 'Tampered r11-compatible transaction was incorrectly authorized.'}

$unknownPrior=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=('a'*64);source_adapter_schema=1;source_adapter_sha256=$currentAdapter;changes=@($change)}
$failed=$false
try{[void](Assert-AddonSourceAdapterTransactionAuthorization -Tx $unknownPrior)}catch{$failed=$true}
if(-not $failed){throw 'Unknown historical registry fingerprint was incorrectly authorized.'}

Write-Host "V0623_R12_R11_SOURCE_TRANSACTION_COMPAT_PASS current_registry=$currentRegistry prior_registry=$priorRegistry adapter=$currentAdapter mode=$mode"
