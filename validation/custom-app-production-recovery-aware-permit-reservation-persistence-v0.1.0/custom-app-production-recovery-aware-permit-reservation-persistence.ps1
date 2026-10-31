$CustomAppProductionRecoveryAwarePermitReservationPersistenceSchema = 1
$CustomAppProductionRecoveryAwarePermitReservationPersistenceManagedBy = 'custom-app-production-recovery-aware-permit-reservation-persistence-v1'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationHead = '7419213070d7c01316f9746697c6bf06125c9a32'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationCoreBlob = '7c29b51da88c49c87046ceaf0751819116be912a'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionHead = 'bef6688559ab6b13be02f316464afb6f3b720e67'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionCoreBlob = 'b8a3f9e2fcbb3d59cd10f92e988cc435e9cea660'
$CustomAppProductionRecoveryAwarePermitReservationPersistenceZeroHash = ('0' * 64)

function Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()) }
    finally { $sha.Dispose() }
}

function Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if ($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)) { return $AllowRoot }
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-CustomAppProductionRecoveryAwarePermitReservationPersistencePathV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='path',[bool]$RequireExisting=$true)
    $r = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceWithinV010 -Root $r -Path $p)) { throw "$Label escaped allowed root" }
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { throw "$Label allowed root missing" }
    $rootItem = Get-Item -LiteralPath $r -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label allowed root is reparse point" }
    $probe = $p
    while (-not $probe.Equals($r,[StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label contains reparse point" }
        }
        $parent = [IO.Directory]::GetParent($probe)
        if ($null -eq $parent) { throw "$Label parent escaped allowed root" }
        $probe = $parent.FullName
        if (-not ($probe.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $probe.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))) { throw "$Label parent escaped allowed root" }
    }
    if ($RequireExisting -and -not (Test-Path -LiteralPath $p)) { throw "$Label missing" }
    return $p
}

function Get-CustomAppProductionRecoveryAwarePermitReservationPersistencePathsV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory)
    $store = Assert-CustomAppProductionRecoveryAwarePermitReservationPersistencePathV010 -AllowedRoot $AllowedRoot -Path $PersistenceStoreDirectory -Label 'reservation persistence store'
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { throw 'reservation persistence store is not directory' }
    $history = Assert-CustomAppProductionRecoveryAwarePermitReservationPersistencePathV010 -AllowedRoot $AllowedRoot -Path (Join-Path $store 'history') -Label 'reservation persistence history'
    if (-not (Test-Path -LiteralPath $history -PathType Container)) { throw 'reservation persistence history is not directory' }
    return [pscustomobject]@{allowed_root=[IO.Path]::GetFullPath($AllowedRoot);store=$store;history=$history;current=(Join-Path $store 'current.json');lock=(Join-Path $store '.reservation-persistence.lock')}
}

function Open-CustomAppProductionRecoveryAwarePermitReservationPersistenceLockV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    try { return [IO.File]::Open([string]$Paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch [IO.IOException] { throw 'reservation-persistence-lock-busy' }
}

function Write-CustomAppProductionRecoveryAwarePermitReservationDurableFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][IO.FileMode]$Mode)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = $null
    try { $stream=[IO.File]::Open($Path,$Mode,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 {
    param([Parameter(Mandatory=$true)]$State)
    return ($State | ConvertTo-Json -Depth 60 -Compress)
}

function Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_reservation_head,[string]$Envelope.qualified_reservation_core_blob,
        [string]$Envelope.qualified_admission_head,[string]$Envelope.qualified_admission_core_blob,[string]$Envelope.revision,[string]$Envelope.state_sha256,
        [string]$Envelope.previous_envelope_sha256,[string]$Envelope.reservation_id,[string]$Envelope.reservation_fingerprint,[string]$Envelope.persistence_admission_fingerprint,
        [string]$Envelope.written_at,[string]$Envelope.append_only,[string]$Envelope.reservation_persisted,[string]$Envelope.nonce_durably_reserved,[string]$Envelope.permit_durably_reserved,
        [string]$Envelope.session_key_persisted,[string]$Envelope.session_key_exposed,[string]$Envelope.permit_consumed,[string]$Envelope.requires_single_use_consumption,
        [string]$Envelope.requires_fresh_admission_revalidation_on_consume,[string]$Envelope.requires_persisted_consumption_before_executor,[string]$Envelope.persistence_is_authority,
        [string]$Envelope.executor_may_start,[string]$Envelope.production_execution_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 {
    param(
        [Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)][string]$PreviousEnvelopeSha256,
        [Parameter(Mandatory=$true)][string]$ReservationId,[Parameter(Mandatory=$true)][string]$ReservationFingerprint,
        [Parameter(Mandatory=$true)][string]$PersistenceAdmissionFingerprint,[DateTimeOffset]$WrittenAt=[DateTimeOffset]::UtcNow
    )
    $stateCheck = Test-CustomAppProductionPermitReservationStateV010 -State $State
    if (-not [bool]$stateCheck.ok) { throw ('cannot persist invalid reservation state: '+[string]$stateCheck.reason) }
    if ([int64]$stateCheck.revision -le 0) { throw 'cannot persist empty reservation state' }
    foreach ($v in @($PreviousEnvelopeSha256,$ReservationId,$ReservationFingerprint,$PersistenceAdmissionFingerprint)) {
        if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 $v)) { throw 'reservation persistence hash material invalid' }
    }
    $last = @($State.reservations)[-1]
    if (([string]$last.reservation_id).Trim().ToLowerInvariant() -cne $ReservationId.Trim().ToLowerInvariant()) { throw 'reservation persistence last reservation mismatch' }
    $e = [pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitReservationPersistenceSchema;managed_by=$CustomAppProductionRecoveryAwarePermitReservationPersistenceManagedBy
        qualified_reservation_head=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationHead;qualified_reservation_core_blob=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationCoreBlob
        qualified_admission_head=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionHead;qualified_admission_core_blob=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionCoreBlob
        revision=[int64]$State.revision;state_sha256=(Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $State))
        previous_envelope_sha256=$PreviousEnvelopeSha256.Trim().ToLowerInvariant();reservation_id=$ReservationId.Trim().ToLowerInvariant();reservation_fingerprint=$ReservationFingerprint.Trim().ToLowerInvariant();persistence_admission_fingerprint=$PersistenceAdmissionFingerprint.Trim().ToLowerInvariant()
        written_at=$WrittenAt.ToUniversalTime().ToString('o');append_only=$true;reservation_persisted=$true;nonce_durably_reserved=$true;permit_durably_reserved=$true
        session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true
        persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;state=$State;envelope_sha256=$null
    }
    $e.envelope_sha256 = Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeMaterialV010 -Envelope $e)
    return $e
}

function Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 {
    param([AllowNull()]$Envelope)
    if ($null -eq $Envelope) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-null'} }
    foreach ($f in @('schema','managed_by','qualified_reservation_head','qualified_reservation_core_blob','qualified_admission_head','qualified_admission_core_blob','revision','state_sha256','previous_envelope_sha256','reservation_id','reservation_fingerprint','persistence_admission_fingerprint','written_at','append_only','reservation_persisted','nonce_durably_reserved','permit_durably_reserved','session_key_persisted','session_key_exposed','permit_consumed','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_persisted_consumption_before_executor','persistence_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','state','envelope_sha256')) {
        if (-not $Envelope.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-envelope-field-missing-'+$f)} }
    }
    if ([int]$Envelope.schema -ne $CustomAppProductionRecoveryAwarePermitReservationPersistenceSchema -or [string]$Envelope.managed_by -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceManagedBy) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-owner-schema-mismatch'} }
    if ([string]$Envelope.qualified_reservation_head -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationHead -or [string]$Envelope.qualified_reservation_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationCoreBlob -or [string]$Envelope.qualified_admission_head -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionHead -or [string]$Envelope.qualified_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionCoreBlob) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-lineage-mismatch'} }
    foreach ($f in @('state_sha256','previous_envelope_sha256','reservation_id','reservation_fingerprint','persistence_admission_fingerprint','envelope_sha256')) { if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (([string]$Envelope.$f).Trim().ToLowerInvariant()))) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-envelope-hash-invalid-'+$f)} } }
    foreach ($f in @('append_only','reservation_persisted','nonce_durably_reserved','permit_durably_reserved','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_persisted_consumption_before_executor')) { if (-not [bool]$Envelope.$f) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-envelope-required-flag-false-'+$f)} } }
    foreach ($f in @('session_key_persisted','session_key_exposed','permit_consumed','persistence_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')) { if ([bool]$Envelope.$f) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-envelope-authority-escaped-'+$f)} } }
    $stateCheck = Test-CustomAppProductionPermitReservationStateV010 -State $Envelope.state
    if (-not [bool]$stateCheck.ok) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-envelope-state-invalid:'+[string]$stateCheck.reason)} }
    if ([int64]$Envelope.revision -ne [int64]$stateCheck.revision) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-revision-mismatch'} }
    $expectedState = Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $Envelope.state)
    if (([string]$Envelope.state_sha256).Trim().ToLowerInvariant() -cne $expectedState) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-state-sha-mismatch'} }
    $last = @($Envelope.state.reservations)[-1]
    if (([string]$last.reservation_id).Trim().ToLowerInvariant() -cne ([string]$Envelope.reservation_id).Trim().ToLowerInvariant()) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-last-reservation-mismatch'} }
    $expected = Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeMaterialV010 -Envelope $Envelope)
    if (([string]$Envelope.envelope_sha256).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-envelope-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='reservation-persistence-envelope-valid';revision=[int64]$stateCheck.revision;envelope_sha256=$expected;reservation_id=([string]$Envelope.reservation_id).Trim().ToLowerInvariant()}
}

function ConvertFrom-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reservation persistence file is reparse point' }
    if ($item.Length -gt 4194304) { throw 'reservation persistence file exceeds 4 MiB' }
    $raw = [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
    try { $e=$raw | ConvertFrom-Json } catch { throw 'reservation persistence JSON invalid' }
    $check = Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 -Envelope $e
    if (-not [bool]$check.ok) { throw ('reservation persistence envelope invalid: '+[string]$check.reason) }
    return [pscustomobject]@{envelope=$e;raw=$raw;raw_sha256=(Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 $raw)}
}

function Read-CustomAppProductionRecoveryAwarePermitReservationStoreUnlockedV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    $files = @(Get-ChildItem -LiteralPath ([string]$Paths.history) -File -Filter '*.json' -Force | Sort-Object Name)
    if ($files.Count -eq 0) {
        if (Test-Path -LiteralPath ([string]$Paths.current)) { throw 'reservation-persistence-current-without-history' }
        return [pscustomobject]@{ok=$true;reason='reservation-persistence-store-empty';initialized=$true;revision=[int64]0;state=(New-CustomAppProductionPermitReservationStateV010);envelope=$null;history_count=0;current_matches_history=$true;reloaded_from_persistent_store=$true}
    }
    $expectedRevision=[int64]1;$previous=$CustomAppProductionRecoveryAwarePermitReservationPersistenceZeroHash;$latest=$null
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reservation persistence history entry is reparse point' }
        $entry=ConvertFrom-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeFileV010 -Path $file.FullName;$e=$entry.envelope
        if ([int64]$e.revision -ne $expectedRevision) { throw 'reservation persistence history revision chain invalid' }
        if (([string]$e.previous_envelope_sha256).Trim().ToLowerInvariant() -cne $previous) { throw 'reservation persistence history hash chain invalid' }
        $expectedName=('{0:D20}-{1}.json' -f [int64]$e.revision,([string]$e.envelope_sha256).Trim().ToLowerInvariant())
        if ([string]$file.Name -cne $expectedName) { throw 'reservation persistence history filename identity invalid' }
        $previous=([string]$e.envelope_sha256).Trim().ToLowerInvariant();$latest=$e;$expectedRevision++
    }
    if (-not (Test-Path -LiteralPath ([string]$Paths.current) -PathType Leaf)) { throw 'reservation-persistence-current-missing' }
    $current=ConvertFrom-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeFileV010 -Path ([string]$Paths.current)
    if ([int64]$current.envelope.revision -ne [int64]$latest.revision -or ([string]$current.envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$latest.envelope_sha256).Trim().ToLowerInvariant()) { throw 'reservation-persistence-current-history-mismatch' }
    return [pscustomobject]@{ok=$true;reason='reservation-persistence-store-valid';initialized=$true;revision=[int64]$latest.revision;state=$latest.state;envelope=$latest;history_count=$files.Count;current_matches_history=$true;reloaded_from_persistent_store=$true}
}

function Read-CustomAppProductionRecoveryAwarePermitReservationStoreV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory)
    $paths=Get-CustomAppProductionRecoveryAwarePermitReservationPersistencePathsV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory;$lock=$null
    try { $lock=Open-CustomAppProductionRecoveryAwarePermitReservationPersistenceLockV010 -Paths $paths;$r=Read-CustomAppProductionRecoveryAwarePermitReservationStoreUnlockedV010 -Paths $paths;return [pscustomobject]@{ok=$true;reason=[string]$r.reason;revision=[int64]$r.revision;state=$r.state;envelope=$r.envelope;history_count=[int]$r.history_count;current_matches_history=[bool]$r.current_matches_history;reloaded_from_persistent_store=$true;session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false} }
    finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Test-CustomAppProductionRecoveryAwarePermitReservationStateExtendsExactlyOneV010 {
    param([Parameter(Mandatory=$true)]$Current,[Parameter(Mandatory=$true)]$Next)
    $a=Test-CustomAppProductionPermitReservationStateV010 -State $Current;$b=Test-CustomAppProductionPermitReservationStateV010 -State $Next
    if (-not [bool]$a.ok) { return [pscustomobject]@{ok=$false;reason=('current-state-invalid:'+[string]$a.reason)} }
    if (-not [bool]$b.ok) { return [pscustomobject]@{ok=$false;reason=('next-state-invalid:'+[string]$b.reason)} }
    if ([int64]$Next.revision -ne ([int64]$Current.revision+1)) { return [pscustomobject]@{ok=$false;reason='next-state-not-single-revision-extension'} }
    $left=@($Current.reservations);$right=@($Next.reservations)
    if ($right.Count -ne ($left.Count+1)) { return [pscustomobject]@{ok=$false;reason='next-state-not-single-row-extension'} }
    for ($i=0;$i -lt $left.Count;$i++) { if (($left[$i]|ConvertTo-Json -Depth 60 -Compress) -cne ($right[$i]|ConvertTo-Json -Depth 60 -Compress)) { return [pscustomobject]@{ok=$false;reason='next-state-rewrites-history'} } }
    return [pscustomobject]@{ok=$true;reason='next-state-exact-single-extension'}
}

function Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceContinuityV010 {
    param([Parameter(Mandatory=$true)]$ReservationReceipt,[Parameter(Mandatory=$true)]$FreshAdmission)
    $pairs=@(
        @('name','name'),@('source_identity','source_identity'),@('transaction_id','transaction_id'),@('github_repo_id','github_repo_id'),@('surface_kind','surface_kind'),
        @('stable_live_tree_sha256','stable_live_tree_sha256'),@('stable_persistence_fingerprint','stable_persistence_fingerprint'),@('current_remote_tree_sha256','current_remote_tree_sha256'),
        @('current_remote_commit_sha','current_remote_commit_sha'),@('current_binding_fingerprint','current_binding_fingerprint'),@('current_provenance_fingerprint','current_provenance_fingerprint'),
        @('live_admission_fingerprint','live_admission_fingerprint'),@('current_eligibility_fingerprint','current_eligibility_fingerprint'),@('live_attested_qualification_fingerprint','live_attested_qualification_fingerprint')
    )
    foreach ($p in $pairs) { if (([string]$ReservationReceipt.($p[0])).Trim().ToLowerInvariant() -cne ([string]$FreshAdmission.($p[1])).Trim().ToLowerInvariant()) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-continuity-'+$p[0]+'-mismatch')} } }
    return [pscustomobject]@{ok=$true;reason='reservation-persistence-continuity-valid'}
}

function Save-CustomAppProductionRecoveryAwarePermitReservationStateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory,[Parameter(Mandatory=$true)]$NextState,
        [Parameter(Mandatory=$true)][int64]$ExpectedCurrentRevision,[Parameter(Mandatory=$true)][string]$ReservationFingerprint,[Parameter(Mandatory=$true)][string]$PersistenceAdmissionFingerprint,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;read_after_write_verified=$false;write_performed=$false;recovered_existing_persistence=$false;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    try { $paths=Get-CustomAppProductionRecoveryAwarePermitReservationPersistencePathsV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory } catch { return & $deny ('reservation-persistence-path-denied:'+[string]$_.Exception.Message) }
    $lock=$null;$temp=$null;$backup=$null
    try {
        try { $lock=Open-CustomAppProductionRecoveryAwarePermitReservationPersistenceLockV010 -Paths $paths } catch { return & $deny ([string]$_.Exception.Message) }
        try { $current=Read-CustomAppProductionRecoveryAwarePermitReservationStoreUnlockedV010 -Paths $paths } catch { return & $deny ('reservation-persistence-read-denied:'+[string]$_.Exception.Message) }
        $targetCheck=Test-CustomAppProductionPermitReservationStateV010 -State $NextState
        if (-not [bool]$targetCheck.ok) { return & $deny ('reservation-persistence-next-state-invalid:'+[string]$targetCheck.reason) }
        $targetLast=@($NextState.reservations)[-1]
        if ([int64]$current.revision -eq [int64]$NextState.revision) {
            $currentJson=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $current.state;$targetJson=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $NextState
            if ($currentJson -cne $targetJson -or $null -eq $current.envelope -or ([string]$current.envelope.reservation_fingerprint).Trim().ToLowerInvariant() -cne $ReservationFingerprint.Trim().ToLowerInvariant()) { return & $deny 'reservation-persistence-existing-revision-conflict' }
            return [pscustomobject]@{ok=$true;reason='reservation-state-already-durably-persisted-and-reloaded';persisted=$true;read_after_write_verified=$true;write_performed=$false;recovered_existing_persistence=$true;revision=[int64]$current.revision;state=$current.state;envelope=$current.envelope;reservation_id=[string]$targetLast.reservation_id;reloaded_from_persistent_store=$true;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
        }
        if ([int64]$current.revision -ne $ExpectedCurrentRevision) { return & $deny 'reservation-persistence-revision-conflict' }
        $extend=Test-CustomAppProductionRecoveryAwarePermitReservationStateExtendsExactlyOneV010 -Current $current.state -Next $NextState
        if (-not [bool]$extend.ok) { return & $deny ([string]$extend.reason) }
        $previous=if($null -eq $current.envelope){$CustomAppProductionRecoveryAwarePermitReservationPersistenceZeroHash}else{([string]$current.envelope.envelope_sha256).Trim().ToLowerInvariant()}
        $e=New-CustomAppProductionRecoveryAwarePermitReservationPersistenceEnvelopeV010 -State $NextState -PreviousEnvelopeSha256 $previous -ReservationId ([string]$targetLast.reservation_id) -ReservationFingerprint $ReservationFingerprint -PersistenceAdmissionFingerprint $PersistenceAdmissionFingerprint -WrittenAt $Now
        $json=$e|ConvertTo-Json -Depth 70 -Compress;$historyPath=Join-Path ([string]$paths.history) ('{0:D20}-{1}.json' -f [int64]$e.revision,[string]$e.envelope_sha256)
        try { Write-CustomAppProductionRecoveryAwarePermitReservationDurableFileV010 -Path $historyPath -Text $json -Mode ([IO.FileMode]::CreateNew) } catch { return & $deny ('reservation-persistence-history-create-failed:'+[string]$_.Exception.Message) }
        if ($FailurePoint -ceq 'after-history-before-current') { return & $deny 'simulated-crash-after-history-before-current' }
        if (Test-Path -LiteralPath ([string]$paths.current)) {
            $temp=Join-Path ([string]$paths.store) ('current.tmp.'+[Guid]::NewGuid().ToString('N'));$backup=Join-Path ([string]$paths.store) ('current.backup.'+[Guid]::NewGuid().ToString('N'))
            Write-CustomAppProductionRecoveryAwarePermitReservationDurableFileV010 -Path $temp -Text $json -Mode ([IO.FileMode]::CreateNew)
            [IO.File]::Replace($temp,[string]$paths.current,$backup,$true);$temp=$null
        } else { Write-CustomAppProductionRecoveryAwarePermitReservationDurableFileV010 -Path ([string]$paths.current) -Text $json -Mode ([IO.FileMode]::CreateNew) }
        try { $verify=Read-CustomAppProductionRecoveryAwarePermitReservationStoreUnlockedV010 -Paths $paths } catch { return & $deny ('reservation-persistence-readback-denied:'+[string]$_.Exception.Message) }
        if ([int64]$verify.revision -ne [int64]$NextState.revision -or ([string]$verify.envelope.envelope_sha256).Trim().ToLowerInvariant() -cne ([string]$e.envelope_sha256).Trim().ToLowerInvariant()) { return & $deny 'reservation-persistence-readback-mismatch' }
        if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue;$backup=$null }
        return [pscustomobject]@{ok=$true;reason='reservation-state-durably-persisted-and-readback-verified';persisted=$true;read_after_write_verified=$true;write_performed=$true;recovered_existing_persistence=$false;revision=[int64]$verify.revision;state=$verify.state;envelope=$verify.envelope;reservation_id=[string]$targetLast.reservation_id;reloaded_from_persistent_store=$true;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    } finally {
        if ($null -ne $temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

function Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_reservation_head,[string]$Receipt.qualified_reservation_core_blob,[string]$Receipt.qualified_admission_head,[string]$Receipt.qualified_admission_core_blob,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.transaction_id,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,[string]$Receipt.reservation_id,[string]$Receipt.reservation_fingerprint,
        [string]$Receipt.pre_persistence_admission_fingerprint,[string]$Receipt.post_persistence_admission_fingerprint,[string]$Receipt.persistence_envelope_sha256,[string]$Receipt.persisted_revision,
        [string]$Receipt.reservation_persisted,[string]$Receipt.nonce_durably_reserved,[string]$Receipt.permit_durably_reserved,[string]$Receipt.session_key_persisted,[string]$Receipt.session_key_exposed,[string]$Receipt.permit_consumed,
        [string]$Receipt.recovery_aware_persistence_revalidated,[string]$Receipt.read_after_write_verified,[string]$Receipt.reloaded_from_persistent_store,[string]$Receipt.write_performed,[string]$Receipt.recovered_existing_persistence,
        [string]$Receipt.requires_single_use_consumption,[string]$Receipt.requires_fresh_admission_revalidation_on_consume,[string]$Receipt.requires_persisted_consumption_before_executor,[string]$Receipt.persistence_is_authority,[string]$Receipt.executor_may_start,
        [string]$Receipt.production_execution_authorized,[string]$Receipt.production_mutation_authorized,[string]$Receipt.checked_at
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 {
    param([AllowNull()]$Receipt)
    if ($null -eq $Receipt) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-null'} }
    foreach ($f in @('schema','managed_by','qualified_reservation_head','qualified_reservation_core_blob','qualified_admission_head','qualified_admission_core_blob','name','source_identity','transaction_id','github_repo_id','surface_kind','reservation_id','reservation_fingerprint','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','persistence_envelope_sha256','persisted_revision','reservation_persisted','nonce_durably_reserved','permit_durably_reserved','session_key_persisted','session_key_exposed','permit_consumed','recovery_aware_persistence_revalidated','read_after_write_verified','reloaded_from_persistent_store','write_performed','recovered_existing_persistence','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_persisted_consumption_before_executor','persistence_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized','checked_at','persistence_fingerprint')) { if (-not $Receipt.PSObject.Properties[$f]) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-receipt-field-missing-'+$f)} } }
    if ([int]$Receipt.schema -ne $CustomAppProductionRecoveryAwarePermitReservationPersistenceSchema -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceManagedBy) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-owner-schema-mismatch'} }
    if ([string]$Receipt.qualified_reservation_head -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationHead -or [string]$Receipt.qualified_reservation_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationCoreBlob -or [string]$Receipt.qualified_admission_head -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionHead -or [string]$Receipt.qualified_admission_core_blob -cne $CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionCoreBlob) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-lineage-mismatch'} }
    foreach ($f in @('transaction_id','reservation_id','reservation_fingerprint','pre_persistence_admission_fingerprint','post_persistence_admission_fingerprint','persistence_envelope_sha256','persistence_fingerprint')) { if (-not (Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-receipt-hash-invalid-'+$f)} } }
    if (([string]$Receipt.pre_persistence_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Receipt.post_persistence_admission_fingerprint).Trim().ToLowerInvariant()) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-admission-drift'} }
    foreach ($f in @('reservation_persisted','nonce_durably_reserved','permit_durably_reserved','recovery_aware_persistence_revalidated','read_after_write_verified','reloaded_from_persistent_store','requires_single_use_consumption','requires_fresh_admission_revalidation_on_consume','requires_persisted_consumption_before_executor')) { if (-not [bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-receipt-required-flag-false-'+$f)} } }
    foreach ($f in @('session_key_persisted','session_key_exposed','permit_consumed','persistence_is_authority','executor_may_start','production_execution_authorized','production_mutation_authorized')) { if ([bool]$Receipt.$f) { return [pscustomobject]@{ok=$false;reason=('reservation-persistence-receipt-authority-escaped-'+$f)} } }
    if ([bool]$Receipt.write_performed -eq [bool]$Receipt.recovered_existing_persistence) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-write-recovery-flags-invalid'} }
    try { if ([int64]$Receipt.persisted_revision -le 0) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-revision-invalid'} };[void][DateTimeOffset]::Parse([string]$Receipt.checked_at) } catch { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-time-or-revision-invalid'} }
    $expected=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $Receipt)
    if (([string]$Receipt.persistence_fingerprint).Trim().ToLowerInvariant() -cne $expected) { return [pscustomobject]@{ok=$false;reason='reservation-persistence-receipt-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-reservation-persistence-valid-zero-authority';reservation_id=([string]$Receipt.reservation_id).Trim().ToLowerInvariant();persisted_revision=[int64]$Receipt.persisted_revision;executor_may_start=$false;production_mutation_authorized=$false}
}

function Invoke-CustomAppProductionRecoveryAwarePermitReservationPersistenceV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$StageResult,[AllowNull()]$ShadowResult,[AllowNull()]$RetirementResumeResult,
        [AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,[Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$RecoveryStoreDirectory,[Parameter(Mandatory=$true)][string]$PersistenceStoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[Parameter(Mandatory=$true)]$ReservationResult,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36,[ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason,[bool]$Persisted=$false,[AllowNull()]$Saved=$null)[pscustomobject]@{ok=$false;reason=$Reason;reservation_persisted=$Persisted;nonce_durably_reserved=$Persisted;permit_durably_reserved=$Persisted;session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false;recovery_aware_persistence_revalidated=$false;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;saved=$Saved}}
    if ($null -eq $ReservationResult -or -not [bool]$ReservationResult.ok -or $null -eq $ReservationResult.receipt -or $null -eq $ReservationResult.next_state) { return & $deny 'reservation-persistence-reservation-result-invalid' }
    $rr=$ReservationResult.receipt
    $checked=[DateTimeOffset]::MinValue;$until=[DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$rr.checked_at,[ref]$checked) -or -not [DateTimeOffset]::TryParse([string]$rr.persistence_eligible_until,[ref]$until)) { return & $deny 'reservation-persistence-reservation-receipt-time-invalid' }
    $structural=Test-CustomAppProductionRecoveryAwarePermitReservationReceiptV010 -Receipt $rr -Now $checked.AddMilliseconds(1)
    if (-not [bool]$structural.ok) { return & $deny ('reservation-persistence-reservation-receipt-invalid:'+[string]$structural.reason) }
    $nextCheck=Test-CustomAppProductionPermitReservationStateV010 -State $ReservationResult.next_state
    if (-not [bool]$nextCheck.ok) { return & $deny ('reservation-persistence-next-state-invalid:'+[string]$nextCheck.reason) }
    $last=@($ReservationResult.next_state.reservations)[-1]
    if (([string]$last.reservation_id).Trim().ToLowerInvariant() -cne ([string]$rr.reservation_id).Trim().ToLowerInvariant() -or ([string]$last.token_id).Trim().ToLowerInvariant() -cne ([string]$rr.permit_token_id).Trim().ToLowerInvariant() -or ([string]$last.permit_nonce).Trim().ToLowerInvariant() -cne ([string]$rr.permit_nonce).Trim().ToLowerInvariant() -or ([string]$last.permit_hmac_sha256).Trim().ToLowerInvariant() -cne ([string]$rr.permit_hmac_sha256).Trim().ToLowerInvariant()) { return & $deny 'reservation-persistence-reservation-row-receipt-mismatch' }
    try { $preStore=Read-CustomAppProductionRecoveryAwarePermitReservationStoreV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory } catch { return & $deny ('reservation-persistence-store-read-denied:'+[string]$_.Exception.Message) }
    $alreadyPersisted=([int64]$preStore.revision -eq [int64]$ReservationResult.next_state.revision -and (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $preStore.state) -ceq (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceStateJsonV010 -State $ReservationResult.next_state))
    if (-not $alreadyPersisted -and $Now -ge $until) { return & $deny 'reservation-persistence-window-expired-before-durable-write' }
    if (-not $alreadyPersisted -and [int64]$preStore.revision -ne [int64]$rr.state_revision_before) { return & $deny 'reservation-persistence-store-revision-conflict' }
    $pre=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $pre -or -not [bool]$pre.ok) { return & $deny ('reservation-persistence-pre-admission-denied:'+[string]$pre.reason) }
    $preCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $pre.receipt -Now $Now
    if (-not [bool]$preCheck.ok) { return & $deny ('reservation-persistence-pre-admission-invalid:'+[string]$preCheck.reason) }
    $continuity=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceContinuityV010 -ReservationReceipt $rr -FreshAdmission $pre.receipt
    if (-not [bool]$continuity.ok) { return & $deny ([string]$continuity.reason) }
    $saved=Save-CustomAppProductionRecoveryAwarePermitReservationStateV010 -AllowedRoot $AllowedRoot -PersistenceStoreDirectory $PersistenceStoreDirectory -NextState $ReservationResult.next_state -ExpectedCurrentRevision ([int64]$rr.state_revision_before) -ReservationFingerprint ([string]$rr.reservation_fingerprint) -PersistenceAdmissionFingerprint ([string]$pre.receipt.issuance_admission_fingerprint) -Now $Now -FailurePoint $FailurePoint
    if (-not [bool]$saved.ok) { return & $deny ('reservation-persistence-save-denied:'+[string]$saved.reason) ([bool]$saved.persisted) $saved }
    $post=Resolve-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionV010 -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -StageResult $StageResult -ShadowResult $ShadowResult -RetirementResumeResult $RetirementResumeResult -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -AllowedRoot $AllowedRoot -StoreDirectory $RecoveryStoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if ($null -eq $post -or -not [bool]$post.ok) { return & $deny ('reservation-persistence-post-admission-denied:'+[string]$post.reason) $true $saved }
    $postCheck=Test-CustomAppProductionRecoveryAwarePermitIssuanceAdmissionReceiptV010 -Receipt $post.receipt -Now $Now
    if (-not [bool]$postCheck.ok) { return & $deny ('reservation-persistence-post-admission-invalid:'+[string]$postCheck.reason) $true $saved }
    $continuity2=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceContinuityV010 -ReservationReceipt $rr -FreshAdmission $post.receipt
    if (-not [bool]$continuity2.ok) { return & $deny ('reservation-persistence-post-'+[string]$continuity2.reason) $true $saved }
    if (([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant() -cne ([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()) { return & $deny 'reservation-persistence-admission-drift-after-durable-write' $true $saved }
    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwarePermitReservationPersistenceSchema;managed_by=$CustomAppProductionRecoveryAwarePermitReservationPersistenceManagedBy
        qualified_reservation_head=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationHead;qualified_reservation_core_blob=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedReservationCoreBlob
        qualified_admission_head=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionHead;qualified_admission_core_blob=$CustomAppProductionRecoveryAwarePermitReservationPersistenceQualifiedAdmissionCoreBlob
        name=([string]$rr.name).Trim().ToLowerInvariant();source_identity=([string]$rr.source_identity).Trim().ToLowerInvariant();transaction_id=([string]$rr.transaction_id).Trim().ToLowerInvariant();github_repo_id=[int64]$rr.github_repo_id;surface_kind=([string]$rr.surface_kind).Trim().ToLowerInvariant()
        reservation_id=([string]$rr.reservation_id).Trim().ToLowerInvariant();reservation_fingerprint=([string]$rr.reservation_fingerprint).Trim().ToLowerInvariant();pre_persistence_admission_fingerprint=([string]$pre.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant();post_persistence_admission_fingerprint=([string]$post.receipt.issuance_admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$saved.envelope.envelope_sha256).Trim().ToLowerInvariant();persisted_revision=[int64]$saved.revision;reservation_persisted=$true;nonce_durably_reserved=$true;permit_durably_reserved=$true;session_key_persisted=$false;session_key_exposed=$false;permit_consumed=$false
        recovery_aware_persistence_revalidated=$true;read_after_write_verified=[bool]$saved.read_after_write_verified;reloaded_from_persistent_store=[bool]$saved.reloaded_from_persistent_store;write_performed=[bool]$saved.write_performed;recovered_existing_persistence=[bool]$saved.recovered_existing_persistence
        requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false;checked_at=$Now.ToUniversalTime().ToString('o');persistence_fingerprint=$null
    }
    $receipt.persistence_fingerprint=Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceSha256V010 (Get-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptMaterialV010 -Receipt $receipt)
    $receiptCheck=Test-CustomAppProductionRecoveryAwarePermitReservationPersistenceReceiptV010 -Receipt $receipt
    if (-not [bool]$receiptCheck.ok) { return & $deny ('reservation-persistence-output-invalid:'+[string]$receiptCheck.reason) $true $saved }
    return [pscustomobject]@{ok=$true;reason='recovery-aware-permit-reservation-durably-persisted-zero-authority';receipt=$receipt;store=$saved;reservation_persisted=$true;nonce_durably_reserved=$true;permit_durably_reserved=$true;permit_consumed=$false;recovery_aware_persistence_revalidated=$true;requires_single_use_consumption=$true;requires_fresh_admission_revalidation_on_consume=$true;requires_persisted_consumption_before_executor=$true;persistence_is_authority=$false;executor_may_start=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
