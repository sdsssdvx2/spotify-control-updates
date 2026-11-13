# Hosted Windows PowerShell 5.1 only: R131 actual source helper integration.
# Synthetic Spotify Apps and roaming Spicetify surface only; never touch owner.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
  throw 'R131_HOSTED_WINDOWS_ONLY'
}
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$candidate=Join-Path $base 'out/atomic-spicetify-preprocess-migration-R131/spotify-control.ps1'
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($candidate,[ref]$tokens,[ref]$errors)
if(@($errors).Count -ne 0){throw 'R131_SOURCE_AST_NOT_VALID'}
$required=@('New-SpicetifyMigrationPreimage','Restore-SpicetifyMigrationSurface',
  'Restore-SpicetifyMigrationPreimage','Confirm-SpicetifyMigrationApplied',
  'Get-SpicetifyRootManifest','Copy-SpicetifyRootExact','Get-ExactFileSha256',
  'Get-StringSha256','Get-SpicetifyConfigSemanticHash','Get-IniSectionValue',
  'Commit-SpicetifyCliTransaction','Rollback-SpicetifyCliTransaction',
  'Invoke-SpicetifyTransactionalMaintenance',
  'Repair-PendingSpicetifyTransaction',
  'Assert-SpicetifyOwnerPreimageAdoption',
  'Save-SpicetifyTransaction','Write-SpicetifyJournalJsonAtomic')
$fns=@($ast.FindAll({param($x)
  $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $x.Name -cin $required
},$true))
if($fns.Count -ne $required.Count){throw 'R131_REQUIRED_REAL_FUNCTIONS_NOT_PRESENT'}
. ([ScriptBlock]::Create((@($fns|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine)))
function Test-UsablePath {
  param([string]$Path,[string]$PathType)
  return (Test-Path -LiteralPath $Path -PathType $PathType)
}
function Test-SpotifyRunning {return $false}
function Get-ConfigPath {return (Join-Path $env:APPDATA 'spicetify/config-xpui.ini')}
$previousAppdata=$env:APPDATA
$scratch=Join-Path $env:RUNNER_TEMP ('R131-Synthetic-'+[guid]::NewGuid().ToString('N'))
$env:APPDATA=Join-Path $scratch 'Roaming'
try {
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify/Apps'
  $backupDir=Join-Path $scratch 'OwnerBackup/spicetify-transactions/20261113-180011-abcdef01'
  foreach($dir in @($spice,$apps,(Join-Path $spice 'Backup'),
      (Join-Path $spice 'Themes'),$backupDir)){
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $utf8=New-Object System.Text.UTF8Encoding($false)
  $nl=[Environment]::NewLine
  $ini='[Backup]'+$nl+'version=1.3.6.1921.gtest'+$nl+'with=2.46.4'+$nl+
     '[Setting]'+$nl+'current_theme=UserTheme'+$nl
  $iniAfter=$ini.Replace('with=2.46.4','with=2.46.7')
  [IO.File]::WriteAllText((Join-Path $spice 'config-xpui.ini'),$ini,$utf8)
  [IO.File]::WriteAllText((Join-Path $spice 'Themes/theme.css'),'user-theme-original',$utf8)
  [IO.File]::WriteAllBytes((Join-Path $spice 'Backup/xpui.spa'),([byte[]]@(0,1,3,255,0,10)))
  [IO.File]::WriteAllBytes((Join-Path $apps 'xpui.spa'),([byte[]]@(4,3,255,0,88,5)))
  # Exercise actual product journal publication on scratch NTFS.
  function Ensure-SpicetifyTransactionShape {param($Transaction);return $Transaction}
  $ledgerDir=Join-Path $scratch 'AtomicJournal'
  New-Item -ItemType Directory -Path $ledgerDir -Force | Out-Null
  $script:SpicetifyTransactionPath=Join-Path $ledgerDir 'last-transaction.json'
  $script:SpicetifyTransactionReport=Join-Path $ledgerDir 'report.json'
  $journalA=[pscustomobject]@{schema=3;id='scratch-only';status='prepared'}
  Save-SpicetifyTransaction -Transaction $journalA
  $oldHash=Get-ExactFileSha256 -Path $script:SpicetifyTransactionPath
  $journalB=[pscustomobject]@{schema=3;id='scratch-only';status='awaiting-guard'}
  Save-SpicetifyTransaction -Transaction $journalB
  $current=Get-Content -LiteralPath $script:SpicetifyTransactionPath -Raw | ConvertFrom-Json
  $report=Get-Content -LiteralPath $script:SpicetifyTransactionReport -Raw | ConvertFrom-Json
  $preFile=$script:SpicetifyTransactionPath+'.previous'
  if($current.status -cne 'awaiting-guard' -or
     $report.status -cne 'awaiting-guard' -or
     (Get-ExactFileSha256 -Path $preFile) -cne $oldHash){
    throw 'R131_ATOMIC_SCHEMA3_JOURNAL_READBACK_FAILURE'
  }
  $tempCount=@(Get-ChildItem -LiteralPath $ledgerDir -File -Filter '.spotifycontrol-journal-*.tmp').Count
  if($tempCount -ne 0){throw 'R131_JOURNAL_UNEXPECTED_TEMP_LEFTOVER'}
  Write-Host 'R131_PRODUCTION_ATOMIC_PRIMARY_REPORT_AND_PREVIOUS_SNAPSHOT=PASS'
  $beforeSpice=Get-SpicetifyRootManifest -Path $spice
  $beforeApps=Get-SpicetifyRootManifest -Path $apps
  $pre=New-SpicetifyMigrationPreimage -TransactionBackupDir $backupDir -InstalledCliVersion '2.46.4'
  if($pre.RoamingTreeSha256 -cne $beforeSpice.TreeSha256 -or
     $pre.AppsTreeSha256 -cne $beforeApps.TreeSha256){
    throw 'R131_BOTH_EXTERNAL_SNAPSHOTS_NOT_EXACT'
  }
  $tx=[pscustomobject]@{
    migration_required=$true;migration_snapshot_ready=$true;migration_started=$true
    id='20261113-180011-abcdef01'
    backup_root=(Join-Path $backupDir 'root-before')
    migration_snapshot_root=$pre.BackupRoot
    migration_spicetify_root=$pre.Roaming
    migration_apps_root=$pre.Apps
    migration_spicetify_before_sha256=$pre.RoamingTreeSha256
    migration_apps_before_sha256=$pre.AppsTreeSha256
    migration_semantic_before_sha256=$pre.SemanticHash
    after_version='2.46.7'
    migration_apps_after_sha256=$null
    migration_spicetify_after_sha256=$null
    migration_finished=$false
  }
  # Simulate exactly the external writes a new CLI can cause, no real CLI call.
  [IO.File]::WriteAllText((Join-Path $spice 'config-xpui.ini'),$iniAfter,$utf8)
  [IO.File]::WriteAllText((Join-Path $apps 'xpui.spa'),'altered Spotify application',$utf8)
  [IO.File]::WriteAllBytes((Join-Path $spice 'Backup/xpui.spa'),([byte[]]@(33,34,35)))
  $tx=Confirm-SpicetifyMigrationApplied $tx
  if(-not $tx.migration_finished -or
     $tx.migration_apps_after_sha256 -ceq $tx.migration_apps_before_sha256){
    throw 'R131_MIGRATION_AFTER_PROOF_MISSING'
  }
  # Exercise the production COMMIT function: changing Apps after successful
  # apply must not rewrite its durable after-pin by object aliasing.
  $cliRoot=Join-Path $scratch 'SyntheticCLI'
  New-Item -ItemType Directory -Path $cliRoot -Force | Out-Null
  $exe=Join-Path $cliRoot 'spicetify.exe'
  [IO.File]::WriteAllBytes($exe,([byte[]]@(77,90,4,0,4,0)))
  $rootManifest=Get-SpicetifyRootManifest -Path $cliRoot
  $script:TxnForCommit=($tx|ConvertTo-Json -Depth 8|ConvertFrom-Json)
  $script:TxnForCommit|Add-Member -NotePropertyName 'target_root' -NotePropertyValue $cliRoot
  $script:TxnForCommit|Add-Member -NotePropertyName 'after_tree_sha256' -NotePropertyValue $rootManifest.TreeSha256
  $script:TxnForCommit|Add-Member -NotePropertyName 'after_sha256' -NotePropertyValue ((Get-ExactFileSha256 -Path $exe))
  $script:TxnForCommit|Add-Member -NotePropertyName 'root_transaction' -NotePropertyValue $true
  $script:TxnForCommit|Add-Member -NotePropertyName 'status' -NotePropertyValue 'awaiting-guard'
  $script:TxnForCommit|Add-Member -NotePropertyName 'before_version' -NotePropertyValue '2.46.4'
  $script:TxnForCommit|Add-Member -NotePropertyName 'committed_at' -NotePropertyValue $null
  $script:TxnForCommit|Add-Member -NotePropertyName 'extras_preserved' -NotePropertyValue $true
  $script:TxnForCommit|Add-Member -NotePropertyName 'extras_before_tree_sha256' -NotePropertyValue ('a'*64)
  $script:TxnForCommit|Add-Member -NotePropertyName 'extras_after_tree_sha256' -NotePropertyValue ('a'*64)
  $script:TxnForCommit|Add-Member -NotePropertyName 'apply_succeeded' -NotePropertyValue $true
  $script:TxnForCommit|Add-Member -NotePropertyName 'post_apply_guard_succeeded' -NotePropertyValue $true
  $script:TxnForCommit|Add-Member -NotePropertyName 'same_dir_old_root' -NotePropertyValue ''
  $script:TxnForCommit|Add-Member -NotePropertyName 'same_dir_new_root' -NotePropertyValue ''
  function Get-SpicetifyTransaction {return $script:TxnForCommit}
  function Save-SpicetifyTransaction {param($Transaction);$script:TxnForCommit=$Transaction}
  function Invoke-NativeCapture {
    param([string]$FilePath,[string[]]$Arguments)
    return [pscustomobject]@{ExitCode=0;Output='Spicetify 2.46.7'}
  }
  function Write-Log {param([string]$Message,[string]$Level='INFO')}
  $appAfterFirst=[IO.File]::ReadAllBytes((Join-Path $apps 'xpui.spa'))
  [IO.File]::WriteAllText((Join-Path $apps 'xpui.spa'),'post-apply-tampered-content',$utf8)
  $blocked=$false
  try{[void](Commit-SpicetifyCliTransaction)}catch{
    $blocked=$_.Exception.Message -match 'R131_COMMIT_EXTERNAL_AFTER_TREE_CHANGED'
  }
  if(-not $blocked){throw 'R131_COMMIT_DID_NOT_BLOCK_AFTER_IMAGE_DRIFT'}
  if([string]$script:TxnForCommit.status -cne 'awaiting-guard' -or
     [string]$script:TxnForCommit.migration_apps_after_sha256 -cne [string]$tx.migration_apps_after_sha256){
    throw 'R131_FAILED_COMMIT_MUTATED_DURABLE_EXPECTATION'
  }
  [IO.File]::WriteAllBytes((Join-Path $apps 'xpui.spa'),$appAfterFirst)
  [void](Commit-SpicetifyCliTransaction)
  if([string]$script:TxnForCommit.status -cne 'committed'){
    throw 'R131_PINNED_EXTERNAL_AFTER_IMAGE_NOT_COMMITTED'
  }
  Write-Host 'R131_COMMIT_REJECTS_CHANGED_EXTERNAL_AFTER_IMAGE=PASS'
  Write-Host 'R131_COMMIT_ACCEPTS_STABLE_EXTERNAL_AFTER_IMAGE=PASS'
  $res=Restore-SpicetifyMigrationPreimage $tx
  if(-not $res.Restored -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne $pre.AppsTreeSha256 -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne $pre.RoamingTreeSha256){
    throw 'R131_EXTERNAL_PREIMAGE_BYTES_NOT_RESTORED'
  }
  $again=Restore-SpicetifyMigrationPreimage $tx
  if(-not $again.Restored){throw 'R131_ROLLBACK_NOT_IDEMPOTENT'}
  $quarantine=Join-Path (Split-Path -Parent $apps) '.spotifycontrol-r131-quarantine-apps-20261113-180011-abcdef01'
  if(-not (Test-Path -LiteralPath $quarantine -PathType Container)){
    throw 'R131_MODIFIED_APPS_NOT_RETAINED'
  }
  Write-Host 'R131_WINDOWS_REAL_SOURCE_EXTERNAL_PREIMAGE=PASS'
  Write-Host 'R131_WINDOWS_REAL_SOURCE_EXACT_EXTERNAL_ROLLBACK=PASS'
  Write-Host 'R131_WINDOWS_REPEATED_RECOVERY_IS_NOOP=PASS'
  Write-Host 'R131_WINDOWS_QUARANTINE_UNKNOWN_CHANGES=PASS'
  # Simulate abrupt termination after live Apps was moved aside but before
  # the verified staged original was published: this must resume safely.
  $resumeId='20261113-180012-abcdef02'
  $appsParent=Split-Path -Parent $apps
  $heldApps=Join-Path $appsParent ('.spotifycontrol-r131-quarantine-apps-'+$resumeId)
  $stageApps=Join-Path $appsParent ('.spotifycontrol-r131-staged-apps-'+$resumeId)
  [IO.File]::WriteAllText((Join-Path $apps 'xpui.spa'),'interrupted-transaction-current',$utf8)
  [void](Copy-SpicetifyRootExact -Source $pre.AppsBackup -Destination $stageApps -ExpectedTreeSha256 $pre.AppsTreeSha256)
  Move-Item -LiteralPath $apps -Destination $heldApps -ErrorAction Stop
  $resumed=Restore-SpicetifyMigrationSurface -Path $apps -Backup $pre.AppsBackup -BeforeSha256 $pre.AppsTreeSha256 -TransactionId $resumeId -Suffix 'apps'
  if(-not $resumed.Resumed -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne $pre.AppsTreeSha256 -or
     -not (Test-Path -LiteralPath $heldApps -PathType Container)){
    throw 'R131_INTERRUPTED_STAGED_RESTORE_NOT_RESUMED_EXACT'
  }
  # A later external edit must not be overwritten even if an older
  # transaction quarantine is still present.
  [IO.File]::WriteAllText((Join-Path $apps 'xpui.spa'),'third-party-after-restore',$utf8)
  $blockedForeign=$false
  try{
    [void](Restore-SpicetifyMigrationSurface -Path $apps -Backup $pre.AppsBackup -BeforeSha256 $pre.AppsTreeSha256 -TransactionId $resumeId -Suffix 'apps')
  }catch{$blockedForeign=$_.Exception.Message -match 'R131_RESTORE_RESERVED_PATH_ALREADY_EXISTS'}
  if(-not $blockedForeign){throw 'R131_FOREIGN_LIVE_TREE_WAS_NOT_PROTECTED'}
  [IO.File]::WriteAllBytes((Join-Path $apps 'xpui.spa'),([byte[]]@(4,3,255,0,88,5)))
  # Test a crash with the staged original absent: recreate only from the
  # still-verified preimage; leave the displaced unknown tree untouched.
  $resumeId2='20261113-180013-abcdef03'
  $heldSpice=Join-Path (Split-Path -Parent $spice) ('.spotifycontrol-r131-quarantine-roaming-'+$resumeId2)
  [IO.File]::WriteAllText((Join-Path $spice 'Themes/theme.css'),'interrupted-roaming-current',$utf8)
  Move-Item -LiteralPath $spice -Destination $heldSpice -ErrorAction Stop
  $resumed2=Restore-SpicetifyMigrationSurface -Path $spice -Backup $pre.RoamingBackup -BeforeSha256 $pre.RoamingTreeSha256 -TransactionId $resumeId2 -Suffix 'roaming'
  if(-not $resumed2.Resumed -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne $pre.RoamingTreeSha256 -or
     -not (Test-Path -LiteralPath $heldSpice -PathType Container)){
    throw 'R131_INTERRUPTED_UNSTAGED_RESTORE_NOT_RESUMED_EXACT'
  }
  Write-Host 'R131_INTERRUPTED_STAGED_AND_UNSTAGED_RESTORE_RESUME=PASS'
  Write-Host 'R131_INTERRUPTED_RECOVERY_FOREIGN_TREE_NO_CLOBBER=PASS'
  # Exercise the actual product rollback, not just the external helper:
  # a fully swapped CLI root and both modified external surfaces must be
  # restored through the same durable transaction. In the migration branch,
  # old CLI 'apply' is intentionally NOT rerun over exact restored bytes.
  $recoveryId='20261113-180014-abcdef04'
  $recoveryDir=Join-Path $scratch ('OwnerBackup/spicetify-transactions/'+$recoveryId)
  New-Item -ItemType Directory -Path $recoveryDir -Force | Out-Null
  $recoveryPre=New-SpicetifyMigrationPreimage -TransactionBackupDir $recoveryDir -InstalledCliVersion '2.46.4'
  $cliBefore=Get-SpicetifyRootManifest -Path $cliRoot
  $exeBefore=(Get-ExactFileSha256 -Path $exe)
  $cliBackup=Join-Path $recoveryDir 'root-before'
  [void](Copy-SpicetifyRootExact -Source $cliRoot -Destination $cliBackup -ExpectedTreeSha256 $cliBefore.TreeSha256)
  [IO.File]::WriteAllBytes($exe,([byte[]]@(77,90,31,2,46,7)))
  $cliAfter=Get-SpicetifyRootManifest -Path $cliRoot
  [IO.File]::WriteAllText((Join-Path $spice 'config-xpui.ini'),$iniAfter,$utf8)
  [IO.File]::WriteAllText((Join-Path $spice 'Themes/theme.css'),'migration-changed-theme',$utf8)
  [IO.File]::WriteAllBytes((Join-Path $apps 'xpui.spa'),([byte[]]@(77,79,68,73,70,73,69,68)))
  $script:TxnForCommit=[pscustomobject]@{
    schema=3;root_transaction=$true;id=$recoveryId;status='awaiting-guard'
    target_root=$cliRoot;backup_root=$cliBackup
    same_dir_old_root=(Join-Path $scratch 'NeverExists-OldCliRoot')
    same_dir_new_root=(Join-Path $scratch 'NeverExists-NewCliRoot')
    before_tree_sha256=$cliBefore.TreeSha256;after_tree_sha256=$cliAfter.TreeSha256
    before_sha256=$exeBefore;after_sha256=(Get-ExactFileSha256 -Path $exe)
    before_version='2.46.4';after_version='2.46.7';apply_attempted=$true
    migration_required=$true;migration_snapshot_ready=$true
    migration_snapshot_root=$recoveryPre.BackupRoot
    migration_spicetify_root=$recoveryPre.Roaming
    migration_apps_root=$recoveryPre.Apps
    migration_spicetify_before_sha256=$recoveryPre.RoamingTreeSha256
    migration_apps_before_sha256=$recoveryPre.AppsTreeSha256
    migration_semantic_before_sha256=$recoveryPre.SemanticHash
    migration_started=$true
    migration_external_rollback_restored=$false
    rollback_reapply_succeeded=$null;rollback_reapply_at=$null
    rolled_back_at=$null;error=$null
  }
  $script:OldCliApplyCalls=0
  function Invoke-NativeCapture {
    param([string]$FilePath,[string[]]$Arguments)
    if($Arguments -contains 'apply'){
      $script:OldCliApplyCalls++
      return [pscustomobject]@{ExitCode=90;Output='UNEXPECTED_OLD_CLI_APPLY'}
    }
    if(@($Arguments).Count -ne 1 -or $Arguments[0] -cne '--version'){
      throw 'R131_ROLLBACK_UNEXPECTED_NATIVE_CALL'
    }
    return [pscustomobject]@{ExitCode=0;Output='Spicetify 2.46.4'}
  }
  function Get-SpicetifyCommand {return $null}
  $rolled=Rollback-SpicetifyCliTransaction
  if(-not $rolled.Success -or $rolled.Status -cne 'rolled-back' -or
     $script:TxnForCommit.status -cne 'rolled-back' -or
     -not $script:TxnForCommit.migration_external_rollback_restored -or
     $script:OldCliApplyCalls -ne 0 -or
     (Get-SpicetifyRootManifest -Path $cliRoot).TreeSha256 -cne $cliBefore.TreeSha256 -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne $recoveryPre.AppsTreeSha256 -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne $recoveryPre.RoamingTreeSha256){
    throw 'R131_PRODUCTION_FULL_ROOT_AND_EXTERNAL_ROLLBACK_FAILED'
  }
  Write-Host 'R131_PRODUCTION_ROLLBACK_CLI_APPS_CONFIG_TOGETHER=PASS'
  Write-Host 'R131_PRODUCTION_MIGRATION_ROLLBACK_NO_OLD_REAPPLY=PASS'
  # Rehearse a second interruption in the *CLI root* rollback.
  # The after-root was moved into exact transaction quarantine and the
  # before-root copy was staged, but the process died before publication.
  $rootCrashId='20261113-180015-abcdef05'
  $rootCrashDir=Join-Path $scratch ('OwnerBackup/spicetify-transactions/'+$rootCrashId)
  New-Item -ItemType Directory -Path $rootCrashDir -Force | Out-Null
  $crashPre=New-SpicetifyMigrationPreimage -TransactionBackupDir $rootCrashDir -InstalledCliVersion '2.46.4'
  $crashBeforeRoot=Get-SpicetifyRootManifest -Path $cliRoot
  $crashBeforeExe=(Get-ExactFileSha256 -Path $exe)
  $crashRootBackup=Join-Path $rootCrashDir 'root-before'
  [void](Copy-SpicetifyRootExact -Source $cliRoot -Destination $crashRootBackup -ExpectedTreeSha256 $crashBeforeRoot.TreeSha256)
  [IO.File]::WriteAllBytes($exe,([byte[]]@(77,90,45,2,46,7)))
  $crashAfterRoot=Get-SpicetifyRootManifest -Path $cliRoot
  $script:TxnForCommit.id=$rootCrashId
  $script:TxnForCommit.status='awaiting-guard'
  $script:TxnForCommit.backup_root=$crashRootBackup
  $script:TxnForCommit.before_tree_sha256=$crashBeforeRoot.TreeSha256
  $script:TxnForCommit.after_tree_sha256=$crashAfterRoot.TreeSha256
  $script:TxnForCommit.before_sha256=$crashBeforeExe
  $script:TxnForCommit.after_sha256=(Get-ExactFileSha256 -Path $exe)
  $script:TxnForCommit.migration_snapshot_root=$crashPre.BackupRoot
  $script:TxnForCommit.migration_spicetify_before_sha256=$crashPre.RoamingTreeSha256
  $script:TxnForCommit.migration_apps_before_sha256=$crashPre.AppsTreeSha256
  $script:TxnForCommit.migration_semantic_before_sha256=$crashPre.SemanticHash
  $script:TxnForCommit.migration_external_rollback_restored=$false
  $crashQuarantine=Join-Path (Split-Path -Parent $cliRoot) ('.spotifycontrol-spicetify-rollback-current-'+$rootCrashId)
  $crashStage=Join-Path (Split-Path -Parent $cliRoot) ('.spotifycontrol-spicetify-restore-'+$rootCrashId)
  [void](Copy-SpicetifyRootExact -Source $crashRootBackup -Destination $crashStage -ExpectedTreeSha256 $crashBeforeRoot.TreeSha256)
  Move-Item -LiteralPath $cliRoot -Destination $crashQuarantine -ErrorAction Stop
  $crashResult=Rollback-SpicetifyCliTransaction
  if(-not $crashResult.Success -or $crashResult.Status -cne 'rolled-back' -or
     (Get-SpicetifyRootManifest -Path $cliRoot).TreeSha256 -cne $crashBeforeRoot.TreeSha256 -or
     -not $script:TxnForCommit.migration_external_rollback_restored -or
     $script:OldCliApplyCalls -ne 0){
    throw 'R131_INTERRUPTED_CLI_ROOT_ROLLBACK_DID_NOT_RESUME'
  }
  Write-Host 'R131_PRODUCTION_INTERRUPTED_CLI_ROOT_ROLLBACK_RESUMED=PASS'
  # Execute the real maintenance coordinator against an isolated complete
  # synthetic transaction. Only the upstream CLI process and network-dependent
  # starter/guard are substituted; commit, rollback, migration confirmation,
  # root manifest and file restore are actual R131 production functions.
  function Ensure-StateShape {param($State);return $State}
  function Save-State {param($State);$script:R131SavedState=$State}
  function Load-State {return $script:R131SavedState}
  function Repair-PendingSpicetifyTransaction {return $null}
  function Get-SmartUpdateGuardPlan {
    return [pscustomobject]@{
      CurrentSupported=$true;MinSupported='1.3.0';MaxSupported='1.3.9'
      SpicetifyTag='v2.46.7'
    }
  }
  function Invoke-SmartUpdateGuard {
    param($State,$Plan)
    return [pscustomobject]@{Success=$true;State=$State}
  }
  function Get-InstalledSpicetifyVersion {return '2.46.7'}
  function Get-SpicetifyManagedInstallInfo {
    return [pscustomobject]@{Mode='OFFICIAL_PINNED_SYNTHETIC'}
  }
  function Get-SpicetifyCommand {return $exe}
  $script:R131Attempt=0
  $script:R131NativeApply=0
  $script:R131SpyCalls=0
  $script:R131SimulateFailure=$false
  function Start-SpicetifyCliTransaction {
    param([switch]$ForceReinstall)
    $script:R131Attempt++
    if($script:R131Attempt -gt 2){throw 'R131_SYNTHETIC_UNEXPECTED_EXTRA_START'}
    $id=if($script:R131Attempt -eq 1){
      '20261113-180020-abcdef06'
    }else{'20261113-180021-abcdef07'}
    $dir=Join-Path $scratch ('OwnerBackup/spicetify-transactions/'+$id)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $pre=New-SpicetifyMigrationPreimage -TransactionBackupDir $dir -InstalledCliVersion '2.46.4'
    $old=Get-SpicetifyRootManifest -Path $cliRoot
    $rootBackup=Join-Path $dir 'root-before'
    [void](Copy-SpicetifyRootExact -Source $cliRoot -Destination $rootBackup -ExpectedTreeSha256 $old.TreeSha256)
    $oldExeHash=Get-ExactFileSha256 -Path $exe
    [IO.File]::WriteAllBytes($exe,([byte[]]@(77,90,51,2,46,7)))
    $new=Get-SpicetifyRootManifest -Path $cliRoot
    $script:R131BeforeExeHash=$oldExeHash
    $script:R131AfterExeHash=Get-ExactFileSha256 -Path $exe
    $script:TxnForCommit=[pscustomobject]@{
      schema=3;root_transaction=$true;id=$id;status='awaiting-guard'
      target_root=$cliRoot;backup_root=$rootBackup
      same_dir_old_root=(Join-Path $scratch ('NeverExists-Old-'+$id))
      same_dir_new_root=(Join-Path $scratch ('NeverExists-New-'+$id))
      before_tree_sha256=$old.TreeSha256;after_tree_sha256=$new.TreeSha256
      before_sha256=$oldExeHash;after_sha256=$script:R131AfterExeHash
      before_version='2.46.4';after_version='2.46.7'
      release_tag='v2.46.7';asset_digest='sha256:SYNTHETIC_ONLY'
      apply_attempted=$false;apply_succeeded=$false;apply_at=$null
      post_apply_guard_succeeded=$false;post_apply_guard_at=$null
      extras_preserved=$true
      extras_before_tree_sha256=('a'*64);extras_after_tree_sha256=('a'*64)
      migration_required=$true;migration_snapshot_ready=$true
      migration_started=$false;migration_finished=$false
      migration_snapshot_root=$pre.BackupRoot
      migration_spicetify_root=$pre.Roaming
      migration_apps_root=$pre.Apps
      migration_spicetify_before_sha256=$pre.RoamingTreeSha256
      migration_apps_before_sha256=$pre.AppsTreeSha256
      migration_semantic_before_sha256=$pre.SemanticHash
      migration_spicetify_after_sha256=$null
      migration_apps_after_sha256=$null
      migration_external_rollback_restored=$false
      rollback_reapply_succeeded=$null;rollback_reapply_at=$null
      committed_at=$null;rolled_back_at=$null;error=$null
    }
    $script:R131AttemptBefore=$pre
    return [pscustomobject]@{
      Changed=$true;Transaction=$script:TxnForCommit
      Latest=[pscustomobject]@{Tag='v2.46.7'}
    }
  }
  function Invoke-NativeCapture {
    param([string]$FilePath,[string[]]$Arguments)
    if(@($Arguments).Count -ne 1 -or $Arguments[0] -cne '--version'){
      $script:R131NativeApply++
      throw 'R131_SYNTHETIC_NATIVE_OLD_APPLY_NOT_ALLOWED'
    }
    $now=Get-ExactFileSha256 -Path $FilePath
    $ver=if($now -ceq $script:R131BeforeExeHash){'2.46.4'
      }elseif($now -ceq $script:R131AfterExeHash){'2.46.7'
      }else{throw 'R131_SYNTHETIC_UNKNOWN_CLI_BYTES'}
    return [pscustomobject]@{ExitCode=0;Output=('Spicetify '+$ver)}
  }
  function Invoke-Spice {
    param([string[]]$Arguments)
    if(($Arguments -join ' ') -cne 'restore backup apply --no-restart'){
      throw 'R131_SYNTHETIC_WRONG_OFFICIAL_COMMAND'
    }
    $script:R131SpyCalls++
    [IO.File]::WriteAllText((Join-Path $spice 'config-xpui.ini'),$iniAfter,$utf8)
    [IO.File]::WriteAllText((Join-Path $spice 'Backup/xpui.spa'),'processed-new-cli',$utf8)
    [IO.File]::WriteAllText((Join-Path $apps 'xpui.spa'),'applied-new-cli',$utf8)
    if($script:R131SimulateFailure){
      throw 'R131_SYNTHETIC_APPLY_EXIT_NONZERO'
    }
  }
  function New-R131CoordinatorState {
    return [pscustomobject]@{
      last_spicetify_upgrade_check=$null;pending_spicetify_upgrade=$true
      spicetify_installed_version='2.46.4'
      spicetify_install_mode=$null
      spicetify_compat_tag=$null;spicetify_compat_min_windows=$null
      spicetify_max_windows=$null;spicetify_latest_tag=$null
      spicetify_last_digest=$null
      spicetify_last_transaction_id=$null
      spicetify_last_transaction_status=$null
      spicetify_last_transaction_utc=$null
    }
  }
  $initial=New-R131CoordinatorState
  Save-State $initial
  $script:R131SimulateFailure=$false
  $outcome=Invoke-SpicetifyTransactionalMaintenance -State $initial
  if(-not $outcome.Success -or $outcome.Status -cne 'committed' -or
     $script:TxnForCommit.status -cne 'committed' -or
     -not $script:TxnForCommit.migration_finished -or
     $script:R131SpyCalls -ne 1 -or $script:R131NativeApply -ne 0 -or
     $outcome.State.spicetify_installed_version -cne '2.46.7' -or
     $outcome.State.pending_spicetify_upgrade -ne $false){
    throw 'R131_ACTUAL_MAINTENANCE_COORDINATOR_COMMIT_INVALID'
  }
  Write-Host 'R131_REAL_COORDINATOR_SYNTHETIC_UPGRADE_AND_COMMIT=PASS'
  # Reset only this scratch fixture to the old version. A committed real
  # transaction is never automatically rolled back in production.
  [void](Restore-SpicetifyMigrationPreimage -Txn $script:TxnForCommit)
  [IO.File]::WriteAllBytes($exe,([byte[]]@(77,90,4,0,4,0)))
  $initial=New-R131CoordinatorState
  Save-State $initial
  $script:R131SimulateFailure=$true
  $failed=Invoke-SpicetifyTransactionalMaintenance -State $initial
  if($failed.Success -or $failed.Status -cne 'rolled-back-apply-failure' -or
     $script:TxnForCommit.status -cne 'rolled-back' -or
     $failed.State.pending_spicetify_upgrade -ne $true -or
     $script:R131SpyCalls -ne 2 -or $script:R131NativeApply -ne 0 -or
     (Get-SpicetifyRootManifest -Path $cliRoot).TreeSha256 -cne
       $script:TxnForCommit.before_tree_sha256 -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne
       $script:R131AttemptBefore.AppsTreeSha256 -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne
       $script:R131AttemptBefore.RoamingTreeSha256){
    throw 'R131_ACTUAL_MAINTENANCE_COORDINATOR_FAILED_APPLY_NOT_ROLLED_BACK'
  }
  Write-Host 'R131_REAL_COORDINATOR_SYNTHETIC_APPLY_FAILURE_AND_ROLLBACK=PASS'
  # Restore the actual product function after the isolated coordinator
  # deliberately substituted a no-op admission fixture.
  $repairDefs=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Repair-PendingSpicetifyTransaction'
  },$true))
  if($repairDefs.Count -ne 1){throw 'R131_REAL_REPAIR_FUNCTION_NOT_UNIQUE'}
  . ([ScriptBlock]::Create($repairDefs[0].Extent.Text))
  # Fail closed before any mutation when a previous R112/R130 journal lacks
  # complete R131 external-preimage provenance (owner review required).
  $legacy=[pscustomobject]@{
    schema=3;root_transaction=$true;id='20261113-170000-aabbccdd'
    status='awaiting-guard';apply_attempted=$true
  }
  $script:TxnForCommit=$legacy
  $legacyBefore=$legacy|ConvertTo-Json -Compress
  $nativeBefore=$script:R131NativeApply
  $held=$false
  try{[void](Repair-PendingSpicetifyTransaction)}catch{
    $held=$_.Exception.Message -match 'R131_UNSETTLED_PRE_MIGRATION_LEDGER_OWNER_REVIEW_HOLD'
  }
  if(-not $held -or ($script:TxnForCommit|ConvertTo-Json -Compress) -cne $legacyBefore -or
      $script:R131NativeApply -ne $nativeBefore){
    throw 'R131_UNSETTLED_LEGACY_LEDGER_MUST_BE_FROZEN'
  }
  Write-Host 'R131_UNSETTLED_R112_LEDGER_AUTO_REPAIR_BLOCKED=PASS'
  $partial=[pscustomobject]@{
    schema=3;root_transaction=$true;id='20261113-170100-aabbccdd'
    status='awaiting-guard';apply_attempted=$true
    migration_required=$true;migration_snapshot_ready=$false
    migration_snapshot_root=$null
    migration_spicetify_before_sha256=$null
    migration_apps_before_sha256=$null
  }
  $script:TxnForCommit=$partial
  $partialBefore=$partial|ConvertTo-Json -Compress
  $held=$false
  try{[void](Repair-PendingSpicetifyTransaction)}catch{
    $held=$_.Exception.Message -match 'R131_UNSETTLED_MIGRATION_SNAPSHOT_NOT_CERTIFIED_HOLD'
  }
  if(-not $held -or ($script:TxnForCommit|ConvertTo-Json -Compress) -cne $partialBefore -or
      $script:R131NativeApply -ne $nativeBefore){
    throw 'R131_PARTIAL_MIGRATION_LEDGER_MUST_BE_FROZEN'
  }
  Write-Host 'R131_PARTIAL_MIGRATION_LEDGER_AUTO_REPAIR_BLOCKED=PASS'
  # Accept the owner-reviewed baseline only when its original pending
  # journal and full external copies are separately certified. The owner
  # status must not claim a historical Spotify-app rollback.
  $script:Root=Join-Path $scratch 'R132Owner'
  $ownerId='20261113-190050-aabbccdd'
  $ownerDir=Join-Path $script:Root ('owner-recovery\R132-'+$ownerId)
  New-Item -ItemType Directory -Path $ownerDir -Force | Out-Null
  $manifest=Get-SpicetifyRootManifest -Path $cliRoot
  $orig=[pscustomobject]@{
    schema=3;root_transaction=$true;id=$ownerId;status='awaiting-guard'
    target_root=$cliRoot;before_tree_sha256=$manifest.TreeSha256
    before_sha256=(Get-ExactFileSha256 -Path $exe)
  }
  $oldFile=Join-Path $ownerDir 'original-ledger.json'
  [IO.File]::WriteAllText($oldFile,($orig|ConvertTo-Json -Depth 8),$utf8)
  Copy-Item -LiteralPath $spice -Destination (Join-Path $ownerDir 'spicetify-roaming') -Recurse -Force
  Copy-Item -LiteralPath $apps -Destination (Join-Path $ownerDir 'spotify-apps') -Recurse -Force
  $evidence=[pscustomobject]@{
    schema=1;transaction_id=$ownerId
    evidence_kind='CURRENT_PREIMAGE_ADOPTED_NOT_HISTORICAL_EXTERNAL_ROLLBACK'
    ledger_sha256=(Get-ExactFileSha256 -Path $oldFile)
    roaming_tree_sha256=(Get-SpicetifyRootManifest -Path $spice).TreeSha256
    apps_tree_sha256=(Get-SpicetifyRootManifest -Path $apps).TreeSha256
  }
  $evidencePath=Join-Path $ownerDir 'adoption-evidence.json'
  [IO.File]::WriteAllText($evidencePath,($evidence|ConvertTo-Json -Depth 8),$utf8)
  $adopted=$orig|ConvertTo-Json -Depth 8|ConvertFrom-Json
  $adopted.status='owner-reviewed-preimage'
  $adopted|Add-Member -NotePropertyName owner_reconciliation -NotePropertyValue (
    [pscustomobject]@{
      schema=1;kind='OWNER_APPROVED_CURRENT_PREIMAGE_NOT_EXTERNAL_ROLLBACK'
      snapshot_root=$ownerDir
      evidence_sha256=(Get-ExactFileSha256 -Path $evidencePath)
    })
  $script:TxnForCommit=$adopted
  if((Assert-SpicetifyOwnerPreimageAdoption $adopted) -cne $true){
    throw 'R132_OWNER_ADOPTION_NOT_ACCEPTED_BY_REAL_PRODUCT_HELPER'
  }
  $returned=Repair-PendingSpicetifyTransaction
  if([string]$returned.status -cne 'owner-reviewed-preimage' -or
     $script:R131NativeApply -ne $nativeBefore){
    throw 'R132_OWNER_ADOPTION_TRIGGERED_UNAPPROVED_ROLLBACK'
  }
  Write-Host 'R132_OWNER_RECONCILIATION_REAL_PRODUCT_ADMISSION=PASS'
  [IO.File]::WriteAllText($evidencePath,'TAMPERED_OWNER_EVIDENCE',$utf8)
  $blockedOwner=$false
  try{[void](Repair-PendingSpicetifyTransaction)}catch{
    $blockedOwner=$_.Exception.Message -match 'R132_ADOPTION_EVIDENCE_SHA_INVALID'
  }
  if(-not $blockedOwner -or $script:R131NativeApply -ne $nativeBefore){
    throw 'R132_TAMPERED_OWNER_ADOPTION_NOT_BLOCKED'
  }
  Write-Host 'R132_TAMPERED_ARCHIVE_BLOCKED_BEFORE_NEW_MUTATION=PASS'
  # New and old transaction remains protected if one external backup is tampered.
  [IO.File]::WriteAllText((Join-Path $pre.RoamingBackup 'Themes/theme.css'),'CORRUPTED_BACKUP',$utf8)
  $failed=$false
  try {[void](Restore-SpicetifyMigrationPreimage $tx)}catch {
    $failed=($_.Exception.Message -match 'R131_EXTERNAL_BACKUP_SHA_MISMATCH')
  }
  if(-not $failed){throw 'R131_CORRUPT_BACKUP_NOT_BLOCKED'}
  Write-Host 'R131_WINDOWS_TAMPERED_BACKUP_REJECTED=PASS'
  $startFns=@($ast.FindAll({param($x)
    $x -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $x.Name -cin @('Start-SpicetifyCliTransaction',
      'Invoke-SpicetifyTransactionalMaintenance','Rollback-SpicetifyCliTransaction',
      'Commit-SpicetifyCliTransaction')
  },$true))
  if($startFns.Count -ne 4){throw 'R131_PRODUCT_FLOW_FUNCTIONS_MISSING'}
  $combined=$startFns|ForEach-Object{$_.Extent.Text}
  $allFlow=$combined -join [Environment]::NewLine
  if(-not $allFlow.Contains("('restore','backup','apply','--no-restart')") -or
     -not $allFlow.Contains('Restore-SpicetifyMigrationPreimage') -or
     -not $allFlow.Contains('migration_snapshot_ready') -or
     -not $allFlow.Contains('Assert-SpicetifyOwnerPreimageAdoption')){
    throw 'R131_OFFICIAL_CLI_AND_ROLLBACK_NOT_WIRED'
  }
  Write-Host 'R131_PRODUCT_MIGRATION_AND_RECOVERY_SOURCE_WIRED=PASS'
  Write-Host 'R131_REAL_SPOTIFY_AND_OWNER_PC_FILES=UNTOUCHED'
}finally{
  $env:APPDATA=$previousAppdata
}
