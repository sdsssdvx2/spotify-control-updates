function Resolve-MarketplaceRecordUpdateTopology {
    param($Record)

    if ($null -eq $Record) {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'unknown'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'marketplace-record-null'; source = $null; key = $null
        }
    }

    $kind = ([string]$Record.kind).Trim().ToLowerInvariant()
    $key = if ($Record.PSObject.Properties['key']) { [string]$Record.key } else { $null }
    $source = $null
    if ($Record.PSObject.Properties['github_owner'] -and $Record.PSObject.Properties['github_repo']) {
        $owner = ([string]$Record.github_owner).Trim()
        $repo = ([string]$Record.github_repo).Trim()
        if (-not [string]::IsNullOrWhiteSpace($owner) -and -not [string]::IsNullOrWhiteSpace($repo)) {
            $source = $owner + '/' + $repo
        }
    }

    if (($Record.PSObject.Properties['ambiguous'] -and [bool]$Record.ambiguous) -or $kind -eq 'ambiguous-multiple-lists') {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'unknown'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'marketplace-record-ambiguous'; source = $source; key = $key
        }
    }
    if ($Record.PSObject.Properties['mutation_authorized'] -and [bool]$Record.mutation_authorized) {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'unknown'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'collector-authority-contract-violation'; source = $source; key = $key
        }
    }

    switch ($kind) {
        'extension' {
            return [pscustomobject]@{
                schema = 1; applicable = $true; owner = 'marketplace-native-runtime';
                update_mode = 'remote-url-runtime-refresh'; manager_direct_mutation_authorized = $false;
                marketplace_native_refresh = $true; reason = 'extension-code-is-runtime-remote-owned';
                source = $source; key = $key
            }
        }
        'theme' {
            return [pscustomobject]@{
                schema = 1; applicable = $true; owner = 'marketplace-native-runtime';
                update_mode = 'remote-theme-runtime-refresh'; manager_direct_mutation_authorized = $false;
                marketplace_native_refresh = $true; reason = 'theme-css-is-runtime-remote-owned';
                source = $source; key = $key
            }
        }
        'snippet' {
            return [pscustomobject]@{
                schema = 1; applicable = $true; owner = 'marketplace-storage';
                update_mode = 'marketplace-storage-owned'; manager_direct_mutation_authorized = $false;
                marketplace_native_refresh = $false; reason = 'snippet-content-is-marketplace-storage-owned';
                source = $source; key = $key
            }
        }
        default {
            return [pscustomobject]@{
                schema = 1; applicable = $true; owner = 'unknown'; update_mode = 'deny';
                manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
                reason = ('unsupported-or-unlisted-marketplace-kind:' + $kind); source = $source; key = $key
            }
        }
    }
}

function Resolve-ManagedCustomAppUpdateTopology {
    param($Item,$Authorization)

    if ($null -eq $Item) {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'unknown'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'custom-app-item-null'; source = $null; name = $null
        }
    }
    $kind = ([string]$Item.kind).Trim().ToLowerInvariant()
    $name = [string]$Item.name
    $source = [string]$Item.source
    if ($kind -ne 'custom-app') {
        return [pscustomobject]@{
            schema = 1; applicable = $false; owner = 'not-custom-app'; update_mode = 'not-applicable';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'not-custom-app'; source = $source; name = $name
        }
    }
    if (-not ($Item.PSObject.Properties['installed']) -or -not [bool]$Item.installed) {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'local-spicetify'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'custom-app-not-installed'; source = $source; name = $name
        }
    }
    if ($null -eq $Authorization -or -not ($Authorization.PSObject.Properties['Allowed']) -or -not [bool]$Authorization.Allowed) {
        $reason = if ($null -ne $Authorization -and $Authorization.PSObject.Properties['Reason']) { [string]$Authorization.Reason } else { 'authorization-missing' }
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'local-spicetify'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = ('managed-custom-app-denied:' + $reason); source = $source; name = $name
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Authorization.Handler)) {
        return [pscustomobject]@{
            schema = 1; applicable = $true; owner = 'local-spicetify'; update_mode = 'deny';
            manager_direct_mutation_authorized = $false; marketplace_native_refresh = $false;
            reason = 'authorized-custom-app-has-no-handler'; source = $source; name = $name
        }
    }

    return [pscustomobject]@{
        schema = 1; applicable = $true; owner = 'addon-manager-installed-only';
        update_mode = 'explicit-source-adapter'; manager_direct_mutation_authorized = $true;
        marketplace_native_refresh = $false; reason = 'existing-explicit-managed-custom-app-authority';
        source = $source; name = $name; handler = [string]$Authorization.Handler
    }
}

function Get-MarketplaceSourceTopologySummary {
    param([object[]]$Records)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($record in @($Records)) { $rows.Add((Resolve-MarketplaceRecordUpdateTopology -Record $record)) }
    return [pscustomobject]@{
        schema = 1
        record_count = $rows.Count
        marketplace_native_count = @($rows | Where-Object { $_.marketplace_native_refresh }).Count
        manager_direct_mutation_count = @($rows | Where-Object { $_.manager_direct_mutation_authorized }).Count
        denied_count = @($rows | Where-Object { $_.update_mode -eq 'deny' }).Count
        rows = $rows.ToArray()
    }
}

function Invoke-MarketplaceSourceTopologySelfTest {
    $newRecord = {
        param([string]$Kind,[bool]$Ambiguous=$false,[bool]$MutationAuthorized=$false)
        [pscustomobject]@{
            key = ('marketplace:installed:example/repo/' + $Kind + '.js')
            kind = $Kind
            github_owner = 'example'
            github_repo = 'repo'
            ambiguous = $Ambiguous
            mutation_authorized = $MutationAuthorized
        }
    }

    $extension = Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'extension')
    if ([string]$extension.owner -cne 'marketplace-native-runtime' -or [string]$extension.update_mode -cne 'remote-url-runtime-refresh' -or [bool]$extension.manager_direct_mutation_authorized -or -not [bool]$extension.marketplace_native_refresh) {
        throw 'Marketplace topology self-test: extension ownership contract drifted.'
    }

    $theme = Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'theme')
    if ([string]$theme.owner -cne 'marketplace-native-runtime' -or [string]$theme.update_mode -cne 'remote-theme-runtime-refresh' -or [bool]$theme.manager_direct_mutation_authorized -or -not [bool]$theme.marketplace_native_refresh) {
        throw 'Marketplace topology self-test: theme ownership contract drifted.'
    }

    $snippet = Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'snippet')
    if ([string]$snippet.owner -cne 'marketplace-storage' -or [string]$snippet.update_mode -cne 'marketplace-storage-owned' -or [bool]$snippet.manager_direct_mutation_authorized) {
        throw 'Marketplace topology self-test: snippet ownership contract drifted.'
    }

    foreach ($denied in @(
        (Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'unlisted')),
        (Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'extension' $true $false)),
        (Resolve-MarketplaceRecordUpdateTopology -Record (& $newRecord 'extension' $false $true)),
        (Resolve-MarketplaceRecordUpdateTopology -Record $null)
    )) {
        if ([string]$denied.update_mode -cne 'deny' -or [bool]$denied.manager_direct_mutation_authorized) {
            throw 'Marketplace topology self-test: unsafe Marketplace record gained direct manager mutation authority.'
        }
    }

    $unknownApp = [pscustomobject]@{name='future-app';kind='custom-app';source='future/repo';installed=$true}
    $unknownAuth = [pscustomobject]@{Allowed=$false;Handler=$null;Reason='not-in-registry'}
    $unknownTopology = Resolve-ManagedCustomAppUpdateTopology -Item $unknownApp -Authorization $unknownAuth
    if ([string]$unknownTopology.update_mode -cne 'deny' -or [bool]$unknownTopology.manager_direct_mutation_authorized) {
        throw 'Marketplace topology self-test: unknown future custom app gained mutation authority.'
    }

    $knownApp = [pscustomobject]@{name='tagify';kind='custom-app';source='alexk218/tagify';installed=$true}
    $knownAuth = [pscustomobject]@{Allowed=$true;Handler='tagify';Reason='authorized'}
    $knownTopology = Resolve-ManagedCustomAppUpdateTopology -Item $knownApp -Authorization $knownAuth
    if ([string]$knownTopology.owner -cne 'addon-manager-installed-only' -or [string]$knownTopology.update_mode -cne 'explicit-source-adapter' -or -not [bool]$knownTopology.manager_direct_mutation_authorized) {
        throw 'Marketplace topology self-test: explicitly authorized installed custom app was not delegated to the source-adapter engine.'
    }

    $absentApp = [pscustomobject]@{name='tagify';kind='custom-app';source='alexk218/tagify';installed=$false}
    $absentTopology = Resolve-ManagedCustomAppUpdateTopology -Item $absentApp -Authorization $knownAuth
    if ([string]$absentTopology.update_mode -cne 'deny' -or [bool]$absentTopology.manager_direct_mutation_authorized) {
        throw 'Marketplace topology self-test: absent custom app escaped installed-only semantics.'
    }

    $summary = Get-MarketplaceSourceTopologySummary -Records @((& $newRecord 'extension'),(& $newRecord 'theme'),(& $newRecord 'snippet'),(& $newRecord 'unlisted'))
    if ([int]$summary.record_count -ne 4 -or [int]$summary.marketplace_native_count -ne 2 -or [int]$summary.manager_direct_mutation_count -ne 0 -or [int]$summary.denied_count -ne 1) {
        throw 'Marketplace topology self-test: summary counts drifted.'
    }

    Write-AddonLog 'Marketplace source topology self-test passed: native runtime ownership, storage ownership, installed-only custom-app delegation, and unknown-source fail-closed semantics.'
}
