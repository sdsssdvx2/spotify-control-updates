from __future__ import annotations

import hashlib
import importlib.util
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE_PATH = HERE / "build_and_validate.py"
SPEC = importlib.util.spec_from_file_location("runtime_builder_base", BASE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load base runtime builder")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

FORBIDDEN = ("spicetify apply", "spicetify backup", "spicetify restore")
REQUIRED_FUNCTIONS = {
    "Write-LabLog",
    "Test-SafePath",
    "Get-Sha256Lower",
    "Invoke-Native",
    "Get-TreeFingerprint",
    "Suspend-Resident",
    "Restore-Resident",
    "Stop-SpotifyForVariant",
    "Wait-SpotifyReady",
    "Assert-AcceptedRuntimeBaseline",
    "Measure-TransitionCondition",
    "Get-RoleSnapshot",
    "Send-MediaKey",
    "Backup-ProtectedPersistence",
    "Get-MetricSummary",
    "Average-TwoMetricSummaries",
}


def sanitize_runtime(files: dict[str, bytes]) -> None:
    script = files["runtime-validator.ps1"].decode("utf-8-sig")
    removed: list[str] = []
    for name, block in base.extract_function_blocks(script):
        lower = block.lower()
        if any(needle in lower for needle in FORBIDDEN):
            if name in REQUIRED_FUNCTIONS:
                raise RuntimeError(f"Required runtime function contains forbidden mutation phrase: {name}")
            if script.count(block) != 1:
                raise RuntimeError(f"Function block replacement is ambiguous: {name}")
            script = script.replace(block, "", 1)
            removed.append(name)

    lower = script.lower()
    for needle in FORBIDDEN:
        if needle in lower:
            raise RuntimeError(f"Forbidden mutation phrase remains after sanitizer: {needle}")
    if not removed:
        raise RuntimeError("Sanitizer unexpectedly removed no inherited test-only functions")

    files["runtime-validator.ps1"] = script.encode("utf-8-sig")
    files.pop("SHA256SUMS.txt", None)
    sums = [f"{base.sha256(files[name])} *{name}" for name in sorted(files)]
    files["SHA256SUMS.txt"] = ("\n".join(sums) + "\n").encode("ascii")
    print("SANITIZED_TEST_ONLY_FUNCTIONS", ",".join(removed))


def main() -> None:
    files = base.build()
    sanitize_runtime(files)
    base.validate(files)
    base.write_zip(files)
    with zipfile.ZipFile(base.OUT) as zf:
        bad = zf.testzip()
        if bad:
            raise RuntimeError(f"ZIP CRC failure: {bad}")
        if sorted(zf.namelist()) != sorted(files):
            raise RuntimeError("ZIP inventory mismatch")
        for name, data in files.items():
            if zf.read(name) != data:
                raise RuntimeError(f"ZIP byte mismatch: {name}")
    print("PERFORMANCE_OVERLAY_RUNTIME_R2_PACKAGE_PASS", base.OUT.stat().st_size, base.sha256(base.OUT.read_bytes()))
    print("RUNTIME_R2_SCRIPT_PASS", len(files["runtime-validator.ps1"]), base.sha256(files["runtime-validator.ps1"]))


if __name__ == "__main__":
    main()
