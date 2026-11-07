"""V025: single targeted change on top of the already-qualified V024
genuine HMAC whole-app, real official Spicetify and central CAS fixture.

Keep all historical BLOB-pinned HMAC and real vendor portions unchanged.
Only replace the in-memory pending -> apply-verified append with a fresh
CurrentUser-DPAPI sealed, keyless independent Windows worker that NEVER calls
Spicetify again. Generated file remains disposable, not committed.
"""
from pathlib import Path
import subprocess
import hashlib

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/"validation/custom-app-real-native-journaled-forward-commit/derive_real_native_journal_test.py"
MODULE=HERE/"real-native-pending-recovery.ps1"
WORKER=HERE/"resume-pending-fresh-process.ps1"
GENERATED=ROOT/"validation/custom-app-production-triple-id-journaled-forward-commit-v0.1.0/ci_real_native_journaled_forward_generated.ps1"
PINS={
    PARENT:"5ca7707755a499157dd0eb2560dbbb740456cc81",
    MODULE:"a0976d85164c215a6ccb45226a059df0f771858b",
    WORKER:"cf727e75c383aa3b276d3d9689e5e9f4748d8b01",
}
PARENT_GENERATED_SHA256="51c745566ee0b5ac55b32746b844a9cdaca3e6fdd8a0ac759715d6340acc4784"

def unique(s,a,b,label):
    c=s.count(a)
    if c!=1:raise RuntimeError(f"{label}: expected one pinned source occurrence, saw {c}")
    return s.replace(a,b,1)

def main():
    if GENERATED.exists():raise RuntimeError("generated native fixture must not already exist")
    for f,pin in PINS.items():
        sha=subprocess.check_output(["git","hash-object",str(f)],cwd=ROOT,text=True).strip()
        if sha!=pin:raise RuntimeError(f"V025 qualified pin drift: {f.name} {sha}")
    subprocess.check_call(["python",str(PARENT)],cwd=ROOT)
    original=GENERATED.read_text(encoding="utf-8")
    actual=hashlib.sha256(original.encode("utf-8")).hexdigest()
    if actual!=PARENT_GENERATED_SHA256:
        raise RuntimeError(f"V024 qualified generated source changed: {actual}")
    source=unique(original,
        ". (Join-Path $root 'validation/custom-app-real-native-journaled-forward-commit/native-journal-receipt.ps1')",
        ". (Join-Path $root 'validation/custom-app-real-native-journaled-forward-commit/native-journal-receipt.ps1')\n"
        ". (Join-Path $root 'validation/custom-app-real-native-pending-recovery-v0.1.0/real-native-pending-recovery.ps1')",
        "import independent native pending DPAPI functions")
    old="""$verified=Append-JF 'apply-returned-success-pending-verification' 'apply-verified' $finalFp $durable.fingerprint
Assert-JF ([string]$verified.entry.apply_result_fingerprint -ceq [string]$durable.fingerprint) 'journal real-native verification not bound'"""
    new=r"""# At this point the genuine official vendor succeeded, but the central
# journal still says pending. Persist a protected proof BEFORE the original
# updater dies, and let a DIFFERENT process finish the CAS without its HMAC
# session key, issuer, original permit or in-memory Spicetify execution result.
$sealed=Save-CustomAppRealNativePendingSealV025 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx -ReceiptFingerprint $durable.fingerprint
Assert-JF ([bool]$sealed.ok -and [string]$sealed.pending_journal_sha256 -ceq [string]$pending.entry.entry_sha256) 'native DPAPI pending receipt was not durably tied to CAS rev6'
$badId=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId ('0'*64)
Assert-JF (-not[bool]$badId.ok) 'different journal ID unexpectedly opened the DPAPI pending proof'
$sealOriginal=[IO.File]::ReadAllBytes([string]$sealed.path)
try{
    $changed=New-Object byte[] $sealOriginal.Length
    [Array]::Copy($sealOriginal,$changed,$sealOriginal.Length)
    $changed[4]=$changed[4] -bxor 1
    [IO.File]::WriteAllBytes([string]$sealed.path,$changed)
    $tampered=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx
    Assert-JF (-not[bool]$tampered.ok) 'tampered DPAPI envelope header was accepted'
}finally{[IO.File]::WriteAllBytes([string]$sealed.path,$sealOriginal)}
$xpui=[string]$durable.receipt.private_target_path
$targetOriginal=[IO.File]::ReadAllBytes($xpui)
try{
    [IO.File]::AppendAllText($xpui,'V025_PENDING_XPUI_POST_VENDOR_TAMPER')
    $tampered=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx
    Assert-JF (-not[bool]$tampered.ok) 'XPUI changed after native vendor but before journal verification'
}finally{[IO.File]::WriteAllBytes($xpui,$targetOriginal)}
Assert-JF ([string](Read-JF 'apply-returned-success-pending-verification').entry.entry_sha256 -ceq [string]$pending.entry.entry_sha256) 'negative tests mutated the CAS journal'
Write-Host 'REAL_NATIVE_V025_TAMPERED_SEAL_WRONG_ID_AND_XPUI_DRIFT_DENIED_PASS'
$worker=Join-Path $root 'validation/custom-app-real-native-pending-recovery-v0.1.0/resume-pending-fresh-process.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx
Assert-JF ($LASTEXITCODE -eq 0) 'different user-session-process did not complete the independently authenticated real native pending CAS'
$verified=Read-JF 'apply-verified'
Assert-JF ([string]$verified.entry.apply_result_fingerprint -ceq [string]$durable.fingerprint -and
    [int64]$verified.revision -eq 7 -and
    [string]$verified.entry.previous_entry_sha256 -ceq [string]$pending.entry.entry_sha256) 'keyless pending resume did not preserve exact journal CAS and real XPUI hash binding'
$replay=Read-CustomAppRealNativePendingSealV025 -AllowedRoot $script:JFAllowed -JournalStoreDirectory $script:JFStore -JournalTransactionId $script:JFTx
Assert-JF (-not[bool]$replay.ok -and [string](Read-JF 'apply-verified').entry.entry_sha256 -ceq [string]$verified.entry.entry_sha256) 'DPAPI pending proof replay mutated terminal verified state'
Write-Host 'REAL_NATIVE_V025_DPAPI_COLD_RESUME_OFFICIAL_VENDOR_ONCE_PASS'
"""
    source=unique(source,old,new,"replace original parent-only in-memory CAS with keyless worker")
    if source.count("REAL_NATIVE_V025_DPAPI_COLD_RESUME_OFFICIAL_VENDOR_ONCE_PASS")!=1:
        raise RuntimeError("DPAPI recovery result marker count drift")
    if source.count("REAL_NATIVE_V024_OFFICIAL_SCOPED_FORWARD_COMMITTED_CLEAN_PASS")!=1:
        raise RuntimeError("qualified original successful terminal receipt missing")
    GENERATED.write_text(source,encoding="utf-8",newline="\n")
    print("REAL_NATIVE_V025_DERIVED_KEYLESS_CRASH_RESUME_PASS",
          len(source.encode("utf-8")),hashlib.sha256(source.encode("utf-8")).hexdigest())

if __name__=="__main__":
    main()
