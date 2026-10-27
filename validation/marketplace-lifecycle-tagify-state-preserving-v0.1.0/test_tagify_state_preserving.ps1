param([Parameter(Mandatory=$true)][string]$CandidatePath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$fixtureRoot=Join-Path $env:RUNNER_TEMP ('tagify-state-preserving-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA;$oldRoaming=$env:APPDATA
try {
  $env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData'
  $env:APPDATA=Join-Path $fixtureRoot 'Roaming'
  New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA,$env:APPDATA | Out-Null
  $raw=Get-Content -LiteralPath $CandidatePath -Raw
  $raw=$raw -replace "`r`n","`n"
  $marker='try {'+"`n"+'    Write-AddonLog "Addon Manager v$Version action=$Action force=$Force"'
  $idx=$raw.LastIndexOf($marker,[StringComparison]::Ordinal)
  if($idx -lt 0){throw 'Could not isolate Addon Manager function definitions.'}
  $defs=Join-Path $fixtureRoot 'definitions.ps1'
  [IO.File]::WriteAllText($defs,$raw.Substring(0,$idx),[Text.UTF8Encoding]::new($true))
  . $defs

  $r331=Get-TagifyReleaseInfo -Version '3.3.1'
  $r332=Get-TagifyReleaseInfo -Version '3.3.2'
  if($r331.digest -cne 'sha256:b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957'){throw 'Tagify 3.3.1 digest drift.'}
  if($r332.digest -cne 'sha256:5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b' -or [int64]$r332.size -ne 1554948){throw 'Tagify 3.3.2 release identity drift.'}
  $stage331=Download-TagifyReleaseStage -Remote $r331
  $stage332=Download-TagifyReleaseStage -Remote $r332
  $tree331=Get-TagifyTreeFingerprint -RootPath $stage331.Path
  $tree332=Get-TagifyTreeFingerprint -RootPath $stage332.Path
  if($tree331.TreeSha256 -cne '8f8abd6f80f88321d6517c1496c985da146e313a949e80f4e4b41c34ad27178a'){throw 'Tagify 3.3.1 authenticated tree drift.'}
  if($tree332.TreeSha256 -cne 'e751c2692d0edb5d63ac359df0b81c024ddca4f02e9de46cd5e4d8f3266bbf71'){throw 'Tagify 3.3.2 authenticated tree drift.'}

  $app=Join-Path $env:APPDATA 'spicetify\CustomApps\tagify'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $app) | Out-Null
  Copy-DirectoryContentsExact -Source $stage331.Path -Destination $app
  $before=Get-DirectoryGitSnapshot $app
  $baseline=Get-TagifyInstalledBaselineProof -Dir $app -Version '3.3.1'
  if($baseline.Fingerprint -cne $before.fingerprint){throw 'Tagify 3.3.1 baseline proof mismatch.'}

  $browserIdb=Join-Path $env:LOCALAPPDATA 'Spotify\Browser\IndexedDB'
  $browserLs=Join-Path $env:LOCALAPPDATA 'Spotify\Browser\Local Storage'
  $defaultIdb=Join-Path $env:LOCALAPPDATA 'Spotify\Default\IndexedDB'
  $defaultLs=Join-Path $env:LOCALAPPDATA 'Spotify\Default\Local Storage'
  New-Item -ItemType Directory -Force -Path $browserIdb,$browserLs,$defaultIdb,$defaultLs | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $browserIdb '000001.log'),[Text.Encoding]::UTF8.GetBytes('tagify-browser-idb'))
  [IO.File]::WriteAllBytes((Join-Path $browserLs '000002.ldb'),[Text.Encoding]::UTF8.GetBytes('tagify-browser-ls'))
  [IO.File]::WriteAllBytes((Join-Path $defaultIdb '000003.log'),[Text.Encoding]::UTF8.GetBytes('tagify-default-idb'))
  [IO.File]::WriteAllBytes((Join-Path $defaultLs '000004.ldb'),[Text.Encoding]::UTF8.GetBytes('tagify-default-ls'))
  $protectedBefore=Get-TagifyProtectedStateSnapshot

  $state=Load-AddonState;$appState=Ensure-AppState $state 'tagify';$appState.installed_revision='v3.3.1';$appState.installed_fingerprint=[string]$before.fingerprint;Save-AddonState $state
  $item=[pscustomobject]@{name='tagify';kind='custom-app';policy='auto';source='alexk218/tagify';installed=$true}
  $plan=Get-AddonSourceAdapterPlan -Item $item
  if(-not $plan.mutation_authorized -or $plan.mutation_handler -cne 'tagify' -or $plan.adapter.id -cne 'tagify-release-state-v1'){throw 'Tagify source-adapter plan is not state-preserving auto.'}
  $prov=New-AddonSourceAdapterTransactionProvenance -Plan $plan

  function New-TestTx([string]$Id,[string]$StagePath,[string]$AfterRevision,[string]$AfterFingerprint,[string]$ProtectedSha){
    $current=Get-DirectoryGitSnapshot $app
    $backup=New-PithayaTransactionBackup -TxId $Id -Name 'tagify' -Target $app -ExpectedFingerprint ([string]$current.fingerprint)
    $change=[pscustomobject]@{
      name='tagify';target=$app;backup=$backup;before_fingerprint=[string]$current.fingerprint;before_revision='v3.3.1'
      after_revision=$AfterRevision;after_fingerprint=$AfterFingerprint;remote_tree=('release-asset-'+$r332.digest.Substring(7));archive_sha256=$stage332.ArchiveSha256;swapped=$false
      registry_kind='custom-app';registry_handler='tagify';registry_source='alexk218/tagify';registry_policy='auto'
      source_adapter_id=$prov.source_adapter_id;source_adapter_strategy=$prov.source_adapter_strategy;source_adapter_source=$prov.source_adapter_source;source_adapter_rollback=$prov.source_adapter_rollback
      protected_state_kind='tagify-browser-storage-v1';protected_state_before_sha256=$ProtectedSha
    }
    $tx=[pscustomobject]@{schema=2;registry_schema=1;registry_sha256=(Get-AddonPolicyRegistryFingerprint);source_adapter_schema=1;source_adapter_sha256=(Get-AddonSourceAdapterFingerprint);id=$Id;created_at=(Get-Date).ToString('o');status='prepared';committed=$false;swapped_at=$null;rolled_back_at=$null;committed_at=$null;changes=@($change)}
    Write-TransactionLedger $tx
    Invoke-AtomicDirectorySwap -Name 'tagify' -Source $StagePath -Target $app -ExpectedFingerprint $AfterFingerprint
    $change.swapped=$true;$tx.status='awaiting-apply';Write-TransactionLedger $tx
  }

  $rollbackStage=Download-TagifyReleaseStage -Remote $r332
  New-TestTx -Id ('rollback-'+[guid]::NewGuid().ToString('N')) -StagePath $rollbackStage.Path -AfterRevision 'v3.3.2' -AfterFingerprint ([string]$rollbackStage.Validation.Fingerprint) -ProtectedSha ([string]$protectedBefore.Fingerprint)
  Rollback-LastTransaction
  $rolled=Get-DirectoryGitSnapshot $app
  if($rolled.fingerprint -cne $before.fingerprint){throw 'Tagify rollback did not restore exact 3.3.1 tree.'}
  if((Get-TagifyProtectedStateSnapshot).Fingerprint -cne $protectedBefore.Fingerprint){throw 'Tagify rollback changed protected Browser/Default storage.'}

  $commitStage=Download-TagifyReleaseStage -Remote $r332
  New-TestTx -Id ('commit-'+[guid]::NewGuid().ToString('N')) -StagePath $commitStage.Path -AfterRevision 'v3.3.2' -AfterFingerprint ([string]$commitStage.Validation.Fingerprint) -ProtectedSha ([string]$protectedBefore.Fingerprint)
  Commit-LastTransaction
  if(Test-Path -LiteralPath $TransactionPath){throw 'Successful Tagify CommitLast left an active transaction ledger.'}
  $committed=Get-DirectoryGitSnapshot $app
  if($committed.fingerprint -cne $commitStage.Validation.Fingerprint){throw 'Tagify commit tree mismatch.'}
  if((Get-TagifyProtectedStateSnapshot).Fingerprint -cne $protectedBefore.Fingerprint){throw 'Tagify commit changed protected Browser/Default storage.'}
  $savedState=Load-AddonState;$savedTag=Ensure-AppState $savedState 'tagify'
  if([string]$savedTag.installed_revision -cne 'v3.3.2' -or [string]$savedTag.installed_fingerprint -cne [string]$committed.fingerprint){throw 'Tagify committed state metadata mismatch.'}

  $resetStage=Download-TagifyReleaseStage -Remote $r331
  Invoke-AtomicDirectorySwap -Name 'tagify-reset' -Source $resetStage.Path -Target $app -ExpectedFingerprint ([string]$resetStage.Validation.Fingerprint)
  $before2=Get-DirectoryGitSnapshot $app;$protected2=Get-TagifyProtectedStateSnapshot
  $tamperStage=Download-TagifyReleaseStage -Remote $r332
  New-TestTx -Id ('tamper-'+[guid]::NewGuid().ToString('N')) -StagePath $tamperStage.Path -AfterRevision 'v3.3.2' -AfterFingerprint ([string]$tamperStage.Validation.Fingerprint) -ProtectedSha ([string]$protected2.Fingerprint)
  [IO.File]::AppendAllText((Join-Path $defaultLs '000004.ldb'),'tampered',[Text.UTF8Encoding]::new($false))
  $failed=$false;try{Commit-LastTransaction}catch{$failed=$true}
  if(-not $failed){throw 'Tagify protected-state drift was incorrectly committed.'}
  if(-not (Test-Path -LiteralPath $TransactionPath -PathType Leaf)){throw 'Tagify protected-state commit refusal did not retain the rollback ledger.'}
  Rollback-LastTransaction
  $rolled2=Get-DirectoryGitSnapshot $app
  if($rolled2.fingerprint -cne $before2.fingerprint){throw 'Tagify drift-refusal rollback did not restore exact code tree.'}

  [IO.File]::WriteAllText((Join-Path $app 'spotify-control-extra.txt'),'drift',[Text.UTF8Encoding]::new($false))
  $failed=$false;try{[void](Get-TagifyInstalledBaselineProof -Dir $app -Version '3.3.1')}catch{$failed=$true}
  if(-not $failed){throw 'Tagify modified local tree was incorrectly accepted as an official baseline.'}

  Write-Host 'TAGIFY_STATE_PRESERVING_TRANSACTION_ACCEPTANCE_PASS'
}
finally {
  $env:LOCALAPPDATA=$oldLocal;$env:APPDATA=$oldRoaming
  if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
