"""Extend the SHA-pinned REAL ZIP + fresh signed THIRD permit + independent
rollback Windows E2E with the per-user immutable DPAPI journal locator.

Original validated fixture is generated untouched. This post-processing is
idempotence-checked with unique text anchors and never runs on installed apps.
"""
from __future__ import annotations
import hashlib,runpy,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PRIOR=ROOT/'validation/custom-app-user-transaction-terminal-journal/derive_real_zip_terminal_e2e.py'
PRIOR_BLOB='dccf4d656d74cb97ba6eb188ba06fc77057ef209'
ORIGINAL=ROOT/'validation/custom-app-user-transaction-terminal-journal/ci_derived_user_verified_terminal.ps1'
OUT=HERE/'ci_derived_signed_zip_bound_locator.ps1'
MODULE='validation/custom-app-journal-restart-locator/user-journal-locator.ps1'
MODULE_BLOB='bb29fe26a3d58f63eb70188bd24ad0782db07efc'

def once(s,old,new,label):
    count=s.count(old)
    if count!=1:raise RuntimeError(f'{label}: {count} unexpected qualified anchors')
    return s.replace(old,new,1)

def main():
    def blob(path):
        return subprocess.check_output(['git','hash-object',str(path)],cwd=ROOT,text=True).strip()
    if blob(PRIOR)!=PRIOR_BLOB or blob(ROOT/MODULE)!=MODULE_BLOB:
        raise RuntimeError('original full-chain E2E or new locator SHA drift')
    if ORIGINAL.exists() or OUT.exists():raise RuntimeError('refusing to clobber earlier derived real ZIP source')
    ns=runpy.run_path(str(PRIOR),run_name='immutable-parent-derivation')
    ns['derive']()
    s=ORIGINAL.read_text('utf-8').replace('\r\n','\n')
    original=s
    old=". (Join-Path $root 'validation/custom-app-user-transaction-terminal-journal/verified-terminal-adapter.ps1')"
    s=once(s,old,old+"\n. (Join-Path $root 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')",'new module load')
    reserve="Assert-TJR ([bool]$reserved.ok -and [long]$reserved.revision -eq 1 -and [bool]$reserved.active) 'user transaction not reserved before atomic swap'"
    b=r"""
    $bound=Bind-CustomAppUserTxnJournalLocatorV010 -Session $preSession -AllowedRoot $script:TJRRoot -JournalStoreDirectory $script:TJRStore
    Assert-TJR ([bool]$bound.ok -and [bool]$bound.first_binding) 'pre-swap immutable locator binding failed'
    $rebound=Bind-CustomAppUserTxnJournalLocatorV010 -Session $preSession -AllowedRoot $script:TJRRoot -JournalStoreDirectory $script:TJRStore
    Assert-TJR ([bool]$rebound.already_bound -and -not[bool]$rebound.first_binding) 'same binding not idempotent'
    Write-Host 'USER_JOURNAL_REAL_SIGNED_THIRD_ID_PRE_SWAP_LOCATOR_BOUND_PASS'
"""
    s=once(s,reserve,reserve+b,'bind immutable journal before real ZIP swap')
    early="$early=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot"
    e=r"""
$earlyLocation=Read-CustomAppUserTxnJournalLocatorV010 -Session $early
Assert-TJR ([bool]$earlyLocation.ok -and [string]$earlyLocation.record.store_directory -ceq [string]$script:TJRStore -and
    [string]$earlyLocation.record.transaction_id -ceq [string]$script:USERExpectedTx) 'fresh process cannot find real signed journal location'
"""
    # read INSIDE the existing try/finally for $early's exclusive lock.
    openTry="try{\n    $earlyDenied=$false"
    s=once(s,openTry,"try{\n"+e+"    $earlyDenied=$false",'early journal locator recovery')
    oldAfter="Write-Host 'USER_TERMINAL_UNFINISHED_REAL_JOURNAL_DENIED_PASS'"
    newAfter=r"""Write-Host 'USER_TERMINAL_UNFINISHED_REAL_JOURNAL_DENIED_PASS'
$earlyBound=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
try{
    $blocked=$false
    try{
        [void](Commit-CustomAppUserTxnBoundJournalTerminalV010 -Session $earlyBound -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming)
    }catch{$blocked=$true}
    Assert-TJR $blocked 'pre-terminal bound journal falsely cleared active reservation'
    Assert-TJR ($null-ne$earlyBound.state.active -and [long]$earlyBound.state.revision -eq 1) 'pre-terminal bound verify mutated state'
}finally{$earlyBound.lock_handle.Dispose()}
Write-Host 'USER_JOURNAL_EARLY_BOUND_COMMIT_DENIED_PASS'
"""
    s=once(s,oldAfter,newAfter,'bound preterminal refusal')
    begin="$USERStoreReopened=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot"
    # Two independently reopened handles (before fault and after); both re-read
    # saved DPAPI receipt rather than consuming caller-supplied path arguments.
    read=r"""
$restoredLocator=Read-CustomAppUserTxnJournalLocatorV010 -Session $USERStoreReopened
Assert-TJR ([bool]$restoredLocator.ok -and -not[bool]$restoredLocator.journal_evidence_verified -and
    [string]$restoredLocator.record.allowed_root -ceq [string]$script:TJRRoot -and
    [string]$restoredLocator.record.store_directory -ceq [string]$script:TJRStore -and
    [string]$restoredLocator.record.transaction_id -ceq [string]$script:USERExpectedTx) 'durable journal lookup after independent rollback was not exact'
"""
    # Insert inside try for the first reopened handle; prevents leaking the lock
    s=once(s,"try{\n    $wrongId=@{}","try{\n"+read+"    $wrongId=@{}",'post-rollback receipt readback')
    originalInterrupt="Commit-CustomAppUserTxnVerifiedTerminalV011 @USERArgs -HostedCiInterruptBeforeReplace"
    replacementInterrupt="Commit-CustomAppUserTxnBoundJournalTerminalV010 -Session $USERStoreReopened -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming -HostedCiInterruptBeforeReplace"
    s=once(s,originalInterrupt,replacementInterrupt,'bounded pre-replace crash')
    originalCommit="$done=Commit-CustomAppUserTxnVerifiedTerminalV011 @USERArgs"
    newCommit="$done=Commit-CustomAppUserTxnBoundJournalTerminalV010 -Session $USERStoreReopened -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming"
    s=once(s,originalCommit,newCommit,'bound journal evidence terminal commit')
    s=once(s,"Write-Host 'USER_TERMINAL_REAL_ZIP_SIGNED_JOURNAL_ROLLBACK_RETIREMENT_PASS",
      "Write-Host 'USER_JOURNAL_SIGNED_ZIP_BOUND_RESTART_TERMINAL_PASS locator_encrypted=true locator_immutable=true only_verified_rollback_retires=true fresh_process_replay_denied=true'\nWrite-Host 'USER_TERMINAL_REAL_ZIP_SIGNED_JOURNAL_ROLLBACK_RETIREMENT_PASS",
      'new positive locator E2E marker')
    if s.count('Commit-CustomAppUserTxnBoundJournalTerminalV010')!=3:
        raise RuntimeError('bound coordinator calls not exactly 3')
    if s==original or 'Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010' not in s:
        raise RuntimeError('real signed third permit and ZIP orchestration not preserved')
    OUT.write_text(s,'utf-8',newline='\n')
    print('SIGNED_REAL_ZIP_DPAPI_JOURNAL_LOCATOR_E2E_DERIVED_PASS',
      len(s),hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
