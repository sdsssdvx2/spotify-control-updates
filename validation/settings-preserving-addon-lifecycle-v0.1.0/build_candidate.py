from __future__ import annotations
from pathlib import Path
import hashlib, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]
AREA=ROOT/'validation/settings-preserving-addon-lifecycle-v0.1.0'
BASE=ROOT/'validation/v0.6.28/out/bin/addon-manager.ps1'
GUARD=AREA/'user_state_guard.ps1'
OUT=AREA/'out-candidate/addon-manager-state-guard-candidate.ps1'
EXPECTED=(323385,'5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285')

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def once(s:str,a:str,b:str,label:str)->str:
    n=s.count(a)
    if n!=1:raise SystemExit(f'{label}: expected one anchor, got {n}')
    return s.replace(a,b,1)

subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.28/build_v0628.py'),'--build'],cwd=ROOT)
b=BASE.read_bytes()
if (len(b),sha(b))!=EXPECTED:raise SystemExit(f'exact r17 identity drift {(len(b),sha(b))}')
t=b.decode('utf-8-sig')
guard=GUARD.read_text(encoding='utf-8').rstrip()+"\n\n"

t=once(t,'$Version = "0.6.5-r17"','$Version = "0.6.5-r18-state-guard-candidate-v1"','version')
t=once(t,'[ValidateSet("Check","Update","Backup","RollbackLast","CommitLast","Status","AssetStatus","SelfTest","IvLyricsTagProofSelfTest","FinalizeRecovery","PithayaPreflight","TransactionSelfTest","DirectExtensionPreflight")]',
       '[ValidateSet("Check","Update","Backup","RollbackLast","CommitLast","Status","AssetStatus","SelfTest","IvLyricsTagProofSelfTest","FinalizeRecovery","PithayaPreflight","TransactionSelfTest","DirectExtensionPreflight","UserStateGuardSelfTest")]', 'actions')
t=once(t,'$AddonTransactionBackupRoot = Join-Path $BackupRoot "customapp-transactions"\nNew-Item -ItemType Directory -Force -Path $AddonTransactionBackupRoot | Out-Null',
       '$AddonTransactionBackupRoot = Join-Path $BackupRoot "customapp-transactions"\n$AddonUserStateBackupRoot = Join-Path $BackupRoot "addon-user-state-transactions"\nNew-Item -ItemType Directory -Force -Path $AddonTransactionBackupRoot,$AddonUserStateBackupRoot | Out-Null','roots')
t=once(t,'function Backup-SpotifyWebData {',guard+'function Backup-SpotifyWebData {','guard-functions')
t=once(t,'foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256")) {',
       'foreach ($optional in @("swapped_at","rolled_back_at","committed_at","registry_schema","registry_sha256","source_adapter_schema","source_adapter_sha256","user_state_guard_schema","user_state_guard")) {','normalize')
t=once(t,'    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }\n    foreach ($change in @($tx.changes)) {',
'''    if ([string]$tx.status -ne "awaiting-apply") { throw "Addon transaction is not in a committable awaiting-apply state." }
    if ($tx.user_state_guard) {
        if ([int]$tx.user_state_guard_schema -ne 1) { throw "Unsupported user-state guard schema in addon transaction." }
        $userStateCheck=Test-AddonUserStateSnapshotUnchanged -Guard $tx.user_state_guard
        if (-not [bool]$userStateCheck.unchanged) { throw ("Protected Spotify/Marketplace/addon user state changed during the managed update window; refusing commit and retaining transaction backup. before={0} current={1} backup={2}" -f [string]$userStateCheck.before_fingerprint,[string]$userStateCheck.current_fingerprint,[string]$tx.user_state_guard.backup_root) }
    } else { Write-AddonLog "Committing legacy addon transaction without transaction-coupled user-state guard; exact app-tree verification remains required." "WARN" }
    foreach ($change in @($tx.changes)) {''','commit')
t=once(t,'    $tx=Get-Content -LiteralPath $TransactionPath -Raw | ConvertFrom-Json\n    $tx = Normalize-PithayaTransaction $tx\n\n    # Reconcile ledger flags',
'''    $tx=Get-Content -LiteralPath $TransactionPath -Raw | ConvertFrom-Json
    $tx = Normalize-PithayaTransaction $tx
    if ($tx.user_state_guard) {
        $userStateCheck=Test-AddonUserStateSnapshotUnchanged -Guard $tx.user_state_guard
        if (-not [bool]$userStateCheck.unchanged) { Write-AddonLog ("Protected user state differs from the pre-update snapshot; app rollback will not overwrite possibly newer user data. Recovery backup retained at {0}." -f [string]$tx.user_state_guard.backup_root) "WARN" }
    }

    # Reconcile ledger flags''','rollback')
t=once(t,'        $txid=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)\n        $changes=New-Object System.Collections.Generic.List[object]\n        $baselineState=Load-AddonState\n        # Phase 2: make and verify every backup before first live swap.',
'''        $txid=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)
        $userStateGuard=New-AddonUserStateTransactionBackup -TxId $txid
        $changes=New-Object System.Collections.Generic.List[object]
        $baselineState=Load-AddonState
        # Phase 2: make and verify every app backup before first live swap. User state was backed up unconditionally above.''','update-guard')
t=once(t,'        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }',
       '        $tx=[pscustomobject]@{ schema=2; registry_schema=1; registry_sha256=$registrySha; source_adapter_schema=1; source_adapter_sha256=$sourceAdapterSha; user_state_guard_schema=1; user_state_guard=$userStateGuard; id=$txid; created_at=(Get-Date).ToString("o"); status="prepared"; committed=$false; swapped_at=$null; rolled_back_at=$null; committed_at=$null; changes=$changes.ToArray() }','ledger')
t=once(t,'        "DirectExtensionPreflight" {\n            Invoke-DirectExtensionPreflight | Out-Null\n        }\n        "Backup" {',
'''        "DirectExtensionPreflight" {
            Invoke-DirectExtensionPreflight | Out-Null
        }
        "UserStateGuardSelfTest" {
            Invoke-AddonUserStateGuardSelfTest
        }
        "Backup" {''','switch')

OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_bytes(b'\xef\xbb\xbf'+t.encode('utf-8'))
cb=OUT.read_bytes()
print('SETTINGS_PRESERVING_STATE_GUARD_CANDIDATE_PASS',len(cb),sha(cb))
for needle in ('New-AddonUserStateTransactionBackup -TxId $txid','user_state_guard_schema=1','Test-AddonUserStateSnapshotUnchanged -Guard $tx.user_state_guard','local-users','roaming-users','UserStateGuardSelfTest'):
    if needle not in t:raise SystemExit('candidate missing '+needle)
