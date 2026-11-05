"""CI ONLY: derive one replacement integration script from an exact, already
qualified real-ZIP/third-HMAC/fresh-process-recovery parent test. No rewriting
of operating software; output is a disposable generated file in the checkout."""
from __future__ import annotations
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / "validation/custom-app-production-triple-id-journaled-restart-e2e-v0.1.0/test_triple_id_journaled_restart_e2e.ps1"
OUTPUT = SOURCE.with_name("ci_derived_authorized_bridge_restart.ps1")
EXPECTED_SOURCE_GIT_BLOB = "6effc4f65d5f93a6e722660301d3c1aea470abde"
EXPECTED_HARD_DISABLED_MAIN = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"

def check_source():
    import subprocess
    actual = subprocess.check_output(["git","hash-object",str(SOURCE)],cwd=ROOT,text=True).strip()
    if actual != EXPECTED_SOURCE_GIT_BLOB:
        raise RuntimeError(f"qualified restart fixture git blob drift {actual}")
    if OUTPUT.exists():
        raise RuntimeError("refusing to overwrite existing checkout output")
    return SOURCE.read_text(encoding="utf-8-sig").replace("\r\n","\n")

def once(s: str, needle: str, repl: str, label: str) -> str:
    n=s.count(needle)
    if n!=1: raise RuntimeError(f"{label}: expected exactly one anchor, got {n}")
    return s.replace(needle,repl,1)

new_block = r"""$script:TJRLabel='third-triple-id-authorized-bridge-restart'
$script:TJRStore=Join-Path $script:TJRRoot ('evidence-bound-'+$script:TJRLabel+'-'+[Guid]::NewGuid().ToString('N'))
$script:TJRTxnNonce=[Guid]::NewGuid().ToString('N')
Assert-Isolated $script:TJRStore 'journal'
$p=$script:PPBValid.result
# Negative cases must fail before creating ANY journal or mutating live app.
$invalid=@{};foreach($k in $TIDArgs.Keys){$invalid[$k]=$TIDArgs[$k]}
$invalid.SessionKey=[byte[]](33..64)
$denied=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $invalid -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce
Assert-TJR (-not[bool]$denied.ok -and -not[bool]$denied.mutation_attempted -and [string]$denied.reason -match 'hmac-preflight-denied') 'incorrect HMAC key reached atomic mutation'
Assert-TJR (-not(Test-Path -LiteralPath $script:TJRStore)) 'invalid HMAC created a journal'
Assert-Original 'bridge-invalid-key-read-only'
$invalid=@{};foreach($k in $TIDArgs.Keys){$invalid[$k]=$TIDArgs[$k]}
$invalid.ExpectedConsumptionId='0'*64
$denied=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $invalid -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce
Assert-TJR (-not[bool]$denied.ok -and -not[bool]$denied.mutation_attempted) 'wrong durable consumption identifier admitted'
Assert-TJR (-not(Test-Path -LiteralPath $script:TJRStore)) 'wrong consumption created a journal'
$denied=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory $script:TJRStore -TransactionNonce 'invalid-nonce'
Assert-TJR (-not[bool]$denied.ok -and -not[bool]$denied.mutation_attempted -and [string]$denied.reason -ceq 'third-id-journal-bridge-nonce-invalid') 'bad transaction nonce admitted'
$denied=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory ([string]$TIDArgs.StoreDirectory) -TransactionNonce $script:TJRTxnNonce
Assert-TJR (-not[bool]$denied.ok -and -not[bool]$denied.mutation_attempted) 'overlap with durable single-use consumption store accepted'
Assert-TJR (-not(Test-Path -LiteralPath $script:TJRStore)) 'negative tests created journal before permit'
Assert-Original 'bridge-negative-tests-read-only'
Write-Host 'TRIPLE_ID_AUTHORIZED_BRIDGE_NEGATIVE_PREMUTATION_PASS bad_hmac=true bad_consumption=true bad_nonce=true overlapping_store=true all_read_only=true'
# Only this bridge can derive a valid caller admission fingerprint, and it
# does so by fresh HMAC verification + persisted single-use readback.
$mutation=Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce
Assert-TJR ([bool]$mutation.ok -and [bool]$mutation.mutation_attempted -and [bool]$mutation.requires_recovery -and [string]$mutation.journal_phase -ceq 'candidate-live') ('verified bridge mutation denied '+[string]$mutation.reason)
Assert-TJR ([bool]$mutation.session_key_not_serialized -and -not[bool]$mutation.production_mutation_authorized -and -not[bool]$mutation.spicetify_apply_authorized) 'bridge result illegally grants authority'
Assert-TJR ([string]$mutation.durable_consumption_envelope_sha256 -cmatch '^[0-9a-f]{64}$') 'durable single-use fingerprint absent'
Assert-TJR ([bool](Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 $mutation.result).ok) 'journal mutation receipt invalid'
Assert-TJRNoAuthority $mutation 'third-id-authorized-bridge'
Assert-TJRNoAuthority $mutation.result 'journal-atomic-result'
Write-Host 'TRIPLE_ID_AUTHORIZED_BRIDGE_REAL_ZIP_SWAP_PASS fresh_hmac=true durable_single_use=true journaling_before_first_move=true no_persisted_key=true zero_apply_authority=true'
"""
def derive() -> tuple[int,str]:
    s=check_source()
    import_anchor=". (Join-Path $root 'validation/custom-app-production-triple-id-prepared-atomic-e2e-v0.1.0/test_triple_id_prepared_atomic_e2e.ps1')"
    imports=import_anchor + "\n. (Join-Path $root 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1')" + "\n. (Join-Path $root 'validation/custom-app-production-triple-id-authorized-journal-bridge-v0.1.0/custom-app-production-triple-id-authorized-journal-bridge.ps1')"
    s=once(s,import_anchor,imports,"qualified bridge imports")
    first="$script:TJRLabel='third-triple-id-restart'"
    last="Assert-TJRNoAuthority $mutation.result 'journal-atomic-result'"
    a=s.index(first);b=s.index(last,a)+len(last)
    if s.count(first)!=1 or s.count(last)!=1 or b-a<500 or b-a>3500:
        raise RuntimeError("qualified atomic test replacement bounds unexpected")
    old=s[a:b]
    if "Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 @TJRMutation" not in old:
        raise RuntimeError("qualified raw atomic mutation anchor unexpectedly absent")
    s=s[:a]+new_block.rstrip()+s[b:]
    summary="TRIPLE_ID_JOURNALED_RESTART_E2E_PASS cases=7"
    if s.count(summary)!=1:raise RuntimeError("existing full recovery proof marker changed")
    s=once(s,summary,summary,"preserve original independent worker pass marker")
    s += "\nWrite-Host 'TRIPLE_ID_AUTHORIZED_BRIDGE_INDEPENDENT_RESTART_E2E_PASS real_zip=true third_hmac_freshly_checked_inside_bridge=true latest_durable_consumption_checked=true journal_before_mutation=true independent_process_restore=true rollback_complete=true replay_denied=true no_real_spicetify=true'\n"
    OUTPUT.write_text(s,encoding="utf-8",newline="\n")
    return len(s), hashlib.sha256(s.encode("utf-8")).hexdigest()
if __name__=="__main__":
    size,digest=derive()
    print(f"TRIPLE_ID_AUTHORIZED_BRIDGE_DERIVED_REAL_ZIP_RESTART size={size} sha256={digest} original_git_blob={EXPECTED_SOURCE_GIT_BLOB}")
