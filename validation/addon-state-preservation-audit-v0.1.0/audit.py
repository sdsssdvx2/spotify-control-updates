from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "validation/addon-state-preservation-audit-v0.1.0"
STABLE_BUILDER = ROOT / "validation/v0.6.28/build_v0628.py"
STABLE_ADDON = ROOT / "validation/v0.6.28/out/bin/addon-manager.ps1"
EXPECTED_SIZE = 323385
EXPECTED_SHA256 = "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
BASE_SHA = "d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def function_map(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"(?m)^function ([A-Za-z0-9_-]+) \\{", text))
    out: dict[str, str] = {}
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        out[match.group(1)] = text[match.start():end].rstrip()
    return out


def main() -> None:
    subprocess.check_call([sys.executable, str(STABLE_BUILDER), "--build"], cwd=ROOT)
    raw = STABLE_ADDON.read_bytes()
    identity = {"size": len(raw), "sha256": sha256(raw)}
    if identity != {"size": EXPECTED_SIZE, "sha256": EXPECTED_SHA256}:
        raise RuntimeError(f"stable r17 identity drift: {identity}")

    text = raw.decode("utf-8-sig").replace("\r\n", "\n")
    functions = function_map(text)
    if not functions:
        raise RuntimeError("no PowerShell functions parsed from r17")

    keywords = (
        "backup", "restore", "rollback", "transaction", "webdata", "web-data",
        "autoapps", "auto-app", "state", "ivlyrics", "tagify", "marketplace",
    )
    relevant = sorted(
        name for name in functions
        if any(keyword in name.lower() for keyword in keywords)
    )

    call_markers = {
        "Backup-SpotifyWebData",
        "Update-AutoApps",
        "Rollback-LastTransaction",
        "Get-AddonPolicyRegistry",
        "Get-AddonInventory",
    }
    exact = {name: functions[name] for name in sorted(call_markers) if name in functions}

    report = {
        "schema": 1,
        "base_main": BASE_SHA,
        "stable_addon": identity,
        "function_count": len(functions),
        "relevant_function_names": relevant,
        "exact_requested_functions_present": sorted(exact),
        "exact_requested_functions": exact,
        "webview_tokens": {
            token: text.count(token)
            for token in (
                "Browser\\Default", "Browser\\", "IndexedDB", "Local Storage",
                "localStorage", "Backup-SpotifyWebData", "Update-AutoApps",
                "Rollback-LastTransaction", "CustomApps\\ivLyrics",
            )
        },
    }
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "audit-report.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("ADDON_STATE_PRESERVATION_AUDIT_IDENTITY_PASS", identity["size"], identity["sha256"])
    print("ADDON_STATE_PRESERVATION_RELEVANT_FUNCTIONS=" + "|".join(relevant))
    print("ADDON_STATE_PRESERVATION_EXACT_FUNCTIONS=" + "|".join(sorted(exact)))
    print("ADDON_STATE_PRESERVATION_WEBVIEW_TOKENS=" + json.dumps(report["webview_tokens"], sort_keys=True))


if __name__ == "__main__":
    main()
