# BEGIN SPOTIFY CONTROL ADDON POLICY REGISTRY v1 / r10
# This registry is authoritative for mutation permission only. It intentionally does not
# grant any new addon automatic-update authority beyond the already runtime-accepted r9 set.
function Get-AddonPolicyRegistry {
    return @(
        [pscustomobject]@{ name='ivLyrics'; kind='custom-app'; source='ivLis-Studio/ivLyrics'; inventory_policy='auto'; mutation_mode='auto'; handler='ivlyrics'; install_mode='installed-only'; version_strategy='semver-release-exact-tree'; rollback_strategy='exact-directory-transaction'; data_policy='preserve-installed-only' },
        [pscustomobject]@{ name='better-local-files'; kind='custom-app'; source='Pithaya/spicetify-apps-dist'; inventory_policy='auto'; mutation_mode='auto'; handler='pithaya'; install_mode='installed-only'; version_strategy='git-commit-tree'; rollback_strategy='exact-directory-transaction'; data_policy='preserve-local-divergence' },
        [pscustomobject]@{ name='eternal-jukebox'; kind='custom-app'; source='Pithaya/spicetify-apps-dist'; inventory_policy='auto'; mutation_mode='auto'; handler='pithaya'; install_mode='installed-only'; version_strategy='git-commit-tree'; rollback_strategy='exact-directory-transaction'; data_policy='preserve-local-divergence' },
        [pscustomobject]@{ name='playlist-maker'; kind='custom-app'; source='Pithaya/spicetify-apps-dist'; inventory_policy='auto'; mutation_mode='auto'; handler='pithaya'; install_mode='installed-only'; version_strategy='git-commit-tree'; rollback_strategy='exact-directory-transaction'; data_policy='preserve-local-divergence' },
        [pscustomobject]@{ name='tagify'; kind='custom-app'; source='alexk218/tagify'; inventory_policy='monitor-only'; mutation_mode='deny'; handler='none'; install_mode='never-auto-install'; version_strategy='semver-release-monitor'; rollback_strategy='none'; data_policy='protect-ratings-tags-notes' },
        [pscustomobject]@{ name='splitify'; kind='custom-app'; source=$null; inventory_policy='unknown-source'; mutation_mode='deny'; handler='none'; install_mode='never-auto-install'; version_strategy='unresolved-source'; rollback_strategy='none'; data_policy='preserve-unknown-source' },
        [pscustomobject]@{ name='star-ratings'; kind='marketplace-extension'; source='brimell/spicetify-star-ratings'; inventory_policy='source-watch-only'; mutation_mode='deny'; handler='none'; install_mode='marketplace-owned'; version_strategy='upstream-head-watch'; rollback_strategy='none'; data_policy='playlist-backed-ratings-preserve' },
        [pscustomobject]@{ name='sc-cover-ambience.js'; kind='extension'; source='Theblockbuster1/spicetify-extensions'; inventory_policy='rescue-copy-cleanup-only'; mutation_mode='deny'; handler='none'; install_mode='recovery-owned'; version_strategy='owner-cleanup-only'; rollback_strategy='external-owner'; data_policy='never-disable-or-optimize' },
        [pscustomobject]@{ name='sc-star-ratings.js'; kind='extension'; source='brimell/spicetify-star-ratings'; inventory_policy='rescue-copy-cleanup-only'; mutation_mode='deny'; handler='none'; install_mode='recovery-owned'; version_strategy='owner-cleanup-only'; rollback_strategy='external-owner'; data_policy='playlist-backed-ratings-preserve' }
    )
}

function Get-AddonPolicyRegistryFingerprint {
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(Get-AddonPolicyRegistry | Sort-Object -Property kind,name)) {
        $rows.Add((@(
            [string]$entry.name,[string]$entry.kind,[string]$entry.source,[string]$entry.inventory_policy,
            [string]$entry.mutation_mode,[string]$entry.handler,[string]$entry.install_mode,
            [string]$entry.version_strategy,[string]$entry.rollback_strategy,[string]$entry.data_policy
        ) -join '|'))
    }
    $payload = (($rows.ToArray() -join "`n") + "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-AddonPolicyRegistryEntry {
    param([Parameter(Mandatory=$true)][string]$Name,[AllowNull()][AllowEmptyString()][string]$Kind)
    $nameMatches = @(Get-AddonPolicyRegistry | Where-Object { [string]$_.name -ceq [string]$Name })
    if ($nameMatches.Count -eq 0) { return $null }
    if ($nameMatches.Count -ne 1) { throw "Addon policy registry has duplicate name '$Name'." }
    $entry = $nameMatches[0]
    if (-not [string]::IsNullOrWhiteSpace([string]$Kind) -and [string]$entry.kind -cne [string]$Kind) { return $null }
    return $entry
}

function Get-AddonMutationAuthorization {
    param([Parameter(Mandatory=$true)]$Item)
    $fingerprint = Get-AddonPolicyRegistryFingerprint
    $entry = Get-AddonPolicyRegistryEntry -Name ([string]$Item.name)
    if ($null -eq $entry) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='unregistered'; Entry=$null; RegistrySha256=$fingerprint } }
    if ([string]$Item.kind -cne [string]$entry.kind) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='kind-mismatch'; Entry=$entry; RegistrySha256=$fingerprint } }
    if ([string]$Item.policy -cne [string]$entry.inventory_policy) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='policy-mismatch'; Entry=$entry; RegistrySha256=$fingerprint } }
    if ([string]$Item.source -cne [string]$entry.source) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='source-mismatch'; Entry=$entry; RegistrySha256=$fingerprint } }
    if ([string]$entry.mutation_mode -cne 'auto') { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='registry-deny'; Entry=$entry; RegistrySha256=$fingerprint } }
    if ([string]$entry.install_mode -ceq 'installed-only' -and $Item.installed -ne $true) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='not-installed'; Entry=$entry; RegistrySha256=$fingerprint } }
    if ([string]$entry.handler -notin @('pithaya','ivlyrics')) { return [pscustomobject]@{ Allowed=$false; Handler=$null; Reason='unsupported-handler'; Entry=$entry; RegistrySha256=$fingerprint } }
    return [pscustomobject]@{ Allowed=$true; Handler=[string]$entry.handler; Reason='authorized'; Entry=$entry; RegistrySha256=$fingerprint }
}

function Add-AddonPolicyRegistryMetadata {
    param([Parameter(Mandatory=$true)][object[]]$Items)
    $fingerprint = Get-AddonPolicyRegistryFingerprint
    [int]$registered=0; [int]$consistent=0; [int]$inconsistent=0
    foreach ($item in @($Items)) {
        $entry = Get-AddonPolicyRegistryEntry -Name ([string]$item.name) -Kind ([string]$item.kind)
        $isRegistered = $null -ne $entry
        $isConsistent = $false
        if ($isRegistered) {
            $registered++
            $isConsistent = ([string]$item.policy -ceq [string]$entry.inventory_policy) -and ([string]$item.source -ceq [string]$entry.source)
            if ($isConsistent) { $consistent++ } else { $inconsistent++ }
        }
        Set-ObjectNoteProperty -Object $item -Name 'registry_registered' -Value $isRegistered
        Set-ObjectNoteProperty -Object $item -Name 'registry_consistent' -Value $isConsistent
        Set-ObjectNoteProperty -Object $item -Name 'registry_sha256' -Value $fingerprint
        Set-ObjectNoteProperty -Object $item -Name 'registry_mutation_mode' -Value $(if($entry){[string]$entry.mutation_mode}else{$null})
        Set-ObjectNoteProperty -Object $item -Name 'registry_handler' -Value $(if($entry){[string]$entry.handler}else{$null})
        Set-ObjectNoteProperty -Object $item -Name 'registry_version_strategy' -Value $(if($entry){[string]$entry.version_strategy}else{$null})
        Set-ObjectNoteProperty -Object $item -Name 'registry_rollback_strategy' -Value $(if($entry){[string]$entry.rollback_strategy}else{$null})
        Set-ObjectNoteProperty -Object $item -Name 'registry_data_policy' -Value $(if($entry){[string]$entry.data_policy}else{$null})
    }
    return [pscustomobject]@{
        schema=1; sha256=$fingerprint; entry_count=@(Get-AddonPolicyRegistry).Count
        registered_inventory_count=$registered; consistent_inventory_count=$consistent; inconsistent_inventory_count=$inconsistent
        auto_names=@(Get-AddonPolicyRegistry | Where-Object { $_.mutation_mode -eq 'auto' } | Sort-Object -Property name | ForEach-Object { [string]$_.name })
    }
}

function Write-AddonPolicyRegistryReport {
    $path = Join-Path $ReportsRoot 'addon-policy-registry-latest.json'
    $report = [pscustomobject]@{
        generated_at=(Get-Date).ToString('o'); manager_version=$Version; schema=1
        sha256=(Get-AddonPolicyRegistryFingerprint); entries=@(Get-AddonPolicyRegistry | Sort-Object -Property kind,name)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $report
}

function Invoke-AddonPolicyRegistrySelfTest {
    $registry = @(Get-AddonPolicyRegistry)
    if ($registry.Count -ne 9) { throw "Addon policy registry entry count changed unexpectedly: $($registry.Count)" }
    $fingerprint = Get-AddonPolicyRegistryFingerprint
    if ($fingerprint -notmatch '^[0-9a-f]{64}$' -or $fingerprint -cne (Get-AddonPolicyRegistryFingerprint)) { throw 'Addon policy registry fingerprint is invalid or nondeterministic.' }
    $names=@($registry|ForEach-Object{[string]$_.name})
    if(@($names|Sort-Object -Unique).Count -ne $registry.Count){throw 'Addon policy registry contains duplicate names.'}

    $allowed = @(
        [pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$true;expected='ivlyrics'},
        [pscustomobject]@{name='better-local-files';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true;expected='pithaya'},
        [pscustomobject]@{name='eternal-jukebox';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true;expected='pithaya'},
        [pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';source='Pithaya/spicetify-apps-dist';installed=$true;expected='pithaya'}
    )
    foreach($item in $allowed){$a=Get-AddonMutationAuthorization -Item $item;if(-not $a.Allowed -or [string]$a.Handler -cne [string]$item.expected){throw "Registry denied accepted fixture $($item.name): $($a.Reason)"}}
    $notInstalled=[pscustomobject]@{name='ivLyrics';kind='custom-app';policy='auto';source='ivLis-Studio/ivLyrics';installed=$false}
    if((Get-AddonMutationAuthorization -Item $notInstalled).Allowed){throw 'Registry incorrectly authorized automatic installation of absent ivLyrics.'}
    $tampered=[pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';source='evil/example';installed=$true}
    if((Get-AddonMutationAuthorization -Item $tampered).Allowed){throw 'Registry incorrectly authorized a source-mismatched Pithaya item.'}
    foreach($item in @(
        [pscustomobject]@{name='tagify';kind='custom-app';policy='monitor-only';source='alexk218/tagify';installed=$true},
        [pscustomobject]@{name='splitify';kind='custom-app';policy='unknown-source';source=$null;installed=$true},
        [pscustomobject]@{name='star-ratings';kind='marketplace-extension';policy='source-watch-only';source='brimell/spicetify-star-ratings';installed=$true},
        [pscustomobject]@{name='sc-cover-ambience.js';kind='extension';policy='rescue-copy-cleanup-only';source='Theblockbuster1/spicetify-extensions';installed=$true},
        [pscustomobject]@{name='sc-star-ratings.js';kind='extension';policy='rescue-copy-cleanup-only';source='brimell/spicetify-star-ratings';installed=$true},
        [pscustomobject]@{name='unknown-addon';kind='custom-app';policy='auto';source='unknown/source';installed=$true}
    )){if((Get-AddonMutationAuthorization -Item $item).Allowed){throw "Registry incorrectly authorized denied fixture $($item.name)."}}

    $tag=Get-AddonPolicyRegistryEntry -Name 'tagify' -Kind 'custom-app'
    if([string]$tag.data_policy -cne 'protect-ratings-tags-notes' -or [string]$tag.mutation_mode -cne 'deny'){throw 'Tagify preservation policy changed.'}
    $cover=Get-AddonPolicyRegistryEntry -Name 'sc-cover-ambience.js' -Kind 'extension'
    if([string]$cover.data_policy -cne 'never-disable-or-optimize' -or [string]$cover.mutation_mode -cne 'deny'){throw 'SC Cover Ambience protection policy changed.'}
    $split=Get-AddonPolicyRegistryEntry -Name 'splitify' -Kind 'custom-app'
    if([string]$split.source -ne '' -or [string]$split.mutation_mode -cne 'deny'){throw 'Splitify unknown-source fail-closed policy changed.'}
}
# END SPOTIFY CONTROL ADDON POLICY REGISTRY v1 / r10
