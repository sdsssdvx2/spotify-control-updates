function New-MarketplaceRefreshDecision {
    param(
        [bool]$Applicable,
        [bool]$Conclusive,
        [string]$Kind,
        [string]$Owner,
        [string]$RuntimeRefresh,
        [string]$MetadataRefresh,
        [string]$StoredStateRefresh,
        [bool]$AutomaticRuntimeContentRefresh,
        [bool]$FullInstalledRecordRefreshGuaranteed,
        [bool]$AddonManagerDirectMutationAllowed,
        [string]$Reason
    )
    return [pscustomobject]@{
        schema = 1
        applicable = $Applicable
        conclusive = $Conclusive
        kind = $Kind
        owner = $Owner
        runtime_refresh = $RuntimeRefresh
        metadata_refresh = $MetadataRefresh
        stored_state_refresh = $StoredStateRefresh
        automatic_runtime_content_refresh = $AutomaticRuntimeContentRefresh
        full_installed_record_refresh_guaranteed = $FullInstalledRecordRefreshGuaranteed
        addon_manager_direct_mutation_allowed = $AddonManagerDirectMutationAllowed
        reason = $Reason
    }
}

function Resolve-MarketplaceNativeRefreshContract {
    param($Record)

    if ($null -eq $Record) {
        return New-MarketplaceRefreshDecision $true $false $null 'unknown' 'none' 'none' 'none' $false $false $false 'record-null'
    }
    if ($Record.PSObject.Properties['mutation_authorized'] -and [bool]$Record.mutation_authorized) {
        return New-MarketplaceRefreshDecision $true $false ([string]$Record.kind) 'unknown' 'none' 'none' 'none' $false $false $false 'collector-authority-violation'
    }
    if ($Record.PSObject.Properties['ambiguous'] -and [bool]$Record.ambiguous) {
        return New-MarketplaceRefreshDecision $true $false ([string]$Record.kind) 'unknown' 'none' 'none' 'none' $false $false $false 'record-ambiguous'
    }

    $kind = ([string]$Record.kind).Trim().ToLowerInvariant()
    $sourceKind = ([string]$Record.source_kind).Trim().ToLowerInvariant()
    if ($kind -eq 'unlisted') {
        return New-MarketplaceRefreshDecision $true $false $kind 'marketplace-storage' 'unknown' 'unknown' 'unknown' $false $false $false 'unlisted-record-not-safe-to-classify'
    }
    if ($kind -notin @('extension','theme','snippet')) {
        return New-MarketplaceRefreshDecision $false $false $kind 'not-marketplace-installed-record' 'none' 'none' 'none' $false $false $false 'unsupported-marketplace-installed-kind'
    }

    if ($kind -eq 'snippet') {
        if ($sourceKind -ne 'snippet-key') {
            return New-MarketplaceRefreshDecision $true $false $kind 'marketplace-storage' 'none' 'none' 'stored-code' $false $false $false 'snippet-source-identity-invalid'
        }
        return New-MarketplaceRefreshDecision $true $true $kind 'marketplace-storage' 'stored-code-injected-on-start' 'none' 'installed-snippet-record-is-code-source' $false $false $false 'snippet-has-no-native-automatic-content-refresh'
    }

    if ($sourceKind -ne 'github-repository-key') {
        return New-MarketplaceRefreshDecision $true $false $kind 'marketplace-runtime' 'unknown' 'unknown' 'unknown' $false $false $false 'github-source-identity-required'
    }

    if ($kind -eq 'extension') {
        return New-MarketplaceRefreshDecision $true $true $kind 'marketplace-runtime' 'remote-script-at-stored-extension-url-refetched-on-spotify-start-with-cache-busting' 'installed-card-refreshes-record-when-installed-tab-card-mounts-and-github-pushed-at-changed' 'manifest-and-url-remain-stored-until-card-refresh' $true $false $false 'runtime-content-refreshes-at-stored-url-but-record-url-drift-is-not-covered'
    }

    if ($kind -eq 'theme') {
        return New-MarketplaceRefreshDecision $true $true $kind 'marketplace-runtime' 'remote-css-and-included-js-at-stored-urls-refetched-on-spotify-start' 'installed-card-refreshes-record-when-installed-tab-card-mounts-and-github-pushed-at-changed' 'theme-update-preserves-stored-schemes-and-active-scheme' $true $false $false 'runtime-css-js-refreshes-but-schemes-and-url-metadata-are-not-fully-automatic'
    }

    throw "Unhandled Marketplace kind: $kind"
}

function Invoke-MarketplaceNativeRefreshContractSelfTest {
    $extension = [pscustomobject]@{ kind='extension'; source_kind='github-repository-key'; ambiguous=$false; mutation_authorized=$false }
    $ext = Resolve-MarketplaceNativeRefreshContract $extension
    if (-not $ext.conclusive -or -not $ext.automatic_runtime_content_refresh -or $ext.full_installed_record_refresh_guaranteed -or $ext.addon_manager_direct_mutation_allowed) {
        throw 'Native refresh contract: extension semantics drifted.'
    }
    if ([string]$ext.runtime_refresh -notlike '*stored-extension-url*' -or [string]$ext.metadata_refresh -notlike '*installed-tab-card*') {
        throw 'Native refresh contract: extension refresh trigger was not explicit.'
    }

    $theme = [pscustomobject]@{ kind='theme'; source_kind='github-repository-key'; ambiguous=$false; mutation_authorized=$false }
    $th = Resolve-MarketplaceNativeRefreshContract $theme
    if (-not $th.conclusive -or -not $th.automatic_runtime_content_refresh -or $th.full_installed_record_refresh_guaranteed -or $th.addon_manager_direct_mutation_allowed) {
        throw 'Native refresh contract: theme semantics drifted.'
    }
    if ([string]$th.stored_state_refresh -cne 'theme-update-preserves-stored-schemes-and-active-scheme') {
        throw 'Native refresh contract: theme scheme preservation caveat is missing.'
    }

    $snippet = [pscustomobject]@{ kind='snippet'; source_kind='snippet-key'; ambiguous=$false; mutation_authorized=$false }
    $sn = Resolve-MarketplaceNativeRefreshContract $snippet
    if (-not $sn.conclusive -or $sn.automatic_runtime_content_refresh -or $sn.full_installed_record_refresh_guaranteed -or $sn.addon_manager_direct_mutation_allowed) {
        throw 'Native refresh contract: snippet semantics drifted.'
    }
    if ([string]$sn.stored_state_refresh -cne 'installed-snippet-record-is-code-source') {
        throw 'Native refresh contract: snippet stored-code ownership is missing.'
    }

    $unlisted = Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{ kind='unlisted'; source_kind='github-repository-key'; ambiguous=$false; mutation_authorized=$false })
    if ($unlisted.conclusive -or $unlisted.addon_manager_direct_mutation_allowed) { throw 'Native refresh contract: unlisted record did not fail closed.' }

    $ambiguous = Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{ kind='extension'; source_kind='github-repository-key'; ambiguous=$true; mutation_authorized=$false })
    if ($ambiguous.conclusive -or $ambiguous.addon_manager_direct_mutation_allowed) { throw 'Native refresh contract: ambiguous record did not fail closed.' }

    $authorityViolation = Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{ kind='extension'; source_kind='github-repository-key'; ambiguous=$false; mutation_authorized=$true })
    if ($authorityViolation.conclusive -or $authorityViolation.addon_manager_direct_mutation_allowed) { throw 'Native refresh contract: collector authority violation did not fail closed.' }

    $customApp = Resolve-MarketplaceNativeRefreshContract ([pscustomobject]@{ kind='custom-app'; source_kind='github-repository-key'; ambiguous=$false; mutation_authorized=$false })
    if ($customApp.applicable -or $customApp.addon_manager_direct_mutation_allowed) { throw 'Native refresh contract: custom app was incorrectly treated as Marketplace-installed storage.' }

    Write-Host 'MARKETPLACE_NATIVE_REFRESH_CONTRACT_SELFTEST_PASS'
}
