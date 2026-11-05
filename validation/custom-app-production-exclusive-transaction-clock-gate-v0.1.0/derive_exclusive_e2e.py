"""Validation-only derivation of the signed real-ZIP third Triple-ID restart test.
First invoke the EXACT SHA-pinned, qualified PR220 generator, then replace
only its bridge call with an exclusive per-app transaction claim and real UTC
validation. All generated files remain inside the disposable Windows checkout.
"""
from __future__ import annotations
import hashlib
import runpy
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASEGEN=ROOT / "validation/custom-app-production-triple-id-authorized-journal-bridge-v0.1.0/derive_bridge_e2e.py"
HERE=Path(__file__).resolve().parent
DERIVED=ROOT / "validation/custom-app-production-triple-id-journaled-restart-e2e-v0.1.0/ci_derived_authorized_bridge_restart.ps1"
OUTPUT=DERIVED.with_name("ci_derived_exclusive_gate_restart.ps1")
EXPECTED_BASEGEN_GIT_BLOB="68a499af508b1b24d30854c628c1a3f9783c6d9a"
PREPERMIT = ROOT / "validation/custom-app-production-pre-permit-backups-bridge-v0.1.0/test_custom_app_production_pre_permit_backups_bridge.ps1"
EXPECTED_PREPERMIT_GIT_BLOB = "ec684a4dd0aea70db85e0eadfdc2c4feec0b07ac"

def start_new_third_permit_at_real_utc():
    # Patch only the disposable GitHub Actions checkout, never committed
    # historical fixture bytes or any previously signed approval/receipt.
    blob=subprocess.check_output(["git","hash-object",str(PREPERMIT)],cwd=ROOT,text=True).strip()
    if blob!=EXPECTED_PREPERMIT_GIT_BLOB:
        raise RuntimeError(f"qualified pre-permit fixture drift {blob}")
    fixture=PREPERMIT.read_text(encoding="utf-8-sig").replace("\r\n","\n")
    anchor="# Fresh third new-cycle permit is issued only AFTER actual backup creation.\n$prior3=Invoke-DINPV010 $q"
    fresh=r"""# CI-only: historical matrices completed minutes ago. Do not rewrite an
# issued HMAC, a consumed ID, a journal or backup timestamp. Begin a NEW
# third-permit issuance at the actual current UTC immediately before readiness,
# reservation, signing and consumption. Earlier receipts remain untouched.
$thirdPermitHostUtc=[DateTimeOffset]::UtcNow
if(([DateTimeOffset]$q.at)-gt$thirdPermitHostUtc.AddSeconds(5)){throw 'exclusive-third-permit-history-clock-in-future'}
$q.at=$thirdPermitHostUtc
Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_THIRD_PERMIT_ISSUED_AT_HOST_UTC previous_signed_history_untouched=true new_third_permit=true'
"""
    fixture=once(fixture,anchor,fresh+anchor,"fresh third permit at real UTC")
    PREPERMIT.write_text(fixture,encoding="utf-8",newline="\n")



def once(s,old,new,label):
    n=s.count(old)
    if n!=1: raise RuntimeError(f"{label}: expected exactly one occurrence but got {n}")
    return s.replace(old,new,1)

def main():
    data=BASEGEN.read_bytes()
    hash256=hashlib.sha256(data).hexdigest()
    blob=subprocess.check_output(["git","hash-object",str(BASEGEN)],cwd=ROOT,text=True).strip()
    if blob!=EXPECTED_BASEGEN_GIT_BLOB:
        raise RuntimeError(f"qualified PR220 generator git blob drift {blob}")
    if DERIVED.exists() or OUTPUT.exists():
        raise RuntimeError("refusing to overwrite prior derived test")
    source=runpy.run_path(str(BASEGEN),run_name="validation-import")
    source["derive"]()
    start_new_third_permit_at_real_utc()
    s=DERIVED.read_text(encoding="utf-8").replace("\r\n","\n")
    oldimport=". (Join-Path $root 'validation/custom-app-production-triple-id-authorized-journal-bridge-v0.1.0/custom-app-production-triple-id-authorized-journal-bridge.ps1')"
    s=once(s,oldimport,oldimport+"\n. (Join-Path $root 'validation/custom-app-production-exclusive-transaction-clock-gate-v0.1.0/custom-app-production-exclusive-transaction-clock-gate.ps1')","gate module load")
    old="$mutation=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce"
    prefix=r"""# Negative attempts to inject a stale/future timestamp must not create an
# exclusive claim or journal. Never conceal fixture time skew by changing Now.
$fakeClock=@{};foreach($key in $TIDArgs.Keys){$fakeClock[$key]=$TIDArgs[$key]}
$fakeClock.Now=[DateTimeOffset]::UtcNow.AddMinutes(-8)
$clockDenied=Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010 -AtomicPreconditionArgs $fakeClock -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce
Assert-TJR (-not[bool]$clockDenied.ok -and [string]$clockDenied.reason -match 'wall-clock-denied' -and -not[bool]$clockDenied.mutation_attempted) 'stale timestamp bypassed new transaction gate'
Assert-TJR (-not(Test-Path -LiteralPath $script:TJRStore)) 'invalid clock created recovery journal'
$paths=Get-CustomAppProductionExclusiveGatePathsV010 -Name 'tagify' -LivePath $script:TIDLive
Assert-TJR (-not(Test-Path -LiteralPath $paths.record)) 'invalid clock created durable active claim'
$clockNow=Test-CustomAppProductionWallClockAdmissionV010 -SuppliedNow ([DateTimeOffset]$TIDArgs.Now)
Assert-TJR ([bool]$clockNow.ok) ('qualified fixture does not have a fresh UTC signing timestamp; do not silently rewrite history: '+[string]$clockNow.reason+' skew='+[string]$clockNow.skew_seconds)
Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_WALLCLOCK_VERIFIED_PASS synthetic_old_now_denied=true fixture_now_current=true'
"""
    new=prefix+"""
$mutation=Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce
Assert-TJR ([bool]$mutation.exclusive_claim_persisted -and [bool]$mutation.requires_recovery) 'successful swap did not leave durable active claim'
Assert-TJR (Test-Path -LiteralPath $paths.record -PathType Leaf) 'successful swap has no active claim'
$exclusiveRead=Read-CustomAppProductionExclusiveGateRecordV010 -Paths $paths
Assert-TJR ([bool]$exclusiveRead.ok -and [string]$exclusiveRead.record.consumption_id -ceq [string]$p.consumption_id) 'persisted cross-process claim not bound to original third consumption'
Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_JOURNALED_SWAP_PASS active_claim_persisted=true fresh_hmac_and_current_utc=true recovery_possible=true'
"""
    s=once(s,old,new.rstrip(),"guarded signed call")
    needle="Assert-TJR ($script:TJRCases -eq 7) ('case count mismatch '+$script:TJRCases)"
    terminal=r"""# Verified recovery is terminal; a wrong identity still must NOT retire
# the per-app active marker. This is the only safe retirement boundary.
$wrongTerminal=Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 -Name 'tagify' -LivePath $script:TIDLive -ExpectedConsumptionId ('0'*64) -ExpectedTransactionId ([string]$mutation.result.transaction_id)
Assert-TJR (-not[bool]$wrongTerminal.ok -and (Test-Path -LiteralPath $paths.record -PathType Leaf)) 'incorrect consumption ID retired active cross-process gate'
$wrongTerminal=Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 -Name 'tagify' -LivePath $script:TIDLive -ExpectedConsumptionId ([string]$p.consumption_id) -ExpectedTransactionId ('0'*64)
Assert-TJR (-not[bool]$wrongTerminal.ok -and (Test-Path -LiteralPath $paths.record -PathType Leaf)) 'incorrect journal transaction ID retired active cross-process gate'
$interrupted=Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 -Name 'tagify' -LivePath $script:TIDLive -ExpectedConsumptionId ([string]$p.consumption_id) -ExpectedTransactionId ([string]$mutation.result.transaction_id) -ValidationInterruptAfterArchive
Assert-TJR (-not[bool]$interrupted.ok -and [string]$interrupted.reason -ceq 'exclusive-app-ci-interrupted-after-retirement-archive') 'retirement crash hook unexpectedly completed'
Assert-TJR (Test-Path -LiteralPath $paths.record -PathType Leaf) 'retirement interruption lost active marker'
$midArchive=Get-CustomAppProductionExclusiveGateRetiredPathV010 -Paths $paths -ConsumptionId ([string]$p.consumption_id)
Assert-TJR (Test-Path -LiteralPath $midArchive -PathType Leaf) 'retirement interruption did not persist durable consumed-ID archive'
$complete=Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010 -Name 'tagify' -LivePath $script:TIDLive -ExpectedConsumptionId ([string]$p.consumption_id) -ExpectedTransactionId ([string]$mutation.result.transaction_id)
Assert-TJR ([bool]$complete.reconciled_interrupted_retirement) 'interrupted durable retirement was not reconciled idempotently'
Assert-TJR ([bool]$complete.ok -and [string]$complete.phase -ceq 'rollback-complete') ('correct terminal rollback was not safely retired '+[string]$complete.reason)
Assert-TJR (-not(Test-Path -LiteralPath $paths.record)) 'retired active transaction record still exists'
$archive=Test-CustomAppProductionExclusiveGateRetiredReceiptV010 -Path ([string]$complete.retired_record_path) -Paths $paths -ConsumptionId ([string]$p.consumption_id)
Assert-TJR ([bool]$archive.ok -and [string]$archive.receipt.transaction_id -ceq [string]$mutation.result.transaction_id -and [string]$archive.receipt.terminal_phase -ceq 'rollback-complete') 'terminal retirement record not bound to original signed transaction'
$replayGate=Open-CustomAppProductionExclusiveGateLockV010 -Name 'tagify' -LivePath $script:TIDLive
Assert-TJR ([bool]$replayGate.ok) 'completed OS lock was not released'
try{
    $repeat=Write-CustomAppProductionExclusiveGateActiveRecordV010 -Lock $replayGate -ConsumptionId ([string]$p.consumption_id) -JournalStoreDirectory (Join-Path $script:TJRRoot ('new-journal-'+[Guid]::NewGuid().ToString('N'))) -TransactionNonce ([Guid]::NewGuid().ToString('N'))
    Assert-TJR (-not[bool]$repeat.ok -and [string]$repeat.reason -match 'consumption-already-retired') 'same consumed third-ID was reauthorized after archived terminal rollback'
    Assert-TJR (-not(Test-Path -LiteralPath $paths.record)) 'retired-ID replay created a new active claim'
}finally{$replayGate.lock_handle.Dispose()}
Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_TERMINAL_RETIREMENT_PASS wrong_consumption_denied=true wrong_transaction_denied=true durable_rollback_complete_required=true active_claim_retired=true archived_consumption_replay_denied=true interrupted_archive_crash_reconciled=true'
"""
    s=once(s,needle,terminal+needle,"terminal after independent rollback")
    s+="\nWrite-Host 'TRIPLE_ID_EXCLUSIVE_REAL_ZIP_END_TO_END_PASS third_hmac_real_zip=true current_utc=true active_claim_before_swap=true independent_process_old_code_restore=true terminal_lock_retirement=true replay_denied=true production_disabled=true'\n"
    OUTPUT.write_text(s,encoding="utf-8",newline="\n")
    print(f"TRIPLE_ID_EXCLUSIVE_REAL_ZIP_DERIVATION_OK bytes={len(s)} sha256={hashlib.sha256(s.encode()).hexdigest()} original_bridge_source_sha256={hash256}")
if __name__=="__main__":main()
