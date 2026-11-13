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
  if([string]$script:TxnForCommit.status -cne 'awaiting-guard'){
    throw 'R131_FAILED_COMMIT_MUTATED_TXN_STATE'
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
