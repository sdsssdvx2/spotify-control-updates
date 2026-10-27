function New-MarketplaceInconclusiveReport {
    param([string]$Reason)
    return [pscustomobject]@{
        schema = 1
        collector_version = 'integrated-fail-closed'
        generated_utc = [DateTime]::UtcNow.ToString('o')
        read_only = $true
        mutation_performed = $false
        status = 'inconclusive'
        record_count = 0
        identity_fingerprint = $null
        records = @()
        profile_conflicts = @()
        profiles = @()
        derived = [pscustomobject]@{
            safe_to_expand_mutation_authority = $false
            next_decision = $Reason
        }
        integration_error = $Reason
    }
}

function Invoke-MarketplaceRecordDiscovery {
    param(
        [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
        [string]$OutputPath = (Join-Path $ReportsRoot 'marketplace-records-latest.json'),
        [string]$CollectorPath = (Join-Path $PSScriptRoot 'Collect-Marketplace-Records.ps1'),
        [string]$ReaderPath = (Join-Path $PSScriptRoot 'LevelDbReadOnly.cs')
    )
    if ([string]::IsNullOrWhiteSpace($LocalAppDataRoot)) {
        return New-MarketplaceInconclusiveReport 'localappdata-unavailable'
    }
    if (-not (Test-PathSafe $CollectorPath 'Leaf') -or -not (Test-PathSafe $ReaderPath 'Leaf')) {
        Write-AddonLog 'Marketplace identity collector payload is missing; Marketplace-dependent mutation remains denied.' 'WARN'
        return New-MarketplaceInconclusiveReport 'collector-payload-missing'
    }
    try {
        if (Test-PathSafe $OutputPath 'Leaf') { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction Stop }
        $started = [DateTimeOffset]::UtcNow
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CollectorPath -LocalAppDataRoot $LocalAppDataRoot -OutputPath $OutputPath -ReaderPath $ReaderPath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "collector-exit-$LASTEXITCODE" }
        if (-not (Test-PathSafe $OutputPath 'Leaf')) { throw 'collector-produced-no-report' }
        $report = Get-Content -LiteralPath $OutputPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $report) { throw 'collector-report-null' }
        if ($report.read_only -ne $true -or $report.mutation_performed -ne $false) { throw 'collector-read-only-contract-violation' }
        $generated = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$report.generated_utc,[ref]$generated)) { throw 'collector-generated-time-invalid' }
        if ($generated -lt $started.AddMinutes(-1) -or $generated -gt [DateTimeOffset]::UtcNow.AddMinutes(1)) { throw 'collector-report-not-current' }
        return $report
    } catch {
        $reason = 'collector-failed:' + [string]$_.Exception.Message
        Write-AddonLog ("Marketplace identity discovery failed closed; Marketplace-dependent mutation remains denied: {0}" -f $reason) 'WARN'
        return New-MarketplaceInconclusiveReport $reason
    }
}

function Update-MarketplaceIdentityLifecycleFromReport {
    param(
        $State,
        $MarketplaceReport,
        [string]$ObservedAt = ([DateTimeOffset]::UtcNow.ToString('o')),
        [string[]]$TransactionOwnedAbsenceKeys = @()
    )
    try {
        return Update-MarketplaceIdentityLifecycleLedger -State $State -MarketplaceReport $MarketplaceReport -ObservedAt $ObservedAt -TransactionOwnedAbsenceKeys $TransactionOwnedAbsenceKeys
    } catch {
        $reason = 'marketplace-ledger-failed:' + [string]$_.Exception.Message
        Write-AddonLog ("Marketplace identity lifecycle update failed closed; prior state was not partially accepted: {0}" -f $reason) 'WARN'
        return [pscustomobject]@{
            schema = 1
            conclusive = $false
            state_changed = $false
            observed_at = $ObservedAt
            present_count = 0
            new_count = 0
            removed_count = 0
            reinstalled_count = 0
            transaction_absence_count = 0
            reason = $reason
        }
    }
}

function Test-MarketplaceSourceUserIntentAllowsMutation {
    param($State,$Item)
    if ($null -eq $Item) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-item-null'; LedgerKey=$null }
    }
    if (-not $Item.PSObject.Properties['marketplace_identity_required'] -or -not [bool]$Item.marketplace_identity_required) {
        return [pscustomobject]@{ Applicable=$false; Allowed=$true; Reason='not-required'; LedgerKey=$null }
    }
    if (-not $Item.PSObject.Properties['marketplace_identity_evidence_conclusive'] -or -not [bool]$Item.marketplace_identity_evidence_conclusive) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-evidence-inconclusive'; LedgerKey=$null }
    }
    $currentFingerprint = if ($Item.PSObject.Properties['marketplace_identity_fingerprint']) { ([string]$Item.marketplace_identity_fingerprint).Trim().ToLowerInvariant() } else { '' }
    if ($currentFingerprint -notmatch '^[0-9a-f]{64}$') {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-current-fingerprint-invalid'; LedgerKey=$null }
    }
    $source = ([string]$Item.source).Trim()
    $parts = @($source -split '/')
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-source-identity-invalid'; LedgerKey=$null }
    }
    $State = Ensure-MarketplaceIdentityLedgerState $State
    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($prop in @($State.lifecycle.PSObject.Properties)) {
        $row = $prop.Value
        if ($null -eq $row) { continue }
        if ([string]$row.managed_by -cne 'marketplace-record-v1') { continue }
        if ([string]$row.source_kind -cne 'github-repository-key') { continue }
        if (-not ([string]$row.github_owner).Equals([string]$parts[0],[StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not ([string]$row.github_repo).Equals([string]$parts[1],[StringComparison]::OrdinalIgnoreCase)) { continue }
        $matches.Add([pscustomobject]@{ Key=[string]$prop.Name; Row=$row })
    }
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-identity-missing'; LedgerKey=$null }
    }
    if ($matches.Count -ne 1) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-source-ambiguous'; LedgerKey=$null }
    }
    $match = $matches[0]
    $row = $match.Row
    if ([string]$row.mutation_mode -cne 'deny') {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-ledger-authority-drift'; LedgerKey=[string]$match.Key }
    }
    if (-not [bool]$row.present) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-not-present'; LedgerKey=[string]$match.Key }
    }
    if ([bool]$row.user_removed) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-user-removed'; LedgerKey=[string]$match.Key }
    }
    if ([bool]$row.ambiguous) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-row-ambiguous'; LedgerKey=[string]$match.Key }
    }
    if (([string]$row.last_report_fingerprint).Trim().ToLowerInvariant() -cne $currentFingerprint) {
        return [pscustomobject]@{ Applicable=$true; Allowed=$false; Reason='marketplace-evidence-stale'; LedgerKey=[string]$match.Key }
    }
    return [pscustomobject]@{ Applicable=$true; Allowed=$true; Reason='current-marketplace-user-intent-confirmed'; LedgerKey=[string]$match.Key }
}

function Invoke-MarketplaceIntegratedEngineSelfTest {
    $fpA = ('a' * 64); $fpB = ('b' * 64); $fpC = ('c' * 64); $fpD = ('d' * 64); $fpE = ('e' * 64); $fpF = ('f' * 64)
    $newRecord = {
        param([string]$Artifact)
        [pscustomobject]@{
            key=('marketplace:installed:alexk218/tagify/' + $Artifact)
            kind='extension'; source_kind='github-repository-key'; github_owner='alexk218'; github_repo='tagify'
            artifact_path=$Artifact; repository_url='https://github.com/alexk218/tagify'; profiles=@('Browser')
            mutation_authorized=$false
        }
    }
    $newReport = {
        param([object[]]$Records,[string]$Fingerprint)
        [pscustomobject]@{
            schema=1; read_only=$true; mutation_performed=$false; status='ok'; record_count=@($Records).Count
            identity_fingerprint=$Fingerprint; records=@($Records); profile_conflicts=@()
            derived=[pscustomobject]@{safe_to_expand_mutation_authority=$false}
        }
    }
    $newItem = {
        param([bool]$Conclusive,[string]$Fingerprint)
        [pscustomobject]@{
            name='tagify';kind='custom-app';policy='auto';installed=$true;source='alexk218/tagify'
            marketplace_identity_required=$true;marketplace_identity_evidence_conclusive=$Conclusive;marketplace_identity_fingerprint=$Fingerprint
        }
    }

    $state=[pscustomobject]@{}
    $records1=@(& $newRecord 'manifest.json')
    $r1=& $newReport $records1 $fpA
    $s1=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport $r1 -ObservedAt '2026-10-28T00:00:00+00:00'
    if(-not [bool]$s1.conclusive){throw 'Integrated Marketplace self-test: initial report was not conclusive.'}
    $g1=Test-MarketplaceSourceUserIntentAllowsMutation -State $state -Item (& $newItem $true $fpA)
    if(-not [bool]$g1.Allowed -or [string]$g1.Reason -cne 'current-marketplace-user-intent-confirmed'){throw 'Integrated Marketplace self-test: current Tagify identity was not allowed.'}

    $g2=Test-MarketplaceSourceUserIntentAllowsMutation -State $state -Item (& $newItem $false $fpA)
    if([bool]$g2.Allowed -or [string]$g2.Reason -cne 'marketplace-evidence-inconclusive'){throw 'Integrated Marketplace self-test: inconclusive current evidence was not denied.'}
    $g3=Test-MarketplaceSourceUserIntentAllowsMutation -State $state -Item (& $newItem $true $fpB)
    if([bool]$g3.Allowed -or [string]$g3.Reason -cne 'marketplace-evidence-stale'){throw 'Integrated Marketplace self-test: fingerprint drift was not denied.'}

    $emptyRecords=@()
    $empty=& $newReport $emptyRecords $fpB
    $s2=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport $empty -ObservedAt '2026-10-28T00:01:00+00:00'
    if([int]$s2.removed_count -ne 1){throw 'Integrated Marketplace self-test: user removal tombstone was not created.'}
    $g4=Test-MarketplaceSourceUserIntentAllowsMutation -State $state -Item (& $newItem $true $fpB)
    if([bool]$g4.Allowed -or [string]$g4.Reason -notin @('marketplace-not-present','marketplace-user-removed')){throw 'Integrated Marketplace self-test: deleted Tagify identity was not denied.'}

    $records3=@(& $newRecord 'manifest.json')
    $r3=& $newReport $records3 $fpC
    $s3=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport $r3 -ObservedAt '2026-10-28T00:02:00+00:00'
    if([int]$s3.reinstalled_count -ne 1){throw 'Integrated Marketplace self-test: explicit reinstall was not recognized.'}
    $g5=Test-MarketplaceSourceUserIntentAllowsMutation -State $state -Item (& $newItem $true $fpC)
    if(-not [bool]$g5.Allowed){throw 'Integrated Marketplace self-test: explicit reinstall did not restore current user-intent gate.'}

    $state2=[pscustomobject]@{}
    $records4=@(& $newRecord 'manifest.json')
    $r4=& $newReport $records4 $fpD
    [void](Update-MarketplaceIdentityLifecycleLedger -State $state2 -MarketplaceReport $r4 -ObservedAt '2026-10-28T00:03:00+00:00')
    $ownedKey='marketplace:installed:alexk218/tagify/manifest.json'
    $empty2=& $newReport $emptyRecords $fpE
    $s4=Update-MarketplaceIdentityLifecycleLedger -State $state2 -MarketplaceReport $empty2 -ObservedAt '2026-10-28T00:04:00+00:00' -TransactionOwnedAbsenceKeys @($ownedKey)
    if([int]$s4.transaction_absence_count -ne 1){throw 'Integrated Marketplace self-test: transaction-owned absence was not distinguished.'}
    $g6=Test-MarketplaceSourceUserIntentAllowsMutation -State $state2 -Item (& $newItem $true $fpE)
    if([bool]$g6.Allowed -or [string]$g6.Reason -cne 'marketplace-not-present'){throw 'Integrated Marketplace self-test: transaction-owned temporary absence became mutable.'}

    $state3=[pscustomobject]@{}
    $multiRecords=@((& $newRecord 'one.js'),(& $newRecord 'two.js'))
    $multi=& $newReport $multiRecords $fpF
    [void](Update-MarketplaceIdentityLifecycleLedger -State $state3 -MarketplaceReport $multi -ObservedAt '2026-10-28T00:05:00+00:00')
    $g7=Test-MarketplaceSourceUserIntentAllowsMutation -State $state3 -Item (& $newItem $true $fpF)
    if([bool]$g7.Allowed -or [string]$g7.Reason -cne 'marketplace-source-ambiguous'){throw 'Integrated Marketplace self-test: multiple records for one source were not denied.'}
    foreach($prop in @($state3.lifecycle.PSObject.Properties)){
        if([string]$prop.Value.managed_by -ceq 'marketplace-record-v1' -and [string]$prop.Value.mutation_mode -cne 'deny'){throw 'Integrated Marketplace self-test: generic Marketplace ledger gained mutation authority.'}
    }

    $plain=[pscustomobject]@{name='playlist-maker';kind='custom-app';policy='auto';installed=$true;source='Pithaya/spicetify-apps-dist'}
    $g8=Test-MarketplaceSourceUserIntentAllowsMutation -State $state3 -Item $plain
    if(-not [bool]$g8.Allowed -or [bool]$g8.Applicable){throw 'Integrated Marketplace self-test: unrelated managed app was unexpectedly gated.'}

    Write-AddonLog 'Marketplace integrated engine self-test passed: current-evidence gate, deletion tombstone, reinstall, transaction absence, stale fingerprint, ambiguity, and generic deny semantics.'
}
