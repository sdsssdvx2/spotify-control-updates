# V051 targeted test reuses V050 610-file fixture and all original hashes.
# Hosted Windows synthetic only: never reads installed user Spotify.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
   throw 'V051_TEST_HOSTED_ONLY'
}
. (Join-Path $PSScriptRoot 'test-guarded-profile-escrow-v050.ps1')
. (Join-Path $PSScriptRoot 'private-detached-recovery-v051.ps1')
function Assert-V051([bool]$Good,[string]$Label){if(-not$Good){throw ('V051_TEST_'+$Label)}}
$reader=@{EscrowId=$id;ReceiptSha256=$receiptPin;HostedEscrowRoot=$escrow}
$target=Join-Path $escrow ('reconstructed-v051-'+$id)
$stage=Join-Path $escrow ('pending-recovery-v051-'+$id)
Assert-V051 (-not(Test-Path $target) -and -not(Test-Path $stage)) 'RECOVERY_OUTPUT_PREEXISTED'
$denied=$false
try{
 [void](Invoke-CustomAppV051PrivateDetachedRecovery @reader)
}catch{
 if([string]$_.Exception.Message -ceq 'V051_EXPLICIT_DETACHED_RECOVERY_AUTHORIZATION_REQUIRED'){$denied=$true}else{throw}
}
Assert-V051 ($denied -and -not(Test-Path $target) -and -not(Test-Path $stage)) 'SILENT_RECOVERY_WITHOUT_OWNER_APPROVAL'
Write-Host 'V051_NO_EXPLICIT_APPROVAL_NO_RECOVERY_BYTES_WRITTEN_PASS'
# A DPAPI appended-ciphertext attack must block restoration before any
# destination creation. Restore only synthetic private backup input.
$cipher=Join-Path $verified 'preimage\protected\prefs.dpapi'
$original=[IO.File]::ReadAllBytes($cipher)
try{
 [IO.File]::AppendAllText($cipher,'V051_TAMPER_TRAILER')
 $blocked=$false
 try{
  [void](Invoke-CustomAppV051PrivateDetachedRecovery @reader -ExplicitDetachedRecoveryAuthorization)
 }catch{
  if([string]$_.Exception.Message -ceq 'V051_V050_SEALED_PREIMAGE_NOT_VERIFIED'){$blocked=$true}else{throw}
 }
 Assert-V051 ($blocked -and -not(Test-Path $target) -and -not(Test-Path $stage)) 'APPENDED_DPAPI_CIPHERTEXT_WAS_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($cipher,$original)}
Write-Host 'V051_FULL_CIPHERTEXT_TAMPER_DENIED_BEFORE_ANY_RECOVERY_WRITE_PASS'
# Invalid receipt pin must fail closed before a private transaction is made.
$blocked=$false
try{[void](Invoke-CustomAppV051PrivateDetachedRecovery -EscrowId $id -ReceiptSha256 ('0'*64) -HostedEscrowRoot $escrow -ExplicitDetachedRecoveryAuthorization)}
catch{
 if([string]$_.Exception.Message -ceq 'V051_V050_SEALED_PREIMAGE_NOT_VERIFIED'){$blocked=$true}else{throw}
}
Assert-V051 ($blocked -and -not(Test-Path $target) -and -not(Test-Path $stage)) 'WRONG_RECEIPT_PIN_WAS_ACCEPTED'
# The new global OS recovery lock prevents two simultaneous cooperative
# reconstruction sessions (not a sandbox for malicious same-user processes).
$locked=Join-Path $escrow '.private-recovery-v051.lock'
$handle=[IO.File]::Open($locked,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
 $blocked=$false
 try{[void](Invoke-CustomAppV051PrivateDetachedRecovery @reader -ExplicitDetachedRecoveryAuthorization)}
 catch [IO.IOException]{$blocked=$true}
 Assert-V051 ($blocked -and -not(Test-Path $target) -and -not(Test-Path $stage)) 'COOPERATIVE_RECOVERY_OS_LEASE_NOT_EXCLUSIVE'
}finally{$handle.Dispose()}
Write-Host 'V051_INVALID_RECEIPT_AND_OS_LOCK_COLLISION_DENIED_PASS'
# The independent child has no original installed Spotify bindings; it
# consumes only the existing verified V050 sealed backup in the private vault.
$child=Join-Path $PSScriptRoot 'private-detached-recovery-child-v051.ps1'
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -EscrowId $id -ReceiptSha256 $receiptPin -HostedEscrowRoot $escrow 2>&1)
if($LASTEXITCODE -ne 0){
 Write-Host ('V051_HOSTED_SAFE_CHILD_FAILURE='+($output -join [char]10))
 throw 'V051_FRESH_PROCESS_RECONSTRUCTION_FAILED'
}
Assert-V051 (($output -join [char]10).Contains('V051_NEW_PROCESS_610FILE_DPAPI_GUARDS_PRIVATE_RECOVERY_PASS')) 'NEW_PROCESS_PROOF_MISSING'
$checked=Test-CustomAppV051DetachedRecovery @reader
Assert-V051 ([bool]$checked.ok -and [int]$checked.xpui_file_count -eq 610 -and
 [int]$checked.approved_app_count -eq 3 -and [int]$checked.protected_file_count -eq 3 -and
 -not[bool]$checked.production_mutation_authorized) 'POST_PROCESS_RECONSTRUCTION_NOT_REVALIDATED'
foreach($pair in @(
 @('trees\xpui',$before.xpui),
 @('trees\ivlyrics',$before.ivlyrics),
 @('trees\better-local-files',$before.better),
 @('trees\eternal-jukebox',$before.eternal)
)){
 $tree=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $target $pair[0])
 Assert-V051 ([string]$tree.tree_sha256 -ceq [string]$pair[1]) 'INDEPENDENT_SOURCE_AND_RECOVERY_TREE_DIFFER'
}
foreach($pair in @(@('guard\config.ini',$before.config),@('guard\prefs',$before.prefs),@('guard\legacy-state.json',$before.state))){
 $digest=(Get-FileHash -LiteralPath (Join-Path $target $pair[0]) -Algorithm SHA256).Hash
 Assert-V051 ($digest -ceq [string]$pair[1]) 'INDEPENDENT_PROTECTED_RECOVERY_BYTES_DIFFER'
}
Write-Host 'V051_FULL_XPUI_APPS_AND_THREE_GUARDS_RECONSTRUCTED_BYTE_EXACT_PASS'
# Fresh restart must not overwrite the user's retained private recovery.
$blocked=$false
try{[void](Invoke-CustomAppV051PrivateDetachedRecovery @reader -ExplicitDetachedRecoveryAuthorization)}
catch{if([string]$_.Exception.Message -ceq 'V051_RECONSTRUCTION_STAGE_OR_TARGET_ALREADY_EXISTS'){$blocked=$true}else{throw}}
Assert-V051 $blocked 'SECOND_RECOVERY_OVERWROTE_EXISTING_OUTPUT'
# Tamper one reconstructed app file: independent reader must reject without
# changing or removing any original backed-up source.
$reconstructed=Join-Path $target 'trees\ivlyrics\index.js'
$raw=[IO.File]::ReadAllBytes($reconstructed)
try{
 [IO.File]::AppendAllText($reconstructed,'NOT_OWNED')
 $bad=Test-CustomAppV051DetachedRecovery @reader
 Assert-V051 (-not[bool]$bad.ok -and -not[bool]$bad.production_mutation_authorized) 'RECOVERY_OUTPUT_TAMPER_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($reconstructed,$raw)}
Assert-V051 ([bool](Test-CustomAppV051DetachedRecovery @reader).ok) 'REPAIRED_SYNTHETIC_RECOVERY_NOT_VERIFIABLE'
Write-Host 'V051_NO_OVERWRITE_AND_INDEPENDENT_OUTPUT_TAMPER_DENIAL_PASS'
# Original protected state, unmanaged app and existing backup not modified.
Assert-V051 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $before.xpui -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256 -ceq $before.ivlyrics -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'better-local-files')).tree_sha256 -ceq $before.better -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'eternal-jukebox')).tree_sha256 -ceq $before.eternal -and
 (Get-FileHash $config -Algorithm SHA256).Hash -ceq $before.config -and
 (Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $before.prefs -and
 (Get-FileHash $state -Algorithm SHA256).Hash -ceq $before.state -and
 (Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $before.unmanaged -and
 (Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $before.foreign -and
 -not(Test-Path $enrollment) -and
 [bool](Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow).ok
 ) 'ORIGINAL_SPOTIFY_OR_BACKUP_CHANGED'
Write-Host 'V051_ORIGINAL_SPOTIFY_LEGACY_UNKNOWN_APP_AND_BACKUP_UNCHANGED_PASS'
Write-Host 'V051_USER_PROFILE_UNTOUCHED_REAL_UPDATE_AND_ROLLBACK_STILL_DISABLED_PASS'
