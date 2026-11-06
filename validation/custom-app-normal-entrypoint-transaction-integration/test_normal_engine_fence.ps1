param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'NORMAL_UPDATE_FENCE_TEST_HOSTED_WINDOWS_ONLY'
}
. (Join-Path $PSScriptRoot 'normal-update-engine-fence.ps1')
function Must-Deny([scriptblock]$Body,[string]$Label,[string]$Reason) {
    $denied=$false
    try{& $Body | Out-Null}catch{
        if([string]$_.Exception.Message -match [regex]::Escape($Reason)){$denied=$true}
        else{throw ('WRONG_DENIAL_REASON '+$Label+' '+[string]$_.Exception.Message)}
    }
    if(-not$denied){throw ('FAIL_OPEN '+$Label)}
}
$root=Join-Path $env:RUNNER_TEMP ('normal-update-old-new-fence-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$allow=Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $root
if($null-eq$allow -or -not[bool]$allow.ok -or [string]$allow.engine -cne 'legacy' -or
   [bool]$allow.production_mutation_authorized -or [bool]$allow.result_is_authority){
    throw 'BACKCOMPAT_UNENROLLED_USER_WAS_DENIED_OR_GRANTED_AUTHORITY'
}
$enrolled=Join-Path $root 'SpotifyControlUpdates-CustomApp-State'
if(Test-Path -LiteralPath $enrolled){throw 'READ_ONLY_PREFLIGHT_CREATED_TRANSACTION_STORE'}
$reason='normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
[IO.Directory]::CreateDirectory($enrolled)|Out-Null
Must-Deny {Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $root} 'directory-enrollment' $reason
if(-not[IO.Directory]::Exists($enrolled)){throw 'DENIAL_MUTATED_ENROLLED_STORE'}
[IO.Directory]::Delete($enrolled)
[IO.File]::WriteAllText($enrolled,'malformed-old-enrollment-must-block',([Text.UTF8Encoding]::new($false)))
Must-Deny {Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $root} 'file-enrollment' $reason
if(-not[IO.File]::Exists($enrolled)){throw 'DENIAL_DELETED_MALFORMED_STORE'}
[IO.File]::Delete($enrolled)
Must-Deny {Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot 'C:\Windows'} 'arbitrary-test-root' 'normal-update-engine-gate-test-root-outside-runner'
$again=Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $root
if(-not[bool]$again.ok -or (Test-Path -LiteralPath $enrolled)){throw 'NORMAL_UPDATE_FENCE_NOT_READ_ONLY_AND_REENTRANT'}
Write-Host 'NORMAL_UPDATE_FENCE_DIRECT_WINDOWS_MATRIX_PASS unenrolled_legacy_preserved=true enrolled_directory_denied=true malformed_enrollment_file_denied=true arbitrary_test_root_denied=true read_only=true'

# The *actual generated* Addon Manager must deny -Action Update before
# old rollback, Spotify persistence backup, source discovery or live rename.
# Here the disposable hosted runner's actual per-user LocalAppData is used,
# never the user's machine, and the store does not include any real secrets.
$actualRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if(-not[IO.Directory]::Exists($actualRoot)){throw 'HOSTED_LOCAL_APPDATA_MISSING'}
$actualEnrollment=Join-Path $actualRoot 'SpotifyControlUpdates-CustomApp-State'
if(Test-Path -LiteralPath $actualEnrollment){throw 'HOSTED_RUNNER_ALREADY_HAS_USER_STORE_FAIL_CLOSED'}
[IO.Directory]::CreateDirectory($actualEnrollment)|Out-Null
try{
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $CandidatePath).Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'CANDIDATE_WINPS51_PARSE_FAILED'}
    $funcs=@($ast.FindAll({
        param($n)
        $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -ceq 'Update-AutoApps'
    },$true))
    if($funcs.Count -ne 1){throw 'NORMAL_UPDATE_REAL_HANDLER_MISSING_OR_DUPLICATE'}
    $s=[string]$funcs[0].Extent.Text
    $check='Assert-CustomAppNormalUpdateEngineExclusivityV010'
    if($s.IndexOf($check,[StringComparison]::Ordinal) -lt 0 -or
       $s.IndexOf($check,[StringComparison]::Ordinal) -gt $s.IndexOf('Rollback-LastTransaction',[StringComparison]::Ordinal) -or
       $s.IndexOf($check,[StringComparison]::Ordinal) -gt $s.IndexOf('Backup-SpotifyWebData',[StringComparison]::Ordinal) -or
       $s.IndexOf($check,[StringComparison]::Ordinal) -gt $s.IndexOf('Get-AddonInventory',[StringComparison]::Ordinal) -or
       $s.IndexOf($check,[StringComparison]::Ordinal) -gt $s.IndexOf('Invoke-AtomicDirectorySwap',[StringComparison]::Ordinal)){
        throw 'NORMAL_UPDATE_FENCE_AFTER_LEGACY_MUTATION'
    }
    $outputFile=Join-Path $root 'actual-update-enrolled-denial.log'
    $ErrorActionPreference='Continue'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Resolve-Path $CandidatePath).Path -Action Update -Force *>&1 |
        Tee-Object -FilePath $outputFile | Out-Null
    $exitCode=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($exitCode -eq 0){throw 'ACTUAL_NORMAL_ACTION_UPDATE_BYPASSED_USER_STORE'}
    $log=Join-Path (Join-Path $actualRoot 'SpotifyControl\logs') 'addons-error.log'
    if(-not[IO.File]::Exists($log)){throw 'ACTUAL_UPDATE_FAILED_WITHOUT_ERROR_REPORT'}
    $errorText=[IO.File]::ReadAllText($log)
    if(-not $errorText.Contains($reason)){throw 'ACTUAL_UPDATE_DENIAL_WRONG_REASON'}
    $legacyLedger=Join-Path $actualRoot 'SpotifyControl\addon-last-transaction.json'
    if([IO.File]::Exists($legacyLedger)){throw 'ACTUAL_UPDATE_CREATED_OLD_MUTATION_LEDGER_AFTER_GATE'}
    if(-not[IO.Directory]::Exists($actualEnrollment)){throw 'NORMAL_ACTION_CHANGED_NEW_ENROLLMENT'}
    Write-Host 'NORMAL_UPDATE_FENCE_ACTUAL_ACTION_UPDATE_DENIED_PASS Force_cannot_bypass=true before_legacy_rollback=true before_backup=true before_remote=true before_swap=true'
}finally{
    if([IO.Directory]::Exists($actualEnrollment)){[IO.Directory]::Delete($actualEnrollment)}
}
Write-Host 'ACTUAL_NORMAL_ADDON_ENTRYPOINT_COMPATIBILITY_BARRIER_E2E_PASS installed_Spotify_untouched=true legacy_transactions_preserved=true normal_production_mutation_disabled=true'
