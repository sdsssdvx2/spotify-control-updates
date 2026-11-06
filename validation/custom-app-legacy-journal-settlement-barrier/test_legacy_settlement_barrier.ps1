param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'LEGACY_SETTLEMENT_WINDOWS_TEST_HOSTED_RUNNER_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1')
. (Join-Path $repo 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $PSScriptRoot 'legacy-settlement-barrier.ps1')
function Must-Deny([scriptblock]$Body,[string]$Reason,[string]$Label) {
    $denied=$false
    try{& $Body|Out-Null}catch{
        if([string]$_.Exception.Message -match [regex]::Escape($Reason)){$denied=$true}
        else{throw ('WRONG_DENIAL_'+$Label+': '+[string]$_.Exception.Message)}
    }
    if(-not $denied){throw ('FAIL_OPEN_'+$Label)}
}
$root=Join-Path $env:RUNNER_TEMP ('legacy-settlement-two-way-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
try{
    $preflight=Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root
    if(-not[bool]$preflight.ok -or [bool]$preflight.safe_to_enroll -or -not[bool]$preflight.requires_cross_engine_lock_before_enrollment -or [bool]$preflight.production_mutation_authorized){
        throw 'NEW_JOURNAL_PREFLIGHT_UNSAFELY_GRANTED_ENROLLMENT'
    }
    $dir=Join-Path $root 'SpotifyControl'
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    $ledger=Join-Path $dir 'addon-last-transaction.json'
    $payload=[Text.Encoding]::UTF8.GetBytes('{"schema":2,"status":"awaiting-apply","test":"mock-existing-legacy-only"}')
    [IO.File]::WriteAllBytes($ledger,$payload)
    Must-Deny { Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root } 'new-journal-legacy-preflight-unresolved-legacy-transaction-must-finish-first' 'awaiting_apply'
    $after=[IO.File]::ReadAllBytes($ledger)
    if($after.Length -ne $payload.Length){throw 'NEW_JOURNAL_PREFLIGHT_CHANGED_OLD_LEDGER_SIZE'}
    for($i=0;$i -lt $after.Length;$i++){if($after[$i] -ne $payload[$i]){throw 'NEW_JOURNAL_PREFLIGHT_MODIFIED_OLD_LEDGER'}}
    Must-Deny { Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root -TransactionPath (Join-Path $root 'wrong.json') } 'new-journal-legacy-preflight-ledger-path-not-canonical' 'ledger_alias'
    [IO.File]::Delete($ledger)
    [IO.Directory]::CreateDirectory($ledger)|Out-Null
    Must-Deny { Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root } 'new-journal-legacy-preflight-unresolved-legacy-transaction-must-finish-first' 'directory_object'
    [IO.Directory]::Delete($ledger)
    Must-Deny { Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot 'C:\Windows' } 'new-journal-legacy-preflight-root-outside-hosted-runner' 'unrelated_profile'
    $preflight=Assert-CustomAppNewJournalLegacyLedgerClosedV011 -LocalAppDataRoot $root
    if(-not[bool]$preflight.ok -or [bool]$preflight.safe_to_enroll){throw 'PREFLIGHT_GRANTED_UNLOCKED_NEW_ENROLLMENT'}
    Write-Host 'TWO_WAY_LEGACY_NEW_ENGINE_PREFLIGHT_MATRIX_PASS active_legacy_denied=true malformed_ledger_denied=true canonical_path_required=true legacy_bytes_unchanged=true no_enrollment_authority=true'
}finally{
    if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
}
# Actually execute CommitLast, RollbackLast, Update in generated Addon
# Manager. An intentionally invalid old ledger proves the exclusive gate
# fires BEFORE any old parse, rollback, fingerprint or persistence mutation.
$actualRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$enrolled=Join-Path $actualRoot 'SpotifyControlUpdates-CustomApp-State'
$ledgerDir=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
$ledger=Join-Path $ledgerDir 'addon-last-transaction.json'
if([IO.Directory]::Exists($enrolled) -or [IO.File]::Exists($enrolled) -or [IO.File]::Exists($ledger) -or [IO.Directory]::Exists($ledger)){
    throw 'HOSTED_WINDOWS_TEST_WOULD_OVERWRITE_EXISTING_TRANSACTION_STATE'
}
[IO.Directory]::CreateDirectory($enrolled)|Out-Null
[IO.Directory]::CreateDirectory($ledgerDir)|Out-Null
$original=[Text.Encoding]::UTF8.GetBytes('garbled-incomplete-old-ledger-must-not-be-touched')
[IO.File]::WriteAllBytes($ledger,$original)
try{
    $expected='normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
    $source=(Resolve-Path $CandidatePath).Path
    foreach($action in @('CommitLast','RollbackLast','Update')){
        $std=Join-Path $env:RUNNER_TEMP ('legacy-settlement-'+$action+'-'+[Guid]::NewGuid().ToString('N')+'.log')
        $ErrorActionPreference='Continue'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $source -Action $action -Force *>&1 | Tee-Object -FilePath $std|Out-Null
        $exitCode=$LASTEXITCODE
        $ErrorActionPreference='Stop'
        if($exitCode -eq 0){throw ('REAL_ACTION_BYPASSED_TWO_WAY_BARRIER_'+$action)}
        $errorFile=Join-Path $ledgerDir 'logs\addons-error.log'
        if(-not[IO.File]::Exists($errorFile) -or -not([IO.File]::ReadAllText($errorFile).Contains($expected))){
            throw ('REAL_ACTION_BLOCKED_FOR_WRONG_REASON_'+$action)
        }
        if(-not[IO.File]::Exists($ledger)){throw ('OLD_LEDGER_DELETED_'+$action)}
        $actual=[IO.File]::ReadAllBytes($ledger)
        if($actual.Length -ne $original.Length){throw ('LEGACY_LEDGER_SIZE_CHANGED_'+$action)}
        for($i=0;$i -lt $original.Length;$i++){if($actual[$i] -ne $original[$i]){throw ('LEGACY_LEDGER_BYTES_CHANGED_'+$action)}}
        if(-not[IO.Directory]::Exists($enrolled)){throw ('NEW_JOURNAL_ENROLLMENT_DELETED_'+$action)}
        Write-Host ('ACTUAL_TWO_WAY_LEGACY_ENTRYPOINT_DENIED_PASS action='+$action+' ledger_unchanged=true')
    }
    Write-Host 'ACTUAL_COMMITLAST_ROLLBACKLAST_UPDATE_FORCE_TWO_WAY_BARRIER_PASS read_only=true no_old_ledger_parse=true no_mutation_authority=true'
}finally{
    [IO.File]::Delete($ledger)
    [IO.Directory]::Delete($enrolled)
}
