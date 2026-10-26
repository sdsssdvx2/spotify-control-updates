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

function Invoke-AddonRegistryCommitCycleSelfTest {
    $fixtureRoot=$null
    $saved=[ordered]@{
        Root=$script:Root; LogDir=$script:LogDir; StatePath=$script:StatePath; TransactionPath=$script:TransactionPath
        ReportsRoot=$script:ReportsRoot; LatestReport=$script:LatestReport; PithayaTransactionReport=$script:PithayaTransactionReport
        LogPath=$script:LogPath
    }
    try {
        $fixtureRoot=Join-Path $env:TEMP ("SpotifyControl-RegistryCommitSelfTest-"+[guid]::NewGuid().ToString('N'))
        $script:Root=$fixtureRoot
        $script:LogDir=Join-Path $fixtureRoot 'logs'
        $script:StatePath=Join-Path $fixtureRoot 'addons-state.json'
        $script:TransactionPath=Join-Path $fixtureRoot 'addon-last-transaction.json'
        $script:ReportsRoot=Join-Path $fixtureRoot 'reports'
        $script:LatestReport=Join-Path $script:ReportsRoot 'addons-latest.json'
        $script:PithayaTransactionReport=Join-Path $script:ReportsRoot 'pithaya-transaction-latest.json'
        $script:LogPath=Join-Path $script:LogDir 'addons-registry-selftest.log'
        New-Item -ItemType Directory -Force -Path $script:Root,$script:LogDir,$script:ReportsRoot|Out-Null

        $target=Join-Path $fixtureRoot 'playlist-maker'
        New-Item -ItemType Directory -Force -Path $target|Out-Null
        Set-Content -LiteralPath (Join-Path $target 'manifest.json') -Value '{"name":"playlist-maker"}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $target 'index.js') -Value 'after-registry' -Encoding UTF8
        $after=Get-DirectoryGitSnapshot $target

        $state=Load-AddonState
        $app=Ensure-AppState $state 'playlist-maker'
        $app.source='Pithaya/spicetify-apps-dist'
        $app.installed_revision='before-registry-revision'
        $app.installed_fingerprint='before-registry-fingerprint'
        $app.last_status='update-available'
        Save-AddonState $state

        $latest=[pscustomobject]@{
            generated_at=(Get-Date).ToString('o');manager_version=$Version
            items=@([pscustomobject]@{
                name='playlist-maker';kind='custom-app';policy='auto';installed=$true
                local='different';remote='dist/playlist-maker';revision='after-registry-revision';status='update-available'
                source='Pithaya/spicetify-apps-dist';local_safety='trusted-baseline'
                local_fingerprint='before-registry-fingerprint';installed_revision='before-registry-revision';installed_fingerprint='before-registry-fingerprint'
            })
        }
        $latest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $script:LatestReport -Encoding UTF8
        if((Get-DiscoveredActionableAutoUpdateCount -Report $latest) -ne 1){throw 'Registry commit-cycle precondition was not actionable pending.'}

        $registrySha=Get-AddonPolicyRegistryFingerprint
        $tx=[pscustomobject]@{
            schema=2;registry_schema=1;registry_sha256=$registrySha;id='registry-commit-cycle-fixture';created_at=(Get-Date).ToString('o');status='awaiting-apply';committed=$false
            swapped_at=(Get-Date).ToString('o');rolled_back_at=$null;committed_at=$null
            changes=@([pscustomobject]@{
                name='playlist-maker';target=$target;backup=(Join-Path $fixtureRoot 'unused-backup')
                before_fingerprint='before-registry-fingerprint';before_revision='before-registry-revision'
                after_revision='after-registry-revision';after_fingerprint=[string]$after.fingerprint
                remote_tree='registry-fixture-tree';archive_sha256='registry-fixture-archive';swapped=$true
                registry_handler='pithaya';registry_source='Pithaya/spicetify-apps-dist';registry_policy='auto'
            })
        }
        if((Assert-AddonTransactionRegistryAuthorization -Tx $tx) -cne 'registry-v1-authorized'){throw 'Registry commit-cycle ledger was not authorized before CommitLast.'}
        Write-TransactionLedger $tx
        Commit-LastTransaction

        if(Test-PathSafe $script:TransactionPath 'Leaf'){throw 'Registry commit-cycle fixture left an active transaction ledger.'}
        $committedState=Load-AddonState
        $committedApp=Ensure-AppState $committedState 'playlist-maker'
        if([string]$committedApp.installed_revision -cne 'after-registry-revision'){throw 'Registry commit-cycle did not persist the committed revision.'}
        if([string]$committedApp.installed_fingerprint -cne [string]$after.fingerprint){throw 'Registry commit-cycle did not persist the committed fingerprint.'}

        $post=Get-Content -LiteralPath $script:LatestReport -Raw|ConvertFrom-Json
        $row=@($post.items|Where-Object{$_.name -eq 'playlist-maker'}|Select-Object -First 1)
        if($row.Count -ne 1 -or [string]$row[0].status -cne 'current' -or [string]$row[0].local_safety -cne 'exact-current'){throw 'Registry commit-cycle did not refresh the inventory row to current.'}
        if((Get-DiscoveredActionableAutoUpdateCount -Report $post) -ne 0){throw 'Registry commit-cycle remained actionable after CommitLast.'}
        $archives=@(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'transactions') -Filter '*-committed-registry-commit-cycle-fixture.json' -File -ErrorAction SilentlyContinue)
        if($archives.Count -ne 1){throw 'Registry commit-cycle did not archive exactly one committed ledger.'}
        $txReport=Get-Content -LiteralPath $script:PithayaTransactionReport -Raw|ConvertFrom-Json
        if([string]$txReport.status -cne 'committed' -or $txReport.committed -ne $true){throw 'Registry commit-cycle transaction report is not terminal committed.'}
        if([string]$txReport.registry_sha256 -cne $registrySha -or [int]$txReport.registry_schema -ne 1){throw 'Registry commit-cycle terminal report lost registry provenance.'}
    } finally {
        $script:Root=$saved.Root;$script:LogDir=$saved.LogDir;$script:StatePath=$saved.StatePath;$script:TransactionPath=$saved.TransactionPath
        $script:ReportsRoot=$saved.ReportsRoot;$script:LatestReport=$saved.LatestReport;$script:PithayaTransactionReport=$saved.PithayaTransactionReport
        $script:LogPath=$saved.LogPath
        if($fixtureRoot -and (Test-Path -LiteralPath $fixtureRoot -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
# END SPOTIFY CONTROL ADDON TRANSACTION REGISTRY GUARD v1 / r10
