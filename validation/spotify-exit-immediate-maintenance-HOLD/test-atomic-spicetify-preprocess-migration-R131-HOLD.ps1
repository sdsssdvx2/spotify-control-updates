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
  'Commit-SpicetifyCliTransaction')
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
     -not $allFlow.Contains('migration_snapshot_ready')){
    throw 'R131_OFFICIAL_CLI_AND_ROLLBACK_NOT_WIRED'
  }
  Write-Host 'R131_PRODUCT_MIGRATION_AND_RECOVERY_SOURCE_WIRED=PASS'
  Write-Host 'R131_REAL_SPOTIFY_AND_OWNER_PC_FILES=UNTOUCHED'
}finally{
  $env:APPDATA=$previousAppdata
}
