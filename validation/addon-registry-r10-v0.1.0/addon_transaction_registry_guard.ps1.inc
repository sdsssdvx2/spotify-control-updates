# BEGIN SPOTIFY CONTROL ADDON TRANSACTION REGISTRY GUARD v1 / r10
function Assert-AddonTransactionRegistryAuthorization {
    param([Parameter(Mandatory=$true)]$Tx)
    if ($null -eq $Tx) { throw 'Addon transaction registry authorization received a null ledger.' }
    $registrySha = if ($Tx.PSObject.Properties['registry_sha256']) { [string]$Tx.registry_sha256 } else { $null }
    if ([string]::IsNullOrWhiteSpace($registrySha)) { return 'legacy-schema2-no-registry' }
    if (-not $Tx.PSObject.Properties['registry_schema'] -or [int]$Tx.registry_schema -ne 1) { throw "Addon transaction registry schema is unsupported: $($Tx.registry_schema)" }
    $currentRegistrySha = Get-AddonPolicyRegistryFingerprint
    if ($registrySha -cne $currentRegistrySha) { throw "Addon policy registry changed since transaction preparation; refusing commit. transaction=$registrySha current=$currentRegistrySha" }
    foreach ($change in @($Tx.changes)) {
        $entry = Get-AddonPolicyRegistryEntry -Name ([string]$change.name)
        if ($null -eq $entry) { throw "Addon policy registry no longer contains committed change $($change.name)." }
        if ([string]$entry.mutation_mode -cne 'auto') { throw "Addon policy registry no longer authorizes committed change $($change.name)." }
        if ($change.PSObject.Properties['registry_source'] -and [string]$change.registry_source -cne [string]$entry.source) { throw "Addon transaction source policy changed for $($change.name)." }
        if ($change.PSObject.Properties['registry_policy'] -and [string]$change.registry_policy -cne [string]$entry.inventory_policy) { throw "Addon transaction inventory policy changed for $($change.name)." }
        if ($change.PSObject.Properties['registry_handler'] -and [string]$change.registry_handler -cne [string]$entry.handler) { throw "Addon transaction handler policy changed for $($change.name)." }
    }
    return 'registry-v1-authorized'
}

function Invoke-AddonTransactionRegistrySelfTest {
    $legacy=[pscustomobject]@{schema=2;changes=@([pscustomobject]@{name='legacy-app'})}
    if((Assert-AddonTransactionRegistryAuthorization -Tx $legacy) -cne 'legacy-schema2-no-registry'){throw 'Legacy schema-2 registry compatibility fixture failed.'}

    $sha=Get-AddonPolicyRegistryFingerprint
    $current=[pscustomobject]@{
        schema=2;registry_schema=1;registry_sha256=$sha
        changes=@([pscustomobject]@{name='playlist-maker';registry_source='Pithaya/spicetify-apps-dist';registry_policy='auto';registry_handler='pithaya'})
    }
    if((Assert-AddonTransactionRegistryAuthorization -Tx $current) -cne 'registry-v1-authorized'){throw 'Current registry transaction fixture failed.'}

    $badSha=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=('0'*64);changes=$current.changes}
    $failed=$false;try{[void](Assert-AddonTransactionRegistryAuthorization -Tx $badSha)}catch{$failed=$true}
    if(-not $failed){throw 'Registry SHA drift fixture was incorrectly accepted.'}

    $badSource=[pscustomobject]@{
        schema=2;registry_schema=1;registry_sha256=$sha
        changes=@([pscustomobject]@{name='playlist-maker';registry_source='evil/source';registry_policy='auto';registry_handler='pithaya'})
    }
    $failed=$false;try{[void](Assert-AddonTransactionRegistryAuthorization -Tx $badSource)}catch{$failed=$true}
    if(-not $failed){throw 'Registry source drift fixture was incorrectly accepted.'}

    $denied=[pscustomobject]@{
        schema=2;registry_schema=1;registry_sha256=$sha
        changes=@([pscustomobject]@{name='tagify';registry_source='alexk218/tagify';registry_policy='monitor-only';registry_handler='none'})
    }
    $failed=$false;try{[void](Assert-AddonTransactionRegistryAuthorization -Tx $denied)}catch{$failed=$true}
    if(-not $failed){throw 'Registry denied-addon transaction fixture was incorrectly accepted.'}
}
# END SPOTIFY CONTROL ADDON TRANSACTION REGISTRY GUARD v1 / r10
