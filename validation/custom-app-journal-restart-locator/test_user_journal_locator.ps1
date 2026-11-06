param([ValidateSet('bootstrap','restart')][string]$Phase='bootstrap')
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
    throw 'USER_JOURNAL_LOCATOR_TEST_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $repo 'validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1')
. (Join-Path $PSScriptRoot 'user-journal-locator.ps1')
$root=Join-Path $env:RUNNER_TEMP ('journal-locator-hosted-'+$env:GITHUB_RUN_ID)
$live=Join-Path $root 'live-tagify'
$private=Join-Path $root 'private'
$journal=Join-Path $root 'signed-journal-location'
$cid=('a'*64);$tid=('b'*64);$nonce=('c'*32)
function Assert-Blocked([scriptblock]$Call,[string]$Label) {
    $failed=$false
    try{& $Call|Out-Null}catch{$failed=$true}
    if(-not $failed){throw ('USER_LOCATOR_FAIL_OPEN_'+$Label)}
}
if($Phase -eq 'bootstrap'){
    if(Test-Path -LiteralPath $root){throw 'BOOTSTRAP_FIXTURE_ALREADY_EXISTS'}
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory($private)
    [void][IO.Directory]::CreateDirectory($live)
    $s=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $private -Initialize
    try{
        Assert-Blocked {Read-CustomAppUserTxnJournalLocatorV010 -Session $s} 'unreserved_locator_read'
        [void](Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $cid -TransactionId $tid -Nonce $nonce)
        Assert-Blocked {Read-CustomAppUserTxnJournalLocatorV010 -Session $s} 'unbound_active_locator_read'
        Assert-Blocked {Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $root -JournalStoreDirectory (Join-Path $live 'not-permitted')} 'journal_inside_live'
        Assert-Blocked {Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $root -JournalStoreDirectory 'C:\Windows'} 'unrelated_store'
        $first=Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $root -JournalStoreDirectory $journal
        if(-not [bool]$first.ok -or -not [bool]$first.first_binding -or [bool]$first.production_mutation_authorized){
            throw 'FIRST_BINDING_FAILED_OR_GRANTED_AUTHORITY'
        }
        $locator=Get-CustomAppUserTxnJournalLocatorFileV010 -Session $s
        $blob=[IO.File]::ReadAllBytes($locator)
        if($blob.Length -lt 64 -or [Text.Encoding]::UTF8.GetString($blob).Contains($journal)){
            throw 'LOCATOR_NOT_DPAPI_ENCRYPTED'
        }
        $repeat=Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $root -JournalStoreDirectory $journal
        if(-not [bool]$repeat.already_bound -or [bool]$repeat.first_binding){throw 'IDEMPOTENT_SAME_BINDING_FAILED'}
        Assert-Blocked {Bind-CustomAppUserTxnJournalLocatorV010 -Session $s -AllowedRoot $root -JournalStoreDirectory (Join-Path $root 'other-journal')} 'rebind_alternate_directory'
        if((Get-FileHash $locator -Algorithm SHA256).Hash -cne ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($blob))).Replace('-','')){
            throw 'REBOUND_JOURNAL_LOCATOR_CHANGED'
        }
        if([IO.Directory]::Exists($journal)){throw 'BINDING_MUST_PRECEDE_REAL_JOURNAL_CREATION'}
        Write-Host 'USER_JOURNAL_LOCATOR_FRESH_BIND_PASS first_bind_before_swap=true no_side_effects=true encrypted=true same_bind_idempotent=true alternate_path_rejected=true'
    }finally{$s.lock_handle.Dispose()}
}else{
    $s=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $private
    try{
        $r=Read-CustomAppUserTxnJournalLocatorV010 -Session $s
        if(-not[bool]$r.ok -or [bool]$r.journal_evidence_verified -or [bool]$r.production_mutation_authorized -or
           [string]$r.record.allowed_root -cne $root -or [string]$r.record.store_directory -cne $journal -or
           [string]$r.record.transaction_id -cne $tid -or [string]$r.record.consumption_id -cne $cid -or
           [string]$r.record.nonce -cne $nonce){
            throw 'FRESH_PROCESS_LOCATOR_NOT_BOUND_TO_TRIPLE_ID'
        }
        $file=Get-CustomAppUserTxnJournalLocatorFileV010 -Session $s
        $original=[IO.File]::ReadAllBytes($file)
        $corrupt=[byte[]]$original.Clone()
        $corrupt[[Math]::Min(15,$corrupt.Length-1)]=[byte]($corrupt[[Math]::Min(15,$corrupt.Length-1)] -bxor 1)
        [IO.File]::WriteAllBytes($file,$corrupt)
        Assert-Blocked {Read-CustomAppUserTxnJournalLocatorV010 -Session $s} 'dpapi_tamper'
        [IO.File]::WriteAllBytes($file,$original)
        [IO.File]::Delete($file)
        Assert-Blocked {Read-CustomAppUserTxnJournalLocatorV010 -Session $s} 'missing_locator'
        [IO.File]::WriteAllBytes($file,$original)
        if(-not [bool](Read-CustomAppUserTxnJournalLocatorV010 -Session $s).ok){throw 'RESTORED_ENCRYPTED_RECEIPT_INVALID'}
        if($null -eq $s.state.active -or [long]$s.state.revision -ne 1){throw 'TAMPER_ALTERED_CANONICAL_STATE'}
        Write-Host 'USER_JOURNAL_LOCATOR_FRESH_PROCESS_PASS active_persisted=true exact_paths_recovered=true tamper_denied=true missing_denied=true no_auto_release=true'
    }finally{$s.lock_handle.Dispose()}
}
