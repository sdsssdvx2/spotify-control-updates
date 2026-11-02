from __future__ import annotations

import argparse
import pathlib
import re
import sys

BASE_HEAD = "c3e1f960447ba84d2410af9c37a22a384f2a5436"
BASE_BLOB = "5fec613c460619da5dbfe88fca5c7334e9e93f76"
PATCH_MANAGED_BY = "custom-app-production-recovery-restore-executor-monotonic-time-v1"
FUNCTION_NAME = "Invoke-CustomAppProductionRecoveryRestoreExecutorV010"

PRE_INITIAL = r'''        $clock0=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null -eq $clock0 -or -not [bool]$clock0.ok){return & $deny ('recovery-restore-executor-monotonic-clock-read-denied:'+[string]$clock0.reason)}
        if(([string]$clock0.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'recovery-restore-executor-monotonic-clock-transaction-mismatch'}
        $clockAt0=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse([string]$clock0.entry.recorded_at,[ref]$clockAt0)){return & $deny 'recovery-restore-executor-monotonic-clock-time-invalid'}
        if($clockAt0 -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){return & $deny 'recovery-restore-executor-monotonic-clock-future-beyond-policy'}
        if($Now -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){return & $deny 'recovery-restore-executor-monotonic-caller-future-beyond-policy'}
        $effectiveNow=$Now
        if($effectiveNow -lt $clockAt0){$effectiveNow=$clockAt0}
'''

POST_INITIAL = r'''        $clock1=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null -eq $clock1 -or -not [bool]$clock1.ok){return & $deny ('recovery-restore-executor-monotonic-clock-reread-denied:'+[string]$clock1.reason)}
        if(([string]$clock1.transaction_id).Trim().ToLowerInvariant() -cne ([string]$i.transaction_id).Trim().ToLowerInvariant()){return & $deny 'recovery-restore-executor-monotonic-clock-reread-transaction-mismatch'}
        if([int64]$clock1.revision -ne [int64]$i.journal_revision -or ([string]$clock1.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$i.journal_entry_sha256).Trim().ToLowerInvariant()){return & $deny 'recovery-restore-executor-monotonic-journal-head-changed-before-barrier'}
        $clockAt1=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse([string]$clock1.entry.recorded_at,[ref]$clockAt1)){return & $deny 'recovery-restore-executor-monotonic-clock-reread-time-invalid'}
        if($clockAt1 -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){return & $deny 'recovery-restore-executor-monotonic-clock-reread-future-beyond-policy'}
        if($effectiveNow -lt $clockAt1){$effectiveNow=$clockAt1}
'''


def find_function_span(text: str) -> tuple[int, int]:
    marker = f"function {FUNCTION_NAME} {{"
    start = text.find(marker)
    if start < 0:
        raise RuntimeError("target function not found")
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError("target function opening brace missing")
    depth = 0
    quote = None
    escape = False
    i = brace
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escape:
                escape = False
            elif ch == "`":
                escape = True
            elif ch == quote:
                quote = None
        else:
            if ch in ("'", '"'):
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return start, i + 1
        i += 1
    raise RuntimeError("target function closing brace missing")


def patch_text(text: str) -> str:
    start, end = find_function_span(text)
    fn = text[start:end]

    initial_needle = "    try{\n        $initial=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010"
    if fn.count(initial_needle) != 1:
        raise RuntimeError(f"initial admission anchor count drift: {fn.count(initial_needle)}")
    fn = fn.replace(
        initial_needle,
        "    try{\n" + PRE_INITIAL + "        $initial=Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010",
        1,
    )

    receipt_needle = "        $i=$initial.receipt\n"
    if fn.count(receipt_needle) != 1:
        raise RuntimeError(f"initial receipt anchor count drift: {fn.count(receipt_needle)}")
    fn = fn.replace(receipt_needle, receipt_needle + POST_INITIAL, 1)

    direct_count = len(re.findall(r"-Now\s+\$Now\b", fn))
    add_ms_count = fn.count("$Now.AddMilliseconds(")
    if direct_count < 1:
        raise RuntimeError("no direct -Now $Now calls found in target function")
    if add_ms_count < 1:
        raise RuntimeError("no $Now.AddMilliseconds calls found in target function")
    fn = re.sub(r"-Now\s+\$Now\b", "-Now $effectiveNow", fn)
    fn = fn.replace("$Now.AddMilliseconds(", "$effectiveNow.AddMilliseconds(")

    if re.search(r"-Now\s+\$Now\b", fn) or "$Now.AddMilliseconds(" in fn:
        raise RuntimeError("unpatched recovery time use remains")
    for marker in (
        "recovery-restore-executor-monotonic-clock-read-denied",
        "recovery-restore-executor-monotonic-journal-head-changed-before-barrier",
        "$effectiveNow.AddMilliseconds(1)",
    ):
        if marker not in fn:
            raise RuntimeError(f"required patched marker missing: {marker}")

    header = (
        f"$CustomAppProductionRecoveryRestoreExecutorMonotonicPatchManagedBy = '{PATCH_MANAGED_BY}'\n"
        f"$CustomAppProductionRecoveryRestoreExecutorMonotonicPatchQualifiedBaseHead = '{BASE_HEAD}'\n"
        f"$CustomAppProductionRecoveryRestoreExecutorMonotonicPatchQualifiedBaseBlob = '{BASE_BLOB}'\n"
    )
    return header + text[:start] + fn + text[end:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    source = pathlib.Path(args.source)
    output = pathlib.Path(args.output)
    raw = source.read_text(encoding="utf-8")
    patched = patch_text(raw)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(patched, encoding="utf-8", newline="\n")
    print("RECOVERY_RESTORE_EXECUTOR_MONOTONIC_PATCH_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
