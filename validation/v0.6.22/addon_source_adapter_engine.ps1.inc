$AddonSourceAdapterSchema = 1

function Get-AddonSourceAdapterCatalog {
    return @(
        [pscustomobject]@{ id='pithaya-git-tree-v1'; version_strategy='git-commit-tree'; mode='existing-handler-delegation'; existing_handler='pithaya'; mutation_capable=$true; network_mode='existing-handler-only'; archive_policy='existing-handler-only'; rollback_strategy='exact-directory-transaction' },
        [pscustomobject]@{ id='ivlyrics-release-tree-v1'; version_strategy='semver-release-exact-tree'; mode='existing-handler-delegation'; existing_handler='ivlyrics'; mutation_capable=$true; network_mode='existing-handler-only'; archive_policy='existing-handler-only'; rollback_strategy='exact-directory-transaction' },
        [pscustomobject]@{ id='github-release-monitor-v1'; version_strategy='semver-release-monitor'; mode='metadata-monitor-only'; existing_handler='none'; mutation_capable=$false; network_mode='metadata-only'; archive_policy='none'; rollback_strategy='none' },
        [pscustomobject]@{ id='github-head-monitor-v1'; version_strategy='upstream-head-watch'; mode='metadata-monitor-only'; existing_handler='none'; mutation_capable=$false; network_mode='metadata-only'; archive_policy='none'; rollback_strategy='none' },
        [pscustomobject]@{ id='unresolved-source-v1'; version_strategy='unresolved-source'; mode='fail-closed-unresolved'; existing_handler='none'; mutation_capable=$false; network_mode='none'; archive_policy='none'; rollback_strategy='none' },
        [pscustomobject]@{ id='external-owner-cleanup-v1'; version_strategy='owner-cleanup-only'; mode='external-owner-only'; existing_handler='none'; mutation_capable=$false; network_mode='none'; archive_policy='none'; rollback_strategy='external-owner' }
    )
}

function Get-AddonSourceAdapterByStrategy {
    param([Parameter(Mandatory=$true)][string]$VersionStrategy)
    $matches=@(Get-AddonSourceAdapterCatalog | Where-Object { [string]$_.version_strategy -ceq $VersionStrategy })
    if($matches.Count -eq 0){ return $null }
    if($matches.Count -ne 1){ throw "Source adapter catalog has duplicate strategy '$VersionStrategy'." }
    return $matches[0]
}

function Assert-AddonSourceAdapterEntryContract {
    param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)]$Adapter)
    $name=[string]$Entry.name
    switch([string]$Adapter.id){
        'pithaya-git-tree-v1' {
            if([string]$Entry.source -cne 'Pithaya/spicetify-apps-dist' -or [string]$Entry.handler -cne 'pithaya' -or [string]$Entry.rollback_strategy -cne 'exact-directory-transaction'){ throw "Pithaya adapter contract mismatch for $name." }
        }
        'ivlyrics-release-tree-v1' {
            if([string]$Entry.source -cne 'ivLis-Studio/ivLyrics' -or [string]$Entry.handler -cne 'ivlyrics' -or [string]$Entry.rollback_strategy -cne 'exact-directory-transaction'){ throw "ivLyrics adapter contract mismatch for $name." }
        }
        'github-release-monitor-v1' {
            if([string]$Entry.source -cne 'alexk218/tagify' -or [string]$Entry.mutation_mode -cne 'deny' -or [string]$Entry.inventory_policy -cne 'monitor-only'){ throw "Release-monitor adapter contract mismatch for $name." }
        }
        'github-head-monitor-v1' {
            if([string]$Entry.source -cne 'brimell/spicetify-star-ratings' -or [string]$Entry.mutation_mode -cne 'deny' -or [string]$Entry.inventory_policy -cne 'source-watch-only'){ throw "Head-monitor adapter contract mismatch for $name." }
        }
        'unresolved-source-v1' {
            if(-not [string]::IsNullOrEmpty([string]$Entry.source) -or [string]$Entry.mutation_mode -cne 'deny'){ throw "Unresolved-source adapter contract mismatch for $name." }
        }
        'external-owner-cleanup-v1' {
            if([string]$Entry.inventory_policy -cne 'rescue-copy-cleanup-only' -or [string]$Entry.mutation_mode -cne 'deny' -or [string]$Entry.rollback_strategy -cne 'external-owner'){ throw "External-owner adapter contract mismatch for $name." }
        }
        default { throw "Unsupported source adapter id '$($Adapter.id)'." }
    }
}

function Get-AddonSourceAdapterPlan {
    param([Parameter(Mandatory=$true)]$Item)
    $registrySha=Get-AddonPolicyRegistryFingerprint
    $entry=Get-AddonPolicyRegistryEntry -Name ([string]$Item.name) -Kind ([string]$Item.kind)
    if($null -eq $entry){
        return [pscustomobject]@{ schema=$AddonSourceAdapterSchema; allowed=$false; reason='unregistered-or-kind-mismatch'; registry_sha256=$registrySha; entry=$null; adapter=$null; mutation_authorized=$false; mutation_handler=$null; authorization_reason='unregistered' }
    }
    if([string]$Item.policy -cne [string]$entry.inventory_policy){
        return [pscustomobject]@{ schema=$AddonSourceAdapterSchema; allowed=$false; reason='policy-mismatch'; registry_sha256=$registrySha; entry=$entry; adapter=$null; mutation_authorized=$false; mutation_handler=$null; authorization_reason='policy-mismatch' }
    }
    if([string]$Item.source -cne [string]$entry.source){
        return [pscustomobject]@{ schema=$AddonSourceAdapterSchema; allowed=$false; reason='source-mismatch'; registry_sha256=$registrySha; entry=$entry; adapter=$null; mutation_authorized=$false; mutation_handler=$null; authorization_reason='source-mismatch' }
    }
    $adapter=Get-AddonSourceAdapterByStrategy -VersionStrategy ([string]$entry.version_strategy)
    if($null -eq $adapter){
        return [pscustomobject]@{ schema=$AddonSourceAdapterSchema; allowed=$false; reason='unsupported-version-strategy'; registry_sha256=$registrySha; entry=$entry; adapter=$null; mutation_authorized=$false; mutation_handler=$null; authorization_reason='unsupported-version-strategy' }
    }
    Assert-AddonSourceAdapterEntryContract -Entry $entry -Adapter $adapter
    $authorization=Get-AddonMutationAuthorization -Item $Item
    $mutationAuthorized=([bool]$adapter.mutation_capable -and [bool]$authorization.Allowed)
    if([bool]$authorization.Allowed -and -not [bool]$adapter.mutation_capable){ throw "Registry authorized mutation through non-mutating source adapter '$($adapter.id)' for $($Item.name)." }
    if($mutationAuthorized -and [string]$authorization.Handler -cne [string]$adapter.existing_handler){ throw "Registry/adapter handler mismatch for $($Item.name)." }
    return [pscustomobject]@{
        schema=$AddonSourceAdapterSchema; allowed=$true; reason='planned'; registry_sha256=$registrySha; entry=$entry; adapter=$adapter
        mutation_authorized=$mutationAuthorized; mutation_handler=$(if($mutationAuthorized){[string]$authorization.Handler}else{$null}); authorization_reason=[string]$authorization.Reason
    }
}

function ConvertTo-StrictAddonMonitorVersion {
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){ return $null }
    $m=[regex]::Match($Value.Trim(),'^v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$',[System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if(-not $m.Success){ return $null }
    return [version]::new([int]$m.Groups[1].Value,[int]$m.Groups[2].Value,[int]$m.Groups[3].Value,$(if($m.Groups[4].Success){[int]$m.Groups[4].Value}else{0}))
}

function Get-AddonSourceVersionObservation {
    param([Parameter(Mandatory=$true)]$Plan,[AllowNull()][string]$LocalVersion,[AllowNull()][string]$RemoteVersion,[AllowNull()][string]$LocalRevision,[AllowNull()][string]$RemoteRevision)
    if(-not [bool]$Plan.allowed -or $null -eq $Plan.adapter){ return [pscustomobject]@{ status='unplanned'; mutation_authorized=$false } }
    switch([string]$Plan.adapter.id){
        'github-release-monitor-v1' {
            $local=ConvertTo-StrictAddonMonitorVersion $LocalVersion; $remote=ConvertTo-StrictAddonMonitorVersion $RemoteVersion
            if($null -eq $local -or $null -eq $remote){ return [pscustomobject]@{ status='monitor-unparseable-version'; mutation_authorized=$false } }
            if($remote -gt $local){ return [pscustomobject]@{ status='monitor-update-available'; mutation_authorized=$false } }
            if($remote -lt $local){ return [pscustomobject]@{ status='monitor-remote-older'; mutation_authorized=$false } }
            return [pscustomobject]@{ status='monitor-current'; mutation_authorized=$false }
        }
        'github-head-monitor-v1' {
            if([string]::IsNullOrWhiteSpace($LocalRevision) -or [string]::IsNullOrWhiteSpace($RemoteRevision)){ return [pscustomobject]@{ status='watch-unresolved-revision'; mutation_authorized=$false } }
            return [pscustomobject]@{ status=$(if($LocalRevision -ceq $RemoteRevision){'watch-current'}else{'watch-changed'}); mutation_authorized=$false }
        }
        'unresolved-source-v1' { return [pscustomobject]@{ status='unresolved-source'; mutation_authorized=$false } }
        'external-owner-cleanup-v1' { return [pscustomobject]@{ status='external-owner'; mutation_authorized=$false } }
        'pithaya-git-tree-v1' { return [pscustomobject]@{ status='delegated-existing-handler'; mutation_authorized=[bool]$Plan.mutation_authorized } }
        'ivlyrics-release-tree-v1' { return [pscustomobject]@{ status='delegated-existing-handler'; mutation_authorized=[bool]$Plan.mutation_authorized } }
        default { throw "Unsupported source adapter '$($Plan.adapter.id)'." }
    }
}

function New-AddonSourceAdapterTransactionProvenance {
    param([Parameter(Mandatory=$true)]$Plan)
    if(-not [bool]$Plan.allowed -or -not [bool]$Plan.mutation_authorized){ throw 'Source adapter provenance may only be created for a registry-authorized mutation plan.' }
    return [pscustomobject]@{
        source_adapter_schema=$AddonSourceAdapterSchema; source_adapter_id=[string]$Plan.adapter.id; source_adapter_strategy=[string]$Plan.entry.version_strategy
        source_adapter_source=[string]$Plan.entry.source; source_adapter_rollback=[string]$Plan.adapter.rollback_strategy; registry_sha256=[string]$Plan.registry_sha256; mutation_handler=[string]$Plan.mutation_handler
    }
}

function Test-AddonSourceAdapterTransactionProvenance {
    param([Parameter(Mandatory=$true)]$Provenance,[Parameter(Mandatory=$true)]$Plan)
    if(-not [bool]$Plan.allowed -or -not [bool]$Plan.mutation_authorized){ return $false }
    return ([int]$Provenance.source_adapter_schema -eq $AddonSourceAdapterSchema -and [string]$Provenance.source_adapter_id -ceq [string]$Plan.adapter.id -and [string]$Provenance.source_adapter_strategy -ceq [string]$Plan.entry.version_strategy -and [string]$Provenance.source_adapter_source -ceq [string]$Plan.entry.source -and [string]$Provenance.source_adapter_rollback -ceq [string]$Plan.adapter.rollback_strategy -and [string]$Provenance.registry_sha256 -ceq [string]$Plan.registry_sha256 -and [string]$Provenance.mutation_handler -ceq [string]$Plan.mutation_handler)
}

function Get-AddonSourceAdapterFingerprint {
    $rows=New-Object System.Collections.Generic.List[string]
    foreach($a in @(Get-AddonSourceAdapterCatalog | Sort-Object -Property id)){
        $rows.Add((@([string]$a.id,[string]$a.version_strategy,[string]$a.mode,[string]$a.existing_handler,[string]$a.mutation_capable,[string]$a.network_mode,[string]$a.archive_policy,[string]$a.rollback_strategy) -join '|'))
    }
    $bytes=[System.Text.Encoding]::UTF8.GetBytes((($rows.ToArray() -join "`n")+"`n")); $sha=[System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}

function Assert-AddonSourceAdapterTransactionAuthorization {
    param([Parameter(Mandatory=$true)]$Tx)
    $hasSchema=($Tx.PSObject.Properties.Name -contains 'source_adapter_schema') -and $null -ne $Tx.source_adapter_schema
    $hasSha=($Tx.PSObject.Properties.Name -contains 'source_adapter_sha256') -and -not [string]::IsNullOrWhiteSpace([string]$Tx.source_adapter_sha256)
    $changeAdapterMetadata=@($Tx.changes | Where-Object { $_.PSObject.Properties.Name -contains 'source_adapter_id' -or $_.PSObject.Properties.Name -contains 'source_adapter_strategy' -or $_.PSObject.Properties.Name -contains 'source_adapter_source' -or $_.PSObject.Properties.Name -contains 'source_adapter_rollback' })
    if(-not $hasSchema -and -not $hasSha -and $changeAdapterMetadata.Count -eq 0){ return 'legacy-r10-no-source-adapter' }
    if(-not $hasSchema -or -not $hasSha){ throw 'Addon transaction has partial source-adapter metadata.' }
    if([int]$Tx.source_adapter_schema -ne $AddonSourceAdapterSchema){ throw "Unsupported source-adapter transaction schema: $($Tx.source_adapter_schema)" }
    $currentSha=Get-AddonSourceAdapterFingerprint
    if([string]$Tx.source_adapter_sha256 -cne $currentSha){ throw 'Source-adapter catalog drifted since transaction creation.' }
    foreach($change in @($Tx.changes)){
        foreach($required in @('registry_kind','registry_policy','registry_source','registry_handler','source_adapter_id','source_adapter_strategy','source_adapter_source','source_adapter_rollback')){
            if(-not ($change.PSObject.Properties.Name -contains $required)){ throw "Addon transaction change '$($change.name)' is missing $required." }
        }
        $item=[pscustomobject]@{ name=[string]$change.name; kind=[string]$change.registry_kind; policy=[string]$change.registry_policy; source=[string]$change.registry_source; installed=$true }
        $plan=Get-AddonSourceAdapterPlan -Item $item
        if(-not [bool]$plan.allowed -or -not [bool]$plan.mutation_authorized){ throw "Source-adapter authorization revoked for $($change.name)." }
        $prov=[pscustomobject]@{ source_adapter_schema=$AddonSourceAdapterSchema; source_adapter_id=[string]$change.source_adapter_id; source_adapter_strategy=[string]$change.source_adapter_strategy; source_adapter_source=[string]$change.source_adapter_source; source_adapter_rollback=[string]$change.source_adapter_rollback; registry_sha256=[string]$Tx.registry_sha256; mutation_handler=[string]$change.registry_handler }
        if(-not (Test-AddonSourceAdapterTransactionProvenance -Provenance $prov -Plan $plan)){ throw "Source-adapter provenance mismatch for $($change.name)." }
    }
    return 'current-source-adapter'
}

function Invoke-AddonSourceAdapterSelfTest {
    $catalog=@(Get-AddonSourceAdapterCatalog); if($catalog.Count -ne 6){ throw 'Expected six source adapters.' }
    if(@($catalog|ForEach-Object{$_.id}|Sort-Object -Unique).Count -ne 6){ throw 'Duplicate source adapter id.' }
    if(@($catalog|ForEach-Object{$_.version_strategy}|Sort-Object -Unique).Count -ne 6){ throw 'Duplicate source adapter strategy.' }
    $fingerprint=Get-AddonSourceAdapterFingerprint; if($fingerprint -notmatch '^[0-9a-f]{64}$' -or $fingerprint -cne (Get-AddonSourceAdapterFingerprint)){ throw 'Source adapter fingerprint is invalid or nondeterministic.' }
    $plans=New-Object System.Collections.Generic.List[object]
    foreach($entry in @(Get-AddonPolicyRegistry)){
        $item=[pscustomobject]@{ name=[string]$entry.name; kind=[string]$entry.kind; policy=[string]$entry.inventory_policy; source=$entry.source; installed=$true }
        $plan=Get-AddonSourceAdapterPlan -Item $item; if(-not [bool]$plan.allowed){ throw "Registered source adapter plan failed for $($entry.name)." }; $plans.Add($plan)
    }
    $authorized=@($plans|Where-Object{$_.mutation_authorized}|ForEach-Object{[string]$_.entry.name}|Sort-Object)
    if(($authorized -join ',') -cne 'better-local-files,eternal-jukebox,ivLyrics,playlist-maker'){ throw "Source adapter authority drift: $($authorized -join ',')" }
    foreach($name in @('tagify','splitify','star-ratings','sc-cover-ambience.js','sc-star-ratings.js')){ if([bool](@($plans|Where-Object{$_.entry.name -ceq $name})[0].mutation_authorized)){ throw "$name unexpectedly gained mutation authority." } }
    $absent=[pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$false}; $absentPlan=Get-AddonSourceAdapterPlan $absent
    if([bool]$absentPlan.mutation_authorized -or [string]$absentPlan.authorization_reason -cne 'not-installed'){ throw 'Installed-only source adapter guard failed.' }
    $playlist=@($plans|Where-Object{$_.entry.name -ceq 'playlist-maker'})[0]; $prov=New-AddonSourceAdapterTransactionProvenance $playlist
    if(-not (Test-AddonSourceAdapterTransactionProvenance -Provenance $prov -Plan $playlist)){ throw 'Valid source adapter provenance rejected.' }
    $legacy=[pscustomobject]@{schema=2;changes=@([pscustomobject]@{name='legacy'})}; if((Assert-AddonSourceAdapterTransactionAuthorization $legacy) -cne 'legacy-r10-no-source-adapter'){ throw 'Legacy r10 source adapter compatibility failed.' }
    Write-AddonLog "Addon source adapter self-test passed: six deterministic adapters, exact four-name mutation authority, installed-only protection, denied protected sources, transaction provenance, and legacy r10 compatibility."
}
