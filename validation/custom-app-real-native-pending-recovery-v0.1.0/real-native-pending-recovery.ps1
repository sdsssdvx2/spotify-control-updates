# V025 / Windows hosted validation only.
# A CurrentUser-DPAPI sealed official-vendor receipt allows a fresh keyless
# process to complete the exact V010 pending -> apply-verified journal CAS
# after its original parent dies. No Spotify CLI is launched on resume,
# and no install/production or bounded-cleanup authority is granted here.
function Assert-CustomAppRealNativePendingHostedV025 {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'real-native-pending-recovery-hosted-Windows-only'
    }
}
function Get-CustomAppRealNativePendingEntropyV025 {
    param([Parameter(Mandatory=$true)][string]$JournalTransactionId)
    return [Text.Encoding]::UTF8.GetBytes(
        'SpotifyControlUpdates|RealNativePendingResume|v025|'+$JournalTransactionId)
}
function Get-CustomAppRealNativePendingPathV025 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId,
          [bool]$RequireExisting=$false)
    if($JournalTransactionId -cnotmatch '^[0-9a-f]{64}$'){
        throw 'real-native-pending-transaction-id-invalid'
    }
    $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $JournalStoreDirectory -Label 'V025 journal root' -RequireExisting:$true
    $out=Join-Path $store ('scoped-real-native-pending-'+$JournalTransactionId+'.dpapi')
    return Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $out -Label 'V025 sealed source' -RequireExisting:$RequireExisting
}
function Test-CustomAppRealNativePendingReceiptBindingV025 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId,
          [Parameter(Mandatory=$true)][string]$ReceiptFingerprint)
    Assert-CustomAppRealNativePendingHostedV025
    $deny={param($why)[pscustomobject]@{ok=$false;reason=[string]$why
      production_execution_authorized=$false;production_mutation_authorized=$false}}
    try{
        $rr=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -ExpectedApplyFingerprint $ReceiptFingerprint -RequireApplyVerified:$false
        if(-not[bool]$rr.ok){throw ('official-success-receipt-read-denied:'+ [string]$rr.reason)}
        $j=$rr.journal;$r=$rr.receipt
        if([string]$j.entry.phase -cne 'apply-returned-success-pending-verification' -or
           [int64]$j.revision -ne 6 -or
           [string]$j.entry.entry_sha256 -cne [string]$r.pending_journal_sha256 -or
           [string]$j.entry.previous_entry_sha256 -cne [string]$r.native_start_journal_sha256 -or
           [string]$j.entry.transaction_id -cne $JournalTransactionId -or
           [string]$j.entry.name -cne 'tagify' -or
           [string]$j.entry.consumption_id -cne [string]$r.consumption_id -or
           [string]$j.entry.source_identity -cne [string]$r.source_identity -or
           [string]$j.entry.remote_commit_sha -cne [string]$r.remote_commit_sha -or
           [string]$j.entry.finalization_fingerprint -cne [string]$r.finalization_fingerprint -or
           [string]$j.entry.apply_result_fingerprint -cne ('0'*64)){
            throw 'native-receipt-pending-journal-or-unverified-result-drift'
        }
        # This evidence is independently reloaded from the original
        # immutable PRE-mutating V010 record, not received in process memory.
        $ev=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedTransactionId $JournalTransactionId
        if(-not[bool]$ev.ok -or -not[bool]$ev.reloaded_from_persistent_store -or
           [string]$ev.envelope.stage_tree_sha256 -cne [string]$r.source_tree_sha256 -or
           [string]$ev.envelope.consumption_id -cne [string]$r.consumption_id -or
           [string]$ev.envelope.source_identity -cne [string]$r.source_identity -or
           [string]$ev.envelope.remote_commit_sha -cne [string]$r.remote_commit_sha -or
           [string]$ev.envelope.live_path -cne [string]$j.entry.live_path -or
           [string]$ev.envelope.transaction_root -cne [string]$j.entry.transaction_root){
            throw 'native-receipt-immutable-pre-mutation-evidence-drift'
        }
        $live=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath ([string]$j.entry.live_path)
        if(-not[bool]$live.safe -or -not[bool]$live.installable -or
           [string]$live.tree_sha256 -cne [string]$r.source_tree_sha256){
            throw 'native-receipt-current-live-whole-tree-unexpected-change'
        }
        $old=Join-Path ([string]$j.entry.transaction_root) 'old-live'
        if(-not[IO.Directory]::Exists($old) -or
           -not[IO.Directory]::Exists([string]$j.entry.app_backup_path) -or
           -not[IO.Directory]::Exists([string]$j.entry.persistence_backup_path) -or
           -not[IO.Directory]::Exists([string]$j.entry.stage_workspace_path)){
            throw 'native-pending-original-rollback-files-not-retained'
        }
        return [pscustomobject]@{ok=$true;reason='real-vendor-success-pending-independent-reverification'
            receipt=$r;journal=$j;recovery=$ev;source_tree_sha256=[string]$live.tree_sha256
            production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('real-native-pending-admission-denied:'+[string]$_.Exception.Message)}
}
function Save-CustomAppRealNativePendingSealV025 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId,
          [Parameter(Mandatory=$true)][string]$ReceiptFingerprint)
    $proof=Test-CustomAppRealNativePendingReceiptBindingV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -ReceiptFingerprint $ReceiptFingerprint
    if(-not[bool]$proof.ok){throw ('real-native-pending-seal-preflight-failed:'+[string]$proof.reason)}
    $r=$proof.receipt
    $record=[ordered]@{
        schema=1;managed_by='scoped-official-native-pending-dpapi-v025'
        journal_transaction_id=$JournalTransactionId
        receipt_fingerprint=$ReceiptFingerprint
        pending_journal_sha256=[string]$r.pending_journal_sha256
        native_start_journal_sha256=[string]$r.native_start_journal_sha256
        consumption_id=[string]$r.consumption_id
        source_tree_sha256=[string]$r.source_tree_sha256
        target_sha256=[string]$r.private_target_sha256
        source_identity=[string]$r.source_identity
        remote_commit_sha=[string]$r.remote_commit_sha
    }
    $path=Get-CustomAppRealNativePendingPathV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $raw=[Text.Encoding]::UTF8.GetBytes(($record|ConvertTo-Json -Compress -Depth 6))
    try{
        $cipher=[Security.Cryptography.ProtectedData]::Protect(
            $raw,(Get-CustomAppRealNativePendingEntropyV025 -JournalTransactionId $JournalTransactionId),
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }finally{[Array]::Clear($raw,0,$raw.Length)}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$digest=$sha.ComputeHash($cipher)}finally{$sha.Dispose()}
    $sealed=New-Object byte[] ($cipher.Length+32)
    [Array]::Copy($digest,0,$sealed,0,32)
    [Array]::Copy($cipher,0,$sealed,32,$cipher.Length)
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($sealed,0,$sealed.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    $reloaded=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId
    if(-not[bool]$reloaded.ok){throw ('native-dpapi-seal-durable-readback-invalid:'+[string]$reloaded.reason)}
    return [pscustomobject]@{
        ok=$true;path=$path;pending_journal_sha256=[string]$r.pending_journal_sha256
        receipt_fingerprint=$ReceiptFingerprint;production_execution_authorized=$false
        production_mutation_authorized=$false}
}
function Read-CustomAppRealNativePendingSealV025 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId)
    Assert-CustomAppRealNativePendingHostedV025
    $deny={param($why)[pscustomobject]@{ok=$false;reason=[string]$why
       production_execution_authorized=$false;production_mutation_authorized=$false}}
    try{
        $path=Get-CustomAppRealNativePendingPathV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -RequireExisting:$true
        $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           $file.Length -lt 160 -or $file.Length -gt 16384){
            throw 'native-pending-dpapi-cipher-size-or-reparse-denied'
        }
        $sealed=[IO.File]::ReadAllBytes($path)
        if($sealed.Length -ne $file.Length){throw 'native-pending-dpapi-cipher-length-raced'}
        $cipher=New-Object byte[] ($sealed.Length-32)
        [Array]::Copy($sealed,32,$cipher,0,$cipher.Length)
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$digest=$sha.ComputeHash($cipher)}finally{$sha.Dispose()}
        for($i=0;$i -lt 32;$i++){
            if($digest[$i] -ne $sealed[$i]){throw 'native-pending-dpapi-entire-ciphertext-digest-mismatch'}
        }
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $raw=$null
        try{
            $raw=[Security.Cryptography.ProtectedData]::Unprotect(
                $cipher,(Get-CustomAppRealNativePendingEntropyV025 -JournalTransactionId $JournalTransactionId),
                [Security.Cryptography.DataProtectionScope]::CurrentUser)
            $r=[Text.Encoding]::UTF8.GetString($raw)|ConvertFrom-Json -ErrorAction Stop
        }finally{if($null-ne$raw){[Array]::Clear($raw,0,$raw.Length)}}
        if([int]$r.schema -ne 1 -or
           [string]$r.managed_by -cne 'scoped-official-native-pending-dpapi-v025' -or
           [string]$r.journal_transaction_id -cne $JournalTransactionId -or
           [string]$r.receipt_fingerprint -cnotmatch '^[0-9a-f]{64}$'){
            throw 'native-pending-dpapi-receipt-identity-invalid'
        }
        $proof=Test-CustomAppRealNativePendingReceiptBindingV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -ReceiptFingerprint ([string]$r.receipt_fingerprint)
        if(-not[bool]$proof.ok){throw ('native-pending-dpapi-current-live-journal-denied:'+[string]$proof.reason)}
        $v=$proof.receipt
        foreach($pair in @(
          @('pending_journal_sha256',[string]$v.pending_journal_sha256),
          @('native_start_journal_sha256',[string]$v.native_start_journal_sha256),
          @('consumption_id',[string]$v.consumption_id),
          @('source_tree_sha256',[string]$v.source_tree_sha256),
          @('target_sha256',[string]$v.private_target_sha256),
          @('source_identity',[string]$v.source_identity),
          @('remote_commit_sha',[string]$v.remote_commit_sha)
        )){
            $key=[string]$pair[0];$expected=[string]$pair[1]
            if([string]$r.$key -cne $expected){
                throw ('native-pending-dpapi-hmac-qualified-binding-drift-'+$key)
            }
        }
        return [pscustomobject]@{
            ok=$true;reason='DPAPI-CurrentUser-authenticated-pending-official-success'
            receipt_fingerprint=[string]$r.receipt_fingerprint
            journal_transaction_id=$JournalTransactionId
            source_tree_sha256=[string]$r.source_tree_sha256
            pending_journal_sha256=[string]$r.pending_journal_sha256
            current_journal_revision=[int64]$proof.journal.revision
            current_journal_entry_sha256=[string]$proof.journal.entry.entry_sha256
            finalization_fingerprint=[string]$proof.journal.entry.finalization_fingerprint
            production_execution_authorized=$false;production_mutation_authorized=$false
        }
    }catch{return & $deny ('real-native-pending-dpapi-read-denied:'+[string]$_.Exception.Message)}
}
function Complete-CustomAppRealNativePendingResumeV025 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId)
    $p=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId
    if(-not[bool]$p.ok){throw ('real-native-pending-independent-resume-rejected:'+[string]$p.reason)}
    $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory
    if(-not[bool]$j.ok -or [int64]$j.revision -ne [int64]$p.current_journal_revision -or
       [string]$j.entry.entry_sha256 -cne [string]$p.pending_journal_sha256 -or
       [string]$j.entry.phase -cne 'apply-returned-success-pending-verification'){
        throw 'real-native-pending-journal-raced-since-DPAPI-readback'
    }
    $at=[DateTimeOffset]::UtcNow
    $prior=[DateTimeOffset]::Parse([string]$j.entry.recorded_at)
    if($at -le $prior){$at=$prior.AddMilliseconds(2)}
    $append=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedRevision ([int64]$j.revision) -ExpectedEntrySha256 ([string]$j.entry.entry_sha256) -Phase 'apply-verified' -FinalizationFingerprint ([string]$p.finalization_fingerprint) -ApplyResultFingerprint ([string]$p.receipt_fingerprint) -Now $at
    if(-not[bool]$append.ok -or -not[bool]$append.persisted -or
       -not[bool]$append.read_after_write_verified){
        throw ('real-native-pending-journal-CAS-rejected:'+[string]$append.reason)
    }
    $verified=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -ExpectedApplyFingerprint ([string]$p.receipt_fingerprint)
    if(-not[bool]$verified.ok){throw 'real-native-pending-post-CAS-independent-XPUI-readback-invalid'}
    Write-Host 'REAL_NATIVE_V025_FRESH_PROCESS_DPAPI_PENDING_TO_APPLY_VERIFIED_CAS_PASS'
    return [pscustomobject]@{
        ok=$true;reason='fresh-process-official-vendor-success-journaled-no-reapply'
        journal_entry_sha256=[string]$append.entry.entry_sha256
        receipt_fingerprint=[string]$p.receipt_fingerprint
        fresh_process=$true;official_vendor_invocations=0
        production_execution_authorized=$false;production_mutation_authorized=$false}
}
