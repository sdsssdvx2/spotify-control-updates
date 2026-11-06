"""Inject an actual missing-live-rename crash window into the already
qualified REAL signed third-HMAC permit ZIP + independent rollback E2E.
No mutation to the pinned parent fixture or to installed user applications.
"""
from __future__ import annotations
import hashlib,runpy,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PRIOR=ROOT/'validation/custom-app-journal-restart-locator/derive_signed_real_zip_locator_e2e.py'
PRIOR_BLOB='af4ddbe703c8c0408ea12f0fdd95aff5297d9a14'
PRIOR_OUTPUT=ROOT/'validation/custom-app-journal-restart-locator/ci_derived_signed_zip_bound_locator.ps1'
OUT=HERE/'ci_derived_real_zip_missing_live_recovery.ps1'
MODULE=ROOT/'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1'
MODULE_BLOB='5f25458ebf9c40206fde11918c2ce221966d6b2b'

def assert_once(s,old,new,label):
    n=s.count(old)
    if n!=1:raise RuntimeError(f'{label}: expected unique qualified anchor, got {n}')
    return s.replace(old,new,1)

def main():
    def hash_blob(path):
        return subprocess.check_output(['git','hash-object',str(path)],cwd=ROOT,text=True).strip()
    if hash_blob(PRIOR)!=PRIOR_BLOB or hash_blob(MODULE)!=MODULE_BLOB:
        raise RuntimeError('qualified original real signed ZIP E2E or missing-live source changed')
    if PRIOR_OUTPUT.exists() or OUT.exists():
        raise RuntimeError('refuse to overwrite generated signed real ZIP E2E')
    previous=runpy.run_path(str(PRIOR),run_name='isolated-pr227-derivation')
    previous['main']()
    s=PRIOR_OUTPUT.read_text('utf-8').replace('\r\n','\n')
    module=". (Join-Path $root 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')"
    s=assert_once(s,module,module+"\n. (Join-Path $root 'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1')",
                  'missing-live read-only module required in actual E2E')
    after="Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_JOURNALED_SWAP_PASS active_claim_persisted=true fresh_hmac_and_current_utc=true recovery_possible=true'"
    insert=r"""
# The actual signed THIRD-ID permit has now completed real staged ZIP atomic
# swap; simulate a second power cut after its live directory was renamed out
# but before independent journal recovery can inspect the interrupted tree.
$missingLivePaths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
$stateShaBefore=(Get-FileHash -LiteralPath $missingLivePaths.state -Algorithm SHA256).Hash
$aside=Join-Path $script:TJRRoot ('temporarily-displaced-live-'+[Guid]::NewGuid().ToString('N'))
Assert-TJR ([IO.Directory]::Exists([string]$script:TIDLive)) 'real signed ZIP swap did not leave a live directory to interrupt'
[IO.Directory]::Move([string]$script:TIDLive,[string]$aside)
try{
    Assert-TJR (-not[IO.Directory]::Exists([string]$script:TIDLive)) 'simulated crash did not remove live app directory'
    $oldOpenerDenied=$false
    try{
        $old=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
        $old.lock_handle.Dispose()
    }catch{$oldOpenerDenied=$true}
    Assert-TJR $oldOpenerDenied 'normal user transaction opener incorrectly accepted absent live folder'
    $opened=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
    try{
        Assert-TJR ([bool]$opened.ok -and [bool]$opened.live_missing -and [bool]$opened.recovery_only -and
            -not[bool]$opened.production_mutation_authorized -and -not[bool]$opened.restored_live_verified -and
            [string]$opened.locator.record.transaction_id -ceq [string]$script:USERExpectedTx -and
            [string]$opened.locator.record.store_directory -ceq [string]$script:TJRStore -and
            [string]$opened.locator.record.consumption_id -ceq [string]$p.consumption_id) 'missing-live transaction reopening was unqualified'
        $secondDenied=$false
        try{
            $parallel=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
            $parallel.session.lock_handle.Dispose()
        }catch{$secondDenied=$true}
        Assert-TJR $secondDenied 'two processes acquired same app missing-live recovery lock'
        Assert-TJR ((Get-FileHash -LiteralPath $missingLivePaths.state -Algorithm SHA256).Hash -ceq $stateShaBefore -and
            -not[IO.Directory]::Exists([string]$script:TIDLive)) 'missing-live inspection reconstructed app directory or altered active claim'
    }finally{$opened.session.lock_handle.Dispose()}
}finally{
    if([IO.Directory]::Exists($aside) -and -not[IO.Directory]::Exists([string]$script:TIDLive)){
        [IO.Directory]::Move([string]$aside,[string]$script:TIDLive)
    }
}
Assert-TJR ([IO.Directory]::Exists([string]$script:TIDLive)) 'test failed to return real swapped app to qualified independent rollback'
Assert-TJR ((Get-FileHash -LiteralPath $missingLivePaths.state -Algorithm SHA256).Hash -ceq $stateShaBefore) 'real signed ZIP missing-live recovery modified canonical DPAPI state'
Write-Host 'MISSING_LIVE_REAL_SIGNED_ZIP_ATOMIC_CRASH_WINDOW_RECOVERY_PASS real_zip_swapped=true immutable_locator_reopened=true old_opener_denied=true exclusive_lock=true no_auto_restore=true'
"""
    s=assert_once(s,after,after+"\n"+insert,'real ZIP post-swap crash window')
    summary="Write-Host 'USER_JOURNAL_SIGNED_ZIP_BOUND_RESTART_TERMINAL_PASS"
    if s.count(summary)!=1:raise RuntimeError('previous full independent rollback summary changed')
    if s.count("MISSING_LIVE_REAL_SIGNED_ZIP_ATOMIC_CRASH_WINDOW_RECOVERY_PASS")!=1:
        raise RuntimeError('missing-live independent proof marker not unique')
    OUT.write_text(s,'utf-8',newline='\n')
    print('MISSING_LIVE_ACTUAL_SIGNED_ZIP_INDEPENDENT_ROLLBACK_DERIVED_PASS',
          len(s),hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
