# V049 targeted hosted-only backup + detached cold-restore rehearsal.
# Reuses V048 fixture, manifest, profile, lock and existing negative gates.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V049_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'test-installed-manifest-audit-v048.ps1')
. (Join-Path $PSScriptRoot 'locked-preimage-rehearsal-v049.ps1')
# Real user's earlier READ-ONLY inventory showed 610 XPUI files (under 64 MiB).
# Exercise that shape without copying any personal Spotify data.
$scaleRoot=Join-Path $xpui 'synthetic-fixture-assets'
[IO.Directory]::CreateDirectory($scaleRoot)|Out-Null
[byte[]]$fixtureBytes=New-Object byte[] 16384
for($i=1;$i -le 609;$i++){
 $leaf=('asset-{0:D4}.dat' -f $i)
 [IO.File]::WriteAllBytes((Join-Path $scaleRoot $leaf),$fixtureBytes)
}
function Assert-V049([bool]$ok,[string]$why){if(-not$ok){throw ('V049_TEST_'+$why)}}
$fixtureArgs=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli}
$admission=Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs
Assert-V049 ($admission.status -ceq 'observed-readonly') 'REUSED_PROFILE_INVALID'
$pin=[string]$admission.profile_sha256
$lease=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $pin @fixtureArgs
try{
 $out=Join-Path $env:RUNNER_TEMP ('v049-rehearsal-'+[Guid]::NewGuid().ToString('N'))
 $r=Invoke-CustomAppHostedPreimageRehearsalV049 -CutoverLease $lease -ExpectedProfileSha256 $pin -OutputDirectory $out @fixtureArgs
 Assert-V049 ($r.status -ceq 'hosted-rehearsal-preimages-verified' -and
   [int]$r.approved_apps -eq 3 -and
   [int]$r.xpui_files -eq 610 -and
   [string]$r.receipt_sha256 -cmatch '^[a-f0-9]{64}$' -and
   -not[bool]$r.production_mutation_authorized -and
   -not[bool]$r.production_backup_durable -and
   -not[bool]$r.user_spotify_modified) 'PREIMAGE_REHEARSAL_NOT_QUALIFIED'
 $ok=Test-CustomAppHostedPreimageRehearsalV049 -OutputDirectory $out -ExpectedReceiptSha256 ([string]$r.receipt_sha256)
 Assert-V049 ([bool]$ok.ok -and -not[bool]$ok.production_mutation_authorized) 'FRESH_PREIMAGE_RECHECK_FAILED'
 Write-Host 'V049_LOCKED_HOSTED_THREE_APP_XPUI_PROTECTED_STATE_PREIMAGE_COPIES_PASS'
 # New independent output proves restored bytes, not just the original
 # backed-up directory. This output is never the live source/XPUI.
 $detached=Join-Path $env:RUNNER_TEMP ('v049-detached-restore-'+[Guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($detached)|Out-Null
 $source=Join-Path $out 'preimage\xpui'
 $restored=Join-Path $detached 'xpui'
 [void](Copy-CustomAppUpdateTreeFixtureV010 -Source $source -Destination $restored -ValidationRoot $env:RUNNER_TEMP)
 Assert-V049 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $restored).tree_sha256 -ceq
   (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256) 'DETACHED_XPUI_RESTORE_MISMATCH'
 foreach($name in @('better-local-files','eternal-jukebox','ivlyrics')){
   $src=Join-Path (Join-Path $out 'preimage\approved-apps') $name
   $dst=Join-Path $detached $name
   [void](Copy-CustomAppUpdateTreeFixtureV010 -Source $src -Destination $dst -ValidationRoot $env:RUNNER_TEMP)
   Assert-V049 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $src).tree_sha256 -ceq
     (Get-CustomAppUpdateTreeSnapshotV010 -Root $dst).tree_sha256) 'DETACHED_APP_RESTORE_MISMATCH'
 }
 Write-Host 'V049_INDEPENDENT_XPUI_AND_THREE_APPROVED_APP_COLD_RESTORE_PASS'
 # Any backup corruption must stop revalidation, not be silently accepted.
 $item=Join-Path $out 'preimage\approved-apps\ivlyrics\index.js'
 $old=[IO.File]::ReadAllBytes($item)
 [IO.File]::AppendAllText($item,'V049_BACKUP_TAMPER')
 $bad=Test-CustomAppHostedPreimageRehearsalV049 -OutputDirectory $out -ExpectedReceiptSha256 ([string]$r.receipt_sha256)
 Assert-V049 (-not[bool]$bad.ok) 'TAMPERED_BACKUP_ACCEPTED'
 [IO.File]::WriteAllBytes($item,$old)
 Assert-V049 ([bool](Test-CustomAppHostedPreimageRehearsalV049 -OutputDirectory $out -ExpectedReceiptSha256 ([string]$r.receipt_sha256)).ok) 'PREIMAGE_RECHECK_NOT_RECOVERABLE'
 $collision=$false
 try{
   [void](Invoke-CustomAppHostedPreimageRehearsalV049 -CutoverLease $lease -ExpectedProfileSha256 $pin -OutputDirectory $out @fixtureArgs)
 }catch{if([string]$_.Exception.Message -ceq 'V049_OUTPUT_NOT_NEW_OR_FIXTURE_OVERLAP'){$collision=$true}else{throw}}
 Assert-V049 $collision 'REUSED_OUTPUT_NOT_REJECTED'
 Write-Host 'V049_BACKUP_TAMPER_AND_OUTPUT_COLLISION_FAIL_CLOSED_PASS'
 # A pending old journal must deny backup staging *before* creating output.
 [IO.File]::WriteAllText($pending,'{"status":"incomplete"}')
 $pendingOutput=Join-Path $env:RUNNER_TEMP ('v049-pending-'+[Guid]::NewGuid().ToString('N'))
 $blocked=$false
 try{
   [void](Invoke-CustomAppHostedPreimageRehearsalV049 -CutoverLease $lease -ExpectedProfileSha256 $pin -OutputDirectory $pendingOutput @fixtureArgs)
 }catch{if([string]$_.Exception.Message -ceq 'V049_LOCKED_APPROVED_MANIFEST_NOT_QUALIFIED'){$blocked=$true}else{throw}}
 Assert-V049 ($blocked -and -not(Test-Path $pendingOutput) -and
   [IO.File]::Exists($pending)) 'PENDING_LEGACY_TRANSACTION_NOT_BLOCKED_BEFORE_COPY'
 [IO.File]::Delete($pending)
 Write-Host 'V049_OLD_UNSETTLED_TRANSACTION_PREVENTS_PREIMAGE_STAGING_PASS'
 Assert-V049 ((Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $foreignOriginal -and
  (Get-FileHash $state -Algorithm SHA256).Hash -ceq $stateOriginal -and
  (Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $unknownOriginal -and
  -not(Test-Path $enrollment)) 'ORIGINAL_PROFILE_CHANGED'
 Write-Host 'V049_ORIGINAL_XPUI_UNMANAGED_APP_LEGACY_STATE_UNTOUCHED_PASS'
}finally{if($null-ne$lease.lock_handle){$lease.lock_handle.Dispose()}}
Assert-V049 (-not[bool](Test-CustomAppHostedPreimageRehearsalV049 -OutputDirectory $out -ExpectedReceiptSha256 ('0'*64)).ok) 'INCORRECT_RECEIPT_SHA_ACCEPTED'
Write-Host 'V049_HOSTED_ONLY_ROLLBACK_REHEARSAL_NO_PRODUCTION_MUTATION_PASS'
