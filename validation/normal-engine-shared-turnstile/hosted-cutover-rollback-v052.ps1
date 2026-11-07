# V052 HOLD — one manifest-scoped, synthetic-only, crash-resumable rollback.
# Does NOT install, run Spicetify, write user's Spotify, or authorize updates.
# This hosted fixture integration bridges V047 exclusive OS turnstile,
# V048 immutable preflight, V050 full-source preimage and V051 cold recovery.
# V046 cannot be reused AFTER candidate mutation; a sealed pre-change intent
# plus pinned exact candidate hashes and retained quarantine are required.
# Preload V010/V036/V041/V042/V044/V046/V047/V048/V050/V051 modules.
function Assert-CustomAppV052Fixture {
 param([string]$HostedFixtureRoot,[string]$HostedFixtureCliPath,[string]$HostedEscrowRoot)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
   throw 'V052_HOSTED_WINDOWS_ONLY_NO_REAL_PROFILE'
 }
 $base=Assert-CustomAppV050Path -Path $HostedFixtureRoot -FixtureRoot $HostedFixtureRoot
 $cli=Assert-CustomAppV050Path -Path $HostedFixtureCliPath -FixtureRoot $HostedFixtureRoot
 if($cli -cne (Join-Path $base 'VendorCLI\spicetify.exe')){
   throw 'V052_SYNTHETIC_CLI_NOT_BOUND'
 }
 $vault=Assert-CustomAppV051Vault -HostedEscrowRoot $HostedEscrowRoot
 $xpui=Assert-CustomAppV050Path -Path (Join-Path $base 'FakeSpotify\Apps\xpui')
 $apps=Assert-CustomAppV050Path -Path (Join-Path $base 'VendorCLI\CustomApps')
 if((Test-CustomAppUpdatePathsOverlapV010 -A $vault -B $base) -or
    (Test-CustomAppUpdatePathsOverlapV010 -A $xpui -B $vault)){
   throw 'V052_ESCROW_OVERLAPS_LIVE_FIXTURE'
 }
 return [pscustomobject]@{base=$base;cli=$cli;vault=$vault;xpui=$xpui;apps=$apps}
}
function Test-CustomAppV052LiveTurnstile {
 param([Parameter(Mandatory=$true)]$Handle,[Parameter(Mandatory=$true)]$Paths)
 try{
   $target=Join-Path $Paths.base 'Local\SpotifyControl\.engine-cutover-turnstile.lock'
   return ($null-ne$Handle -and $Handle -is [IO.FileStream] -and
     -not$Handle.SafeFileHandle.IsClosed -and -not$Handle.SafeFileHandle.IsInvalid -and
     $Handle.CanWrite -and [int64]$Handle.Length -eq 0 -and
     [string]::Equals([IO.Path]::GetFullPath([string]$Handle.Name),
       [IO.Path]::GetFullPath($target),[StringComparison]::OrdinalIgnoreCase))
 }catch{return $false}
}
function Get-CustomAppV052OnlyChanged {
 param([Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After,
       [Parameter(Mandatory=$true)][string]$OnlyRelativePath)
 $a=@{};$b=@{}
 foreach($entry in @($Before.entries)){
   $k=([string]$entry.path).ToLowerInvariant()
   if($a.ContainsKey($k)){throw 'V052_DUPLICATE_PREIMAGE_MEMBER'}
   $a[$k]=([string]$entry.type+'|'+[string]$entry.size+'|'+[string]$entry.sha256)
 }
 foreach($entry in @($After.entries)){
   $k=([string]$entry.path).ToLowerInvariant()
   if($b.ContainsKey($k)){throw 'V052_DUPLICATE_AFTER_MEMBER'}
   $b[$k]=([string]$entry.type+'|'+[string]$entry.size+'|'+[string]$entry.sha256)
 }
 if($a.Count -ne $b.Count -or -not$b.ContainsKey($OnlyRelativePath.ToLowerInvariant())){
    throw 'V052_CANDIDATE_MEMBER_SET_CHANGED'
 }
 $changed=@($a.Keys|Where-Object{ -not$b.ContainsKey($_) -or
     [string]$a[$_] -cne [string]$b[$_] })
 if($changed.Count -ne 1 -or $changed[0] -cne $OnlyRelativePath.ToLowerInvariant()){
    throw 'V052_UNSCOPED_CANDIDATE_FILE_CHANGE'
 }
 return $true
}
function Get-CustomAppV052SealedIntent {
 param([Parameter(Mandatory=$true)]$Paths,[string]$EscrowId,[string]$IntentSha256)
 if($EscrowId -cnotmatch '^[a-f0-9]{32}$' -or $IntentSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V052_TRANSACTION_ID_OR_INTENT_PIN_INVALID'
 }
 $path=Assert-CustomAppV050Path -Path (Join-Path $Paths.vault ('cutover-intent-v052-'+$EscrowId+'.dpapi'))
 $info=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    [int64]$info.Length -lt 64 -or [int64]$info.Length -gt 65536){
    throw 'V052_SEALED_INTENT_FILE_NOT_BOUNDED'
 }
 $bytes=[IO.File]::ReadAllBytes($path)
 try{
    if((Get-CustomAppV050BytesHash -Data $bytes) -cne $IntentSha256){
       throw 'V052_FULL_INTENT_CIPHERTEXT_SHA_CHANGED'
    }
    $plain=ConvertFrom-CustomAppV050Sealed -Cipher $bytes -Purpose ('v052-cutover-intent|'+$EscrowId)
    try{
       $r=([Text.UTF8Encoding]::new($false,$true).GetString($plain)) | ConvertFrom-Json -ErrorAction Stop
    }finally{[Array]::Clear($plain,0,$plain.Length)}
 }finally{[Array]::Clear($bytes,0,$bytes.Length)}
 if([int]$r.schema -ne 1 -or [string]$r.owner -cne 'v052-hosted-only-cutover-recovery' -or
    [string]$r.escrow_id -cne $EscrowId -or
    [string]$r.profile_root -cne $Paths.base -or
    [string]$r.vault_root -cne $Paths.vault -or
    [string]$r.app_name -notin @('ivlyrics','better-local-files','eternal-jukebox') -or
    [string]$r.expected_profile_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.backup_receipt_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.preimage_xpui_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.candidate_xpui_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.preimage_app_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.candidate_app_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.owned_output_source_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.owned_output_manifest_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$r.owned_output_scope_fingerprint -cnotmatch '^[a-f0-9]{64}$' -or
    [int]$r.owned_output_file_count -lt 3 -or [int]$r.owned_output_file_count -gt 256 -or
    -not[bool]$r.v044_native_manifest_fence_verified -or
    [bool]$r.actual_vendor_cli_invoked -or
    [bool]$r.production_mutation_authorized){
    throw 'V052_HOSTED_INTENT_OWNER_SCHEMA_OR_SHA_UNQUALIFIED'
 }
 return $r
}
function New-CustomAppHostedCutoverIntentV052 {
 param([Parameter(Mandatory=$true)]$CutoverLease,
       [Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [Parameter(Mandatory=$true)][string]$HostedFixtureRoot,
       [Parameter(Mandatory=$true)][string]$HostedFixtureCliPath,
       [Parameter(Mandatory=$true)][string]$HostedEscrowRoot,
       [Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$BackupReceiptSha256,
       [ValidateSet('ivlyrics','better-local-files','eternal-jukebox')][string]$AppName='ivlyrics',
       [Parameter(Mandatory=$true)][string]$CandidateXpuiRoot,
       [Parameter(Mandatory=$true)][string]$CandidateAppRoot,
       [switch]$ExplicitHostedSimulationApproval)
 if(-not$ExplicitHostedSimulationApproval -or $ExpectedProfileSha256 -cnotmatch '^[a-f0-9]{64}$'){
   throw 'V052_HOSTED_SIMULATION_OPT_IN_REQUIRED'
 }
 $p=Assert-CustomAppV052Fixture -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath -HostedEscrowRoot $HostedEscrowRoot
 if(-not(Test-CustomAppV052LiveTurnstile -Handle $CutoverLease.lock_handle -Paths $p)){
   throw 'V052_HOSTED_LOCK_NOT_HELD'
 }
 $audit=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 -HostedFixtureRoot $p.base -HostedFixtureCliPath $p.cli
 if([string]$audit.status -cne 'observed-readonly' -or
    [bool]$audit.production_mutation_authorized -or
    [int]$audit.approved_manifest_count -ne 3){
   throw 'V052_V048_INSTALLED_SCOPE_NOT_STABLE_BEFORE_INTENT'
 }
 $reader=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 $BackupReceiptSha256 -Vault $p.vault
 $isRecovered=Test-CustomAppV051DetachedRecovery -EscrowId $EscrowId -ReceiptSha256 $BackupReceiptSha256 -HostedEscrowRoot $p.vault
 if(-not[bool]$isRecovered.ok -or @($reader.names).Count -ne 3 -or
    $AppName -notin @($reader.names)){
   throw 'V052_PRIVATE_RESTORE_NOT_REVERIFIED'
 }
 $app=Assert-CustomAppV050Path -Path (Join-Path $p.apps $AppName)
 if(-not[IO.Directory]::Exists($app)){
   throw 'V052_APPROVED_SOURCE_MISSING'
 }
 $xpuiCandidate=Assert-CustomAppV050Path -Path $CandidateXpuiRoot -FixtureRoot $CandidateXpuiRoot
 $appCandidate=Assert-CustomAppV050Path -Path $CandidateAppRoot -FixtureRoot $CandidateAppRoot
 foreach($cand in @($xpuiCandidate,$appCandidate)){
   if((Test-CustomAppUpdatePathsOverlapV010 -A $cand -B $p.base) -or
      (Test-CustomAppUpdatePathsOverlapV010 -A $cand -B $p.vault) -or
      (Test-CustomAppUpdatePathsOverlapV010 -A $cand -B $p.xpui)){
       throw 'V052_CANDIDATE_COLLIDES_WITH_LIVE_OR_VAULT'
   }
 }
 if(Test-CustomAppUpdatePathsOverlapV010 -A $xpuiCandidate -B $appCandidate){
    throw 'V052_TWO_CANDIDATES_OVERLAP'
 }
 $originalXpui=Get-CustomAppUpdateTreeSnapshotV010 -Root $p.xpui
 $newXpui=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpuiCandidate
 $originalApp=Get-CustomAppUpdateTreeSnapshotV010 -Root $app
 $newApp=Get-CustomAppUpdateTreeSnapshotV010 -Root $appCandidate
 $record=$reader.receipt
 if([string]$originalXpui.tree_sha256 -cne [string]$record.tree_sha256.xpui -or
    [string]$originalApp.tree_sha256 -cne [string]$record.tree_sha256.$AppName -or
    [string]$newXpui.tree_sha256 -ceq [string]$originalXpui.tree_sha256 -or
    [string]$newApp.tree_sha256 -ceq [string]$originalApp.tree_sha256){
    throw 'V052_BACKUP_OR_CANDIDATE_NOT_DISTINCTLY_PINNED'
 }
 # Synthetic candidate app source may edit exactly its own index.js.
 # The simulated XPUI output MUST pass the genuine V044 official Spicetify
 # manifest ownership comparator, not the old foreign-file-only rehearsal.
 # V044 verifies ALL nonowned XPUI bytes and exact extensions/assets hashes.
 # This does not attest a real vendor execution or release provenance.
 [void](Get-CustomAppV052OnlyChanged -Before $originalApp -After $newApp -OnlyRelativePath 'index.js')
 $native=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $originalXpui -After $newXpui -Name $AppName -SourceAppPath $app -ExpectedSourceTreeSha256 ([string]$originalApp.tree_sha256)
 if(-not[bool]$native.ok -or -not[bool]$native.foreign_xpui_preserved -or
    [bool]$native.production_mutation_authorized -or
    [int]$native.scoped_file_count -lt 3 -or
    [string]$native.source_tree_sha256 -cne [string]$originalApp.tree_sha256 -or
    [string]$native.manifest_sha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V053_NATIVE_MANIFEST_ONLY_OWNED_OUTPUT_NOT_VERIFIED'
 }
 $nativeScopeFingerprint=Get-CustomAppUpdateStringSha256V010 -Text (
     (@('v053-native-manifest-owned-candidate',
       [string]$native.source_tree_sha256,[string]$native.manifest_sha256,
       [string]$native.scoped_file_count,[string]$native.scoped_extension_files,
       [string]$native.scoped_asset_files,[string]$native.pre_xpui_sha256,
       [string]$native.post_xpui_sha256)) -join [char]10)
 $again=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 -HostedFixtureRoot $p.base -HostedFixtureCliPath $p.cli
 if([string]$again.status -cne 'observed-readonly' -or
    [string]$again.manifest_footprint_sha256 -cne [string]$audit.manifest_footprint_sha256){
   throw 'V052_PROFILE_CHANGED_BEFORE_INTENT_SEAL'
 }
 $record=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 $BackupReceiptSha256 -Vault $p.vault
 $intent=[ordered]@{
   schema=1;owner='v052-hosted-only-cutover-recovery'
   escrow_id=$EscrowId;backup_receipt_sha256=$BackupReceiptSha256
   profile_root=$p.base;vault_root=$p.vault;app_name=$AppName
   expected_profile_sha256=$ExpectedProfileSha256
   manifest_footprint_sha256=[string]$audit.manifest_footprint_sha256
   preimage_xpui_sha256=[string]$originalXpui.tree_sha256
   candidate_xpui_sha256=[string]$newXpui.tree_sha256
   preimage_app_sha256=[string]$originalApp.tree_sha256
   candidate_app_sha256=[string]$newApp.tree_sha256
   owned_output_source_sha256=[string]$native.source_tree_sha256
   owned_output_manifest_sha256=[string]$native.manifest_sha256
   owned_output_scope_fingerprint=$nativeScopeFingerprint
   owned_output_file_count=[int]$native.scoped_file_count
   v044_native_manifest_fence_verified=$true
   actual_vendor_cli_invoked=$false
   protected_file_sha256=$record.receipt.protected_sha256
   approved_app_tree_sha256=$record.receipt.tree_sha256
   production_mutation_authorized=$false
 }
 $path=Join-Path $p.vault ('cutover-intent-v052-'+$EscrowId+'.dpapi')
 $raw=[Text.UTF8Encoding]::new($false).GetBytes(($intent|ConvertTo-Json -Compress -Depth 8))
 try{
    $sealed=ConvertTo-CustomAppV050Sealed -Plain $raw -Purpose ('v052-cutover-intent|'+$EscrowId)
    try{Write-CustomAppV050NewBytes -Path $path -Bytes $sealed}
    finally{[Array]::Clear($sealed,0,$sealed.Length)}
 }finally{[Array]::Clear($raw,0,$raw.Length)}
 $pin=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
 [void](Get-CustomAppV052SealedIntent -Paths $p -EscrowId $EscrowId -IntentSha256 $pin)
 return [pscustomobject]@{ok=$true;status='hosted-cutover-recovery-intent-sealed'
   escrow_id=$EscrowId;intent_sha256=$pin;app_name=$AppName
   source_preimage_retained=$true;version_or_release_provenance_verified=$false
   production_mutation_authorized=$false;live_update_authorized=$false}
}
# V053 independent admission immediately before synthetic application, with
# the SAME V047 lease kept open across the first test side effect. A prior
# sealed intent alone is not a live execution authority.
function Test-CustomAppV053HostedBeforeApply {
 param([Parameter(Mandatory=$true)]$CutoverLease,
       [Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [Parameter(Mandatory=$true)][string]$HostedFixtureRoot,
       [Parameter(Mandatory=$true)][string]$HostedFixtureCliPath,
       [Parameter(Mandatory=$true)][string]$HostedEscrowRoot,
       [Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$IntentSha256,
       [Parameter(Mandatory=$true)][string]$CandidateXpuiRoot,
       [Parameter(Mandatory=$true)][string]$CandidateAppRoot)
 $p=Assert-CustomAppV052Fixture -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath -HostedEscrowRoot $HostedEscrowRoot
 if(-not(Test-CustomAppV052LiveTurnstile -Handle $CutoverLease.lock_handle -Paths $p) -or
    [string]$CutoverLease.binding_sha256 -cne $ExpectedProfileSha256){
    throw 'V053_BEFORE_APPLY_OS_LEASE_OR_BINDING_NOT_LIVE'
 }
 $intent=Get-CustomAppV052SealedIntent -Paths $p -EscrowId $EscrowId -IntentSha256 $IntentSha256
 if([string]$intent.expected_profile_sha256 -cne $ExpectedProfileSha256 -or
    -not[bool]$intent.v044_native_manifest_fence_verified -or
    [bool]$intent.actual_vendor_cli_invoked -or
    [bool]$intent.production_mutation_authorized){
    throw 'V053_BEFORE_APPLY_INTENT_NOT_BOUND'
 }
 $audit=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 -HostedFixtureRoot $p.base -HostedFixtureCliPath $p.cli
 if([string]$audit.status -cne 'observed-readonly' -or
    [string]$audit.manifest_footprint_sha256 -cne [string]$intent.manifest_footprint_sha256){
    throw 'V053_BEFORE_APPLY_SOURCE_PROFILE_CHANGED'
 }
 $app=Join-Path $p.apps ([string]$intent.app_name)
 $currentApp=Get-CustomAppUpdateTreeSnapshotV010 -Root $app
 $currentXpui=Get-CustomAppUpdateTreeSnapshotV010 -Root $p.xpui
 $candidateApp=Get-CustomAppUpdateTreeSnapshotV010 -Root (Assert-CustomAppV050Path -Path $CandidateAppRoot -FixtureRoot $CandidateAppRoot)
 $candidateXpui=Get-CustomAppUpdateTreeSnapshotV010 -Root (Assert-CustomAppV050Path -Path $CandidateXpuiRoot -FixtureRoot $CandidateXpuiRoot)
 if([string]$currentApp.tree_sha256 -cne [string]$intent.preimage_app_sha256 -or
    [string]$currentXpui.tree_sha256 -cne [string]$intent.preimage_xpui_sha256 -or
    [string]$candidateApp.tree_sha256 -cne [string]$intent.candidate_app_sha256 -or
    [string]$candidateXpui.tree_sha256 -cne [string]$intent.candidate_xpui_sha256){
     throw 'V053_BEFORE_APPLY_ORIGINAL_OR_CANDIDATE_HASH_CHANGED'
 }
 [void](Get-CustomAppV052OnlyChanged -Before $currentApp -After $candidateApp -OnlyRelativePath 'index.js')
 $proof=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $currentXpui -After $candidateXpui -Name ([string]$intent.app_name) -SourceAppPath $app -ExpectedSourceTreeSha256 ([string]$intent.owned_output_source_sha256)
 $fingerprint=Get-CustomAppUpdateStringSha256V010 -Text (
  (@('v053-native-manifest-owned-candidate',
    [string]$proof.source_tree_sha256,[string]$proof.manifest_sha256,
    [string]$proof.scoped_file_count,[string]$proof.scoped_extension_files,
    [string]$proof.scoped_asset_files,[string]$proof.pre_xpui_sha256,
    [string]$proof.post_xpui_sha256)) -join [char]10)
 if(-not[bool]$proof.ok -or -not[bool]$proof.foreign_xpui_preserved -or
    [string]$proof.manifest_sha256 -cne [string]$intent.owned_output_manifest_sha256 -or
    [int]$proof.scoped_file_count -ne [int]$intent.owned_output_file_count -or
    $fingerprint -cne [string]$intent.owned_output_scope_fingerprint -or
    [bool]$proof.production_mutation_authorized){
    throw 'V053_BEFORE_APPLY_NATIVE_OWNERSHIP_FINGERPRINT_CHANGED'
 }
 # Never convert this observation into a production permit or source release
 # attestation. Only the CI test may simulate applying these fixture bytes.
 return [pscustomobject]@{
    ok=$true;status='hosted-manifest-owned-candidate-unchanged-before-simulation'
    source_and_xpui_pinned=$true;v044_manifest_owned_output_verified=$true
    same_os_lease_held=$true;actual_vendor_cli_executed=$false
    real_release_provenance_verified=$false;older_unpatched_processes_excluded=$false
    production_mutation_authorized=$false;live_update_authorized=$false
 }
}
function Get-CustomAppV052TreeStatus {
 param([string]$Live,[string]$Quarantine,[string]$PreimageSha,[string]$CandidateSha)
 $livePresent=[IO.Directory]::Exists($Live)
 $qPresent=[IO.Directory]::Exists($Quarantine)
 foreach($entry in @($Live,$Quarantine)){
   if(-not[IO.Directory]::Exists($entry) -and
      ([IO.File]::Exists($entry) -or (Test-Path -LiteralPath $entry))){
      throw 'V052_TREE_REPLACED_BY_NON_DIRECTORY'
   }
 }
 $liveHash=if($livePresent){[string](Get-CustomAppUpdateTreeSnapshotV010 -Root $Live).tree_sha256}else{''}
 $qHash=if($qPresent){[string](Get-CustomAppUpdateTreeSnapshotV010 -Root $Quarantine).tree_sha256}else{''}
 if($qPresent -and $qHash -cne $CandidateSha){throw 'V052_UNTRUSTED_QUARANTINE_CHANGED'}
 if($livePresent -and $liveHash -cne $PreimageSha -and $liveHash -cne $CandidateSha){
    throw 'V052_UNEXPECTED_LIVE_FOREIGN_CHANGE'
 }
 if(-not$livePresent -and -not$qPresent){throw 'V052_MISSING_LIVE_AND_NO_QUARANTINE'}
 if($qPresent -and $liveHash -ceq $CandidateSha){
    throw 'V052_CANDIDATE_LIVE_AND_QUARANTINE_BOTH_PRESENT'
 }
 if(-not$livePresent -and -not$qPresent){throw 'V052_NO_RECOVERY_INPUT'}
 return [pscustomobject]@{live=$liveHash;quarantine=$qHash;has_live=$livePresent;has_quarantine=$qPresent}
}
function Restore-CustomAppV052Tree {
 param([string]$Live,[string]$Quarantine,[string]$Stage,[string]$Source,
       [string]$PreimageSha,[string]$CandidateSha,[string]$CrashAfter='none')
 $state=Get-CustomAppV052TreeStatus -Live $Live -Quarantine $Quarantine -PreimageSha $PreimageSha -CandidateSha $CandidateSha
 if($state.live -ceq $PreimageSha){
    if([IO.Directory]::Exists($Stage) -or [IO.File]::Exists($Stage)){
       throw 'V052_ORIGINAL_LIVE_WITH_UNEXPECTED_RESTAGE'
    }
    return
 }
 if([IO.File]::Exists($Stage) -or (Test-Path -LiteralPath $Stage -PathType Leaf)){
    throw 'V052_RESTORE_STAGE_NOT_DIRECTORY'
 }
 if(-not[IO.Directory]::Exists($Stage)){
   [void](Copy-CustomAppV050BoundTree -Source $Source -Destination $Stage)
 }
 if((Get-CustomAppUpdateTreeSnapshotV010 -Root $Stage).tree_sha256 -cne $PreimageSha){
    throw 'V052_PARTIAL_RESTAGE_REQUIRES_MANUAL_REVIEW'
 }
 if($state.live -ceq $CandidateSha -and -not$state.has_quarantine){
   [IO.Directory]::Move($Live,$Quarantine)
   if($CrashAfter -ceq 'after-quarantine'){throw 'V052_CONTROLLED_CRASH_AFTER_QUARANTINE'}
 }elseif($state.live -cne '' -or -not$state.has_quarantine){
   throw 'V052_CANNOT_RECOVER_UNKNOWN_PARTIAL_STATE'
 }
 # Same-volume directory rename is the only publication of the prepared old tree.
 [IO.Directory]::Move($Stage,$Live)
 if($CrashAfter -ceq 'after-restore'){throw 'V052_CONTROLLED_CRASH_AFTER_RESTORE'}
 if((Get-CustomAppUpdateTreeSnapshotV010 -Root $Live).tree_sha256 -cne $PreimageSha){
   throw 'V052_RESTORED_TREE_HASH_CHANGED'
 }
}
function Invoke-CustomAppHostedRollbackV052 {
 param([Parameter(Mandatory=$true)][string]$HostedFixtureRoot,
       [Parameter(Mandatory=$true)][string]$HostedFixtureCliPath,
       [Parameter(Mandatory=$true)][string]$HostedEscrowRoot,
       [Parameter(Mandatory=$true)][string]$EscrowId,
       [Parameter(Mandatory=$true)][string]$IntentSha256,
       [ValidateSet('none','after-app-quarantine','after-app-restore',
          'after-xpui-quarantine','after-xpui-restore')][string]$InjectedCrash='none')
 $p=Assert-CustomAppV052Fixture -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath -HostedEscrowRoot $HostedEscrowRoot
 $lease=$null
 try{
   $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot (Join-Path $p.base 'Local')
   if(-not(Test-CustomAppV052LiveTurnstile -Handle $lease -Paths $p)){
     throw 'V052_COOPERATIVE_LEGACY_NEW_LOCK_NOT_VERIFIED'
   }
   $intent=Get-CustomAppV052SealedIntent -Paths $p -EscrowId $EscrowId -IntentSha256 $IntentSha256
   $back=Get-CustomAppV051Receipt -EscrowId $EscrowId -ReceiptSha256 ([string]$intent.backup_receipt_sha256) -Vault $p.vault
   $good=Test-CustomAppV051DetachedRecovery -EscrowId $EscrowId -ReceiptSha256 ([string]$intent.backup_receipt_sha256) -HostedEscrowRoot $p.vault
   if(-not[bool]$good.ok -or
      [string]$back.receipt.tree_sha256.xpui -cne [string]$intent.preimage_xpui_sha256 -or
      [string]$back.receipt.tree_sha256.([string]$intent.app_name) -cne [string]$intent.preimage_app_sha256){
      throw 'V052_BASE_ESCROW_OR_DETACHED_RESTORE_INVALID'
   }
   $config=Join-Path $p.base 'Roaming\spicetify\config-xpui.ini'
   $prefs=Join-Path $p.base 'Roaming\Spotify\prefs'
   $state=Join-Path $p.base 'Local\SpotifyControl\addons-state.json'
   $map=@{config=$config;prefs=$prefs;state=$state}
   foreach($key in @('config','prefs','state')){
     if((Get-FileHash -LiteralPath $map[$key] -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        [string]$intent.protected_file_sha256.$key){
        throw 'V052_PROFILE_PROTECTED_FILE_CHANGED_AFTER_INTENT'
     }
   }
   $app=Join-Path $p.apps ([string]$intent.app_name)
   foreach($n in @($back.names|Where-Object{$_ -cne [string]$intent.app_name})){
     $unchanged=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $p.apps $n)
     if([string]$unchanged.tree_sha256 -cne [string]$back.receipt.tree_sha256.$n){
       throw 'V052_DIFFERENT_APPROVED_APP_CHANGED'
     }
   }
   $qRoot=Join-Path $p.vault ('quarantine-v052-'+$EscrowId)
   $appQ=Join-Path $qRoot 'app-candidate'
   $xpuiQ=Join-Path $qRoot 'xpui-candidate'
   $appStage=Join-Path $qRoot 'app-restage'
   $xpuiStage=Join-Path $qRoot 'xpui-restage'
   # Check BOTH independent live/current states BEFORE any mutation.
   [void](Get-CustomAppV052TreeStatus -Live $app -Quarantine $appQ -PreimageSha ([string]$intent.preimage_app_sha256) -CandidateSha ([string]$intent.candidate_app_sha256))
   [void](Get-CustomAppV052TreeStatus -Live $p.xpui -Quarantine $xpuiQ -PreimageSha ([string]$intent.preimage_xpui_sha256) -CandidateSha ([string]$intent.candidate_xpui_sha256))
   $terminal=Join-Path $p.vault ('rollback-complete-v052-'+$EscrowId+'.dpapi')
   if([IO.File]::Exists($terminal)){
     # A terminal marker can be reused only if all originals still match.
     foreach($pair in @(@($app,[string]$intent.preimage_app_sha256),@($p.xpui,[string]$intent.preimage_xpui_sha256))){
       if((Get-CustomAppUpdateTreeSnapshotV010 -Root $pair[0]).tree_sha256 -cne $pair[1]){
         throw 'V052_TERMINAL_MARKER_WITH_DRIFTED_LIVE_PROFILE'
       }
     }
     if([IO.Directory]::Exists($appStage) -or [IO.Directory]::Exists($xpuiStage)){
       throw 'V052_COMPLETED_WITH_ORPHAN_STAGED_TREE'
     }
     $tinfo=Get-Item -LiteralPath $terminal -Force
     if(($tinfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $tinfo.PSIsContainer -or $tinfo.Length -lt 96 -or $tinfo.Length -gt 65536){
        throw 'V052_TERMINAL_MARKER_UNTRUSTED'
     }
     $tbytes=[IO.File]::ReadAllBytes($terminal)
     $cipher=$null
     try{
       $cipher=New-Object byte[] ($tbytes.Length-32)
       [Array]::Copy($tbytes,32,$cipher,0,$cipher.Length)
       $digest=Get-CustomAppV050BytesHash -Data $cipher
       $header=([BitConverter]::ToString($tbytes,0,32)).Replace('-','').ToLowerInvariant()
       if($digest -cne $header){throw 'V052_TERMINAL_CIPHERTEXT_NOT_EXACT'}
       $tplain=ConvertFrom-CustomAppV050Sealed -Cipher $cipher -Purpose ('v052-rollback-terminal|'+$EscrowId)
       try{$t=([Text.UTF8Encoding]::new($false,$true).GetString($tplain))|ConvertFrom-Json -ErrorAction Stop}
       finally{[Array]::Clear($tplain,0,$tplain.Length)}
     }finally{
       if($null-ne$cipher){[Array]::Clear($cipher,0,$cipher.Length)}
       [Array]::Clear($tbytes,0,$tbytes.Length)
     }
     if([int]$t.schema -ne 1 -or
        [string]$t.escrow_id -cne $EscrowId -or
        [string]$t.intent_sha256 -cne $IntentSha256 -or
        [string]$t.original_app_sha256 -cne [string]$intent.preimage_app_sha256 -or
        [string]$t.original_xpui_sha256 -cne [string]$intent.preimage_xpui_sha256 -or
        [string]$t.owner -cne 'v052-hosted-rollback-complete' -or
        -not[bool]$t.quarantine_retained -or
        [bool]$t.production_mutation_authorized){
       throw 'V052_TERMINAL_SEAL_NOT_BOUND_TO_INTENT'
     }
     return [pscustomobject]@{ok=$true;status='hosted-rollback-already-complete'
       rollback_complete=$true;quarantine_retained=$true
       production_mutation_authorized=$false;live_update_authorized=$false}
   }
   if(-not[IO.Directory]::Exists($qRoot)){[IO.Directory]::CreateDirectory($qRoot)|Out-Null}
   $pre=Join-Path $p.vault ('reconstructed-v051-'+$EscrowId+'\trees')
   $appSrc=Join-Path $pre ([string]$intent.app_name)
   $xpuiSrc=Join-Path $pre 'xpui'
   $appCrash='none';$xpuiCrash='none'
   if($InjectedCrash -ceq 'after-app-quarantine'){$appCrash='after-quarantine'}
   if($InjectedCrash -ceq 'after-app-restore'){$appCrash='after-restore'}
   if($InjectedCrash -ceq 'after-xpui-quarantine'){$xpuiCrash='after-quarantine'}
   if($InjectedCrash -ceq 'after-xpui-restore'){$xpuiCrash='after-restore'}
   Restore-CustomAppV052Tree -Live $app -Quarantine $appQ -Stage $appStage -Source $appSrc -PreimageSha ([string]$intent.preimage_app_sha256) -CandidateSha ([string]$intent.candidate_app_sha256) -CrashAfter $appCrash
   Restore-CustomAppV052Tree -Live $p.xpui -Quarantine $xpuiQ -Stage $xpuiStage -Source $xpuiSrc -PreimageSha ([string]$intent.preimage_xpui_sha256) -CandidateSha ([string]$intent.candidate_xpui_sha256) -CrashAfter $xpuiCrash
   if((Get-CustomAppUpdateTreeSnapshotV010 -Root $app).tree_sha256 -cne [string]$intent.preimage_app_sha256 -or
      (Get-CustomAppUpdateTreeSnapshotV010 -Root $p.xpui).tree_sha256 -cne [string]$intent.preimage_xpui_sha256){
      throw 'V052_NOT_BOTH_SOURCE_AND_XPUI_ORIGINAL'
   }
   $t=[ordered]@{schema=1;owner='v052-hosted-rollback-complete'
      escrow_id=$EscrowId;intent_sha256=$IntentSha256;original_app_sha256=[string]$intent.preimage_app_sha256
      original_xpui_sha256=[string]$intent.preimage_xpui_sha256
      quarantine_retained=$true;production_mutation_authorized=$false}
   $raw=[Text.UTF8Encoding]::new($false).GetBytes(($t|ConvertTo-Json -Compress))
   try{
     $sealed=ConvertTo-CustomAppV050Sealed -Plain $raw -Purpose ('v052-rollback-terminal|'+$EscrowId)
     try{
       $sha=[Security.Cryptography.SHA256]::Create()
       try{$header=$sha.ComputeHash($sealed)}finally{$sha.Dispose()}
       $frame=New-Object byte[] ($sealed.Length+32)
       try{
         [Array]::Copy($header,0,$frame,0,32)
         [Array]::Copy($sealed,0,$frame,32,$sealed.Length)
         Write-CustomAppV050NewBytes -Path $terminal -Bytes $frame
       }finally{[Array]::Clear($frame,0,$frame.Length)}
     }finally{[Array]::Clear($sealed,0,$sealed.Length)}
   }finally{[Array]::Clear($raw,0,$raw.Length)}
   return [pscustomobject]@{ok=$true;status='hosted-scoped-rollback-complete'
      rollback_complete=$true;source_backup_retained=$true;quarantine_retained=$true
      production_mutation_authorized=$false;live_update_authorized=$false}
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
