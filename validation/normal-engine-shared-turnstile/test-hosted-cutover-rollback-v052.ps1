# V052 dedicated scoped integration; reuses V051 fixture, not installed Spotify.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V052_TEST_REAL_USER_PROFILE_FORBIDDEN'
}
. (Join-Path $PSScriptRoot 'test-private-detached-recovery-v051.ps1')
. (Join-Path $PSScriptRoot 'hosted-cutover-rollback-v052.ps1')
function Assert-V052([bool]$Ok,[string]$Reason){if(-not$Ok){throw ('V052_TEST_'+$Reason)}}
# Preserve all 610 original XPUI members and change only the official
# V044 manifest-owned output set. The three route files are synthetic
# stand-ins, NOT proof the official vendor CLI executed in this test.
$candidateX=Join-Path $env:RUNNER_TEMP ('v052-candidate-x-'+[guid]::NewGuid().ToString('N'))
$candidateApp=Join-Path $env:RUNNER_TEMP ('v052-candidate-app-'+[guid]::NewGuid().ToString('N'))
[void](Copy-CustomAppV050BoundTree -Source $xpui -Destination $candidateX)
[void](Copy-CustomAppV050BoundTree -Source (Join-Path $cliApps 'ivlyrics') -Destination $candidateApp)
$scope=Get-ApprovedNativeManifestOwnedScopeV044 -Name 'ivlyrics' -SourceAppPath (Join-Path $cliApps 'ivlyrics')
if(@($scope.owned_files).Count -ne 6 -or [int]$scope.declared_extensions -ne 3){
 throw 'V053_EXPECTED_SIX_NATIVE_OWNED_FILES_MISSING'
}
foreach($owned in @($scope.owned_files)){
 $dest=Join-Path $candidateX ([string]$owned).Replace('/','\')
 [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
 if($scope.byte_exact_copied_outputs.ContainsKey([string]$owned)){
   $source=Join-Path (Join-Path $cliApps 'ivlyrics\extensions') ([IO.Path]::GetFileName([string]$owned))
   if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne
      [string]$scope.byte_exact_copied_outputs[[string]$owned]){
      throw 'V053_OFFICIAL_MANIFEST_EXTENSION_SOURCE_NOT_PINNED'
   }
   [IO.File]::Copy($source,$dest,$false)
 }elseif(([string]$owned).EndsWith('.json',[StringComparison]::Ordinal)){
   [IO.File]::Copy((Join-Path $cliApps 'ivlyrics\manifest.json'),$dest,$false)
 }else{
   [IO.File]::WriteAllText($dest,'V053_HOSTED_SYNTHETIC_MANIFEST_OWNED_ROUTE',([Text.UTF8Encoding]::new($false)))
 }
}
[IO.File]::AppendAllText((Join-Path $candidateApp 'index.js'),'v052-approved-synthetic-change')
$sourceSnap=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$candidateSnap=Get-CustomAppUpdateTreeSnapshotV010 -Root $candidateX
$native=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $sourceSnap -After $candidateSnap -Name 'ivlyrics' -SourceAppPath (Join-Path $cliApps 'ivlyrics') -ExpectedSourceTreeSha256 ([string]$scope.source_tree_sha256)
Assert-V052 ([bool]$native.ok -and [bool]$native.foreign_xpui_preserved -and
 [int]$native.scoped_file_count -eq 6 -and
 [int]$native.scoped_extension_files -eq 3 -and
 -not[bool]$native.production_mutation_authorized) 'V053_NATIVE_MANIFEST_OWNED_CANDIDATE_NOT_QUALIFIED'
Write-Host 'V053_V044_SIX_DECLARED_OUTPUTS_AND_610_FOREIGN_XPUI_MEMBERS_PRESERVED_PASS'
$candidateXpuiSha=(Get-CustomAppUpdateTreeSnapshotV010 -Root $candidateX).tree_sha256
$candidateAppSha=(Get-CustomAppUpdateTreeSnapshotV010 -Root $candidateApp).tree_sha256
Assert-V052 ($candidateXpuiSha -cne $before.xpui -and $candidateAppSha -cne $before.ivlyrics) 'CANDIDATE_NOT_DISTINCT_FROM_ORIGINAL'
$sealed=Join-Path $escrow ('cutover-intent-v052-'+$id+'.dpapi')
$preArgs=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli;HostedEscrowRoot=$escrow
 EscrowId=$id;BackupReceiptSha256=$receiptPin
 ExpectedProfileSha256=$pin;CandidateXpuiRoot=$candidateX;CandidateAppRoot=$candidateApp
 AppName='ivlyrics'}
$preLease=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $pin @fixtureArgs
try{
 $blocked=$false
 try{[void](New-CustomAppHostedCutoverIntentV052 -CutoverLease $preLease @preArgs)}
 catch{if([string]$_.Exception.Message -ceq 'V052_HOSTED_SIMULATION_OPT_IN_REQUIRED'){$blocked=$true}else{throw}}
 Assert-V052 ($blocked -and -not(Test-Path $sealed)) 'UNAPPROVED_INTENT_CREATED'
 # Reject a candidate that touches even one foreign XPUI asset. Do not
 # let a test fixture trick the V044 ownership gate into a positive result.
 $foreignTarget=Join-Path $candidateX 'v050-scale-assets\asset-0001.dat'
 $bytes=[IO.File]::ReadAllBytes($foreignTarget)
 try{
   [IO.File]::AppendAllText($foreignTarget,'V053_FOREIGN_MUTATION')
   $rejected=$false
   try{[void](New-CustomAppHostedCutoverIntentV052 -CutoverLease $preLease @preArgs -ExplicitHostedSimulationApproval)}
   catch{if([string]$_.Exception.Message -ceq 'V044_FOREIGN_XPUI_EXISTING_FILE_CHANGED'){$rejected=$true}else{throw}}
   Assert-V052 ($rejected -and -not(Test-Path $sealed)) 'FOREIGN_XPUI_ASSET_CHANGE_SIGNED_AS_OFFICIAL'
 }finally{[IO.File]::WriteAllBytes($foreignTarget,$bytes)}
 # Officially named extension output is insufficient: its BYTES must match
 # the exact preflight source file after the candidate has been constructed.
 $extensionOut=Join-Path $candidateX 'extensions\ivlyrics\a.js'
 $originalExtension=[IO.File]::ReadAllBytes($extensionOut)
 try{
   [IO.File]::AppendAllText($extensionOut,'V053_FAKE_COPIED_EXTENSION')
   $rejected=$false
   try{[void](New-CustomAppHostedCutoverIntentV052 -CutoverLease $preLease @preArgs -ExplicitHostedSimulationApproval)}
   catch{if([string]$_.Exception.Message -ceq 'V044_MANIFEST_SOURCE_COPIED_BYTES_DID_NOT_MATCH'){$rejected=$true}else{throw}}
   Assert-V052 ($rejected -and -not(Test-Path $sealed)) 'ALTERED_EXTENSION_BYTES_SIGNED_AS_OFFICIAL'
 }finally{[IO.File]::WriteAllBytes($extensionOut,$originalExtension)}
 Write-Host 'V053_FOREIGN_XPUI_AND_SOURCE_COPIED_EXTENSION_MODIFICATION_BLOCKED_BEFORE_SEAL_PASS'
 $intent=New-CustomAppHostedCutoverIntentV052 -CutoverLease $preLease @preArgs -ExplicitHostedSimulationApproval
 Assert-V052 ([bool]$intent.ok -and
   [string]$intent.status -ceq 'hosted-cutover-recovery-intent-sealed' -and
   [string]$intent.intent_sha256 -cmatch '^[a-f0-9]{64}$' -and
   -not[bool]$intent.production_mutation_authorized -and
   -not[bool]$intent.version_or_release_provenance_verified) 'INTENT_NOT_SEALED_AND_NONAUTHORITATIVE'
}finally{if($null-ne$preLease.lock_handle){$preLease.lock_handle.Dispose()}}
$intentSha=[string]$intent.intent_sha256
$p=Assert-CustomAppV052Fixture -HostedFixtureRoot $root -HostedFixtureCliPath $cli -HostedEscrowRoot $escrow
$sealedIntent=Get-CustomAppV052SealedIntent -Paths $p -EscrowId $id -IntentSha256 $intentSha
Assert-V052 ([bool]$sealedIntent.v044_native_manifest_fence_verified -and
 -not[bool]$sealedIntent.actual_vendor_cli_invoked -and
 -not[bool]$sealedIntent.production_mutation_authorized -and
 [int]$sealedIntent.owned_output_file_count -eq 6 -and
 [string]$sealedIntent.owned_output_source_sha256 -ceq [string]$scope.source_tree_sha256 -and
 [string]$sealedIntent.owned_output_manifest_sha256 -ceq [string]$scope.manifest_sha256 -and
 [string]$sealedIntent.owned_output_scope_fingerprint -cmatch '^[a-f0-9]{64}
# The sealed pre-change witness MUST reject even appended DPAPI bytes.
$oldIntent=[IO.File]::ReadAllBytes($sealed)
try{
 [IO.File]::AppendAllText($sealed,'tamper')
 $blocked=$false
 try{
   $p=Assert-CustomAppV052Fixture -HostedFixtureRoot $root -HostedFixtureCliPath $cli -HostedEscrowRoot $escrow
   [void](Get-CustomAppV052SealedIntent -Paths $p -EscrowId $id -IntentSha256 $intentSha)
 }catch{if([string]$_.Exception.Message -ceq 'V052_FULL_INTENT_CIPHERTEXT_SHA_CHANGED'){$blocked=$true}else{throw}}
 Assert-V052 $blocked 'FULL_DPAPI_INTENT_CIPHERTEXT_NOT_BOUND'
}finally{[IO.File]::WriteAllBytes($sealed,$oldIntent)}
Write-Host 'V052_SEALED_TRANSACTION_INTENT_TAMPER_REFUSED_PASS'
# Simulation of a vendor candidate: the candidate is *test-only* and never
# becomes release authorization. Every actual synthetic source mutation
# happens with the same V047 OS FileShare.None lock.
$sim=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot (Join-Path $root 'Local')
try{
 $oldApp=Join-Path $escrow ('sim-v052-before-app-'+$id)
 $oldXpui=Join-Path $escrow ('sim-v052-before-xpui-'+$id)
 [IO.Directory]::Move((Join-Path $cliApps 'ivlyrics'),$oldApp)
 [void](Copy-CustomAppV050BoundTree -Source $candidateApp -Destination (Join-Path $cliApps 'ivlyrics'))
 [IO.Directory]::Move($xpui,$oldXpui)
 [void](Copy-CustomAppV050BoundTree -Source $candidateX -Destination $xpui)
 Assert-V052 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $candidateXpuiSha -and
  (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256 -ceq $candidateAppSha) 'SIMULATED_APPLY_INCOMPLETE'
}finally{$sim.Dispose()}
# After applying, V046 cannot readmit the original profile. Recovery must
# use V050/V051 pinned preimage and the pre-change V052 witness instead.
$drift=Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs
Assert-V052 (-not[bool]$drift.ok -and -not[bool]$drift.production_mutation_authorized) 'PRECHANGE_IDENTITY_WAS_REUSED_AFTER_APPLY'
Write-Host 'V052_SIMULATED_VENDOR_CHANGE_AND_V046_PRECHANGE_ADMISSION_REJECTED_PASS'
$act=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli
 HostedEscrowRoot=$escrow;EscrowId=$id;IntentSha256=$intentSha}
# Unknown after-apply mutation must block before ANY quarantine or rollback.
$foreignOriginal=[IO.File]::ReadAllBytes($foreign)
try{
 [IO.File]::AppendAllText($foreign,'FOREIGN_DRIFT')
 $blocked=$false
 try{[void](Invoke-CustomAppHostedRollbackV052 @act)}
 catch{if([string]$_.Exception.Message -ceq 'V052_UNEXPECTED_LIVE_FOREIGN_CHANGE'){$blocked=$true}else{throw}}
 Assert-V052 ($blocked -and -not(Test-Path (Join-Path $escrow ('quarantine-v052-'+$id)))) 'UNBOUNDED_FOREIGN_CHANGE_WAS_OVERWRITTEN'
}finally{[IO.File]::WriteAllBytes($foreign,$foreignOriginal)}
Write-Host 'V052_UNEXPECTED_FOREIGN_XPUI_DRIFT_FAIL_CLOSED_NO_WRITES_PASS'
# Inject power-loss-like interruption precisely AFTER candidate app quarantine
# but BEFORE original app directory publication.
$crashed=$false
try{[void](Invoke-CustomAppHostedRollbackV052 @act -InjectedCrash 'after-app-quarantine')}
catch{if([string]$_.Exception.Message -ceq 'V052_CONTROLLED_CRASH_AFTER_QUARANTINE'){$crashed=$true}else{throw}}
$q=Join-Path $escrow ('quarantine-v052-'+$id)
Assert-V052 ($crashed -and
 -not[IO.Directory]::Exists((Join-Path $cliApps 'ivlyrics')) -and
 [IO.Directory]::Exists((Join-Path $q 'app-candidate')) -and
 [IO.Directory]::Exists((Join-Path $q 'app-restage')) -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'app-candidate')).tree_sha256 -ceq $candidateAppSha -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $candidateXpuiSha) 'QUARANTINED_APP_CRASH_STATE_NOT_BYTE_EXACT'
Write-Host 'V052_AFTER_APP_QUARANTINE_CRASH_RETURNS_WITH_OLD_PREIMAGE_RETAINED_PASS'
# The new process MUST not call V046 again because profile is partially
# applied. It obtains the same raw V047 lock and uses sealed intent+V051.
$child=Join-Path $PSScriptRoot 'hosted-cutover-rollback-child-v052.ps1'
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child @act 2>&1)
if($LASTEXITCODE -ne 0){
 Write-Host ('V052_CHILD_ERROR_TYPE='+($output -join [char]10))
 throw 'V052_FRESH_PROCESS_RECOVERY_NOT_VERIFIED'
}
Assert-V052 (($output -join [char]10).Contains('V052_FRESH_PROCESS_SHARED_LOCK_APP_AND_XPUI_ROLLBACK_COMPLETE_PASS')) 'RESTART_PROOF_MISSING'
$terminal=Join-Path $escrow ('rollback-complete-v052-'+$id+'.dpapi')
Assert-V052 ([IO.File]::Exists($terminal) -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256 -ceq $before.ivlyrics -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $before.xpui -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'app-candidate')).tree_sha256 -ceq $candidateAppSha -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'xpui-candidate')).tree_sha256 -ceq $candidateXpuiSha
 ) 'COMPOSITE_ROLLBACK_OR_QUARANTINE_MISSING'
Write-Host 'V052_FRESH_PROCESS_LOCKED_ROLLBACK_BOTH_TREES_EXACT_AND_QUARANTINED_PASS'
$again=Invoke-CustomAppHostedRollbackV052 @act
Assert-V052 ([bool]$again.ok -and [string]$again.status -ceq 'hosted-rollback-already-complete' -and
 -not[bool]$again.production_mutation_authorized -and
 -not[bool]$again.live_update_authorized) 'RESTART_NOT_IDEMPOTENT'
# Protect against Windows DPAPI accepting appended bytes on an otherwise
# decryptable ciphertext; the completed record has a full-body SHA frame.
$terminalBytes=[IO.File]::ReadAllBytes($terminal)
try{
 [IO.File]::AppendAllText($terminal,'V052_TRAILER')
 $badTerminal=$false
 try{[void](Invoke-CustomAppHostedRollbackV052 @act)}
 catch{if([string]$_.Exception.Message -ceq 'V052_TERMINAL_CIPHERTEXT_NOT_EXACT'){$badTerminal=$true}else{throw}}
 Assert-V052 $badTerminal 'TERMINAL_DPAPI_APPEND_WAS_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($terminal,$terminalBytes)}
$again=Invoke-CustomAppHostedRollbackV052 @act
Assert-V052 ([bool]$again.ok -and [string]$again.status -ceq 'hosted-rollback-already-complete') 'TERMINAL_NOT_VERIFIABLE_AFTER_SYNTHETIC_REPAIR'
Write-Host 'V052_TERMINAL_FULL_CIPHERTEXT_TAMPER_REJECTED_PASS'
# Neither DPAPI guard files nor other approved apps or unknown inputs change.
Assert-V052 ((Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $before.prefs -and
 (Get-FileHash $config -Algorithm SHA256).Hash -ceq $before.config -and
 (Get-FileHash $state -Algorithm SHA256).Hash -ceq $before.state -and
 (Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $before.unmanaged -and
 (Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $before.foreign -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'better-local-files')).tree_sha256 -ceq $before.better -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'eternal-jukebox')).tree_sha256 -ceq $before.eternal -and
 -not(Test-Path $enrollment) -and
 [bool](Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow).ok
 ) 'FOREIGN_OR_BACKUP_CHANGED_AFTER_RECOVERY'
Write-Host 'V052_RESTART_IDEMPOTENT_NO_PROTECTED_UNMANAGED_OR_BACKUP_CHANGES_PASS'
Write-Host 'V052_HOSTED_ONLY_COMPOSITE_CUTOVER_RECOVERY_NO_REAL_SPOTIFY_MUTATION_PASS'
) 'V053_SEALED_NATIVE_MANIFEST_PROOF_NOT_BOUND'
Write-Host 'V053_NATIVE_MANIFEST_SOURCE_AND_OUTPUT_SCOPE_PINNED_IN_DPAPI_INTENT_PASS'
Write-Host 'V052_EXPLICIT_PRECHANGE_V048_AND_V051_BOUND_SEALED_INTENT_PASS'
# The sealed pre-change witness MUST reject even appended DPAPI bytes.
$oldIntent=[IO.File]::ReadAllBytes($sealed)
try{
 [IO.File]::AppendAllText($sealed,'tamper')
 $blocked=$false
 try{
   $p=Assert-CustomAppV052Fixture -HostedFixtureRoot $root -HostedFixtureCliPath $cli -HostedEscrowRoot $escrow
   [void](Get-CustomAppV052SealedIntent -Paths $p -EscrowId $id -IntentSha256 $intentSha)
 }catch{if([string]$_.Exception.Message -ceq 'V052_FULL_INTENT_CIPHERTEXT_SHA_CHANGED'){$blocked=$true}else{throw}}
 Assert-V052 $blocked 'FULL_DPAPI_INTENT_CIPHERTEXT_NOT_BOUND'
}finally{[IO.File]::WriteAllBytes($sealed,$oldIntent)}
Write-Host 'V052_SEALED_TRANSACTION_INTENT_TAMPER_REFUSED_PASS'
# Simulation of a vendor candidate: the candidate is *test-only* and never
# becomes release authorization. Every actual synthetic source mutation
# happens with the same V047 OS FileShare.None lock.
$sim=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot (Join-Path $root 'Local')
try{
 $oldApp=Join-Path $escrow ('sim-v052-before-app-'+$id)
 $oldXpui=Join-Path $escrow ('sim-v052-before-xpui-'+$id)
 [IO.Directory]::Move((Join-Path $cliApps 'ivlyrics'),$oldApp)
 [void](Copy-CustomAppV050BoundTree -Source $candidateApp -Destination (Join-Path $cliApps 'ivlyrics'))
 [IO.Directory]::Move($xpui,$oldXpui)
 [void](Copy-CustomAppV050BoundTree -Source $candidateX -Destination $xpui)
 Assert-V052 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $candidateXpuiSha -and
  (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256 -ceq $candidateAppSha) 'SIMULATED_APPLY_INCOMPLETE'
}finally{$sim.Dispose()}
# After applying, V046 cannot readmit the original profile. Recovery must
# use V050/V051 pinned preimage and the pre-change V052 witness instead.
$drift=Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs
Assert-V052 (-not[bool]$drift.ok -and -not[bool]$drift.production_mutation_authorized) 'PRECHANGE_IDENTITY_WAS_REUSED_AFTER_APPLY'
Write-Host 'V052_SIMULATED_VENDOR_CHANGE_AND_V046_PRECHANGE_ADMISSION_REJECTED_PASS'
$act=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli
 HostedEscrowRoot=$escrow;EscrowId=$id;IntentSha256=$intentSha}
# Unknown after-apply mutation must block before ANY quarantine or rollback.
$foreignOriginal=[IO.File]::ReadAllBytes($foreign)
try{
 [IO.File]::AppendAllText($foreign,'FOREIGN_DRIFT')
 $blocked=$false
 try{[void](Invoke-CustomAppHostedRollbackV052 @act)}
 catch{if([string]$_.Exception.Message -ceq 'V052_UNEXPECTED_LIVE_FOREIGN_CHANGE'){$blocked=$true}else{throw}}
 Assert-V052 ($blocked -and -not(Test-Path (Join-Path $escrow ('quarantine-v052-'+$id)))) 'UNBOUNDED_FOREIGN_CHANGE_WAS_OVERWRITTEN'
}finally{[IO.File]::WriteAllBytes($foreign,$foreignOriginal)}
Write-Host 'V052_UNEXPECTED_FOREIGN_XPUI_DRIFT_FAIL_CLOSED_NO_WRITES_PASS'
# Inject power-loss-like interruption precisely AFTER candidate app quarantine
# but BEFORE original app directory publication.
$crashed=$false
try{[void](Invoke-CustomAppHostedRollbackV052 @act -InjectedCrash 'after-app-quarantine')}
catch{if([string]$_.Exception.Message -ceq 'V052_CONTROLLED_CRASH_AFTER_QUARANTINE'){$crashed=$true}else{throw}}
$q=Join-Path $escrow ('quarantine-v052-'+$id)
Assert-V052 ($crashed -and
 -not[IO.Directory]::Exists((Join-Path $cliApps 'ivlyrics')) -and
 [IO.Directory]::Exists((Join-Path $q 'app-candidate')) -and
 [IO.Directory]::Exists((Join-Path $q 'app-restage')) -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'app-candidate')).tree_sha256 -ceq $candidateAppSha -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $candidateXpuiSha) 'QUARANTINED_APP_CRASH_STATE_NOT_BYTE_EXACT'
Write-Host 'V052_AFTER_APP_QUARANTINE_CRASH_RETURNS_WITH_OLD_PREIMAGE_RETAINED_PASS'
# The new process MUST not call V046 again because profile is partially
# applied. It obtains the same raw V047 lock and uses sealed intent+V051.
$child=Join-Path $PSScriptRoot 'hosted-cutover-rollback-child-v052.ps1'
$output=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child @act 2>&1)
if($LASTEXITCODE -ne 0){
 Write-Host ('V052_CHILD_ERROR_TYPE='+($output -join [char]10))
 throw 'V052_FRESH_PROCESS_RECOVERY_NOT_VERIFIED'
}
Assert-V052 (($output -join [char]10).Contains('V052_FRESH_PROCESS_SHARED_LOCK_APP_AND_XPUI_ROLLBACK_COMPLETE_PASS')) 'RESTART_PROOF_MISSING'
$terminal=Join-Path $escrow ('rollback-complete-v052-'+$id+'.dpapi')
Assert-V052 ([IO.File]::Exists($terminal) -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'ivlyrics')).tree_sha256 -ceq $before.ivlyrics -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq $before.xpui -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'app-candidate')).tree_sha256 -ceq $candidateAppSha -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $q 'xpui-candidate')).tree_sha256 -ceq $candidateXpuiSha
 ) 'COMPOSITE_ROLLBACK_OR_QUARANTINE_MISSING'
Write-Host 'V052_FRESH_PROCESS_LOCKED_ROLLBACK_BOTH_TREES_EXACT_AND_QUARANTINED_PASS'
$again=Invoke-CustomAppHostedRollbackV052 @act
Assert-V052 ([bool]$again.ok -and [string]$again.status -ceq 'hosted-rollback-already-complete' -and
 -not[bool]$again.production_mutation_authorized -and
 -not[bool]$again.live_update_authorized) 'RESTART_NOT_IDEMPOTENT'
# Protect against Windows DPAPI accepting appended bytes on an otherwise
# decryptable ciphertext; the completed record has a full-body SHA frame.
$terminalBytes=[IO.File]::ReadAllBytes($terminal)
try{
 [IO.File]::AppendAllText($terminal,'V052_TRAILER')
 $badTerminal=$false
 try{[void](Invoke-CustomAppHostedRollbackV052 @act)}
 catch{if([string]$_.Exception.Message -ceq 'V052_TERMINAL_CIPHERTEXT_NOT_EXACT'){$badTerminal=$true}else{throw}}
 Assert-V052 $badTerminal 'TERMINAL_DPAPI_APPEND_WAS_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($terminal,$terminalBytes)}
$again=Invoke-CustomAppHostedRollbackV052 @act
Assert-V052 ([bool]$again.ok -and [string]$again.status -ceq 'hosted-rollback-already-complete') 'TERMINAL_NOT_VERIFIABLE_AFTER_SYNTHETIC_REPAIR'
Write-Host 'V052_TERMINAL_FULL_CIPHERTEXT_TAMPER_REJECTED_PASS'
# Neither DPAPI guard files nor other approved apps or unknown inputs change.
Assert-V052 ((Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $before.prefs -and
 (Get-FileHash $config -Algorithm SHA256).Hash -ceq $before.config -and
 (Get-FileHash $state -Algorithm SHA256).Hash -ceq $before.state -and
 (Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $before.unmanaged -and
 (Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $before.foreign -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'better-local-files')).tree_sha256 -ceq $before.better -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $cliApps 'eternal-jukebox')).tree_sha256 -ceq $before.eternal -and
 -not(Test-Path $enrollment) -and
 [bool](Test-CustomAppV050Escrow -EscrowId $id -ExpectedReceiptSha256 $receiptPin -HostedEscrowRoot $escrow).ok
 ) 'FOREIGN_OR_BACKUP_CHANGED_AFTER_RECOVERY'
Write-Host 'V052_RESTART_IDEMPOTENT_NO_PROTECTED_UNMANAGED_OR_BACKUP_CHANGES_PASS'
Write-Host 'V052_HOSTED_ONLY_COMPOSITE_CUTOVER_RECOVERY_NO_REAL_SPOTIFY_MUTATION_PASS'
