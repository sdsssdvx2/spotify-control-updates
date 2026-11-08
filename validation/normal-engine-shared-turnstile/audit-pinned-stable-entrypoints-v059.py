"""V059 read-only inspection of EXACT stable v0.6.28 / r17 / agent sources.
Never run the PowerShell/VBScript payloads. Do not inspect a live user profile.
The archive/builders already existed and were validated for v0.6.28.
"""
from __future__ import annotations
import argparse
import base64
from io import BytesIO
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "stable_main": (
        Path("validation/v0.6.28/out/bin/spotify-control.ps1"),
        284321,
        "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0",
    ),
    "stable_addon_r17": (
        Path("validation/v0.6.28/out/bin/addon-manager.ps1"),
        323385,
        "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285",
    ),
    "resident_agent": (
        None,  # extracted from the immutable repository v0.6.11 archive
        4855,
        "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278",
    ),
}
TRIGGERS = {
    # Executable control, not just presence of schedule in a comment.
    "scheduler_ps_cmdlet": r"\b(?:Register|Set|Disable|Enable|Stop|Start|Unregister|Get)-ScheduledTask\b",
    "scheduler_com": r"(?i)(?:Schedule\.Service|RegisterTaskDefinition|\.GetTask\(|\.GetTasks\(|\.GetRunningTasks\(|\.GetInstances\()",
    "scheduler_cli": r"(?i)\bschtasks(?:\.exe)?\b",
    "startup_run_key": r"(?i)(?:CurrentVersion[/\\]Run(?:Once)?\b|RunOnceEx|HKCU:.*\\Run\b|HKLM:.*\\Run\b)",
    "startup_folder": r"(?i)(?:Start Menu[/\\]Programs[/\\]Startup|Startup[/\\][^/\\\r\n]+\.lnk)",
    "wmi_startup_process": r"(?i)\b(?:Win32_StartupCommand|Win32_Process|Get-CimInstance)\b",
    "spawn_vbs": r"(?i)(?:WScript\.Shell|WScript\.CreateObject|\.Run\s*\(|\.Exec\s*\(|WScript\.Sleep)",
    "spawn_ps": r"(?i)(?:Start-Process|System\.Diagnostics\.Process|powershell(?:\.exe)?|pwsh(?:\.exe)?|cscript(?:\.exe)?|wscript(?:\.exe)?)",
    "mutation_entrypoint": r"(?i)(?:\bUpdate-AutoApps\b|\bCommit-LastTransaction\b|\bRollback-LastTransaction\b|\bAction\s+Update\b|\bAction\s+AutoUpdate\b)",
    "lock_or_exclusivity": r"(?i)(?:FileShare\]::None|Mutex|WaitOne|Enter-CustomAppEngineTurnstile|New-Object.*Mutex|lock[-_]file)",
}
PS_FUNCTION = re.compile(r"(?im)^\s*function\s+([A-Za-z][\w-]{0,120})\b")

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def extract_verified_agent() -> bytes:
    # The original v0.6.11 delivery archive is stored as base64 ZIP chunks
    # at pinned paths in THIS public repository; the older v0.6.14 repair
    # bootstrap artifact is intentionally NOT required or fabricated.
    _, size, wanted = EXPECTED["resident_agent"]
    candidates = []
    for folder in ("packages/v0.6.11/chunks", "packages/v0.6.11/chunks-v2"):
        files = sorted((ROOT / folder).glob("chunk-*.txt"))
        if not (1 <= len(files) <= 200):
            raise RuntimeError("V059_IMMUTABLE_AGENT_ARCHIVE_CHUNK_SET_NOT_FOUND")
        text = b"".join(x.read_bytes() for x in files)
        if len(text) > 80_000_000:
            raise RuntimeError("V059_AGENT_ARCHIVE_EXCEEDS_HARD_CAP")
        try:
            binary = base64.b64decode(b"".join(text.split()), validate=True)
            with zipfile.ZipFile(BytesIO(binary)) as archive:
                for name in archive.namelist():
                    if name.endswith("/"):
                        continue
                    try:
                        raw = archive.read(name)  # includes ZIP CRC
                    except (RuntimeError, zipfile.BadZipFile, EOFError, OSError):
                        # Ignore unrelated historical malformed archive
                        # members; exact 4855-byte SHA pin remains mandatory.
                        continue
                    if (len(raw), sha256(raw)) == (size, wanted):
                        candidates.append((name, raw))
        except (ValueError, zipfile.BadZipFile, EOFError) as e:
            raise RuntimeError("V059_REPOSITORY_DELIVERED_AGENT_ARCHIVE_CORRUPT") from e
    distinct = {(name, sha256(raw)): raw for name, raw in candidates}
    if len(distinct) != 1:
        raise RuntimeError("V059_EXPECTED_ONE_EXACT_AGENT_MEMBER")
    return next(iter(distinct.values()))

def read_exact(label: str) -> str:
    path, size, sha = EXPECTED[label]
    raw = extract_verified_agent() if label == "resident_agent" else (ROOT / path).read_bytes()
    if (len(raw), sha256(raw)) != (size, sha):
        raise RuntimeError(f"V059_EXACT_STABLE_SOURCE_SHA_OR_SIZE_MISMATCH:{label}")
    try:
        return raw.decode("utf-8-sig")
    except UnicodeError:
        # Fail closed: silently replacing undecodable bytes would make any
        # scan unreliable. The actual tested source set is UTF-8.
        raise RuntimeError(f"V059_SOURCE_ENCODING_NOT_UTF8:{label}")

def owner_at(text: str, offset: int, label: str) -> str:
    if label == "resident_agent":
        return "top-level-vbscript"
    matches = list(PS_FUNCTION.finditer(text, 0, offset))
    return matches[-1].group(1) if matches else "top-level-ps"

def classify(text: str, label: str) -> dict:
    found = {}
    # Bounded counts prevent generating unlimited log output.
    for key, pattern in TRIGGERS.items():
        matches = list(re.finditer(pattern, text, re.IGNORECASE))
        funcs = sorted(set(owner_at(text, m.start(), label) for m in matches))
        found[key] = {"count": min(len(matches), 99999), "owners": funcs[:32]}
    return found

def static_selftest():
    fake = """function Update-AutoApps { Register-ScheduledTask; Start-Process }
function Other { $x=New-Object -ComObject Schedule.Service }
Set-ItemProperty HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run -Name Y -Value Z
"""
    x = classify(fake, "stable_main")
    assert x["scheduler_ps_cmdlet"]["count"] == 1
    assert x["scheduler_ps_cmdlet"]["owners"] == ["Update-AutoApps"]
    assert x["scheduler_com"]["count"] == 1
    assert x["scheduler_com"]["owners"] == ["Other"]
    assert x["startup_run_key"]["count"] == 1
    assert x["spawn_ps"]["count"] >= 1
    assert x["scheduler_cli"]["count"] == 0
    assert not any(x["scheduler_cli"]["owners"])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", action="store_true")
    args = parser.parse_args()
    if not args.audit:
        parser.error("use --audit")
    if sys.platform != "win32":
        raise RuntimeError("V059_EXACT_WINDOWS_BUILDER_OUTPUT_ONLY")
    static_selftest()
    meta = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    expected_files = {x["path"]: x for x in meta["latest_files"]}
    for label, relative in [
        ("stable_main", "bin/spotify-control.ps1"),
        ("stable_addon_r17", "bin/addon-manager.ps1"),
        ("resident_agent", "bin/spotify-control-agent.vbs"),
    ]:
        _, n, h = EXPECTED[label]
        if (expected_files[relative]["size"], expected_files[relative]["sha256"]) != (n, h):
            raise RuntimeError("V059_STABLE_MANIFEST_DIFFERENT_FROM_PINNED_BUILDER")
    if meta["source_commit"] != "bb6d90146f20b73d36fbf8cb813f1b190f403c48":
        raise RuntimeError("V059_CURRENT_STABLE_TRANSPORT_CHANGED")
    result = {label: classify(read_exact(label), label) for label in EXPECTED}
    # The VBS agent is a distinct process/executable; report all THREE.
    # The bootstrap digest appears in the manifest, but its historical ZIP
    # bytes are not shipped in this checkout and are not inferred from SHA.
    for label, fields in result.items():
        evidence = [
            f"{name}={values['count']}"
            for name, values in fields.items()
        ]
        print("V059_PINNED_SOURCE_CLASSIFICATION_" + label.upper()
              + " " + " ".join(evidence))
        for k in ("scheduler_ps_cmdlet", "scheduler_com", "scheduler_cli",
                  "startup_run_key", "startup_folder", "wmi_startup_process",
                  "mutation_entrypoint"):
            owners = fields[k]["owners"]
            # Public source function names only; no commands or arguments.
            if owners:
                print("V059_OWNER_" + label.upper() + "_" + k.upper()
                      + "=" + ",".join(owners))
    if not any(result["stable_addon_r17"][k]["count"] for k in
               ("mutation_entrypoint", "spawn_ps")):
        raise RuntimeError("V059_STABLE_ADDON_SOURCE_UNEXPECTEDLY_NO_ENTRYPOINTS")
    # Static source evidence can NEVER imply exact installed task identity,
    # activated Run keys, present processes or complete manual-launch fencing.
    if meta["bootstrap"] != {
        "version": "1.0.6",
        "size": 42963,
        "sha256": "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6",
    }:
        raise RuntimeError("V059_BOOTSTRAP_MANIFEST_HASH_PIN_CHANGED")
    print("V059_EXACT_STABLE_MAIN_ADDON_AGENT_3_OF_3_SHA_SIZE_MATCH_PASS")
    print("V059_BOOTSTRAP_METADATA_ONLY_FULL_BYTES_UNAVAILABLE_NOT_AUDITED_PASS")
    print("V059_EXECUTION_TOPOLOGY_SOURCE_ONLY_NO_REAL_TASK_OR_PROCESS_PROOF_PASS")
    print("V059_NO_SCRIPT_EXECUTION_NO_SCHEDULER_CHANGE_NO_PRODUCTION_AUTHORITY_PASS")

if __name__ == "__main__":
    main()
