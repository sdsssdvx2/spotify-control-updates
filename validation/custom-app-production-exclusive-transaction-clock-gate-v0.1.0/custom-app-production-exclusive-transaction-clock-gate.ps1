# VALIDATION ONLY. No production FullChain is enabled or modified.
# This extends the signed Triple-ID bridge with a cross-process per-app guard:
#   FileShare.None lock while entering a transaction, plus durable active marker.
# A killed process loses the handle but NOT the active marker. Active markers
# are retired only when the same immutable journal reaches a terminal phase.
# No user-PC paths are allowed by this validation implementation.

function New-CustomAppProductionExclusiveGateDeniedV010 {
    param([string]$Reason)
    return [pscustomobject]@{ok=$false;reason=$Reason;lock_handle=$null;record_path=$null;result=$null;mutation_attempted=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
function Get-CustomAppProductionExclusiveGateSha256V010 {
    param([Parameter(Mandatory=$true)][string]$Material)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Material))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionWallClockAdmissionV010 {
    param([Parameter(Mandatory=$true)][DateTimeOffset]$SuppliedNow,[int]$MaxSkewSeconds=45)
    if($MaxSkewSeconds -lt 1 -or $MaxSkewSeconds -gt 60){return [pscustomobject]@{ok=$false;reason='wall-clock-maximum-skew-invalid';production_mutation_authorized=$false}}
    $actual=[DateTimeOffset]::UtcNow
    $diff=[Math]::Abs(($actual-$SuppliedNow.ToUniversalTime()).TotalSeconds)
    if($diff -gt $MaxSkewSeconds){
        return [pscustomobject]@{ok=$false;reason='wall-clock-supplied-time-not-current';skew_seconds=[Math]::Round($diff,3);production_mutation_authorized=$false}
    }
    return [pscustomobject]@{ok=$true;reason='wall-clock-current-time-consistent';skew_seconds=[Math]::Round($diff,3);trusted_now=$actual;production_mutation_authorized=$false}
}
function Get-CustomAppProductionExclusiveGatePathsV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$LivePath)
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'exclusive-gate-hosted-windows-only'}
    if($Name -cnotmatch '^[a-zA-Z][a-zA-Z0-9_-]{1,63}$'){throw 'exclusive-gate-invalid-app-name'}
    $root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $live=[IO.Path]::GetFullPath($LivePath).TrimEnd('\','/')
    if(-not $live.StartsWith(($root+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'exclusive-gate-live-not-under-hosted-runner'}
    $dir=Join-Path $root 'custom-app-exclusive-transactions'
    if($live.StartsWith(($dir+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'exclusive-gate-live-overlaps-registry'}
    # Lock identity is the canonical live directory, NOT a caller-selected app alias.
    # Distinct names pointing at the same physical app directory must contend.
    $key=Get-CustomAppProductionExclusiveGateSha256V010 ($live.ToLowerInvariant())
    return [pscustomobject]@{name=$Name.ToLowerInvariant();live=$live;root=$root;directory=$dir;key=$key;lock=(Join-Path $dir ($key+'.lock'));record=(Join-Path $dir ($key+'.json'))}
}
function Assert-CustomAppProductionExclusiveGateNoReparseV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(Test-Path -LiteralPath $Path){
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'exclusive-gate-reparse-path-denied'}
    }
}
function Open-CustomAppProductionExclusiveGateLockV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$LivePath)
    $paths=$null;$handle=$null
    try{
        $paths=Get-CustomAppProductionExclusiveGatePathsV010 -Name $Name -LivePath $LivePath
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.root
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.directory
        if(-not(Test-Path -LiteralPath $paths.directory)){[IO.Directory]::CreateDirectory($paths.directory)|Out-Null}
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.directory
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.lock
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.record
        $handle=[IO.File]::Open($paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $paths.lock
        return [pscustomobject]@{ok=$true;reason='exclusive-app-lock-held';paths=$paths;lock_handle=$handle;production_mutation_authorized=$false}
    }catch{
        if($null -ne $handle){$handle.Dispose()}
        return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-lock-unavailable:'+[string]$_.Exception.Message)
    }
}
function Get-CustomAppProductionExclusiveGateRecordMaterialV010 {
    param([Parameter(Mandatory=$true)]$Record)
    return ([string]$Record.schema+'|'+[string]$Record.name+'|'+[string]$Record.live_path+'|'+[string]$Record.consumption_id+'|'+[string]$Record.journal_store+'|'+[string]$Record.transaction_nonce+'|'+[string]$Record.created_utc+'|'+[string]$Record.state)
}
function Read-CustomAppProductionExclusiveGateRecordV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    if(-not(Test-Path -LiteralPath $Paths.record -PathType Leaf)){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-active-record-missing'}
    try{
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $Paths.record
        $bytes=[IO.File]::ReadAllBytes([string]$Paths.record)
        if($bytes.Length -lt 100 -or $bytes.Length -gt 8192){throw 'exclusive-app-record-size-invalid'}
        $record=([Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -ErrorAction Stop)
        if([int]$record.schema -ne 1 -or [string]$record.name -cne [string]$Paths.name -or [string]$record.live_path -cne [string]$Paths.live -or [string]$record.state -cne 'active'){
            throw 'exclusive-app-active-record-identity-invalid'
        }
        if([string]$record.consumption_id -cnotmatch '^[0-9a-f]{64}$' -or [string]$record.transaction_nonce -cnotmatch '^[0-9a-fA-F]{32}$'){throw 'exclusive-app-record-token-shape-invalid'}
        $journal=[IO.Path]::GetFullPath([string]$record.journal_store).TrimEnd('\','/')
        if(-not $journal.StartsWith(([string]$Paths.root+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'exclusive-app-record-journal-outside-runner'}
        $expected=Get-CustomAppProductionExclusiveGateSha256V010 (Get-CustomAppProductionExclusiveGateRecordMaterialV010 -Record $record)
        if([string]$record.record_sha256 -cne $expected){throw 'exclusive-app-active-record-checksum-invalid'}
        return [pscustomobject]@{ok=$true;reason='exclusive-app-durable-record-valid';record=$record;record_sha256=$expected;production_mutation_authorized=$false}
    }catch{return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-record-tampered-or-unreadable:'+[string]$_.Exception.Message)}
}
function Get-CustomAppProductionExclusiveGateRetiredPathV010 {
    param([Parameter(Mandatory=$true)]$Paths,[Parameter(Mandatory=$true)][string]$ConsumptionId)
    if($ConsumptionId -cnotmatch '^[0-9a-f]{64}$'){throw 'exclusive-app-retired-consumption-id-invalid'}
    return (Join-Path ([string]$Paths.directory) (([string]$Paths.key)+'.'+$ConsumptionId+'.retired.json'))
}
function Test-CustomAppProductionExclusiveGateRetiredReceiptV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Paths,[Parameter(Mandatory=$true)][string]$ConsumptionId)
    try{
        Assert-CustomAppProductionExclusiveGateNoReparseV010 -Path $Path
        if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'retirement-receipt-missing'}
        $bytes=[IO.File]::ReadAllBytes($Path)
        if($bytes.Length -lt 120 -or $bytes.Length -gt 8192){throw 'retirement-receipt-size-invalid'}
        $receipt=([Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -ErrorAction Stop)
        if([int]$receipt.schema -ne 1 -or [string]$receipt.name -cne [string]$Paths.name -or
            [string]$receipt.live_path -cne [string]$Paths.live -or [string]$receipt.consumption_id -cne $ConsumptionId -or
            [string]$receipt.transaction_id -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$receipt.terminal_phase -notin @('rollback-complete','committed-clean') -or
            [string]$receipt.active_record_sha256 -cnotmatch '^[0-9a-f]{64}$'){
            throw 'retirement-receipt-binding-invalid'
        }
        $material=([string]$receipt.schema+'|'+[string]$receipt.name+'|'+[string]$receipt.live_path+'|'+[string]$receipt.consumption_id+'|'+[string]$receipt.transaction_id+'|'+[string]$receipt.terminal_phase+'|'+[string]$receipt.active_record_sha256+'|'+[string]$receipt.completed_utc)
        if([string]$receipt.receipt_sha256 -cne (Get-CustomAppProductionExclusiveGateSha256V010 $material)){throw 'retirement-receipt-checksum-invalid'}
        return [pscustomobject]@{ok=$true;reason='retired-consumption-record-present-and-valid';receipt=$receipt;production_mutation_authorized=$false}
    }catch{return New-CustomAppProductionExclusiveGateDeniedV010 ('retired-consumption-record-invalid:'+[string]$_.Exception.Message)}
}
function Write-CustomAppProductionExclusiveGateActiveRecordV010 {
    param(
        [Parameter(Mandatory=$true)]$Lock,
        [Parameter(Mandatory=$true)][string]$ConsumptionId,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
        [Parameter(Mandatory=$true)][string]$TransactionNonce
    )
    if($null -eq $Lock -or -not[bool]$Lock.ok -or $null -eq $Lock.lock_handle){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-claim-without-held-lock'}
    $p=$Lock.paths
    try{
        if([string]$ConsumptionId -cnotmatch '^[0-9a-f]{64}$' -or $TransactionNonce -cnotmatch '^[0-9a-fA-F]{32}$'){throw 'exclusive-app-invalid-claim-identifiers'}
        $journal=[IO.Path]::GetFullPath($JournalStoreDirectory).TrimEnd('\','/')
        if(-not $journal.StartsWith(([string]$p.root+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'exclusive-app-journal-not-in-hosted-runner'}
        if($journal.StartsWith(([string]$p.directory+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'exclusive-app-journal-overlaps-gate'}
        if(Test-Path -LiteralPath $p.record){throw 'exclusive-app-active-transaction-blocks-new-claim'}
        $retiredPath=Get-CustomAppProductionExclusiveGateRetiredPathV010 -Paths $p -ConsumptionId $ConsumptionId
        if(Test-Path -LiteralPath $retiredPath){throw 'exclusive-app-consumption-already-retired'}
        $record=[ordered]@{schema=1;name=[string]$p.name;live_path=[string]$p.live;consumption_id=$ConsumptionId;transaction_nonce=$TransactionNonce;journal_store=$journal;created_utc=([DateTimeOffset]::UtcNow.ToString('o'));state='active'}
        $record.record_sha256=Get-CustomAppProductionExclusiveGateSha256V010 (Get-CustomAppProductionExclusiveGateRecordMaterialV010 $record)
        $bytes=[Text.Encoding]::UTF8.GetBytes(($record|ConvertTo-Json -Compress -Depth 6))
        $s=$null
        try{
            $s=[IO.File]::Open($p.record,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $s.Write($bytes,0,$bytes.Length);$s.Flush($true)
        }finally{if($null -ne $s){$s.Dispose()}}
        $read=Read-CustomAppProductionExclusiveGateRecordV010 $p
        if(-not[bool]$read.ok){throw ('exclusive-app-record-readback-denied:'+ [string]$read.reason)}
        return [pscustomobject]@{ok=$true;reason='exclusive-app-claim-durable';record_path=$p.record;record_sha256=[string]$read.record_sha256;production_mutation_authorized=$false}
    }catch{return New-CustomAppProductionExclusiveGateDeniedV010 ([string]$_.Exception.Message)}
}
function Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010 {
    param([Parameter(Mandatory=$true)][hashtable]$AtomicPreconditionArgs,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$TransactionNonce)
    $clock=$null;$lock=$null
    try{
        if(-not $AtomicPreconditionArgs.ContainsKey('Now')){return New-CustomAppProductionExclusiveGateDeniedV010 'wall-clock-now-parameter-missing'}
        $clock=Test-CustomAppProductionWallClockAdmissionV010 -SuppliedNow ([DateTimeOffset]$AtomicPreconditionArgs.Now)
        if(-not[bool]$clock.ok){return New-CustomAppProductionExclusiveGateDeniedV010 ('wall-clock-denied:'+[string]$clock.reason)}
        $name=[string]$AtomicPreconditionArgs.Name
        $live=[string]$AtomicPreconditionArgs.LifecycleRow.locations[0]
        $lock=Open-CustomAppProductionExclusiveGateLockV010 -Name $name -LivePath $live
        if(-not[bool]$lock.ok){return $lock}
        if(Test-Path -LiteralPath $lock.paths.record){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-active-transaction-blocks-new-update'}
        # Re-run HMAC, live/.git/settings, and durable latest-consumption preflight
        # WHILE THE PER-APP CROSS-PROCESS LOCK IS HELD, before writing marker.
        $actual=@{};foreach($k in $AtomicPreconditionArgs.Keys){$actual[$k]=$AtomicPreconditionArgs[$k]}
        $actual.Now=[DateTimeOffset]::UtcNow
        $pre=Test-CustomAppProductionAtomicPreconditionsV010 @actual
        if($null-eq$pre -or -not[bool]$pre.ok){return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-fresh-hmac-or-live-denied:'+[string]$pre.reason)}
        $identity=Test-CustomAppProductionPostSwapPermitStageContinuityV010 -Permit $actual.Permit -StageExecutorResult $actual.StageExecutorResult -Name $name
        if(-not[bool]$identity.ok){return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-permit-stage-denied:'+[string]$identity.reason)}
        $consumed=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot ([string]$actual.AllowedRoot) -StoreDirectory ([string]$actual.StoreDirectory) -ExpectedConsumptionId ([string]$actual.ExpectedConsumptionId) -Permit $actual.Permit -StageExecutorResult $actual.StageExecutorResult -Name $name
        if(-not[bool]$consumed.ok){return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-consumption-denied:'+[string]$consumed.reason)}
        $claim=Write-CustomAppProductionExclusiveGateActiveRecordV010 -Lock $lock -ConsumptionId ([string]$actual.ExpectedConsumptionId) -JournalStoreDirectory $JournalStoreDirectory -TransactionNonce $TransactionNonce
        if(-not[bool]$claim.ok){return $claim}
        # From here a crash MUST leave an active durable marker. Never
        # automatically unlink it on failed/partial journal mutation.
        $result=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $actual -JournalStoreDirectory $JournalStoreDirectory -TransactionNonce $TransactionNonce
        return [pscustomobject]@{
            ok=[bool]$result.ok;reason=[string]$result.reason
            result=$result.result;atomic_result=$result.atomic_result
            mutation_attempted=[bool]$result.mutation_attempted
            requires_recovery=$true
            exclusive_claim_persisted=$true;claim_path=[string]$lock.paths.record
            journal_phase=[string]$result.journal_phase
            transaction_id=[string]$result.transaction_id
            session_key_not_serialized=$true
            production_execution_authorized=$false;production_mutation_authorized=$false
            spicetify_apply_authorized=$false;additional_mutation_authorized=$false
        }
    }catch{return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-guarded-operation-threw:'+[string]$_.Exception.Message)}
    finally{if($null -ne $lock -and $null -ne $lock.lock_handle){$lock.lock_handle.Dispose()}}
}
function Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$LivePath,
        [Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [switch]$ValidationInterruptAfterArchive
    )
    $lock=$null
    try{
        $lock=Open-CustomAppProductionExclusiveGateLockV010 -Name $Name -LivePath $LivePath
        if(-not[bool]$lock.ok){return $lock}
        $r=Read-CustomAppProductionExclusiveGateRecordV010 -Paths $lock.paths
        if(-not[bool]$r.ok){return $r}
        if([string]$r.record.consumption_id -cne $ExpectedConsumptionId){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-terminal-consumption-id-mismatch'}
        if([string]$ExpectedTransactionId -cnotmatch '^[0-9a-f]{64}$'){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-terminal-transaction-id-shape-invalid'}
        $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$lock.paths.root) -StoreDirectory ([string]$r.record.journal_store)
        if(-not[bool]$j.ok -or -not[bool]$j.reloaded_from_persistent_store -or [string]$j.transaction_id -cne $ExpectedTransactionId -or [string]$j.entry.consumption_id -cne $ExpectedConsumptionId -or [string]$j.entry.phase -notin @('rollback-complete','committed-clean')){
            return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-journal-not-terminal-or-identity-drift'
        }
        $e=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$lock.paths.root) -StoreDirectory ([string]$r.record.journal_store) -ExpectedTransactionId $ExpectedTransactionId
        if(-not[bool]$e.ok){return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-terminal-recovery-evidence-invalid'}
        # Persist the consumed-ID retirement BEFORE deleting the active marker.
        # A crash between these operations is fail-closed (both remain).
        # The same Third-ID cannot be reused after terminal completion.
        $retiredPath=Get-CustomAppProductionExclusiveGateRetiredPathV010 -Paths $lock.paths -ConsumptionId $ExpectedConsumptionId
        $reconciledExisting=$false
        if(Test-Path -LiteralPath $retiredPath){
            # Crash window: retirement was durably archived but the active marker
            # was not deleted. Re-verify BOTH, then finish the original retirement.
            $reconciledExisting=$true
        }else{
            $stamp=[DateTimeOffset]::UtcNow.ToString('o')
            $archive=[ordered]@{
                schema=1;name=[string]$lock.paths.name;live_path=[string]$lock.paths.live
                consumption_id=$ExpectedConsumptionId;transaction_id=$ExpectedTransactionId
                terminal_phase=[string]$j.entry.phase;active_record_sha256=[string]$r.record_sha256
                completed_utc=$stamp
            }
            $archiveMaterial=([string]$archive.schema+'|'+[string]$archive.name+'|'+[string]$archive.live_path+'|'+[string]$archive.consumption_id+'|'+[string]$archive.transaction_id+'|'+[string]$archive.terminal_phase+'|'+[string]$archive.active_record_sha256+'|'+[string]$archive.completed_utc)
            $archive.receipt_sha256=Get-CustomAppProductionExclusiveGateSha256V010 $archiveMaterial
            $archiveBytes=[Text.Encoding]::UTF8.GetBytes(($archive|ConvertTo-Json -Compress -Depth 6))
            $s=$null
            try{
                $s=[IO.File]::Open($retiredPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $s.Write($archiveBytes,0,$archiveBytes.Length);$s.Flush($true)
            }finally{if($null -ne $s){$s.Dispose()}}
        }
        $archived=Test-CustomAppProductionExclusiveGateRetiredReceiptV010 -Path $retiredPath -Paths $lock.paths -ConsumptionId $ExpectedConsumptionId
        if(-not[bool]$archived.ok){return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-retired-archive-readback-denied:'+[string]$archived.reason)}
        if([string]$archived.receipt.active_record_sha256 -cne [string]$r.record_sha256 -or
            [string]$archived.receipt.transaction_id -cne $ExpectedTransactionId -or
            [string]$archived.receipt.terminal_phase -cne [string]$j.entry.phase){
            return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-retired-archive-journal-identity-mismatch'
        }
        # Validation-only fault injection: exactly the durable-archive / active
        # unlink crash boundary. A fresh caller must reconcile the same files.
        if($ValidationInterruptAfterArchive){
            return New-CustomAppProductionExclusiveGateDeniedV010 'exclusive-app-ci-interrupted-after-retirement-archive'
        }
        [IO.File]::Delete([string]$lock.paths.record)
        return [pscustomobject]@{
            ok=$true;reason='exclusive-app-terminal-journal-verified-consumption-archived-and-active-retired'
            phase=[string]$j.entry.phase;retired_record_path=$retiredPath
            retired_receipt_sha256=[string]$archived.receipt.receipt_sha256
            reconciled_interrupted_retirement=$reconciledExisting
            production_mutation_authorized=$false
        }
    }catch{return New-CustomAppProductionExclusiveGateDeniedV010 ('exclusive-app-terminal-recovery-check-threw:'+[string]$_.Exception.Message)}
    finally{if($null -ne $lock -and $null -ne $lock.lock_handle){$lock.lock_handle.Dispose()}}
}
