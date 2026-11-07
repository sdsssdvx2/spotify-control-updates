# V024 real vendor scoped receipt: deliberately distinct from legacy fake apply.
# Its fingerprint, not a forged old-schema result, anchors V010 apply-verified.
function Get-CustomAppRealNativeReceiptMaterialV024 {
    param([Parameter(Mandatory=$true)]$Receipt)
    $fields=@('schema','managed_by','name','journal_transaction_id',
      'consumption_id','source_identity','remote_commit_sha','source_tree_sha256',
      'official_binary_sha256','private_native_root','private_target_path',
      'private_target_sha256','native_start_journal_sha256','pending_journal_sha256',
      'finalization_fingerprint','native_started_at','native_finished_at',
      'native_exit_code','vendor_scoped_refresh','nontarget_unchanged',
      'live_tree_unchanged','requires_new_permit',
      'production_execution_authorized','production_mutation_authorized')
    return (($fields|ForEach-Object{[string]$Receipt.$_}) -join [Environment]::NewLine)
}
function Test-CustomAppRealNativeReceiptV024 {
    param([AllowNull()]$Receipt)
    $deny={param($why)[pscustomobject]@{ok=$false;reason=$why}}
    if($null-eq$Receipt){return & $deny 'native-receipt-null'}
    foreach($f in @('schema','managed_by','name','journal_transaction_id',
       'consumption_id','source_identity','remote_commit_sha','source_tree_sha256',
       'official_binary_sha256','private_native_root','private_target_path',
       'private_target_sha256','native_start_journal_sha256','pending_journal_sha256',
       'finalization_fingerprint','native_started_at','native_finished_at',
       'native_exit_code','vendor_scoped_refresh','nontarget_unchanged',
       'live_tree_unchanged','requires_new_permit',
       'production_execution_authorized','production_mutation_authorized','fingerprint')){
        if(-not$Receipt.PSObject.Properties[$f]){return & $deny ('native-receipt-field-missing-'+$f)}
    }
    if([int]$Receipt.schema -ne 1 -or
       [string]$Receipt.managed_by -cne 'real-vendor-scoped-native-receipt-v024' -or
       [string]$Receipt.name -cne 'tagify' -or
       [string]$Receipt.official_binary_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db' -or
       [int]$Receipt.native_exit_code -ne 0 -or
       -not[bool]$Receipt.vendor_scoped_refresh -or
       -not[bool]$Receipt.nontarget_unchanged -or -not[bool]$Receipt.live_tree_unchanged -or
       -not[bool]$Receipt.requires_new_permit -or
       [bool]$Receipt.production_execution_authorized -or [bool]$Receipt.production_mutation_authorized){
        return & $deny 'native-receipt-scope-or-authority-invalid'
    }
    foreach($field in @('journal_transaction_id','consumption_id','source_tree_sha256',
      'official_binary_sha256','private_target_sha256','native_start_journal_sha256',
      'pending_journal_sha256','finalization_fingerprint','fingerprint')){
        if(([string]$Receipt.$field) -cnotmatch '^[a-f0-9]{64}$'){
            return & $deny ('native-receipt-hash-invalid-'+$field)
        }
    }
    if(([string]$Receipt.remote_commit_sha) -cnotmatch '^[a-f0-9]{40}$'){
        return & $deny 'native-receipt-remote-commit-invalid'
    }
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Receipt.native_started_at,[ref]$start) -or
       -not[DateTimeOffset]::TryParse([string]$Receipt.native_finished_at,[ref]$end) -or
       $end -lt $start){return & $deny 'native-receipt-time-invalid'}
    $expected=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppRealNativeReceiptMaterialV024 $Receipt)
    if([string]$Receipt.fingerprint -cne $expected){return & $deny 'native-receipt-fingerprint-drift'}
    return [pscustomobject]@{ok=$true;fingerprint=$expected}
}
function Read-CustomAppRealNativeReceiptV024 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,
          [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
          [Parameter(Mandatory=$true)][string]$JournalTransactionId,
          [Parameter(Mandatory=$true)][string]$ExpectedApplyFingerprint,
          [bool]$RequireApplyVerified=$true)
    $deny={param($why)[pscustomobject]@{ok=$false;reason=$why;production_mutation_authorized=$false}}
    try{
        if($JournalTransactionId -cnotmatch '^[a-f0-9]{64}$' -or $ExpectedApplyFingerprint -cnotmatch '^[a-f0-9]{64}$'){
            throw 'native-receipt-invalid-expected-identity'
        }
        $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $JournalStoreDirectory -Label 'V024 journal store' -RequireExisting:$true
        $file=Join-Path $store ('scoped-official-native-'+$JournalTransactionId+'.json')
        [void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $file -Label 'V024 receipt' -RequireExisting:$true)
        $item=Get-Item -LiteralPath $file -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 32768){throw 'native-receipt-reparse-or-too-large'}
        $r=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
        $check=Test-CustomAppRealNativeReceiptV024 -Receipt $r
        if(-not[bool]$check.ok -or [string]$r.journal_transaction_id -cne $JournalTransactionId -or
           [string]$check.fingerprint -cne $ExpectedApplyFingerprint){throw 'native-receipt-proof-or-identity-drift'}
        $j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory
        if(-not[bool]$j.ok -or [string]$j.transaction_id -cne $JournalTransactionId -or
           [string]$j.entry.finalization_fingerprint -cne [string]$r.finalization_fingerprint){
            throw 'native-receipt-journal-binding-drift'
        }
        if($RequireApplyVerified -and
           (([string]$j.entry.phase -notin @('apply-verified','cleanup-starting','committed-clean')) -or
            [string]$j.entry.apply_result_fingerprint -cne $ExpectedApplyFingerprint)){
            throw 'native-receipt-not-yet-verified-in-journal'
        }
        $root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $private=Assert-CustomAppWholeTreeHostedPathV023 -Path ([string]$r.private_native_root) -RunnerRoot $root
        $target=Assert-CustomAppWholeTreeHostedPathV023 -Path ([string]$r.private_target_path) -RunnerRoot $root
        if(-not$target.StartsWith(($private+'\'),[StringComparison]::OrdinalIgnoreCase) -or
           -not[IO.File]::Exists($target) -or
           (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$r.private_target_sha256){
            throw 'native-receipt-official-output-bytes-changed'
        }
        return [pscustomobject]@{ok=$true;receipt=$r;fingerprint=[string]$check.fingerprint;journal=$j
            production_mutation_authorized=$false;production_execution_authorized=$false}
    }catch{return & $deny ('native-receipt-read-failed:'+[string]$_.Exception.Message)}
}
function Save-CustomAppRealNativeReceiptV024 {
    param([Parameter(Mandatory=$true)]$NativeResult,
          [Parameter(Mandatory=$true)][hashtable]$Proof,
          [Parameter(Mandatory=$true)]$StartedJournal,
          [Parameter(Mandatory=$true)]$PendingJournal)
    if(-not[bool]$NativeResult.ok -or
       -not[bool]$NativeResult.real_official_native_scoped_refresh_verified -or
       -not[bool]$NativeResult.signed_permit_and_whole_tree_bound -or
       -not[bool]$NativeResult.nontarget_unchanged -or -not[bool]$NativeResult.live_tree_unchanged -or
       [bool]$NativeResult.production_mutation_authorized -or
       [string]$NativeResult.journal_transaction_id -cne [string]$Proof.ExpectedJournalTransactionId -or
       [string]$NativeResult.native_journal_entry_sha256 -cne [string]$StartedJournal.entry.entry_sha256 -or
       [string]$NativeResult.native_vendor_executable_sha256 -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db' -or
       [string]$NativeResult.source_tree_sha256 -cne [string]$Proof.StageExecutorResult.remote_tree_sha256){
        throw 'v024-unqualified-official-native-output'
    }
    if([string]$StartedJournal.entry.phase -cne 'apply-starting' -or
       [string]$PendingJournal.entry.phase -cne 'apply-returned-success-pending-verification' -or
       [string]$StartedJournal.transaction_id -cne [string]$PendingJournal.transaction_id -or
       [string]$PendingJournal.transaction_id -cne [string]$Proof.ExpectedJournalTransactionId){
        throw 'v024-native-pending-journal-invalid'
    }
    $admission=Test-CustomAppRealNativeJournalAdmissionV024 -Proof $Proof -ExpectedPhase 'apply-returned-success-pending-verification'
    if(-not[bool]$admission.ok -or
       [string]$admission.journal_entry_sha256 -cne [string]$PendingJournal.entry.entry_sha256){
        throw 'v024-post-vendor-live-consumption-journal-drift'
    }
    $root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $private=Assert-CustomAppWholeTreeHostedPathV023 -Path $NativeResult.native_private_root -RunnerRoot $root
    $target=Assert-CustomAppWholeTreeHostedPathV023 -Path $NativeResult.native_xpui_target_path -RunnerRoot $root
    if(-not$target.StartsWith(($private+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne
       [string]$NativeResult.native_xpui_target_sha256){throw 'v024-source-XPUI-target-mismatch'}
    $r=[pscustomobject]@{
        schema=1;managed_by='real-vendor-scoped-native-receipt-v024'
        name='tagify';journal_transaction_id=[string]$PendingJournal.transaction_id
        consumption_id=[string]$NativeResult.consumption_id
        source_identity=[string]$NativeResult.source_identity
        remote_commit_sha=[string]$Proof.StageExecutorResult.remote_commit_sha
        source_tree_sha256=[string]$NativeResult.source_tree_sha256
        official_binary_sha256=[string]$NativeResult.native_vendor_executable_sha256
        private_native_root=$private;private_target_path=$target
        private_target_sha256=[string]$NativeResult.native_xpui_target_sha256
        native_start_journal_sha256=[string]$StartedJournal.entry.entry_sha256
        pending_journal_sha256=[string]$PendingJournal.entry.entry_sha256
        finalization_fingerprint=[string]$Proof.ExpectedFinalizationFingerprint
        native_started_at=[string]$NativeResult.native_started_at
        native_finished_at=[string]$NativeResult.native_finished_at
        native_exit_code=0;vendor_scoped_refresh=$true;nontarget_unchanged=$true
        live_tree_unchanged=$true;requires_new_permit=$true
        production_execution_authorized=$false;production_mutation_authorized=$false
        fingerprint=$null
    }
    $r.fingerprint=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppRealNativeReceiptMaterialV024 $r)
    if(-not[bool](Test-CustomAppRealNativeReceiptV024 $r).ok){throw 'native-receipt-self-check-failed'}
    $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $Proof.AllowedRoot -Path $Proof.JournalStoreDirectory -Label 'V024 store' -RequireExisting:$true
    $path=Join-Path $store ('scoped-official-native-'+$r.journal_transaction_id+'.json')
    [void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $Proof.AllowedRoot -Path $path -Label 'V024 result')
    Write-CustomAppProductionCrashJournalDurableFileV010 -Path $path -Text ($r|ConvertTo-Json -Depth 12 -Compress) -Mode ([IO.FileMode]::CreateNew)
    $check=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $Proof.AllowedRoot -JournalStoreDirectory $store -JournalTransactionId $r.journal_transaction_id -ExpectedApplyFingerprint $r.fingerprint -RequireApplyVerified:$false
    if(-not[bool]$check.ok){throw ('native-receipt-durable-readback-failed:'+[string]$check.reason)}
    Write-Host 'REAL_NATIVE_V024_OFFICIAL_SUCCESS_RECEIPT_DURABLE_BEFORE_APPLY_VERIFIED_PASS'
    return [pscustomobject]@{ok=$true;fingerprint=$r.fingerprint;receipt=$r;path=$path
        production_execution_authorized=$false;production_mutation_authorized=$false}
}
