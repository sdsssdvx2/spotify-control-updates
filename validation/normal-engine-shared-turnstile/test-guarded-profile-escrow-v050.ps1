# V050 targeted hosted acceptance of real-profile-capable backup-only path.
# Runs against the V048 exact synthetic installed profile, never real Spotify.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
  throw 'V050_TEST_NOT_HOSTED_WINDOWS'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'test-installed-manifest-audit-v048.ps1')
. (Join-Path $PSScriptRoot 'guarded-profile-escrow-v050.ps1')
function Assert-V050([bool]$ok,[string]$reason){if(-not$ok){throw ('V050_TEST_'+$reason)}}
$fixtureArgs=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli}
$additional=Join-Path $xpui 'v050-scale-assets'
[IO.Directory]::CreateDirectory($additional)|Out-Null
[byte[]]$sample=New-Object byte[] 16384
for($i=1;$i -le 609;$i++){
  [IO.File]::WriteAllBytes((Join-Path $additional ('asset-{0:D4}.dat' -f $i)),$sample)
}
$origProfile=Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs
Assert-V050 ($origProfile.status -ceq 'observed-readonly') 'CUTOVER_AFTER_610_FILES_NOT_ADMITTED'
$pin=[string]$origProfile.profile_sha256
$before=@{
  xpui=(Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256
  ivlyrics=(Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256
  better=(Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'better-local-files')).tree_sha256
  eternal=(Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'eternal-jukebox')).tree_sha256
  state=(Get-FileHash -LiteralPath $state -Algorithm SHA256).Hash
  prefs=(Get-FileHash -LiteralPath $prefs -Algorithm SHA256).Hash
  config=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
  unmanaged=(Get-FileHash -LiteralPath $unknown -Algorithm SHA256).Hash
  foreign=(Get-FileHash -LiteralPath $foreign -Algorithm SHA256).Hash
}
Assert-V050 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).file_count -eq 610) 'SCALE_COUNT_NOT_610'
$escrow=Join-Path $env:RUNNER_TEMP ('v050-private-escrow-'+[Guid]::NewGuid().ToString('N'))
$lease=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $pin @fixtureArgs
try{
  $blocked=$false
  try{[void](New-CustomAppProfilePreimageEscrowV050 -CutoverLease $lease -ExpectedProfileSha256 $pin -HostedEscrowRoot $escrow @fixtureArgs)}
  catch{if([string]$_.Exception.Message -ceq 'V050_EXPLICIT_BACKUP_APPROVAL_OR_WINDOWS_REQUIRED'){$blocked=$true}else{throw}}
  Assert-V050 ($blocked -and -not(Test-Path $escrow)) 'BACKUP_WITHOUT_EXPLICIT_OPT_IN_ALLOWED'
  $args=@{
    CutoverLease=$lease;ExpectedProfileSha256=$pin;ExplicitBackupAuthorization=$true
    HostedEscrowRoot=$escrow;HostedFixtureRoot=$root;HostedFixtureCliPath=$cli
  }
  $created=New-CustomAppProfilePreimageEscrowV050 @args
  Assert-V050 ($created.status -ceq 'durable-private-backup-only' -and
    [string]$created.escrow_id -cmatch '^[a-f0-9]{32}$' -and
    [string]$created.receipt_sha256 -cmatch '^[a-f0-9]{64}$' -and
    [int]$created.xpui_file_count -eq 610 -and
    [int]$created.approved_count -eq 3 -and
    [bool]$created.backup_private_acl_verified -and
    [bool]$created.guard_files_dpapi_sealed -and
    [bool]$created.user_originals_unchanged -and
    -not[bool]$created.live_update_authorized -and
    -not[bool]$created.production_mutation_authorized) 'ESCROW_NOT_DURABLE_BACKUP_ONLY'
  $id=[string]$created.escrow_id
  $receiptPin=[string]$created.receipt_sha256
  $verified=Join-Path $escrow ('verified-'+$id)
  Assert-V050 ((Get-Item -LiteralPath $escrow).GetAccessControl().AreAccessRulesProtected) 'ESCROW_ACL_NOT_PRIVATE'
  Assert-V050 (-not[IO.Directory]::Exists((Join-Path $escrow ('pending-'+$id)))) 'PENDING_STAGE_PUBLISHED_WRONGLY'
  foreach($key in @('prefs','config','state')){
    $protected=Join-Path $verified ('preimage\protected\'+$key+'.dpapi')
    Assert-V050 ([IO.File]::Exists($protected)) 'PROTECTED_CIPHERTEXT_MISSING'
    $bytes=[IO.File]::ReadAllBytes($protected)
    Assert-V050 ($bytes.Length -gt 64 -and
      (Get-CustomAppV050BytesHash -Data $bytes) -cne
      ($before[$key]).ToLowerInvariant()) 'PROTECTED_FILE_LOOKS_UNSEALED'
  }
  $ok=Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow
  Assert-V050 ([bool]$ok.ok -and [int]$ok.approved_count -eq 3) 'INPROCESS_COLD_RECEIPT_VERIFY_FAILED'
  Write-Host 'V050_610FILE_PRIVATE_ACL_DPAPI_CONFIG_PREFS_STATE_BACKUP_PASS'
}finally{
  if($null-ne$lease.lock_handle){$lease.lock_handle.Dispose()}
}
# Independently loaded PowerShell reads the backup without the updater's lease
# or any HMAC issuer key; it can never apply/restore/mutate originals.
$child=Join-Path $PSScriptRoot 'read-guarded-escrow-child-v050.ps1'
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -EscrowId $id -ReceiptSha256 $receiptPin -FixtureEscrowRoot $escrow 2>&1)
Assert-V050 ($LASTEXITCODE -eq 0 -and
  ($output -join [char]10).Contains('V050_FRESH_PROCESS_DPAPI_RECEIPT_XPUI_AND_APP_TREE_VERIFIED_PASS')) 'FRESH_PROCESS_DPAPI_VERIFY_FAILED'
Write-Host 'V050_SEPARATE_PROCESS_DPAPI_READER_WITHOUT_ISSUER_OR_OS_LEASE_PASS'
# The readback has no relationship to today's live profile; it must survive
# simulated post-backup user modifications without altering the originals.
[IO.File]::AppendAllText($foreign,'v050-live-drift')
$still=Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow
Assert-V050 ([bool]$still.ok) 'COLD_BACKUP_MUST_SURVIVE_LATER_ORIGINAL_CHANGE'
[IO.File]::WriteAllText($foreign,'V046_UNMANAGED_XPUI_DO_NOT_CHANGE')
Assert-V050 ((Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $before.foreign) 'FIXTURE_FOREIGN_RESTORE_FAILED'
Write-Host 'V050_BACKUP_INDEPENDENT_OF_LATER_LIVE_FILE_CHANGES_PASS'
# Tamper denial, then restore ONLY synthetic escrow bytes.
$file=Join-Path $verified 'preimage\trees\ivlyrics\index.js'
$old=[IO.File]::ReadAllBytes($file)
[IO.File]::AppendAllText($file,'attacker')
$bad=Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow
Assert-V050 (-not[bool]$bad.ok -and -not[bool]$bad.production_mutation_authorized) 'TAMPERED_APP_ACCEPTED'
[IO.File]::WriteAllBytes($file,$old)
$cipherPath=Join-Path $verified 'preimage\protected\prefs.dpapi'
$old=[IO.File]::ReadAllBytes($cipherPath)
[IO.File]::AppendAllText($cipherPath,'tamper')
$bad=Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow
Assert-V050 (-not[bool]$bad.ok) 'TAMPERED_PREFS_ACCEPTED'
[IO.File]::WriteAllBytes($cipherPath,$old)
$receiptPath=Join-Path $verified 'receipt.dpapi'
$old=[IO.File]::ReadAllBytes($receiptPath)
[IO.File]::AppendAllText($receiptPath,'tamper')
$bad=Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow
Assert-V050 (-not[bool]$bad.ok) 'TAMPERED_RECEIPT_ACCEPTED'
[IO.File]::WriteAllBytes($receiptPath,$old)
Assert-V050 ([bool](Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow).ok) 'CLEAN_BACKUP_NOT_REVERIFIABLE'
Write-Host 'V050_APP_TREE_PREFS_CIPHERTEXT_AND_RECEIPT_TAMPER_DENIAL_PASS'
# An unsettled older transaction blocks a second snapshot even while lock
# is held. No second backup vault is created before preflight.
$next=Join-Path $env:RUNNER_TEMP ('v050-should-not-exist-'+[Guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($pending,'{"state":"unsettled"}')
$lease2=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $pin @fixtureArgs
# Open must fail on pending journal, and may not reserve any new vault.
throw 'V050_PENDING_TRANSACTION_WAS_WRONGLY_ADMITTED'
