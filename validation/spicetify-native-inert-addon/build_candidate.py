"""Build a genuine *hard-disabled* Addon Manager that exposes only the
hosted-Windows-only official-native DPAPI/CAS rollback LAB module as an inert
SelfTest participant. No normal entrypoint, source updater, or FullChain changes.

The qualified V016 Addon remains the exact historical predecessor; every
operation which can mutate a user's installation is byte-identical to it.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "out" / "bin"
PARENT = "f95995d054252b1c2adeeabb2af3bf7944be50b8"
PARENT_BUILDER = "validation/custom-app-spicetify-sealed-enrollment/build_candidate.py"
PARENT_BUILDER_SHA = "27c9cace152401c02448e82767c2f6d557368de8"
PARENT_BYTES = 1573812
PARENT_SHA = "70639fb47ca038d3e745c78cae0c2344c0ab92d2f98bbdee9c0b8766fe675d85"
NORMAL_CONTROL_SHA = "69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99"
NORMAL_CONTROL_BYTES = 284327
MODULE = "validation/custom-app-native-scoped-crash-rollback/native-scoped-crash-rollback.ps1"
MODULE_SHA = "44c432029bf76a2280db7b4794d56b2028880e4c"
TEST = "validation/custom-app-native-scoped-crash-rollback/test_native_scoped_crash_rollback.ps1"
TEST_SHA = "b16bd21be10d1519b36896368297b5041a376233"
BUILDER = "validation/spicetify-native-inert-addon/build_candidate.py"
OLD_HOOK = (
    '    try { Test-CustomAppSpicetifySealedPinSelfTestV016 } '
    'catch { $errors.Add("Spicetify sealed pre-mutation pin and restart verification '
    'self-test failed: $($_.Exception.Message)") }'
)
NEW_HOOK = (
    OLD_HOOK + "\n" +
    '    try { Test-CustomAppScopedLabSelfTestV017 } '
    'catch { $errors.Add("hosted-only native CAS crash rollback '
    'self-test failed: $($_.Exception.Message)") }'
)
EXPECT_NEW_FUNCTIONS = {
    "Get-CustomAppScopedLabShaV017",
    "Assert-CustomAppScopedLabHostedV017",
    "Get-CustomAppScopedLabContextV017",
    "Read-CustomAppScopedLabSnapshotV017",
    "Get-CustomAppScopedLabInventoryV017",
    "Assert-CustomAppScopedLabOutsideUnchangedV017",
    "Save-CustomAppScopedLabSnapshotV017",
    "Get-CustomAppScopedLabJournalV018",
    "Move-CustomAppScopedLabJournalV018",
    "Get-CustomAppScopedLabFirstMutationEntryV018",
    "Invoke-CustomAppScopedLabNativeV017",
    "Restore-CustomAppScopedLabNativeV017",
    "Invoke-CustomAppScopedLabIndependentRecoveryV017",
    "Test-CustomAppScopedLabSelfTestV017",
}

def hash_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()

def pin_git(ref: str, path: str, sha: str) -> None:
    actual = subprocess.check_output(
        ["git", "rev-parse", f"{ref}:{path}"], cwd=ROOT, text=True
    ).strip()
    if actual != sha:
        raise RuntimeError(f"immutable Git blob pin invalid: {path}: {actual}")

def only_replace(text: str, original: str, replacement: str, label: str) -> str:
    n = text.count(original)
    if n != 1:
        raise RuntimeError(f"{label} must have one occurrence, got {n}")
    return text.replace(original, replacement, 1)

def names(text: str) -> list[str]:
    return re.findall(r"(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{", text)

def function_body(text: str, name: str) -> str:
    m = re.search(r"(?im)^[ \t]*function\s+" + re.escape(name) + r"\s*\{", text)
    if not m:
        raise RuntimeError("missing function: " + name)
    after = re.search(r"(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{", text[m.end():])
    end = m.end() + after.start() if after else len(text)
    return text[m.start():end]

def main() -> None:
    for ref, path, sha in (
        (PARENT, PARENT_BUILDER, PARENT_BUILDER_SHA),
        ("HEAD", MODULE, MODULE_SHA),
        ("HEAD", TEST, TEST_SHA),
    ):
        pin_git(ref, path, sha)

    subprocess.check_call(["python", str(ROOT / PARENT_BUILDER)], cwd=ROOT)
    parent_dir = ROOT / "validation/custom-app-spicetify-sealed-enrollment/out/bin"
    files = {
        name: (parent_dir / name).read_bytes()
        for name in ("addon-manager.ps1", "spotify-control.ps1",
                     "Collect-Marketplace-Records.ps1", "LevelDbReadOnly.cs")
    }
    prior = files["addon-manager.ps1"]
    if (len(prior), hash_bytes(prior)) != (PARENT_BYTES, PARENT_SHA):
        raise RuntimeError("qualified V016 Addon byte-identical parent drift")
    if (len(files["spotify-control.ps1"]), hash_bytes(files["spotify-control.ps1"])) != (
        NORMAL_CONTROL_BYTES, NORMAL_CONTROL_SHA
    ):
        raise RuntimeError("original Spotify Control was changed")
    bom = b"\xef\xbb\xbf" if prior.startswith(b"\xef\xbb\xbf") else b""
    original = prior[len(bom):].decode("utf-8").replace("\r\n", "\n")
    module = (ROOT / MODULE).read_text("utf-8-sig").replace("\r\n", "\n").strip()
    current_names = names(original)
    module_names = names(module)
    if set(module_names) != EXPECT_NEW_FUNCTIONS or len(module_names) != len(EXPECT_NEW_FUNCTIONS):
        raise RuntimeError("V018 source exports unexpected or duplicate functions")
    if set(current_names) & set(module_names):
        raise RuntimeError("V018 collides with a pre-existing normal Addon function")

    for marker in (
        "[Environment]::OSVersion.Platform",
        "$env:GITHUB_ACTIONS -cne 'true'",
        "$env:RUNNER_OS -cne 'Windows'",
        "$env:RUNNER_ENVIRONMENT -cne 'github-hosted'",
        "SPICETIFY_CONFIG",
        "SPICETIFY_STATE",
        "Read-CustomAppSpicetifySealedPinV016",
        "Get-CustomAppSealedStartupRecoveryAssessmentV013",
        "Get-CustomAppScopedLabJournalV018",
        "Append-CustomAppProductionCrashJournalPhaseV010",
        "NATIVE_SCOPED_V018_APPEND_ONLY_CAS_PHASE_BEFORE_NATIVE_EFFECT_PASS",
        "NATIVE_SCOPED_V018_CAS_ROLLBACK_COMPLETE_AFTER_EXACT_BYTES_PASS",
        "production_execution_authorized=$false",
        "production_mutation_authorized=$false",
    ):
        if marker not in module:
            raise RuntimeError("mandatory security contract missing: " + marker)
    for prohibited in (
        "$script:CustomAppProductionPipelineEnabled = $true",
        "Open-CustomAppUserTxnStoreV010 -Name",
        "Invoke-CustomAppProductionFullChainV010",
        "Update-AutoApps",
        "Commit-LastTransaction",
        "Rollback-LastTransaction",
    ):
        if prohibited in module:
            raise RuntimeError("V018 module adds a normal/production dispatcher: " + prohibited)
    # The module intentionally has a hosted test-only vendor execution primitive.
    # The entire guard, not a mutable "test mode" boolean, is mandatory.
    if ("function Assert-CustomAppScopedLabHostedV017" not in module or
        "native-scoped-lab-hosted-windows-only-not-production" not in module or
        "--bypass-admin -n -a refresh" not in module):
        raise RuntimeError("hosted-only native executable guard missing")

    payload = module + "\n\n"
    generated = only_replace(original, "function Test-Due {",
                             payload + "function Test-Due {", "module insertion")
    generated = only_replace(generated, OLD_HOOK, NEW_HOOK, "SelfTest-only hook")
    for name in (
        "Update-AutoApps", "Commit-LastTransaction", "Rollback-LastTransaction",
        "Invoke-CustomAppProductionFullChainV010",
    ):
        if function_body(generated, name) != function_body(original, name):
            raise RuntimeError("legacy normal mutation entrypoint bytes changed: " + name)
    if ("Custom App production full-chain execution is intentionally unavailable in integration-only candidate."
            not in function_body(generated, "Invoke-CustomAppProductionFullChainV010")):
        raise RuntimeError("FullChain unexpectedly enabled")
    if (generated.count("$script:CustomAppProductionPipelineEnabled = $true") !=
            original.count("$script:CustomAppProductionPipelineEnabled = $true")):
        raise RuntimeError("new production mutation authority detected")
    old_again = only_replace(generated, NEW_HOOK, OLD_HOOK, "inverse SelfTest-only hook")
    old_again = only_replace(old_again, payload, "", "inverse exact module")
    if old_again != original:
        raise RuntimeError("candidate not byte-exact reversible to V016")
    result = bom + generated.replace("\n", "\r\n").encode("utf-8")
    files["addon-manager.ps1"] = result

    OUTPUT.mkdir(parents=True, exist_ok=True)
    for filename, data in files.items():
        (OUTPUT / filename).write_bytes(data)
    report = {
        "schema": 1,
        "parent_head": PARENT,
        "parent_addon_sha256": PARENT_SHA,
        "generated_addon_sha256": hash_bytes(result),
        "generated_addon_bytes": len(result),
        "spotify_control_sha256": hash_bytes(files["spotify-control.ps1"]),
        "fullchain_hard_disabled": True,
        "normal_update_commit_rollback_function_bodies_unchanged": True,
        "source_restores_exact_v016_byte_for_byte": True,
        "no_production_user_spotify_mutation": True,
        "new_test_only_native_appears_in_real_addon": True,
        "hosted_windows_runner_guard": True,
        "test_only_official_native_call_guarded": True,
        "native_rollback_cas_journal_integrated": True,
        "previous_dpapi_provenance_preserved": True,
        "new_normal_update_entrypoints": False,
        "release_or_main_modified": False,
    }
    (HERE / "candidate-validation.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("SPICETIFY_V018_INERT_ACTUAL_ADDON_BUILT",
          len(result), hash_bytes(result),
          "prior_v016_exact_inverse=true native_hosted_only=true fullchain_hard_disabled=true")

if __name__ == "__main__":
    main()
