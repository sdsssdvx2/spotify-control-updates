"""V060: Static source provenance and dispatcher/call-site graph (HOLD).

Only exact stable main/addon/agent bytes from previous V059 source attestation.
No live Spotify, no user paths, no execution of any PS1/VBS, no task changes.
This is a *source graph*, not proof of runtime coverage/exclusivity.
"""
from __future__ import annotations
import importlib.util
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py"
spec = importlib.util.spec_from_file_location("v059_readonly_source", MODULE)
if spec is None or spec.loader is None:
    raise RuntimeError("V060_PARENT_SOURCE_READER_MISSING")
v059 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v059)

NAMES = {
    "stable_main": re.compile(
        r"\b(?:Maintain|AgentTick|Update-AutoApps|addon-manager|Install-TasksAndShortcuts|"
        r"Start-Process|Invoke-NativeCapture|powershell\.exe|wscript\.exe|"
        r"AgentEvent|spotify-control-agent|Action\s+)\b", re.I),
    "stable_addon_r17": re.compile(
        r"\b(?:Update-AutoApps|Rollback-LastTransaction|Commit-LastTransaction|"
        r"Update-Addon|Action|Update|AutoUpdate|Get-AddonPolicyRegistry|"
        r"Update-Installed|Get-AddonInventory|Start-Process)\b", re.I),
    "resident_agent": re.compile(
        r"(?:AgentTick|AgentEvent|controlScript|shell\.Run|Win32_Process|Spotify\.exe|"
        r"probeMode|Exit|Quit|WScript\.Sleep)", re.I),
}
INTEREST = {
    "stable_main": [
        re.compile(r"(?i)\bMaintain\b"),
        re.compile(r"(?i)\bAgentTick\b"),
        re.compile(r"(?i)\baddon-manager\b"),
        re.compile(r"(?i)\bInstall-TasksAndShortcuts\b"),
    ],
    "stable_addon_r17": [
        re.compile(r"(?i)\bUpdate-AutoApps\b"),
        re.compile(r"(?i)\bRollback-LastTransaction\b"),
        re.compile(r"(?i)\bCommit-LastTransaction\b"),
    ],
    "resident_agent": [
        re.compile(r"(?i)\bAgentTick\b"),
        re.compile(r"(?i)\bAgentEvent\b"),
    ],
}
SOURCE_FUNCTION = re.compile(r"(?im)^\s*function\s+([A-Za-z][\w-]+)\b")
DISPATCH = re.compile(r"""(?i)\b(?:case|switch|if|elseif|Action|AgentEvent)\b""")
WRITE_TOKENS = re.compile(
    r"(?i)\b(?:Remove-Item|Move-Item|Copy-Item|Rename-Item|Set-Content|"
    r"Set-ItemProperty|Invoke-RestMethod|Start-Process|Invoke-WebRequest|"
    r"spicetify\s+(?:apply|restore|backup)|Invoke-Addon|Update-AutoApps)\b"
)

def line_owner(text: str, offset: int, label: str) -> str:
    if label == "resident_agent":
        return "VBS_TOP_LEVEL"
    funcs = list(SOURCE_FUNCTION.finditer(text, 0, offset))
    return funcs[-1].group(1) if funcs else "PS_TOP_LEVEL"

def mini_context(text: str, phrase: re.Pattern[str], label: str, limit: int = 22) -> list[str]:
    found = []
    offsets = 0
    for ix, line in enumerate(text.splitlines(), 1):
        if not phrase.search(line):
            offsets += len(line) + 1
            continue
        owner = line_owner(text, offsets, label)
        raw = line.strip()
        if raw.startswith(("#", "//", "'")):
            offsets += len(line) + 1
            continue
        if re.search(r"(?i)password|api[_-]?key|bearer|authorization|client_secret", raw):
            offsets += len(line) + 1
            continue
        # Render only exact immutable public release source, short enough
        # for CI review. Do not export any live process command lines.
        found.append(f"{ix}:{owner}:{' '.join(raw.split())[:210]}")
        offsets += len(line) + 1
        if len(found) == limit:
            break
    return found

def source_summary() -> dict:
    if sys.platform != "win32":
        raise RuntimeError("V060_WINDOWS_HOSTED_SOURCE_ONLY")
    source = {key: v059.read_exact(key) for key in (
        "stable_main", "stable_addon_r17", "resident_agent"
    )}
    expected_sha = {key: v059.EXPECTED[key][2] for key in source}
    if expected_sha != {
        "stable_main": "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0",
        "stable_addon_r17": "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285",
        "resident_agent": "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278",
    }:
        raise RuntimeError("V060_STABLE_TRIPLE_PIN_CHANGED")
    counts = {}
    for label, code in source.items():
        hits = []
        for phrase in INTEREST[label]:
            rows = mini_context(code, phrase, label)
            print(f"V060_SOURCE_ANCHOR_{label.upper()}_{phrase.pattern[:18]}_COUNT={len(rows)}")
            for row in rows:
                print(f"V060_PUBLIC_SOURCE_{label.upper()}={row}")
            hits.extend(rows)
        if not hits:
            raise RuntimeError(f"V060_NO_ENTRYPOINT_SOURCE_EVIDENCE_{label.upper()}")
        functions = [m.group(1) for m in SOURCE_FUNCTION.finditer(code)]
        print(f"V060_FUNCTION_COUNT_{label.upper()}={len(functions)}")
        counts[label] = len(hits)
    return {"codes": source, "hit_count": counts}

def emit_targeted_control_flow(code: dict[str, str]) -> None:
    """Bounded immutable-source excerpts for accurate dispatch classification.

    Exact source line ranges were located in the previous SHA-pinned audit.
    These are public source file lines, not process/task/user runtime data.
    """
    zones = {
        "stable_main": [(4250, 4410), (4740, 4810), (4905, 4960)],
        "stable_addon_r17": [(2940, 2990), (3065, 3125), (3825, 3890)],
        "resident_agent": [(125, 147)],
    }
    for label, spans in zones.items():
        lines = code[label].splitlines()
        emitted = 0
        for low, high in spans:
            if len(lines) < low:
                raise RuntimeError(f"V060_PINNED_SOURCE_LINES_TRUNCATED_{label}")
            for line_no in range(low, min(high, len(lines)) + 1):
                raw = lines[line_no - 1].strip()
                if not raw or raw.startswith(("#", "//", "Rem ", "'", "<#")):
                    continue
                if re.search(r"(?i)password|api[_-]?key|bearer|authorization|client_secret", raw):
                    continue
                if raw.lower().startswith(("write-log ", "log-msg ", "log ")):
                    continue
                print(f"V060_PUBLIC_FLOW_{label.upper()}_L{line_no}=" +
                      " ".join(raw.split())[:230])
                emitted += 1
                if emitted > 350:
                    raise RuntimeError("V060_SOURCE_FLOW_OUTPUT_CAP")
        if emitted < 15:
            raise RuntimeError(f"V060_NOT_ENOUGH_SOURCE_FLOW_EVIDENCE_{label}")


def selftest() -> None:
    example = "function Alpha {\n -Action Maintain\n}\nfunction Bravo {\n -Action AgentTick\n}"
    a = mini_context(example, re.compile("Maintain"), "stable_main")
    b = mini_context(example, re.compile("AgentTick"), "stable_main")
    assert len(a) == len(b) == 1
    assert ":Alpha:" in a[0] and ":Bravo:" in b[0]
    assert len(mini_context("# Maintain\nAgentTick", re.compile("Maintain"), "stable_main")) == 0

if __name__ == "__main__":
    selftest()
    info = source_summary()
    emit_targeted_control_flow(info["codes"])
    print("V060_ACTUAL_STABLE_MAIN_ADDON_VBS_TRIPLE_PINNED_DISPATCH_SOURCE_AUDIT_PASS")
    print("V060_SOURCE_CALLSITE_ONLY_NOT_RUNTIME_CUTOVER_OR_LIVE_AUTHORITY_PASS")
