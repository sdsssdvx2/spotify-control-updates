from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / "validation/persistence-transaction-guard-v0.1.0/out/bin/addon-manager.ps1"
HARNESS = ROOT / "validation/persistence-transaction-guard-v0.1.0/out/persistence-commit-integration-e2e.ps1"

DISPATCH_ANCHOR = '\ntry {\n    Write-AddonLog "Addon Manager v$Version action=$Action force=$Force"'

HARNESS_BODY = r'''
$fixtureRoot=$null
$saved=[ordered]@{
    Root=$script:Root;LogDir=$script:LogDir;StatePath=$script:StatePath;TransactionPath=$script:TransactionPath
    ReportsRoot=$script:ReportsRoot;LatestReport=$script:LatestReport;PithayaTransactionReport=$script:PithayaTransactionReport
    LogPath=$script:LogPath;AddonTransactionBackupRoot=$AddonTransactionBackupRoot
}
try {
    $fixtureRoot=Join-Path $env:TEMP ('SpotifyControl-PersistenceCommitE2E-'+[guid]::NewGuid().ToString('N'))
    $script:Root=$fixtureRoot
    $script:LogDir=Join-Path $fixtureRoot 'logs'
    $script:StatePath=Join-Path $fixtureRoot 'addons-state.json'
    $script:TransactionPath=Join-Path $fixtureRoot 'addon-last-transaction.json'
    $script:ReportsRoot=Join-Path $fixtureRoot 'reports'
    $script:LatestReport=Join-Path $script:ReportsRoot 'addons-latest.json'
    $script:PithayaTransactionReport=Join-Path $script:ReportsRoot 'pithaya-transaction-latest.json'
    $script:LogPath=Join-Path $script:LogDir 'addons-e2e.log'
    $AddonTransactionBackupRoot=Join-Path $fixtureRoot 'backups\customapp-transactions'
    New-Item -ItemType Directory -Force -Path $script:Root,$script:LogDir,$script:ReportsRoot,$AddonTransactionBackupRoot|Out-Null

    $spotifyRoot=Join-Path $fixtureRoot 'Spotify'
    $prefs=Join-Path $spotifyRoot 'Browser\Preferences'
    $localStorage=Join-Path $spotifyRoot 'Browser\Local Storage'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $prefs),$localStorage|Out-Null
    [System.IO.File]::WriteAllText($prefs,'{"guard":"before"}',[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $localStorage 'state.bin'),'settings-before',[System.Text.UTF8Encoding]::new($false))

    # Failure path: app tree is in the post-swap state but guarded WebView persistence drifts before CommitLast.
    $txid='persistence-drift-fixture'
    $target=Join-Path $fixtureRoot 'target-drift'
    New-Item -ItemType Directory -Force -Path $target|Out-Null
    [System.IO.File]::WriteAllText((Join-Path $target 'manifest.json'),'{"name":"fixture"}',[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $target 'index.js'),'before',[System.Text.UTF8Encoding]::new($false))
    $before=Get-DirectoryGitSnapshot $target
    $appBackup=New-PithayaTransactionBackup -TxId $txid -Name 'fixture' -Target $target -ExpectedFingerprint ([string]$before.fingerprint)
    $guard=New-SpotifyPersistenceTransactionSnapshot -SnapshotId $txid -SpotifyRoot $spotifyRoot -BackupBaseRoot $AddonTransactionBackupRoot

    [System.IO.File]::WriteAllText((Join-Path $target 'index.js'),'after',[System.Text.UTF8Encoding]::new($false))
    $after=Get-DirectoryGitSnapshot $target
    $tx=[pscustomobject]@{
        schema=2;persistence_guard_schema=1;persistence_backup_path=[string]$guard.backup_path
        persistence_manifest_sha256=[string]$guard.manifest_sha256;persistence_before_fingerprint=[string]$guard.before_fingerprint
        id=$txid;created_at=(Get-Date).ToString('o');status='awaiting-apply';committed=$false
        swapped_at=(Get-Date).ToString('o');rolled_back_at=$null;committed_at=$null
        changes=@([pscustomobject]@{
            name='fixture';target=$target;backup=$appBackup
            before_fingerprint=[string]$before.fingerprint;before_revision='before-revision'
            after_revision='after-revision';after_fingerprint=[string]$after.fingerprint
            remote_tree='fixture-tree';archive_sha256=('a'*64);swapped=$true
        })
    }
    Write-TransactionLedger $tx
    [System.IO.File]::WriteAllText($prefs,'{"guard":"drifted"}',[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $localStorage 'new-after-swap.bin'),'unexpected',[System.Text.UTF8Encoding]::new($false))

    $commitFailed=$false
    $commitMessage=$null
    try { Commit-LastTransaction }
    catch { $commitFailed=$true;$commitMessage=$_.Exception.Message }
    if(-not $commitFailed){throw 'Persistence drift fixture was incorrectly committed.'}
    if([string]$commitMessage -notmatch 'Persistence drift detected during addon update/apply'){throw "Persistence drift fixture failed for the wrong reason: $commitMessage"}
    if(Test-PathSafe $script:TransactionPath 'Leaf'){throw 'Persistence drift rollback left an active transaction ledger.'}
    $restoredTree=Get-DirectoryGitSnapshot $target
    if([string]$restoredTree.fingerprint -cne [string]$before.fingerprint){throw 'Persistence drift rollback did not restore the exact pre-update app tree.'}
    if([System.IO.File]::ReadAllText($prefs) -cne '{"guard":"before"}'){throw 'Persistence drift rollback did not restore exact Preferences bytes.'}
    if(Test-PathSafe (Join-Path $localStorage 'new-after-swap.bin') 'Any'){throw 'Persistence drift rollback did not remove a path absent from the pre-update snapshot.'}
    $guardCheck=Test-SpotifyPersistenceTransactionSnapshot -BackupPath ([string]$guard.backup_path) -ManifestSha256 ([string]$guard.manifest_sha256)
    if(-not [bool]$guardCheck.Valid){throw 'Persistence drift rollback did not restore the exact guarded persistence fingerprint.'}
    $rollbackArchives=@(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'transactions') -Filter '*-rolled-back-persistence-drift-fixture.json' -File -ErrorAction SilentlyContinue)
    if($rollbackArchives.Count -ne 1){throw 'Persistence drift fixture did not archive exactly one rolled-back transaction.'}
    $rollbackReport=Get-Content -LiteralPath $script:PithayaTransactionReport -Raw|ConvertFrom-Json
    if([string]$rollbackReport.status -cne 'rolled-back'){throw 'Persistence drift fixture transaction report is not rolled-back.'}

    # Success path: the same guarded transaction commits normally when persistence remains byte-exact.
    $txid2='persistence-clean-fixture'
    $target2=Join-Path $fixtureRoot 'target-clean'
    New-Item -ItemType Directory -Force -Path $target2|Out-Null
    [System.IO.File]::WriteAllText((Join-Path $target2 'manifest.json'),'{"name":"fixture-clean"}',[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $target2 'index.js'),'before-clean',[System.Text.UTF8Encoding]::new($false))
    $before2=Get-DirectoryGitSnapshot $target2
    $appBackup2=New-PithayaTransactionBackup -TxId $txid2 -Name 'fixture-clean' -Target $target2 -ExpectedFingerprint ([string]$before2.fingerprint)
    $guard2=New-SpotifyPersistenceTransactionSnapshot -SnapshotId $txid2 -SpotifyRoot $spotifyRoot -BackupBaseRoot $AddonTransactionBackupRoot
    [System.IO.File]::WriteAllText((Join-Path $target2 'index.js'),'after-clean',[System.Text.UTF8Encoding]::new($false))
    $after2=Get-DirectoryGitSnapshot $target2
    $tx2=[pscustomobject]@{
        schema=2;persistence_guard_schema=1;persistence_backup_path=[string]$guard2.backup_path
        persistence_manifest_sha256=[string]$guard2.manifest_sha256;persistence_before_fingerprint=[string]$guard2.before_fingerprint
        id=$txid2;created_at=(Get-Date).ToString('o');status='awaiting-apply';committed=$false
        swapped_at=(Get-Date).ToString('o');rolled_back_at=$null;committed_at=$null
        changes=@([pscustomobject]@{
            name='fixture-clean';target=$target2;backup=$appBackup2
            before_fingerprint=[string]$before2.fingerprint;before_revision='before-clean-revision'
            after_revision='after-clean-revision';after_fingerprint=[string]$after2.fingerprint
            remote_tree='fixture-clean-tree';archive_sha256=('b'*64);swapped=$true
        })
    }
    Write-TransactionLedger $tx2
    Commit-LastTransaction
    if(Test-PathSafe $script:TransactionPath 'Leaf'){throw 'Clean persistence fixture left an active transaction ledger.'}
    $cleanTree=Get-DirectoryGitSnapshot $target2
    if([string]$cleanTree.fingerprint -cne [string]$after2.fingerprint){throw 'Clean persistence fixture did not retain the committed app tree.'}
    $guardCheck2=Test-SpotifyPersistenceTransactionSnapshot -BackupPath ([string]$guard2.backup_path) -ManifestSha256 ([string]$guard2.manifest_sha256)
    if(-not [bool]$guardCheck2.Valid){throw 'Clean persistence fixture unexpectedly changed guarded persistence.'}
    $committedState=Load-AddonState
    $committedApp=Ensure-AppState $committedState 'fixture-clean'
    if([string]$committedApp.installed_revision -cne 'after-clean-revision'){throw 'Clean persistence fixture did not persist the committed addon revision.'}
    $commitArchives=@(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'transactions') -Filter '*-committed-persistence-clean-fixture.json' -File -ErrorAction SilentlyContinue)
    if($commitArchives.Count -ne 1){throw 'Clean persistence fixture did not archive exactly one committed transaction.'}

    Write-Host 'PERSISTENCE_COMMIT_INTEGRATION_E2E_PASS drift-rollback=exact clean-commit=exact'
}
finally {
    $script:Root=$saved.Root;$script:LogDir=$saved.LogDir;$script:StatePath=$saved.StatePath;$script:TransactionPath=$saved.TransactionPath
    $script:ReportsRoot=$saved.ReportsRoot;$script:LatestReport=$saved.LatestReport;$script:PithayaTransactionReport=$saved.PithayaTransactionReport
    $script:LogPath=$saved.LogPath;$AddonTransactionBackupRoot=$saved.AddonTransactionBackupRoot
    if($fixtureRoot -and(Test-Path -LiteralPath $fixtureRoot -ErrorAction SilentlyContinue)){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
'''


def main() -> None:
    subprocess.check_call([sys.executable, str(ROOT / "validation/persistence-transaction-guard-v0.1.0/build_candidate.py"), "--build"], cwd=ROOT)
    text = CANDIDATE.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    idx = text.find(DISPATCH_ANCHOR)
    if idx < 0:
        raise RuntimeError("candidate main dispatch anchor missing")
    prefix = text[:idx]
    for required in (
        "function Commit-LastTransaction {",
        "function Rollback-LastTransaction {",
        "function New-SpotifyPersistenceTransactionSnapshot {",
        "function Restore-SpotifyPersistenceTransactionSnapshot {",
    ):
        if required not in prefix:
            raise RuntimeError(f"required exact candidate function missing before harness: {required}")
    HARNESS.parent.mkdir(parents=True, exist_ok=True)
    HARNESS.write_text(prefix + "\n" + HARNESS_BODY + "\n", encoding="utf-8", newline="\n")
    print("PERSISTENCE_COMMIT_INTEGRATION_HARNESS_BUILD_PASS", HARNESS)


if __name__ == "__main__":
    main()
