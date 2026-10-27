function Ensure-LedgerProperty {
    param($Object,[string]$Name,$DefaultValue)
    if ($null -eq $Object) { throw 'Ledger object cannot be null.' }
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Set-LedgerProperty {
    param($Object,[string]$Name,$Value)
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
}

function Ensure-MarketplaceIdentityLedgerState {
    param($State)
    if ($null -eq $State) { $State = [pscustomobject]@{} }
    [void](Ensure-LedgerProperty -Object $State -Name 'lifecycle' -DefaultValue ([pscustomobject]@{}))
    if ($null -eq $State.lifecycle) { Set-LedgerProperty -Object $State -Name 'lifecycle' -Value ([pscustomobject]@{}) }
    return $State
}

function Get-MarketplaceIdentityLedgerKey {
    param([string]$MarketplaceKey)
    if ([string]::IsNullOrWhiteSpace($MarketplaceKey)) { throw 'Marketplace key cannot be empty.' }
    $normalized = $MarketplaceKey.Trim().ToLowerInvariant()
    if (-not $normalized.StartsWith('marketplace:installed:', [StringComparison]::Ordinal)) {
        throw "Unsupported Marketplace key: $MarketplaceKey"
    }
    return ('marketplace-record:' + $normalized)
}

function Normalize-MarketplaceIdentityRecord {
    param($Record)
    if ($null -eq $Record) { throw 'Marketplace record cannot be null.' }
    $key = [string]$Record.key
    $ledgerKey = Get-MarketplaceIdentityLedgerKey -MarketplaceKey $key
    $kind = ([string]$Record.kind).Trim().ToLowerInvariant()
    if ($kind -notin @('extension','theme','snippet','unlisted')) { throw "Unsupported Marketplace record kind: $kind" }
    if ([bool]$Record.mutation_authorized) { throw "Input Marketplace record unexpectedly authorizes mutation: $key" }

    $sourceKind = ([string]$Record.source_kind).Trim().ToLowerInvariant()
    $owner = $null; $repo = $null; $artifact = ([string]$Record.artifact_path).Trim()
    $repoUrl = $null; $sourceIdentity = $null
    if ($sourceKind -ceq 'github-repository-key') {
        $owner = ([string]$Record.github_owner).Trim()
        $repo = ([string]$Record.github_repo).Trim()
        if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo) -or [string]::IsNullOrWhiteSpace($artifact)) {
            throw "Incomplete GitHub Marketplace identity: $key"
        }
        $expected = ('marketplace:installed:{0}/{1}/{2}' -f $owner,$repo,$artifact)
        if (-not $key.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Marketplace key/source identity mismatch: $key != $expected"
        }
        $repoUrl = ('https://github.com/{0}/{1}' -f $owner,$repo)
        if ($Record.PSObject.Properties['repository_url'] -and -not [string]::IsNullOrWhiteSpace([string]$Record.repository_url)) {
            if (-not ([string]$Record.repository_url).Trim().Equals($repoUrl,[StringComparison]::OrdinalIgnoreCase)) {
                throw "Marketplace repository URL mismatch: $key"
            }
        }
        $sourceIdentity = ('github:{0}/{1}:{2}' -f $owner.ToLowerInvariant(),$repo.ToLowerInvariant(),$artifact.Replace('\\','/').ToLowerInvariant())
    } elseif ($sourceKind -ceq 'snippet-key') {
        if ($kind -cne 'snippet' -or [string]::IsNullOrWhiteSpace($artifact)) { throw "Invalid snippet Marketplace identity: $key" }
        $expected = 'marketplace:installed:snippet:' + $artifact
        if (-not $key.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { throw "Marketplace snippet key mismatch: $key != $expected" }
        $sourceIdentity = ('snippet:' + $artifact.ToLowerInvariant())
    } else {
        throw "Unsupported Marketplace source identity kind: $sourceKind"
    }

    $profiles = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Record.profiles)) {
        $name = ([string]$p).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -notin @('Browser','Default')) { throw "Unexpected Marketplace profile: $name" }
        if (-not $profiles.Contains($name)) { $profiles.Add($name) }
    }
    if ($profiles.Count -eq 0) { throw "Marketplace record has no profile evidence: $key" }
    $profileArray = @($profiles.ToArray() | Sort-Object)

    return [pscustomobject]@{
        ledger_key = $ledgerKey
        marketplace_key = $key.Trim()
        kind = $kind
        source_kind = $sourceKind
        github_owner = $owner
        github_repo = $repo
        artifact_path = $artifact
        repository_url = $repoUrl
        source_identity = $sourceIdentity
        profiles = $profileArray
    }
}

function Ensure-MarketplaceIdentityLedgerRow {
    param($State,[string]$LedgerKey)
    $State = Ensure-MarketplaceIdentityLedgerState $State
    if ([string]::IsNullOrWhiteSpace($LedgerKey)) { throw 'Marketplace ledger key cannot be empty.' }
    if (-not $State.lifecycle.PSObject.Properties[$LedgerKey]) {
        $State.lifecycle | Add-Member -NotePropertyName $LedgerKey -NotePropertyValue ([pscustomobject]@{})
    }
    $row = $State.lifecycle.PSObject.Properties[$LedgerKey].Value
    if ($null -eq $row) { $row=[pscustomobject]@{}; $State.lifecycle.PSObject.Properties[$LedgerKey].Value=$row }
    foreach ($pair in @(
        @('key',$LedgerKey),@('managed_by','marketplace-record-v1'),@('marketplace_key',$null),@('kind',$null),
        @('source_kind',$null),@('source_identity',$null),@('github_owner',$null),@('github_repo',$null),
        @('artifact_path',$null),@('repository_url',$null),@('profiles',@()),@('present',$false),
        @('first_seen',$null),@('last_seen',$null),@('last_absent',$null),@('user_removed',$false),
        @('removed_at',$null),@('reinstalled_at',$null),@('mutation_mode','deny'),@('ambiguous',$false),
        @('last_report_fingerprint',$null)
    )) { [void](Ensure-LedgerProperty -Object $row -Name ([string]$pair[0]) -DefaultValue $pair[1]) }
    if ([string]$row.managed_by -cne 'marketplace-record-v1') { throw "Marketplace lifecycle key collides with another owner: $LedgerKey" }
    return $row
}

function Update-MarketplaceIdentityLifecycleLedger {
    param(
        $State,
        $MarketplaceReport,
        [string]$ObservedAt=([DateTimeOffset]::UtcNow.ToString('o')),
        [string[]]$TransactionOwnedAbsenceKeys=@()
    )
    $State = Ensure-MarketplaceIdentityLedgerState $State
    if ($null -eq $MarketplaceReport) { throw 'Marketplace report cannot be null.' }
    if ($MarketplaceReport.read_only -ne $true -or $MarketplaceReport.mutation_performed -ne $false) {
        throw 'Marketplace report does not satisfy the read-only evidence contract.'
    }
    if ($MarketplaceReport.PSObject.Properties['derived'] -and $MarketplaceReport.derived.PSObject.Properties['safe_to_expand_mutation_authority']) {
        if ($MarketplaceReport.derived.safe_to_expand_mutation_authority -ne $false) {
            throw 'Marketplace report unexpectedly claims mutation authority may expand.'
        }
    }
    if ([string]$MarketplaceReport.status -cne 'ok') {
        return [pscustomobject]@{ schema=1; conclusive=$false; state_changed=$false; observed_at=$ObservedAt; present_count=0; new_count=0; removed_count=0; reinstalled_count=0; transaction_absence_count=0; reason=('marketplace-report-' + [string]$MarketplaceReport.status) }
    }
    if (@($MarketplaceReport.profile_conflicts).Count -gt 0) {
        return [pscustomobject]@{ schema=1; conclusive=$false; state_changed=$false; observed_at=$ObservedAt; present_count=0; new_count=0; removed_count=0; reinstalled_count=0; transaction_absence_count=0; reason='marketplace-profile-conflict' }
    }
    $reportFingerprint = ([string]$MarketplaceReport.identity_fingerprint).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($reportFingerprint) -or $reportFingerprint -notmatch '^[0-9a-f]{64}$') {
        throw 'Conclusive Marketplace report is missing a valid identity fingerprint.'
    }

    # Validate and normalize the complete report before touching lifecycle state.
    $normalized = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($record in @($MarketplaceReport.records)) {
        $n = Normalize-MarketplaceIdentityRecord -Record $record
        if ($seen.ContainsKey([string]$n.ledger_key)) { throw "Duplicate Marketplace identity in report: $($n.marketplace_key)" }
        $seen[[string]$n.ledger_key] = $true
        $normalized.Add($n)
    }
    if ([int]$MarketplaceReport.record_count -ne $normalized.Count) {
        throw "Marketplace report count mismatch: reported=$($MarketplaceReport.record_count) normalized=$($normalized.Count)"
    }

    # Validate existing rows that will be touched before mutating any state.
    foreach ($n in @($normalized.ToArray())) {
        if ($State.lifecycle.PSObject.Properties[[string]$n.ledger_key]) {
            $existing = $State.lifecycle.PSObject.Properties[[string]$n.ledger_key].Value
            if ($null -eq $existing -or [string]$existing.managed_by -cne 'marketplace-record-v1') { throw "Marketplace ledger owner collision: $($n.ledger_key)" }
            if ($existing.PSObject.Properties['source_identity'] -and -not [string]::IsNullOrWhiteSpace([string]$existing.source_identity)) {
                if ([string]$existing.source_identity -cne [string]$n.source_identity) { throw "Marketplace source identity drift for stable key: $($n.marketplace_key)" }
            }
        }
    }

    $owned = @{}
    foreach ($raw in @($TransactionOwnedAbsenceKeys)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $k = if ($raw.Trim().ToLowerInvariant().StartsWith('marketplace-record:')) { $raw.Trim().ToLowerInvariant() } else { Get-MarketplaceIdentityLedgerKey -MarketplaceKey $raw }
        $owned[$k] = $true
    }

    $newCount=0; $removedCount=0; $reinstalledCount=0; $transactionAbsenceCount=0; $stateChanged=$false
    foreach ($n in @($normalized.ToArray())) {
        $isNew = (-not $State.lifecycle.PSObject.Properties[[string]$n.ledger_key])
        $row = Ensure-MarketplaceIdentityLedgerRow -State $State -LedgerKey ([string]$n.ledger_key)
        if ($isNew) { $newCount++; $stateChanged=$true }
        $wasRemoved=[bool]$row.user_removed; $wasPresent=[bool]$row.present
        $row.marketplace_key=[string]$n.marketplace_key; $row.kind=[string]$n.kind; $row.source_kind=[string]$n.source_kind
        $row.source_identity=[string]$n.source_identity; $row.github_owner=$n.github_owner; $row.github_repo=$n.github_repo
        $row.artifact_path=[string]$n.artifact_path; $row.repository_url=$n.repository_url; $row.profiles=@($n.profiles)
        $row.present=$true; if (-not $row.first_seen) { $row.first_seen=$ObservedAt }; $row.last_seen=$ObservedAt
        $row.mutation_mode='deny'; $row.ambiguous=$false; $row.last_report_fingerprint=$reportFingerprint
        if (-not $wasPresent) { $stateChanged=$true }
        if ($wasRemoved) { $row.user_removed=$false; $row.reinstalled_at=$ObservedAt; $reinstalledCount++; $stateChanged=$true }
    }

    foreach ($prop in @($State.lifecycle.PSObject.Properties)) {
        $ledgerKey=[string]$prop.Name; $row=$prop.Value
        if ($null -eq $row -or [string]$row.managed_by -cne 'marketplace-record-v1' -or $seen.ContainsKey($ledgerKey)) { continue }
        if ([bool]$row.present) {
            $row.present=$false; $row.last_absent=$ObservedAt; $row.last_report_fingerprint=$reportFingerprint; $stateChanged=$true
            if ($owned.ContainsKey($ledgerKey.ToLowerInvariant())) {
                $transactionAbsenceCount++
            } else {
                $row.user_removed=$true; $row.removed_at=$ObservedAt; $removedCount++
            }
        }
    }

    return [pscustomobject]@{
        schema=1; conclusive=$true; state_changed=$stateChanged; observed_at=$ObservedAt; present_count=$normalized.Count;
        new_count=$newCount; removed_count=$removedCount; reinstalled_count=$reinstalledCount;
        transaction_absence_count=$transactionAbsenceCount; reason='ok'; report_fingerprint=$reportFingerprint
    }
}

function Test-MarketplaceIdentityMutationAllowed {
    param($State,[string]$MarketplaceKey)
    $State = Ensure-MarketplaceIdentityLedgerState $State
    $ledgerKey = Get-MarketplaceIdentityLedgerKey -MarketplaceKey $MarketplaceKey
    if (-not $State.lifecycle.PSObject.Properties[$ledgerKey]) { return $false }
    $row = Ensure-MarketplaceIdentityLedgerRow -State $State -LedgerKey $ledgerKey
    return ([bool]$row.present -and -not [bool]$row.user_removed -and -not [bool]$row.ambiguous -and [string]$row.mutation_mode -ceq 'auto')
}
