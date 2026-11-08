"""Opt-in development source staging: fix stale Spotify-exit discovery in the
EXISTING stable AgentTick; do not invent a second updater or deploy to users.

The canonical v0.6.28/r17 sources and v0.1.1 VBS come from existing pinned
repository builders. This script merely adds one narrow event-triggered check
to the actual stable main function, preserving the full Addon Manager source.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import runpy

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STAGED = HERE / "out" / "bin"
EXPECTED_MAIN = (284321, "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0")
EXPECTED_ADDON = (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285")
EXPECTED_AGENT = (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278")

def fingerprint(data: bytes) -> tuple[int, str]:
    return len(data), hashlib.sha256(data).hexdigest()

def function_span(text: str, name: str) -> tuple[int, int]:
    match = re.search(r"(?im)^[ \t]*function[ \t]+" + re.escape(name) + r"[ \t]*\{", text)
    if not match:
        raise RuntimeError("STABLE_AGENTTICK_FUNCTION_NOT_FOUND")
    after = re.search(r"(?im)^[ \t]*function[ \t]+[A-Za-z][A-Za-z0-9_-]*[ \t]*\{", text[match.end():])
    return match.start(), match.end() + after.start() if after else len(text)

def source_from_stable() -> tuple[bytes, bytes, bytes]:
    # Existing v0.6.28 production builder exactly validates its own immutable
    # source ancestry and the r17 registry, rather than trusting a new parser.
    stable_builder = runpy.run_path(str(ROOT / "validation/v0.6.28/build_v0628.py"))
    stable_builder["build"]()
    base = ROOT / "validation/v0.6.28/out/bin"
    main = (base / "spotify-control.ps1").read_bytes()
    addon = (base / "addon-manager.ps1").read_bytes()
    if fingerprint(main) != EXPECTED_MAIN or fingerprint(addon) != EXPECTED_ADDON:
        raise RuntimeError("STABLE_PARENT_BYTES_NOT_CANONICAL")
    observer = runpy.run_path(str(ROOT / "validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py"))
    agent = observer["extract_verified_agent"]()
    if fingerprint(agent) != EXPECTED_AGENT:
        raise RuntimeError("CANONICAL_RESIDENT_AGENT_SOURCE_DRIFT")
    return main, addon, agent

def extract_actual_exit_event(agent: bytes) -> str:
    source = agent.decode("utf-8-sig")
    # Read the exact runtime VBS invocation, not comments/previous reports.
    calls = re.findall(r'(?im)^[ \t]*(?:Call[ \t]+)?RunTick[ \t]*(?:\([ \t]*)?"([A-Za-z0-9_-]+)"', source)
    exit_calls = sorted({x for x in calls if "exit" in x.casefold()})
    if len(exit_calls) != 1:
        raise RuntimeError("RESIDENT_VBS_EXIT_EVENT_NOT_EXACTLY_ONE:" + ",".join(sorted(set(calls))))
    return exit_calls[0]

def construct() -> dict:
    stable_main, stable_addon, agent = source_from_stable()
    event = extract_actual_exit_event(agent)
    bom = b"\xef\xbb\xbf" if stable_main.startswith(b"\xef\xbb\xbf") else b""
    main = stable_main[len(bom):].decode("utf-8")
    newline = "\r\n" if "\r\n" in main else "\n"
    start, end = function_span(main, "Invoke-ResidentAgentTick")
    original = main[start:end]
    marker = "$mutationRan = $false"
    if original.count(marker) != 1:
        raise RuntimeError("AGENTTICK_STAGE_MARKER_CHANGED")
    p = original.index(marker) + len(marker)
    anchor = original.find("if ($running) {", p)
    if anchor < 0 or anchor - p > 96 or original[p:anchor].strip():
        raise RuntimeError("AGENTTICK_RUNNING_BRANCH_NOT_ADJACENT")
    indentation = re.search(r"(?m)^([ \t]*)if \(\$running\) \{", original[p:]).group(1)
    # The real resident VBS emits this exact event ONCE per Spotify exit
    # transition. Ordinary closed ticks may also recheck an unhealthy or
    # ambiguous pending state only when the original 12-hour discovery
    # interval is due; they are NOT allowed to bypass the existing mutation
    # authority/health/ambiguity gate.
    insert_lines = [
        " # Trigger a fresh read-only check when Spotify actually closes.",
        " # Without this, an update immediately after a 12-hour scan could",
        " # leave a missing Spicetify patch unnoticed until the next scan.",
        " $exitRefreshDone = $false",
        f' if (-not $running -and $EventName -ceq "{event}") {{',
        "     [void](Invoke-MaintenanceCheckPhase -State $State)",
        "     $State = Ensure-StateShape (Load-State)",
        "     $checkRan = $true",
        "     $exitRefreshDone = $true",
        " }",
        " # Recover from stale unhealthy/ambiguous discovery while closed.",
        " # Keep the existing 12-hour cadence; do not make unchecked network",
        " # requests on every resident tick after a failed or partial check.",
        " # This ONLY performs discovery/state bookkeeping; the existing",
        " # armed/healthy/unambiguous gate below still owns all mutations.",
        " if (-not $running -and -not $exitRefreshDone -and $checkDue -and",
        "     [bool]$State.pending_maintenance -and",
        "     ($State.maintenance_check_healthy -eq $false -or",
        "      [int]$State.pending_addon_auto_ambiguous -gt 0)) {",
        "     # Persist retry admission BEFORE remote checks. If discovery",
        "     # throws early, subsequent ticks cannot hammer free endpoints.",
        '     $State.last_check_only_utc = [DateTimeOffset]::UtcNow.ToString("o")',
        "     Save-State (Ensure-StateShape $State)",
        "     [void](Invoke-MaintenanceCheckPhase -State $State)",
        "     $State = Ensure-StateShape (Load-State)",
        "     $checkRan = $true",
        "     $exitRefreshDone = $true",
        " }",
    ]
    insertion = newline.join(indentation + line[1:] for line in insert_lines) + newline + indentation
    changed = original[:anchor] + insertion + original[anchor:]
    # Avoid making two network/discovery checks on a due-and-exit tick.
    old_guard = "} elseif ($checkDue) {"
    if changed.count(old_guard) != 1:
        raise RuntimeError("AGENTTICK_CLOSED_DISCOVERY_GUARD_DRIFT")
    changed = changed.replace(old_guard, "} elseif ($checkDue -and -not $exitRefreshDone) {", 1)
    if changed.replace(insertion, "", 1).replace(
        "} elseif ($checkDue -and -not $exitRefreshDone) {", old_guard, 1
    ) != original:
        raise RuntimeError("AGENTTICK_EXACT_INVERSE_REPLAY_FAILED")
    candidate = bom + (main[:start] + changed + main[end:]).encode("utf-8")
    if candidate == stable_main:
        raise RuntimeError("EVENT_FAST_PATH_DID_NOT_CHANGE_MAIN")
    STAGED.mkdir(parents=True, exist_ok=True)
    (STAGED / "spotify-control.ps1").write_bytes(candidate)
    (STAGED / "addon-manager.ps1").write_bytes(stable_addon)
    test = HERE / "out" / "isolated"
    test.mkdir(parents=True, exist_ok=True)
    (test / "actual-agenttick-function.ps1").write_text(changed, encoding="utf-8", newline="\n")
    meta = {
        "schema": 1,
        "mode": "HOSTED_HOLD_NO_RELEASE",
        "base_main_sha256": EXPECTED_MAIN[1],
        "base_addon_sha256": EXPECTED_ADDON[1],
        "base_resident_vbs_sha256": EXPECTED_AGENT[1],
        "candidate_main_sha256": fingerprint(candidate)[1],
        "candidate_main_bytes": len(candidate),
        "candidate_addon_sha256": fingerprint(stable_addon)[1],
        "agent_vbs_exit_event": event,
        "changed_existing_function_count": 1,
        "new_resident_processes": 0,
        "new_external_dependencies": 0,
        "production_mutation_authorized": False,
        "user_profile_access": False,
        "user_settings_changed": False,
    }
    (HERE / "out" / "source-attestation.json").write_text(json.dumps(meta,indent=2,sort_keys=True)+"\n", encoding="utf-8")
    print("REAL_STABLE_MAIN_SINGLE_FUNCTION_EXIT_DISCOVERY_CANDIDATE_STAGED")
    print("STABLE_R17_BYTE_IDENTICAL_AND_VBS_EVENT_GROUNDED")
    return meta

if __name__ == "__main__":
    construct()
